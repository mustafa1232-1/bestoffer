/* eslint-disable no-console */
import "dotenv/config";

import {
  assertStatus,
  buildPhone,
  buildRunTag,
  createActor,
  readId,
  request,
} from "./e2eTestUtils.js";

const DEFAULT_BASE_URL = "https://bestoffer-production.up.railway.app";

function toInt(value, fallback, { min = 1, max = 500 } = {}) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed)) return fallback;
  if (parsed < min || parsed > max) return fallback;
  return parsed;
}

function parseArgs() {
  const args = process.argv.slice(2);
  const out = {
    baseUrl: String(process.env.LOAD_BASE_URL || DEFAULT_BASE_URL).trim().replace(/\/+$/, ""),
    runTag: process.env.LOAD_RUN_TAG?.trim() || buildRunTag("load"),
    customerPool: toInt(process.env.LOAD_CUSTOMER_POOL, 160, { min: 5, max: 300 }),
  };
  for (let i = 0; i < args.length; i += 1) {
    const key = String(args[i] || "").trim();
    const next = String(args[i + 1] || "").trim();
    if (key === "--base-url" && next) {
      out.baseUrl = next.replace(/\/+$/, "");
      i += 1;
      continue;
    }
    if (key === "--run-tag" && next) {
      out.runTag = next;
      i += 1;
      continue;
    }
    if (key === "--customer-pool" && next) {
      out.customerPool = toInt(next, out.customerPool, { min: 5, max: 300 });
      i += 1;
    }
  }
  return out;
}

async function registerCustomer(baseUrl, runTag, index) {
  const actor = createActor(`load-customer-${index}`, runTag, "load-fixtures/1");
  const phone = buildPhone("079", Number(String(Date.now() + index).slice(-8)));
  const response = await request(baseUrl, actor, "POST", "/api/auth/register", {
    fullName: `Load Customer ${runTag} ${index}`,
    phone,
    pin: "1234",
    block: "A1",
    buildingNumber: `A1${String((index % 12) + 1).padStart(2, "0")}`,
    apartment: `${(index % 9) + 1}${String((index % 12) + 1).padStart(2, "0")}`,
    analyticsConsentAccepted: true,
    analyticsConsentVersion: "analytics_v1",
  });
  assertStatus(response, 201, `register customer ${index}`);
  actor.token = String(response.data?.token || "");
  return {
    actor,
    token: actor.token,
    userId: readId(response.data?.user),
    phone,
    deviceId: actor.deviceId,
    platform: actor.platform,
    appVersion: actor.appVersion,
    model: actor.model,
    userAgent: actor.userAgent,
  };
}

async function registerOwnerMerchant(baseUrl, runTag, suffix, merchantPayload) {
  const actor = createActor(`load-owner-${suffix}`, runTag, "load-fixtures/1");
  const phone = buildPhone("078", Number(String(Date.now() + suffix.length).slice(-8)));
  const response = await request(baseUrl, actor, "POST", "/api/owner/register", {
    phone,
    pin: "1234",
    block: "A2",
    buildingNumber: "A201",
    apartment: "102",
    merchantName: merchantPayload.name,
    merchantType: merchantPayload.type,
    merchantActivityType: merchantPayload.activityType,
    merchantDiscoverySubcategory: merchantPayload.discoverySubcategory,
    merchantDescription: merchantPayload.description,
    merchantTagline: merchantPayload.tagline,
    merchantWorkingHours: "09:00-23:00",
    merchantServiceAreaNote: merchantPayload.serviceAreaNote,
    merchantSupportsChat: merchantPayload.supportsChat === true,
    merchantSupportsAttachments: merchantPayload.supportsAttachments === true,
    merchantSupportsPharmacyWorkflow:
      merchantPayload.supportsPharmacyWorkflow === true,
    analyticsConsentAccepted: true,
    analyticsConsentVersion: "analytics_v1",
  });
  assertStatus(response, 201, `owner register ${suffix}`);
  actor.token = String(response.data?.token || "");
  return {
    actor,
    phone,
    ownerUserId: readId(response.data?.user),
    merchantId: readId(response.data?.merchant),
  };
}

async function approveMerchantFlow(baseUrl, admin, ownerActor, merchantId) {
  const approveMerchant = await request(
    baseUrl,
    admin,
    "PATCH",
    `/api/admin/merchants/${merchantId}/approve`,
    {
      commissionType: "percentage",
      commissionValue: 10,
      serviceFeeType: "fixed",
      serviceFeeValue: 250,
      deliveryFeeMode: "dynamic",
      appDeliveryFeeValue: 1000,
      storeDeliveryFeeValue: 0,
      appDeliveryEnabled: true,
      merchantDeliveryEnabled: true,
      settlementCycle: "weekly",
      distributionPolicy: "commission_service_delivery",
      effectiveFrom: new Date().toISOString(),
    }
  );
  assertStatus(approveMerchant, 204, `approve merchant ${merchantId}`);

  const acceptFinancialTerms = await request(
    baseUrl,
    ownerActor,
    "POST",
    "/api/owner/merchant/financial-terms/accept"
  );
  assertStatus(
    acceptFinancialTerms,
    200,
    `owner accept financial terms for merchant ${merchantId}`
  );
}

async function createCategory(baseUrl, ownerActor, name) {
  const response = await request(baseUrl, ownerActor, "POST", "/api/owner/categories", {
    name,
    sortOrder: 1,
  });
  assertStatus(response, 201, `create category ${name}`);
  return readId(response.data);
}

async function createProduct(baseUrl, ownerActor, payload) {
  const response = await request(baseUrl, ownerActor, "POST", "/api/owner/products", payload);
  assertStatus(response, 201, `create product ${payload.name}`);
  return readId(response.data);
}

async function createSeedPost(baseUrl, customerActor, caption) {
  const response = await request(baseUrl, customerActor, "POST", "/api/feed/posts", {
    caption,
    postKind: "text",
  });
  assertStatus(response, 201, `create seed post ${caption}`);
  return readId(response.data?.post);
}

async function cleanupViaAdmin(baseUrl, admin, runTag) {
  const response = await request(
    baseUrl,
    admin,
    "POST",
    "/api/admin/ops/test-artifacts/cleanup",
    { runTag }
  );
  assertStatus(response, 200, `cleanup pre-existing artifacts ${runTag}`);
}

async function main() {
  const cfg = parseArgs();
  const admin = createActor("load-admin", cfg.runTag, "load-fixtures/1");
  const adminLogin = await request(cfg.baseUrl, admin, "POST", "/api/auth/login", {
    phone: process.env.SUPER_ADMIN_PHONE,
    pin: process.env.SUPER_ADMIN_PIN,
  });
  assertStatus(adminLogin, 200, "super admin login");
  admin.token = String(adminLogin.data?.token || "");

  await cleanupViaAdmin(cfg.baseUrl, admin, cfg.runTag);

  const storeOwner = await registerOwnerMerchant(cfg.baseUrl, cfg.runTag, "store", {
    name: `Load Store ${cfg.runTag}`,
    type: "restaurant",
    activityType: "restaurant",
    discoverySubcategory: "eastern",
    description: `load-store-${cfg.runTag}`,
    tagline: `load-store-tagline-${cfg.runTag}`,
    serviceAreaNote: `load-store-service-area-${cfg.runTag}`,
    supportsChat: true,
    supportsAttachments: true,
    supportsPharmacyWorkflow: false,
  });

  const pharmacyOwner = await registerOwnerMerchant(cfg.baseUrl, cfg.runTag, "pharmacy", {
    name: `Load Pharmacy ${cfg.runTag}`,
    type: "market",
    activityType: "pharmacy",
    discoverySubcategory: "prescriptions",
    description: `load-pharmacy-${cfg.runTag}`,
    tagline: `load-pharmacy-tagline-${cfg.runTag}`,
    serviceAreaNote: `load-pharmacy-service-area-${cfg.runTag}`,
    supportsChat: true,
    supportsAttachments: true,
    supportsPharmacyWorkflow: true,
  });

  await approveMerchantFlow(cfg.baseUrl, admin, storeOwner.actor, storeOwner.merchantId);
  await approveMerchantFlow(
    cfg.baseUrl,
    admin,
    pharmacyOwner.actor,
    pharmacyOwner.merchantId
  );

  const storeCategoryId = await createCategory(
    cfg.baseUrl,
    storeOwner.actor,
    `Load Store Category ${cfg.runTag}`
  );
  const pharmacyCategoryId = await createCategory(
    cfg.baseUrl,
    pharmacyOwner.actor,
    `Load Pharmacy Category ${cfg.runTag}`
  );

  const storeProductId = await createProduct(cfg.baseUrl, storeOwner.actor, {
    name: `Load Product ${cfg.runTag}`,
    categoryId: storeCategoryId,
    price: 4500,
    discountedPrice: 4200,
    description: `load-product-${cfg.runTag}`,
    freeDelivery: false,
    isAvailable: true,
    sortOrder: 1,
  });

  const pharmacyOtcProductId = await createProduct(cfg.baseUrl, pharmacyOwner.actor, {
    name: `Load OTC ${cfg.runTag}`,
    categoryId: pharmacyCategoryId,
    price: 3000,
    description: `load-otc-${cfg.runTag}`,
    freeDelivery: false,
    isAvailable: true,
    sortOrder: 1,
    requiresPrescription: false,
    requiresReview: false,
  });

  const pharmacyRxProductId = await createProduct(cfg.baseUrl, pharmacyOwner.actor, {
    name: `Load RX ${cfg.runTag}`,
    categoryId: pharmacyCategoryId,
    price: 5500,
    description: `load-rx-${cfg.runTag}`,
    freeDelivery: false,
    isAvailable: true,
    sortOrder: 2,
    requiresPrescription: true,
    requiresReview: true,
  });

  const customers = [];
  for (let i = 1; i <= cfg.customerPool; i += 1) {
    const customer = await registerCustomer(cfg.baseUrl, cfg.runTag, i);
    customers.push(customer);
  }

  const seedPostIds = [];
  for (const customer of customers.slice(0, Math.min(3, customers.length))) {
    const postId = await createSeedPost(
      cfg.baseUrl,
      customer.actor,
      `load-seed-post-${cfg.runTag}-${customer.userId}`
    );
    if (postId) seedPostIds.push(postId);
  }

  console.log(
    JSON.stringify({
      runTag: cfg.runTag,
      merchantId: storeOwner.merchantId,
      productId: storeProductId,
      pharmacyMerchantId: pharmacyOwner.merchantId,
      pharmacyOtcProductId,
      pharmacyProductId: pharmacyRxProductId,
      seedPostIds,
      authTokens: customers.map((customer) => ({
        userId: customer.userId,
        phone: customer.phone,
        token: customer.token,
        deviceId: customer.deviceId,
        platform: customer.platform,
        appVersion: customer.appVersion,
        model: customer.model,
        userAgent: customer.userAgent,
      })),
    })
  );
}

main().catch((error) => {
  console.error("[seed-load-fixtures] failed:", error);
  process.exitCode = 1;
});

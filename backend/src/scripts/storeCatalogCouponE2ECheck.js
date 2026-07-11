/* eslint-disable no-console */
import "dotenv/config";

import assert from "node:assert/strict";
import { execSync } from "node:child_process";

import { app } from "../app.js";
import {
  buildPhone,
  buildRunTag,
  createActor,
  readId,
  startLocalServer,
  stopLocalServer,
} from "./e2eTestUtils.js";

const DEFAULT_BASE_URL = "https://bestoffer-production.up.railway.app";

function parseArgs() {
  const args = process.argv.slice(2);
  const out = {
    baseUrl:
      String(
        process.env.E2E_BASE_URL ||
          process.env.LOAD_BASE_URL ||
          process.env.BASE_URL ||
          "",
      )
        .trim()
        .replace(/\/+$/, "") || null,
    runTag:
      String(process.env.STORE_CATALOG_COUPON_RUN_TAG || "").trim() ||
      buildRunTag("store-catalog-coupon"),
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
    }
  }

  return out;
}

function getGitCommit() {
  try {
    return execSync("git rev-parse HEAD", {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch (_) {
    return (
      String(process.env.GIT_COMMIT || process.env.RAILWAY_GIT_COMMIT || "")
        .trim() || null
    );
  }
}

function parseResponseText(raw) {
  if (!raw) return null;
  try {
    return JSON.parse(raw);
  } catch (_) {
    return raw;
  }
}

function extractRequestId(headers) {
  for (const key of [
    "x-request-id",
    "x-requestid",
    "x-correlation-id",
    "x-trace-id",
  ]) {
    const value = headers.get(key);
    if (value) return value;
  }
  return null;
}

function buildHeaders(actor, { withBody = false } = {}) {
  const appFlavor = String(actor.appFlavor || "").trim();
  const headers = {
    "X-Device-Id": actor.deviceId,
    "X-App-Version": actor.appVersion,
    "X-Device-Model": actor.model,
    "User-Agent": actor.userAgent,
  };
  if (appFlavor) {
    headers["X-Client-Platform"] = `flutter:${appFlavor}`;
    headers["X-App-Flavor"] = appFlavor;
  } else {
    headers["X-Client-Platform"] = actor.platform;
  }
  if (actor.token) {
    headers.Authorization = `Bearer ${actor.token}`;
  }
  if (withBody) {
    headers["Content-Type"] = "application/json";
  }
  return headers;
}

async function request(baseUrl, actor, method, path, body) {
  const max429Retries = 4;
  const maxTransportRetries = 3;

  for (let attempt = 0; ; attempt += 1) {
    let response;
    try {
      response = await fetch(`${baseUrl}${path}`, {
        method,
        headers: buildHeaders(actor, { withBody: body !== undefined }),
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: AbortSignal.timeout(20000),
      });
    } catch (error) {
      if (attempt >= maxTransportRetries) {
        throw error;
      }
      await new Promise((resolve) => setTimeout(resolve, (attempt + 1) * 1000));
      continue;
    }

    const raw = await response.text();
    const data = parseResponseText(raw);
    const result = {
      status: response.status,
      ok: response.ok,
      data,
      requestId: extractRequestId(response.headers),
      headers: Object.fromEntries(response.headers.entries()),
    };

    if (response.status !== 429 || attempt >= max429Retries) {
      return result;
    }

    const retryHeader = Number(response.headers.get("retry-after") || 0);
    const retryDetails = Number(data?.details?.retryAfterSeconds || 0);
    const waitSec = Math.max(1, retryHeader || retryDetails || 1);
    await new Promise((resolve) => setTimeout(resolve, waitSec * 1000));
  }
}

function assertStatus(response, expectedStatus, label) {
  assert.equal(
    response.status,
    expectedStatus,
    `${label} -> expected ${expectedStatus}, received ${response.status}, body=${JSON.stringify(response.data)}`,
  );
}

function readCouponDiscountTotal(payload) {
  const value =
    payload?.coupon_discount_total ??
    payload?.couponDiscountTotal ??
    payload?.totals?.couponDiscountTotal ??
    payload?.preview?.totals?.couponDiscountTotal ??
    0;
  const numeric = Number(value || 0);
  return Number.isFinite(numeric) ? numeric : 0;
}

function namesFromList(payload) {
  const list = Array.isArray(payload) ? payload : [];
  return list
    .map((item) => String(item?.name || item?.merchantName || "").trim())
    .filter(Boolean);
}

async function cleanup(baseUrl, admin, runTag) {
  const response = await request(
    baseUrl,
    admin,
    "POST",
    "/api/admin/ops/test-artifacts/cleanup",
    { runTag },
  );
  assertStatus(response, 200, `cleanup ${runTag}`);
}

async function login(baseUrl, actor, phone, pin, label) {
  const response = await request(baseUrl, actor, "POST", "/api/auth/login", {
    phone,
    pin,
  });
  assertStatus(response, 200, label);
  actor.token = String(response.data?.token || "");
  actor.sessionId = Number(response.data?.sessionId || 0) || null;
  return response;
}

async function registerCustomer(baseUrl, actor, { fullName, phone, pin }) {
  const response = await request(baseUrl, actor, "POST", "/api/auth/register", {
    fullName,
    phone,
    pin,
    block: "A1",
    buildingNumber: "A101",
    apartment: "101",
    analyticsConsentAccepted: true,
    analyticsConsentVersion: "analytics_v1",
  });
  assertStatus(response, 201, "customer register");
  actor.token = String(response.data?.token || "");
  actor.sessionId = Number(response.data?.sessionId || 0) || null;
  return response;
}

async function createMerchant(baseUrl, admin, payload, label) {
  const response = await request(baseUrl, admin, "POST", "/api/merchants", payload);
  assertStatus(response, 201, label);
  const merchantId = readId(response.data?.merchant || response.data);
  assert.ok(merchantId, `${label} -> merchant id missing`);
  return { response, merchantId };
}

async function acceptFinancialTermsAndReadMerchant(baseUrl, owner, label) {
  const acceptTerms = await request(
    baseUrl,
    owner,
    "POST",
    "/api/owner/merchant/financial-terms/accept",
  );
  if (acceptTerms.status !== 200) {
    assert.equal(
      acceptTerms.status,
      409,
      `${label} accept financial terms -> expected 200 or a controlled 409, received ${acceptTerms.status}, body=${JSON.stringify(acceptTerms.data)}`,
    );
    assert.equal(
      String(acceptTerms.data?.message || acceptTerms.data?.error || ""),
      "MERCHANT_FINANCIAL_TERMS_NOT_PENDING",
      `${label} accept financial terms -> expected MERCHANT_FINANCIAL_TERMS_NOT_PENDING when not pending`,
    );
  }
  const merchantState = await request(baseUrl, owner, "GET", "/api/owner/merchant");
  assertStatus(merchantState, 200, `${label} merchant state`);
  assert.equal(
    merchantState.data?.merchant?.isOpen,
    true,
    `${label} merchant should already be open`,
  );
  return { acceptTerms, merchantState };
}

async function createCategory(baseUrl, owner, payload, label) {
  const response = await request(baseUrl, owner, "POST", "/api/owner/categories", payload);
  assertStatus(response, 201, label);
  const categoryId = readId(response.data?.category || response.data);
  assert.ok(categoryId, `${label} -> category id missing`);
  return { response, categoryId };
}

async function createProduct(baseUrl, owner, payload, label) {
  const response = await request(baseUrl, owner, "POST", "/api/owner/products", payload);
  assertStatus(response, 201, label);
  const productId = readId(response.data?.product || response.data);
  assert.ok(productId, `${label} -> product id missing`);
  return { response, productId };
}

async function createCoupon(baseUrl, actor, payload, label) {
  const response = await request(baseUrl, actor, "POST", "/api/coupons", payload);
  assertStatus(response, 201, label);
  const couponId = readId(response.data?.coupon || response.data);
  assert.ok(couponId, `${label} -> coupon id missing`);
  return { response, couponId };
}

async function validateCoupon(baseUrl, customer, payload, label) {
  const response = await request(
    baseUrl,
    customer,
    "POST",
    "/api/coupons/validate",
    payload,
  );
  assertStatus(response, 200, label);
  return response;
}

async function previewOrder(baseUrl, customer, payload, label) {
  const response = await request(baseUrl, customer, "POST", "/api/orders/preview", payload);
  assertStatus(response, 200, label);
  return response;
}

async function createOrder(baseUrl, customer, payload, label) {
  const response = await request(baseUrl, customer, "POST", "/api/orders", payload);
  assertStatus(response, 201, label);
  const orderId = readId(response.data?.order || response.data);
  assert.ok(orderId, `${label} -> order id missing`);
  return { response, orderId };
}

async function listPublicMerchants(baseUrl, query, label) {
  const search = new URLSearchParams();
  for (const [key, value] of Object.entries(query || {})) {
    if (value !== undefined && value !== null && String(value).trim() !== "") {
      search.set(key, String(value));
    }
  }
  const suffix = search.toString() ? `?${search.toString()}` : "";
  const publicActor = {
    deviceId: "public-device",
    appVersion: "e2e/1",
    model: "public-model",
    platform: "e2e",
    userAgent: "public-user-agent",
  };
  const response = await request(baseUrl, publicActor, "GET", `/api/merchants${suffix}`);
  assertStatus(response, 200, label);
  return response;
}

async function main() {
  const cfg = parseArgs();
  const commit = getGitCommit();
  const runningInRailway = Boolean(
    process.env.RAILWAY_ENVIRONMENT_ID ||
      process.env.RAILWAY_SERVICE_ID ||
      process.env.RAILWAY_PROJECT_ID,
  );
  let baseUrl = cfg.baseUrl;
  let localServer = null;
  if (!baseUrl) {
    if (runningInRailway) {
      baseUrl = DEFAULT_BASE_URL;
    } else {
      localServer = await startLocalServer(app);
      baseUrl = localServer.baseUrl;
    }
  }

  const superAdminPhone = String(process.env.SUPER_ADMIN_PHONE || "").trim();
  const superAdminPin = String(process.env.SUPER_ADMIN_PIN || "").trim();
  if (!superAdminPhone || !superAdminPin) {
    throw new Error("SUPER_ADMIN_CREDENTIALS_REQUIRED");
  }

  const runTag = cfg.runTag;
  const timestampUtc = new Date().toISOString();
  const timestampSeed = Number(String(Date.now()).slice(-8));

  const evidence = {
    script: "backend/src/scripts/storeCatalogCouponE2ECheck.js",
    commit,
    timestampUtc,
    env: {
      baseUrl,
      railway: runningInRailway,
      nodeEnv: process.env.NODE_ENV || null,
      runtime:
        process.env.RAILWAY_ENVIRONMENT_ID ||
        process.env.RAILWAY_SERVICE_ID ||
        null,
    },
    runTag,
    entities: {},
    steps: [],
  };

  const admin = createActor("super-admin", runTag, "store-catalog-coupon-e2e/1");
  admin.appFlavor = "company";
  const ownerMen = createActor("owner-men", runTag, "store-catalog-coupon-e2e/1");
  ownerMen.appFlavor = "store";
  const ownerWomen = createActor("owner-women", runTag, "store-catalog-coupon-e2e/1");
  ownerWomen.appFlavor = "store";
  const ownerUnisex = createActor("owner-unisex", runTag, "store-catalog-coupon-e2e/1");
  ownerUnisex.appFlavor = "store";
  const customer = createActor("customer", runTag, "store-catalog-coupon-e2e/1");
  customer.appFlavor = "user";

  try {
    const adminLogin = await request(baseUrl, admin, "POST", "/api/auth/login", {
      phone: superAdminPhone,
      pin: superAdminPin,
    });
    assertStatus(adminLogin, 200, "super admin login");
    admin.token = String(adminLogin.data?.token || "");
    admin.sessionId = Number(adminLogin.data?.sessionId || 0) || null;
    evidence.steps.push({
      label: "super_admin_login",
      method: "POST",
      endpoint: "/api/auth/login",
      status: adminLogin.status,
      requestId: adminLogin.requestId,
      ids: { userId: readId(adminLogin.data?.user) },
    });

    await cleanup(baseUrl, admin, runTag);
    evidence.steps.push({
      label: "preflight_cleanup",
      method: "POST",
      endpoint: "/api/admin/ops/test-artifacts/cleanup",
      status: 200,
      requestId: null,
      ids: { runTag },
    });

    const menOwnerPhone = buildPhone("078", timestampSeed + 11);
    const menMerchant = await createMerchant(
      baseUrl,
      admin,
      {
        name: `Phase 1A Men Store ${runTag}`,
        type: "market",
        activityType: "fashion_clothing",
        department: "men",
        description: `men-store-${runTag}`,
        phone: buildPhone("078", timestampSeed + 1),
        owner: {
          fullName: `Phase 1A Owner Men ${runTag}`,
          phone: menOwnerPhone,
          pin: "1234",
          block: "A2",
          buildingNumber: "A201",
          apartment: "201",
        },
      },
      "create men fashion merchant",
    );
    evidence.entities.menMerchantId = menMerchant.merchantId;
    evidence.steps.push({
      label: "create_men_merchant",
      method: "POST",
      endpoint: "/api/merchants",
      status: menMerchant.response.status,
      requestId: menMerchant.response.requestId,
      ids: { merchantId: menMerchant.merchantId },
    });
    const menOwnerLogin = await login(baseUrl, ownerMen, menOwnerPhone, "1234", "owner men login");
    evidence.entities.menOwnerId = readId(menOwnerLogin.data?.user);
    evidence.steps.push({
      label: "owner_men_login",
      method: "POST",
      endpoint: "/api/auth/login",
      status: menOwnerLogin.status,
      requestId: menOwnerLogin.requestId,
      ids: { userId: evidence.entities.menOwnerId },
    });
    const menMerchantOps = await acceptFinancialTermsAndReadMerchant(baseUrl, ownerMen, "men merchant");
    evidence.steps.push({
      label: "men_merchant_open",
      method: "POST|GET",
      endpoint: "/api/owner/merchant/financial-terms/accept + /api/owner/merchant",
      status: `${menMerchantOps.acceptTerms.status}/${menMerchantOps.merchantState.status}`,
      requestId: `${menMerchantOps.acceptTerms.requestId || "n/a"}|${menMerchantOps.merchantState.requestId || "n/a"}`,
      ids: { merchantId: menMerchant.merchantId },
    });

    const duplicateOwnerCreate = await request(baseUrl, admin, "POST", "/api/merchants", {
      name: `Phase 1A Men Store Duplicate ${runTag}`,
      type: "market",
      activityType: "fashion_clothing",
      department: "women",
      description: `duplicate-men-store-${runTag}`,
      phone: buildPhone("078", timestampSeed + 21),
      ownerUserId: evidence.entities.menOwnerId,
    });
    assertStatus(duplicateOwnerCreate, 409, "same owner blocked from second merchant");
    assert.equal(
      String(duplicateOwnerCreate.data?.message || duplicateOwnerCreate.data?.error || ""),
      "OWNER_ALREADY_HAS_MERCHANT",
    );
    evidence.steps.push({
      label: "duplicate_owner_blocked",
      method: "POST",
      endpoint: "/api/merchants",
      status: duplicateOwnerCreate.status,
      requestId: duplicateOwnerCreate.requestId,
      ids: { ownerUserId: evidence.entities.menOwnerId },
    });

    const womenOwnerPhone = buildPhone("078", timestampSeed + 12);
    const womenMerchant = await createMerchant(
      baseUrl,
      admin,
      {
        name: `Phase 1A Women Store ${runTag}`,
        type: "market",
        activityType: "fashion_clothing",
        department: "women",
        description: `women-store-${runTag}`,
        phone: buildPhone("078", timestampSeed + 2),
        owner: {
          fullName: `Phase 1A Owner Women ${runTag}`,
          phone: womenOwnerPhone,
          pin: "1234",
          block: "A2",
          buildingNumber: "A202",
          apartment: "202",
        },
      },
      "create women fashion merchant",
    );
    evidence.entities.womenMerchantId = womenMerchant.merchantId;
    const womenOwnerLogin = await login(baseUrl, ownerWomen, womenOwnerPhone, "1234", "owner women login");
    evidence.steps.push({
      label: "owner_women_login",
      method: "POST",
      endpoint: "/api/auth/login",
      status: womenOwnerLogin.status,
      requestId: womenOwnerLogin.requestId,
      ids: { userId: readId(womenOwnerLogin.data?.user) },
    });
    const womenMerchantOps = await acceptFinancialTermsAndReadMerchant(baseUrl, ownerWomen, "women merchant");
    evidence.steps.push({
      label: "women_merchant_open",
      method: "POST|GET",
      endpoint: "/api/owner/merchant/financial-terms/accept + /api/owner/merchant",
      status: `${womenMerchantOps.acceptTerms.status}/${womenMerchantOps.merchantState.status}`,
      requestId: `${womenMerchantOps.acceptTerms.requestId || "n/a"}|${womenMerchantOps.merchantState.requestId || "n/a"}`,
      ids: { merchantId: womenMerchant.merchantId },
    });

    const unisexOwnerPhone = buildPhone("078", timestampSeed + 13);
    const unisexMerchant = await createMerchant(
      baseUrl,
      admin,
      {
        name: `Phase 1A Unisex Store ${runTag}`,
        type: "market",
        activityType: "fashion_clothing",
        department: "unisex",
        description: `unisex-store-${runTag}`,
        phone: buildPhone("078", timestampSeed + 3),
        owner: {
          fullName: `Phase 1A Owner Unisex ${runTag}`,
          phone: unisexOwnerPhone,
          pin: "1234",
          block: "A2",
          buildingNumber: "A203",
          apartment: "203",
        },
      },
      "create unisex fashion merchant",
    );
    evidence.entities.unisexMerchantId = unisexMerchant.merchantId;
    const unisexOwnerLogin = await login(baseUrl, ownerUnisex, unisexOwnerPhone, "1234", "owner unisex login");
    evidence.steps.push({
      label: "owner_unisex_login",
      method: "POST",
      endpoint: "/api/auth/login",
      status: unisexOwnerLogin.status,
      requestId: unisexOwnerLogin.requestId,
      ids: { userId: readId(unisexOwnerLogin.data?.user) },
    });
    const unisexMerchantOps = await acceptFinancialTermsAndReadMerchant(baseUrl, ownerUnisex, "unisex merchant");
    evidence.steps.push({
      label: "unisex_merchant_open",
      method: "POST|GET",
      endpoint: "/api/owner/merchant/financial-terms/accept + /api/owner/merchant",
      status: `${unisexMerchantOps.acceptTerms.status}/${unisexMerchantOps.merchantState.status}`,
      requestId: `${unisexMerchantOps.acceptTerms.requestId || "n/a"}|${unisexMerchantOps.merchantState.requestId || "n/a"}`,
      ids: { merchantId: unisexMerchant.merchantId },
    });

    const menList = await listPublicMerchants(
      baseUrl,
      { activityType: "fashion_clothing", department: "men" },
      "public men department list",
    );
    const womenList = await listPublicMerchants(
      baseUrl,
      { activityType: "fashion_clothing", department: "women" },
      "public women department list",
    );
    const menNames = namesFromList(menList.data);
    const womenNames = namesFromList(womenList.data);
    assert.ok(
      menNames.includes(`Phase 1A Men Store ${runTag}`),
      "men list should include men store",
    );
    assert.ok(
      menNames.includes(`Phase 1A Unisex Store ${runTag}`),
      "men list should include unisex store",
    );
    assert.ok(
      !menNames.includes(`Phase 1A Women Store ${runTag}`),
      "men list should not include women store",
    );
    assert.ok(
      womenNames.includes(`Phase 1A Women Store ${runTag}`),
      "women list should include women store",
    );
    assert.ok(
      womenNames.includes(`Phase 1A Unisex Store ${runTag}`),
      "women list should include unisex store",
    );
    assert.ok(
      !womenNames.includes(`Phase 1A Men Store ${runTag}`),
      "women list should not include men store",
    );
    evidence.steps.push({
      label: "fashion_department_filters",
      method: "GET",
      endpoint: "/api/merchants?activityType=fashion_clothing&department=men|women",
      status: 200,
      requestId: null,
      ids: {
        menMerchantId: menMerchant.merchantId,
        womenMerchantId: womenMerchant.merchantId,
        unisexMerchantId: unisexMerchant.merchantId,
      },
    });

    const category = await createCategory(
      baseUrl,
      ownerMen,
      {
        name: `Phase 1A Clothes ${runTag}`,
        sortOrder: 1,
        catalogType: "clothes",
      },
      "create fashion category",
    );
    evidence.entities.categoryId = category.categoryId;
    evidence.steps.push({
      label: "create_category",
      method: "POST",
      endpoint: "/api/owner/categories",
      status: category.response.status,
      requestId: category.response.requestId,
      ids: { categoryId: category.categoryId },
    });

    const ownerCategories = await request(baseUrl, ownerMen, "GET", "/api/owner/categories");
    assertStatus(ownerCategories, 200, "owner category list");
    assert.ok(
      Array.isArray(ownerCategories.data) &&
        ownerCategories.data.some((item) => Number(item?.id || 0) === category.categoryId),
      "owner categories should include created category",
    );
    evidence.steps.push({
      label: "owner_category_list",
      method: "GET",
      endpoint: "/api/owner/categories",
      status: ownerCategories.status,
      requestId: ownerCategories.requestId,
      ids: { categoryId: category.categoryId },
    });

    const publicCategories = await request(
      baseUrl,
      { deviceId: "public-device", appVersion: "e2e/1", model: "public-model", platform: "e2e", userAgent: "public-user-agent" },
      "GET",
      `/api/merchants/${menMerchant.merchantId}/categories`,
    );
    assertStatus(publicCategories, 200, "public category list");
    assert.ok(
      Array.isArray(publicCategories.data) &&
        publicCategories.data.some((item) => Number(item?.id || 0) === category.categoryId),
      "public categories should include created category",
    );
    evidence.steps.push({
      label: "public_category_list",
      method: "GET",
      endpoint: `/api/merchants/${menMerchant.merchantId}/categories`,
      status: publicCategories.status,
      requestId: publicCategories.requestId,
      ids: { merchantId: menMerchant.merchantId, categoryId: category.categoryId },
    });

    const product = await createProduct(
      baseUrl,
      ownerMen,
      {
        name: `Phase 1A Shirt ${runTag}`,
        categoryId: category.categoryId,
        price: 5000,
        discountedPrice: 4500,
        description: `shirt-product-${runTag}`,
        freeDelivery: false,
        isAvailable: true,
        sortOrder: 1,
      },
      "create fashion product",
    );
    evidence.entities.productId = product.productId;
    evidence.steps.push({
      label: "create_product",
      method: "POST",
      endpoint: "/api/owner/products",
      status: product.response.status,
      requestId: product.response.requestId,
      ids: { productId: product.productId, categoryId: category.categoryId },
    });

    const ownerProducts = await request(baseUrl, ownerMen, "GET", "/api/owner/products");
    assertStatus(ownerProducts, 200, "owner product list");
    assert.ok(
      Array.isArray(ownerProducts.data) &&
        ownerProducts.data.some((item) => Number(item?.id || 0) === product.productId),
      "owner products should include created product",
    );
    evidence.steps.push({
      label: "owner_product_list",
      method: "GET",
      endpoint: "/api/owner/products",
      status: ownerProducts.status,
      requestId: ownerProducts.requestId,
      ids: { productId: product.productId },
    });

    const publicProducts = await request(
      baseUrl,
      { deviceId: "public-device", appVersion: "e2e/1", model: "public-model", platform: "e2e", userAgent: "public-user-agent" },
      "GET",
      `/api/merchants/${menMerchant.merchantId}/products`,
    );
    assertStatus(publicProducts, 200, "public product list");
    assert.ok(
      Array.isArray(publicProducts.data) &&
        publicProducts.data.some((item) => Number(item?.id || 0) === product.productId),
      "public products should include created product",
    );
    evidence.steps.push({
      label: "public_product_list",
      method: "GET",
      endpoint: `/api/merchants/${menMerchant.merchantId}/products`,
      status: publicProducts.status,
      requestId: publicProducts.requestId,
      ids: { merchantId: menMerchant.merchantId, productId: product.productId },
    });

    const customerPhone = buildPhone("079", timestampSeed + 4);
    const customerRegister = await registerCustomer(baseUrl, customer, {
      fullName: `Phase 1A Customer ${runTag}`,
      phone: customerPhone,
      pin: "1234",
    });
    evidence.entities.customerUserId = readId(customerRegister.data?.user);
    evidence.steps.push({
      label: "customer_register",
      method: "POST",
      endpoint: "/api/auth/register",
      status: customerRegister.status,
      requestId: customerRegister.requestId,
      ids: { customerUserId: evidence.entities.customerUserId },
    });

    const merchantCouponCode = `M${String(timestampSeed).slice(-4)}A`;
    const merchantCoupon = await createCoupon(
      baseUrl,
      ownerMen,
      {
        code: merchantCouponCode,
        description: `Merchant coupon ${runTag}`,
        discountType: "fixed",
        discountValue: 500,
        minOrderTotal: 0,
        maxUses: 5,
      },
      "create merchant coupon",
    );
    evidence.entities.merchantCouponId = merchantCoupon.couponId;
    evidence.steps.push({
      label: "create_merchant_coupon",
      method: "POST",
      endpoint: "/api/coupons",
      status: merchantCoupon.response.status,
      requestId: merchantCoupon.response.requestId,
      ids: { couponId: merchantCoupon.couponId, merchantId: menMerchant.merchantId },
    });

    const merchantCouponValidation = await validateCoupon(
      baseUrl,
      customer,
      {
        code: merchantCouponCode,
        merchantId: menMerchant.merchantId,
        orderSubtotal: 5000,
      },
      "validate merchant coupon",
    );
    assert.equal(
      Number(merchantCouponValidation.data?.discountAmount || 0),
      500,
      "merchant coupon discount should be 500",
    );
    evidence.steps.push({
      label: "validate_merchant_coupon",
      method: "POST",
      endpoint: "/api/coupons/validate",
      status: merchantCouponValidation.status,
      requestId: merchantCouponValidation.requestId,
      ids: { couponId: merchantCoupon.couponId, merchantId: menMerchant.merchantId },
    });

    const merchantCouponPreview = await previewOrder(
      baseUrl,
      customer,
      {
        merchantId: menMerchant.merchantId,
        items: [{ productId: product.productId, quantity: 1 }],
        couponCode: merchantCouponCode,
        note: `merchant-preview-${runTag}`,
      },
      "preview merchant coupon order",
    );
    assert.equal(
      Number(merchantCouponPreview.data?.totals?.couponDiscountTotal || 0),
      500,
      "merchant coupon preview should include coupon discount",
    );
    evidence.steps.push({
      label: "preview_merchant_coupon_checkout",
      method: "POST",
      endpoint: "/api/orders/preview",
      status: merchantCouponPreview.status,
      requestId: merchantCouponPreview.requestId,
      ids: { couponId: merchantCoupon.couponId, merchantId: menMerchant.merchantId, productId: product.productId },
    });

    const merchantCouponOrder = await createOrder(
      baseUrl,
      customer,
      {
        merchantId: menMerchant.merchantId,
        items: [{ productId: product.productId, quantity: 1 }],
        couponId: merchantCoupon.couponId,
        couponCode: merchantCouponCode,
        note: `merchant-checkout-${runTag}`,
      },
      "checkout merchant coupon order",
    );
    assert.equal(
      readCouponDiscountTotal(merchantCouponOrder.response.data),
      500,
      "merchant coupon checkout should include coupon discount",
    );
    evidence.entities.merchantCouponOrderId = merchantCouponOrder.orderId;
    evidence.steps.push({
      label: "checkout_merchant_coupon_order",
      method: "POST",
      endpoint: "/api/orders",
      status: merchantCouponOrder.response.status,
      requestId: merchantCouponOrder.response.requestId,
      ids: { orderId: merchantCouponOrder.orderId, couponId: merchantCoupon.couponId, productId: product.productId },
    });

    const adminCouponCode = `A${String(timestampSeed + 7).slice(-4)}G`;
    const adminCoupon = await createCoupon(
      baseUrl,
      admin,
      {
        code: adminCouponCode,
        description: `Admin coupon ${runTag}`,
        discountType: "percent",
        discountValue: 10,
        minOrderTotal: 0,
        maxUses: 10,
      },
      "create admin coupon",
    );
    evidence.entities.adminCouponId = adminCoupon.couponId;
    evidence.steps.push({
      label: "create_admin_coupon",
      method: "POST",
      endpoint: "/api/coupons",
      status: adminCoupon.response.status,
      requestId: adminCoupon.response.requestId,
      ids: { couponId: adminCoupon.couponId },
    });

    const adminCouponValidation = await validateCoupon(
      baseUrl,
      customer,
      {
        code: adminCouponCode,
        merchantId: menMerchant.merchantId,
        orderSubtotal: 5000,
      },
      "validate admin coupon",
    );
    assert.equal(
      Number(adminCouponValidation.data?.discountAmount || 0),
      500,
      "admin coupon discount should be 500 on 5000 subtotal",
    );
    evidence.steps.push({
      label: "validate_admin_coupon",
      method: "POST",
      endpoint: "/api/coupons/validate",
      status: adminCouponValidation.status,
      requestId: adminCouponValidation.requestId,
      ids: { couponId: adminCoupon.couponId, merchantId: menMerchant.merchantId },
    });

    const adminCouponPreview = await previewOrder(
      baseUrl,
      customer,
      {
        merchantId: menMerchant.merchantId,
        items: [{ productId: product.productId, quantity: 1 }],
        couponCode: adminCouponCode,
        note: `admin-preview-${runTag}`,
      },
      "preview admin coupon order",
    );
    const adminCouponBase = Math.max(
      0,
      Number(adminCouponPreview.data?.totals?.grossSubtotal || 0) -
        Number(adminCouponPreview.data?.totals?.productDiscountTotal || 0),
    );
    const adminCouponExpectedDiscount = Math.round(adminCouponBase * 0.1);
    assert.equal(
      Number(adminCouponPreview.data?.totals?.couponDiscountTotal || 0),
      adminCouponExpectedDiscount,
      "admin coupon preview should include the percent discount on the current subtotal",
    );
    evidence.steps.push({
      label: "preview_admin_coupon_checkout",
      method: "POST",
      endpoint: "/api/orders/preview",
      status: adminCouponPreview.status,
      requestId: adminCouponPreview.requestId,
      ids: { couponId: adminCoupon.couponId, merchantId: menMerchant.merchantId, productId: product.productId },
    });

    const adminCouponOrder = await createOrder(
      baseUrl,
      customer,
      {
        merchantId: menMerchant.merchantId,
        items: [{ productId: product.productId, quantity: 1 }],
        couponId: adminCoupon.couponId,
        couponCode: adminCouponCode,
        note: `admin-checkout-${runTag}`,
      },
      "checkout admin coupon order",
    );
    assert.equal(
      readCouponDiscountTotal(adminCouponOrder.response.data),
      adminCouponExpectedDiscount,
      "admin coupon checkout should include the percent discount on the current subtotal",
    );
    evidence.entities.adminCouponOrderId = adminCouponOrder.orderId;
    evidence.steps.push({
      label: "checkout_admin_coupon_order",
      method: "POST",
      endpoint: "/api/orders",
      status: adminCouponOrder.response.status,
      requestId: adminCouponOrder.response.requestId,
      ids: { orderId: adminCouponOrder.orderId, couponId: adminCoupon.couponId, productId: product.productId },
    });

    const adminCouponDelete = await request(
      baseUrl,
      admin,
      "DELETE",
      `/api/coupons/${adminCoupon.couponId}`,
    );
    assertStatus(adminCouponDelete, 200, "delete admin coupon cleanup");
    evidence.steps.push({
      label: "admin_coupon_cleanup",
      method: "DELETE",
      endpoint: `/api/coupons/${adminCoupon.couponId}`,
      status: adminCouponDelete.status,
      requestId: adminCouponDelete.requestId,
      ids: { couponId: adminCoupon.couponId },
    });

    console.log(JSON.stringify(evidence, null, 2));
    console.log("[store-catalog-coupon-e2e] passed");
  } finally {
    if (admin.token) {
      await cleanup(baseUrl, admin, runTag).catch((error) => {
        console.error("[store-catalog-coupon-e2e] cleanup failed:", error);
      });
    }
    if (localServer) {
      await stopLocalServer(localServer.server).catch(() => {});
    }
  }
}

main().catch((error) => {
  console.error("[store-catalog-coupon-e2e] failed:", error);
  process.exitCode = 1;
});

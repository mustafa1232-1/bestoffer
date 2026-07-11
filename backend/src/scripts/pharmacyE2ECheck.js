/* eslint-disable no-console */
import "dotenv/config";

import assert from "node:assert/strict";

import {
  assertStatus,
  buildPhone,
  buildRunTag,
  createActor,
  expectNotification,
  readId,
  request,
} from "./e2eTestUtils.js";
import { q } from "../config/db.js";

const DEFAULT_BASE_URL = "https://bestoffer-production.up.railway.app";

async function multipartRequest(baseUrl, actor, method, path, formData) {
  const response = await fetch(`${baseUrl}${path}`, {
    method,
    headers: {
      "X-Device-Id": actor.deviceId,
      "X-Client-Platform": actor.platform,
      "X-App-Version": actor.appVersion,
      "X-Device-Model": actor.model,
      "User-Agent": actor.userAgent,
      ...(actor.token ? { Authorization: `Bearer ${actor.token}` } : {}),
    },
    body: formData,
  });
  const raw = await response.text();
  const data = raw
    ? (() => {
        try {
          return JSON.parse(raw);
        } catch {
          return raw;
        }
      })()
    : null;
  return { status: response.status, ok: response.ok, data };
}

async function cleanupViaAdmin(baseUrl, admin, runTag) {
  const response = await request(
    baseUrl,
    admin,
    "POST",
    "/api/admin/ops/test-artifacts/cleanup",
    { runTag }
  );
  assertStatus(response, 200, `cleanup ${runTag}`);
}

async function findUserIdByPhone(phone) {
  const result = await q(
    `SELECT id
     FROM app_user
     WHERE phone = $1
     LIMIT 1`,
    [String(phone)]
  );
  return Number(result.rows[0]?.id || 0) || null;
}

async function main() {
  const baseUrl = String(process.env.LOAD_BASE_URL || DEFAULT_BASE_URL).trim().replace(/\/+$/, "");
  const runTag = buildRunTag("pharmacy-e2e");
  const seed = Number(String(Date.now()).slice(-8));

  const admin = createActor("admin", runTag, "pharmacy-e2e/1");
  const owner = createActor("owner", runTag, "pharmacy-e2e/1");
  const customer = createActor("customer", runTag, "pharmacy-e2e/1");
  const customerPhone = buildPhone("079", seed);
  const ownerPhone = buildPhone("078", seed + 1);

  try {
    const adminLogin = await request(baseUrl, admin, "POST", "/api/auth/login", {
      phone: process.env.SUPER_ADMIN_PHONE,
      pin: process.env.SUPER_ADMIN_PIN,
    });
    assertStatus(adminLogin, 200, "admin login");
    admin.token = String(adminLogin.data?.token || "");

    await cleanupViaAdmin(baseUrl, admin, runTag);

    const customerRegister = await request(baseUrl, customer, "POST", "/api/auth/register", {
      fullName: `Pharmacy Customer ${runTag}`,
      phone: customerPhone,
      pin: "1234",
      block: "A1",
      buildingNumber: "A101",
      apartment: "101",
      analyticsConsentAccepted: true,
      analyticsConsentVersion: "analytics_v1",
    });
    assertStatus(customerRegister, 201, "customer register");
    customer.token = String(customerRegister.data?.token || "");
    const customerUserId = await findUserIdByPhone(customerPhone);
    assert.ok(customerUserId, "customer user id missing");

    const ownerRegister = await request(baseUrl, owner, "POST", "/api/owner/register", {
      phone: ownerPhone,
      pin: "1234",
      block: "A2",
      buildingNumber: "A201",
      apartment: "201",
      merchantName: `Pharmacy Merchant ${runTag}`,
      merchantType: "market",
      merchantActivityType: "pharmacy",
      merchantDiscoverySubcategory: "prescriptions",
      merchantDescription: `pharmacy-desc-${runTag}`,
      merchantTagline: `pharmacy-tag-${runTag}`,
      merchantWorkingHours: "24h",
      merchantServiceAreaNote: `pharmacy-zone-${runTag}`,
      merchantSupportsChat: true,
      merchantSupportsAttachments: true,
      merchantSupportsPharmacyWorkflow: true,
      analyticsConsentAccepted: true,
      analyticsConsentVersion: "analytics_v1",
    });
    assertStatus(ownerRegister, 201, "owner register pharmacy");
    owner.token = String(ownerRegister.data?.token || "");
    const merchantId = readId(ownerRegister.data?.merchant);
    const ownerUserId = await findUserIdByPhone(ownerPhone);
    assert.ok(ownerUserId, "owner user id missing");

    const approveMerchant = await request(
      baseUrl,
      admin,
      "PATCH",
      `/api/admin/merchants/${merchantId}/approve`,
      {
        commissionType: "percentage",
        commissionValue: 10,
        serviceFeeType: "fixed",
        serviceFeeValue: 500,
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
    assertStatus(approveMerchant, 204, "approve pharmacy merchant");

    const acceptTerms = await request(
      baseUrl,
      owner,
      "POST",
      "/api/owner/merchant/financial-terms/accept"
    );
    assertStatus(acceptTerms, 200, "accept pharmacy terms");

    const categoryCreate = await request(baseUrl, owner, "POST", "/api/owner/categories", {
      name: `Pharmacy Category ${runTag}`,
      sortOrder: 1,
    });
    assertStatus(categoryCreate, 201, "create pharmacy category");
    const categoryId = readId(categoryCreate.data);

    const rxProductCreate = await request(baseUrl, owner, "POST", "/api/owner/products", {
      name: `RX Product ${runTag}`,
      categoryId,
      price: 5000,
      description: `rx-${runTag}`,
      freeDelivery: false,
      isAvailable: true,
      sortOrder: 1,
      requiresPrescription: true,
      requiresReview: true,
    });
    assertStatus(rxProductCreate, 201, "create rx product");
    const rxProductId = readId(rxProductCreate.data);

    const conversationCreate = await request(
      baseUrl,
      customer,
      "POST",
      "/api/pharmacy/conversations",
      {
        merchantId,
        initialMessage: `Need review for ${runTag}`,
        metadata: {
          productId: rxProductId,
          source: "pharmacy_e2e",
        },
      }
    );
    assertStatus(conversationCreate, 201, "create pharmacy conversation");
    const conversationId = readId(conversationCreate.data?.conversation);

    await expectNotification(
      {
        userId: ownerUserId,
        type: "pharmacy.conversation.new",
        payloadChecks: {
          target: "pharmacy_conversation",
          conversationId: String(conversationId),
          merchantId: String(merchantId),
        },
      },
      "pharmacy conversation notification"
    );

    const formData = new FormData();
    formData.set("file", new Blob(["prescription"], { type: "text/plain" }), "rx.txt");
    formData.set("metadata", JSON.stringify({ kind: "prescription", runTag }));
    const attachmentUpload = await multipartRequest(
      baseUrl,
      customer,
      "POST",
      `/api/pharmacy/conversations/${conversationId}/attachments`,
      formData
    );
    assertStatus(attachmentUpload, 201, "upload pharmacy attachment");
    const attachmentId = Number(attachmentUpload.data?.attachmentId || 0) || null;
    assert.ok(attachmentId, "attachment id missing");

    const accessUrlRes = await request(
      baseUrl,
      customer,
      "GET",
      `/api/pharmacy/attachments/${attachmentId}/access-url`
    );
    assertStatus(accessUrlRes, 200, "attachment access url");
    assert.ok(String(accessUrlRes.data?.url || "").includes("token="));

    const ownerConversations = await request(
      baseUrl,
      owner,
      "GET",
      "/api/pharmacy/conversations?bucket=active&q=Pharmacy"
    );
    assertStatus(ownerConversations, 200, "owner list pharmacy conversations");
    assert.ok(
      Array.isArray(ownerConversations.data?.items) &&
        ownerConversations.data.items.some(
          (item) => Number(item?.id || 0) === conversationId
        )
    );

    const firstCart = await request(
      baseUrl,
      owner,
      "POST",
      `/api/pharmacy/conversations/${conversationId}/proposed-carts`,
      {
        deliveryFee: 1000,
        notes: `first cart ${runTag}`,
        items: [
          {
            productId: rxProductId,
            productName: `RX Product ${runTag}`,
            quantity: 1,
            unitPrice: 5000,
            requiresPrescription: true,
            requiresReview: true,
          },
        ],
      }
    );
    assertStatus(firstCart, 201, "owner create proposed cart");
    const firstCartId = readId(firstCart.data?.cart);

    await expectNotification(
      {
        userId: customerUserId,
        type: "pharmacy.cart.proposed",
        payloadChecks: {
          target: "pharmacy_conversation",
          conversationId: String(conversationId),
          cartId: String(firstCartId),
        },
      },
      "pharmacy cart proposed notification"
    );

    const reviseCart = await request(
      baseUrl,
      customer,
      "POST",
      `/api/pharmacy/proposed-carts/${firstCartId}/request-revision`,
      { note: `revise ${runTag}` }
    );
    assertStatus(reviseCart, 200, "customer request cart revision");

    const revisedCart = await request(
      baseUrl,
      owner,
      "POST",
      `/api/pharmacy/conversations/${conversationId}/proposed-carts`,
      {
        deliveryFee: 500,
        notes: `revised cart ${runTag}`,
        items: [
          {
            productId: rxProductId,
            productName: `RX Product ${runTag}`,
            quantity: 1,
            unitPrice: 4800,
            requiresPrescription: true,
            requiresReview: true,
          },
        ],
      }
    );
    assertStatus(revisedCart, 201, "owner create revised proposed cart");
    const revisedCartId = readId(revisedCart.data?.cart);

    const acceptCart = await request(
      baseUrl,
      customer,
      "POST",
      `/api/pharmacy/proposed-carts/${revisedCartId}/accept`,
      {}
    );
    assertStatus(acceptCart, 200, "customer accept revised cart");

    await expectNotification(
      {
        userId: ownerUserId,
        type: "pharmacy.cart.accept",
        payloadChecks: {
          target: "pharmacy_conversation",
          conversationId: String(conversationId),
          cartId: String(revisedCartId),
        },
      },
      "pharmacy cart accepted notification"
    );

    const convertToOrder = await request(
      baseUrl,
      customer,
      "POST",
      `/api/pharmacy/proposed-carts/${revisedCartId}/convert-to-order`,
      { note: `convert ${runTag}` }
    );
    assertStatus(convertToOrder, 200, "convert pharmacy cart to order");
    const orderId = Number(convertToOrder.data?.orderId || 0) || null;
    assert.ok(orderId, "converted order id missing");

    await expectNotification(
      {
        userId: customerUserId,
        type: "pharmacy.order.created",
        payloadChecks: {
          target: "order_details",
          conversationId: String(conversationId),
          orderId: String(orderId),
        },
      },
      "pharmacy customer order created notification"
    );

    await expectNotification(
      {
        userId: ownerUserId,
        type: "pharmacy.order.created.store",
        payloadChecks: {
          target: "owner_order_details",
          conversationId: String(conversationId),
          orderId: String(orderId),
        },
      },
      "pharmacy owner order created notification"
    );

    const conversationDetails = await request(
      baseUrl,
      customer,
      "GET",
      `/api/pharmacy/conversations/${conversationId}?limit=50`
    );
    assertStatus(conversationDetails, 200, "pharmacy conversation details");
    assert.equal(
      String(conversationDetails.data?.conversation?.status || ""),
      "order_created"
    );

    const orders = await request(baseUrl, customer, "GET", "/api/orders/my");
    assertStatus(orders, 200, "customer orders after pharmacy convert");
    assert.ok(
      Array.isArray(orders.data) &&
        orders.data.some((item) => Number(item?.id || 0) === Number(orderId))
    );

    console.log(JSON.stringify({ ok: true, runTag, merchantId, conversationId, orderId }));
  } finally {
    if (admin.token) {
      await cleanupViaAdmin(baseUrl, admin, runTag).catch(() => {});
    }
  }
}

main().catch((error) => {
  console.error("[pharmacy-e2e] failed:", error);
  process.exitCode = 1;
});

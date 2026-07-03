/* eslint-disable no-console */
import "dotenv/config";

import assert from "node:assert/strict";

import { app } from "../app.js";
import { ensureSchema, pool, q } from "../config/db.js";
import { env, validateRuntimeEnv } from "../config/env.js";
import { allocateRegistrationUsername } from "../modules/auth/auth.service.js";
import { runSqlMigrations } from "../config/sqlMigrations.js";
import { hashPin } from "../shared/utils/hash.js";

function buildRunTag() {
  return `e2e-${Date.now().toString(36)}-${Math.random()
    .toString(36)
    .slice(2, 8)}`;
}

function shouldSkipMigrations() {
  const raw = String(process.env.E2E_SKIP_SQL_MIGRATIONS || "").trim().toLowerCase();
  return ["1", "true", "yes", "on"].includes(raw);
}

function shouldSkipEnsureSchema() {
  const raw = String(process.env.E2E_SKIP_ENSURE_SCHEMA || "").trim().toLowerCase();
  return ["1", "true", "yes", "on"].includes(raw);
}

function buildPhone(prefix, seed) {
  const suffix = String(seed).padStart(8, "0").slice(-8);
  return `${prefix}${suffix}`;
}

function createActor(name, runTag) {
  return {
    name,
    token: null,
    sessionId: null,
    deviceId: `${runTag}-${name}-device`,
    platform: "e2e",
    appVersion: "e2e-order-check/1",
    model: `${name}-simulator`,
    userAgent: `order-e2e/${name}`,
  };
}

function buildHeaders(actor, { withBody = false } = {}) {
  const headers = {
    "X-Device-Id": actor.deviceId,
    "X-Client-Platform": actor.platform,
    "X-App-Version": actor.appVersion,
    "X-Device-Model": actor.model,
    "User-Agent": actor.userAgent,
  };
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
  for (let attempt = 0; ; attempt += 1) {
    const response = await fetch(`${baseUrl}${path}`, {
      method,
      headers: buildHeaders(actor, { withBody: body !== undefined }),
      body: body === undefined ? undefined : JSON.stringify(body),
    });

    const raw = await response.text();
    const data = raw
      ? (() => {
          try {
            return JSON.parse(raw);
          } catch (_) {
            return raw;
          }
        })()
      : null;

    if (response.status !== 429 || attempt >= max429Retries) {
      return {
        status: response.status,
        ok: response.ok,
        data,
      };
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
    `${label} -> expected ${expectedStatus}, received ${
      response.status
    }, body=${JSON.stringify(response.data)}`
  );
}

function readId(value) {
  const id = Number(value?.id || 0);
  return Number.isFinite(id) && id > 0 ? id : null;
}

function readOrderStatus(order) {
  return String(order?.status || order?.order_status || "");
}

function readCustomerConfirmedAt(order) {
  return order?.customer_confirmed_at || order?.customerConfirmedAt || null;
}

function extractOrderRows(payload) {
  if (Array.isArray(payload)) return payload;
  if (Array.isArray(payload?.orders)) return payload.orders;
  if (Array.isArray(payload?.requests)) return payload.requests;
  if (Array.isArray(payload?.items)) return payload.items;
  if (Array.isArray(payload?.data)) return payload.data;
  return [];
}

function readOrderId(order) {
  const id = Number(order?.id || order?.order_id || 0);
  return Number.isFinite(id) && id > 0 ? id : null;
}

function findOrder(rows, orderId) {
  const safeRows = extractOrderRows(rows);
  return safeRows.find((row) => readOrderId(row) === Number(orderId)) || null;
}

async function expectOrderVisible(
  baseUrl,
  actor,
  path,
  orderId,
  expectedStatus,
  label
) {
  const response = await request(baseUrl, actor, "GET", path);
  assertStatus(response, 200, label);
  const order = findOrder(response.data, orderId);
  assert.ok(order, `${label} -> order ${orderId} not found`);
  assert.equal(
    readOrderStatus(order),
    expectedStatus,
    `${label} -> expected status ${expectedStatus}, got ${readOrderStatus(order)}`
  );
  return order;
}

async function expectOrderHidden(baseUrl, actor, path, orderId, label) {
  const response = await request(baseUrl, actor, "GET", path);
  assertStatus(response, 200, label);
  const order = findOrder(response.data, orderId);
  assert.equal(order, null, `${label} -> order ${orderId} should be hidden`);
}

async function getLatestNotification({
  userId,
  type,
  orderId = null,
  merchantId = null,
  payloadChecks = null,
}) {
  const clauses = ["user_id = $1", "type = $2"];
  const params = [Number(userId), String(type)];

  if (orderId != null) {
    params.push(Number(orderId));
    clauses.push(`order_id = $${params.length}`);
  }

  if (merchantId != null) {
    params.push(Number(merchantId));
    clauses.push(`merchant_id = $${params.length}`);
  }

  if (payloadChecks && typeof payloadChecks === "object") {
    for (const [key, value] of Object.entries(payloadChecks)) {
      params.push(String(value));
      clauses.push(`COALESCE(payload->>'${key}', '') = $${params.length}`);
    }
  }

  const result = await q(
    `SELECT id, type, title, body, payload, created_at
     FROM app_notification
     WHERE ${clauses.join(" AND ")}
     ORDER BY id DESC
     LIMIT 1`,
    params
  );

  return result.rows[0] || null;
}

async function expectNotification(check, label) {
  const notification = await getLatestNotification(check);
  assert.ok(notification, `${label} -> notification not found`);
  return notification;
}

async function fetchOrderRow(orderId) {
  const result = await q(
    `SELECT
       id,
       status,
       customer_block,
       customer_building_number,
       customer_apartment,
       approved_at,
       preparing_started_at,
       prepared_at,
       picked_up_at,
       arrived_at,
       delivered_at,
       customer_confirmed_at
     FROM customer_order
     WHERE id = $1`,
    [Number(orderId)]
  );
  return result.rows[0] || null;
}

async function fetchCouponSnapshot(couponId, orderId) {
  const [couponResult, redemptionResult] = await Promise.all([
    q(
      `SELECT id, uses_count, max_uses
       FROM coupon
       WHERE id = $1
       LIMIT 1`,
      [Number(couponId)]
    ),
    q(
      `SELECT id, coupon_id, customer_id, order_id, discount_amount, is_void, void_reason
       FROM coupon_redemption
       WHERE coupon_id = $1
         AND order_id = $2
       LIMIT 1`,
      [Number(couponId), Number(orderId)]
    ),
  ]);

  return {
    coupon: couponResult.rows[0] || null,
    redemption: redemptionResult.rows[0] || null,
  };
}

async function fetchOfferUsageSnapshot(offerId, orderId) {
  const result = await q(
    `SELECT id, offer_id, order_id, discount_total, is_void, void_reason
     FROM merchant_offer_usage
     WHERE offer_id = $1
       AND order_id = $2
     LIMIT 1`,
    [Number(offerId), Number(orderId)]
  );
  return result.rows[0] || null;
}

async function ensureSuperAdminAccount() {
  const superPhone = String(env.superAdminPhone || "").trim();
  const superPin = String(env.superAdminPin || "").trim();
  const superName = String(env.superAdminName || "Super Admin").trim();

  if (!/^\d{8,20}$/.test(superPhone)) {
    throw new Error("SUPER_ADMIN_PHONE_INVALID");
  }
  if (!/^\d{4,8}$/.test(superPin)) {
    throw new Error("SUPER_ADMIN_PIN_INVALID");
  }

  const pinHash = await hashPin(superPin);
  const username = await allocateRegistrationUsername({
    fullName: superName,
    phone: superPhone,
  });
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query(
      `UPDATE app_user
       SET is_super_admin = FALSE
       WHERE is_super_admin = TRUE`
    );
    await client.query(
      `INSERT INTO app_user
        (
          full_name,
          username,
          phone,
          pin_hash,
          block,
          building_number,
          apartment,
          role,
          is_super_admin,
          analytics_consent_granted,
          analytics_consent_version,
          analytics_consent_granted_at
        )
       VALUES ($1,$2,$3,$4,'A','1','1','admin',TRUE,TRUE,'system_seed_v1',NOW())
       ON CONFLICT (phone)
       DO UPDATE SET
         full_name = EXCLUDED.full_name,
         username = COALESCE(NULLIF(app_user.username, ''), EXCLUDED.username),
         pin_hash = EXCLUDED.pin_hash,
         role = 'admin',
         is_super_admin = TRUE,
         analytics_consent_granted = TRUE,
         analytics_consent_version = 'system_seed_v1',
         analytics_consent_granted_at = COALESCE(
           app_user.analytics_consent_granted_at,
           NOW()
         )`,
      [superName, username, superPhone, pinHash]
    );
    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }

  const seeded = await q(
    `SELECT id
     FROM app_user
     WHERE phone = $1
     LIMIT 1`,
    [superPhone]
  );
  const superAdminId = Number(seeded.rows[0]?.id || 0);
  assert.ok(superAdminId > 0, "Super admin seeding failed");
  return superAdminId;
}

async function cleanup(state) {
  const userIds = [
    state.customerUserId,
    state.ownerUserId,
    state.deliveryUserId,
  ].filter((value) => Number.isFinite(Number(value)) && Number(value) > 0);
  const pathCleanup = [];
  if (state.merchantId) {
    pathCleanup.push(`/api/admin/merchants/${state.merchantId}/approve`);
  }

  const orderIds = [
    state.orderId,
    state.cancelledOrderId,
    state.postCompletionOrderId,
  ].filter((value) => Number.isFinite(Number(value)) && Number(value) > 0);

  const targetIds = [
    state.merchantId,
    state.deliveryUserId,
    ...orderIds,
    state.productId,
    state.categoryId,
    state.couponId,
    state.offerId,
  ].filter((value) => Number.isFinite(Number(value)) && Number(value) > 0);

  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    if (state.adminSessionId) {
      await client.query(`DELETE FROM user_session WHERE id = $1`, [
        Number(state.adminSessionId),
      ]);
    }

    if (pathCleanup.length > 0 && state.superAdminId) {
      await client.query(
        `DELETE FROM user_activity_event
         WHERE user_id = $1
           AND path = ANY($2::text[])`,
        [Number(state.superAdminId), pathCleanup]
      );
    }

    if (userIds.length > 0) {
      await client.query(
        `DELETE FROM user_activity_event
         WHERE user_id = ANY($1::bigint[])`,
        [userIds]
      );
    }

    if (targetIds.length > 0) {
      await client.query(
        `DELETE FROM admin_audit_event
         WHERE target_id = ANY($1::bigint[])`,
        [targetIds]
      );
    }

    if (state.runTag) {
      await client.query(
        `DELETE FROM admin_audit_event
         WHERE summary ILIKE $1
            OR COALESCE(target_label, '') ILIKE $1
            OR COALESCE(metadata::text, '') ILIKE $1`,
        [`%${state.runTag}%`]
      );
    }

    if (orderIds.length > 0) {
      await client.query(
        `DELETE FROM app_notification
         WHERE order_id = ANY($1::bigint[])`,
        [orderIds]
      );
      await client.query(
        `DELETE FROM merchant_offer_usage
         WHERE order_id = ANY($1::bigint[])`,
        [orderIds]
      );
      await client.query(
        `DELETE FROM coupon_redemption
         WHERE order_id = ANY($1::bigint[])`,
        [orderIds]
      );
      await client.query(
        `DELETE FROM order_item
         WHERE order_id = ANY($1::bigint[])`,
        [orderIds]
      );
      await client.query(
        `DELETE FROM customer_order
         WHERE id = ANY($1::bigint[])`,
        [orderIds]
      );
    }

    if (state.offerId) {
      await client.query(
        `DELETE FROM merchant_offer_product WHERE offer_id = $1`,
        [Number(state.offerId)]
      );
      await client.query(`DELETE FROM merchant_offer WHERE id = $1`, [
        Number(state.offerId),
      ]);
    }

    if (state.couponId) {
      await client.query(`DELETE FROM coupon WHERE id = $1`, [
        Number(state.couponId),
      ]);
    }

    if (state.merchantId) {
      await client.query(`DELETE FROM app_notification WHERE merchant_id = $1`, [
        Number(state.merchantId),
      ]);
      await client.query(
        `DELETE FROM customer_favorite_product
         WHERE product_id IN (
           SELECT id FROM product WHERE merchant_id = $1
         )`,
        [Number(state.merchantId)]
      );
      await client.query(`DELETE FROM product WHERE merchant_id = $1`, [
        Number(state.merchantId),
      ]);
      await client.query(`DELETE FROM merchant_category WHERE merchant_id = $1`, [
        Number(state.merchantId),
      ]);
      await client.query(`DELETE FROM merchant_settlement WHERE merchant_id = $1`, [
        Number(state.merchantId),
      ]);
      await client.query(`DELETE FROM merchant WHERE id = $1`, [
        Number(state.merchantId),
      ]);
    }

    if (userIds.length > 0) {
      await client.query(
        `DELETE FROM app_notification
         WHERE user_id = ANY($1::bigint[])`,
        [userIds]
      );
      await client.query(
        `DELETE FROM customer_address
         WHERE customer_user_id = ANY($1::bigint[])`,
        [userIds]
      );
      await client.query(
        `DELETE FROM user_push_token
         WHERE user_id = ANY($1::bigint[])`,
        [userIds]
      );
      await client.query(
        `DELETE FROM user_session
         WHERE user_id = ANY($1::bigint[])`,
        [userIds]
      );
    }

    if (state.deliveryUserId) {
      await client.query(
        `DELETE FROM taxi_captain_presence WHERE captain_user_id = $1`,
        [Number(state.deliveryUserId)]
      );
      await client.query(
        `DELETE FROM taxi_captain_profile WHERE user_id = $1`,
        [Number(state.deliveryUserId)]
      );
    }

    if (userIds.length > 0) {
      await client.query(`DELETE FROM app_user WHERE id = ANY($1::bigint[])`, [
        userIds,
      ]);
    }

    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

async function main() {
  validateRuntimeEnv();
  if (!shouldSkipMigrations()) {
    await runSqlMigrations({ force: true });
  }
  if (!shouldSkipEnsureSchema()) {
    await ensureSchema();
  }

  const runTag = buildRunTag();
  const timestampSeed = Number(String(Date.now()).slice(-8));
  const state = {
    runTag,
    customerPhone: buildPhone("079", timestampSeed),
    ownerPhone: buildPhone("078", timestampSeed + 1),
    deliveryPhone: buildPhone("077", timestampSeed + 2),
    superAdminId: await ensureSuperAdminAccount(),
    customerUserId: null,
    ownerUserId: null,
    deliveryUserId: null,
    merchantId: null,
    categoryId: null,
    productId: null,
    couponId: null,
    offerId: null,
    orderId: null,
    cancelledOrderId: null,
    postCompletionOrderId: null,
    adminSessionId: null,
  };

  let server = null;

  try {
    server = await new Promise((resolve, reject) => {
      const startedServer = app.listen(0, "127.0.0.1", () =>
        resolve(startedServer)
      );
      startedServer.on("error", reject);
    });

    const address = server.address();
    const baseUrl = `http://127.0.0.1:${address.port}`;
    console.log(`[order-e2e] baseUrl=${baseUrl} runTag=${runTag}`);

    const admin = createActor("admin", runTag);
    const owner = createActor("owner", runTag);
    const customer = createActor("customer", runTag);
    const delivery = createActor("delivery", runTag);

    const customerRegister = await request(
      baseUrl,
      customer,
      "POST",
      "/api/auth/register",
      {
        fullName: `E2E Customer ${runTag}`,
        phone: state.customerPhone,
        pin: "1234",
        block: "A1",
        buildingNumber: "A101",
        apartment: "101",
        analyticsConsentAccepted: true,
        analyticsConsentVersion: "analytics_v1",
      }
    );
    assertStatus(customerRegister, 201, "customer register");
    customer.token = String(customerRegister.data?.token || "");
    customer.sessionId = Number(customerRegister.data?.sessionId || 0) || null;
    state.customerUserId = readId(customerRegister.data?.user);
    assert.ok(state.customerUserId, "customer id missing after register");

    const ownerRegister = await request(
      baseUrl,
      owner,
      "POST",
      "/api/owner/register",
      {
        phone: state.ownerPhone,
        pin: "1234",
        block: "A2",
        buildingNumber: "A201",
        apartment: "102",
        merchantName: `E2E Merchant ${runTag}`,
        merchantType: "restaurant",
        merchantActivityType: "restaurant",
        merchantDiscoverySelectAll: true,
        merchantDescription: `merchant-desc-${runTag}`,
        merchantTagline: `merchant-tag-${runTag}`,
        merchantWorkingHours: "10:00-22:00",
        merchantServiceAreaNote: `service-area-${runTag}`,
        analyticsConsentAccepted: true,
        analyticsConsentVersion: "analytics_v1",
      }
    );
    assertStatus(ownerRegister, 201, "owner register");
    owner.token = String(ownerRegister.data?.token || "");
    owner.sessionId = Number(ownerRegister.data?.sessionId || 0) || null;
    state.ownerUserId = readId(ownerRegister.data?.user);
    state.merchantId = readId(ownerRegister.data?.merchant);
    assert.ok(state.ownerUserId, "owner id missing after register");
    assert.ok(state.merchantId, "merchant id missing after register");

    const deliveryRegister = await request(
      baseUrl,
      owner,
      "POST",
      "/api/owner/delivery-agents",
      {
        fullName: `E2E Delivery ${runTag}`,
        phone: state.deliveryPhone,
        pin: "1234",
      }
    );
    assertStatus(deliveryRegister, 201, "owner create delivery agent");
    state.deliveryUserId = readId(deliveryRegister.data?.user);
    assert.ok(state.deliveryUserId, "delivery id missing after owner create");

    const adminLogin = await request(baseUrl, admin, "POST", "/api/auth/login", {
      phone: env.superAdminPhone,
      pin: env.superAdminPin,
    });
    assertStatus(adminLogin, 200, "admin login");
    admin.token = String(adminLogin.data?.token || "");
    admin.sessionId = Number(adminLogin.data?.sessionId || 0) || null;
    state.adminSessionId = admin.sessionId;
    assert.ok(admin.token, "admin token missing");

    await expectNotification(
      {
        userId: state.superAdminId,
        type: "admin_pending_merchant",
        merchantId: state.merchantId,
      },
      "admin pending merchant notification"
    );
    const pendingMerchants = await request(
      baseUrl,
      admin,
      "GET",
      "/api/admin/merchants/pending"
    );
    assertStatus(pendingMerchants, 200, "pending merchants");
    assert.ok(
      Array.isArray(pendingMerchants.data) &&
        pendingMerchants.data.some(
          (item) => Number(item?.id || 0) === state.merchantId
        ),
      "pending merchants should include the created merchant"
    );

    const approveMerchant = await request(
      baseUrl,
      admin,
      "PATCH",
      `/api/admin/merchants/${state.merchantId}/approve`,
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
    assertStatus(approveMerchant, 204, "approve merchant");

    const pendingMerchantsAfterApprove = await request(
      baseUrl,
      admin,
      "GET",
      "/api/admin/merchants/pending"
    );
    assertStatus(pendingMerchantsAfterApprove, 200, "pending merchants after approve");
    assert.ok(
      !pendingMerchantsAfterApprove.data.some(
        (item) => Number(item?.id || 0) === state.merchantId
      ),
      "approved merchant should disappear from pending list"
    );

    const ownerMerchant = await request(baseUrl, owner, "GET", "/api/owner/merchant");
    assertStatus(ownerMerchant, 200, "owner merchant");
    assert.equal(
      ownerMerchant.data?.merchant?.approvalStatus,
      "awaiting_store_financial_acceptance",
      "merchant should wait for owner financial acceptance"
    );
    assert.equal(
      ownerMerchant.data?.merchant?.isApproved,
      false,
      "merchant should stay unapproved until owner accepts financial terms"
    );
    assert.ok(
      ownerMerchant.data?.merchant?.financialTermsSnapshot,
      "financial terms snapshot should be visible to owner"
    );

    const acceptFinancialTerms = await request(
      baseUrl,
      owner,
      "POST",
      "/api/owner/merchant/financial-terms/accept"
    );
    assertStatus(
      acceptFinancialTerms,
      200,
      "owner accept financial terms"
    );
    assert.equal(
      acceptFinancialTerms.data?.merchant?.approvalStatus,
      "approved",
      "merchant approval status should become approved after owner acceptance"
    );
    assert.equal(
      acceptFinancialTerms.data?.merchant?.isApproved,
      true,
      "merchant should become approved after owner acceptance"
    );

    const ownerMerchantAfterAcceptance = await request(
      baseUrl,
      owner,
      "GET",
      "/api/owner/merchant"
    );
    assertStatus(
      ownerMerchantAfterAcceptance,
      200,
      "owner merchant after accepting financial terms"
    );
    assert.equal(
      ownerMerchantAfterAcceptance.data?.merchant?.approvalStatus,
      "approved",
      "merchant should remain approved after owner acceptance"
    );
    assert.equal(
      ownerMerchantAfterAcceptance.data?.merchant?.isApproved,
      true,
      "merchant approved flag should remain true after owner acceptance"
    );

    const deliveryLogin = await request(baseUrl, delivery, "POST", "/api/auth/login", {
      phone: state.deliveryPhone,
      pin: "1234",
    });
    assertStatus(deliveryLogin, 200, "delivery login after approval");
    delivery.token = String(deliveryLogin.data?.token || "");
    delivery.sessionId = Number(deliveryLogin.data?.sessionId || 0) || null;

    const ownerDeliveryAgents = await request(
      baseUrl,
      owner,
      "GET",
      "/api/owner/delivery-agents"
    );
    assertStatus(ownerDeliveryAgents, 200, "owner delivery agents");
    assert.ok(
      Array.isArray(ownerDeliveryAgents.data) &&
        ownerDeliveryAgents.data.some(
          (item) => Number(item?.id || 0) === state.deliveryUserId
        ),
      "approved delivery agent should appear in owner delivery agents"
    );

    const categoryCreate = await request(
      baseUrl,
      owner,
      "POST",
      "/api/owner/categories",
      {
        name: `E2E Category ${runTag}`,
        sortOrder: 1,
      }
    );
    assertStatus(categoryCreate, 201, "owner create category");
    state.categoryId = readId(categoryCreate.data);
    assert.ok(state.categoryId, "category id missing");

    const productCreate = await request(baseUrl, owner, "POST", "/api/owner/products", {
      name: `E2E Product ${runTag}`,
      categoryId: state.categoryId,
      price: 3500,
      discountedPrice: 3200,
      description: `product-desc-${runTag}`,
      freeDelivery: false,
      isAvailable: true,
      sortOrder: 1,
    });
    assertStatus(productCreate, 201, "owner create product");
    state.productId = readId(productCreate.data);
    assert.ok(state.productId, "product id missing");

    const offerCreate = await request(baseUrl, owner, "POST", "/api/owner/offers", {
      title: `E2E Limited Offer ${runTag}`,
      description: `limited-offer-${runTag}`,
      offerType: "percentage",
      discountValue: 20,
      startsAt: new Date(Date.now() - 60 * 1000).toISOString(),
      endsAt: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
      status: "active",
      maxUsage: 1,
      productIds: [state.productId],
    });
    assertStatus(offerCreate, 201, "owner create limited offer");
    state.offerId = readId(offerCreate.data?.offer);
    assert.ok(state.offerId, "offer id missing");

    const couponCreate = await request(baseUrl, owner, "POST", "/api/coupons", {
      code: `ONCE${String(timestampSeed).slice(-4)}`,
      description: `single-use-coupon-${runTag}`,
      discountType: "fixed",
      discountValue: 500,
      minOrderTotal: 1500,
      maxUses: 1,
    });
    assertStatus(couponCreate, 201, "owner create coupon");
    state.couponId = readId(couponCreate.data?.coupon);
    assert.ok(state.couponId, "coupon id missing");

    const addresses = await request(
      baseUrl,
      customer,
      "GET",
      "/api/auth/account/addresses"
    );
    assertStatus(addresses, 200, "customer addresses");
    assert.ok(Array.isArray(addresses.data), "addresses response should be an array");
    const defaultAddress = addresses.data.find((item) => item?.isDefault === true);
    assert.ok(defaultAddress, "default address should exist");
    assert.equal(defaultAddress.block, "A1", "default address block mismatch");
    assert.equal(
      defaultAddress.buildingNumber,
      "A101",
      "default address building mismatch"
    );
    assert.equal(defaultAddress.apartment, "101", "default address apartment mismatch");

    const couponValidationBeforeOrder = await request(
      baseUrl,
      customer,
      "POST",
      "/api/coupons/validate",
      {
        code: couponCreate.data?.coupon?.code,
        merchantId: state.merchantId,
        orderSubtotal: 2800,
      }
    );
    assertStatus(couponValidationBeforeOrder, 200, "validate coupon before order");
    assert.equal(
      Number(couponValidationBeforeOrder.data?.discountAmount || 0),
      500,
      "coupon discount before order should match fixed value"
    );

    const cancelledOrderCreate = await request(baseUrl, customer, "POST", "/api/orders", {
      merchantId: state.merchantId,
      couponId: state.couponId,
      couponCode: couponCreate.data?.coupon?.code,
      items: [
        {
          productId: state.productId,
          quantity: 1,
        },
      ],
      note: `cancelled-order-${runTag}`,
    });
    assertStatus(cancelledOrderCreate, 201, "create order with coupon and offer");
    state.cancelledOrderId = readId(cancelledOrderCreate.data);
    assert.ok(state.cancelledOrderId, "cancelled order id missing");
    assert.equal(
      Number(cancelledOrderCreate.data?.product_discount_total || 0),
      700,
      "product offer should be applied on first order"
    );
    assert.equal(
      Number(cancelledOrderCreate.data?.coupon_discount_total || 0),
      500,
      "coupon should be applied on first order"
    );

    const couponAfterCreate = await fetchCouponSnapshot(
      state.couponId,
      state.cancelledOrderId
    );
    assert.equal(
      Number(couponAfterCreate.coupon?.uses_count || 0),
      1,
      "coupon uses_count should increment on order creation"
    );
    assert.equal(
      couponAfterCreate.redemption?.is_void,
      false,
      "coupon redemption should be active before cancellation"
    );
    const offerUsageAfterCreate = await fetchOfferUsageSnapshot(
      state.offerId,
      state.cancelledOrderId
    );
    assert.ok(offerUsageAfterCreate, "offer usage row missing after order creation");
    assert.equal(
      offerUsageAfterCreate?.is_void,
      false,
      "offer usage should be active before cancellation"
    );

    const cancelCouponOrder = await request(
      baseUrl,
      owner,
      "PATCH",
      `/api/owner/orders/${state.cancelledOrderId}/status`,
      {
        status: "cancelled",
      }
    );
    assertStatus(cancelCouponOrder, 204, "cancel coupon order");

    const couponAfterCancel = await fetchCouponSnapshot(
      state.couponId,
      state.cancelledOrderId
    );
    assert.equal(
      Number(couponAfterCancel.coupon?.uses_count || 0),
      0,
      "coupon uses_count should be restored after cancellation"
    );
    assert.equal(
      couponAfterCancel.redemption?.is_void,
      true,
      "coupon redemption should be void after cancellation"
    );
    assert.equal(
      String(couponAfterCancel.redemption?.void_reason || "").startsWith(
        "owner_status_transition:cancelled"
      ),
      true,
      "coupon void reason should record cancellation source"
    );
    const offerUsageAfterCancel = await fetchOfferUsageSnapshot(
      state.offerId,
      state.cancelledOrderId
    );
    assert.equal(
      offerUsageAfterCancel?.is_void,
      true,
      "offer usage should be void after cancellation"
    );

    const couponValidationAfterCancel = await request(
      baseUrl,
      customer,
      "POST",
      "/api/coupons/validate",
      {
        code: couponCreate.data?.coupon?.code,
        merchantId: state.merchantId,
        orderSubtotal: 2800,
      }
    );
    assertStatus(
      couponValidationAfterCancel,
      200,
      "validate coupon after cancellation"
    );

    const orderCreate = await request(baseUrl, customer, "POST", "/api/orders", {
      merchantId: state.merchantId,
      couponId: state.couponId,
      couponCode: couponCreate.data?.coupon?.code,
      items: [
        {
          productId: state.productId,
          quantity: 1,
        },
      ],
      note: `order-note-${runTag}`,
    });
    assertStatus(orderCreate, 201, "customer create order");
    state.orderId = readId(orderCreate.data);
    assert.ok(state.orderId, "order id missing");
    assert.equal(
      Number(orderCreate.data?.product_discount_total || 0),
      700,
      "offer should still be available after cancelled order reversal"
    );
    assert.equal(
      Number(orderCreate.data?.coupon_discount_total || 0),
      500,
      "coupon should still be available after cancelled order reversal"
    );

    const couponAfterSecondCreate = await fetchCouponSnapshot(
      state.couponId,
      state.orderId
    );
    assert.equal(
      Number(couponAfterSecondCreate.coupon?.uses_count || 0),
      1,
      "coupon uses_count should return to one on replacement order"
    );
    assert.equal(
      couponAfterSecondCreate.redemption?.is_void,
      false,
      "second order coupon redemption should stay active"
    );
    const offerUsageAfterSecondCreate = await fetchOfferUsageSnapshot(
      state.offerId,
      state.orderId
    );
    assert.equal(
      offerUsageAfterSecondCreate?.is_void,
      false,
      "second order offer usage should stay active"
    );

    const thirdOrderWithCoupon = await request(baseUrl, customer, "POST", "/api/orders", {
      merchantId: state.merchantId,
      couponId: state.couponId,
      couponCode: couponCreate.data?.coupon?.code,
      items: [
        {
          productId: state.productId,
          quantity: 1,
        },
      ],
      note: `should-fail-coupon-${runTag}`,
    });
    assertStatus(
      thirdOrderWithCoupon,
      400,
      "second active use of same coupon should fail"
    );

    const couponValidationWhileConsumed = await request(
      baseUrl,
      customer,
      "POST",
      "/api/coupons/validate",
      {
        code: couponCreate.data?.coupon?.code,
        merchantId: state.merchantId,
        orderSubtotal: 2800,
      }
    );
    assertStatus(
      couponValidationWhileConsumed,
      404,
      "validate coupon while active redemption exists"
    );

    const orderRowAfterCreate = await fetchOrderRow(state.orderId);
    assert.ok(orderRowAfterCreate, "order row missing after create");
    assert.equal(orderRowAfterCreate.customer_block, "A1", "order block mismatch");
    assert.equal(
      orderRowAfterCreate.customer_building_number,
      "A101",
      "order building mismatch"
    );
    assert.equal(orderRowAfterCreate.customer_apartment, "101", "order apartment mismatch");

    await expectNotification(
      {
        userId: state.customerUserId,
        type: "order_created",
        orderId: state.orderId,
      },
      "customer order created notification"
    );
    const ownerNewOrderNotification = await expectNotification(
      {
        userId: state.ownerUserId,
        type: "owner_new_order",
        orderId: state.orderId,
      },
      "owner new order notification"
    );
    assert.equal(
      ownerNewOrderNotification.payload?.requiresAction,
      true,
      "owner new order notification should require action"
    );

    await expectOrderVisible(
      baseUrl,
      customer,
      "/api/orders/my",
      state.orderId,
      "pending",
      "customer pending order"
    );
    await expectOrderVisible(
      baseUrl,
      owner,
      "/api/owner/orders/current",
      state.orderId,
      "pending",
      "owner pending order"
    );
    await expectOrderHidden(
      baseUrl,
      delivery,
      "/api/delivery/orders/current",
      state.orderId,
      "delivery should not see order before assignment"
    );

    const approveOrder = await request(
      baseUrl,
      owner,
      "PATCH",
      `/api/owner/orders/${state.orderId}/status`,
      {
        status: "approved",
        estimatedPrepMinutes: 15,
      }
    );
    assertStatus(approveOrder, 204, "owner approve order");
    await expectOrderVisible(
      baseUrl,
      customer,
      "/api/orders/my",
      state.orderId,
      "approved",
      "customer approved order"
    );
    await expectOrderVisible(
      baseUrl,
      owner,
      "/api/owner/orders/current",
      state.orderId,
      "approved",
      "owner approved order"
    );

    const preparingOrder = await request(
      baseUrl,
      owner,
      "POST",
      `/api/orders/${state.orderId}/store/start-preparing`,
      {
        estimatedPrepMinutes: 20,
        preferredCourierUserId: state.deliveryUserId,
      }
    );
    assertStatus(preparingOrder, 200, "owner preparing order");
    await expectOrderVisible(
      baseUrl,
      customer,
      "/api/orders/my",
      state.orderId,
      "preparing",
      "customer preparing order"
    );
    await expectOrderVisible(
      baseUrl,
      owner,
      "/api/owner/orders/current",
      state.orderId,
      "preparing",
      "owner preparing order"
    );
    await expectOrderVisible(
      baseUrl,
      delivery,
      "/api/courier/requests",
      state.orderId,
      "preparing",
      "courier preparing request after start preparing"
    );

    const assignCourier = await request(
      baseUrl,
      owner,
      "POST",
      `/api/orders/${state.orderId}/store/assign-courier`,
      {
        courierUserId: state.deliveryUserId,
        assignmentMode: "store_selected",
      }
    );
    assertStatus(assignCourier, 200, "owner assign courier");

    const courierAccept = await request(
      baseUrl,
      delivery,
      "POST",
      `/api/orders/${state.orderId}/courier/accept`
    );
    assertStatus(courierAccept, 200, "courier accept order");
    await expectOrderHidden(
      baseUrl,
      delivery,
      "/api/courier/requests",
      state.orderId,
      "courier requests after accept"
    );
    await expectOrderVisible(
      baseUrl,
      delivery,
      "/api/courier/orders",
      state.orderId,
      "preparing",
      "courier accepted preparing order"
    );

    await expectNotification(
      {
        userId: state.customerUserId,
        type: "order_courier_assigned",
        orderId: state.orderId,
      },
      "customer courier assigned notification"
    );

    const readyForDelivery = await request(
      baseUrl,
      owner,
      "POST",
      `/api/orders/${state.orderId}/store/ready-for-pickup`,
      {
        estimatedDeliveryMinutes: 12,
      }
    );
    assertStatus(readyForDelivery, 200, "owner ready for delivery");
    await expectOrderVisible(
      baseUrl,
      delivery,
      "/api/courier/orders",
      state.orderId,
      "ready_for_delivery",
      "courier ready for pickup order"
    );

    const courierPickedUp = await request(
      baseUrl,
      delivery,
      "POST",
      `/api/orders/${state.orderId}/courier/picked-up`
    );
    assertStatus(courierPickedUp, 200, "courier picked up order");
    await expectOrderVisible(
      baseUrl,
      customer,
      "/api/orders/my",
      state.orderId,
      "on_the_way",
      "customer on the way order"
    );
    await expectOrderVisible(
      baseUrl,
      owner,
      "/api/owner/orders/current",
      state.orderId,
      "on_the_way",
      "owner on the way order"
    );
    await expectOrderVisible(
      baseUrl,
      delivery,
      "/api/courier/orders",
      state.orderId,
      "on_the_way",
      "courier on the way order"
    );

    const courierArrived = await request(
      baseUrl,
      delivery,
      "POST",
      `/api/orders/${state.orderId}/courier/arrived`
    );
    assertStatus(courierArrived, 200, "courier mark arrived");
    await expectOrderVisible(
      baseUrl,
      customer,
      "/api/orders/my",
      state.orderId,
      "arrived",
      "customer arrived order"
    );
    await expectOrderVisible(
      baseUrl,
      owner,
      "/api/owner/orders/current",
      state.orderId,
      "arrived",
      "owner arrived order"
    );
    await expectOrderVisible(
      baseUrl,
      delivery,
      "/api/courier/orders",
      state.orderId,
      "arrived",
      "courier arrived order"
    );

    const courierDelivered = await request(
      baseUrl,
      delivery,
      "POST",
      `/api/orders/${state.orderId}/courier/delivered`
    );
    assertStatus(courierDelivered, 200, "courier mark delivered");
    await expectOrderVisible(
      baseUrl,
      customer,
      "/api/orders/my",
      state.orderId,
      "delivered",
      "customer delivered order"
    );
    const ownerDeliveredOrder = await expectOrderVisible(
      baseUrl,
      owner,
      "/api/owner/orders/current",
      state.orderId,
      "delivered",
      "owner delivered order"
    );
    assert.equal(
      readCustomerConfirmedAt(ownerDeliveredOrder),
      null,
      "owner delivered order should wait for customer confirmation"
    );
    await expectOrderVisible(
      baseUrl,
      delivery,
      "/api/courier/orders",
      state.orderId,
      "delivered",
      "courier delivered order"
    );

    const confirmDelivered = await request(
      baseUrl,
      customer,
      "POST",
      `/api/orders/${state.orderId}/customer/confirm-received`
    );
    assertStatus(confirmDelivered, 200, "customer confirm delivered");
    await expectNotification(
      {
        userId: state.ownerUserId,
        type: "owner_customer_received",
        orderId: state.orderId,
      },
      "owner customer confirmed notification"
    );

    const customerConfirmedOrder = await expectOrderVisible(
      baseUrl,
      customer,
      "/api/orders/my",
      state.orderId,
      "completed",
      "customer confirmed order remains visible"
    );
    assert.ok(
      readCustomerConfirmedAt(customerConfirmedOrder),
      "customer confirmed timestamp should be visible to customer"
    );
    await expectOrderHidden(
      baseUrl,
      owner,
      "/api/owner/orders/current",
      state.orderId,
      "owner current orders after customer confirmation"
    );
    await expectOrderHidden(
      baseUrl,
      delivery,
      "/api/delivery/orders/current",
      state.orderId,
      "delivery current orders after customer confirmation"
    );

    const finalOrderRow = await fetchOrderRow(state.orderId);
    assert.ok(finalOrderRow?.approved_at, "approved_at should be set");
    assert.ok(finalOrderRow?.preparing_started_at, "preparing_started_at should be set");
    assert.ok(finalOrderRow?.prepared_at, "prepared_at should be set");
    assert.ok(finalOrderRow?.picked_up_at, "picked_up_at should be set");
    assert.ok(finalOrderRow?.arrived_at, "arrived_at should be set");
    assert.ok(finalOrderRow?.delivered_at, "delivered_at should be set");
    assert.ok(
      finalOrderRow?.customer_confirmed_at,
      "customer_confirmed_at should be set"
    );

    const couponAfterCompletion = await fetchCouponSnapshot(
      state.couponId,
      state.orderId
    );
    assert.equal(
      Number(couponAfterCompletion.coupon?.uses_count || 0),
      1,
      "completed order should keep coupon usage consumed"
    );
    assert.equal(
      couponAfterCompletion.redemption?.is_void,
      false,
      "completed order coupon redemption should remain active"
    );
    const offerUsageAfterCompletion = await fetchOfferUsageSnapshot(
      state.offerId,
      state.orderId
    );
    assert.equal(
      offerUsageAfterCompletion?.is_void,
      false,
      "completed order offer usage should remain active"
    );

    const couponValidationAfterCompletion = await request(
      baseUrl,
      customer,
      "POST",
      "/api/coupons/validate",
      {
        code: couponCreate.data?.coupon?.code,
        merchantId: state.merchantId,
        orderSubtotal: 2800,
      }
    );
    assertStatus(
      couponValidationAfterCompletion,
      404,
      "completed order should keep coupon unavailable"
    );

    const postCompletionOrder = await request(baseUrl, customer, "POST", "/api/orders", {
      merchantId: state.merchantId,
      items: [
        {
          productId: state.productId,
          quantity: 1,
        },
      ],
      note: `post-completion-offer-check-${runTag}`,
    });
    assertStatus(postCompletionOrder, 201, "post-completion order without coupon");
    state.postCompletionOrderId = readId(postCompletionOrder.data);
    assert.ok(state.postCompletionOrderId, "post completion order id missing");
    assert.equal(
      Number(postCompletionOrder.data?.product_discount_total || 0),
      300,
      "after the limited offer is exhausted, pricing should fall back to the product discounted price only"
    );

    const cancelPostCompletionOrder = await request(
      baseUrl,
      owner,
      "PATCH",
      `/api/owner/orders/${state.postCompletionOrderId}/status`,
      {
        status: "cancelled",
      }
    );
    assertStatus(
      cancelPostCompletionOrder,
      204,
      "cancel post-completion verification order"
    );

    console.log(
      `[order-e2e] passed orderId=${state.orderId} cancelledOrderId=${state.cancelledOrderId} merchantId=${state.merchantId} couponId=${state.couponId} offerId=${state.offerId}`
    );
  } finally {
    try {
      await cleanup(state);
    } finally {
      if (server) {
        await new Promise((resolve) => server.close(resolve));
      }
      await pool.end();
    }
  }
}

main()
  .then(() => {
    process.exit(0);
  })
  .catch((error) => {
    console.error("[order-e2e] failed", error);
    process.exit(1);
  });

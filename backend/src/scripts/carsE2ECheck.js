/* eslint-disable no-console */
import "dotenv/config";

import assert from "node:assert/strict";

import { ensureSchema, q } from "../config/db.js";
import { env, validateRuntimeEnv } from "../config/env.js";
import { runSqlMigrations } from "../config/sqlMigrations.js";
import { assertSafeE2EDatabaseTarget } from "./e2eDbSafety.js";
import {
  assertStatus,
  buildPhone,
  buildRunTag,
  createActor,
  ensureSuperAdminAccount,
  expectNotification,
  readId,
  request,
} from "./e2eTestUtils.js";

const DEFAULT_BASE_URL = "https://bestoffer-production.up.railway.app";

function parseArgs() {
  const args = process.argv.slice(2);
  const out = {
    baseUrl: String(process.env.E2E_BASE_URL || DEFAULT_BASE_URL)
      .trim()
      .replace(/\/+$/, ""),
    runTag: String(process.env.CARS_E2E_RUN_TAG || "").trim() || buildRunTag("cars"),
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

function shouldSkipMigrations() {
  const raw = String(process.env.E2E_SKIP_SQL_MIGRATIONS || "")
    .trim()
    .toLowerCase();
  return ["1", "true", "yes", "on"].includes(raw);
}

function shouldSkipEnsureSchema() {
  const raw = String(process.env.E2E_SKIP_ENSURE_SCHEMA || "")
    .trim()
    .toLowerCase();
  return ["1", "true", "yes", "on"].includes(raw);
}

function readString(value) {
  return String(value ?? "").trim();
}

function readToken(response, label) {
  const token = readString(response?.data?.token || response?.data?.accessToken);
  assert.ok(token, `${label} -> missing token`);
  return token;
}

function readUserId(response, label) {
  const id = Number(response?.data?.user?.id || response?.data?.id || 0);
  assert.ok(id > 0, `${label} -> missing user id`);
  return id;
}

function readRequestId(response, label) {
  const requestRow = Array.isArray(response?.data?.requests)
    ? response.data.requests[0]
    : response?.data?.request;
  const id = Number(requestRow?.id || 0);
  assert.ok(id > 0, `${label} -> missing request id`);
  return id;
}

function readListingId(response, label) {
  const listing = response?.data?.listing || response?.data;
  const id = Number(listing?.id || 0);
  assert.ok(id > 0, `${label} -> missing listing id`);
  return id;
}

function extractThread(response) {
  return response?.data?.thread || response?.data || null;
}

function extractList(data) {
  if (Array.isArray(data)) return data;
  if (Array.isArray(data?.listings)) return data.listings;
  if (Array.isArray(data?.items)) return data.items;
  if (Array.isArray(data?.threads)) return data.threads;
  if (Array.isArray(data?.messages)) return data.messages;
  return [];
}

async function login(actor, baseUrl, phone, pin, label) {
  const response = await request(baseUrl, actor, "POST", "/api/auth/login", {
    phone,
    pin,
  });
  assertStatus(response, 200, label);
  actor.token = readToken(response, label);
  actor.userId = readUserId(response, label);
  actor.sessionId = Number(response?.data?.sessionId || 0) || null;
  return response.data;
}

async function registerUser(actor, baseUrl, payload, label) {
  const response = await request(baseUrl, actor, "POST", "/api/auth/register", payload);
  assertStatus(response, 201, label);
  return response.data;
}

async function createPaidUpgradeRequest(actor, baseUrl, planCode, runTag, label) {
  const response = await request(baseUrl, actor, "POST", "/api/paid-upgrades/requests", {
    planCodes: [planCode],
    activityName: `Cars Seller ${runTag}`,
    activityDescription: `Phase 2B cars seller request ${runTag}`,
    contactPhone: actor.phone,
    notes: `phase2b-${runTag}`,
    requestMeta: {
      phase: "phase_2b",
      runTag,
      module: "cars",
      planCode,
    },
  });
  assertStatus(response, 201, label);
  return readRequestId(response, label);
}

async function approvePaidUpgradeRequest(baseUrl, adminActor, requestId, label) {
  const response = await request(
    baseUrl,
    adminActor,
    "PATCH",
    `/api/admin/paid-upgrades/requests/${requestId}/approve`,
    {
      reviewNote: `Approved for ${label}`,
    }
  );
  assertStatus(response, 200, label);
  return response.data;
}

async function createListing(baseUrl, actor, payload, label) {
  const response = await request(baseUrl, actor, "POST", "/api/cars/listings", payload);
  assertStatus(response, 201, label);
  return readListingId(response, label);
}

async function createThread(baseUrl, actor, otherUserId, contextId, label) {
  const response = await request(baseUrl, actor, "POST", "/api/feed/chats/threads", {
    userId: otherUserId,
    kind: "business",
    contextType: "car_listing",
    contextId,
  });
  assertStatus(response, 201, label);
  return extractThread(response);
}

async function sendMessage(baseUrl, actor, threadId, body, label) {
  const response = await request(
    baseUrl,
    actor,
    "POST",
    `/api/feed/chats/threads/${threadId}/messages`,
    { body }
  );
  assertStatus(response, 201, label);
  return response.data;
}

async function listThreadMessages(baseUrl, actor, threadId, label) {
  const response = await request(
    baseUrl,
    actor,
    "GET",
    `/api/feed/chats/threads/${threadId}/messages`
  );
  assertStatus(response, 200, label);
  return response.data;
}

async function cleanupArtifacts({
  adminSessionId,
  superAdminId,
  sellerUserId,
  buyerUserId,
  listingId,
  requestId,
  runTag,
}) {
  const listingIds = [listingId]
    .map((value) => Number(value))
    .filter((value) => Number.isInteger(value) && value > 0);
  const requestIds = [requestId]
    .map((value) => Number(value))
    .filter((value) => Number.isInteger(value) && value > 0);
  const userIds = [sellerUserId, buyerUserId]
    .map((value) => Number(value))
    .filter((value) => Number.isInteger(value) && value > 0);

  if (listingIds.length > 0 || requestIds.length > 0) {
    await q(
      `DELETE FROM app_notification
       WHERE COALESCE(payload->>'listingId', '') = ANY($1::text[])
          OR COALESCE(payload->>'requestId', '') = ANY($2::text[])`,
      [listingIds.map(String), requestIds.map(String)]
    );
  }

  if (userIds.length > 0) {
    await q(`DELETE FROM app_user WHERE id = ANY($1::bigint[])`, [userIds]);
  }

  if (superAdminId && adminSessionId) {
    await q(`DELETE FROM user_session WHERE id = $1 AND user_id = $2`, [
      Number(adminSessionId),
      Number(superAdminId),
    ]);
  }

  if (superAdminId && runTag) {
    await q(
      `DELETE FROM user_activity_event
       WHERE user_id = $1
         AND path IN (
           '/api/admin/paid-upgrades/requests/' || $2::text || '/approve',
           '/api/admin/cars/listings/' || $3::text || '/approve'
         )`,
      [Number(superAdminId), String(requestId || 0), String(listingId || 0)]
    );
  }
}

async function main() {
  validateRuntimeEnv();
  const { baseUrl, runTag } = parseArgs();

  console.log(`[phase2b:cars] baseUrl=${baseUrl}`);
  console.log(`[phase2b:cars] runTag=${runTag}`);
  assertSafeE2EDatabaseTarget({
    scriptName: "phase2b-cars",
    databaseUrl: env.databaseUrl,
  });

  if (!shouldSkipMigrations()) {
    await runSqlMigrations({ force: true });
  }
  if (!shouldSkipEnsureSchema()) {
    await ensureSchema();
  }

  const superAdminId = await ensureSuperAdminAccount();

  const admin = createActor("phase2b-admin", runTag, "phase2b-cars/1");
  admin.appFlavor = "company";
  const seller = createActor("phase2b-cars-seller", runTag, "phase2b-cars/1");
  seller.appFlavor = "user";
  const buyer = createActor("phase2b-cars-buyer", runTag, "phase2b-cars/1");
  buyer.appFlavor = "user";

  const sellerPhone = buildPhone("079", Number(String(Date.now() + 23).slice(-8)));
  const buyerPhone = buildPhone("078", Number(String(Date.now() + 29).slice(-8)));
  const sellerPin = "1234";
  const buyerPin = "1234";

  let adminSessionId = null;
  let sellerUserId = null;
  let buyerUserId = null;
  let listingId = null;
  let requestId = null;

  try {
    console.log("[phase2b:cars] logging in super admin");
    await login(admin, baseUrl, env.superAdminPhone, env.superAdminPin, "super admin login");
    adminSessionId = admin.sessionId;

    console.log("[phase2b:cars] registering seller");
    await registerUser(
      seller,
      baseUrl,
      {
        fullName: `Phase 2B Cars Seller ${runTag}`,
        phone: sellerPhone,
        pin: sellerPin,
        block: "B2",
        buildingNumber: "B201",
        apartment: "101",
        analyticsConsentAccepted: true,
        analyticsConsentVersion: "phase2b_cars_v1",
      },
      "seller register"
    );
    seller.phone = sellerPhone;
    await login(seller, baseUrl, sellerPhone, sellerPin, "seller login");
    sellerUserId = seller.userId;

    console.log("[phase2b:cars] registering buyer");
    await registerUser(
      buyer,
      baseUrl,
      {
        fullName: `Phase 2B Cars Buyer ${runTag}`,
        phone: buyerPhone,
        pin: buyerPin,
        block: "A2",
        buildingNumber: "A201",
        apartment: "102",
        analyticsConsentAccepted: true,
        analyticsConsentVersion: "phase2b_cars_v1",
      },
      "buyer register"
    );
    buyer.phone = buyerPhone;
    await login(buyer, baseUrl, buyerPhone, buyerPin, "buyer login");
    buyerUserId = buyer.userId;

    console.log("[phase2b:cars] creating and activating paid upgrade");
    requestId = await createPaidUpgradeRequest(
      seller,
      baseUrl,
      "car_seller_monthly",
      runTag,
      "cars seller paid upgrade request"
    );
    await approvePaidUpgradeRequest(
      baseUrl,
      admin,
      requestId,
      "cars seller paid upgrade approval"
    );

    const paidUpgradeSummary = await request(baseUrl, seller, "GET", "/api/paid-upgrades/me");
    assertStatus(paidUpgradeSummary, 200, "seller paid-upgrades summary");
    assert.equal(
      paidUpgradeSummary.data?.entitlements?.carSellerMonthly,
      true,
      "seller entitlement should be active"
    );

    const entitlementResponse = await request(baseUrl, seller, "GET", "/api/cars/entitlements");
    assertStatus(entitlementResponse, 200, "seller cars entitlements");
    assert.equal(
      entitlementResponse.data?.carSellerMonthly,
      true,
      "cars entitlement should be active"
    );
    assert.equal(
      entitlementResponse.data?.canPostCars,
      true,
      "cars posting entitlement should be active"
    );

    console.log("[phase2b:cars] creating listing");
    listingId = await createListing(
      baseUrl,
      seller,
      {
        title: `Phase 2B Cars ${runTag}`,
        description: `Phase 2B cars listing ${runTag}`,
        brand: "Toyota",
        model: "Corolla",
        modelYear: 2022,
        condition: "used",
        price: 13800000,
        mileageKm: 42000,
        city: "Baghdad",
        phone: sellerPhone,
        transmission: "automatic",
        fuelType: "fuel",
        bodyType: "sedan",
        color: "White",
      },
      "cars create listing"
    );

    const requestSubmittedNotification = await expectNotification(
      {
        userId: sellerUserId,
        type: "paid_upgrade.request_submitted",
        payloadChecks: {
          requestId: String(requestId),
          planCode: "car_seller_monthly",
        },
      },
      "seller paid upgrade submitted notification"
    );
    assert.equal(
      requestSubmittedNotification.payload?.target,
      "paid_upgrades_home",
      "paid-upgrade submitted target"
    );

    const activatedNotification = await expectNotification(
      {
        userId: sellerUserId,
        type: "paid_upgrade.activated",
        payloadChecks: {
          requestId: String(requestId),
          planCode: "car_seller_monthly",
        },
      },
      "seller paid upgrade activated notification"
    );
    assert.equal(
      activatedNotification.payload?.target,
      "paid_upgrades_home",
      "paid-upgrade activation target"
    );

    const publicListing = await request(
      baseUrl,
      buyer,
      "GET",
      `/api/cars/listings/${listingId}`
    );
    assertStatus(publicListing, 200, "buyer listing detail");
    assert.equal(Number(publicListing.data?.id || 0), listingId, "buyer should see listing");
    assert.equal(
      String(publicListing.data?.status || "").toLowerCase(),
      "active",
      "published car listing should be active for buyers"
    );

    const workspace = await request(baseUrl, seller, "GET", "/api/cars/workspace");
    assertStatus(workspace, 200, "seller cars workspace");
    assert.equal(
      workspace.data?.entitlement?.carSellerMonthly,
      true,
      "seller workspace should report active car entitlement"
    );
    const workspaceListings = extractList(workspace.data);
    assert.equal(
      workspaceListings.some((item) => Number(item?.id || 0) === listingId),
      true,
      "seller workspace should contain the active listing"
    );

    console.log("[phase2b:cars] creating business thread");
    const threadResponse = await request(baseUrl, buyer, "POST", "/api/feed/chats/threads", {
      userId: sellerUserId,
      kind: "business",
      contextType: "car_listing",
      contextId: listingId,
    });
    assertStatus(threadResponse, 201, "cars business thread create");
    const thread = extractThread(threadResponse);
    const threadId = Number(thread?.id || 0);
    assert.ok(threadId > 0, "cars thread id missing");
    assert.equal(thread?.context?.type, "car_listing");
    assert.equal(Number(thread?.context?.id || 0), listingId);
    assert.equal(String(thread?.context?.status || "").toLowerCase(), "active");

    const buyerMessage = await sendMessage(
      baseUrl,
      buyer,
      threadId,
      `Interested in the car listing ${runTag}`,
      "buyer send car message"
    );
    assert.ok(buyerMessage, "buyer car message response missing");

    const sellerMessagesAfterBuyer = await listThreadMessages(
      baseUrl,
      seller,
      threadId,
      "seller list car messages after buyer send"
    );
    assert.equal(
      extractList(sellerMessagesAfterBuyer).length >= 1,
      true,
      "seller should see the buyer message"
    );

    const sellerReply = await sendMessage(
      baseUrl,
      seller,
      threadId,
      `Thanks - Phase 2B cars reply ${runTag}`,
      "seller reply car message"
    );
    assert.ok(sellerReply, "seller car reply response missing");

    const buyerMessagesAfterReply = await listThreadMessages(
      baseUrl,
      buyer,
      threadId,
      "buyer list car messages after reply"
    );
    assert.equal(
      extractList(buyerMessagesAfterReply).length >= 2,
      true,
      "buyer should see the threaded conversation"
    );

    console.log(
      `[phase2b:cars] success listingId=${listingId} requestId=${requestId} threadId=${threadId}`
    );
  } finally {
    await cleanupArtifacts({
      adminSessionId,
      superAdminId,
      sellerUserId,
      buyerUserId,
      listingId,
      requestId,
      runTag,
    });
  }
}

main().catch((error) => {
  console.error("[phase2b:cars] failed", error);
  process.exit(1);
});

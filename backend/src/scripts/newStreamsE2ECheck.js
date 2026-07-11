/* eslint-disable no-console */
import "dotenv/config";

import assert from "node:assert/strict";

import { env } from "../config/env.js";
import {
  assertStatus,
  buildPhone,
  buildRunTag,
  createActor,
  request,
} from "./e2eTestUtils.js";

const DEFAULT_BASE_URL = "https://bestoffer-production.up.railway.app";

function readToken(response, label) {
  const token = String(response?.data?.token || "").trim();
  assert.ok(token, `${label} -> missing token`);
  return token;
}

function readUserId(response, label) {
  const id = Number(response?.data?.user?.id || 0);
  assert.ok(id > 0, `${label} -> missing user id`);
  return id;
}

function findById(items, key, expectedId) {
  return (Array.isArray(items) ? items : []).find(
    (item) => Number(item?.[key] || 0) === Number(expectedId)
  );
}

function readList(data, key = "items") {
  if (Array.isArray(data)) return data;
  if (Array.isArray(data?.[key])) return data[key];
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

async function registerCustomer(actor, baseUrl, payload, label) {
  const response = await request(baseUrl, actor, "POST", "/api/auth/register", payload);
  assertStatus(response, 201, label);
  return response.data;
}

async function main() {
  const baseUrl = String(process.env.E2E_BASE_URL || DEFAULT_BASE_URL).trim();
  const runTag = buildRunTag("streams");
  const seed = Date.now() % 100000000;
  const customerPhone = buildPhone("079", seed);
  const customerPin = "4321";
  const customerName = `E2E Streams ${runTag}`;
  const listingTitle = `Real Estate ${runTag}`;

  const admin = createActor("super-admin", runTag, "e2e-new-streams/1");
  const customer = createActor("customer", runTag, "e2e-new-streams/1");

  console.log(`[e2e:new-streams] baseUrl=${baseUrl}`);
  console.log(`[e2e:new-streams] runTag=${runTag}`);

  await login(
    admin,
    baseUrl,
    env.superAdminPhone,
    env.superAdminPin,
    "super admin login"
  );
  console.log(
    `[e2e:new-streams] super admin ready -> userId=${admin.userId}, phone=${env.superAdminPhone}`
  );

  await registerCustomer(
    customer,
    baseUrl,
    {
      fullName: customerName,
      phone: customerPhone,
      pin: customerPin,
      block: "A1",
      buildingNumber: "A101",
      apartment: "101",
      analyticsConsentAccepted: true,
    },
    "customer register"
  );
  await login(customer, baseUrl, customerPhone, customerPin, "customer login");
  console.log(
    `[e2e:new-streams] customer ready -> userId=${customer.userId}, phone=${customerPhone}`
  );

  // Residence change
  const residenceBefore = await request(
    baseUrl,
    customer,
    "GET",
    "/api/feed/profile/me/residence-change"
  );
  assertStatus(residenceBefore, 200, "get current residence change state");
  assert.equal(
    residenceBefore.data?.currentSnapshot?.buildingNumber,
    "A101",
    "residence before approval should reflect registration address"
  );

  const residenceSubmit = await request(
    baseUrl,
    customer,
    "POST",
    "/api/feed/profile/me/residence-change",
    {
      block: "A1",
      buildingNumber: "A102",
      apartmentNumber: "102",
      note: `Residence update ${runTag}`,
    }
  );
  assertStatus(residenceSubmit, 201, "submit residence change request");
  const residenceRequestId = Number(residenceSubmit.data?.request?.id || 0);
  assert.ok(residenceRequestId > 0, "residence request id missing");
  console.log(
    `[e2e:new-streams] residence request submitted -> requestId=${residenceRequestId}`
  );

  const pendingResidence = await request(
    baseUrl,
    admin,
    "GET",
    "/api/admin/residence-change-requests?status=pending&limit=100"
  );
  assertStatus(pendingResidence, 200, "list pending residence change requests");
  const residenceRow = findById(
    pendingResidence.data?.items,
    "id",
    residenceRequestId
  );
  assert.ok(residenceRow, "pending residence request not visible to admin");

  const residenceApprove = await request(
    baseUrl,
    admin,
    "PATCH",
    `/api/admin/residence-change-requests/${residenceRequestId}/approve`,
    {
      reviewNote: `Approved by ${runTag}`,
    }
  );
  assertStatus(residenceApprove, 200, "approve residence change request");

  const residenceAfter = await request(
    baseUrl,
    customer,
    "GET",
    "/api/feed/profile/me/residence-change"
  );
  assertStatus(residenceAfter, 200, "get residence state after approval");
  assert.equal(
    residenceAfter.data?.currentSnapshot?.buildingNumber,
    "A102",
    "approved residence change did not update current snapshot"
  );
  assert.equal(
    String(residenceAfter.data?.request?.status || "").toLowerCase(),
    "approved",
    "approved residence request should remain visible as approved"
  );
  console.log("[e2e:new-streams] residence change workflow passed");

  // Social restrictions
  const postBeforeRestriction = await request(
    baseUrl,
    customer,
    "POST",
    "/api/feed/posts",
    {
      caption: `Baseline post before restriction ${runTag}`,
      postKind: "text",
    }
  );
  assertStatus(postBeforeRestriction, 201, "create baseline social post");
  const baselinePostId = Number(postBeforeRestriction.data?.post?.id || 0);
  assert.ok(baselinePostId > 0, "baseline post id missing");

  const restrictionCreate = await request(
    baseUrl,
    admin,
    "POST",
    `/api/admin/social-restrictions/users/${customer.userId}`,
    {
      capabilityKey: "post_create",
      reason: `E2E restrict ${runTag}`,
      endsAt: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
    }
  );
  assertStatus(restrictionCreate, 201, "create social post restriction");
  const restrictionId = Number(
    restrictionCreate.data?.restriction?.id || 0
  );
  assert.ok(restrictionId > 0, "social restriction id missing");

  const blockedPost = await request(
    baseUrl,
    customer,
    "POST",
    "/api/feed/posts",
    {
      caption: `Blocked post ${runTag}`,
      postKind: "text",
    }
  );
  assert.equal(
    blockedPost.status,
    403,
    `restricted post create should fail with 403, received ${blockedPost.status}`
  );
  console.log("[e2e:new-streams] social restriction blocked post creation as expected");

  const restrictionRevoke = await request(
    baseUrl,
    admin,
    "POST",
    `/api/admin/social-restrictions/${restrictionId}/revoke`,
    {}
  );
  assertStatus(restrictionRevoke, 200, "revoke social restriction");

  const postAfterRestriction = await request(
    baseUrl,
    customer,
    "POST",
    "/api/feed/posts",
    {
      caption: `Allowed post after revoke ${runTag}`,
      postKind: "text",
    }
  );
  assertStatus(postAfterRestriction, 201, "create post after restriction revoke");
  const allowedPostId = Number(postAfterRestriction.data?.post?.id || 0);
  assert.ok(allowedPostId > 0, "allowed post id missing");
  console.log("[e2e:new-streams] social restriction workflow passed");

  await login(
    admin,
    baseUrl,
    env.superAdminPhone,
    env.superAdminPin,
    "super admin refresh before paid upgrades"
  );

  // Paid upgrades
  const paidUpgradeCreate = await request(
    baseUrl,
    customer,
    "POST",
    "/api/paid-upgrades/requests",
    {
      planCodes: ["property_seller_monthly"],
      activityName: `Property seller ${runTag}`,
      activityDescription: "E2E property seller activation flow",
      contactPhone: customerPhone,
      notes: `Created by ${runTag}`,
    }
  );
  assertStatus(paidUpgradeCreate, 201, "create paid upgrade request");
  const paidUpgradeRequestId = Number(
    paidUpgradeCreate.data?.requests?.[0]?.id || 0
  );
  assert.ok(paidUpgradeRequestId > 0, "paid upgrade request id missing");

  const pendingUpgrades = await request(
    baseUrl,
    admin,
    "GET",
    "/api/admin/paid-upgrades/requests?status=pending_admin_review&limit=100"
  );
  assertStatus(pendingUpgrades, 200, "list pending paid upgrade requests");
  const pendingUpgradeRow = findById(
    readList(pendingUpgrades.data),
    "id",
    paidUpgradeRequestId
  );
  assert.ok(pendingUpgradeRow, "pending paid upgrade request not visible to admin");

  await login(
    admin,
    baseUrl,
    env.superAdminPhone,
    env.superAdminPin,
    "super admin refresh before paid upgrade approve"
  );

  const paidUpgradeApprove = await request(
    baseUrl,
    admin,
    "PATCH",
    `/api/admin/paid-upgrades/requests/${paidUpgradeRequestId}/approve`,
    {
      reviewNote: `Approved by ${runTag}`,
    }
  );
  assertStatus(paidUpgradeApprove, 200, "approve paid upgrade request");

  await login(
    admin,
    baseUrl,
    env.superAdminPhone,
    env.superAdminPin,
    "super admin refresh before paid upgrade activate"
  );

  const paidUpgradeActivate = await request(
    baseUrl,
    admin,
    "PATCH",
    `/api/admin/paid-upgrades/requests/${paidUpgradeRequestId}/activate`,
    {}
  );
  assertStatus(paidUpgradeActivate, 200, "activate paid upgrade request");

  const paidUpgradeSummary = await request(
    baseUrl,
    customer,
    "GET",
    "/api/paid-upgrades/me"
  );
  assertStatus(paidUpgradeSummary, 200, "get paid upgrades summary");
  assert.equal(
    paidUpgradeSummary.data?.entitlements?.propertySellerMonthly,
    true,
    "property seller entitlement should be active after activation"
  );
  console.log("[e2e:new-streams] paid upgrades workflow passed");

  await login(
    admin,
    baseUrl,
    env.superAdminPhone,
    env.superAdminPin,
    "super admin refresh before real estate"
  );

  // Real estate
  const listingCreate = await request(
    baseUrl,
    customer,
    "POST",
    "/api/real-estate/listings",
    {
      purpose: "sale",
      title: listingTitle,
      description: `E2E listing ${runTag}`,
      areaSqm: 100,
      bankSettlementAmount: 0,
      bankSettlementMode: "full",
      furnished: false,
      phone: customerPhone,
      price: 125000000,
      city: "Basmaya",
      block: "A1",
      buildingNumber: "A102",
      apartmentNumber: "102",
      detailsJson: { runTag },
    }
  );
  assertStatus(listingCreate, 201, "create real estate listing");
  const listingId = Number(listingCreate.data?.listing?.id || 0);
  assert.ok(listingId > 0, "real estate listing id missing");
  assert.equal(
    String(listingCreate.data?.listing?.status || "").toLowerCase(),
    "pending_admin_review",
    "new real estate listing should start pending"
  );

  const pendingListings = await request(
    baseUrl,
    admin,
    "GET",
    "/api/admin/real-estate/listings/pending?limit=100"
  );
  assertStatus(pendingListings, 200, "list pending real estate listings");
  const pendingListingRow = findById(
    readList(pendingListings.data),
    "id",
    listingId
  );
  assert.ok(pendingListingRow, "pending real estate listing not visible to admin");

  const listingApprove = await request(
    baseUrl,
    admin,
    "PATCH",
    `/api/admin/real-estate/listings/${listingId}/approve`,
    {
      reviewNote: `Approved by ${runTag}`,
    }
  );
  assertStatus(listingApprove, 200, "approve real estate listing");

  const workspace = await request(
    baseUrl,
    customer,
    "GET",
    "/api/real-estate/workspace"
  );
  assertStatus(workspace, 200, "get real estate workspace");
  const workspaceListing = findById(workspace.data?.listings, "id", listingId);
  assert.ok(workspaceListing, "listing missing from owner workspace");
  assert.equal(
    String(workspaceListing.status || "").toLowerCase(),
    "active",
    "approved real estate listing should be active in workspace"
  );

  const publicListings = await request(
    baseUrl,
    customer,
    "GET",
    "/api/real-estate/listings?purpose=sale&limit=100"
  );
  assertStatus(publicListings, 200, "list public real estate listings");
  const publicListing = findById(publicListings.data, "id", listingId);
  assert.ok(publicListing, "approved real estate listing not visible in marketplace");

  const archiveListing = await request(
    baseUrl,
    customer,
    "POST",
    `/api/real-estate/listings/${listingId}/mark-status`,
    {
      nextStatus: "archived",
      note: `Archived after E2E ${runTag}`,
    }
  );
  assertStatus(archiveListing, 200, "archive real estate listing after verification");
  console.log("[e2e:new-streams] real estate workflow passed");

  console.log("");
  console.log("[e2e:new-streams] SUCCESS");
  console.log(
    JSON.stringify(
      {
        runTag,
        customer: {
          userId: customer.userId,
          phone: customerPhone,
        },
        residenceRequestId,
        social: {
          baselinePostId,
          allowedPostId,
          restrictionId,
        },
        paidUpgradeRequestId,
        listingId,
      },
      null,
      2
    )
  );
}

main().catch((error) => {
  console.error("[e2e:new-streams] FAILED");
  console.error(error?.stack || error?.message || error);
  process.exitCode = 1;
});

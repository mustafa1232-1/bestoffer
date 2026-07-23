/* eslint-disable no-console */
import "dotenv/config";

import assert from "node:assert/strict";

import { app } from "../app.js";
import { ensureSchema, q } from "../config/db.js";
import { env, validateRuntimeEnv } from "../config/env.js";
import { runSqlMigrations } from "../config/sqlMigrations.js";
import {
  assertStatus,
  buildPhone,
  buildRunTag,
  createActor,
  ensureSuperAdminAccount,
  readId,
  request,
  startLocalServer,
  stopLocalServer,
} from "./e2eTestUtils.js";

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

async function getServiceCategoryPair(createdByUserId = null, seededCategoryIds = []) {
  const result = await q(
    `SELECT
       parent.id AS main_category_id,
       child.id AS subcategory_id
     FROM service_categories parent
     JOIN service_categories child ON child.parent_id = parent.id
     WHERE parent.is_active = TRUE
       AND parent.is_public = TRUE
       AND child.is_active = TRUE
       AND child.is_public = TRUE
     ORDER BY parent.sort_order ASC, child.sort_order ASC, parent.id ASC, child.id ASC
     LIMIT 1`
  );

  const first = result.rows[0] || null;
  if (first?.main_category_id && first?.subcategory_id) {
    return {
      mainCategoryId: Number(first.main_category_id),
      subcategoryId: Number(first.subcategory_id),
    };
  }

  const fallback = await q(
    `SELECT id
     FROM service_categories
     WHERE is_active = TRUE
       AND is_public = TRUE
     ORDER BY level ASC, sort_order ASC, id ASC
     LIMIT 2`
  );
  if (fallback.rows.length < 2) {
    const rootName = `Phase 2A Services Root ${buildRunTag("svc-root")}`;
    const childName = `Phase 2A Services Child ${buildRunTag("svc-child")}`;
    const rootInsert = await q(
      `INSERT INTO service_categories
        (
          parent_id,
          level,
          name,
          sort_order,
          is_active,
          is_public,
          created_by_user_id,
          created_at,
          updated_at
        )
       VALUES (NULL,1,$1,1,TRUE,TRUE,$2,NOW(),NOW())
       RETURNING id`,
      [rootName, createdByUserId == null ? null : Number(createdByUserId)]
    );
    const childInsert = await q(
      `INSERT INTO service_categories
        (
          parent_id,
          level,
          name,
          sort_order,
          is_active,
          is_public,
          created_by_user_id,
          created_at,
          updated_at
        )
       VALUES ($1,2,$2,1,TRUE,TRUE,$3,NOW(),NOW())
       RETURNING id`,
      [
        Number(rootInsert.rows[0].id),
        childName,
        createdByUserId == null ? null : Number(createdByUserId),
      ]
    );
    const rootId = Number(rootInsert.rows[0].id);
    const childId = Number(childInsert.rows[0].id);
    if (Array.isArray(seededCategoryIds)) {
      seededCategoryIds.push(childId, rootId);
    }
    return {
      mainCategoryId: rootId,
      subcategoryId: childId,
    };
  }
  return {
    mainCategoryId: Number(fallback.rows[0].id),
    subcategoryId: Number(fallback.rows[1].id),
  };
}

async function cleanupServiceArtifacts({
  adminUserId,
  providerUserId,
  customerUserId,
  requestId,
  quoteId,
  offeringId,
  subscriptionRequestId,
}) {
  const serviceUserIds = [adminUserId, providerUserId, customerUserId]
    .map((value) => Number(value))
    .filter((value) => Number.isInteger(value) && value > 0);
  const requestIds = [requestId]
    .map((value) => Number(value))
    .filter((value) => Number.isInteger(value) && value > 0);
  const quoteIds = [quoteId]
    .map((value) => Number(value))
    .filter((value) => Number.isInteger(value) && value > 0);
  const offeringIds = [offeringId]
    .map((value) => Number(value))
    .filter((value) => Number.isInteger(value) && value > 0);
  const subscriptionRequestIds = [subscriptionRequestId]
    .map((value) => Number(value))
    .filter((value) => Number.isInteger(value) && value > 0);

  if (requestIds.length) {
    await q(
      `DELETE FROM service_request_status_history
       WHERE request_id = ANY($1::bigint[])`,
      [requestIds]
    );
    await q(
      `DELETE FROM service_request_quotes
       WHERE id = ANY($1::bigint[])
          OR request_id = ANY($2::bigint[])`,
      [quoteIds, requestIds]
    );
    await q(
      `DELETE FROM service_request_attachments
       WHERE request_id = ANY($1::bigint[])`,
      [requestIds]
    );
    await q(
      `DELETE FROM service_requests
       WHERE id = ANY($1::bigint[])`,
      [requestIds]
    );
  }

  if (offeringIds.length) {
    await q(
      `DELETE FROM service_offering_media
       WHERE offering_id = ANY($1::bigint[])`,
      [offeringIds]
    );
    await q(
      `DELETE FROM service_pricing_options
       WHERE offering_id = ANY($1::bigint[])`,
      [offeringIds]
    );
    await q(
      `DELETE FROM service_offerings
       WHERE id = ANY($1::bigint[])`,
      [offeringIds]
    );
  }

  if (subscriptionRequestIds.length) {
    await q(
      `DELETE FROM service_provider_subscription_offers
       WHERE request_id = ANY($1::bigint[])`,
      [subscriptionRequestIds]
    );
    await q(
      `DELETE FROM service_provider_subscription_status_history
       WHERE request_id = ANY($1::bigint[])`,
      [subscriptionRequestIds]
    );
    await q(
      `DELETE FROM service_provider_subscription_requests
       WHERE id = ANY($1::bigint[])`,
      [subscriptionRequestIds]
    );
  }

  if (providerUserId) {
    await q(
      `DELETE FROM service_provider_profiles
       WHERE user_id = ANY($1::bigint[])`,
      [[Number(providerUserId)]]
    );
  }

  if (serviceUserIds.length) {
    await q(
      `DELETE FROM app_notification
       WHERE user_id = ANY($1::bigint[])
          OR type LIKE 'services.%'`,
      [serviceUserIds]
    );
    await q(
      `DELETE FROM app_user
       WHERE id = ANY($1::bigint[])`,
      [serviceUserIds.filter((id) => Number(id) !== Number(adminUserId))]
    );
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
  const superAdminId = await ensureSuperAdminAccount();
  const runTag = buildRunTag("services-e2e");
  const timestampSeed = Number(String(Date.now()).slice(-8));
  const admin = createActor("admin", runTag, "services-e2e/1");
  const providerActor = createActor("provider", runTag, "services-e2e/1");
  const customerActor = createActor("customer", runTag, "services-e2e/1");
  const publicActor = createActor("public", runTag, "services-e2e/1");
  const providerPhone = buildPhone("077", timestampSeed + 31);
  const customerPhone = buildPhone("078", timestampSeed + 32);
  const providerPin = "1234";
  const customerPin = "1234";
  const seededServiceCategoryIds = [];
  const categoryPair = await getServiceCategoryPair(superAdminId, seededServiceCategoryIds);

  let server = null;
  let subscriptionRequestId = null;
  let offerId = null;
  let providerUserId = null;
  let providerProfileId = null;
  let customerUserId = null;
  let offeringId = null;
  let serviceRequestId = null;
  let quoteId = null;

  try {
    const started = await startLocalServer(app);
    server = started.server;
    const { baseUrl } = started;
    console.log(`[services-e2e] baseUrl=${baseUrl} runTag=${runTag}`);

    let response = await request(baseUrl, admin, "POST", "/api/auth/login", {
      phone: env.superAdminPhone,
      pin: env.superAdminPin,
    });
    assertStatus(response, 200, "admin login");
    admin.token = String(response.data?.token || "");
    assert.equal(readId(response.data?.user), Number(superAdminId), "admin login user mismatch");

    response = await request(baseUrl, providerActor, "POST", "/api/services/provider/register", {
      fullName: `Services Provider ${runTag}`,
      businessName: `Services Provider ${runTag}`,
      phone: providerPhone,
      pin: providerPin,
      city: "Baghdad",
      area: "Bismayah",
      addressLine: "Service street 101",
      mainCategoryId: categoryPair.mainCategoryId,
      bookingPolicy: "approval_required",
      pricingMode: "mixed",
      hasEmergencyService: true,
      servesAtHome: true,
      servesAtShop: false,
      servesRemote: false,
      yearsExperience: 5,
      hasTeam: false,
      acceptsCash: true,
      acceptsElectronic: false,
      averageResponseMinutes: 20,
      available247: false,
      providerGender: "mixed",
      languages: ["ar"],
      areas: [{ city: "Baghdad", area: "Bismayah", note: "Service coverage" }],
      availabilityRules: [],
    });
    assertStatus(response, 201, "provider register");
    subscriptionRequestId = readId(response.data?.request);
    assert.ok(subscriptionRequestId, "provider subscription request id missing");
    assert.equal(String(response.data?.status || ""), "pending_offer");

    response = await request(
      baseUrl,
      admin,
      "GET",
      "/api/admin/services/subscription-requests?subscriptionRequestStatus=pending_offer&limit=20"
    );
    assertStatus(response, 200, "admin list provider subscription requests");
    assert.ok(
      Array.isArray(response.data) &&
        response.data.some(
          (item) => Number(item?.id || 0) === Number(subscriptionRequestId)
        ),
      "admin should see provider subscription request"
    );

    response = await request(
      baseUrl,
      admin,
      "POST",
      `/api/admin/services/subscription-requests/${subscriptionRequestId}/offer`,
      {
        amount: 250000,
        currency: "IQD",
        title: `Services onboarding offer ${runTag}`,
        description: "QA onboarding offer",
        validUntil: new Date(Date.now() + 48 * 60 * 60 * 1000).toISOString(),
        note: "Please review the onboarding offer",
      }
    );
    assertStatus(response, 200, "admin send subscription offer");
    assert.equal(String(response.data?.status || ""), "offer_sent");
    offerId = readId(response.data?.activeOffer);
    assert.ok(offerId, "subscription offer id missing");

    response = await request(baseUrl, providerActor, "POST", "/api/services/provider/subscription/status", {
      phone: providerPhone,
      pin: providerPin,
    });
    assertStatus(response, 200, "provider subscription status");
    assert.equal(String(response.data?.status || ""), "offer_sent");
    assert.equal(Number(response.data?.activeOffer?.id || 0), Number(offerId));

    response = await request(
      baseUrl,
      providerActor,
      "POST",
      `/api/services/provider/subscription/requests/${subscriptionRequestId}/respond-offer`,
      {
        phone: providerPhone,
        pin: providerPin,
        action: "accept",
        offerId,
      }
    );
    assertStatus(response, 200, "provider accepts subscription offer");
    assert.equal(String(response.data?.status || ""), "offer_accepted");

    response = await request(
      baseUrl,
      admin,
      "POST",
      `/api/admin/services/subscription-requests/${subscriptionRequestId}/confirm-cash-payment`,
      {
        note: "Cash onboarding confirmed for QA runtime",
      }
    );
    assertStatus(response, 200, "admin confirm cash payment");
    providerUserId = readId(response.data?.user);
    assert.ok(providerUserId, "provider user id missing after confirmation");
    assert.equal(String(response.data?.user?.role || ""), "service_provider");

    response = await request(baseUrl, providerActor, "POST", "/api/auth/login", {
      phone: providerPhone,
      pin: providerPin,
    });
    assertStatus(response, 200, "provider login");
    providerActor.token = String(response.data?.token || "");
    assert.equal(readId(response.data?.user), Number(providerUserId));
    assert.equal(String(response.data?.user?.role || ""), "service_provider");

    response = await request(baseUrl, providerActor, "GET", "/api/services/provider/workspace");
    assertStatus(response, 200, "provider workspace");
    assert.equal(Number(response.data?.provider?.userId || 0), Number(providerUserId));
    providerProfileId = Number(response.data?.provider?.id || 0);
    assert.ok(providerProfileId, "provider profile id missing from workspace");

    response = await request(baseUrl, customerActor, "POST", "/api/auth/register", {
      fullName: `Services Customer ${runTag}`,
      phone: customerPhone,
      pin: customerPin,
      block: "A1",
      buildingNumber: "A101",
      apartment: "101",
      analyticsConsentAccepted: true,
      analyticsConsentVersion: "analytics_v1",
    });
    assertStatus(response, 201, "customer register");
    customerActor.token = String(response.data?.token || "");
    customerUserId = readId(response.data?.user);
    assert.ok(customerUserId, "customer user id missing");

    response = await request(
      baseUrl,
      customerActor,
      "GET",
      "/api/services/provider/workspace"
    );
    assertStatus(response, 403, "customer forbidden from provider workspace");

    response = await request(baseUrl, providerActor, "POST", "/api/services/provider/offerings", {
      mainCategoryId: categoryPair.mainCategoryId,
      subcategoryId: categoryPair.subcategoryId,
      name: `Runtime Services Offering ${runTag}`,
      description: "Runtime offering for services closure",
      executionMode: "both",
      requiresSchedule: true,
      requiresProviderApproval: true,
      estimatedDurationMinutes: 90,
      hasFixedPrice: false,
      startsFromPrice: null,
      inspectionRequired: true,
      customQuoteOnly: false,
      workersCount: 1,
      includesText: "Service coverage",
      excludesText: "Excluded coverage",
      materialsText: "Runtime materials",
      notes: "Phase 2A services runtime offering",
      supportsHourlyBooking: false,
      supportsDailyBooking: false,
      supportsVisitBooking: true,
      supportsFullDayBooking: false,
      searchText: `Runtime Services Offering ${runTag}`,
      pricingOptions: [
        {
          pricingModel: "inspection_required",
          pricingUnit: "visit",
          label: "Inspection visit",
          visitFee: 30000,
          currency: "IQD",
          inspectionRequired: true,
          isDefault: true,
          isActive: true,
          sortOrder: 0,
        },
      ],
    });
    assertStatus(response, 201, "provider create offering");
    offeringId = readId(response.data?.offering);
    assert.ok(offeringId, "offering id missing");
    assert.equal(String(response.data?.offering?.moderationStatus || ""), "approved");

    response = await request(
      baseUrl,
      publicActor,
      "GET",
      `/api/services/public/search?q=Runtime%20Services%20Offering%20${encodeURIComponent(runTag)}&limit=20`
    );
    assertStatus(response, 200, "public search services");
    assert.ok(
      Array.isArray(response.data) &&
        response.data.some((item) => Number(item?.id || 0) === Number(offeringId)),
      "published offering should be visible in public search"
    );

    response = await request(
      baseUrl,
      publicActor,
      "GET",
      `/api/services/public/providers/${providerProfileId}`
    );
    assertStatus(response, 200, "public provider view");
    assert.equal(Number(response.data?.id || 0), Number(providerProfileId));

    response = await request(
      baseUrl,
      publicActor,
      "GET",
      `/api/services/public/offerings/${offeringId}`
    );
    assertStatus(response, 200, "public offering view");
    assert.equal(Number(response.data?.id || 0), Number(offeringId));

    response = await request(baseUrl, customerActor, "POST", "/api/services/requests", {
      offeringId,
      providerId: providerProfileId,
      requestedExecutionMode: "home",
      requestedDate: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString().slice(0, 10),
      requestedTime: "10:30",
      quantity: 2,
      durationHours: 1.5,
      notes: `Need runtime services for ${runTag}`,
      addressLine: "Customer address 1",
      city: "Baghdad",
      area: "Bismayah",
      latitude: 33.3152,
      longitude: 44.3661,
      requiresHomeService: true,
      requiresQuote: true,
    });
    assertStatus(response, 201, "customer create service request");
    serviceRequestId = readId(response.data);
    assert.ok(serviceRequestId, "service request id missing");
    assert.equal(String(response.data?.status || ""), "awaiting_provider");

    response = await request(
      baseUrl,
      providerActor,
      "GET",
      "/api/services/provider/requests?limit=20&status=awaiting_provider"
    );
    assertStatus(response, 200, "provider list requests");
    assert.ok(
      Array.isArray(response.data) &&
        response.data.some((item) => Number(item?.id || 0) === Number(serviceRequestId)),
      "provider should see the new service request"
    );

    response = await request(baseUrl, providerActor, "POST", `/api/services/provider/requests/${serviceRequestId}/quotes`, {
      pricingModel: "custom_quote",
      pricingUnit: "visit",
      amount: 45000,
      currency: "IQD",
      note: `Runtime quote for ${runTag}`,
      expiresAt: new Date(Date.now() + 48 * 60 * 60 * 1000).toISOString(),
    });
    assertStatus(response, 201, "provider create quote");
    quoteId = readId(response.data);
    assert.ok(quoteId, "quote id missing");

    response = await request(baseUrl, customerActor, "GET", "/api/services/requests/mine?limit=20");
    assertStatus(response, 200, "customer list requests");
    assert.ok(
      Array.isArray(response.data) &&
        response.data.some(
          (item) =>
            Number(item?.id || 0) === Number(serviceRequestId) &&
            Array.isArray(item?.quotes) &&
            item.quotes.some((quote) => Number(quote?.id || 0) === Number(quoteId))
        ),
      "customer should see the received quote"
    );

    response = await request(
      baseUrl,
      customerActor,
      "POST",
      `/api/services/requests/${serviceRequestId}/quotes/${quoteId}/respond`,
      {
        action: "accepted",
        note: "Accepting runtime quote",
      }
    );
    assertStatus(response, 200, "customer accept quote");
    assert.equal(String(response.data?.status || ""), "accepted");
    assert.equal(Number(response.data?.acceptedQuoteId || 0), Number(quoteId));
    assert.equal(Number(response.data?.finalPrice || 0), 45000);

    response = await request(
      baseUrl,
      providerActor,
      "POST",
      `/api/services/provider/requests/${serviceRequestId}/status`,
      {
        status: "accepted",
        note: "Provider acknowledged acceptance",
      }
    );
    assertStatus(response, 200, "provider acknowledge accepted request");
    assert.equal(String(response.data?.status || ""), "accepted");

    response = await request(
      baseUrl,
      providerActor,
      "POST",
      `/api/services/provider/requests/${serviceRequestId}/status`,
      {
        status: "in_progress",
        note: "Provider started the service",
      }
    );
    assertStatus(response, 200, "provider starts service");
    assert.equal(String(response.data?.status || ""), "in_progress");

    response = await request(
      baseUrl,
      providerActor,
      "POST",
      `/api/services/provider/requests/${serviceRequestId}/status`,
      {
        status: "completed",
        note: "Provider completed the service",
      }
    );
    assertStatus(response, 200, "provider completes service");
    assert.equal(String(response.data?.status || ""), "completed");

    response = await request(baseUrl, customerActor, "GET", `/api/services/requests/${serviceRequestId}`);
    assertStatus(response, 200, "customer gets service request detail");
    assert.equal(String(response.data?.status || ""), "completed");
    assert.equal(Number(response.data?.acceptedQuoteId || 0), Number(quoteId));
    assert.equal(Number(response.data?.finalPrice || 0), 45000);

    const customerNotifications = await q(
      `SELECT type, payload
       FROM app_notification
       WHERE user_id = $1
         AND type IN (
           'services.request.quote_received',
           'services.request.status.accepted',
           'services.request.status.in_progress',
           'services.request.status.completed'
         )
       ORDER BY id ASC`,
      [Number(customerUserId)]
    );
    assert.ok(
      customerNotifications.rows.some((row) => row.type === "services.request.quote_received"),
      "customer should receive quote notification"
    );
    assert.ok(
      customerNotifications.rows.some((row) => row.type === "services.request.status.completed"),
      "customer should receive completed notification"
    );
    assert.equal(
      customerNotifications.rows.every((row) => row.payload?.target === "service_request_details"),
      true,
      "customer notifications should deep-link to service request details"
    );

    const providerNotifications = await q(
      `SELECT type, payload
       FROM app_notification
       WHERE user_id = $1
        AND type IN (
           'services.provider.subscription.account_created',
           'services.request.created'
         )
       ORDER BY id ASC`,
      [Number(providerUserId)]
    );
    assert.ok(
      providerNotifications.rows.some((row) => row.type === "services.provider.subscription.account_created"),
      "provider should receive account creation notification"
    );
    assert.ok(
      providerNotifications.rows.some((row) => row.type === "services.request.created"),
      "provider should receive request created notification"
    );

    const adminNotifications = await q(
      `SELECT type, payload
       FROM app_notification
       WHERE user_id = $1
         AND type IN (
           'services.provider.subscription.request_submitted',
           'services.provider.subscription.offer_accepted'
         )
       ORDER BY id ASC`,
      [Number(superAdminId)]
    );
    assert.ok(
      adminNotifications.rows.some((row) => row.type === "services.provider.subscription.request_submitted"),
      "admin should receive provider subscription request notification"
    );
    assert.ok(
      adminNotifications.rows.some((row) => row.type === "services.provider.subscription.offer_accepted"),
      "admin should receive provider offer accepted notification"
    );

    response = await request(
      baseUrl,
      publicActor,
      "GET",
      `/api/services/public/search?q=${encodeURIComponent(`Runtime Services Offering ${runTag}`)}&limit=20`
    );
    assertStatus(response, 200, "public search after approval");
    assert.ok(
      Array.isArray(response.data) &&
        response.data.some((item) => Number(item?.id || 0) === Number(offeringId)),
      "public search should still expose the published offering"
    );

    console.log(
      `[services-e2e] passed subscriptionRequestId=${subscriptionRequestId} providerUserId=${providerUserId} customerUserId=${customerUserId} offeringId=${offeringId} requestId=${serviceRequestId} quoteId=${quoteId}`
    );
  } finally {
    try {
      await cleanupServiceArtifacts({
        adminUserId: superAdminId,
        providerUserId,
        customerUserId,
        requestId: serviceRequestId,
        quoteId,
        offeringId,
        subscriptionRequestId,
      });
      if (seededServiceCategoryIds.length > 0) {
        for (const categoryId of seededServiceCategoryIds) {
          await q(`DELETE FROM service_categories WHERE id = $1`, [categoryId]);
        }
      }
    } catch (cleanupError) {
      console.warn("[services-e2e] cleanup failed", cleanupError?.message || cleanupError);
    }
    await stopLocalServer(server);
  }
}

main()
  .then(() => {
    process.exit(0);
  })
  .catch((error) => {
    console.error("[services-e2e] failed", error);
    process.exit(1);
  });

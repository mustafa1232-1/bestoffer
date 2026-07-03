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
  const raw = String(process.env.E2E_SKIP_SQL_MIGRATIONS || "").trim().toLowerCase();
  return ["1", "true", "yes", "on"].includes(raw);
}

function shouldSkipEnsureSchema() {
  const raw = String(process.env.E2E_SKIP_ENSURE_SCHEMA || "").trim().toLowerCase();
  return ["1", "true", "yes", "on"].includes(raw);
}

function findById(items, id) {
  if (!Array.isArray(items)) return null;
  return items.find((item) => Number(item?.id || 0) === Number(id)) || null;
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

  const runTag = buildRunTag("jobs-e2e");
  const timestampSeed = Number(String(Date.now()).slice(-8));
  const ownerPhone = buildPhone("078", timestampSeed + 41);
  const outsiderOwnerPhone = buildPhone("078", timestampSeed + 43);
  const hrPhone = buildPhone("078", timestampSeed + 44);
  const candidatePhone = buildPhone("079", timestampSeed + 42);

  const admin = createActor("admin", runTag, "jobs-e2e/1");
  const owner = createActor("owner", runTag, "jobs-e2e/1");
  const outsiderOwner = createActor("outsider-owner", runTag, "jobs-e2e/1");
  const hr = createActor("hr", runTag, "jobs-e2e/1");
  const candidate = createActor("candidate", runTag, "jobs-e2e/1");

  let server = null;
  try {
    const started = await startLocalServer(app);
    server = started.server;
    const { baseUrl } = started;
    console.log(`[jobs-e2e] baseUrl=${baseUrl} runTag=${runTag}`);

    let response = await request(baseUrl, owner, "POST", "/api/owner/register", {
      phone: ownerPhone,
      pin: "1234",
      block: "A2",
      buildingNumber: "A201",
      apartment: "102",
      merchantName: `Jobs Merchant ${runTag}`,
      merchantType: "restaurant",
      merchantActivityType: "restaurant",
      merchantDiscoverySelectAll: true,
      merchantDescription: `merchant-desc-${runTag}`,
      merchantTagline: `merchant-tag-${runTag}`,
      merchantWorkingHours: "10:00-22:00",
      merchantServiceAreaNote: `service-area-${runTag}`,
      analyticsConsentAccepted: true,
      analyticsConsentVersion: "analytics_v1",
    });
    assertStatus(response, 201, "owner register");
    owner.token = String(response.data?.token || "");
    const ownerUserId = readId(response.data?.user);
    const merchantId = readId(response.data?.merchant);
    assert.ok(ownerUserId, "owner id missing");
    assert.ok(merchantId, "merchant id missing");

    response = await request(baseUrl, outsiderOwner, "POST", "/api/owner/register", {
      phone: outsiderOwnerPhone,
      pin: "1234",
      block: "A3",
      buildingNumber: "A301",
      apartment: "201",
      merchantName: `Jobs Merchant Outsider ${runTag}`,
      merchantType: "restaurant",
      merchantActivityType: "restaurant",
      merchantDiscoverySelectAll: true,
      merchantDescription: `merchant-outsider-desc-${runTag}`,
      merchantTagline: `merchant-outsider-tag-${runTag}`,
      merchantWorkingHours: "10:00-22:00",
      merchantServiceAreaNote: `service-area-outsider-${runTag}`,
      analyticsConsentAccepted: true,
      analyticsConsentVersion: "analytics_v1",
    });
    assertStatus(response, 201, "outsider owner register");
    outsiderOwner.token = String(response.data?.token || "");
    const outsiderOwnerUserId = readId(response.data?.user);
    const outsiderMerchantId = readId(response.data?.merchant);
    assert.ok(outsiderOwnerUserId, "outsider owner id missing");
    assert.ok(outsiderMerchantId, "outsider merchant id missing");

    response = await request(baseUrl, candidate, "POST", "/api/auth/register", {
      fullName: `Jobs Candidate ${runTag}`,
      phone: candidatePhone,
      pin: "1234",
      block: "A1",
      buildingNumber: "A101",
      apartment: "101",
      analyticsConsentAccepted: true,
      analyticsConsentVersion: "analytics_v1",
    });
    assertStatus(response, 201, "candidate register");
    candidate.token = String(response.data?.token || "");
    const candidateUserId = readId(response.data?.user);
    assert.ok(candidateUserId, "candidate id missing");

    response = await request(baseUrl, admin, "POST", "/api/auth/login", {
      phone: env.superAdminPhone,
      pin: env.superAdminPin,
    });
    assertStatus(response, 200, "admin login");
    admin.token = String(response.data?.token || "");
    const adminUserId = readId(response.data?.user);
    assert.equal(adminUserId, Number(superAdminId), "admin login user mismatch");

    response = await request(baseUrl, admin, "GET", "/api/admin/merchants/pending");
    assertStatus(response, 200, "pending merchants");
    const pendingMerchant = findById(response.data, merchantId);
    assert.ok(pendingMerchant, "owner merchant not pending");
    const pendingOutsiderMerchant = findById(response.data, outsiderMerchantId);
    assert.ok(pendingOutsiderMerchant, "outsider merchant not pending");

    response = await request(
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
    assertStatus(response, 204, "approve merchant");

    response = await request(
      baseUrl,
      admin,
      "PATCH",
      `/api/admin/merchants/${outsiderMerchantId}/approve`,
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
    assertStatus(response, 204, "approve outsider merchant");

    response = await request(
      baseUrl,
      owner,
      "POST",
      "/api/owner/merchant/financial-terms/accept"
    );
    assertStatus(response, 200, "owner accept merchant financial terms");

    response = await request(
      baseUrl,
      outsiderOwner,
      "POST",
      "/api/owner/merchant/financial-terms/accept"
    );
    assertStatus(response, 200, "outsider owner accept merchant financial terms");

    owner.token = null;
    response = await request(baseUrl, owner, "POST", "/api/auth/login", {
      phone: ownerPhone,
      pin: "1234",
    });
    assertStatus(response, 200, "owner login after approval");
    owner.token = String(response.data?.token || "");

    outsiderOwner.token = null;
    response = await request(baseUrl, outsiderOwner, "POST", "/api/auth/login", {
      phone: outsiderOwnerPhone,
      pin: "1234",
    });
    assertStatus(response, 200, "outsider owner login after approval");
    outsiderOwner.token = String(response.data?.token || "");

    response = await request(baseUrl, owner, "POST", "/api/owner/hr-staff", {
      fullName: `Jobs HR ${runTag}`,
      phone: hrPhone,
      pin: "1234",
    });
    assertStatus(response, 201, "create hr staff");
    const hrUserId = readId(response.data?.user);
    assert.ok(hrUserId, "hr user id missing");

    response = await request(baseUrl, hr, "POST", "/api/auth/login", {
      phone: hrPhone,
      pin: "1234",
    });
    assertStatus(response, 200, "hr login");
    hr.token = String(response.data?.token || "");

    response = await request(baseUrl, owner, "POST", "/api/jobs", {
      title: `Restaurant Accountant ${runTag}`,
      category: "Jobs",
      activityType: "restaurant",
      department: "accounting",
      city: "Baghdad",
      area: "Bismayah",
      description: `Hiring accountant for run ${runTag}`,
      requirements: "Restaurant accounting experience",
      responsibilities: "Daily bookkeeping and reporting",
      benefits: "Stable salary + incentives",
      workplaceType: "on_site",
      employmentType: "full_time",
      experienceLevel: "mid",
      salaryPeriod: "monthly",
      salaryCurrency: "IQD",
      salaryMin: 600000,
      salaryMax: 900000,
      vacancies: 1,
      merchantId,
      status: "active",
    });
    assertStatus(response, 201, "create job");
    const jobId = readId(response.data?.job);
    assert.ok(jobId, "job id missing");

    response = await request(baseUrl, hr, "GET", "/api/jobs/manage/mine?limit=20");
    assertStatus(response, 200, "hr managed jobs");
    assert.ok(
      Array.isArray(response.data?.items) &&
        response.data.items.some((item) => Number(item?.id || 0) === jobId),
      "hr should see owner-created job in managed jobs"
    );

    response = await request(baseUrl, hr, "PATCH", `/api/jobs/${jobId}`, {
      benefits: `Updated by HR ${runTag}`,
      requirements: "Updated requirements by hr",
    });
    assertStatus(response, 200, "hr updates owner-created job");
    assert.equal(
      String(response.data?.job?.benefits || ""),
      `Updated by HR ${runTag}`,
      "hr update should persist on owner-created job"
    );

    response = await request(baseUrl, candidate, "POST", `/api/jobs/${jobId}/apply`, {
      message: "I can handle branch accounting and reporting.",
      phone: candidatePhone,
      email: `candidate.${runTag}@example.com`,
      expectedSalary: 750000,
    });
    assertStatus(response, 201, "apply to job");
    const applicationId = readId(response.data?.application);
    assert.ok(applicationId, "application id missing");

    response = await request(
      baseUrl,
      outsiderOwner,
      "GET",
      `/api/jobs/${jobId}/applications?limit=20`
    );
    assertStatus(response, 403, "outsider owner cannot read other merchant applications");

    response = await request(
      baseUrl,
      admin,
      "POST",
      `/api/jobs/${jobId}/recommendations`,
      {
        candidateUserId,
        note: "Recommended from central talent pool",
      }
    );
    assertStatus(response, 201, "create recommendation");
    const recommendationId = readId(response.data?.recommendation);
    assert.ok(recommendationId, "recommendation id missing");

    response = await request(
      baseUrl,
      admin,
      "POST",
      `/api/jobs/${jobId}/recommendations/${recommendationId}/accept`,
      { reason: "Admin shortlisted the candidate from the talent pool." }
    );
    assertStatus(response, 200, "admin accept recommendation");
    assert.equal(
      String(response.data?.application?.status || ""),
      "shortlisted",
      "admin recommendation acceptance should shortlist the application"
    );

    response = await request(
      baseUrl,
      owner,
      "GET",
      `/api/jobs/${jobId}/applications?limit=20`
    );
    assertStatus(response, 200, "owner reads shortlisted applications");
    assert.ok(
      Array.isArray(response.data?.items) &&
        response.data.items.some(
          (item) =>
            Number(item?.id || 0) === applicationId &&
            String(item?.status || "") === "shortlisted"
        ),
      "owner should see the shortlisted application inside store applications"
    );

    const shortlistDb = await q(
      `SELECT status, status_reason
       FROM job_application
       WHERE id = $1
       LIMIT 1`,
      [Number(applicationId)]
    );
    assert.equal(
      String(shortlistDb.rows[0]?.status || ""),
      "shortlisted",
      "shortlist status persisted"
    );

    response = await request(
      baseUrl,
      hr,
      "PATCH",
      `/api/jobs/${jobId}/applications/${applicationId}/status`,
      {
        status: "hired",
        reason: "Selected for immediate onboarding",
        offerSalary: 850000,
        offerWorkHours: "09:00-17:00",
        offerWorkDays: "Sunday-Thursday",
        offerMessage: "Please review and accept this offer in-app.",
      }
    );
    assertStatus(response, 200, "hr marks application hired");
    assert.equal(
      String(response.data?.application?.status || ""),
      "hired",
      "hired status in response"
    );

    response = await request(baseUrl, owner, "GET", `/api/jobs/${jobId}`);
    assertStatus(response, 200, "owner gets job after hr hire");
    assert.equal(String(response.data?.job?.status || ""), "closed", "job auto close");

    response = await request(baseUrl, hr, "POST", "/api/jobs", {
      title: `HR Created Job ${runTag}`,
      category: "Jobs",
      activityType: "restaurant",
      department: "hr",
      city: "Baghdad",
      area: "Bismayah",
      description: `Hiring HR staff for run ${runTag}`,
      requirements: "Human resources experience",
      responsibilities: "Hiring and onboarding",
      benefits: "Stable salary + growth",
      workplaceType: "on_site",
      employmentType: "full_time",
      experienceLevel: "mid",
      salaryPeriod: "monthly",
      salaryCurrency: "IQD",
      salaryMin: 500000,
      salaryMax: 800000,
      vacancies: 1,
      merchantId,
      status: "active",
    });
    assertStatus(response, 201, "hr creates store-scoped job");
    const hrCreatedJobId = readId(response.data?.job);
    assert.ok(hrCreatedJobId, "hr created job id missing");

    response = await request(baseUrl, owner, "GET", "/api/jobs/manage/mine?limit=20");
    assertStatus(response, 200, "owner managed jobs");
    assert.ok(
      Array.isArray(response.data?.items) &&
        response.data.items.some((item) => Number(item?.id || 0) === hrCreatedJobId),
      "owner should see hr-created job in managed jobs"
    );

    response = await request(baseUrl, owner, "PATCH", `/api/jobs/${hrCreatedJobId}/status`, {
      status: "paused",
    });
    assertStatus(response, 200, "owner pauses hr-created job");
    assert.equal(
      String(response.data?.job?.status || ""),
      "paused",
      "owner should manage hr-created job status"
    );

    response = await request(
      baseUrl,
      outsiderOwner,
      "PATCH",
      `/api/jobs/${hrCreatedJobId}/status`,
      { status: "closed" }
    );
    assertStatus(response, 403, "outsider owner cannot manage foreign store job");

    response = await request(baseUrl, candidate, "GET", "/api/jobs/mine/applications");
    assertStatus(response, 200, "candidate applications list");
    const mineItem = findById(response.data?.items, applicationId);
    assert.ok(mineItem, "application not visible for candidate");
    assert.equal(String(mineItem.status || ""), "hired", "candidate sees hired status");
    assert.ok(mineItem.offerSentAt, "offer timestamp missing");

    response = await request(
      baseUrl,
      candidate,
      "POST",
      `/api/jobs/applications/${applicationId}/accept-offer`
    );
    assertStatus(response, 200, "candidate accept offer");
    const workProfile = response.data?.workProfile || {};
    assert.ok(String(workProfile.workTitle || "").trim().length > 0, "work title missing");
    assert.ok(
      String(workProfile.workCompany || "").trim().length > 0,
      "work company missing"
    );

    response = await request(baseUrl, candidate, "GET", "/api/users/me");
    assertStatus(response, 200, "candidate profile after offer");
    const workTitle = String(
      response.data?.user?.work_title || response.data?.user?.workTitle || ""
    ).trim();
    const workCompany = String(
      response.data?.user?.work_company || response.data?.user?.workCompany || ""
    ).trim();
    assert.ok(workTitle.length > 0, "profile work title not persisted");
    assert.ok(workCompany.length > 0, "profile work company not persisted");

    const notificationRows = await q(
      `SELECT type
       FROM app_notification
       WHERE user_id = $1
         AND type IN ('jobs.application.status_updated', 'jobs.application.offer_accepted')
       ORDER BY id DESC
       LIMIT 20`,
      [Number(candidateUserId)]
    );
    assert.ok(
      notificationRows.rows.some((row) => row.type === "jobs.application.status_updated"),
      "candidate status notification missing"
    );

    response = await request(
      baseUrl,
      admin,
      "GET",
      `/api/jobs/applications/monitor?jobId=${jobId}&limit=20`
    );
    assertStatus(response, 200, "admin monitor applications");
    const monitorItem = findById(
      response.data?.applications?.items,
      applicationId
    );
    assert.ok(monitorItem, "monitor list missing application");

    console.log(
      `[jobs-e2e] passed ownerJobId=${jobId} hrJobId=${hrCreatedJobId} applicationId=${applicationId} recommendationId=${recommendationId}`
    );
  } finally {
    await stopLocalServer(server);
  }
}

main()
  .then(() => {
    process.exit(0);
  })
  .catch((error) => {
    console.error("[jobs-e2e] failed", error);
    process.exit(1);
  });

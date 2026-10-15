import assert from "node:assert/strict";

import { pool } from "../config/db.js";
import { env } from "../config/env.js";
import { MASLAKI_SERVICES_OPERATOR_PHONE } from "../modules/services/services.catalog.js";
import { createActor, request } from "./e2eTestUtils.js";

const baseUrl = String(
  process.env.RUNTIME_BASE_URL || "https://bestoffer-production.up.railway.app",
).replace(/\/$/, "");
const runTag = `unique-conflict-${Date.now().toString(36)}`;
const provider = createActor("services-operator", runTag, "runtime-conflict/1");
const admin = createActor("super-admin", runTag, "runtime-conflict/1");
provider.appFlavor = "user";
admin.appFlavor = "company";

const offeringIds = [];
const sessionIds = [];

function expect(response, status, message, label) {
  assert.equal(
    response.status,
    status,
    `${label}: expected ${status}, got ${response.status} (${JSON.stringify(response.data)})`,
  );
  if (message) assert.equal(response.data?.message, message, label);
}

async function cleanup() {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    if (offeringIds.length > 0) {
      await client.query(
        `DELETE FROM service_offering_media WHERE offering_id = ANY($1::bigint[])`,
        [offeringIds],
      );
      await client.query(
        `DELETE FROM service_pricing_options WHERE offering_id = ANY($1::bigint[])`,
        [offeringIds],
      );
      await client.query(
        `DELETE FROM service_offerings WHERE id = ANY($1::bigint[])`,
        [offeringIds],
      );
    }
    if (sessionIds.length > 0) {
      await client.query(`DELETE FROM user_session WHERE id = ANY($1::bigint[])`, [
        sessionIds,
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

try {
  const category = await pool.query(
    `SELECT id
     FROM service_categories
     WHERE level = 1
       AND parent_id IS NULL
       AND is_active = TRUE
     ORDER BY sort_order ASC, id ASC
     LIMIT 1`,
  );
  const mainCategoryId = Number(category.rows[0]?.id || 0);
  assert.ok(mainCategoryId > 0, "an active service category is required");

  let response = await request(baseUrl, provider, "POST", "/api/auth/login", {
    phone: MASLAKI_SERVICES_OPERATOR_PHONE,
    pin: "199711",
  });
  expect(response, 200, null, "services operator login");
  provider.token = String(response.data?.token || "");
  if (response.data?.sessionId) sessionIds.push(Number(response.data.sessionId));

  const firstName = `Runtime conflict A ${runTag}`;
  const secondName = `Runtime conflict B ${runTag}`;
  const offeringBody = (name) => ({
    mainCategoryId,
    name,
    description: "Temporary runtime conflict verification",
    executionMode: "home",
    startsFromPrice: 5000,
    pricingOptions: [
      {
        pricingModel: "fixed_package",
        pricingUnit: "job",
        label: "للخدمة كاملة",
        amount: 5000,
        currency: "IQD",
        isDefault: true,
      },
    ],
  });

  response = await request(
    baseUrl,
    provider,
    "POST",
    "/api/services/provider/offerings",
    offeringBody(firstName),
  );
  expect(response, 201, null, "first offering create");
  offeringIds.push(Number(response.data?.offering?.id || response.data?.id));

  response = await request(
    baseUrl,
    provider,
    "POST",
    "/api/services/provider/offerings",
    offeringBody(firstName),
  );
  expect(
    response,
    409,
    "SERVICE_OFFERING_NAME_EXISTS",
    "duplicate offering create",
  );

  response = await request(
    baseUrl,
    provider,
    "POST",
    "/api/services/provider/offerings",
    offeringBody(secondName),
  );
  expect(response, 201, null, "second offering create");
  const secondOfferingId = Number(
    response.data?.offering?.id || response.data?.id,
  );
  offeringIds.push(secondOfferingId);

  response = await request(
    baseUrl,
    provider,
    "PATCH",
    `/api/services/provider/offerings/${secondOfferingId}`,
    { name: firstName },
  );
  expect(
    response,
    409,
    "SERVICE_OFFERING_NAME_EXISTS",
    "duplicate offering update",
  );

  const duplicatePhone = createActor(
    "duplicate-phone",
    runTag,
    "runtime-conflict/1",
  );
  duplicatePhone.appFlavor = "user";
  response = await request(baseUrl, duplicatePhone, "POST", "/api/auth/register", {
    fullName: "Runtime Duplicate Phone",
    phone: MASLAKI_SERVICES_OPERATOR_PHONE,
    pin: "199711",
    block: "B1",
    buildingNumber: "B101",
    apartment: "101",
    analyticsConsentAccepted: true,
    analyticsConsentVersion: "runtime_conflict_v1",
  });
  expect(response, 409, "PHONE_EXISTS", "duplicate phone registration");

  response = await request(baseUrl, admin, "POST", "/api/auth/login", {
    phone: env.superAdminPhone,
    pin: env.superAdminPin,
  });
  expect(response, 200, null, "super admin login");
  admin.token = String(response.data?.token || "");
  if (response.data?.sessionId) sessionIds.push(Number(response.data.sessionId));

  response = await request(
    baseUrl,
    admin,
    "GET",
    "/api/admin/merchants/receivables?limit=2",
  );
  expect(response, 200, null, "admin merchant receivables");

  console.log(
    JSON.stringify({
      ok: true,
      createConflictStatus: 409,
      updateConflictStatus: 409,
      duplicatePhoneStatus: 409,
      receivablesStatus: 200,
    }),
  );
} finally {
  await cleanup();
  await pool.end();
}

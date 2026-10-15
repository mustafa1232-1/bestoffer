import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test, { after } from "node:test";

import { q, pool } from "../config/db.js";
import { updateMyProfile } from "../modules/feed/feed.service.js";
import { assertSafeE2EDatabaseTarget } from "../scripts/e2eDbSafety.js";

function uniqueSuffix() {
  return randomUUID().replace(/-/g, "").slice(0, 10);
}

async function createSocialUser() {
  const suffix = uniqueSuffix();
  const result = await q(
    `INSERT INTO app_user (
       full_name,
       phone,
       pin_hash,
       block,
       building_number,
       apartment,
       role,
       username,
       is_account_disabled,
       is_super_admin
     )
     VALUES ($1, $2, 'test-pin-hash', 'A', 'A203', $3, 'user', $4, FALSE, FALSE)
     RETURNING id, username, full_name`,
    [
      `Profile User ${suffix}`,
      `077profile${suffix}`,
      `P${suffix}`,
      `profile_${suffix}`,
    ]
  );
  return result.rows[0];
}

test("social profile username updates immediately without approval request", async () => {
  assertSafeE2EDatabaseTarget({
    scriptName: "feed.profile-username.test",
    databaseUrl: process.env.DATABASE_URL || "",
    allowProductionOverride: false,
    isProduction: false,
  });

  const user = await createSocialUser();
  const nextUsername = `m.u${uniqueSuffix()}`;

  const out = await updateMyProfile(Number(user.id), {
    username: nextUsername,
  });

  assert.equal(out.profile.username, nextUsername);

  const stored = await q(
    `SELECT username FROM app_user WHERE id = $1`,
    [Number(user.id)]
  );
  assert.equal(stored.rows[0].username, nextUsername);

  const pending = await q(
    `SELECT COUNT(*)::int AS count
       FROM social_profile_change_request
      WHERE user_id = $1
        AND status = 'pending'`,
    [Number(user.id)]
  );
  assert.equal(pending.rows[0].count, 0);
});

test("username and full name update immediately without approval request", async () => {
  const user = await createSocialUser();
  const nextUsername = `m.u${uniqueSuffix()}`;
  const requestedFullName = `Updated Name ${uniqueSuffix()}`;

  const out = await updateMyProfile(Number(user.id), {
    fullName: requestedFullName,
    username: nextUsername,
  });

  assert.equal(out.profile.username, nextUsername);
  assert.equal(out.profile.fullName, requestedFullName);
  assert.equal(out.profile.coreProfileChangeRequest, null);

  const stored = await q(
    `SELECT username, full_name
       FROM app_user
      WHERE id = $1`,
    [Number(user.id)]
  );
  assert.equal(stored.rows[0].username, nextUsername);
  assert.equal(stored.rows[0].full_name, requestedFullName);

  const pending = await q(
    `SELECT COUNT(*)::int AS count
       FROM social_profile_change_request
      WHERE user_id = $1
        AND status = 'pending'`,
    [Number(user.id)]
  );
  assert.equal(pending.rows[0].count, 0);
});

test("full name update cancels older pending name request", async () => {
  const user = await createSocialUser();
  const requestedFullName = `Direct Name ${uniqueSuffix()}`;

  await q(
    `INSERT INTO social_profile_change_request
       (user_id, change_kind, status, current_snapshot_json, requested_snapshot_json)
     VALUES ($1, 'core_identity', 'pending', $2::jsonb, $3::jsonb)`,
    [
      Number(user.id),
      JSON.stringify({ fullName: user.full_name, username: user.username }),
      JSON.stringify({ fullName: `Old Pending ${uniqueSuffix()}`, username: user.username }),
    ]
  );

  const out = await updateMyProfile(Number(user.id), {
    fullName: requestedFullName,
  });

  assert.equal(out.profile.fullName, requestedFullName);
  assert.equal(out.profile.coreProfileChangeRequest, null);

  const stored = await q(
    `SELECT full_name FROM app_user WHERE id = $1`,
    [Number(user.id)]
  );
  assert.equal(stored.rows[0].full_name, requestedFullName);

  const requests = await q(
    `SELECT status
       FROM social_profile_change_request
      WHERE user_id = $1
      ORDER BY id DESC`,
    [Number(user.id)]
  );
  assert.deepEqual(
    requests.rows.map((row) => row.status),
    ["cancelled"]
  );
});

after(async () => {
  await pool.end();
});

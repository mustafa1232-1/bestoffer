/* eslint-disable no-console */
import "dotenv/config";

import assert from "node:assert/strict";

import { q } from "../config/db.js";
import { env } from "../config/env.js";
import { getSupabaseRealtimeReadiness } from "../config/supabase.js";
import {
  allowUsersOnChannel,
  revokeUserFromChannel,
  syncChatThreadMembers,
  syncOrderMembers,
  syncTaxiRideMembers,
} from "../shared/realtime/realtime-membership.js";
import { enqueueRealtimeOutbox, processRealtimeOutboxBatch } from "../shared/realtime/realtime-outbox.js";
import { publishSupabaseBroadcast } from "../shared/realtime/realtime-supabase-publisher.js";
import {
  assertStatus,
  buildRunTag,
  createActor,
  request,
} from "./e2eTestUtils.js";

const DEFAULT_BASE_URL = "https://bestoffer-production.up.railway.app";

function readString(value) {
  return String(value ?? "").trim();
}

function readPositiveInt(value) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) return null;
  return parsed;
}

async function loginSuperAdmin(baseUrl, runTag) {
  const actor = createActor("realtime-runtime-admin", runTag, "realtime-runtime/1");
  const response = await request(baseUrl, actor, "POST", "/api/auth/login", {
    phone: env.superAdminPhone,
    pin: env.superAdminPin,
  });
  assertStatus(response, 200, "super admin login");
  actor.token = readString(response.data?.token);
  actor.userId = readPositiveInt(response.data?.user?.id);
  assert.ok(actor.token, "super admin login -> missing token");
  assert.ok(actor.userId, "super admin login -> missing user id");
  return actor;
}

async function verifyRealtimeTokenEndpoint(baseUrl, actor) {
  const response = await request(baseUrl, actor, "POST", "/api/realtime/token");
  assertStatus(response, 200, "realtime token issuance");
  const data = response.data || {};
  assert.equal(readString(data.supabaseUrl).length > 0, true, "supabaseUrl missing");
  assert.equal(
    readString(data.supabaseAnonKey).length > 0,
    true,
    "supabaseAnonKey missing"
  );
  assert.equal(
    readString(data.realtimeToken).length > 20,
    true,
    "realtimeToken missing"
  );
  assert.equal(
    readPositiveInt(data.userId),
    actor.userId,
    "realtime token userId mismatch"
  );
  assert.equal(
    Number(data.expiresIn) > 0,
    true,
    "realtime token expiresIn invalid"
  );
}

async function verifyDirectBroadcastPublish(topic, runTag) {
  await publishSupabaseBroadcast(topic, "runtime_check", {
    id: runTag,
    event: "runtime_check",
    channel: topic,
    module: "runtime",
    recipientUserId: null,
    actorUserId: null,
    entityType: "runtime_check",
    entityId: null,
    createdAt: new Date().toISOString(),
    data: { runTag },
  });
}

async function readOutboxStatus(entryId) {
  const result = await q(
    `SELECT id, status, attempts, last_error
     FROM realtime_outbox
     WHERE id = $1`,
    [Number(entryId)]
  );
  return result.rows[0] || null;
}

async function waitForOutboxStatus(entryId, expectedStatus, { timeoutMs = 20000 } = {}) {
  const deadline = Date.now() + Math.max(1000, Number(timeoutMs) || 20000);
  let lastRow = null;
  while (Date.now() < deadline) {
    lastRow = await readOutboxStatus(entryId);
    if (String(lastRow?.status || "").trim().toLowerCase() === expectedStatus) {
      return lastRow;
    }
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
  return lastRow;
}

async function verifyOutboxRuntime(topic, runTag) {
  const entryId = await enqueueRealtimeOutbox({
    topic,
    event: "runtime_check",
    payload: { runTag, mode: "runtime_drain_check" },
  });
  assert.ok(entryId, "outbox entry was not created");

  const summary = await processRealtimeOutboxBatch({ limit: 25 });
  assert.equal(summary.skipped, undefined);

  const publishedRow = await waitForOutboxStatus(entryId, "published");
  assert.equal(publishedRow?.status, "published", "outbox entry did not drain");
  assert.equal(Number(publishedRow?.attempts || 0) >= 1, true, "outbox attempts were not recorded");
}

async function findLatestId(sql) {
  const result = await q(sql);
  return readPositiveInt(result.rows[0]?.id);
}

async function verifyMembershipSync(superAdminUserId, runTag) {
  const tempChannel = `admin:dashboard:runtime-${runTag}`;
  const allowResult = await allowUsersOnChannel([superAdminUserId], tempChannel, {
    replace: true,
  });
  assert.equal(allowResult.ok, true, "temp realtime membership allow failed");
  const revokeResult = await revokeUserFromChannel(superAdminUserId, tempChannel);
  assert.equal(revokeResult.ok, true, "temp realtime membership revoke failed");

  const threadId = await findLatestId(
    `SELECT thread_id AS id
     FROM social_chat_thread_member
     ORDER BY thread_id DESC
     LIMIT 1`
  );
  if (threadId) {
    const chatResult = await syncChatThreadMembers(threadId);
    assert.equal(chatResult.ok, true, "chat membership sync failed");
  } else {
    console.warn("[realtime-runtime-check] skipped chat membership sync: no thread found");
  }

  const rideId = await findLatestId(
    `SELECT id
     FROM taxi_ride_request
     ORDER BY id DESC
     LIMIT 1`
  );
  if (rideId) {
    const taxiResult = await syncTaxiRideMembers(rideId);
    assert.equal(taxiResult.ok, true, "taxi membership sync failed");
  } else {
    console.warn("[realtime-runtime-check] skipped taxi membership sync: no ride found");
  }

  const orderId = await findLatestId(
    `SELECT id
     FROM customer_order
     ORDER BY id DESC
     LIMIT 1`
  );
  if (orderId) {
    const orderResult = await syncOrderMembers(orderId);
    assert.equal(orderResult.ok, true, "order membership sync failed");
  } else {
    console.warn("[realtime-runtime-check] skipped order membership sync: no order found");
  }
}

async function verifySharedTopicMembershipIfAvailable(readiness, superAdminUserId, runTag) {
  if (readiness?.sharedTopicsReady !== true) {
    console.warn(
      `[realtime-runtime-check] shared topic membership skipped: ${readiness?.reason || "shared_topics_unavailable"}`
    );
    return;
  }
  await verifyMembershipSync(superAdminUserId, runTag);
}

async function main() {
  const baseUrl = readString(process.env.E2E_BASE_URL || DEFAULT_BASE_URL);
  const runTag = buildRunTag("realtime-runtime");

  console.log(`[realtime-runtime-check] baseUrl=${baseUrl}`);
  console.log(`[realtime-runtime-check] runTag=${runTag}`);

  const readiness = await getSupabaseRealtimeReadiness();
  assert.equal(readiness.ok, true, `realtime readiness failed: ${readiness.reason}`);
  assert.equal(
    readiness.releaseBlocking,
    false,
    `realtime readiness is release-blocking: ${readiness.reason}`
  );

  const admin = await loginSuperAdmin(baseUrl, runTag);
  await verifyRealtimeTokenEndpoint(baseUrl, admin);

  const tempTopic = `admin:dashboard:runtime:${runTag}`;
  await verifyDirectBroadcastPublish(tempTopic, runTag);
  await verifyOutboxRuntime(tempTopic, runTag);
  await verifySharedTopicMembershipIfAvailable(readiness, admin.userId, runTag);

  console.log("[realtime-runtime-check] SUCCESS");
}

main()
  .catch((error) => {
    console.error("[realtime-runtime-check] FAILED");
    console.error(error?.stack || error?.message || error);
    process.exitCode = 1;
  });

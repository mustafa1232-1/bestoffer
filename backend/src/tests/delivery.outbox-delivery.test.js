// Notification outbox truthful-delivery tests (delivery closure §1, §2, §3, §5).
//
// Uses a fake Firebase messaging (via __setFirebaseMessagingForTests) and real
// user_session/user_push_token rows so the outbox worker exercises the genuine
// createNotificationAndAwaitDelivery → dispatch path, then asserts TRUTHFUL
// outbox states (creating an app_notification is never provider acceptance).

import test from "node:test";
import assert from "node:assert/strict";
import pg from "pg";
import { drainNotificationOutbox } from "../modules/delivery/notification-outbox.worker.js";
import { __setFirebaseMessagingForTests } from "../modules/notifications/notifications.repo.js";

const MARK = "fixt_ob_";
let recipientSerial = 0;
function newClient() {
  return new pg.Client({ connectionString: process.env.DATABASE_URL });
}

function mockMessaging(responder) {
  return {
    async sendEachForMulticast(msg) {
      const responses = msg.tokens.map((t, i) => responder(t, i, msg));
      const successCount = responses.filter((r) => r.success).length;
      return { responses, successCount, failureCount: responses.length - successCount };
    },
  };
}

async function cleanup(c) {
  await c.query(`DELETE FROM notification_outbox WHERE event_id LIKE '${MARK}%'`);
  await c.query(`DELETE FROM app_notification WHERE event_id LIKE '${MARK}%'`);
  await c.query(
    `DELETE FROM user_push_token WHERE user_id IN (SELECT id FROM app_user WHERE username LIKE '${MARK}%')`
  );
  await c.query(
    `DELETE FROM user_session WHERE user_id IN (SELECT id FROM app_user WHERE username LIKE '${MARK}%')`
  );
  await c.query(`DELETE FROM app_user WHERE username LIKE '${MARK}%'`);
}

async function makeRecipient(c, { role = "delivery", surface = "delivery", tokens = ["tok1"], suffix }) {
  recipientSerial += 1;
  const uniquePhone = `0${Date.now().toString(36)}${process.pid}${recipientSerial}`.slice(0, 15);
  const uid = Number(
    (
      await c.query(
        `INSERT INTO app_user
           (full_name, phone, pin_hash, block, building_number, apartment, username, role, delivery_account_approved)
         VALUES ($1,$2,'x','A','1','1',$3,$4,$5) RETURNING id`,
        [`${MARK}u`, uniquePhone, `${MARK}${suffix}`, role, role === "delivery"]
      )
    ).rows[0].id
  );
  const sid = Number(
    (
      await c.query(
        `INSERT INTO user_session (user_id, refresh_token, expires_at)
         VALUES ($1,$2, NOW() + INTERVAL '1 day') RETURNING id`,
        [uid, `${MARK}s_${suffix}`]
      )
    ).rows[0].id
  );
  for (let i = 0; i < tokens.length; i += 1) {
    await c.query(
      `INSERT INTO user_push_token (user_id, push_token, app_surface, is_active, auth_session_id, locale)
       VALUES ($1,$2,$3,TRUE,$4,'ar')`,
      [uid, tokens[i], surface, sid]
    );
  }
  return uid;
}

async function insertOutbox(c, { eventId, recipient, targetSurface = "delivery", entityId = 1 }) {
  await c.query(
    `INSERT INTO notification_outbox
       (event_id, event_type, recipient_user_id, target_surface, target_entity_type,
        target_entity_id, payload_json, priority, status, next_attempt_at)
     VALUES ($1,'COURIER_MULTI_STORE_DELIVERY_ASSIGNED',$2,$3,'delivery_job',$4,
             $5::jsonb,'high','CREATED', NOW())`,
    [eventId, recipient, targetSurface, entityId, JSON.stringify({ numberOfStores: 2, route: "/x" })]
  );
}

async function outboxStatus(c, eventId) {
  return (
    await c.query(`SELECT status, provider_result_json, app_notification_id FROM notification_outbox WHERE event_id=$1`, [eventId])
  ).rows[0];
}
async function notifCount(c, eventId) {
  return Number(
    (await c.query(`SELECT COUNT(*)::int n FROM app_notification WHERE event_id=$1`, [eventId])).rows[0].n
  );
}

test("outbox truthful delivery semantics", async (t) => {
  const c = newClient();
  await c.connect();
  t.after(async () => {
    __setFirebaseMessagingForTests(null);
    await cleanup(c).catch(() => {});
    await c.end();
  });
  await cleanup(c);

  // 1) Firebase unavailable → PUSH_RETRY, but the app_notification IS created.
  __setFirebaseMessagingForTests(null);
  const r1 = await makeRecipient(c, { suffix: "fb", tokens: ["t_fb"] });
  await insertOutbox(c, { eventId: `${MARK}fb`, recipient: r1 });
  await drainNotificationOutbox({ limit: 50 });
  let s = await outboxStatus(c, `${MARK}fb`);
  assert.equal(s.status, "PUSH_RETRY", "firebase-unavailable is retryable, not accepted");
  assert.equal(await notifCount(c, `${MARK}fb`), 1, "app_notification created");
  assert.equal(s.provider_result_json.firebaseConfigured, false);

  // 2) No matching-surface token → PUSH_FAILED (nothing delivered), not accepted.
  __setFirebaseMessagingForTests(mockMessaging(() => ({ success: true, messageId: "m" })));
  const r2 = await makeRecipient(c, { suffix: "nt", surface: "delivery", tokens: [] });
  await insertOutbox(c, { eventId: `${MARK}nt`, recipient: r2 });
  await drainNotificationOutbox({ limit: 50 });
  s = await outboxStatus(c, `${MARK}nt`);
  assert.equal(s.status, "PUSH_FAILED", "no tokens is not acceptance");

  // 3) One success → PUSH_ACCEPTED with a truthful provider result.
  __setFirebaseMessagingForTests(mockMessaging(() => ({ success: true, messageId: "m1" })));
  const r3 = await makeRecipient(c, { suffix: "ok", tokens: ["t_ok"] });
  await insertOutbox(c, { eventId: `${MARK}ok`, recipient: r3 });
  await drainNotificationOutbox({ limit: 50 });
  s = await outboxStatus(c, `${MARK}ok`);
  assert.equal(s.status, "PUSH_ACCEPTED");
  assert.equal(s.provider_result_json.acceptedTokens, 1);
  assert.ok(Number(s.app_notification_id) > 0, "app_notification_id recorded");

  // 4) Crash-window idempotency: app_notification already exists + row stuck in
  //    NOTIFICATION_CREATED with an expired lease → recovery must NOT duplicate.
  __setFirebaseMessagingForTests(mockMessaging(() => ({ success: true, messageId: "m2" })));
  const r4 = await makeRecipient(c, { suffix: "cr", tokens: ["t_cr"] });
  await c.query(
    `INSERT INTO app_notification (user_id, type, title, body, payload, event_id)
     VALUES ($1,'delivery_grouped_assigned','t','b','{}'::jsonb,$2)`,
    [r4, `${MARK}cr`]
  );
  await c.query(
    `INSERT INTO notification_outbox
       (event_id, event_type, recipient_user_id, target_surface, target_entity_type,
        target_entity_id, payload_json, priority, status, processing_started_at, lease_expires_at)
     VALUES ($1,'COURIER_MULTI_STORE_DELIVERY_ASSIGNED',$2,'delivery','delivery_job',1,
             '{}'::jsonb,'high','NOTIFICATION_CREATED', NOW() - INTERVAL '5 min', NOW() - INTERVAL '1 min')`,
    [`${MARK}cr`, r4]
  );
  await drainNotificationOutbox({ limit: 50 });
  assert.equal(await notifCount(c, `${MARK}cr`), 1, "crash recovery does not duplicate the notification");
  s = await outboxStatus(c, `${MARK}cr`);
  assert.equal(s.status, "PUSH_ACCEPTED", "recovered row completes");

  // 5) Surface mismatch (recipient role user, event target delivery) → suppressed.
  __setFirebaseMessagingForTests(mockMessaging(() => ({ success: true, messageId: "m" })));
  const r5 = await makeRecipient(c, { suffix: "sm", role: "user", surface: "user", tokens: ["t_sm"] });
  await insertOutbox(c, { eventId: `${MARK}sm`, recipient: r5, targetSurface: "delivery" });
  await drainNotificationOutbox({ limit: 50 });
  s = await outboxStatus(c, `${MARK}sm`);
  assert.equal(s.status, "PUSH_FAILED", "wrong-surface fails closed");
  assert.equal(s.provider_result_json.suppressed, "surface_mismatch");
  assert.equal(await notifCount(c, `${MARK}sm`), 0, "no push notification for wrong surface");

  // 6) Mixed success/failure across two tokens → PUSH_PARTIAL.
  __setFirebaseMessagingForTests(
    mockMessaging((tok) =>
      tok.endsWith("A") ? { success: true, messageId: "mA" } : { success: false, error: { code: "messaging/internal-error" } }
    )
  );
  const r6 = await makeRecipient(c, { suffix: "pt", tokens: ["t_ptA", "t_ptB"] });
  await insertOutbox(c, { eventId: `${MARK}pt`, recipient: r6 });
  await drainNotificationOutbox({ limit: 50 });
  s = await outboxStatus(c, `${MARK}pt`);
  assert.equal(s.status, "PUSH_PARTIAL", "some accepted, some failed");
  assert.equal(s.provider_result_json.acceptedTokens, 1);

  // 7) Dead token only → deactivated + PUSH_FAILED (not accepted, not retried).
  __setFirebaseMessagingForTests(
    mockMessaging(() => ({ success: false, error: { code: "messaging/registration-token-not-registered" } }))
  );
  const r7 = await makeRecipient(c, { suffix: "dt", tokens: ["t_dt"] });
  await insertOutbox(c, { eventId: `${MARK}dt`, recipient: r7 });
  await drainNotificationOutbox({ limit: 50 });
  s = await outboxStatus(c, `${MARK}dt`);
  assert.equal(s.status, "PUSH_FAILED");
  assert.equal(s.provider_result_json.deadTokens, 1);
  const active = Number(
    (await c.query(`SELECT COUNT(*)::int n FROM user_push_token WHERE push_token='t_dt' AND is_active`)).rows[0].n
  );
  assert.equal(active, 0, "dead token deactivated");

  // 8) Retryable provider failure (only token) → PUSH_RETRY.
  __setFirebaseMessagingForTests(
    mockMessaging(() => ({ success: false, error: { code: "messaging/server-unavailable" } }))
  );
  const r8 = await makeRecipient(c, { suffix: "rt", tokens: ["t_rt"] });
  await insertOutbox(c, { eventId: `${MARK}rt`, recipient: r8 });
  await drainNotificationOutbox({ limit: 50 });
  s = await outboxStatus(c, `${MARK}rt`);
  assert.equal(s.status, "PUSH_RETRY", "retryable failure stays retryable");
});

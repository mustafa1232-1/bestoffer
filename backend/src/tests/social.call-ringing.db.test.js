import assert from "node:assert/strict";
import test, { after, before } from "node:test";
import { readFile } from "node:fs/promises";

import { pool, q } from "../config/db.js";
import * as repo from "../modules/feed/feed.repo.js";
import * as service from "../modules/feed/feed.service.js";
import { signCallActionToken } from "../modules/feed/feed.call-push.js";
import * as notificationsRepo from "../modules/notifications/notifications.repo.js";

const MARK = `ring${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
let caller;
let callee;
let outsider;
let threadId;

before(async () => {
  assert.match(new URL(process.env.DATABASE_URL).pathname, /\/qa_f_/);
  await q(await readFile(new URL("../../sql/232_social_call_livekit.sql", import.meta.url), "utf8"));
  const phoneBase = String(Date.now()).slice(-6);
  const users = await q(
    `INSERT INTO app_user(full_name, phone, username, pin_hash, role, block, building_number, apartment)
     SELECT (ARRAY['علي المتصل','سارة','غريب'])[i], '0779' || $2 || i, $1 || '_' || i, 'test', 'user', 'A', 'A203', '1'
     FROM generate_series(1,3) i RETURNING id`,
    [MARK, phoneBase]
  );
  [caller, callee, outsider] = users.rows.map((row) => Number(row.id));
  await q(
    `INSERT INTO social_user_relation(user_a_id, user_b_id, initiator_user_id, status)
     VALUES ($1,$2,$1,'accepted')`,
    [caller, callee]
  );
  const thread = await repo.createOrGetThread({ userAId: caller, userBId: callee });
  threadId = Number(thread.id);
});

after(() => pool.end());

async function notificationsFor(userId, type) {
  const r = await q(
    `SELECT title, body, payload FROM app_notification WHERE user_id = $1 AND type = $2 ORDER BY id`,
    [userId, type]
  );
  return r.rows;
}

test("an invite rings (push only) and a caller hang-up leaves the callee a missed call", async () => {
  const started = await service.startThreadCall({ userId: caller, threadId });
  const sessionId = Number(started.session.id);
  // The ringing invite is a transient push, not a stale inbox entry.
  assert.equal((await notificationsFor(callee, "social.call.incoming")).length, 0);

  await service.sendThreadCallSignal({
    userId: caller,
    threadId,
    dto: { sessionId, signalType: "hangup" },
  });
  const missed = await notificationsFor(callee, "social.call.missed");
  assert.equal(missed.length, 1);
  assert.equal(missed[0].title, "مكالمة فائتة من علي المتصل");
  assert.equal(missed[0].payload.target, "social_chat");
  assert.equal(Number(missed[0].payload.threadId), threadId);
  assert.equal(missed[0].payload.appSurface, "user");
});

test("Decline from the lock screen ends the call as declined via the signed token", async () => {
  const started = await service.startThreadCall({ userId: caller, threadId });
  const sessionId = Number(started.session.id);

  await assert.rejects(
    service.declineThreadCallByToken({
      token: signCallActionToken({ sessionId, calleeUserId: outsider }),
    }),
    { code: "SOCIAL_CALL_SESSION_NOT_FOUND" }
  );
  await assert.rejects(service.declineThreadCallByToken({ token: "x.y.z.w" }), {
    code: "SOCIAL_CALL_TOKEN_INVALID",
  });

  const token = signCallActionToken({ sessionId, calleeUserId: callee });
  const out = await service.declineThreadCallByToken({ token });
  assert.deepEqual(out, { declined: true, status: "declined" });
  const session = await repo.getThreadCallSessionById(sessionId);
  assert.equal(session.status, "declined");
  const signals = await repo.listThreadCallSignals(sessionId);
  assert.ok(signals.some((signal) => signal.signalType === "decline"));

  // Idempotent: the Dart side and the native side may both send it.
  const again = await service.declineThreadCallByToken({ token });
  assert.equal(again.declined, false);
  // The callee declined: no missed call for them.
  const missed = await notificationsFor(callee, "social.call.missed");
  assert.ok(missed.every((row) => Number(row.payload.sessionId) !== sessionId));
});

test("inbox and badge only show the current role's notifications", async () => {
  await notificationsRepo.createNotification({
    userId: outsider,
    type: "customer_order_status",
    title: "طلبك قيد التحضير",
    body: "الطلب #1",
    payload: { status: "preparing" },
  });
  await q(`UPDATE app_user SET role = 'delivery' WHERE id = $1`, [outsider]);
  await notificationsRepo.createNotification({
    userId: outsider,
    type: "delivery_order_assigned",
    title: "طلب توصيل جديد",
    body: "الطلب #2",
    payload: {},
  });

  const courierInbox = await notificationsRepo.listUserNotifications(outsider, {
    appSurface: "delivery",
  });
  assert.deepEqual(
    courierInbox.map((row) => row.type),
    ["delivery_order_assigned"]
  );
  assert.equal(
    await notificationsRepo.countUnreadNotifications(outsider, { appSurface: "delivery" }),
    1
  );
  const customerInbox = await notificationsRepo.listUserNotifications(outsider, {
    appSurface: "user",
  });
  assert.deepEqual(
    customerInbox.map((row) => row.type),
    ["customer_order_status"]
  );
});

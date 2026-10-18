import assert from "node:assert/strict";
import crypto from "node:crypto";
import test from "node:test";

import {
  attachNotificationI18n,
  isGenericNotificationKey,
} from "../modules/notifications/notification.i18n.js";
import { renderNotificationTextForLocale } from "../modules/notifications/notification.render.js";
import {
  __notificationsRepoTestables,
  buildNotificationAudienceMetadata,
} from "../modules/notifications/notifications.repo.js";
import { supportNotificationCopy } from "../modules/support/support.service.js";
import {
  callUuidForSession,
  signCallActionToken,
  verifyCallActionToken,
} from "../modules/feed/feed.call-push.js";
import {
  __apnsVoipTestables,
  sendVoipCallPush,
} from "../modules/notifications/apns-voip.js";

const {
  buildMulticastMessage,
  prepareNotificationInsertRow,
  resolveNotificationTarget,
  applyRecipientAudience,
  attachDeepLinkEntity,
  selectPushTargetsForSurface,
} = __notificationsRepoTestables;

function render(row, locale = "ar") {
  const payload = JSON.parse(row.payloadJson || "{}");
  return renderNotificationTextForLocale({
    locale,
    title: row.title,
    body: row.body,
    payload,
  });
}

// ---------------------------------------------------------------- content ---

test("admin notifications keep their specific title instead of 'تحديث إداري'", () => {
  const row = prepareNotificationInsertRow({
    userId: 7,
    type: "admin_support_ticket_created",
    title: "🚨 تذكرة دعم عاجلة: الطلب وصل تالف",
    body: "ST-1042 — تحتاج تدخل فوري.",
    payload: { ticketId: 1042, target: "admin_support_ticket" },
  });
  const payload = JSON.parse(row.payloadJson);
  assert.equal(payload.i18nTitleKey, undefined);
  assert.equal(payload.i18nBodyKey, undefined);
  const text = render(row);
  assert.equal(text.title, "🚨 تذكرة دعم عاجلة: الطلب وصل تالف");
  assert.equal(text.body, "ST-1042 — تحتاج تدخل فوري.");
});

test("category-level keys only fill a missing title/body", () => {
  for (const type of [
    "admin_pending_merchant",
    "hr.leave.request_created",
    "jobs.posted",
    "paid_upgrade.request_submitted",
    "company.workspace.updated",
    "social.relation.request",
    "social.report.post.created",
    "real_estate.listing.approved",
  ]) {
    const withCopy = attachNotificationI18n({
      type,
      payload: {},
      title: "عنوان محدد",
      body: "نص محدد",
    });
    assert.equal(withCopy.i18nTitleKey, undefined, type);
    assert.equal(withCopy.i18nBodyKey, undefined, type);
    const empty = attachNotificationI18n({ type, payload: {}, title: "", body: "" });
    assert.ok(isGenericNotificationKey(empty.i18nTitleKey), type);
  }
});

test("event templates with real details still localise order events", () => {
  const row = prepareNotificationInsertRow({
    userId: 7,
    type: "customer_order_status",
    title: "Order update",
    body: "",
    orderId: 123,
    payload: { status: "preparing", storeName: "مشاوي أبو علي", orderNumber: 123 },
  });
  const ar = render(row, "ar");
  assert.equal(ar.title, "طلبك قيد التحضير");
  assert.match(ar.body, /مشاوي أبو علي/);
  assert.match(ar.body, /#123/);
});

test("legacy rows stored with a generic key render the stored specific text", () => {
  const text = renderNotificationTextForLocale({
    locale: "ar",
    title: "طلب دعم جديد",
    body: "ST-9: التطبيق لا يفتح",
    payload: {
      i18nTitleKey: "notifications.admin.title",
      i18nBodyKey: "notifications.admin.body",
    },
  });
  assert.equal(text.title, "طلب دعم جديد");
  assert.equal(text.body, "ST-9: التطبيق لا يفتح");
});

test("English devices get the event's English copy (textEn)", () => {
  const row = prepareNotificationInsertRow({
    userId: 7,
    type: "admin_taxi_captain_pending_approval",
    title: "طلب حساب كابتن جديد: علي",
    body: "علي سجّل ككابتن",
    textEn: { title: "New taxi captain request: Ali", body: "Ali registered as a captain" },
    payload: {},
  });
  assert.equal(render(row, "en").title, "New taxi captain request: Ali");
  assert.equal(render(row, "ar").title, "طلب حساب كابتن جديد: علي");
});

test("chat notifications say who sent the message and keep the preview", () => {
  const row = prepareNotificationInsertRow({
    userId: 7,
    type: "social.chat.message",
    title: "رسالة جديدة من علي",
    body: "وين صرت؟",
    payload: { threadId: 5, remoteDisplayName: "علي", target: "social_chat" },
  });
  const text = render(row);
  assert.equal(text.title, "رسالة جديدة من علي");
  assert.equal(text.body, "وين صرت؟");
});

test("support copy always names the ticket and its subject", () => {
  const ticket = {
    id: 1042,
    ticket_number: "ST-1042",
    subject: "الطلب وصل تالف",
    priority: "urgent",
  };
  const urgent = supportNotificationCopy("new_ticket", ticket);
  assert.equal(urgent.title, "🚨 تذكرة دعم عاجلة: الطلب وصل تالف");
  assert.match(urgent.body, /ST-1042/);
  assert.match(urgent.textEn.title, /Urgent support ticket/);
  for (const kind of [
    "assigned",
    "customer_reply",
    "agent_reply",
    "agent_joined",
    "status_changed",
    "resolved",
    "reopened",
    "escalated",
    "sla_warning",
    "sla_breached",
    "callback_scheduled",
  ]) {
    const copy = supportNotificationCopy(kind, { ...ticket, priority: "normal" }, {
      message: "شكراً",
      status: "RESOLVED",
      team: "orders_l2",
      rating: 5,
    });
    assert.ok(copy.title.includes("ST-1042"), kind);
    assert.ok(copy.body.trim().length > 0, kind);
    assert.ok(!/^Ticket\b/.test(copy.title), `${kind} must be Arabic first`);
    assert.ok(copy.textEn.title.includes("ST-1042"), kind);
  }
});

// ---------------------------------------------------------------- deep links ---

test("every notification carries the entity it is about", () => {
  const cases = [
    [{ ticketId: 9 }, "support_ticket", 9],
    [{ orderId: 12 }, "order", 12],
    [{ rideId: 33 }, "taxi_ride", 33],
    [{ threadId: 44 }, "social_thread", 44],
    [{ postId: 55 }, "social_post", 55],
  ];
  for (const [payload, entity, id] of cases) {
    const out = attachDeepLinkEntity({ ...payload });
    assert.equal(out.targetEntity, entity);
    assert.equal(out.entityId, id);
  }
  const explicit = attachDeepLinkEntity({ targetEntity: "competition", entityId: 3, orderId: 4 });
  assert.equal(explicit.targetEntity, "competition");
  assert.equal(explicit.entityId, 3);
});

test("support and Mimo escalations open the ticket, not the notifications list", () => {
  assert.equal(
    resolveNotificationTarget({ type: "support.mimo.escalation", payload: {} }, null),
    "support_ticket"
  );
  assert.equal(
    resolveNotificationTarget({ type: "support.ticket.agent_reply", payload: {} }, null),
    "support_ticket"
  );
  const row = prepareNotificationInsertRow({
    userId: 1,
    type: "support.mimo.escalation",
    title: "🚨 تذكرة دعم عاجلة: x",
    body: "ST-1 — x",
    payload: { ticketId: 1, target: "admin_support_ticket" },
  });
  const payload = JSON.parse(row.payloadJson);
  assert.equal(payload.target, "admin_support_ticket");
  assert.equal(payload.entityId, 1);
});

test("social reports go to admin review; moderation results go to the content", () => {
  assert.equal(
    resolveNotificationTarget({ type: "social.report.story.created", payload: {} }, null),
    "admin_social_reports"
  );
  assert.equal(
    resolveNotificationTarget({ type: "social.report.post.deleted", payload: {} }, null),
    "social_post"
  );
  assert.equal(
    resolveNotificationTarget({ type: "social.report.story.edit_requested", payload: {} }, null),
    "social_story"
  );
});

// ---------------------------------------------------------------- role isolation ---

test("recipient role rewrites conflicting role hints (no cross-app routing)", () => {
  const owner = buildNotificationAudienceMetadata("owner");
  const payload = applyRecipientAudience(
    { roleScope: "customer", targetModule: "customer", target: "support_ticket" },
    owner
  );
  assert.equal(payload.appSurface, "store");
  assert.equal(payload.roleScope, "merchant");
  assert.equal(payload.targetModule, "merchant");
  assert.equal(payload.target, "support_ticket");

  const admin = buildNotificationAudienceMetadata("super_admin");
  const adminPayload = applyRecipientAudience(
    { roleScope: "customer", target: "support_ticket" },
    admin
  );
  assert.equal(adminPayload.appSurface, "company");
  assert.equal(adminPayload.roleScope, "admin");
  assert.equal(adminPayload.target, "admin_support_ticket");

  const customer = buildNotificationAudienceMetadata("user");
  const customerPayload = applyRecipientAudience(
    { roleScope: "admin", target: "admin_support_ticket" },
    customer
  );
  assert.equal(customerPayload.appSurface, "user");
  assert.equal(customerPayload.roleScope, "customer");
  assert.equal(customerPayload.target, "support_ticket");
});

test("HR and accountant recipients get their own module instead of 'admin'", () => {
  assert.deepEqual(buildNotificationAudienceMetadata("hr"), {
    appSurface: "company",
    roleScope: "hr",
    targetModule: "hr",
  });
  assert.equal(buildNotificationAudienceMetadata("accountant").targetModule, "accountant");
  assert.equal(buildNotificationAudienceMetadata("admin").roleScope, "admin");
});

test("a token registered for another app surface never receives the push", () => {
  const notification = { payload: { appSurface: "delivery" } };
  const selected = selectPushTargetsForSurface(notification, [
    { token: "user-app", appSurface: "user", recipientSurface: "delivery" },
    { token: "courier-app", appSurface: "delivery", recipientSurface: "delivery" },
  ]);
  assert.deepEqual(
    selected.targets.map((target) => target.token),
    ["courier-app"]
  );
  const switched = selectPushTargetsForSurface(
    { payload: { appSurface: "user" } },
    [{ token: "t", appSurface: "user", recipientSurface: "delivery" }]
  );
  assert.equal(switched.targets.length, 0);
  assert.equal(switched.suppressed, "recipient_surface_mismatch");
});

// ---------------------------------------------------------------- calls ---

test("call invites are data-only, high priority and carry the native call fields", () => {
  const message = buildMulticastMessage(
    {
      id: null,
      type: "social.call.incoming",
      title: "مكالمة واردة من علي",
      body: "مكالمة صوتية",
      payload: {
        threadId: 5,
        sessionId: 77,
        target: "social_call",
        callUuid: callUuidForSession(77),
        callerName: "علي",
        callActionToken: "tok",
        callExpiresAt: "2026-10-18T10:00:00.000Z",
      },
    },
    ["t1"],
    null,
    { title: "مكالمة واردة من علي", body: "مكالمة صوتية" },
    "user"
  );
  assert.equal(message.notification, undefined);
  assert.equal(message.android.notification, undefined);
  assert.equal(message.android.priority, "high");
  assert.equal(message.data.type, "social.call.incoming");
  assert.equal(message.data.callActionToken, "tok");
  assert.equal(message.data.callerName, "علي");
  assert.equal(message.data.callUuid, callUuidForSession(77));
  assert.equal(message.android.collapseKey, "social-call:77");
});

test("missed calls are ordinary tray notifications that never ring", () => {
  const message = buildMulticastMessage(
    {
      id: 1,
      type: "social.call.missed",
      title: "مكالمة فائتة من علي",
      body: "اضغط لفتح المحادثة",
      payload: { threadId: 5, sessionId: 77, target: "social_chat" },
    },
    ["t1"],
    null,
    { title: "مكالمة فائتة من علي", body: "اضغط لفتح المحادثة" },
    "user"
  );
  assert.equal(message.notification.title, "مكالمة فائتة من علي");
  assert.ok(message.android.notification);
});

test("call-ended pushes are silent dismissals", () => {
  const message = buildMulticastMessage(
    {
      id: null,
      type: "social.call.ended",
      title: "انتهت المكالمة",
      body: "",
      payload: { threadId: 5, sessionId: 77, target: "social_call" },
    },
    ["t1"],
    null,
    { title: "انتهت المكالمة", body: "" },
    "user"
  );
  assert.equal(message.notification, undefined);
  assert.equal(message.apns.headers["apns-push-type"], "background");
  assert.equal(message.apns.payload.aps.alert, undefined);
  assert.equal(message.android.collapseKey, "social-call:77");
});

test("call decline token is signed, scoped to the callee and expires", () => {
  const now = Date.now();
  const token = signCallActionToken({ sessionId: 77, calleeUserId: 9, ttlSeconds: 60, now });
  assert.deepEqual(
    { ...verifyCallActionToken(token, { now }), exp: undefined },
    { sessionId: 77, calleeUserId: 9, exp: undefined }
  );
  const [s, c, e, sig] = token.split(".");
  assert.equal(verifyCallActionToken(`${s}.${Number(c) + 1}.${e}.${sig}`, { now }), null);
  assert.equal(verifyCallActionToken(token, { now: now + 61_000 }), null);
  assert.equal(verifyCallActionToken("garbage", { now }), null);
});

test("CallKit UUID per session matches the app's format", () => {
  assert.equal(callUuidForSession(77), "5a17ca11-0000-4000-8000-00000000004d");
  assert.match(callUuidForSession(123456789), /^5a17ca11-0000-4000-8000-[0-9a-f]{12}$/);
});

test("iOS VoIP pushes use PushKit topic, voip type and drop dead tokens", async () => {
  const { privateKey } = crypto.generateKeyPairSync("ec", { namedCurve: "P-256" });
  const saved = { ...process.env };
  process.env.APNS_KEY_ID = "ABC123DEFG";
  process.env.APNS_TEAM_ID = "TEAM123456";
  process.env.APNS_PRIVATE_KEY = privateKey.export({ type: "pkcs8", format: "pem" });
  process.env.APNS_BUNDLE_ID = "com.maslaki.user";
  const requests = [];
  __apnsVoipTestables.setTransport(async (req) => {
    requests.push(req);
    return req.path.endsWith("/dead")
      ? { status: 410, reason: "Unregistered" }
      : { status: 200, reason: null };
  });
  try {
    const result = await sendVoipCallPush({
      tokens: ["live", "dead"],
      callPayload: { id: callUuidForSession(77), nameCaller: "علي", extra: { sessionId: 77 } },
    });
    assert.equal(result.accepted, 1);
    assert.deepEqual(result.deadTokens, ["dead"]);
    assert.equal(requests[0].headers["apns-topic"], "com.maslaki.user.voip");
    assert.equal(requests[0].headers["apns-push-type"], "voip");
    assert.match(requests[0].headers.authorization, /^bearer [\w-]+\.[\w-]+\.[\w-]+$/);
    assert.equal(requests[0].body.nameCaller, "علي");
  } finally {
    __apnsVoipTestables.setTransport(null);
    for (const key of ["APNS_KEY_ID", "APNS_TEAM_ID", "APNS_PRIVATE_KEY", "APNS_BUNDLE_ID"]) {
      if (saved[key] === undefined) delete process.env[key];
      else process.env[key] = saved[key];
    }
  }
});

test("VoIP sender is a no-op without APNs keys", async () => {
  const saved = process.env.APNS_KEY_ID;
  delete process.env.APNS_KEY_ID;
  try {
    const result = await sendVoipCallPush({ tokens: ["x"], callPayload: { id: "1" } });
    assert.equal(result.configured, false);
    assert.equal(result.accepted, 0);
  } finally {
    if (saved !== undefined) process.env.APNS_KEY_ID = saved;
  }
});

import assert from "node:assert/strict";
import test from "node:test";

import { findGuide } from "../modules/mimo/mimo.appguide.js";
import { diagnose, escalate, learnPlaybook, ticketsStatus } from "../modules/mimo/mimo.support.js";
import { agreedToEscalate, createMimoToolbox } from "../modules/mimo/mimo.tools.js";

const NOW = new Date("2026-10-18T12:00:00Z").getTime();
const minsAgo = (m) => new Date(NOW - m * 60000).toISOString();

function supportDeps(overrides = {}) {
  const calls = { tickets: [], notes: [], notified: [], playbooks: [] };
  const deps = {
    calls,
    async account() {
      return { id: 7, full_name: "مصطفى", is_account_disabled: false, locked_until: null };
    },
    async recentOrders() {
      return [
        { id: 901, status: "pending", merchant_name: "برونتو", created_at: minsAgo(35) },
        { id: 900, status: "completed", merchant_name: "أبو علي", created_at: minsAgo(3000) },
      ];
    },
    async currentRide() {
      return null;
    },
    async counts() {
      return { addresses: 1, pushTokens: 0 };
    },
    async myTickets() {
      return [];
    },
    async lastAgentMessage() {
      return { body: "كلمنا المحل وراح يطلع طلبك هسه" };
    },
    async createTicket(input) {
      calls.tickets.push(input);
      return { id: 55, ticket_number: "SUP-55", assigned_user_id: 3, sla: { firstResponseDueAt: "x" } };
    },
    async addMimoNote(ticketId, body) {
      calls.notes.push({ ticketId, body });
    },
    async admins() {
      return [1, 2];
    },
    async notify(p) {
      calls.notified.push(p);
    },
    async realtime() {},
    async ticketTranscript() {
      return {
        ticket: { id: 55, ticket_number: "SUP-55", subject: "🤖 ميمو: الطلب ما يتحرك", description: "طلبي معلگ", channel: "mimo", resolution_summary: "المحل ما شاف الطلب، اتصلنا بيه" },
        messages: [{ author_role: "customer", body: "طلبي من ساعة" }, { author_role: "agent", body: "اتصلنا بالمحل" }],
        notes: [{ author_role: "mimo", body: "عمو مشكلة" }],
      };
    },
    async savePlaybook(row) {
      calls.playbooks.push(row);
    },
    ...overrides,
  };
  return deps;
}

test("diagnose spots a stuck order and missing push registration", async () => {
  const out = await diagnose(supportDeps(), 7, { clientInfo: { platform: "android", appVersion: "4.2", online: true }, now: NOW });
  assert.equal(out.activeOrders.length, 1);
  assert.equal(out.activeOrders[0].meaning, "بانتظار موافقة المحل");
  assert.equal(out.activeOrders[0].minutesAgo, 35);
  assert.ok(out.findings.some((f) => /901 still waiting for the store after 35/.test(f)));
  assert.ok(out.findings.some((f) => /push notifications/.test(f)));
  assert.equal(out.device.platform, "android");
});

test("escalation needs the user's OK", () => {
  assert.equal(agreedToEscalate("طلبي ما وصل", "هلا"), false);
  assert.equal(agreedToEscalate("إي ارفعها", "أرفعها للإدارة؟"), true);
  assert.equal(agreedToEscalate("اريد احچي ويه الدعم", ""), true);
  assert.equal(agreedToEscalate("اي", "شنو تريد تاكل؟"), false);
});

test("escalate opens a mimo ticket, writes 'عمو مشكلة' and alerts admins", async () => {
  const deps = supportDeps();
  const out = await escalate(deps, 7, {
    domain: "delivery",
    problem: "الطلب 901 من ساعة ما انقبل",
    stepsTried: ["شفنا حالة الطلب", "حاولنا نتواصل ويه المحل"],
    urgency: "urgent",
    orderId: 901,
    userName: "مصطفى",
  });
  const t = deps.calls.tickets[0];
  assert.equal(t.channel, "mimo");
  assert.equal(t.priority, "urgent");
  assert.equal(t.domain, "DELIVERY");
  assert.equal(t.entityType, "order");
  assert.match(deps.calls.notes[0].body, /عمو مشكلة/);
  assert.match(deps.calls.notes[0].body, /مصطفى/);
  assert.match(deps.calls.notes[0].body, /• حاولنا نتواصل ويه المحل/);
  // Admins 1, 2 + the auto-assigned agent 3.
  assert.deepEqual(deps.calls.notified.map((n) => n.userId).sort(), [1, 2, 3]);
  assert.equal(deps.calls.notified[0].type, "support.mimo.escalation");
  assert.match(deps.calls.notified[0].title, /فوراً/);
  assert.equal(out.ticketNumber, "SUP-55");
});

test("toolbox asks before escalating and never opens duplicate tickets", async () => {
  const deps = supportDeps({
    async myTickets() {
      return [{ id: 40, ticket_number: "SUP-40", status: "ASSIGNED", channel: "mimo" }];
    },
  });
  const box = createMimoToolbox({ userId: 7, deps: {}, supportDeps: deps });
  box.setUserMessage("طلبي ما وصل", "هلا");
  const ask = await box.run("escalate_to_admin", { domain: "DELIVERY", problem: "x" });
  assert.equal(ask.reason, "NEEDS_USER_OK");
  box.setUserMessage("إي ارفعها", "أرفعها للإدارة؟");
  const out = await box.run("escalate_to_admin", { domain: "DELIVERY", problem: "بعده ما وصل" });
  assert.equal(out.existingTicket, true);
  assert.equal(deps.calls.tickets.length, 0, "reused the open ticket");
  assert.match(deps.calls.notes[0].body, /تحديث من ميمو/);
  const ui = await box.display("respond", { text: "رفعتها", mood: "happy" });
  assert.equal(ui[0].type, "ticket");
  assert.equal(ui[0].ticketNumber, "SUP-40");
});

test("ticket status relays the support team's latest reply", async () => {
  const deps = supportDeps({
    async myTickets() {
      return [{ id: 55, ticket_number: "SUP-55", status: "IN_PROGRESS", subject: "🤖 ميمو: طلب", channel: "mimo" }];
    },
  });
  const out = await ticketsStatus(deps, 7);
  assert.equal(out[0].lastSupportReply, "كلمنا المحل وراح يطلع طلبك هسه");
  assert.equal(out[0].fromMimo, true);
});

test("a resolved ticket becomes a playbook Mimo can reuse", async () => {
  const deps = supportDeps();
  const llm = {
    async complete({ messages }) {
      assert.match(messages[1].content, /اتصلنا بالمحل/);
      assert.doesNotMatch(messages[1].content, /\[internal mimo\]/, "Mimo's own notes are not learned from");
      return {
        content: JSON.stringify({
          problem: "طلبي من مدة طويلة بانتظار موافقة المحل",
          solution: "إذا الطلب بقى بانتظار المحل أكثر من 20 دقيقة، نبلغ الدعم يتصلون بالمحل",
          self_service: false,
          topic: "orders",
        }),
      };
    },
  };
  const out = await learnPlaybook(deps, llm, { ticketId: 55 });
  assert.equal(out.learned, true);
  const pb = deps.calls.playbooks[0];
  assert.match(pb.question_key, /^support:/);
  assert.equal(pb.topic, "support:orders");
  assert.match(pb.answer, /يحلها فريق الدعم/);
  assert.equal(pb.evidence[0].ticketId, 55);
});

test("app guide answers how-to questions with the real rules", () => {
  const cancel = findGuide("شلون الغي طلبي؟");
  assert.equal(cancel[0].id, "order_cancel");
  assert.match(cancel[0].how, /يدوّر مندوب/);
  assert.equal(findGuide("نسيت الرمز ما اگدر ادخل")[0].id, "pin_reset");
  assert.equal(findGuide("ما توصلني اشعارات")[0].id, "notifications_fix");
});

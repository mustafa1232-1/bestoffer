import assert from "node:assert/strict";
import test from "node:test";

import { safeAttachments } from "../modules/mimo/mimo.controller.js";
import { buildDashboard, estimateCost, priceTable } from "../modules/mimo/mimo.dashboard.js";
import { meterLlm } from "../modules/mimo/mimo.llm.js";
import { pickNudge } from "../modules/mimo/mimo.proactive.js";
import { escalate } from "../modules/mimo/mimo.support.js";

test("cost estimate uses per-model prices and web search fees", () => {
  const prices = priceTable({ MIMO_PRICES: '{"gpt-4.1":{"in":2,"out":8}}', MIMO_WEB_SEARCH_USD: "0.01" });
  const usd = estimateCost(
    [
      { model: "gpt-4.1-2025-04-14", inputTokens: 10000, outputTokens: 500 },
      { model: "gpt-5.4-mini", inputTokens: 2000, outputTokens: 300, webSearch: true },
    ],
    prices
  );
  // 0.02 + 0.004 + (0.0005 + 0.0006) + 0.01
  assert.equal(usd, 0.0351);
});

test("the metered llm records every call's usage", async () => {
  const base = {
    async chat({ onUsage }) {
      onUsage({ model: "gpt-4.1", inputTokens: 100, outputTokens: 20, kind: "chat" });
      return { content: "", toolCalls: [] };
    },
    async complete({ onUsage }) {
      onUsage({ model: "gpt-5.4-mini", inputTokens: 50, outputTokens: 10, webSearch: true });
      return { content: "x" };
    },
  };
  const m = meterLlm(base);
  await m.llm.chat({ messages: [] });
  await m.llm.complete({ kind: "search", messages: [] });
  assert.equal(m.calls.length, 2);
  assert.equal(m.calls[1].webSearch, true);
});

test("dashboard turns raw rows into clear KPIs", async () => {
  const deps = {
    async kpis() {
      return {
        q: { questions: 200, users: 40 },
        fb: [{ kind: "feedback_up", n: 45 }, { kind: "feedback_down", n: 5 }],
        usage: { replies: 200, cost_usd: 3.5, avg_ms: 3200, input_tokens: 900000, output_tokens: 60000 },
        tickets: [{ status: "RESOLVED", n: 6 }, { status: "ASSIGNED", n: 2 }],
        know: [{ status: "verified", n: 12, playbooks: 4 }, { status: "community", n: 3, playbooks: 0 }],
        carts: 31,
        pro: [{ kind: "proactive_shown", n: 80 }, { kind: "proactive_tapped", n: 12 }],
      };
    },
    async daily() {
      return [{ day: "2026-10-18", questions: 20, users: 9, cost_usd: 0.4 }];
    },
    async tools() {
      return [{ tool: "search_products", n: 70 }];
    },
    async badAnswers() {
      return [{ id: 1, question: "q", answer: "a", reason: "" }];
    },
    async demand() {
      return { unmet: [{ text: "شاورما", times: 14 }], misses: [], synonyms: [] };
    },
    async tickets() {
      return [];
    },
  };
  const out = await buildDashboard(deps, { days: 7 });
  assert.equal(out.days, 7);
  assert.equal(out.kpis.satisfaction, 90);
  assert.equal(out.kpis.avgReplySeconds, 3.2);
  assert.equal(out.kpis.costPerQuestionUsd, 0.0175);
  assert.equal(out.kpis.escalations, 8);
  assert.equal(out.kpis.escalationsOpen, 2);
  assert.equal(out.kpis.playbooks, 4);
  assert.equal(out.kpis.learnedVerified, 12);
  assert.equal(out.kpis.nudgesTapped, 12);
  assert.equal(out.demand.unmet[0].text, "شاورما");
});

function nudgeDeps({ orders = [], coupons = [] } = {}) {
  return {
    async orders() {
      return orders;
    },
    async coupons() {
      return coupons;
    },
    async name() {
      return "مصطفى";
    },
  };
}

// Thursday 2026-10-15 20:00 Baghdad = 17:00 UTC.
const THURSDAY_EVENING = new Date("2026-10-15T17:00:00Z");
const pastThursday = (weeksAgo) =>
  new Date(THURSDAY_EVENING.getTime() - weeksAgo * 7 * 86400000).toISOString();

test("habit nudge: usual Thursday evening order from the favorite store", async () => {
  const orders = [1, 2, 3].map((w) => ({
    id: w,
    merchant_id: 101,
    merchant_name: "مشاوي أبو علي",
    status: "completed",
    total_amount: 20000,
    created_at: pastThursday(w),
    items: [{ product_id: 9, product_name: "كباب", quantity: 1 }],
  }));
  const n = await pickNudge(nudgeDeps({ orders }), 7, { now: THURSDAY_EVENING });
  assert.equal(n.kind, "habit");
  assert.match(n.text, /مصطفى، الخميس سعيد/);
  assert.match(n.action.message, /نفس طلبي من مشاوي أبو علي/);
});

test("no nudge while an order is in progress; coupon nudge when one is expiring", async () => {
  const busy = await pickNudge(
    nudgeDeps({ orders: [{ id: 1, status: "preparing", created_at: new Date().toISOString() }] }),
    7,
    { now: THURSDAY_EVENING }
  );
  assert.equal(busy, null);
  const coupon = await pickNudge(
    nudgeDeps({
      coupons: [{ code: "MIMO10", discount_type: "percent", discount_value: 10, valid_until: new Date(THURSDAY_EVENING.getTime() + 10 * 3600000).toISOString() }],
    }),
    7,
    { now: THURSDAY_EVENING }
  );
  assert.equal(coupon.kind, "coupon");
  assert.match(coupon.text, /MIMO10 خصم 10% يخلص اليوم/);
  assert.equal(coupon.action.section, "offers");
});

test("only our own uploaded images are accepted as chat attachments", () => {
  const out = safeAttachments(
    [
      { fileUrl: "/uploads/chat/a.jpg", mimeType: "image/jpeg" },
      { fileUrl: "javascript:alert(1)" },
      { fileUrl: "https://cdn.example.com/x.png", mimeType: "image/png" },
      { fileUrl: "https://evil.example.net/uploads/x.png", mimeType: "image/png" },
      { fileUrl: "/uploads/doc.pdf", mimeType: "application/pdf" },
    ],
    new Set(["cdn.example.com"])
  );
  assert.deepEqual(out.map((a) => a.fileUrl), ["/uploads/chat/a.jpg", "https://cdn.example.com/x.png"]);
});

test("escalation attaches the user's photos to the ticket", async () => {
  const created = [];
  const notes = [];
  await escalate(
    {
      async createTicket(t) {
        created.push(t);
        return { id: 9, ticket_number: "SUP-9" };
      },
      async addMimoNote(_id, body) {
        notes.push(body);
      },
      async admins() {
        return [];
      },
      async notify() {},
      async realtime() {},
    },
    7,
    { domain: "DELIVERY", problem: "الطلب وصل تالف", attachments: [{ fileUrl: "/uploads/a.jpg", mimeType: "image/jpeg" }] }
  );
  assert.equal(created[0].attachments[0].fileUrl, "/uploads/a.jpg");
  assert.match(notes[0], /أرفق 1 صورة/);
});

test("directory maps every store and service with its place, rating and orders", async () => {
  const { loadDirectory, __resetDirectoryCache } = await import("../modules/mimo/mimo.directory.js");
  __resetDirectoryCache();
  let calls = 0;
  const deps = {
    async stores() {
      calls += 1;
      return [
        {
          id: 1, name: "مشاوي أبو علي", type: "restaurant", activity_type: "restaurant",
          avg_merchant_rating: "4.7", rating_count: 120, completed_orders_count: 420,
          is_open: true, service_area_note: "بسماية - بلوك A5", latitude: 33.2, longitude: 44.6,
        },
        { id: 2, name: "", type: "market" },
      ];
    },
    async services() {
      return [
        { id: 9, name: "تصليح سبالت", mainCategoryName: "تبريد", ratingAvg: 4.9, ratingCount: 30,
          completedOrdersCount: 51, provider: { businessName: "أبو حسين للتبريد", area: "B3", city: "بسماية" } },
        { id: 10, name: "موقوف", isTemporarilyPaused: true, provider: {} },
      ];
    },
  };
  const d = await loadDirectory(deps, { now: 1000 });
  assert.equal(d.stores.length, 1);
  assert.deepEqual(
    { name: d.stores[0].name, rating: d.stores[0].rating, orders: d.stores[0].orders, area: d.stores[0].area },
    { name: "مشاوي أبو علي", rating: 4.7, orders: 420, area: "بسماية - بلوك A5" }
  );
  assert.equal(d.services.length, 1);
  assert.equal(d.services[0].provider, "أبو حسين للتبريد");
  assert.equal(d.services[0].area, "B3، بسماية");
  await loadDirectory(deps, { now: 30_000 });
  assert.equal(calls, 1, "cached for a minute");
});

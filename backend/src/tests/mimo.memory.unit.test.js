import assert from "node:assert/strict";
import test from "node:test";

import { runMimoTurn } from "../modules/mimo/mimo.agent.js";
import {
  buildTasteProfile,
  forgetFact,
  isSafeMemory,
  learnFromTurn,
  loadMimoMemory,
  memoryPromptSection,
  rememberFact,
} from "../modules/mimo/mimo.memory.js";
import { createMimoToolbox } from "../modules/mimo/mimo.tools.js";

function memDeps({ consent = {}, memories = [], orders = [] } = {}) {
  const store = memories.map((m, i) => ({ id: i + 1, memory_key: m.key, memory_value: m.value, is_active: true }));
  const events = [];
  const synonyms = new Map();
  return {
    store,
    events,
    synonyms,
    async consent() {
      return consent;
    },
    async listMemories() {
      return store;
    },
    async insertMemory(_u, key, value) {
      const row = { id: store.length + 1, memory_key: key, memory_value: value, is_active: true };
      store.push(row);
      return row;
    },
    async updateMemory(_u, id, value) {
      const row = store.find((r) => r.id === id);
      row.memory_value = value;
      return row;
    },
    async deleteMemory(_u, id) {
      store.splice(store.findIndex((r) => r.id === id), 1);
      return true;
    },
    async deleteAllMemories() {
      store.length = 0;
    },
    async recentOrders() {
      return orders;
    },
    async logEvent(e) {
      events.push(e);
    },
    async learnSynonym(term, alias) {
      const k = `${term}→${alias}`;
      synonyms.set(k, (synonyms.get(k) || 0) + 1);
    },
    async synonymsFor(terms) {
      return [...synonyms.keys()]
        .map((k) => k.split("→"))
        .filter(([t]) => terms.includes(t))
        .map(([term, alias]) => ({ term, alias, hits: 1 }));
    },
  };
}

const ORDERS = [
  { id: 3, merchant_id: 1, merchant_name: "مشاوي أبو علي", status: "delivered", total_amount: 24000,
    created_at: "2026-10-16T17:30:00Z", items: [{ product_id: 12, product_name: "نص كيلو كباب", quantity: 2, unit_price: 12000 }] },
  { id: 2, merchant_id: 1, merchant_name: "مشاوي أبو علي", status: "delivered", total_amount: 12000,
    created_at: "2026-10-10T18:00:00Z", items: [{ product_id: 12, product_name: "نص كيلو كباب", quantity: 1, unit_price: 12000 }] },
  { id: 1, merchant_id: 4, merchant_name: "برونتو", status: "cancelled", total_amount: 8000,
    created_at: "2026-10-01T12:00:00Z", items: [{ product_id: 40, product_name: "بركر", quantity: 1 }] },
];

test("taste profile is learned from real (non-cancelled) orders", () => {
  const p = buildTasteProfile(ORDERS, new Date("2026-10-18T12:00:00Z").getTime());
  assert.equal(p.orders, 2);
  assert.equal(p.avgSpend, 18000);
  assert.equal(p.favoriteStores[0].name, "مشاوي أبو علي");
  assert.equal(p.favoriteDishes[0].name, "نص كيلو كباب");
  assert.equal(p.favoriteDishes[0].times, 3);
  assert.equal(p.usualTime, "evening");
  assert.equal(p.daysSinceLastOrder, 1);
  assert.match(p.lastOrder.items[0], /نص كيلو كباب ×2/);
  assert.equal(buildTasteProfile([]), null);
});

test("memory never stores secrets or long numbers", () => {
  assert.equal(isSafeMemory("يحب الحار"), true);
  assert.equal(isSafeMemory("عدهم 5 بالبيت"), true);
  assert.equal(isSafeMemory("رقم بطاقتي 4111 1111 1111 1111"), false);
  assert.equal(isSafeMemory("الرمز السري 1234"), false);
  assert.equal(isSafeMemory("07701234567"), false);
});

test("remember merges likes, respects consent, forget removes", async () => {
  const deps = memDeps({ memories: [{ key: "likes", value: "مشاوي" }] });
  const memory = await loadMimoMemory(deps, 7);
  const r1 = await rememberFact(deps, 7, memory, { key: "likes", value: "الحار" });
  assert.equal(r1.value, "مشاوي، الحار");
  await rememberFact(deps, 7, memory, { key: "allergy", value: "فول سوداني" });
  assert.match(memoryPromptSection(memory), /allergy: فول سوداني/);
  await forgetFact(deps, 7, memory, { key: "likes" });
  assert.equal(memory.memories.some((m) => m.key === "likes"), false);
  assert.equal(deps.store.some((r) => r.memory_key === "likes"), false);

  const off = memDeps({ consent: { memoryEnabled: false } });
  const memOff = await loadMimoMemory(off, 7);
  assert.deepEqual(await rememberFact(off, 7, memOff, { key: "likes", value: "x" }), {
    saved: false,
    reason: "MEMORY_DISABLED_BY_USER",
  });
  assert.match(memoryPromptSection(memOff), /turned memory OFF/);
});

test("personalization off → no taste profile from orders", async () => {
  const deps = memDeps({ consent: { personalization: false }, orders: ORDERS });
  const memory = await loadMimoMemory(deps, 7);
  assert.equal(memory.profile, null);
});

test("learns a synonym when a missed word was rescued by another word", async () => {
  const deps = memDeps();
  await learnFromTurn(deps, {
    userId: 7,
    improveOn: true,
    question: "اريد برغر",
    searches: [
      { word: "برغر", count: 0, productIds: [] },
      { word: "برگر", count: 2, productIds: [5, 6] },
    ],
    shownProductIds: new Set([5]),
  });
  assert.equal(deps.synonyms.get("برغر→برگر"), 1);
  assert.ok(deps.events.some((e) => e.kind === "question" && e.userId === 7));
  assert.ok(deps.events.some((e) => e.kind === "search_miss" && e.text === "برغر"));
  assert.ok(!deps.events.some((e) => e.kind === "unmet_need"));

  // Next time "برغر" is searched, the learned alias is added automatically.
  const searched = [];
  const box = createMimoToolbox({
    userId: 7,
    memoryDeps: deps,
    deps: {
      async searchProducts(_u, p) {
        searched.push(p.q);
        return [];
      },
    },
  });
  await box.run("search_products", { keywords: ["برغر"] });
  assert.deepEqual(searched, ["برغر", "برگر"]);
});

test("unmet needs are recorded anonymously without improve-consent", async () => {
  const deps = memDeps();
  await learnFromTurn(deps, {
    userId: 7,
    improveOn: false,
    question: "اريد شاورمه",
    searches: [{ word: "شاورمه", count: 0, productIds: [] }],
    shownProductIds: new Set(),
  });
  const unmet = deps.events.find((e) => e.kind === "unmet_need");
  assert.equal(unmet.text, "شاورمه");
  assert.ok(deps.events.every((e) => e.userId === null));
});

test("quote_order uses the real checkout preview, falls back honestly", async () => {
  const box = createMimoToolbox({
    userId: 7,
    deps: {
      async previewOrder(_u, dto) {
        assert.equal(dto.storeOrders[0].items[0].quantity, 2);
        return {
          totals: { grossSubtotal: 24000, productDiscountTotal: 0, couponDiscountTotal: 2400, serviceFeeTotal: 500, deliveryFeeTotal: 2000, totalAmount: 24100 },
          stores: [{ merchantName: "أبو علي", items: [{ productName: "كباب", quantity: 2, lineTotal: 24000 }], pricing: { totalAmount: 24100, deliveryFee: 2000, serviceFee: 500, grossSubtotal: 24000 } }],
        };
      },
    },
  });
  const q = await box.run("quote_order", { stores: [{ store_id: 1, items: [{ product_id: 12, quantity: 2 }] }], coupon_code: "mimo10" });
  assert.equal(q.exact, true);
  assert.equal(q.total, 24100);
  assert.equal(q.couponDiscount, 2400);
  const card = await box.display("respond", { text: "x", mood: "happy", quote: true });
  assert.equal(card[0].type, "quote");
  assert.equal(card[0].total, 24100);

  const offline = createMimoToolbox({
    userId: 7,
    deps: {
      async previewOrder() {
        throw new Error("ADDRESS_REQUIRED");
      },
      async searchProducts() {
        return [{ productId: 12, name: "كباب", price: 12000, finalPrice: 12000, merchant: { id: 1 } }];
      },
    },
  });
  await offline.run("search_products", { keywords: ["كباب"] });
  const est = await offline.run("quote_order", { stores: [{ store_id: 1, items: [{ product_id: 12, quantity: 3 }] }] });
  assert.equal(est.exact, false);
  assert.equal(est.subtotal, 36000);
  assert.equal(est.total, null);
});

test("reorder_last turns the previous order into a confirmable bundle", async () => {
  const box = createMimoToolbox({
    userId: 7,
    deps: {
      async recentOrders() {
        return ORDERS;
      },
      async storeMenu(storeId, p) {
        return [{ id: p.productIds[0], merchant_id: storeId, name: "نص كيلو كباب", price: 12000 }];
      },
      async listStores() {
        return [{ id: 1, name: "مشاوي أبو علي" }];
      },
    },
  });
  const r = await box.run("reorder_last", {});
  assert.equal(r.found, true);
  assert.deepEqual(r.items[0], { product_id: 12, store_id: 1, name: "نص كيلو كباب", quantity: 2, unitPrice: 12000 });
  const ui = await box.display("respond", {
    text: "نفس طلبك؟",
    mood: "happy",
    cart_bundle: [{ product_id: 12, store_id: 1, quantity: 2 }],
  });
  const bundle = ui.find((e) => e.type === "cart_bundle");
  assert.equal(bundle.items.length, 1);
  assert.equal(bundle.items[0].quantity, 2);
  assert.equal(bundle.items[0].store.name, "مشاوي أبو علي");
});

test("agent injects memory into the prompt and learns after the turn", async () => {
  const deps = memDeps({ memories: [{ key: "allergy", value: "فول سوداني" }], orders: ORDERS });
  const memory = await loadMimoMemory(deps, 7);
  let systemPrompt = "";
  const llm = {
    async chat({ messages }) {
      systemPrompt = messages[0].content;
      return { content: "", toolCalls: [{ id: "r", name: "respond", arguments: '{"text":"هلا","mood":"happy"}' }] };
    },
  };
  await runMimoTurn({
    llm,
    toolbox: createMimoToolbox({ userId: 7, memoryDeps: deps, memory, deps: {} }),
    history: [{ role: "user", content: "هلا" }],
    memory,
    memoryDeps: deps,
    userId: 7,
    emit: () => {},
  });
  assert.match(systemPrompt, /allergy: فول سوداني/);
  assert.match(systemPrompt, /Favorite dishes: نص كيلو كباب/);
  await new Promise((r) => setTimeout(r, 5));
  assert.ok(deps.events.some((e) => e.kind === "question" && e.text === "هلا"));
});

test("only facts the user states about themselves can be remembered", async () => {
  const { statesPersonalFact } = await import("../modules/mimo/mimo.memory.js");
  assert.equal(statesPersonalFact("اريد برغر"), false);
  assert.equal(statesPersonalFact("شنو اطلب عشا؟"), false);
  assert.equal(statesPersonalFact("ترا انا عندي حساسية من الفول السوداني"), true);
  assert.equal(statesPersonalFact("عدنا 5 بالبيت"), true);
  assert.equal(statesPersonalFact("I'm vegetarian"), true);

  const deps = memDeps();
  const memory = await loadMimoMemory(deps, 7);
  const box = createMimoToolbox({ userId: 7, memoryDeps: deps, memory, deps: {} });
  box.setUserMessage("اريد برغر");
  const rejected = await box.run("remember", { key: "likes", value: "يحب البرغر" });
  assert.equal(rejected.saved, false);
  assert.equal(deps.store.length, 0);
  box.setUserMessage("انا احب الحار هواية");
  assert.equal((await box.run("remember", { key: "likes", value: "يحب الحار" })).saved, true);
  const again = await box.run("remember", { key: "likes", value: "يحب الحار" });
  assert.ok(again.alreadyNoted || again.note, "no repeat saves in one turn");
  assert.equal(deps.store.length, 1);
});

test("allergy safety net removes risky dishes and adds the warning", async () => {
  const { allergenWords } = await import("../modules/mimo/mimo.memory.js");
  const deps = memDeps({ memories: [{ key: "allergy", value: "حساسية من الفستق والمكسرات" }] });
  const memory = await loadMimoMemory(deps, 7);
  assert.ok(allergenWords(memory).includes("كنافة"));
  const box = createMimoToolbox({
    userId: 7,
    memory,
    memoryDeps: deps,
    deps: {
      async searchProducts() {
        return [
          { productId: 1, name: "كنافة نابلسية", price: 5000, merchant: { id: 9 } },
          { productId: 2, name: "كليچة تمر", price: 4000, merchant: { id: 9 } },
        ];
      },
    },
  });
  await box.run("search_products", { keywords: ["حلويات"] });
  const events = [];
  const out = await runMimoTurn({
    llm: {
      async chat() {
        return {
          content: "",
          toolCalls: [{
            id: "r",
            name: "respond",
            arguments: JSON.stringify({
              text: "هاي حلويات طيبة",
              mood: "yummy",
              products: [{ product_id: 1, note: "x" }, { product_id: 2, note: "y" }],
            }),
          }],
        };
      },
    },
    toolbox: box,
    history: [{ role: "user", content: "اريد حلويات" }],
    memory,
    emit: (e, d) => events.push([e, d]),
  });
  const cards = out.ui.find((u) => u.type === "products");
  assert.deepEqual(cards.items.map((i) => i.id), [2], "kunafa removed");
  assert.match(out.text, /تأكد من المحل/);
});

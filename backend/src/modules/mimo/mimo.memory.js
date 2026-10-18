/**
 * Mimo's memory and learning.
 *
 * Per user (only with the user's AI-memory consent):
 *   - explicit memories Mimo saves when the user reveals something useful
 *     ("I'm allergic to peanuts", "we are 5 at home", "I love spicy")
 *   - a taste profile computed from real orders (favourite stores and dishes,
 *     usual spend and time) — learned, never invented.
 * Global (anonymous unless the user allowed "improve the assistant"):
 *   - every question, search misses and unmet needs → demand insights
 *   - learned synonyms (برغر → برگر) that make future searches smarter.
 */

export const MEMORY_KEYS = [
  "likes",
  "dislikes",
  "allergy",
  "diet",
  "household",
  "budget",
  "favorite_store",
  "routine",
  "preferred_name",
  "other",
];

const MEMORY_TYPE = "mimo";
const MAX_MEMORY_VALUE = 220;

const clean = (v, max = 200) => String(v ?? "").replace(/\s+/g, " ").trim().slice(0, max);

/**
 * Did the user state something lasting about THEMSELVES in this message?
 * ("عندي حساسية"، "ما آكل"، "عدنا 5"، "احب الحار"، "I'm vegetarian").
 * A plain request ("اريد برغر") is not a fact about the person.
 */
export function statesPersonalFact(message) {
  const m = String(message || "");
  return /(عندي|عدني|عدنا|عندنا|عدهم|احنا|إحنا|نحن|انا|أنا|آني|اني|ما آكل|ما اكل|ما ناكل|ما احب|ما أحب|ما نحب|احب|أحب|نحب|اكره|أكره|حساسية|نباتي|دايت|رجيم|ريجيم|سكري|ميزانيتي|دايماً|دائماً|دايما|كل يوم|كل جمعة|سميني|ناديني|اسمي|بيتنا|بيتي|I'm|I am|I have|I don't|I never|I always|allergic|vegetarian|vegan|my budget|call me|we are|we're)/i.test(m);
}

/** Common foods that contain each allergen family (Iraqi menus). */
const ALLERGEN_FOODS = [
  [/(مكسرات|فستق|لوز|جوز|فول سوداني|كاجو|بندق|nut|peanut|pistachio|almond)/i,
    ["مكسرات", "فستق", "لوز", "جوز", "فول سوداني", "كاجو", "بندق", "بقلاوة", "بقلاوه", "كنافة", "كنافه", "معمول", "حلاوة", "بسبوسة", "نوتيلا", "nut", "pistachio"]],
  [/(غلوتين|جلوتين|قمح|حنطة|gluten|wheat|celiac|سيلياك)/i,
    ["خبز", "صمون", "معجنات", "بيتزا", "كيك", "بسكويت", "معكرونة", "باستا", "برگر", "بركر", "سندويچ", "سندويج", "لفة", "كليچة", "كليجة"]],
  [/(حليب|ألبان|البان|لاكتوز|dairy|lactose|milk)/i,
    ["جبن", "جبنة", "قيمر", "لبن", "حليب", "كريمة", "زبدة", "آيس كريم", "ايس كريم", "تشيز", "cheese"]],
  [/(بيض|egg)/i, ["بيض", "كيك", "مايونيز", "عجة"]],
  [/(سمك|روبيان|بحري|seafood|fish|shrimp)/i, ["سمك", "مسكوف", "روبيان", "تونة", "سلمون"]],
  [/(سمسم|طحينة|sesame)/i, ["طحينة", "سمسم", "حمص", "حلاوة"]],
];

/** Words that, if found in a dish, mean it may contain the user's allergens. */
export function allergenWords(memory) {
  const text = (memory?.memories || [])
    .filter((m) => m.key === "allergy" || m.key === "diet")
    .map((m) => m.value)
    .join(" ");
  if (!text) return [];
  return [...new Set(ALLERGEN_FOODS.filter(([re]) => re.test(text)).flatMap(([, words]) => words))];
}

/** Rejects things Mimo must never store (credentials, card/ID numbers). */
export function isSafeMemory(value) {
  const v = String(value || "");
  if (!v.trim()) return false;
  if (/\b\d{6,}\b/.test(v.replace(/[\s-]/g, ""))) return false; // long numbers: cards, phones, IDs
  if (/(password|pin|باسورد|رمز سري|الرمز السري|كلمة السر|كلمة المرور|بطاقة|فيزا|ماستر)/i.test(v)) return false;
  return true;
}

export function createDefaultMemoryDeps() {
  const lazy = (p) => import(p);
  return {
    async consent(userId) {
      const m = await lazy("../assistant/assistant.ai.service.js");
      const out = await m.getUserAiProfile({ customerUserId: userId });
      return out?.profile?.consentFlags || {};
    },
    async listMemories(userId) {
      const m = await lazy("../assistant/assistant.ai.repo.js");
      return m.listAiUserMemoriesV2({ customerUserId: userId, memoryType: MEMORY_TYPE, limit: 40 });
    },
    async insertMemory(userId, key, value) {
      const m = await lazy("../assistant/assistant.ai.repo.js");
      return m.insertAiUserMemoryV2({
        customerUserId: userId,
        memoryType: MEMORY_TYPE,
        memoryKey: key,
        memoryValue: value,
        confidenceScore: 0.9,
      });
    },
    async updateMemory(userId, id, value) {
      const m = await lazy("../assistant/assistant.ai.repo.js");
      return m.updateAiUserMemoryV2({ memoryId: id, customerUserId: userId, memoryValue: value });
    },
    async deleteMemory(userId, id) {
      const m = await lazy("../assistant/assistant.ai.repo.js");
      return m.deleteAiUserMemoryV2({ memoryId: id, customerUserId: userId });
    },
    async deleteAllMemories(userId) {
      const m = await lazy("../assistant/assistant.ai.repo.js");
      return m.deleteAllAiUserMemoriesV2({ customerUserId: userId, memoryType: MEMORY_TYPE });
    },
    async recentOrders(userId) {
      const m = await lazy("../orders/orders.repo.js");
      return m.listCustomerOrders(userId, { paginate: true, limit: 30 });
    },
    async logEvent({ userId, kind, text, detail }) {
      const { q } = await lazy("../../config/db.js");
      await q(
        `INSERT INTO mimo_learning_event (user_id, kind, text, detail)
         VALUES ($1, $2, $3, $4::jsonb)`,
        [userId || null, kind, text ? clean(text, 600) : null, JSON.stringify(detail || {})]
      );
    },
    async learnSynonym(term, alias) {
      const { q } = await lazy("../../config/db.js");
      await q(
        `INSERT INTO mimo_learned_synonym (term, alias) VALUES ($1, $2)
         ON CONFLICT (term, alias) DO UPDATE
           SET hits = mimo_learned_synonym.hits + 1, updated_at = NOW()`,
        [term, alias]
      );
    },
    async synonymsFor(terms) {
      if (!terms.length) return [];
      const { q } = await lazy("../../config/db.js");
      const r = await q(
        `SELECT term, alias, hits FROM mimo_learned_synonym
         WHERE term = ANY($1::text[]) AND hits >= 1
         ORDER BY hits DESC LIMIT 12`,
        [terms]
      );
      return r.rows;
    },
    async insights({ days = 30 } = {}) {
      const { q } = await lazy("../../config/db.js");
      const since = `NOW() - ($1::int * INTERVAL '1 day')`;
      const [unmet, misses, questions, feedback, synonyms] = await Promise.all([
        q(`SELECT LOWER(text) AS text, COUNT(*)::int AS times FROM mimo_learning_event
           WHERE kind = 'unmet_need' AND created_at > ${since} AND text IS NOT NULL
           GROUP BY 1 ORDER BY 2 DESC LIMIT 30`, [days]),
        q(`SELECT LOWER(text) AS text, COUNT(*)::int AS times FROM mimo_learning_event
           WHERE kind = 'search_miss' AND created_at > ${since} AND text IS NOT NULL
           GROUP BY 1 ORDER BY 2 DESC LIMIT 30`, [days]),
        q(`SELECT COUNT(*)::int AS total, COUNT(DISTINCT user_id)::int AS users FROM mimo_learning_event
           WHERE kind = 'question' AND created_at > ${since}`, [days]),
        q(`SELECT kind, COUNT(*)::int AS times FROM mimo_learning_event
           WHERE kind IN ('feedback_up','feedback_down') AND created_at > ${since}
           GROUP BY kind`, [days]),
        q(`SELECT term, alias, hits FROM mimo_learned_synonym ORDER BY hits DESC LIMIT 30`),
      ]);
      return {
        days,
        questions: questions.rows[0] || { total: 0, users: 0 },
        unmetNeeds: unmet.rows,
        searchMisses: misses.rows,
        feedback: Object.fromEntries(feedback.rows.map((r) => [r.kind, r.times])),
        learnedSynonyms: synonyms.rows,
      };
    },
  };
}

/** Taste profile from real orders: what this person actually orders. */
export function buildTasteProfile(orders = [], now = Date.now()) {
  const done = orders.filter((o) => !/cancel|reject|fail/i.test(String(o.status || "")));
  if (!done.length) return null;
  const stores = new Map();
  const dishes = new Map();
  const hours = new Map();
  let spend = 0;
  for (const o of done) {
    const sid = Number(o.merchant_id);
    const s = stores.get(sid) || { id: sid, name: clean(o.merchant_name, 50), orders: 0 };
    s.orders += 1;
    stores.set(sid, s);
    spend += Number(o.total_amount ?? o.totalAmount ?? 0) || 0;
    const created = o.created_at ? new Date(o.created_at) : null;
    if (created && !Number.isNaN(created.getTime())) {
      const h = Number(
        new Intl.DateTimeFormat("en-GB", { timeZone: "Asia/Baghdad", hour: "2-digit", hour12: false }).format(created)
      );
      const slot = h < 11 ? "morning" : h < 16 ? "midday" : h < 19 ? "afternoon" : "evening";
      hours.set(slot, (hours.get(slot) || 0) + 1);
    }
    for (const it of o.items || []) {
      const name = clean(it.product_name || it.productName || it.name, 50);
      if (!name) continue;
      const key = `${name}@${sid}`;
      const d = dishes.get(key) || {
        productId: Number(it.product_id || it.productId) || null,
        storeId: sid,
        name,
        store: s.name,
        times: 0,
      };
      d.times += Number(it.quantity) || 1;
      dishes.set(key, d);
    }
  }
  const last = done[0];
  const lastAt = last?.created_at ? new Date(last.created_at).getTime() : null;
  return {
    orders: done.length,
    avgSpend: Math.round(spend / done.length),
    favoriteStores: [...stores.values()].sort((a, b) => b.orders - a.orders).slice(0, 4),
    favoriteDishes: [...dishes.values()].sort((a, b) => b.times - a.times).slice(0, 5),
    usualTime: [...hours.entries()].sort((a, b) => b[1] - a[1])[0]?.[0] || null,
    daysSinceLastOrder: lastAt ? Math.floor((now - lastAt) / 86400000) : null,
    lastOrder: last
      ? {
          id: Number(last.id),
          store: clean(last.merchant_name, 50),
          items: (last.items || []).slice(0, 6).map((i) => `${clean(i.product_name || i.name, 40)} ×${i.quantity}`),
        }
      : null,
  };
}

/** Everything Mimo should "remember" at the start of a turn. */
export async function loadMimoMemory(deps, userId) {
  let consent = {};
  try {
    consent = await deps.consent(userId);
  } catch {
    consent = {};
  }
  const memoryOn = consent.memoryEnabled !== false;
  const personalization = consent.personalization !== false;
  const [memories, orders] = await Promise.all([
    memoryOn ? deps.listMemories(userId).catch(() => []) : [],
    personalization ? deps.recentOrders(userId).catch(() => []) : [],
  ]);
  return {
    memoryOn,
    improveOn: consent.improveModel !== false,
    memories: memories
      .filter((m) => m.is_active !== false)
      .slice(0, 30)
      .map((m) => ({ id: Number(m.id), key: m.memory_key, value: clean(m.memory_value, MAX_MEMORY_VALUE) })),
    profile: personalization ? buildTasteProfile(orders) : null,
  };
}

/** Prompt section describing what Mimo knows about this user. */
export function memoryPromptSection(memory) {
  if (!memory) return "";
  const lines = ["# What you know about this user (use naturally, never dump it)"];
  if (!memory.memoryOn) {
    lines.push("- The user turned memory OFF: don't save new memories; if they ask, tell them they can enable it in the app.");
  }
  for (const m of memory.memories || []) lines.push(`- ${m.key}: ${m.value}`);
  const p = memory.profile;
  if (p) {
    lines.push(
      `- From ${p.orders} real orders: avg spend ${p.avgSpend} IQD; usual time ${p.usualTime || "?"}; last order ${p.daysSinceLastOrder ?? "?"} days ago.`
    );
    if (p.favoriteStores.length) {
      lines.push(`- Favorite stores: ${p.favoriteStores.map((s) => `${s.name} (${s.orders}×, store#${s.id})`).join(", ")}`);
    }
    if (p.favoriteDishes.length) {
      lines.push(`- Favorite dishes: ${p.favoriteDishes.map((d) => `${d.name} from ${d.store} (${d.times}×)`).join(", ")}`);
    }
    if (p.lastOrder) lines.push(`- Last order: ${p.lastOrder.store} — ${p.lastOrder.items.join("، ")}`);
  }
  if (lines.length === 1) lines.push("- Nothing yet. Learn as you go (use remember).");
  return lines.join("\n");
}

/** Saves/updates one memory (merging values under the same key). */
export async function rememberFact(deps, userId, memory, { key, value }) {
  if (!memory?.memoryOn) return { saved: false, reason: "MEMORY_DISABLED_BY_USER" };
  const k = MEMORY_KEYS.includes(key) ? key : "other";
  const v = clean(value, MAX_MEMORY_VALUE);
  if (!isSafeMemory(v)) return { saved: false, reason: "NOT_ALLOWED_TO_STORE_THIS" };
  const existing = memory.memories.find((m) => m.key === k);
  const mergeable = ["likes", "dislikes", "allergy", "favorite_store", "other"].includes(k);
  if (existing) {
    const merged = mergeable && !existing.value.includes(v)
      ? clean(`${existing.value}، ${v}`, MAX_MEMORY_VALUE)
      : v;
    await deps.updateMemory(userId, existing.id, merged);
    existing.value = merged;
    return { saved: true, key: k, value: merged, updated: true };
  }
  const row = await deps.insertMemory(userId, k, v);
  memory.memories.push({ id: Number(row?.id) || 0, key: k, value: v });
  return { saved: true, key: k, value: v };
}

export async function forgetFact(deps, userId, memory, { key, everything }) {
  if (everything === true) {
    await deps.deleteAllMemories(userId);
    memory.memories.length = 0;
    return { forgotten: "everything" };
  }
  const hits = memory.memories.filter((m) => m.key === key);
  for (const m of hits) await deps.deleteMemory(userId, m.id);
  memory.memories = memory.memories.filter((m) => m.key !== key);
  return { forgotten: hits.length ? key : null };
}

/**
 * After a turn: learn synonyms from (missed word → word that found what was
 * shown) and record unmet needs when nothing could be offered.
 */
export async function learnFromTurn(deps, { userId, improveOn, question, searches, shownProductIds }) {
  const uid = improveOn ? userId : null;
  const jobs = [];
  if (question) jobs.push(deps.logEvent({ userId: uid, kind: "question", text: question }));
  const misses = searches.filter((s) => s.count === 0).map((s) => s.word);
  const hits = searches.filter((s) => s.count > 0 && s.productIds.some((id) => shownProductIds.has(id)));
  for (const miss of [...new Set(misses)].slice(0, 4)) {
    jobs.push(deps.logEvent({ userId: uid, kind: "search_miss", text: miss }));
  }
  for (const miss of [...new Set(misses)].slice(0, 3)) {
    for (const hit of hits.slice(0, 2)) {
      if (hit.word !== miss) jobs.push(deps.learnSynonym(miss, hit.word));
    }
  }
  if (searches.length && misses.length === searches.length && shownProductIds.size === 0) {
    jobs.push(
      deps.logEvent({ userId: uid, kind: "unmet_need", text: misses[0], detail: { words: misses.slice(0, 6) } })
    );
  }
  await Promise.allSettled(jobs);
}

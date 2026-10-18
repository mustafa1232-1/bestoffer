import { findGuide } from "./mimo.appguide.js";
import { isTeachingMoment, recallKnowledge, teachFact } from "./mimo.knowledge.js";
import { ESCALATION_DOMAINS, diagnose, escalate, ticketsStatus } from "./mimo.support.js";
import { MEMORY_KEYS, allergenWords, forgetFact, rememberFact, statesPersonalFact } from "./mimo.memory.js";

/**
 * Mimo's tools. "Data" tools read real app data (stores, products, menus,
 * the user's orders and coupons) so Mimo never invents prices or ratings.
 * "Display" tools put things in the chat UI (cards, quick replies, a cart
 * proposal, a mood) and end the turn without another model round-trip.
 */

const MS_DAY = 24 * 60 * 60 * 1000;

/** Sections of the app that are not stores but Mimo can point to. */
export const APP_SECTIONS = [
  { key: "shopping", ar: "التسوق (مطاعم، أسواق، ملابس، كهربائيات...)", en: "Shopping" },
  { key: "taxi", ar: "تكسي مسلكي داخل بسماية", en: "Taxi" },
  { key: "services", ar: "خدمات مسلكي (حرفيين ومهنيين)", en: "Services" },
  { key: "pharmacy", ar: "الصيدليات والوصفات", en: "Pharmacy" },
  { key: "community", ar: "مجتمع بسماية (سوشل ميديا)", en: "Community" },
  { key: "offers", ar: "العروض والكوبونات", en: "Offers & coupons" },
  { key: "cars", ar: "سوق السيارات", en: "Cars" },
  { key: "real_estate", ar: "العقارات", en: "Real estate" },
  { key: "jobs", ar: "الوظائف", en: "Jobs" },
  { key: "orders", ar: "طلباتي وتتبعها", en: "My orders" },
  { key: "cart", ar: "السلة", en: "Cart" },
];

const SORTS = ["best", "top_rated", "most_ordered", "newest", "cheapest", "fastest"];
const MOODS = [
  "idle", "happy", "love", "thinking", "curious", "wink", "dancing", "yummy",
  "waving", "laughing", "shocked", "sad", "relieved", "sleepy",
];

const str = (v, max = 160) => {
  const s = String(v ?? "").replace(/\s+/g, " ").trim();
  return s.length > max ? `${s.slice(0, max - 1)}…` : s;
};
const num = (v) => (Number.isFinite(Number(v)) ? Number(v) : null);
const clampInt = (v, min, max, fallback) => {
  const n = Number.parseInt(String(v ?? ""), 10);
  return Number.isFinite(n) ? Math.max(min, Math.min(max, n)) : fallback;
};

function fn(name, description, properties = {}, required = []) {
  return {
    type: "function",
    function: {
      name,
      description,
      parameters: { type: "object", properties, required, additionalProperties: false },
    },
  };
}

export const MIMO_TOOL_SCHEMAS = [
  fn(
    "list_store_categories",
    "List every store category (activity type) in the app with Arabic/English names, plus the non-store app sections. Use when the user is browsing or you need the right activity_type."
  ),
  fn(
    "list_subcategories",
    "Sub-filters inside a store category (e.g. restaurant → grills, eastern, fast food, sweets; fashion → men/women).",
    { activity_type: { type: "string" } },
    ["activity_type"]
  ),
  fn(
    "find_stores",
    "Find stores with live stats (rating, ratings count, completed orders, open now, new, avg price, delivery time/fee, offers). Filter by category/sub-filter/text and sort. Text query also matches the store's products.",
    {
      activity_type: { type: "string", description: "e.g. restaurant, supermarket, fashion_clothing, electronics_mobile, pharmacy" },
      subcategory: { type: "string" },
      query: { type: "string", description: "Free text, e.g. a dish or brand. Optional." },
      department: { type: "string", enum: ["men", "women"] },
      sort: { type: "string", enum: SORTS },
      open_now: { type: "boolean" },
      limit: { type: "integer", minimum: 1, maximum: 8 },
    }
  ),
  fn(
    "search_products",
    "Search products/dishes across all stores (live price, discount, store, store rating, order count). Arabic matching is literal: try 2-4 spelling variants/synonyms in `keywords` (e.g. مشاوي، كباب، تكة، شيش) — results are merged.",
    {
      keywords: { type: "array", items: { type: "string" }, minItems: 1, maxItems: 4 },
      store_type: { type: "string", enum: ["restaurant", "market"] },
      max_price: { type: "number", description: "IQD" },
      only_offers: { type: "boolean" },
      limit: { type: "integer", minimum: 1, maximum: 10 },
    },
    ["keywords"]
  ),
  fn(
    "get_store_menu",
    "A store's products/menu (optionally filtered by text), with prices and availability.",
    {
      store_id: { type: "integer" },
      query: { type: "string" },
      limit: { type: "integer", minimum: 1, maximum: 20 },
    },
    ["store_id"]
  ),
  fn(
    "pick_for_me",
    "When the user says 'choose for me' (اختارلي انت). Finds products matching the craving, picks the store with the MOST completed orders, then the highest rating, random on a tie; then that store's most-ordered matching dish. Returns the pick and alternatives.",
    {
      keywords: { type: "array", items: { type: "string" }, minItems: 1, maxItems: 4 },
      store_type: { type: "string", enum: ["restaurant", "market"] },
      max_price: { type: "number" },
    },
    ["keywords"]
  ),
  fn("my_recent_orders", "The user's latest orders with status, store and items.", {
    limit: { type: "integer", minimum: 1, maximum: 5 },
  }),
  fn("my_coupons", "Coupons the user can use right now."),
  fn(
    "calculate",
    "Exact arithmetic for multi-item totals, budgets, per-person costs and what's left. Put ALL the sums you need in ONE call (e.g. [\"2*12000+18000\", \"50000-(2*12000+18000)\"]). Not needed for a single price.",
    {
      expressions: {
        type: "array",
        minItems: 1,
        maxItems: 6,
        items: { type: "string", description: "Numbers, + - * / ( ) only" },
      },
    },
    ["expressions"]
  ),

  fn(
    "quote_order",
    "Simulate a REAL checkout before the user orders: exact subtotal, discounts, delivery and service fees, coupon effect and final total per store and overall (uses the user's saved address). Use for 'شگد يطلع الحساب'، budgets, comparing options, before proposing a bundle.",
    {
      stores: {
        type: "array",
        minItems: 1,
        maxItems: 3,
        items: {
          type: "object",
          properties: {
            store_id: { type: "integer" },
            items: {
              type: "array",
              minItems: 1,
              maxItems: 20,
              items: {
                type: "object",
                properties: {
                  product_id: { type: "integer" },
                  quantity: { type: "integer", minimum: 1, maximum: 50 },
                },
                required: ["product_id", "quantity"],
                additionalProperties: false,
              },
            },
          },
          required: ["store_id", "items"],
          additionalProperties: false,
        },
      },
      coupon_code: { type: "string" },
    },
    ["stores"]
  ),
  fn(
    "reorder_last",
    "The user's previous order(s) as ready-to-add items (for 'نفس طلبي الأخير' / 'رجعلي طلب امبارح'). Returns items with ids; then respond with cart_bundle.",
    { which: { type: "integer", minimum: 1, maximum: 5, description: "1 = last order, 2 = the one before…" } }
  ),
  fn(
    "search_services",
    "Home & professional services (plumber/سباك، electrician/كهربائي، AC/تبريد، cleaning/تنظيف، painter/صباغ، carpenter/نجار، tutor/مدرس…) with provider, price and rating. Try 2-3 keyword variants.",
    {
      keywords: { type: "array", items: { type: "string" }, minItems: 1, maxItems: 3 },
      max_price: { type: "number" },
    },
    ["keywords"]
  ),
  fn(
    "store_info",
    "One store's practical details: open now, working hours, next opening, delivery time and fee, minimum order, rating.",
    { store_id: { type: "integer" } },
    ["store_id"]
  ),
  fn(
    "remember",
    "Save something useful the user revealed about themselves for next time (taste, allergies, diet, household size, budget, favorite store, routine, what to call them). Only real, stable facts the user said — never guesses, never phone numbers/addresses/passwords/payment data.",
    {
      key: { type: "string", enum: MEMORY_KEYS },
      value: { type: "string", description: "Short, in the user's words, e.g. 'يحب الحار' / 'عدهم 5 بالبيت'" },
    },
    ["key", "value"]
  ),
  fn(
    "forget",
    "Delete a memory when the user asks you to forget something (or everything).",
    {
      key: { type: "string", enum: MEMORY_KEYS },
      everything: { type: "boolean" },
    }
  ),

  fn(
    "web_search",
    "Search the internet ONLY for current/changing or very specific facts: news, prices/exchange rates, weather, sports results, schedules, recent events, specific lesser-known people/places/products. NOT for well-known stable facts (capitals, history, science, definitions, how-to) — answer those yourself. Max 2 per turn.",
    { query: { type: "string", description: "A precise search query (Arabic or English, whichever finds better results)" } },
    ["query"]
  ),
  fn(
    "think_deeply",
    "Hand a hard problem to a slow, careful reasoning brain: multi-step math, logic puzzles, tricky word problems, planning/optimisation, comparing complex options, code reasoning. Returns the final answer with a short explanation. Don't use it for simple questions.",
    {
      problem: { type: "string", description: "The full problem with all the numbers/conditions from the conversation" },
    },
    ["problem"]
  ),
  fn(
    "recall_knowledge",
    "ONLY for local Basmaya/community/personal things you can't know (a shop's hours, a local person/teacher, neighborhood info, local slang). Never for general knowledge. Once per turn.",
    { query: { type: "string" } },
    ["query"]
  ),
  fn(
    "learn_fact",
    "The user is TEACHING you something (usually after you said you didn't know it, or 'تعلم/احفظ هاي'). It is verified online before you keep it: correct → learned, wrong → not learned (you get the correction), local info → kept as unconfirmed until others confirm. Never use for the user's personal preferences (that's remember).",
    {
      question: { type: "string", description: "The question this answers, e.g. 'يمته يفتح مخبز الأصيل؟'" },
      answer: { type: "string", description: "What the user taught, faithfully" },
      topic: { type: "string" },
    },
    ["question", "answer"]
  ),

  fn(
    "app_guide",
    "How Maslaki works: ordering, tracking, cancelling (rules), returns, coupons, addresses, PIN reset/login, settings, taxi, services, community, pharmacy, notifications, app problems. Use it to explain features or guide someone step by step.",
    { question: { type: "string" } },
    ["question"]
  ),
  fn(
    "diagnose_problem",
    "When the user has a problem (something not working, order stuck/late, can't log in, no notifications, taxi issue, app glitch): look at their REAL state — account, active orders with how long they've waited, taxi ride, open support tickets, saved addresses, push registration, device/app info — and returns spotted findings.",
    { area: { type: "string", description: "orders|taxi|account|notifications|app|services|community|payments|other" } }
  ),
  fn(
    "escalate_to_admin",
    "Open a real support ticket for the user and alert the admins (urgent notification). ONLY when you couldn't solve it yourself AND the user agreed (or explicitly asked for support/admin). Include what you both already tried.",
    {
      domain: { type: "string", enum: ESCALATION_DOMAINS },
      problem: { type: "string", description: "Clear summary of the problem in Arabic (what, since when, which order/ride)" },
      steps_tried: { type: "array", items: { type: "string" }, maxItems: 6 },
      urgency: { type: "string", enum: ["high", "urgent"], description: "urgent = money/safety/blocked from using the app now" },
      order_id: { type: "integer" },
    },
    ["domain", "problem"]
  ),
  fn(
    "my_support_tickets",
    "The user's recent support tickets: status, the latest reply from the support team, and the resolution. Use when they ask about their complaint/ticket or after you escalated.",
  ),

  // ---- the final answer (ends the turn) ----
  fn(
    "respond",
    "Your FINAL answer to the user, always exactly once per turn, after any data tools. `text` is what Mimo says (short, in the user's language). Attach cards/buttons only with ids you got from tools.",
    {
      text: { type: "string", description: "What Mimo says — natural and spontaneous. App tasks: 1-3 sentences (items go in cards). Explanations/knowledge: up to ~8 short lines." },
      mood: { type: "string", enum: MOODS },
      cards_title: { type: "string" },
      stores: {
        type: "array",
        maxItems: 6,
        items: {
          type: "object",
          properties: { store_id: { type: "integer" }, note: { type: "string", description: "Your short personal note on why it fits" } },
          required: ["store_id", "note"],
          additionalProperties: false,
        },
      },
      products: {
        type: "array",
        maxItems: 6,
        items: {
          type: "object",
          properties: { product_id: { type: "integer" }, note: { type: "string" } },
          required: ["product_id", "note"],
          additionalProperties: false,
        },
      },
      replies: {
        type: "array",
        maxItems: 6,
        items: { type: "string" },
        description: "2-6 short tappable replies in the user's language",
      },
      cart_add: {
        type: "object",
        description: "Confirm card to add a product to the cart — only after the user agreed/asked. The user confirms in the app.",
        properties: {
          product_id: { type: "integer" },
          store_id: { type: "integer" },
          quantity: { type: "integer", minimum: 1, maximum: 20 },
        },
        required: ["product_id"],
        additionalProperties: false,
      },
      cart_bundle: {
        type: "array",
        maxItems: 20,
        description: "Several products to add with ONE confirm (party plans, reorders) — only after the user agreed/asked.",
        items: {
          type: "object",
          properties: {
            product_id: { type: "integer" },
            store_id: { type: "integer" },
            quantity: { type: "integer", minimum: 1, maximum: 50 },
          },
          required: ["product_id", "store_id", "quantity"],
          additionalProperties: false,
        },
      },
      services: {
        type: "array",
        maxItems: 6,
        items: {
          type: "object",
          properties: { service_id: { type: "integer" }, note: { type: "string" } },
          required: ["service_id", "note"],
          additionalProperties: false,
        },
      },
      quote: {
        type: "boolean",
        description: "Attach the last quote_order result as a bill card.",
      },
      sources: {
        type: "boolean",
        description: "Show the web/learned sources you used (true when you answered from web_search).",
      },
      open_section: { type: "string", enum: APP_SECTIONS.map((x) => x.key) },
    },
    ["text", "mood"]
  ),
];

export const DISPLAY_TOOLS = new Set(["respond"]);

/** Human status line shown while a data tool runs (Mimo "thinking out loud"). */
export function toolStatusLine(name, args = {}, lang = "ar") {
  const ar = lang !== "en";
  const kw = Array.isArray(args.keywords) ? args.keywords[0] : args.query;
  switch (name) {
    case "list_store_categories":
      return ar ? "أشوف أقسام التطبيق..." : "Looking at the app sections...";
    case "list_subcategories":
      return ar ? "أشوف الأنواع..." : "Checking the types...";
    case "find_stores":
      return ar ? "أدوّر على المحلات وأقارن التقييمات..." : "Comparing stores and ratings...";
    case "search_products":
      return ar ? `أدوّر على «${str(kw, 30)}»...` : `Searching for "${str(kw, 30)}"...`;
    case "get_store_menu":
      return ar ? "أفتح المنيو..." : "Opening the menu...";
    case "pick_for_me":
      return ar ? "دا أختارلك الأحسن..." : "Picking the best one for you...";
    case "my_recent_orders":
      return ar ? "أشوف طلباتك..." : "Checking your orders...";
    case "my_coupons":
      return ar ? "أشوف كوبوناتك..." : "Checking your coupons...";
    case "calculate":
      return ar ? "أحسبها بالضبط..." : "Doing the math...";
    case "quote_order":
      return ar ? "أحسبلك الفاتورة ويه التوصيل..." : "Calculating the full bill...";
    case "reorder_last":
      return ar ? "أجيب طلبك السابق..." : "Fetching your previous order...";
    case "search_services":
      return ar ? "أدوّر على أحسن فنيين..." : "Finding the best providers...";
    case "store_info":
      return ar ? "أشوف أوقات الدوام والتوصيل..." : "Checking hours and delivery...";
    case "remember":
      return ar ? "حفظتها ببالي..." : "Noted...";
    case "web_search":
      return ar ? `أدوّر بالإنترنت عن «${str(args.query, 40)}»...` : `Searching the web for "${str(args.query, 40)}"...`;
    case "think_deeply":
      return ar ? "دا أفكر بيها زين، لحظة..." : "Thinking it through carefully...";
    case "recall_knowledge":
      return ar ? "أتذكر شنو علموني..." : "Checking what I've learned...";
    case "learn_fact":
      return ar ? "أتأكد من المعلومة بالإنترنت قبل لا أحفظها..." : "Verifying it online before I learn it...";
    case "app_guide":
      return ar ? "أراجع شلون يشتغل التطبيق..." : "Checking how the app works...";
    case "diagnose_problem":
      return ar ? "أفحص حسابك وطلباتك حتى ألگى المشكلة..." : "Checking your account and orders...";
    case "escalate_to_admin":
      return ar ? "أبلّغ الإدارة هسه..." : "Alerting the support team...";
    case "my_support_tickets":
      return ar ? "أشوف شكواك وين وصلت..." : "Checking your support tickets...";
    case "forget":
      return ar ? "نسيتها..." : "Forgetting...";
    default:
      return ar ? "لحظة أفكر..." : "Thinking...";
  }
}

/**
 * Did the user agree to (or ask for) contacting support/admins? Either they
 * asked directly, or Mimo offered and they said yes.
 */
export function agreedToEscalate(userMessage, previousMimoMessage) {
  const u = String(userMessage || "");
  const m = String(previousMimoMessage || "");
  const asksSupport = /(الإدارة|الادارة|الدعم|موظف|بلّغ|بلغ|ارفعها|ارفع شكوى|اشتكي|أشتكي|شكوى|كلم احد|كلّم احد|admin|support|complain|escalate|human)/i.test(u);
  const offered = /(الإدارة|الادارة|الدعم|أرفعها|ارفعها|أبلّغ|ابلغ|support|admin)/i.test(m);
  const yes = /^(\s)*(اي|إي|ايه|إيه|نعم|اكيد|أكيد|اوكي|أوكي|تمام|يلا|ارفعها|إي ارفعها|ok|okay|yes|sure|please)/i.test(u);
  return asksSupport || (offered && yes);
}

/**
 * Evaluates + - * / and parentheses over numbers (with optional thousands
 * separators) without eval(). Returns null on anything else.
 */
export function safeArithmetic(input) {
  const src = String(input ?? "")
    .replace(/[٠-٩]/g, (d) => String("٠١٢٣٤٥٦٧٨٩".indexOf(d)))
    .replace(/(\d),(?=\d{3}\b)/g, "$1")
    .replace(/[×x]/g, "*")
    .replace(/÷/g, "/");
  if (!/^[\d\s+\-*/().]+$/.test(src) || src.length > 200) return null;
  let i = 0;
  const peek = () => src[i];
  const skip = () => {
    while (src[i] === " ") i += 1;
  };
  function number() {
    skip();
    const m = /^\d+(\.\d+)?/.exec(src.slice(i));
    if (!m) throw new Error("num");
    i += m[0].length;
    return Number(m[0]);
  }
  function factor() {
    skip();
    if (peek() === "-") {
      i += 1;
      return -factor();
    }
    if (peek() === "(") {
      i += 1;
      const v = expr();
      skip();
      if (peek() !== ")") throw new Error("paren");
      i += 1;
      return v;
    }
    return number();
  }
  function term() {
    let v = factor();
    for (;;) {
      skip();
      const op = peek();
      if (op !== "*" && op !== "/") return v;
      i += 1;
      const r = factor();
      v = op === "*" ? v * r : v / r;
    }
  }
  function expr() {
    let v = term();
    for (;;) {
      skip();
      const op = peek();
      if (op !== "+" && op !== "-") return v;
      i += 1;
      const r = term();
      v = op === "+" ? v + r : v - r;
    }
  }
  try {
    const v = expr();
    skip();
    if (i !== src.length || !Number.isFinite(v)) return null;
    return Math.round(v * 100) / 100;
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Mapping helpers
// ---------------------------------------------------------------------------

export function compactStore(row, now = Date.now()) {
  const createdAt = row.created_at ? new Date(row.created_at).getTime() : null;
  const etaMin = num(row.delivery_eta_min_minutes);
  const etaMax = num(row.delivery_eta_max_minutes);
  return {
    id: Number(row.id),
    name: str(row.name, 60),
    type: row.type,
    activityType: row.activity_type || row.type,
    subcategories: Array.isArray(row.discovery_subcategories)
      ? row.discovery_subcategories.slice(0, 6)
      : [],
    description: str(row.description || row.tagline, 140) || null,
    rating: Math.round((num(row.avg_merchant_rating) || 0) * 10) / 10,
    ratingsCount: num(row.rating_count) || 0,
    completedOrders: num(row.completed_orders_count) || 0,
    isOpen: row.is_open === true,
    isNew: createdAt != null && now - createdAt < 30 * MS_DAY,
    avgItemPrice: num(row.avg_menu_price) ? Math.round(num(row.avg_menu_price)) : null,
    deliveryMinutes: etaMin || etaMax ? `${etaMin ?? etaMax}-${etaMax ?? etaMin}` : null,
    deliveryFee: num(row.delivery_fee),
    hasOffer: row.has_discount_offer === true,
    freeDelivery: row.has_free_delivery_offer === true,
    opensAt: row.is_open === true ? undefined : row.next_open_at || undefined,
  };
}

/** Store card payload for the app (also what Flutter's MerchantModel reads). */
export function storeCard(row) {
  return {
    ...compactStore(row),
    imageUrl: row.image_url || null,
    logoUrl: row.logo_url || null,
    coverImageUrl: row.cover_image_url || null,
  };
}

export function compactProduct(item) {
  return {
    id: Number(item.productId),
    name: str(item.name, 70),
    description: str(item.description, 100) || null,
    price: num(item.finalPrice) ?? num(item.price),
    originalPrice: num(item.price),
    discountPercent: num(item.discountPercent) || 0,
    offer: item.offerLabel || null,
    hasOptions: item.hasVariants === true,
    available: item.isAvailable !== false,
    orders: num(item.stats?.ordersCount ?? item.ordersCount) || 0,
    store: item.merchant
      ? {
          id: Number(item.merchant.id),
          name: str(item.merchant.name, 60),
          rating: Math.round((num(item.merchant.rating) || 0) * 10) / 10,
          type: item.merchant.type,
        }
      : null,
  };
}

function menuItemToSearchShape(row, store) {
  const price = num(row.price);
  const discounted = num(row.discounted_price);
  return {
    productId: row.id,
    name: row.name,
    description: row.description,
    price,
    finalPrice: discounted != null && discounted > 0 ? discounted : price,
    discountPercent:
      discounted != null && price ? Math.round(100 * (1 - discounted / price)) : 0,
    offerLabel: row.offer_label || null,
    hasVariants: row.hasVariants === true,
    isAvailable: row.is_available !== false,
    imageUrl: row.imageUrl || row.image_url || null,
    merchant: store
      ? { id: store.id, name: store.name, rating: store.avg_merchant_rating, type: store.type }
      : { id: row.merchant_id },
  };
}

function sortStores(rows, sort) {
  const r = [...rows];
  const rating = (x) => num(x.avg_merchant_rating) || 0;
  const orders = (x) => num(x.completed_orders_count) || 0;
  const created = (x) => (x.created_at ? new Date(x.created_at).getTime() : 0);
  const price = (x) => num(x.avg_menu_price) ?? Number.MAX_SAFE_INTEGER;
  const eta = (x) => num(x.delivery_eta_max_minutes) ?? num(x.delivery_eta_min_minutes) ?? 999;
  const open = (x) => (x.is_open === true ? 1 : 0);
  const cmp = {
    top_rated: (a, b) => rating(b) - rating(a) || (num(b.rating_count) || 0) - (num(a.rating_count) || 0),
    most_ordered: (a, b) => orders(b) - orders(a) || rating(b) - rating(a),
    newest: (a, b) => created(b) - created(a),
    cheapest: (a, b) => price(a) - price(b),
    fastest: (a, b) => eta(a) - eta(b),
    // Bayesian-ish blend: rating weighted by confidence + popularity.
    best: (a, b) => {
      const score = (x) =>
        open(x) * 2 +
        ((rating(x) * (num(x.rating_count) || 0) + 4 * 5) / ((num(x.rating_count) || 0) + 5)) +
        Math.log10(1 + orders(x)) * 0.8;
      return score(b) - score(a);
    },
  }[sort] || null;
  if (cmp) r.sort((a, b) => open(b) - open(a) || cmp(a, b));
  return r;
}

// ---------------------------------------------------------------------------
// Default data access (lazy so unit tests can inject fakes)
// ---------------------------------------------------------------------------

export function createDefaultMimoDeps() {
  const lazy = (path) => import(path);
  return {
    async listActivities() {
      const m = await lazy("../merchants/store-activity.registry.js");
      return m.listActivityRegistry();
    },
    async listSubcategories(activityType) {
      const m = await lazy("../merchants/store-activity.registry.js");
      return m.listDiscoveryOptions(activityType);
    },
    async listStores({ activityType, subcategory, query, department } = {}) {
      const m = await lazy("../merchants/merchants.repo.js");
      return m.getAllMerchants(null, query || null, {
        activityType: activityType || undefined,
        discoverySubcategory: subcategory || undefined,
        department: department || undefined,
      });
    },
    async searchProducts(userId, params) {
      const m = await lazy("../commerce/commerce.repo.js");
      const res = await m.searchProductsGlobal(userId, params);
      return Array.isArray(res?.items) ? res.items : [];
    },
    async storeMenu(storeId, params) {
      const m = await lazy("../merchants/merchants.service.js");
      return m.listMerchantProducts(storeId, params);
    },
    async recentOrders(userId, limit) {
      const m = await lazy("../orders/orders.repo.js");
      return m.listCustomerOrders(userId, { paginate: true, limit });
    },
    async coupons(userId) {
      const m = await lazy("../coupons/coupons.repo.js");
      return m.listCustomerCoupons({ customerId: userId, limit: 10 });
    },
    async previewOrder(userId, dto) {
      const m = await lazy("../orders/orders.service.js");
      return m.previewOrder(userId, dto);
    },
    async searchServices(query, userId) {
      const m = await lazy("../services/services.service.js");
      return m.searchPublicOfferings(query, userId);
    },
  };
}

// ---------------------------------------------------------------------------
// Tool runner
// ---------------------------------------------------------------------------

export function createMimoToolbox({
  deps = createDefaultMimoDeps(),
  memoryDeps = null,
  memory = null,
  llm = null,
  knowledgeDeps = null,
  signal = null,
  supportDeps = null,
  clientInfo = {},
  userName = null,
  transcript = () => "",
  attachments = [],
  userId,
  lang = "ar",
  random = Math.random,
} = {}) {
  // Learning traces for this turn.
  const searchLog = [];
  const rememberedThisTurn = new Set();
  let lastUserMessage = "";
  let escalatedThisTurn = false;
  let transcriptText = "";
  let lastTicket = null;
  let lastMimoMessage = "";
  let learnedThisTurn = false;
  const shownProductIds = new Set();
  const seenServices = new Map();
  let lastQuote = null;
  let lastSources = [];
  let usedWeb = false;
  // Safety net: never put a dish that may contain the user's allergen in a card.
  const allergens = allergenWords(memory);
  const mayContainAllergen = (item) => {
    if (!allergens.length) return false;
    const hay = `${item?.name || ""} ${item?.description || ""} ${item?.categoryName || ""}`;
    return allergens.some((w) => hay.includes(w));
  };
  let filteredForAllergy = 0;
  let shownFood = false;
  let synonymCache = null;

  async function learnedAliases(words) {
    if (!memoryDeps?.synonymsFor) return [];
    try {
      synonymCache ??= new Map();
      const missing = words.filter((w) => !synonymCache.has(w));
      if (missing.length) {
        const rows = await memoryDeps.synonymsFor(missing);
        for (const w of missing) synonymCache.set(w, []);
        for (const r of rows) synonymCache.get(r.term)?.push(r.alias);
      }
      return words.flatMap((w) => synonymCache.get(w) || []);
    } catch {
      return [];
    }
  }
  // Everything Mimo has "seen" this turn, so display tools can render full cards.
  const seenStores = new Map();
  const seenProducts = new Map();
  let allStoresCache = null;

  async function allStores() {
    if (!allStoresCache) {
      allStoresCache = await deps.listStores({});
      for (const row of allStoresCache) seenStores.set(Number(row.id), row);
    }
    return allStoresCache;
  }

  function rememberStores(rows) {
    for (const row of rows) seenStores.set(Number(row.id), row);
  }

  async function searchMany({ keywords, store_type, max_price, only_offers, limit = 10 }) {
    const asked = [...new Set((keywords || []).map((k) => str(k, 40)).filter(Boolean))].slice(0, 4);
    const learned = await learnedAliases(asked);
    const words = [...new Set([...asked, ...learned])].slice(0, 6);
    const merged = new Map();
    for (const word of words) {
      let items = [];
      try {
        items = await deps.searchProducts(userId, {
          q: word,
          merchantType: store_type || null,
          maxPrice: max_price ?? null,
          onlyAvailable: true,
          onlyDiscounted: only_offers === true,
          limit: 15,
          sort: "best_offers",
        });
      } catch {
        items = [];
      }
      for (const item of items) {
        const id = Number(item.productId);
        if (!merged.has(id)) merged.set(id, item);
      }
      searchLog.push({ word, count: items.length, productIds: items.map((i) => Number(i.productId)) });
    }
    const list = [...merged.values()];
    for (const item of list) seenProducts.set(Number(item.productId), item);
    return list.slice(0, clampInt(limit, 1, 20, 10));
  }

  const handlers = {
    async list_store_categories() {
      const acts = await deps.listActivities();
      return {
        storeCategories: acts
          .filter((a) => a.isActive !== false)
          .map((a) => ({
            activity_type: a.activityType,
            ar: a.displayNameAr,
            en: a.displayNameEn,
            hasSubcategories: a.hasDiscoverySubcategories === true,
          })),
        appSections: APP_SECTIONS,
      };
    },

    async list_subcategories({ activity_type }) {
      const opts = await deps.listSubcategories(String(activity_type || ""));
      return { subcategories: opts.map((o) => ({ code: o.code, ar: o.labelAr, en: o.labelEn })) };
    },

    async find_stores(args = {}) {
      const rows = await deps.listStores({
        activityType: args.activity_type,
        subcategory: args.subcategory,
        query: args.query,
        department: args.department,
      });
      rememberStores(rows);
      let list = args.open_now ? rows.filter((r) => r.is_open === true) : rows;
      // Asked for a store by name but it's closed: say so right away.
      const closedMatches =
        args.open_now && args.query
          ? rows.filter((r) => r.is_open !== true && String(r.name || "").includes(String(args.query).trim()))
          : [];
      list = sortStores(list, SORTS.includes(args.sort) ? args.sort : "best");
      const limit = clampInt(args.limit, 1, 8, 6);
      return {
        total: list.length,
        openNow: rows.filter((r) => r.is_open === true).length,
        stores: list.slice(0, limit).map((r) => compactStore(r)),
        closedMatches: closedMatches.length ? closedMatches.slice(0, 3).map((r) => compactStore(r)) : undefined,
        hint: rows.length
          ? undefined
          : "No store matched these filters — this does NOT mean closed. Retry without activity_type/subcategory, or use search_products.",
      };
    },

    async search_products(args = {}) {
      const items = await searchMany(args);
      return {
        count: items.length,
        products: items.map(compactProduct),
        hint: items.length ? undefined : "No match. Try other spellings/synonyms or a broader word.",
      };
    },

    async get_store_menu({ store_id, query, limit }) {
      const storeId = Number(store_id);
      const stores = await allStores();
      const store = stores.find((s) => Number(s.id) === storeId) || null;
      const rows = await deps.storeMenu(storeId, {
        search: query || undefined,
        limit: clampInt(limit, 1, 20, 12),
        onlyAvailable: true,
      });
      const items = rows.map((row) => menuItemToSearchShape(row, store));
      for (let i = 0; i < items.length; i += 1) {
        seenProducts.set(Number(items[i].productId), { ...items[i], _raw: rows[i] });
      }
      return {
        store: store ? compactStore(store) : { id: storeId },
        products: items.map(compactProduct),
      };
    },

    async pick_for_me(args = {}) {
      const items = await searchMany({ ...args, limit: 20 });
      if (!items.length) {
        return { found: false, hint: "Nothing matches. Ask the user or try other words." };
      }
      const stores = await allStores();
      const byId = new Map(stores.map((s) => [Number(s.id), s]));
      const groups = new Map();
      for (const item of items) {
        const sid = Number(item.merchant?.id);
        if (!groups.has(sid)) groups.set(sid, []);
        groups.get(sid).push(item);
      }
      const orders = (sid) => num(byId.get(sid)?.completed_orders_count) || 0;
      const rating = (sid) =>
        num(byId.get(sid)?.avg_merchant_rating) ?? num(groups.get(sid)?.[0]?.merchant?.rating) ?? 0;
      const open = (sid) => (byId.get(sid)?.is_open === false ? 0 : 1);
      const ranked = [...groups.keys()].sort(
        (a, b) => open(b) - open(a) || orders(b) - orders(a) || rating(b) - rating(a)
      );
      const top = ranked[0];
      const ties = ranked.filter(
        (s) => open(s) === open(top) && orders(s) === orders(top) && rating(s) === rating(top)
      );
      const chosen = ties[Math.floor(random() * ties.length)] ?? top;
      const dishes = [...groups.get(chosen)].sort(
        (a, b) =>
          (num(b.stats?.ordersCount) || 0) - (num(a.stats?.ordersCount) || 0) ||
          (num(a.finalPrice) || 0) - (num(b.finalPrice) || 0)
      );
      const store = byId.get(chosen);
      return {
        found: true,
        rule: "most completed orders → best rating → random tie",
        store: store ? compactStore(store) : { id: chosen },
        dish: compactProduct(dishes[0]),
        otherDishesSameStore: dishes.slice(1, 3).map(compactProduct),
        alternatives: ranked
          .filter((s) => s !== chosen)
          .slice(0, 2)
          .map((s) => ({
            store: byId.get(s) ? compactStore(byId.get(s)) : { id: s },
            dish: compactProduct(groups.get(s)[0]),
          })),
      };
    },

    async my_recent_orders({ limit } = {}) {
      const rows = await deps.recentOrders(userId, clampInt(limit, 1, 5, 3));
      return {
        orders: rows.slice(0, 5).map((o) => ({
          id: Number(o.id),
          status: o.status,
          store: str(o.merchant_name || o.merchantName, 50),
          total: num(o.total_amount ?? o.totalAmount),
          createdAt: o.created_at || o.createdAt,
          items: (o.items || [])
            .slice(0, 5)
            .map((i) => `${str(i.product_name || i.productName || i.name, 40)} ×${i.quantity}`),
        })),
      };
    },

    async quote_order({ stores, coupon_code }) {
      const storeOrders = (stores || []).slice(0, 3).map((s) => ({
        merchantId: Number(s.store_id),
        couponCode: coupon_code ? String(coupon_code).trim().toUpperCase() : null,
        items: (s.items || []).slice(0, 20).map((i) => ({
          productId: Number(i.product_id),
          quantity: clampInt(i.quantity, 1, 50, 1),
        })),
      }));
      try {
        const out = await deps.previewOrder(userId, { storeOrders });
        const t = out?.totals || {};
        lastQuote = {
          exact: true,
          stores: (out?.stores || []).map((s) => ({
            store: str(s.merchantName, 50),
            items: (s.items || []).map((i) => ({
              name: str(i.productName || i.product_name || i.name, 50),
              quantity: Number(i.quantity) || 1,
              lineTotal: num(i.lineTotal ?? i.line_total),
            })),
            subtotal: num(s.pricing?.subtotalAfterAllDiscounts ?? s.pricing?.grossSubtotal),
            delivery: num(s.pricing?.deliveryFee),
            serviceFee: num(s.pricing?.serviceFee),
            total: num(s.pricing?.totalAmount),
          })),
          subtotal: num(t.grossSubtotal),
          discounts: (num(t.productDiscountTotal) || 0) + (num(t.couponDiscountTotal) || 0),
          couponDiscount: num(t.couponDiscountTotal) || 0,
          delivery: num(t.deliveryFeeTotal),
          serviceFee: num(t.serviceFeeTotal),
          total: num(t.totalAmount),
          multiStoreNotice: out?.multiStoreDelayNotice ? str(out.multiStoreDelayNotice, 160) : undefined,
        };
        return lastQuote;
      } catch (error) {
        // No saved address / item problem → honest estimate from seen prices.
        let subtotal = 0;
        const unknown = [];
        for (const s of storeOrders) {
          for (const i of s.items) {
            const p = seenProducts.get(i.productId);
            const price = num(p?.finalPrice ?? p?.price);
            if (price == null) unknown.push(i.productId);
            else subtotal += price * i.quantity;
          }
        }
        lastQuote = {
          exact: false,
          subtotal,
          total: null,
          reason: str(error?.message, 80),
          note: "Items subtotal only; delivery & service fees are added at checkout (no saved address or preview failed).",
          unknownPrices: unknown.length ? unknown : undefined,
        };
        return lastQuote;
      }
    },

    async reorder_last({ which } = {}) {
      const idx = clampInt(which, 1, 5, 1) - 1;
      const rows = await deps.recentOrders(userId, idx + 1);
      const o = rows[idx];
      if (!o) return { found: false };
      const sid = Number(o.merchant_id);
      const items = (o.items || []).slice(0, 20).map((i) => {
        const id = Number(i.product_id || i.productId);
        const item = {
          productId: id,
          name: i.product_name || i.name,
          price: num(i.unit_price ?? i.unitPrice),
          finalPrice: num(i.unit_price ?? i.unitPrice),
          merchant: { id: sid, name: o.merchant_name },
        };
        seenProducts.set(id, item);
        return { product_id: id, store_id: sid, name: str(item.name, 50), quantity: Number(i.quantity) || 1, unitPrice: item.price };
      });
      return {
        found: true,
        orderId: Number(o.id),
        store: { id: sid, name: str(o.merchant_name, 50) },
        status: o.status,
        createdAt: o.created_at,
        total: num(o.total_amount),
        items,
      };
    },

    async search_services({ keywords, max_price }) {
      const out = new Map();
      for (const word of (keywords || []).slice(0, 3)) {
        let rows = [];
        try {
          rows = await deps.searchServices(
            { q: str(word, 60), maxPrice: max_price ?? undefined, limit: 8, offset: 0, sort: "rating" },
            userId
          );
        } catch {
          rows = [];
        }
        for (const r of rows || []) {
          const id = Number(r.id ?? r.offeringId ?? r.offering_id);
          if (!id || out.has(id)) continue;
          const svc = {
            id,
            title: str(r.title ?? r.name ?? r.offering_title, 70),
            provider: str(r.providerName ?? r.provider_name ?? r.provider?.displayName ?? r.provider?.name, 50),
            price: r.pricingDisplay ?? r.priceDisplay ?? r.price_display ?? num(r.price ?? r.base_price ?? r.starting_price),
            rating: Math.round((num(r.ratingAvg ?? r.rating_avg ?? r.rating ?? r.provider?.ratingAvg) || 0) * 10) / 10,
            reviews: num(r.ratingCount ?? r.rating_count ?? r.reviewsCount) || 0,
            category: str(r.categoryName ?? r.category_name, 40) || null,
            imageUrl: r.coverImageUrl ?? r.cover_image_url ?? r.imageUrl ?? r.image_url ?? null,
          };
          out.set(id, svc);
          seenServices.set(id, svc);
        }
      }
      const list = [...out.values()];
      return {
        count: list.length,
        services: list.slice(0, 8).map(({ imageUrl: _i, ...rest }) => rest),
        hint: list.length ? undefined : "Nothing found — try another word or open the services section.",
      };
    },

    async store_info({ store_id }) {
      const stores = await allStores();
      const row = stores.find((s) => Number(s.id) === Number(store_id));
      if (!row) return { found: false };
      return {
        ...compactStore(row),
        workingHours: str(row.working_hours, 200) || null,
        nextOpenAt: row.next_open_at || null,
        minimumOrder: num(row.minimum_order),
      };
    },

    async web_search({ query }) {
      if (!llm?.complete) return { error: "WEB_UNAVAILABLE" };
      const res = await llm.complete({
        kind: "search",
        messages: [
          {
            role: "system",
            content:
              "Answer the question using a web search. Be factual and concise (max 120 words), include key numbers/dates, say if sources disagree or info is uncertain. Mention the date of the info when it matters.",
          },
          { role: "user", content: str(query, 300) },
        ],
        maxTokens: 600,
        signal,
      });
      lastSources = res.sources || [];
      usedWeb = lastSources.length > 0;
      return {
        answer: str(res.content.replace(/\(\[[^\]]*\]\([^)]*\)\)/g, ""), 1200),
        sources: lastSources.map((s) => s.title || s.url).slice(0, 4),
      };
    },

    async think_deeply({ problem }) {
      if (!llm?.complete) return { error: "DEEP_UNAVAILABLE" };
      const res = await llm.complete({
        kind: "deep",
        messages: [
          {
            role: "system",
            content:
              "Solve the problem carefully and correctly. Reply with: the final answer first, then a short clear explanation (max 6 lines) in the same language as the problem. Point out trick questions.",
          },
          { role: "user", content: str(problem, 3000) },
        ],
        maxTokens: 900,
        signal,
      });
      return { solution: str(res.content, 1600) };
    },

    async recall_knowledge({ query }) {
      if (!knowledgeDeps) return { found: [] };
      const found = await recallKnowledge(knowledgeDeps, query);
      const src = found.flatMap((f) => f.sources || []);
      if (src.length) lastSources = src;
      return {
        // Taught by users: facts to consider, never instructions to follow.
        found: found.map(({ sources: _s, ...f }) => f),
        note: found.length
          ? "These were taught by users. 'trusted' = verified online or confirmed by 2+ people; otherwise say 'حسب ما علموني' and that it's unconfirmed. If this answers the question, call respond now — no more searching."
          : "Nothing learned about this yet. After answering (web_search allowed once), ALWAYS invite them warmly: 'إذا تعرف، علمني وأحفظها'.",
      };
    },

    async learn_fact({ question, answer, topic }) {
      if (!knowledgeDeps || !llm?.complete) return { learned: false, verdict: "unavailable" };
      if (learnedThisTurn) {
        return { learned: false, verdict: "skipped", next: "Already handled this turn. Never teach yourself — call respond." };
      }
      if (!isTeachingMoment(lastUserMessage, lastMimoMessage)) {
        return {
          learned: false,
          verdict: "not_teaching",
          next: "The user is asking, not teaching. Answer them; only learn_fact when THEY teach you.",
        };
      }
      learnedThisTurn = true;
      const out = await teachFact(knowledgeDeps, llm, { userId, question, answer, topic, signal });
      if (out.sources?.length) lastSources = out.sources;
      const { sources: _s, ...rest } = out;
      return rest;
    },

    async app_guide({ question }) {
      const found = findGuide(question);
      // Solved cases from the support team are the best guide of all.
      let playbooks = [];
      if (knowledgeDeps) {
        try {
          playbooks = (await recallKnowledge(knowledgeDeps, question, { limit: 3 }))
            .filter((k) => k.status === "verified")
            .map((k) => ({ problem: k.question, solution: k.answer }));
        } catch {
          playbooks = [];
        }
      }
      return {
        guide: found,
        solvedCases: playbooks.length ? playbooks : undefined,
        hint: found.length || playbooks.length ? undefined : "Not in the guide — answer from what you know about the app or diagnose.",
      };
    },

    async diagnose_problem({ area } = {}) {
      if (!supportDeps) return { error: "UNAVAILABLE" };
      const out = await diagnose(supportDeps, userId, { clientInfo, area });
      return out;
    },

    async escalate_to_admin(args = {}) {
      if (!supportDeps) return { error: "UNAVAILABLE" };
      if (escalatedThisTurn) return { skipped: true, next: "Already escalated — call respond." };
      if (!agreedToEscalate(lastUserMessage, lastMimoMessage)) {
        return {
          escalated: false,
          reason: "NEEDS_USER_OK",
          next: "Ask the user first: 'أرفعها للإدارة؟' with replies ['إي ارفعها','لا هسه'] — then escalate when they agree.",
        };
      }
      // Don't spam the team: reuse an open Mimo ticket instead of a new one.
      const open = (await supportDeps.myTickets(userId).catch(() => [])).find(
        (t) => t.channel === "mimo" && !["RESOLVED", "CLOSED"].includes(String(t.status))
      );
      escalatedThisTurn = true;
      if (open) {
        await supportDeps
          .addMimoNote(open.id, `تحديث من ميمو: ${str(args.problem, 600)}`)
          .catch(() => {});
        lastTicket = { ticketId: Number(open.id), ticketNumber: open.ticket_number, existing: true };
        return { escalated: true, existingTicket: true, ...lastTicket, status: open.status };
      }
      const out = await escalate(supportDeps, userId, {
        domain: args.domain,
        problem: args.problem,
        stepsTried: args.steps_tried || [],
        urgency: args.urgency,
        orderId: args.order_id || null,
        attachments,
        userName,
        transcript: transcriptText || transcript(),
      });
      lastTicket = out;
      return { escalated: true, ...out };
    },

    async my_support_tickets() {
      if (!supportDeps) return { tickets: [] };
      return { tickets: await ticketsStatus(supportDeps, userId) };
    },

    async remember({ key, value }) {
      if (!memoryDeps || !memory) return { saved: false, reason: "MEMORY_UNAVAILABLE" };
      const sig = `${key}|${str(value, 80)}`;
      if (!statesPersonalFact(lastUserMessage)) {
        return {
          saved: false,
          reason: "NOT_A_STATED_FACT",
          next: "The user didn't state a lasting fact about themselves in this message — don't save it. Continue or call respond.",
        };
      }
      if (rememberedThisTurn.has(sig) || rememberedThisTurn.size >= 3) {
        return { saved: true, alreadyNoted: true, next: "Done. Don't call remember again — continue or call respond." };
      }
      rememberedThisTurn.add(sig);
      const out = await rememberFact(memoryDeps, userId, memory, { key, value });
      return { ...out, next: "Saved. Don't call remember again for this — continue or call respond." };
    },

    async forget({ key, everything }) {
      if (!memoryDeps || !memory) return { forgotten: null };
      return forgetFact(memoryDeps, userId, memory, { key, everything });
    },

    async calculate({ expressions, expression }) {
      const list = (Array.isArray(expressions) ? expressions : [expression]).slice(0, 6);
      const results = list.map((e) => ({ expression: str(e, 200), result: safeArithmetic(e) }));
      return {
        results,
        result: results.at(-1)?.result ?? null,
        hint: results.some((r) => r.result == null) ? "Use only numbers and + - * / ( )" : undefined,
      };
    },

    async my_coupons() {
      const rows = await deps.coupons(userId);
      return {
        coupons: rows.slice(0, 8).map((c) => ({
          code: c.code,
          discount:
            c.discount_type === "fixed"
              ? `${num(c.discount_value)} IQD`
              : `${num(c.discount_value)}%`,
          minOrder: num(c.min_order_total),
          scope: c.scope_kind,
          store: c.merchant_name || c.company_name || null,
          validUntil: c.valid_until || null,
        })),
      };
    },
  };

  /** Builds one UI event (or null if unusable). */
  async function displayPart(name, args = {}) {
    switch (name) {
      case "show_stores": {
        const cards = [];
        for (const it of args.items || []) {
          let row = seenStores.get(Number(it.store_id));
          if (!row) {
            row = (await allStores()).find((s) => Number(s.id) === Number(it.store_id));
          }
          if (row) cards.push({ ...storeCard(row), note: str(it.note, 140) });
        }
        return cards.length ? { type: "stores", title: str(args.title, 60) || null, items: cards } : null;
      }
      case "show_products": {
        const cards = [];
        for (const it of args.items || []) {
          const item = seenProducts.get(Number(it.product_id));
          if (!item) continue;
          if (mayContainAllergen(item)) {
            filteredForAllergy += 1;
            continue;
          }
          shownFood = true;
          shownProductIds.add(Number(it.product_id));
          cards.push({
            ...compactProduct(item),
            imageUrl: item.imageUrl || item.primaryMedia?.imageUrl || null,
            note: str(it.note, 140),
          });
        }
        return cards.length ? { type: "products", title: str(args.title, 60) || null, items: cards } : null;
      }
      case "suggest_replies": {
        const options = (args.options || []).map((o) => str(o, 40)).filter(Boolean).slice(0, 6);
        return options.length ? { type: "replies", options } : null;
      }
      case "propose_cart_add": {
        const id = Number(args.product_id);
        const item = seenProducts.get(id) || null;
        const storeId = Number(item?.merchant?.id || args.store_id);
        if (!storeId) return null;
        let product = item?._raw || null;
        if (!product) {
          try {
            const rows = await deps.storeMenu(storeId, { productIds: [id], limit: 1 });
            product = rows[0] || null;
          } catch {
            product = null;
          }
        }
        if (!product) return null;
        const store = seenStores.get(storeId) || (await allStores()).find((s) => Number(s.id) === storeId);
        return {
          type: "cart_proposal",
          quantity: clampInt(args.quantity, 1, 20, 1),
          product,
          store: { id: storeId, name: store?.name || item?.merchant?.name || "" },
          hasOptions: item?.hasVariants === true || product.hasVariants === true,
        };
      }
      case "open_section": {
        const section = APP_SECTIONS.find((s) => s.key === args.section);
        return section
          ? { type: "open_section", section: section.key, label: lang === "en" ? section.en : section.ar }
          : null;
      }
      case "set_mood":
        return { type: "mood", mood: MOODS.includes(args.mood) ? args.mood : "happy" };
      default:
        return null;
    }
  }

  /** The final `respond` call → ordered UI events. */
  async function display(name, args = {}) {
    if (name !== "respond") return [];
    const events = [];
    const push = (e) => e && events.push(e);
    if (Array.isArray(args.stores) && args.stores.length) {
      push(await displayPart("show_stores", { title: args.cards_title, items: args.stores }));
    }
    if (Array.isArray(args.products) && args.products.length) {
      push(await displayPart("show_products", { title: args.cards_title, items: args.products }));
    }
    if (Array.isArray(args.services) && args.services.length) {
      const items = args.services
        .map((s) => {
          const svc = seenServices.get(Number(s.service_id));
          return svc ? { ...svc, note: str(s.note, 140) } : null;
        })
        .filter(Boolean);
      if (items.length) push({ type: "services", title: str(args.cards_title, 60) || null, items });
    }
    if (args.sources !== false && usedWeb && lastSources.length) {
      push({ type: "sources", items: lastSources.slice(0, 4) });
    }
    // A simulated bill is always worth showing (unless explicitly declined).
    if (args.quote !== false && lastQuote) push({ type: "quote", ...lastQuote });
    if (args.cart_add?.product_id) push(await displayPart("propose_cart_add", args.cart_add));
    if (Array.isArray(args.cart_bundle) && args.cart_bundle.length) {
      const bundle = [];
      for (const b of args.cart_bundle.slice(0, 20)) {
        const e = await displayPart("propose_cart_add", b);
        if (e) bundle.push({ product: e.product, store: e.store, quantity: e.quantity, hasOptions: e.hasOptions });
      }
      if (bundle.length) push({ type: "cart_bundle", items: bundle });
    }
    if (lastTicket) {
      push({
        type: "ticket",
        ticketId: lastTicket.ticketId,
        ticketNumber: lastTicket.ticketNumber || null,
        priority: lastTicket.priority || null,
        existing: lastTicket.existing === true,
      });
    }
    if (args.open_section) push(await displayPart("open_section", { section: args.open_section }));
    if (Array.isArray(args.replies) && args.replies.length >= 2) {
      push(await displayPart("suggest_replies", { options: args.replies }));
    }
    push(await displayPart("set_mood", { mood: args.mood || "happy" }));
    return events;
  }

  // Research budget per turn, so Mimo answers instead of over-researching.
  // (learn_fact has its own once-per-turn guard that ignores refused calls.)
  const BUDGET = { web_search: 2, recall_knowledge: 1, think_deeply: 1 };
  const used = new Map();
  const callCache = new Map();

  async function run(name, args) {
    const handler = handlers[name];
    if (!handler) return { error: "UNKNOWN_TOOL" };
    // Stateful tools depend on context — never answer them from the cache.
    const cacheable = !["learn_fact", "remember", "forget", "reorder_last"].includes(name);
    const sig = `${name}:${JSON.stringify(args || {})}`;
    if (cacheable && callCache.has(sig)) {
      return { ...callCache.get(sig), note: "Same call as before — you already have this. Don't repeat; call respond." };
    }
    const count = (used.get(name) || 0) + 1;
    used.set(name, count);
    if (BUDGET[name] && count > BUDGET[name]) {
      return { skipped: true, next: `Budget for ${name} reached — answer with what you have and call respond.` };
    }
    try {
      const out = await handler(args || {});
      if (cacheable) callCache.set(sig, out);
      return out;
    } catch (error) {
      return { error: "TOOL_FAILED", detail: str(error?.message, 120) };
    }
  }

  return {
    run,
    display,
    isDisplay: (name) => DISPLAY_TOOLS.has(name),
    learning: () => ({ searches: searchLog, shownProductIds }),
    safety: () => ({ hasAllergy: allergens.length > 0, filteredForAllergy, shownFood }),
    toolsUsed: () => [...used.keys()],
    setTranscript: (text) => {
      transcriptText = String(text || "");
    },
    setUserMessage: (text, previousMimo = "") => {
      lastUserMessage = String(text || "");
      lastMimoMessage = String(previousMimo || "");
    },
  };
}

import crypto from "crypto";

import { createOrder } from "../orders/orders.service.js";
import * as repo from "./assistant.repo.js";

const FIXED_SERVICE_FEE = 500;
const FIXED_DELIVERY_FEE = 1000;

const CHEAP_KEYWORDS = [
  "ارخص",
  "رخيص",
  "اقتصادي",
  "سعر",
  "اقل",
  "أقل",
  "low price",
  "cheap",
];

const TOP_RATED_KEYWORDS = [
  "افضل",
  "أفضل",
  "احسن",
  "أحسن",
  "اعلى تقييم",
  "أعلى تقييم",
  "top rated",
  "high rating",
];

const FREE_DELIVERY_KEYWORDS = [
  "توصيل مجاني",
  "بدون توصيل",
  "free delivery",
];

const FAST_KEYWORDS = ["سريع", "بسرعة", "عاجل", "quick", "fast"];
const ORDER_KEYWORDS = [
  "اطلب",
  "أطلب",
  "طلب",
  "اريد",
  "أريد",
  "ابغى",
  "ابي",
  "سو",
  "سوي",
  "جيب",
  "order",
];

const CONFIRM_KEYWORDS = [
  "موافق",
  "ثبت",
  "ثبته",
  "تثبيت",
  "تمام",
  "اوكي",
  "ok",
  "confirm",
];

const CANCEL_KEYWORDS = [
  "الغ",
  "إلغ",
  "الغاء",
  "إلغاء",
  "لا",
  "مو",
  "not now",
  "cancel",
];

const CATEGORY_HINTS = [
  { key: "burgers", words: ["بركر", "burger"] },
  { key: "pizza", words: ["بيتزا", "pizza"] },
  { key: "shawarma", words: ["شاورما"] },
  { key: "grills", words: ["مشاوي", "كباب", "شيش", "تكه"] },
  { key: "chicken", words: ["دجاج", "بروستد", "كرسبي"] },
  { key: "drinks", words: ["مشروب", "عصير", "بيبسي", "كوكا", "قهوة"] },
  { key: "sweets", words: ["حلويات", "كيك", "دونات", "تشيز"] },
  { key: "grocery", words: ["بقالة", "سوبر", "ماركت", "مواد"] },
  { key: "vegetables", words: ["خضار", "فواكه"] },
  { key: "bakery", words: ["معجنات", "خبز", "فرن"] },
];

const STOPWORDS = new Set([
  "ابي",
  "اريد",
  "أريد",
  "ابغى",
  "من",
  "على",
  "في",
  "الى",
  "إلى",
  "عن",
  "مع",
  "لو",
  "اذا",
  "إذا",
  "شنو",
  "شنوكم",
  "هذا",
  "هاي",
  "هذاك",
  "هذي",
  "يابه",
  "حبي",
  "حبيبي",
  "لوحدي",
  "وي",
  "و",
  "the",
  "a",
  "to",
  "for",
]);

function appError(message, status = 400) {
  const err = new Error(message);
  err.status = status;
  return err;
}

function normalizeDigits(value) {
  return String(value || "")
    .replace(/[\u0660-\u0669]/g, (d) => String(d.charCodeAt(0) - 0x0660))
    .replace(/[\u06F0-\u06F9]/g, (d) => String(d.charCodeAt(0) - 0x06f0));
}

function normalizeForNlp(value) {
  const normalized = normalizeDigits(value)
    .toLowerCase()
    .replace(/[إأآ]/g, "ا")
    .replace(/ى/g, "ي")
    .replace(/ة/g, "ه")
    .replace(/[ؤئ]/g, "ء")
    .replace(/[^\p{L}\p{N}\s]/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
  return normalized;
}

function tokenize(value) {
  if (!value) return [];
  return normalizeForNlp(value)
    .split(" ")
    .map((part) => part.trim())
    .filter((part) => part.length >= 2 && !STOPWORDS.has(part));
}

function containsAny(text, keywords) {
  return keywords.some((keyword) => text.includes(normalizeForNlp(keyword)));
}

function extractBudgetIqd(normalizedText) {
  const matches = [...normalizedText.matchAll(/(\d{2,6})\s*(الف|دينار|iqd|k)?/g)];
  if (!matches.length) return null;

  for (const match of matches) {
    let amount = Number(match[1] || 0);
    const unit = (match[2] || "").trim();
    if (!amount) continue;
    if (unit === "الف" || unit === "k") amount *= 1000;
    if (amount >= 500 && amount <= 500000) return amount;
  }

  return null;
}

function extractRequestedQuantity(normalizedText) {
  const match = normalizedText.match(/(?:x|عدد|قطعه|قطعة|حبه|حبة)?\s*(\d{1,2})/);
  if (!match) return 1;
  const quantity = Number(match[1] || 1);
  if (!Number.isFinite(quantity)) return 1;
  return Math.min(Math.max(quantity, 1), 8);
}

function detectCategoryHints(normalizedText) {
  const out = [];
  for (const hint of CATEGORY_HINTS) {
    if (containsAny(normalizedText, hint.words)) {
      out.push(hint.key);
    }
  }
  return out;
}

function detectIntent(message) {
  const normalized = normalizeForNlp(message || "");

  return {
    normalizedText: normalized,
    tokens: tokenize(normalized),
    wantsCheap: containsAny(normalized, CHEAP_KEYWORDS),
    wantsTopRated: containsAny(normalized, TOP_RATED_KEYWORDS),
    wantsFreeDelivery: containsAny(normalized, FREE_DELIVERY_KEYWORDS),
    wantsFast: containsAny(normalized, FAST_KEYWORDS),
    orderIntent: containsAny(normalized, ORDER_KEYWORDS),
    confirmIntent: containsAny(normalized, CONFIRM_KEYWORDS),
    cancelIntent: containsAny(normalized, CANCEL_KEYWORDS),
    budgetIqd: extractBudgetIqd(normalized),
    requestedQuantity: extractRequestedQuantity(normalized),
    categoryHints: detectCategoryHints(normalized),
  };
}

function parseProfile(rawProfile) {
  const preferenceJson =
    rawProfile && typeof rawProfile.preference_json === "object"
      ? rawProfile.preference_json
      : {};

  return {
    pricePreference: preferenceJson.pricePreference || "balanced",
    counters: {
      cheap: Number(preferenceJson?.counters?.cheap || 0),
      topRated: Number(preferenceJson?.counters?.topRated || 0),
      freeDelivery: Number(preferenceJson?.counters?.freeDelivery || 0),
      ordering: Number(preferenceJson?.counters?.ordering || 0),
    },
    categorySignals:
      preferenceJson.categorySignals &&
      typeof preferenceJson.categorySignals === "object"
        ? { ...preferenceJson.categorySignals }
        : {},
  };
}

function clamp01(value) {
  if (value <= 0) return 0;
  if (value >= 1) return 1;
  return value;
}

function bumpMapCount(map, key, amount = 1) {
  if (!key) return;
  map[key] = Number(map[key] || 0) + amount;
}

function mergeProfileSignals(profile, intent) {
  const next = {
    ...profile,
    counters: { ...profile.counters },
    categorySignals: { ...profile.categorySignals },
  };

  if (intent.wantsCheap) next.counters.cheap += 1;
  if (intent.wantsTopRated) next.counters.topRated += 1;
  if (intent.wantsFreeDelivery) next.counters.freeDelivery += 1;
  if (intent.orderIntent) next.counters.ordering += 1;

  for (const category of intent.categoryHints) {
    bumpMapCount(next.categorySignals, category, 1);
  }

  const cheapBias = next.counters.cheap + next.counters.freeDelivery * 0.4;
  const topRatedBias = next.counters.topRated;
  if (cheapBias - topRatedBias >= 2) {
    next.pricePreference = "cheap";
  } else if (topRatedBias - cheapBias >= 3) {
    next.pricePreference = "premium";
  } else {
    next.pricePreference = "balanced";
  }

  return next;
}

function buildHistoryWeights(historySignals) {
  const merchantMax = Math.max(
    1,
    ...historySignals.merchants.map((item) => item.ordersCount)
  );
  const categoryMax = Math.max(
    1,
    ...historySignals.categories.map((item) => item.itemsCount)
  );

  const merchantWeight = new Map();
  for (const item of historySignals.merchants) {
    merchantWeight.set(item.merchantId, clamp01(item.ordersCount / merchantMax));
  }

  const categoryWeight = new Map();
  for (const item of historySignals.categories) {
    categoryWeight.set(normalizeForNlp(item.categoryName), clamp01(item.itemsCount / categoryMax));
  }

  const favoriteProductIds = new Set(
    historySignals.favoriteProducts.map((item) => item.productId)
  );

  return { merchantWeight, categoryWeight, favoriteProductIds };
}

function computeTokenMatchScore(queryTokens, candidateText) {
  if (!queryTokens.length) return 0;
  const normalizedCandidate = normalizeForNlp(candidateText);
  if (!normalizedCandidate) return 0;

  let hits = 0;
  for (const token of queryTokens) {
    if (normalizedCandidate.includes(token)) hits += 1;
  }
  return hits / queryTokens.length;
}

function mapCategoryToHint(categoryName) {
  const normalizedCategory = normalizeForNlp(categoryName || "");
  for (const hint of CATEGORY_HINTS) {
    for (const word of hint.words) {
      if (normalizedCategory.includes(normalizeForNlp(word))) {
        return hint.key;
      }
    }
  }
  return normalizedCategory;
}

function rankProducts({ pool, intent, profile, historyWeights }) {
  if (!pool.length) return [];

  const minPrice = Math.min(...pool.map((p) => p.effectivePrice));
  const maxPrice = Math.max(...pool.map((p) => p.effectivePrice));
  const priceRange = Math.max(maxPrice - minPrice, 1);
  const maxCompleted = Math.max(
    1,
    ...pool.map((p) => Number(p.merchantCompletedOrders || 0))
  );

  const weightPrice =
    intent.wantsCheap || profile.pricePreference === "cheap" ? 2.8 : 1.1;
  const weightRating =
    intent.wantsTopRated || profile.pricePreference === "premium" ? 2.6 : 1.3;

  return pool
    .map((candidate) => {
      const queryText = [
        candidate.productName,
        candidate.productDescription,
        candidate.categoryName,
        candidate.merchantName,
      ]
        .filter(Boolean)
        .join(" ");

      const tokenMatch = computeTokenMatchScore(intent.tokens, queryText);
      const categoryHint = mapCategoryToHint(candidate.categoryName);
      const categoryMatch = intent.categoryHints.includes(categoryHint) ? 1 : 0;

      const priceScore = 1 - (candidate.effectivePrice - minPrice) / priceRange;
      const ratingScore = clamp01((candidate.merchantAvgRating || 0) / 5);
      const popularityScore = clamp01(
        Number(candidate.merchantCompletedOrders || 0) / maxCompleted
      );

      const historyMerchant =
        historyWeights.merchantWeight.get(candidate.merchantId) || 0;
      const historyCategory =
        historyWeights.categoryWeight.get(normalizeForNlp(candidate.categoryName || "")) ||
        0;
      const profileCategory = Number(profile.categorySignals[categoryHint] || 0);
      const profileCategoryWeight = clamp01(profileCategory / 6);

      let score =
        tokenMatch * 4.2 +
        categoryMatch * 2.3 +
        priceScore * weightPrice +
        ratingScore * weightRating +
        popularityScore * 1.1 +
        historyMerchant * 1.5 +
        historyCategory * 1.2 +
        profileCategoryWeight * 1.4;

      if (candidate.isFavorite || historyWeights.favoriteProductIds.has(candidate.productId)) {
        score += 1.5;
      }

      if (intent.wantsFreeDelivery) {
        score += candidate.freeDelivery ? 1.7 : -0.4;
      }

      if (intent.budgetIqd) {
        if (candidate.effectivePrice <= intent.budgetIqd) {
          score += 0.8;
        } else {
          const deltaRatio =
            (candidate.effectivePrice - intent.budgetIqd) / Math.max(intent.budgetIqd, 1);
          score -= Math.min(3.2, deltaRatio * 2.4);
        }
      }

      return {
        ...candidate,
        score,
        match: {
          tokenMatch,
          categoryMatch,
          ratingScore,
          priceScore,
          historyMerchant,
          historyCategory,
        },
      };
    })
    .sort((a, b) => b.score - a.score);
}

function buildMerchantSuggestions(scoredProducts) {
  const groups = new Map();

  for (const candidate of scoredProducts.slice(0, 40)) {
    const key = candidate.merchantId;
    const current = groups.get(key) || {
      merchantId: candidate.merchantId,
      merchantName: candidate.merchantName,
      merchantType: candidate.merchantType,
      merchantImageUrl: candidate.merchantImageUrl,
      scoreSum: 0,
      scoreCount: 0,
      minPrice: Number.POSITIVE_INFINITY,
      maxPrice: 0,
      avgRating: candidate.merchantAvgRating || 0,
      completedOrders: candidate.merchantCompletedOrders || 0,
      hasFreeDelivery: false,
      topProducts: [],
    };

    current.scoreSum += candidate.score;
    current.scoreCount += 1;
    current.minPrice = Math.min(current.minPrice, candidate.effectivePrice);
    current.maxPrice = Math.max(current.maxPrice, candidate.effectivePrice);
    current.hasFreeDelivery = current.hasFreeDelivery || candidate.freeDelivery;

    if (current.topProducts.length < 3) {
      current.topProducts.push(candidate.productName);
    }

    groups.set(key, current);
  }

  return Array.from(groups.values())
    .map((merchant) => ({
      merchantId: merchant.merchantId,
      merchantName: merchant.merchantName,
      merchantType: merchant.merchantType,
      merchantImageUrl: merchant.merchantImageUrl,
      averageScore: merchant.scoreCount
        ? merchant.scoreSum / merchant.scoreCount
        : merchant.scoreSum,
      minPrice: Number.isFinite(merchant.minPrice) ? merchant.minPrice : 0,
      maxPrice: merchant.maxPrice,
      avgRating: merchant.avgRating,
      completedOrders: merchant.completedOrders,
      hasFreeDelivery: merchant.hasFreeDelivery,
      topProducts: merchant.topProducts,
    }))
    .sort((a, b) => b.averageScore - a.averageScore)
    .slice(0, 6);
}

function buildProductSuggestions(scoredProducts) {
  return scoredProducts.slice(0, 12).map((product) => ({
    productId: product.productId,
    merchantId: product.merchantId,
    merchantName: product.merchantName,
    productName: product.productName,
    categoryName: product.categoryName,
    effectivePrice: product.effectivePrice,
    basePrice: product.basePrice,
    discountedPrice: product.discountedPrice,
    offerLabel: product.offerLabel,
    freeDelivery: product.freeDelivery,
    productImageUrl: product.productImageUrl,
    merchantAvgRating: product.merchantAvgRating,
    merchantCompletedOrders: product.merchantCompletedOrders,
    isFavorite: product.isFavorite,
    score: product.score,
  }));
}

function buildDraftCandidate(scoredProducts, requestedQuantity = 1) {
  if (!scoredProducts.length) return null;

  const merchantGroups = new Map();
  for (const candidate of scoredProducts.slice(0, 30)) {
    const existing = merchantGroups.get(candidate.merchantId) || [];
    existing.push(candidate);
    merchantGroups.set(candidate.merchantId, existing);
  }

  let selectedMerchantId = null;
  let selectedItems = [];
  let bestGroupScore = -Infinity;

  for (const [merchantId, items] of merchantGroups.entries()) {
    const sorted = items.sort((a, b) => b.score - a.score);
    const top = sorted.slice(0, 3);
    const groupScore = top.reduce((sum, item) => sum + item.score, 0);
    if (groupScore > bestGroupScore) {
      bestGroupScore = groupScore;
      selectedMerchantId = merchantId;
      selectedItems = top;
    }
  }

  if (!selectedMerchantId || !selectedItems.length) return null;

  const withQuantities = selectedItems.map((item, index) => ({
    productId: item.productId,
    productName: item.productName,
    quantity: index === 0 ? requestedQuantity : 1,
    unitPrice: item.effectivePrice,
    lineTotal: item.effectivePrice * (index === 0 ? requestedQuantity : 1),
    freeDelivery: item.freeDelivery === true,
  }));

  const subtotal = withQuantities.reduce((sum, item) => sum + item.lineTotal, 0);
  const serviceFee = subtotal > 0 ? FIXED_SERVICE_FEE : 0;
  const hasFreeDelivery = withQuantities.some((item) => item.freeDelivery);
  const deliveryFee = hasFreeDelivery ? 0 : FIXED_DELIVERY_FEE;
  const totalAmount = subtotal + serviceFee + deliveryFee;

  return {
    merchantId: selectedMerchantId,
    merchantName: selectedItems[0].merchantName,
    merchantType: selectedItems[0].merchantType,
    items: withQuantities.map((item) => ({
      productId: item.productId,
      productName: item.productName,
      quantity: item.quantity,
      unitPrice: item.unitPrice,
      lineTotal: item.lineTotal,
    })),
    subtotal,
    serviceFee,
    deliveryFee,
    totalAmount,
    hasFreeDelivery,
  };
}

function formatIqd(value) {
  const amount = Number(value || 0);
  return `${Math.round(amount).toLocaleString("en-US")} دينار`;
}

function mapProfileForApi(profile) {
  const topCategories = Object.entries(profile.categorySignals || {})
    .map(([key, value]) => ({
      key,
      weight: Number(value || 0),
    }))
    .sort((a, b) => b.weight - a.weight)
    .slice(0, 5);

  return {
    pricePreference: profile.pricePreference,
    counters: profile.counters,
    topCategories,
  };
}

function buildReasonPhrases(intent, merchants) {
  const reasons = [];
  if (intent.wantsCheap) reasons.push("ركزت على الخيارات الأقل سعرًا");
  if (intent.wantsTopRated) reasons.push("قدّمت خيارات بتقييم أعلى");
  if (intent.wantsFreeDelivery) reasons.push("أعطيت أولوية للتوصيل المجاني");
  if (intent.categoryHints.length) reasons.push("طابقت الأصناف المطلوبة");
  if (!reasons.length) {
    reasons.push("اعتمدت على طلباتك السابقة والمتاجر المتاحة الآن");
  }

  if (merchants.length) {
    reasons.push(`أفضل ترشيح حاليًا: ${merchants[0].merchantName}`);
  }

  return reasons;
}

function buildAssistantReply({
  intent,
  merchants,
  products,
  draft,
  createdOrder,
  confirmFromDraft,
}) {
  if (createdOrder && confirmFromDraft) {
    return `تم يا بطل، ثبتت الطلب #${createdOrder.id} من ${createdOrder.merchantName} بمبلغ ${formatIqd(createdOrder.totalAmount)}. تقدر تتابعه مباشرة من شاشة طلباتي.`;
  }

  if (draft) {
    const firstItem = draft.items[0];
    const itemText = firstItem
      ? `${firstItem.productName} x${firstItem.quantity}`
      : "منتجات مناسبة";
    return `جهزت لك مسودة طلب جاهزة من ${draft.merchantName} تشمل ${itemText}. إذا كلشي مناسب اضغط تثبيت الطلب، وإذا تريد تعديل اكتبه إلي.`;
  }

  if (!products.length) {
    return "حالياً ما حصلت خيارات مناسبة جدًا لطلبك. جرّب تكتب الصنف بشكل أوضح مثل: بركر، مشاوي، مواد منزلية، أو حدد ميزانيتك بالدينار.";
  }

  const topMerchants = merchants.slice(0, 3).map((m) => m.merchantName).join("، ");
  const reasons = buildReasonPhrases(intent, merchants).join(" • ");
  return `حاضر، رتبت لك أفضل الترشيحات المتاحة الآن. المتاجر المقترحة: ${topMerchants || "متاجر قريبة منك"}. ${reasons}. إذا تريد، أقدر أسويلك مسودة طلب مباشرة.`;
}

function buildDraftRationale(intent) {
  const reasons = [];
  if (intent.wantsCheap) reasons.push("اعتمدت على السعر الأقل");
  if (intent.wantsTopRated) reasons.push("اعتمدت على تقييم المتجر");
  if (intent.wantsFreeDelivery) reasons.push("قدمت خيارات توصيل مجاني");
  if (intent.categoryHints.length) reasons.push("طابقت الأصناف المطلوبة");
  if (!reasons.length) reasons.push("اعتمدت على تاريخ طلباتك ونشاطك");
  return reasons.join(" | ");
}

function mapDraftForApi(draft) {
  if (!draft) return null;
  return {
    token: draft.token,
    merchantId: draft.merchantId,
    merchantName: draft.merchantName,
    merchantType: draft.merchantType,
    addressId: draft.addressId,
    addressLabel: draft.addressLabel,
    addressCity: draft.addressCity,
    addressBlock: draft.addressBlock,
    addressBuildingNumber: draft.addressBuildingNumber,
    addressApartment: draft.addressApartment,
    note: draft.note,
    items: draft.items,
    subtotal: draft.subtotal,
    serviceFee: draft.serviceFee,
    deliveryFee: draft.deliveryFee,
    totalAmount: draft.totalAmount,
    rationale: draft.rationale,
    status: draft.status,
    expiresAt: draft.expiresAt,
  };
}

function mapOrderForApi(order) {
  if (!order) return null;
  return {
    id: Number(order.id),
    status: order.status,
    merchantId: Number(order.merchant_id || order.merchantId || 0),
    merchantName: order.merchant_name || order.merchantName || "",
    totalAmount: Number(order.total_amount || order.totalAmount || 0),
    createdAt: order.created_at || order.createdAt || null,
  };
}

async function resolveSession(customerUserId, sessionId) {
  if (sessionId != null) {
    const existing = await repo.getSessionById(customerUserId, Number(sessionId));
    if (!existing) {
      throw appError("AI_SESSION_NOT_FOUND", 404);
    }
    return existing;
  }

  return (await repo.getLatestSession(customerUserId)) || repo.createSession(customerUserId);
}

async function ensureWelcomeMessage(sessionId) {
  const messages = await repo.listMessages(sessionId, 2);
  if (messages.length) return;
  await repo.insertMessage(
    sessionId,
    "assistant",
    "هلا بيك، أني مساعدك الذكي. اكلي شنو تحب اليوم، وأنا أرشح لك الأفضل وأسوي لك مسودة طلب جاهزة."
  );
}

async function buildSessionPayload(customerUserId, sessionId, profile) {
  const [messages, pendingDraft, addresses] = await Promise.all([
    repo.listMessages(sessionId, 50),
    repo.getLatestPendingDraft(customerUserId, sessionId),
    repo.listCustomerAddresses(customerUserId),
  ]);

  return {
    sessionId: Number(sessionId),
    messages,
    draftOrder: mapDraftForApi(pendingDraft),
    addresses: addresses.map((a) => ({
      id: Number(a.id),
      label: a.label,
      city: a.city,
      block: a.block,
      buildingNumber: a.building_number,
      apartment: a.apartment,
      isDefault: a.is_default === true,
    })),
    profile: mapProfileForApi(profile),
  };
}

export async function getCurrentConversation(customerUserId, options = {}) {
  await repo.expireOldDrafts(customerUserId);
  const session = await resolveSession(customerUserId, options.sessionId);
  await ensureWelcomeMessage(session.id);

  const rawProfile = await repo.getProfile(customerUserId);
  const profile = parseProfile(rawProfile);
  return buildSessionPayload(customerUserId, session.id, profile);
}

export async function confirmDraft(customerUserId, token, options = {}) {
  await repo.expireOldDrafts(customerUserId);

  const session = await resolveSession(customerUserId, options.sessionId);
  const draft = token
    ? await repo.getDraftByToken(customerUserId, token)
    : await repo.getLatestPendingDraft(customerUserId, session.id);

  if (!draft || draft.status !== "pending") {
    throw appError("DRAFT_NOT_FOUND", 404);
  }

  if (new Date(draft.expiresAt).getTime() < Date.now()) {
    await repo.markDraftCancelled(draft.id);
    throw appError("DRAFT_EXPIRED", 400);
  }

  const resolvedAddressId =
    options.addressId != null ? Number(options.addressId) : draft.addressId;
  if (!resolvedAddressId) {
    throw appError("ADDRESS_REQUIRED", 400);
  }

  const items = draft.items.map((item) => ({
    productId: Number(item.productId),
    quantity: Number(item.quantity || 1),
  }));

  if (!items.length) {
    throw appError("DRAFT_ITEMS_EMPTY", 400);
  }

  const orderNote = [draft.note, options.note, "تم إنشاؤه عبر المساعد الذكي"]
    .filter((part) => typeof part === "string" && part.trim().length)
    .join(" | ");

  const createdOrder = await createOrder(customerUserId, {
    merchantId: draft.merchantId,
    addressId: resolvedAddressId,
    note: orderNote,
    items,
  });

  await repo.markDraftConfirmed(draft.id, createdOrder.id);

  const assistantText = buildAssistantReply({
    intent: {},
    merchants: [],
    products: [],
    draft: null,
    createdOrder: mapOrderForApi(createdOrder),
    confirmFromDraft: true,
  });

  const assistantMessage = await repo.insertMessage(session.id, "assistant", assistantText, {
    type: "draft_confirmed",
    draftToken: draft.token,
    orderId: createdOrder.id,
  });

  const rawProfile = await repo.getProfile(customerUserId);
  const profile = parseProfile(rawProfile);

  const payload = await buildSessionPayload(customerUserId, session.id, profile);
  return {
    ...payload,
    assistantMessage,
    suggestions: { merchants: [], products: [] },
    createdOrder: mapOrderForApi(createdOrder),
  };
}

export async function chat(customerUserId, dto) {
  await repo.expireOldDrafts(customerUserId);

  const session = await resolveSession(customerUserId, dto.sessionId);
  await ensureWelcomeMessage(session.id);

  const message = String(dto.message || "").trim();
  const intent = detectIntent(message);
  const wantsConfirm =
    dto.confirmDraft === true || intent.confirmIntent === true;

  if (!message && !wantsConfirm) {
    throw appError("MESSAGE_REQUIRED", 400);
  }

  if (message) {
    await repo.insertMessage(session.id, "user", message, {
      budgetIqd: intent.budgetIqd,
      categoryHints: intent.categoryHints,
    });
  }

  if (intent.cancelIntent) {
    const pending = await repo.getLatestPendingDraft(customerUserId, session.id);
    if (pending) {
      await repo.markDraftCancelled(pending.id);
    }

    const cancelMessage = await repo.insertMessage(
      session.id,
      "assistant",
      "تمام، تم إلغاء مسودة الطلب الحالية. إذا تريد نعيد الترشيح من جديد أنا حاضر."
    );

    const rawProfile = await repo.getProfile(customerUserId);
    const profile = parseProfile(rawProfile);
    const payload = await buildSessionPayload(customerUserId, session.id, profile);
    return {
      ...payload,
      assistantMessage: cancelMessage,
      suggestions: { merchants: [], products: [] },
      createdOrder: null,
    };
  }

  if (wantsConfirm) {
    return confirmDraft(customerUserId, dto.draftToken || null, {
      sessionId: session.id,
      addressId: dto.addressId,
      note: dto.note,
    });
  }

  const [rawProfile, historySignals, pool] = await Promise.all([
    repo.getProfile(customerUserId),
    repo.getHistorySignals(customerUserId),
    repo.listRecommendationPool(customerUserId, 900),
  ]);

  const profile = mergeProfileSignals(parseProfile(rawProfile), intent);
  await repo.upsertProfile(customerUserId, profile, "updated_from_chat");

  const historyWeights = buildHistoryWeights(historySignals);
  const ranked = rankProducts({
    pool,
    intent,
    profile,
    historyWeights,
  });

  const merchantSuggestions = buildMerchantSuggestions(ranked);
  const productSuggestions = buildProductSuggestions(ranked);

  let createdDraft = null;
  const shouldDraft = intent.orderIntent || dto.createDraft === true;
  if (shouldDraft && ranked.length) {
    const draftCandidate = buildDraftCandidate(ranked, intent.requestedQuantity);
    if (draftCandidate) {
      let address = null;
      if (dto.addressId != null) {
        address = await repo.getAddressById(customerUserId, Number(dto.addressId));
      }
      if (!address) {
        address = await repo.getDefaultAddress(customerUserId);
      }

      createdDraft = await repo.createDraft({
        token: `drf_${crypto.randomBytes(14).toString("base64url")}`,
        customerUserId,
        sessionId: session.id,
        merchantId: draftCandidate.merchantId,
        addressId: address?.id || null,
        note: "مسودة طلب مقترحة من المساعد الذكي",
        items: draftCandidate.items,
        subtotal: draftCandidate.subtotal,
        serviceFee: draftCandidate.serviceFee,
        deliveryFee: draftCandidate.deliveryFee,
        totalAmount: draftCandidate.totalAmount,
        rationale: buildDraftRationale(intent),
      });
    }
  }

  const assistantText = buildAssistantReply({
    intent,
    merchants: merchantSuggestions,
    products: productSuggestions,
    draft: createdDraft,
    createdOrder: null,
    confirmFromDraft: false,
  });

  const assistantMessage = await repo.insertMessage(session.id, "assistant", assistantText, {
    type: createdDraft ? "draft_created" : "recommendation",
    draftToken: createdDraft?.token || null,
    merchantsCount: merchantSuggestions.length,
    productsCount: productSuggestions.length,
  });

  const payload = await buildSessionPayload(customerUserId, session.id, profile);

  return {
    ...payload,
    assistantMessage,
    suggestions: {
      merchants: merchantSuggestions,
      products: productSuggestions,
    },
    createdOrder: null,
  };
}

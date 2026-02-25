import crypto from "crypto";

import { createOrder } from "../orders/orders.service.js";
import * as repo from "./assistant.repo.js";

const FIXED_SERVICE_FEE = 500;
const FIXED_DELIVERY_FEE = 1000;

const CHEAP_KEYWORDS = [
  'cheap',
  'low price',
  'budget',
  '\u0627\u0631\u062e\u0635',
  '\u0631\u062e\u064a\u0635',
  '\u0627\u0642\u062a\u0635\u0627\u062f\u064a',
  '\u0633\u0639\u0631',
  '\u0627\u0642\u0644',
  '\u0623\u0642\u0644',
];

const TOP_RATED_KEYWORDS = [
  'top rated',
  'high rating',
  '\u0627\u0641\u0636\u0644',
  '\u0623\u0641\u0636\u0644',
  '\u0627\u062d\u0633\u0646',
  '\u0623\u062d\u0633\u0646',
  '\u0627\u0639\u0644\u0649 \u062a\u0642\u064a\u064a\u0645',
  '\u0623\u0639\u0644\u0649 \u062a\u0642\u064a\u064a\u0645',
];

const FREE_DELIVERY_KEYWORDS = [
  'free delivery',
  '\u062a\u0648\u0635\u064a\u0644 \u0645\u062c\u0627\u0646\u064a',
  '\u0628\u062f\u0648\u0646 \u062a\u0648\u0635\u064a\u0644',
];

const FAST_KEYWORDS = [
  'fast',
  'quick',
  '\u0633\u0631\u064a\u0639',
  '\u0628\u0633\u0631\u0639\u0629',
  '\u0639\u0627\u062c\u0644',
];

const ORDER_KEYWORDS = [
  'order',
  '\u0627\u0637\u0644\u0628',
  '\u0623\u0637\u0644\u0628',
  '\u0637\u0644\u0628',
  '\u0627\u0631\u064a\u062f',
  '\u0623\u0631\u064a\u062f',
  '\u0627\u0628\u063a\u0649',
  '\u0627\u0628\u064a',
  '\u0633\u0648',
  '\u0633\u0648\u064a',
  '\u062c\u064a\u0628',
];

const CONFIRM_KEYWORDS = [
  'ok',
  'confirm',
  '\u0645\u0648\u0627\u0641\u0642',
  '\u062b\u0628\u062a',
  '\u062a\u062b\u0628\u064a\u062a',
  '\u062a\u0645\u0627\u0645',
  '\u0627\u0648\u0643\u064a',
];

const CANCEL_KEYWORDS = [
  'cancel',
  'not now',
  '\u0627\u0644\u063a',
  '\u0625\u0644\u063a',
  '\u0627\u0644\u063a\u0627\u0621',
  '\u0625\u0644\u063a\u0627\u0621',
  '\u0645\u0648',
];

const CATEGORY_HINTS = [
  { key: 'burgers', words: ['burger', '\u0628\u0631\u0643\u0631'] },
  { key: 'pizza', words: ['pizza', '\u0628\u064a\u062a\u0632\u0627'] },
  { key: 'shawarma', words: ['\u0634\u0627\u0648\u0631\u0645\u0627'] },
  { key: 'grills', words: ['\u0645\u0634\u0627\u0648\u064a', '\u0643\u0628\u0627\u0628', '\u0634\u064a\u0634', '\u062a\u0643\u0647'] },
  { key: 'chicken', words: ['\u062f\u062c\u0627\u062c', '\u0628\u0631\u0648\u0633\u062a\u062f', '\u0643\u0631\u0633\u0628\u064a'] },
  { key: 'drinks', words: ['\u0645\u0634\u0631\u0648\u0628', '\u0639\u0635\u064a\u0631', '\u0628\u064a\u0628\u0633\u064a', '\u0643\u0648\u0643\u0627', '\u0642\u0647\u0648\u0629'] },
  { key: 'sweets', words: ['\u062d\u0644\u0648\u064a\u0627\u062a', '\u0643\u064a\u0643', '\u062f\u0648\u0646\u0627\u062a', '\u062a\u0634\u064a\u0632'] },
  { key: 'grocery', words: ['\u0628\u0642\u0627\u0644\u0629', '\u0633\u0648\u0628\u0631', '\u0645\u0627\u0631\u0643\u062a', '\u0645\u0648\u0627\u062f'] },
  { key: 'vegetables', words: ['\u062e\u0636\u0627\u0631', '\u0641\u0648\u0627\u0643\u0647'] },
  { key: 'bakery', words: ['\u0645\u0639\u062c\u0646\u0627\u062a', '\u062e\u0628\u0632', '\u0641\u0631\u0646'] },
];

const STOPWORDS = new Set([
  'the',
  'a',
  'to',
  'for',
  '\u0627\u0628\u064a',
  '\u0627\u0631\u064a\u062f',
  '\u0623\u0631\u064a\u062f',
  '\u0627\u0628\u063a\u0649',
  '\u0645\u0646',
  '\u0639\u0644\u0649',
  '\u0641\u064a',
  '\u0627\u0644\u0649',
  '\u0625\u0644\u0649',
  '\u0639\u0646',
  '\u0645\u0639',
  '\u0644\u0648',
  '\u0627\u0630\u0627',
  '\u0625\u0630\u0627',
  '\u0634\u0646\u0648',
  '\u0647\u0630\u0627',
  '\u0647\u0627\u064a',
  '\u0648',
]);

const GREETING_KEYWORDS = [
  'hello',
  'hi',
  'hey',
  '\u0647\u0644\u0627',
  '\u0627\u0644\u0633\u0644\u0627\u0645 \u0639\u0644\u064a\u0643\u0645',
  '\u0634\u0644\u0648\u0646\u0643',
  '\u0645\u0631\u062d\u0628\u0627',
];

const THANKS_KEYWORDS = [
  'thank you',
  'thanks',
  '\u0634\u0643\u0631\u0627',
  '\u0645\u0645\u0646\u0648\u0646',
  '\u062a\u0633\u0644\u0645',
];

const CHITCHAT_KEYWORDS = [
  'who are you',
  'joke',
  '\u0634\u0646\u0648 \u0627\u0644\u0627\u062e\u0628\u0627\u0631',
  '\u0634\u0644\u0648\u0646 \u0627\u0644\u062c\u0648',
  '\u0645\u0646\u0648 \u0627\u0646\u062a',
  '\u0633\u0624\u0627\u0644',
  '\u0646\u0643\u062a\u0629',
  '\u0636\u062d\u0643\u0646\u064a',
  '\u0643\u064a\u0641 \u062d\u0627\u0644\u0643',
];

const ORDER_DOMAIN_KEYWORDS = [
  'delivery',
  'restaurant',
  'store',
  'product',
  'price',
  '\u0645\u0637\u0639\u0645',
  '\u0645\u062a\u062c\u0631',
  '\u0637\u0644\u0628',
  '\u0648\u062c\u0628\u0629',
  '\u0627\u0643\u0644',
  '\u0623\u0643\u0644',
  '\u0633\u0644\u0629',
  '\u062a\u0648\u0635\u064a\u0644',
  '\u0639\u0646\u0648\u0627\u0646',
  '\u062f\u064a\u0646\u0627\u0631',
  '\u062e\u0635\u0645',
  '\u0645\u0646\u062a\u062c',
];

const GROUP_ORDER_KEYWORDS = [
  'guests',
  'group',
  '\u0636\u064a\u0648\u0641',
  '\u062c\u0645\u0627\u0639\u0629',
  '\u0644\u0644\u062c\u0645\u0639\u0629',
];

const FAMILY_ORDER_KEYWORDS = [
  'family',
  '\u0639\u0627\u0626\u0644\u0629',
  '\u0627\u0633\u0631\u0629',
  '\u0623\u0633\u0631\u0629',
];

const SOLO_ORDER_KEYWORDS = [
  'alone',
  'solo',
  '\u0644\u0648\u062d\u062f\u064a',
  '\u0648\u062d\u062f\u064a',
  '\u0648\u062d\u062f\u0647',
];

const WEATHER_CHITCHAT_KEYWORDS = [
  'weather',
  '\u062c\u0648',
  '\u0637\u0642\u0633',
  '\u0645\u0637\u0631',
];

const JOKE_CHITCHAT_KEYWORDS = [
  'joke',
  '\u0646\u0643\u062a\u0629',
  '\u0636\u062d\u0643',
];

const BOT_IDENTITY_KEYWORDS = [
  'who are you',
  'what can you do',
  '\u0645\u0646\u0648 \u0627\u0646\u062a',
  '\u0634\u062a\u0643\u062f\u0631',
];

const MOOD_CHITCHAT_KEYWORDS = [
  'how are you',
  'how is it going',
  '\u0634\u0644\u0648\u0646\u0643',
  '\u0634\u062e\u0628\u0627\u0631\u0643',
];

function appError(message, status = 400) {
  const err = new Error(message);
  err.status = status;
  return err;
}

function countArabicChars(value) {
  const text = String(value || '');
  const matches = text.match(/[\u0600-\u06FF]/g);
  return matches ? matches.length : 0;
}

function decodeLatin1Utf8(value) {
  try {
    return Buffer.from(String(value || ''), 'latin1').toString('utf8');
  } catch (_) {
    return String(value || '');
  }
}

function fixMojibake(value) {
  let current = String(value || '');
  for (let i = 0; i < 3; i++) {
    const next = decodeLatin1Utf8(current);
    if (!next || next === current) break;
    const currentArabic = countArabicChars(current);
    const nextArabic = countArabicChars(next);
    if (nextArabic >= currentArabic || currentArabic === 0) {
      current = next;
      continue;
    }
    break;
  }
  return current;
}

function normalizeDigits(value) {
  return String(value || '')
    .replace(/[\u0660-\u0669]/g, (d) => String(d.charCodeAt(0) - 0x0660))
    .replace(/[\u06F0-\u06F9]/g, (d) => String(d.charCodeAt(0) - 0x06f0));
}

function normalizeForNlp(value) {
  const normalized = normalizeDigits(fixMojibake(value))
    .toLowerCase()
    .replace(/[\u0625\u0623\u0622]/g, '\u0627')
    .replace(/\u0649/g, '\u064a')
    .replace(/\u0629/g, '\u0647')
    .replace(/[\u0624\u0626]/g, '\u0621')
    .replace(/[^\p{L}\p{N}\s]/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  return normalized;
}

function tokenize(value) {
  if (!value) return [];
  return normalizeForNlp(value)
    .split(' ')
    .map((part) => part.trim())
    .filter((part) => part.length >= 2 && !STOPWORDS.has(part));
}

function containsAny(text, keywords) {
  return keywords.some((keyword) => {
    const normalizedKeyword = normalizeForNlp(fixMojibake(keyword));
    return normalizedKeyword.length > 0 && text.includes(normalizedKeyword);
  });
}

function extractBudgetIqd(normalizedText) {
  const matches = [
    ...normalizedText.matchAll(/(\d{2,6})\s*([\p{L}]{0,10}|iqd|k)?/gu),
  ];
  if (!matches.length) return null;

  const thousandWord = normalizeForNlp('\u0627\u0644\u0641');
  for (const match of matches) {
    let amount = Number(match[1] || 0);
    const unit = normalizeForNlp((match[2] || '').trim());
    if (!amount) continue;
    if (unit === thousandWord || unit === 'k') amount *= 1000;
    if (amount >= 500 && amount <= 500000) return amount;
  }

  return null;
}

function extractRequestedQuantity(normalizedText) {
  const explicit = normalizedText.match(
    /(?:x|qty|\u0639\u062F\u062F|\u0642\u0637\u0639\u0647|\u0642\u0637\u0639\u0629|\u062D\u0628\u0647|\u062D\u0628\u0629)\s*(\d{1,2})/u
  );
  if (!explicit) return 1;
  const quantity = Number(explicit[1] || 1);
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

function detectSmallTalkType(normalizedText) {
  if (!normalizedText) return "none";
  if (containsAny(normalizedText, GREETING_KEYWORDS)) return "greeting";
  if (containsAny(normalizedText, THANKS_KEYWORDS)) return "thanks";
  if (containsAny(normalizedText, CHITCHAT_KEYWORDS)) return "chitchat";
  return "none";
}

function detectAudienceType(normalizedText) {
  if (!normalizedText) return "unknown";
  if (containsAny(normalizedText, GROUP_ORDER_KEYWORDS)) return "group";
  if (containsAny(normalizedText, FAMILY_ORDER_KEYWORDS)) return "family";
  if (containsAny(normalizedText, SOLO_ORDER_KEYWORDS)) return "solo";
  return "unknown";
}

function detectOffTopicTheme(normalizedText) {
  if (!normalizedText) return "none";
  if (containsAny(normalizedText, WEATHER_CHITCHAT_KEYWORDS)) return "weather";
  if (containsAny(normalizedText, JOKE_CHITCHAT_KEYWORDS)) return "joke";
  if (containsAny(normalizedText, BOT_IDENTITY_KEYWORDS)) return "bot_identity";
  if (containsAny(normalizedText, MOOD_CHITCHAT_KEYWORDS)) return "mood";
  return "general";
}

function detectIntent(message) {
  const normalized = normalizeForNlp(message || "");
  const categoryHints = detectCategoryHints(normalized);
  const smallTalkType = detectSmallTalkType(normalized);
  const audienceType = detectAudienceType(normalized);
  const wantsCheap = containsAny(normalized, CHEAP_KEYWORDS);
  const wantsTopRated = containsAny(normalized, TOP_RATED_KEYWORDS);
  const wantsFreeDelivery = containsAny(normalized, FREE_DELIVERY_KEYWORDS);
  const wantsFast = containsAny(normalized, FAST_KEYWORDS);
  const orderIntent = containsAny(normalized, ORDER_KEYWORDS);
  const confirmIntent = containsAny(normalized, CONFIRM_KEYWORDS);
  const cancelIntent = containsAny(normalized, CANCEL_KEYWORDS);
  const budgetIqd = extractBudgetIqd(normalized);
  const tokens = tokenize(normalized);

  const hasDomainTerms =
    containsAny(normalized, ORDER_DOMAIN_KEYWORDS) ||
    categoryHints.length > 0 ||
    budgetIqd != null;

  const hardOrderSignals =
    orderIntent ||
    confirmIntent ||
    cancelIntent ||
    wantsCheap ||
    wantsTopRated ||
    wantsFreeDelivery ||
    wantsFast;

  const offTopicIntent = !hardOrderSignals && !hasDomainTerms && tokens.length > 0;
  const offTopicTheme = offTopicIntent ? detectOffTopicTheme(normalized) : "none";

  return {
    normalizedText: normalized,
    tokens,
    wantsCheap,
    wantsTopRated,
    wantsFreeDelivery,
    wantsFast,
    orderIntent,
    confirmIntent,
    cancelIntent,
    offTopicIntent,
    offTopicTheme,
    smallTalkType,
    audienceType,
    budgetIqd,
    requestedQuantity: extractRequestedQuantity(normalized),
    categoryHints,
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
    merchantSignals:
      preferenceJson.merchantSignals &&
      typeof preferenceJson.merchantSignals === "object"
        ? { ...preferenceJson.merchantSignals }
        : {},
    tokenSignals:
      preferenceJson.tokenSignals &&
      typeof preferenceJson.tokenSignals === "object"
        ? { ...preferenceJson.tokenSignals }
        : {},
    audienceSignals:
      preferenceJson.audienceSignals &&
      typeof preferenceJson.audienceSignals === "object"
        ? { ...preferenceJson.audienceSignals }
        : {},
    conversation:
      preferenceJson.conversation &&
      typeof preferenceJson.conversation === "object"
        ? {
            smallTalkCount: Number(preferenceJson.conversation.smallTalkCount || 0),
            offTopicCount: Number(preferenceJson.conversation.offTopicCount || 0),
            confirmedDrafts: Number(preferenceJson.conversation.confirmedDrafts || 0),
            lastIntent: preferenceJson.conversation.lastIntent || "unknown",
            lastTopic: preferenceJson.conversation.lastTopic || "none",
          }
        : {
            smallTalkCount: 0,
            offTopicCount: 0,
            confirmedDrafts: 0,
            lastIntent: "unknown",
            lastTopic: "none",
          },
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

function decaySignalMap(map, decay = 0.985, minKeep = 0.2) {
  const out = {};
  for (const [key, value] of Object.entries(map || {})) {
    const nextValue = Number(value || 0) * decay;
    if (nextValue >= minKeep) out[key] = Number(nextValue.toFixed(4));
  }
  return out;
}

function trimSignalMap(map, maxEntries = 140) {
  const ordered = Object.entries(map || {}).sort((a, b) => Number(b[1]) - Number(a[1]));
  return Object.fromEntries(ordered.slice(0, maxEntries));
}

function boostTokenSignals(signalMap, tokens, amount = 1) {
  for (const token of tokens.slice(0, 10)) {
    if (!token || token.length < 2) continue;
    bumpMapCount(signalMap, token, amount);
  }
}

function mergeProfileSignals(profile, intent) {
  const next = {
    ...profile,
    counters: { ...profile.counters },
    categorySignals: { ...profile.categorySignals },
    merchantSignals: decaySignalMap(profile.merchantSignals, 0.992, 0.25),
    tokenSignals: decaySignalMap(profile.tokenSignals, 0.985, 0.15),
    audienceSignals: decaySignalMap(profile.audienceSignals, 0.993, 0.2),
    conversation: { ...profile.conversation },
  };

  if (intent.wantsCheap) next.counters.cheap += 1;
  if (intent.wantsTopRated) next.counters.topRated += 1;
  if (intent.wantsFreeDelivery) next.counters.freeDelivery += 1;
  if (intent.orderIntent) next.counters.ordering += 1;
  if (intent.smallTalkType !== "none") next.conversation.smallTalkCount += 1;
  if (intent.offTopicIntent) next.conversation.offTopicCount += 1;

  for (const category of intent.categoryHints) {
    bumpMapCount(next.categorySignals, category, 1);
  }
  if (intent.audienceType !== "unknown") {
    bumpMapCount(next.audienceSignals, intent.audienceType, 1.1);
  }

  const learnableTokens = intent.offTopicIntent ? [] : intent.tokens;
  boostTokenSignals(next.tokenSignals, learnableTokens, 1);
  next.tokenSignals = trimSignalMap(next.tokenSignals, 150);
  next.categorySignals = trimSignalMap(next.categorySignals, 90);
  next.merchantSignals = trimSignalMap(next.merchantSignals, 90);
  next.audienceSignals = trimSignalMap(next.audienceSignals, 30);

  const cheapBias = next.counters.cheap + next.counters.freeDelivery * 0.4;
  const topRatedBias = next.counters.topRated;
  if (cheapBias - topRatedBias >= 2) {
    next.pricePreference = "cheap";
  } else if (topRatedBias - cheapBias >= 3) {
    next.pricePreference = "premium";
  } else {
    next.pricePreference = "balanced";
  }

  next.conversation.lastIntent = intent.offTopicIntent
    ? "off_topic"
    : intent.orderIntent
    ? "order"
    : intent.smallTalkType !== "none"
    ? "small_talk"
    : "browse";
  next.conversation.lastTopic = intent.offTopicIntent
    ? intent.offTopicTheme
    : intent.categoryHints[0] || "none";

  return next;
}

function buildHistoryWeights(historySignals, globalSignals = null) {
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

  const globalMerchantWeight = new Map();
  const globalCategoryWeight = new Map();
  const globalProductWeight = new Map();

  if (globalSignals) {
    const globalMerchantMax = Math.max(
      1,
      ...(globalSignals.merchants || []).map((item) => item.deliveredOrders || 0)
    );
    for (const item of globalSignals.merchants || []) {
      globalMerchantWeight.set(
        Number(item.merchantId),
        clamp01(Number(item.deliveredOrders || 0) / globalMerchantMax)
      );
    }

    const globalCategoryMax = Math.max(
      1,
      ...(globalSignals.categories || []).map((item) => item.itemsCount || 0)
    );
    for (const item of globalSignals.categories || []) {
      globalCategoryWeight.set(
        normalizeForNlp(item.categoryName),
        clamp01(Number(item.itemsCount || 0) / globalCategoryMax)
      );
    }

    const globalProductMax = Math.max(
      1,
      ...(globalSignals.products || []).map((item) => item.soldUnits || 0)
    );
    for (const item of globalSignals.products || []) {
      globalProductWeight.set(
        Number(item.productId),
        clamp01(Number(item.soldUnits || 0) / globalProductMax)
      );
    }
  }

  return {
    merchantWeight,
    categoryWeight,
    favoriteProductIds,
    globalMerchantWeight,
    globalCategoryWeight,
    globalProductWeight,
  };
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
  const learnedTokens = Object.entries(profile.tokenSignals || {})
    .sort((a, b) => Number(b[1]) - Number(a[1]))
    .slice(0, 10)
    .map(([token]) => token);

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
      const globalMerchant =
        historyWeights.globalMerchantWeight?.get(candidate.merchantId) || 0;
      const globalCategory =
        historyWeights.globalCategoryWeight?.get(
          normalizeForNlp(candidate.categoryName || "")
        ) || 0;
      const globalProduct =
        historyWeights.globalProductWeight?.get(candidate.productId) || 0;
      const profileCategory = Number(profile.categorySignals[categoryHint] || 0);
      const profileCategoryWeight = clamp01(profileCategory / 6);
      const profileMerchant = clamp01(
        Number(profile.merchantSignals[candidate.merchantId] || 0) / 8
      );
      const learnedTokenMatch = computeTokenMatchScore(learnedTokens, queryText);

      let score =
        tokenMatch * 4.2 +
        categoryMatch * 2.3 +
        priceScore * weightPrice +
        ratingScore * weightRating +
        popularityScore * 1.1 +
        historyMerchant * 1.5 +
        historyCategory * 1.2 +
        globalMerchant * 0.9 +
        globalCategory * 0.7 +
        globalProduct * 0.8 +
        profileCategoryWeight * 1.4 +
        profileMerchant * 1.8 +
        learnedTokenMatch * 1.2;

      if (candidate.isFavorite || historyWeights.favoriteProductIds.has(candidate.productId)) {
        score += 1.5;
      }

      if (intent.wantsFreeDelivery) {
        score += candidate.freeDelivery ? 1.7 : -0.4;
      }
      if (intent.wantsFast) {
        score += popularityScore * 0.9;
      }
      if (intent.audienceType === "group") {
        score += candidate.freeDelivery ? 0.55 : 0;
      } else if (intent.audienceType === "family") {
        score += categoryMatch ? 0.35 : 0;
      } else if (intent.audienceType === "solo") {
        score += priceScore * 0.25;
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
          globalMerchant,
          globalCategory,
          globalProduct,
          profileMerchant,
          learnedTokenMatch,
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

function buildDraftCandidate(
  scoredProducts,
  requestedQuantity = 1,
  audienceType = "unknown"
) {
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

  let primaryQuantity = requestedQuantity;
  if (audienceType === "group" && primaryQuantity < 3) primaryQuantity = 3;
  if (audienceType === "family" && primaryQuantity < 2) primaryQuantity = 2;

  const withQuantities = selectedItems.map((item, index) => ({
    productId: item.productId,
    productName: item.productName,
    quantity: index === 0 ? primaryQuantity : 1,
    unitPrice: item.effectivePrice,
    lineTotal: item.effectivePrice * (index === 0 ? primaryQuantity : 1),
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
  return `${Math.round(amount).toLocaleString("en-US")} IQD`;
}

function mapProfileForApi(profile) {
  const topCategories = Object.entries(profile.categorySignals || {})
    .map(([key, value]) => ({
      key,
      weight: Number(value || 0),
    }))
    .sort((a, b) => b.weight - a.weight)
    .slice(0, 5);

  const favoriteTokens = Object.entries(profile.tokenSignals || {})
    .map(([key, value]) => ({ key, weight: Number(value || 0) }))
    .sort((a, b) => b.weight - a.weight)
    .slice(0, 7);

  const topMerchants = Object.entries(profile.merchantSignals || {})
    .map(([merchantId, value]) => ({
      merchantId: Number(merchantId),
      weight: Number(value || 0),
    }))
    .sort((a, b) => b.weight - a.weight)
    .slice(0, 5);

  const topAudiences = Object.entries(profile.audienceSignals || {})
    .map(([key, value]) => ({ key, weight: Number(value || 0) }))
    .sort((a, b) => b.weight - a.weight)
    .slice(0, 3);

  return {
    pricePreference: profile.pricePreference,
    counters: profile.counters,
    topCategories,
    favoriteTokens,
    topMerchants,
    topAudiences,
    conversation: profile.conversation,
  };
}

function buildReasonPhrases(intent, merchants) {
  const reasons = [];
  if (intent.wantsCheap) reasons.push('rakazt 3al ar5as');
  if (intent.wantsTopRated) reasons.push('rakazt 3al a3la taqyeem');
  if (intent.wantsFreeDelivery) reasons.push('free delivery dakhal bil awlawiya');
  if (intent.categoryHints.length) reasons.push('t7adeed no3 el matloob');
  if (intent.wantsFast) reasons.push('afdal tawseel saree3');
  if (!reasons.length) {
    reasons.push('esta5damt tareekh t6labatk w soug el yom');
  }

  if (merchants.length) {
    reasons.push(`a7san taree7 hassa: ${merchants[0].merchantName}`);
  }

  return reasons;
}

function buildRefocusQuestion(intent, profile) {
  if (intent.audienceType === 'group') {
    return 'momtaz, andak 9youf. trid draft jahiz l3adad akbar?';
  }
  if (intent.audienceType === 'family') {
    return 'tam, ll3a2la. t7eb options tashba3 aktar bse3r monaseb?';
  }
  if (!intent.categoryHints.length) {
    return 'shno t7eb hassa? burger, pizza, mashawi, baqala, aw electronics?';
  }
  if (!intent.budgetIqd && profile.pricePreference !== 'premium') {
    return '7adedly budget taqreebi bil IQD ta asawi rank adaq.';
  }
  if (!intent.orderIntent) {
    return 'trid asawilek draft jahiz hassa?';
  }
  return 'qabel el tatbeet, t7eb azid aw ashil shay?';
}

function buildOffTopicSnippet(intent) {
  switch (intent.offTopicTheme) {
    case "weather":
      return 'jaw basmaya yitghayar, fa afdal n5tar option qareeb w saree3.';
    case "joke":
      return 'nokta sree3a: el diet yebda ba3ad bokra dyman :)';
    case "bot_identity":
      return 'ana mosa3ed BestOffer, artab matager w products b7asab talabak.';
    case "mood":
      return 'ana tamam, weyak step by step l7ad ma yethabet talabak.';
    default:
      return 'aqdar a7chi wayak, bas dawari el asasi khidmat el talabat.';
  }
}

function buildSmallTalkReply({ intent, profile, merchants, products }) {
  let intro = 'ana weyak.';
  if (intent.smallTalkType === 'greeting') {
    intro = 'hala beek, nwartna.';
  } else if (intent.smallTalkType === 'thanks') {
    intro = 'tadlal, hatha wajebna.';
  } else if (intent.smallTalkType === 'chitchat' || intent.offTopicIntent) {
    intro = buildOffTopicSnippet(intent);
  }

  const merchantHint = merchants.length
    ? `aqarab match hassa: ${merchants[0].merchantName}.`
    : 'min t7aded talabak, aratablik afdal options fawran.';
  const productHint = products.length
    ? `mathal sree3: ${products[0].productName} b ${formatIqd(products[0].effectivePrice)}.`
    : '';
  const refocus = buildRefocusQuestion(intent, profile);
  return `${intro} ${merchantHint} ${productHint} ${refocus}`;
}

function summarizeRecentContext(recentMessages) {
  const recentUser = (recentMessages || [])
    .filter((msg) => msg.role === 'user' && typeof msg.text === 'string')
    .slice(-2)
    .map((msg) => msg.text.trim())
    .filter(Boolean);
  if (!recentUser.length) return null;
  if (recentUser.length === 1) return `a5er taleb: ${recentUser[0]}.`;
  return `a5er talabeen: ${recentUser[0]} , ba3daha ${recentUser[1]}.`;
}

function buildAssistantReply({
  intent,
  merchants,
  products,
  draft,
  createdOrder,
  confirmFromDraft,
  profile,
  recentContext,
}) {
  if (createdOrder && confirmFromDraft) {
    return `tm. talab #${createdOrder.id} t2akad mn ${createdOrder.merchantName} bmajmoo3 ${formatIqd(createdOrder.totalAmount)}. tqdar ttaab3a mn talabati.`;
  }

  if (intent.offTopicIntent || intent.smallTalkType !== 'none') {
    return buildSmallTalkReply({ intent, profile, merchants, products });
  }

  if (draft) {
    const firstItem = draft.items[0];
    const itemText = firstItem
      ? `${firstItem.productName} x${firstItem.quantity}`
      : 'items murtaba';
    const contextLine = recentContext ? `${recentContext} ` : '';
    return `${contextLine}sawaitlak draft jahiz mn ${draft.merchantName} b ${itemText}. if kulshi zain dos confirm, w if trid taghyeer golii hassa.`;
  }

  if (!products.length) {
    return 'hassa ma leget match qawi. 7aded no3 el talab aw budget bil IQD w ana azabitha.';
  }

  const topMerchants = merchants.slice(0, 3).map((m) => m.merchantName).join(', ');
  const reasons = buildReasonPhrases(intent, merchants).join(' | ');
  const refocus = buildRefocusQuestion(intent, profile);
  const contextLine = recentContext ? `${recentContext} ` : '';
  return `${contextLine}ratabt el options el an b7asab talabak. stores el mrfadla: ${topMerchants || 'stores qareeba'}. asbab el tarteeb: ${reasons}. ${refocus}`;
}

function buildDraftRationale(intent) {
  const reasons = [];
  if (intent.wantsCheap) reasons.push('price-sensitive ranking');
  if (intent.wantsTopRated) reasons.push('rating-sensitive ranking');
  if (intent.wantsFreeDelivery) reasons.push('free-delivery preference');
  if (intent.categoryHints.length) reasons.push('category alignment');
  if (intent.audienceType !== "unknown") reasons.push(`audience:${intent.audienceType}`);
  if (!reasons.length) reasons.push('history-based ranking');
  return reasons.join(' | ');
}

function learnFromConfirmedDraft(profile, draft) {
  const next = {
    ...profile,
    counters: { ...profile.counters },
    categorySignals: { ...profile.categorySignals },
    merchantSignals: { ...profile.merchantSignals },
    tokenSignals: { ...profile.tokenSignals },
    audienceSignals: { ...profile.audienceSignals },
    conversation: { ...profile.conversation },
  };

  next.counters.ordering += 1;
  next.conversation.confirmedDrafts += 1;
  next.conversation.lastIntent = 'draft_confirmed';

  bumpMapCount(next.merchantSignals, String(draft.merchantId), 2.5);
  for (const item of draft.items || []) {
    const itemTokens = tokenize(item.productName || '');
    boostTokenSignals(next.tokenSignals, itemTokens, 1.25);
  }

  next.merchantSignals = trimSignalMap(next.merchantSignals, 90);
  next.tokenSignals = trimSignalMap(next.tokenSignals, 150);
  next.audienceSignals = trimSignalMap(next.audienceSignals, 30);
  return next;
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
    // Client can hold a stale session id after app reinstall / DB reset.
    // Fallback to latest session (or create one) instead of failing hard.
    if (existing) return existing;
  }

  return (await repo.getLatestSession(customerUserId)) || repo.createSession(customerUserId);
}

async function ensureWelcomeMessage(sessionId) {
  const messages = await repo.listMessages(sessionId, 2);
  if (messages.length) return;
  await repo.insertMessage(
    sessionId,
    'assistant',
    'hala beek. ani mosa3edak bil talab. akdarlak aratab el stores w asawilek draft jahiz.'
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

  const orderNote = [draft.note, options.note, 'created_via_ai_assistant']
    .filter((part) => typeof part === "string" && part.trim().length)
    .join(" | ");

  const createdOrder = await createOrder(customerUserId, {
    merchantId: draft.merchantId,
    addressId: resolvedAddressId,
    note: orderNote,
    items,
  });

  await repo.markDraftConfirmed(draft.id, createdOrder.id);

  const rawProfile = await repo.getProfile(customerUserId);
  const profile = learnFromConfirmedDraft(parseProfile(rawProfile), draft);
  await repo.upsertProfile(
    customerUserId,
    profile,
    "updated_from_draft_confirmation"
  );

  const assistantText = buildAssistantReply({
    intent: { offTopicIntent: false, smallTalkType: "none", categoryHints: [] },
    merchants: [],
    products: [],
    draft: null,
    createdOrder: mapOrderForApi(createdOrder),
    confirmFromDraft: true,
    profile,
    recentContext: null,
  });

  const assistantMessage = await repo.insertMessage(session.id, "assistant", assistantText, {
    type: "draft_confirmed",
    draftToken: draft.token,
    orderId: createdOrder.id,
  });

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
      audienceType: intent.audienceType,
      offTopicTheme: intent.offTopicTheme,
    });
  }

  if (intent.cancelIntent) {
    const pending = await repo.getLatestPendingDraft(customerUserId, session.id);
    if (pending) {
      await repo.markDraftCancelled(pending.id);
    }

    const cancelMessage = await repo.insertMessage(
      session.id,
      'assistant',
      'tlaqa el draft. goli shno t7eb t6lob hassa w asawilek tarteeb jadeed.'
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

  const [rawProfile, historySignals, globalSignals, pool, recentMessages] = await Promise.all([
    repo.getProfile(customerUserId),
    repo.getHistorySignals(customerUserId),
    repo.getGlobalSignals(),
    repo.listRecommendationPool(customerUserId, 900),
    repo.listMessages(session.id, 12),
  ]);

  const profile = mergeProfileSignals(parseProfile(rawProfile), intent);
  await repo.upsertProfile(customerUserId, profile, "updated_from_chat");

  const historyWeights = buildHistoryWeights(historySignals, globalSignals);
  const ranked = rankProducts({
    pool,
    intent,
    profile,
    historyWeights,
  });
  const recentContext = summarizeRecentContext(recentMessages);

  const merchantSuggestions = buildMerchantSuggestions(ranked);
  const productSuggestions = buildProductSuggestions(ranked);

  let createdDraft = null;
  const shouldDraft =
    (intent.orderIntent || dto.createDraft === true) && !intent.offTopicIntent;
  if (shouldDraft && ranked.length) {
    const draftCandidate = buildDraftCandidate(
      ranked,
      intent.requestedQuantity,
      intent.audienceType
    );
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
        note: 'suggested_draft_generated_by_ai',
        items: draftCandidate.items,
        subtotal: draftCandidate.subtotal,
        serviceFee: draftCandidate.serviceFee,
        deliveryFee: draftCandidate.deliveryFee,
        totalAmount: draftCandidate.totalAmount,
        rationale: buildDraftRationale(intent),
      });

      if (createdDraft) {
        bumpMapCount(profile.merchantSignals, String(createdDraft.merchantId), 1.1);
        profile.merchantSignals = trimSignalMap(profile.merchantSignals, 90);
        profile.conversation.lastIntent = "draft_created";
        await repo.upsertProfile(
          customerUserId,
          profile,
          "updated_from_draft_created"
        );
      }
    }
  }

  const assistantText = buildAssistantReply({
    intent,
    merchants: merchantSuggestions,
    products: productSuggestions,
    draft: createdDraft,
    createdOrder: null,
    confirmFromDraft: false,
    profile,
    recentContext,
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


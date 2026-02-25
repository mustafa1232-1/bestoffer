import crypto from "crypto";

import { createOrder } from "../orders/orders.service.js";
import * as repo from "./assistant.repo.js";
import {
  getScenarioLibrarySize,
  pickScenarioBlueprint,
  pickScenarioQuestion,
} from "./assistant.scenarios.js";

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

const LANG_EN_KEYWORDS = [
  'english',
  'in english',
  '\u0627\u0646\u0643\u0644\u064a\u0632\u064a',
  '\u0627\u0646\u0643\u0644\u0634',
  '\u0628\u0627\u0644\u0627\u0646\u0643\u0644\u064a\u0632\u064a',
];

const LANG_AR_KEYWORDS = [
  'arabic',
  '\u0639\u0631\u0628\u064a',
  '\u0628\u0627\u0644\u0639\u0631\u0628\u064a',
];

const DISCOVER_NEW_KEYWORDS = [
  'new',
  '\u062c\u062f\u064a\u062f',
  '\u0634\u0646\u0648 \u0627\u0644\u062c\u062f\u064a\u062f',
];

const OFFERS_KEYWORDS = [
  'offers',
  'offer',
  'discount',
  '\u0639\u0631\u0648\u0636',
  '\u062e\u0635\u0645',
  '\u062d\u0633\u0648\u0645\u0627\u062a',
  '1+1',
];

const RECOMMEND_KEYWORDS = [
  'recommend',
  '\u0627\u0646\u0635\u062d\u0646\u064a',
  '\u0631\u0634\u062d\u0644\u064a',
  '\u0627\u0642\u062a\u0631\u062d',
];

const EVALUATE_KEYWORDS = [
  'what do you think',
  '\u0631\u0623\u064a\u0643',
  '\u0634\u0631\u0623\u064a\u0643',
  '\u0631\u0627\u064a\u0643',
];

const SUPPORT_KEYWORDS = [
  'problem',
  'issue',
  'late',
  'missing',
  'wrong',
  '\u0645\u0634\u0643\u0644\u0629',
  '\u062a\u0623\u062e\u0631',
  '\u0646\u0627\u0642\u0635',
  '\u063a\u0644\u0637',
  '\u0633\u064a\u0621',
  '\u0627\u0634\u062a\u0643\u064a',
  '\u0634\u0643\u0648\u0649',
];

const MOOD_BASED_KEYWORDS = [
  'what to eat',
  '\u0634\u0646\u0648 \u0622\u0643\u0644',
  '\u0634\u0646\u0648 \u0627\u0643\u0644',
  '\u0645\u0632\u0627\u062c',
  '\u0634\u0646\u0648 \u062a\u0634\u062a\u0647\u064a',
];

const COMPARISON_KEYWORDS = [
  'compare',
  '\u0642\u0627\u0631\u0646',
  '\u0645\u0642\u0627\u0631\u0646\u0629',
];

const HURRY_KEYWORDS = [
  '\u0645\u0633\u062a\u0639\u062c\u0644',
  '\u0633\u0631\u064a\u0639',
  '\u0628\u0633\u0631\u0639\u0629',
  'quick',
  'fast',
  'hurry',
];

const FORMAL_STYLE_KEYWORDS = [
  '\u0645\u0646 \u0641\u0636\u0644\u0643',
  '\u0631\u062c\u0627\u0621',
  'please',
];

const PLAYFUL_STYLE_KEYWORDS = [
  '\u0647\u0647',
  '\u0644\u0648\u0644',
  '\u0645\u0632\u062d',
  'haha',
  'lol',
];

const DIETARY_KEYWORDS = [
  { key: '\u0628\u062f\u0648\u0646 \u0644\u062d\u0645', words: ['\u0628\u062f\u0648\u0646 \u0644\u062d\u0645', 'no meat'] },
  { key: '\u0646\u0628\u0627\u062a\u064a', words: ['\u0646\u0628\u0627\u062a\u064a', 'vegan', 'vegetarian'] },
  { key: '\u0628\u062f\u0648\u0646 \u063a\u0644\u0648\u062a\u064a\u0646', words: ['\u0628\u062f\u0648\u0646 \u063a\u0644\u0648\u062a\u064a\u0646', 'gluten'] },
  { key: '\u062d\u0633\u0627\u0633\u064a\u0629', words: ['\u062d\u0633\u0627\u0633\u064a\u0629', 'allergy'] },
];

const SUPPORT_DELAY_KEYWORDS = [
  '\u062a\u0623\u062e\u0631',
  'late',
  '\u0645\u062a\u0623\u062e\u0631',
];

const SUPPORT_MISSING_KEYWORDS = [
  '\u0646\u0627\u0642\u0635',
  'missing',
  '\u0645\u0627 \u0648\u0635\u0644',
];

const SUPPORT_WRONG_KEYWORDS = [
  '\u063a\u0644\u0637',
  'wrong',
  '\u063a\u064a\u0631 \u0627\u0644\u0645\u0637\u0644\u0648\u0628',
];

const MEAL_TYPE_KEYWORDS = {
  breakfast: ['\u0641\u0637\u0648\u0631', 'breakfast'],
  lunch: ['\u063a\u062f\u0627\u0621', 'lunch'],
  dinner: ['\u0639\u0634\u0627\u0621', 'dinner'],
  snack: ['\u0633\u0646\u0627\u0643', 'snack'],
};

const SPICE_LEVEL_KEYWORDS = {
  mild: ['\u0639\u0627\u062f\u064a', 'mild'],
  medium: ['\u062d\u0627\u0631', 'medium spicy'],
  hot: ['\u0646\u0627\u0631', '\u062d\u0627\u0631 \u062c\u062f\u0627', 'very spicy', 'hot'],
};

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

function countLatinChars(value) {
  const text = String(value || '');
  const matches = text.match(/[A-Za-z]/g);
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

function detectLanguageSwitch(normalizedText) {
  if (containsAny(normalizedText, LANG_EN_KEYWORDS)) return "en";
  if (containsAny(normalizedText, LANG_AR_KEYWORDS)) return "ar";
  return null;
}

function detectTextLanguage(rawText) {
  const text = String(rawText || "");
  const arabic = countArabicChars(text);
  const latin = countLatinChars(text);
  const enHint =
    /\b(hello|hi|hey|please|what|want|order|restaurant|menu|offer|delivery|price|cheap|rating|thanks|english)\b/i.test(
      text
    );
  if (arabic === 0 && latin === 0) return "ar";
  if (arabic === 0) return enHint ? "en" : "ar";
  if (arabic >= latin * 0.6) return "ar";
  if (enHint) return "en";
  return "en";
}

function detectConversationStyle(normalizedText) {
  if (containsAny(normalizedText, HURRY_KEYWORDS)) return "rush";
  if (containsAny(normalizedText, FORMAL_STYLE_KEYWORDS)) return "formal";
  if (containsAny(normalizedText, PLAYFUL_STYLE_KEYWORDS)) return "playful";
  return "neutral";
}

function detectDietaryNotes(normalizedText) {
  const notes = [];
  for (const note of DIETARY_KEYWORDS) {
    if (containsAny(normalizedText, note.words)) notes.push(note.key);
  }
  return Array.from(new Set(notes));
}

function detectSupportType(normalizedText) {
  if (containsAny(normalizedText, SUPPORT_DELAY_KEYWORDS)) return "delay";
  if (containsAny(normalizedText, SUPPORT_MISSING_KEYWORDS)) return "missing_items";
  if (containsAny(normalizedText, SUPPORT_WRONG_KEYWORDS)) return "wrong_order";
  return "general";
}

function detectMealType(normalizedText) {
  for (const [key, words] of Object.entries(MEAL_TYPE_KEYWORDS)) {
    if (containsAny(normalizedText, words)) return key;
  }
  return "any";
}

function detectSpiceLevel(normalizedText) {
  for (const [key, words] of Object.entries(SPICE_LEVEL_KEYWORDS)) {
    if (containsAny(normalizedText, words)) return key;
  }
  return "unknown";
}

function extractPeopleCount(normalizedText, audienceType = "unknown") {
  const match = normalizedText.match(
    /(\d{1,2})\s*(?:\u0634\u062e\u0635|\u0627\u0634\u062e\u0627\u0635|person|people)/iu
  );
  if (match?.[1]) {
    const n = Number(match[1]);
    if (Number.isFinite(n) && n >= 1 && n <= 40) return n;
  }
  if (audienceType === "solo") return 1;
  if (audienceType === "family") return 4;
  if (audienceType === "group") return 6;
  return null;
}

function defaultConversationModel() {
  return {
    phase: "discovery",
    turns: 0,
    clarificationTurns: 0,
    recommendationTurns: 0,
    lastQuestionSlot: null,
    lastQuestionAt: null,
    slots: {
      cuisine: null,
      budgetLevel: "unknown",
      budgetIqd: null,
      speedPriority: "balanced",
      qualityPriority: "balanced",
      mealType: "any",
      spiceLevel: "unknown",
      audienceType: "unknown",
      peopleCount: null,
      dietary: [],
      city: null,
      area: null,
    },
  };
}

function normalizeConversationModel(raw) {
  const base = defaultConversationModel();
  if (!raw || typeof raw !== "object") return base;
  const slots = raw.slots && typeof raw.slots === "object" ? raw.slots : {};
  return {
    phase: ["discovery", "understanding", "recommendation", "support", "checkout"].includes(
      raw.phase
    )
      ? raw.phase
      : base.phase,
    turns: Number(raw.turns || 0),
    clarificationTurns: Number(raw.clarificationTurns || 0),
    recommendationTurns: Number(raw.recommendationTurns || 0),
    lastQuestionSlot: raw.lastQuestionSlot || null,
    lastQuestionAt: raw.lastQuestionAt || null,
    slots: {
      ...base.slots,
      ...slots,
      dietary: Array.isArray(slots.dietary)
        ? slots.dietary.filter((x) => typeof x === "string")
        : [],
    },
  };
}

function deriveConversationPriority(intent, profile) {
  if (intent.wantsCheap) return "cheap";
  if (intent.wantsFast) return "fast";
  if (intent.wantsTopRated) return "quality";
  if (profile?.pricePreference === "cheap") return "cheap";
  if (profile?.qualityPriority === "high") return "quality";
  return "balanced";
}

function deriveConversationSlots(intent, profile) {
  const slots = {};
  if (intent.categoryHints?.[0]) slots.cuisine = intent.categoryHints[0];
  if (intent.budgetIqd != null) {
    slots.budgetIqd = intent.budgetIqd;
    if (intent.budgetIqd <= 12000) slots.budgetLevel = "low";
    else if (intent.budgetIqd <= 30000) slots.budgetLevel = "medium";
    else slots.budgetLevel = "high";
  }

  if (intent.wantsFast) slots.speedPriority = "high";
  if (intent.wantsTopRated) slots.qualityPriority = "high";
  if (intent.wantsCheap && !intent.wantsTopRated) {
    slots.qualityPriority = "balanced";
  }

  if (intent.audienceType && intent.audienceType !== "unknown") {
    slots.audienceType = intent.audienceType;
  }
  const people = extractPeopleCount(intent.normalizedText, intent.audienceType);
  if (people != null) slots.peopleCount = people;
  const mealType = detectMealType(intent.normalizedText);
  if (mealType !== "any") slots.mealType = mealType;
  const spiceLevel = detectSpiceLevel(intent.normalizedText);
  if (spiceLevel !== "unknown") slots.spiceLevel = spiceLevel;
  if (intent.cityHint) slots.city = intent.cityHint;
  if (intent.areaHint) slots.area = intent.areaHint;
  if (intent.dietaryNotes?.length) slots.dietary = intent.dietaryNotes;

  if (!slots.city && profile?.city) slots.city = profile.city;
  if (!slots.area && profile?.area) slots.area = profile.area;
  return slots;
}

function mergeConversationModel(profile, intent) {
  const model = normalizeConversationModel(profile.conversationModel);
  model.turns += 1;
  const derived = deriveConversationSlots(intent, profile);

  if (derived.cuisine) model.slots.cuisine = derived.cuisine;
  if (derived.budgetLevel) model.slots.budgetLevel = derived.budgetLevel;
  if (derived.budgetIqd != null) model.slots.budgetIqd = derived.budgetIqd;
  if (derived.speedPriority) model.slots.speedPriority = derived.speedPriority;
  if (derived.qualityPriority) model.slots.qualityPriority = derived.qualityPriority;
  if (derived.mealType) model.slots.mealType = derived.mealType;
  if (derived.spiceLevel) model.slots.spiceLevel = derived.spiceLevel;
  if (derived.audienceType) model.slots.audienceType = derived.audienceType;
  if (derived.peopleCount != null) model.slots.peopleCount = derived.peopleCount;
  if (derived.city) model.slots.city = derived.city;
  if (derived.area) model.slots.area = derived.area;
  if (Array.isArray(derived.dietary) && derived.dietary.length) {
    model.slots.dietary = Array.from(new Set([...model.slots.dietary, ...derived.dietary]));
  }

  if (intent.supportIntent) {
    model.phase = "support";
  } else if (model.phase !== "recommendation") {
    model.phase = model.turns >= 2 ? "understanding" : "discovery";
  }

  return model;
}

function conversationCoreFilledCount(model) {
  const slots = model?.slots || {};
  let count = 0;
  if (slots.cuisine) count += 1;
  if (slots.budgetLevel && slots.budgetLevel !== "unknown") count += 1;
  if (slots.speedPriority && slots.speedPriority !== "balanced") count += 1;
  if (slots.mealType && slots.mealType !== "any") count += 1;
  if (slots.peopleCount != null) count += 1;
  if (Array.isArray(slots.dietary) && slots.dietary.length) count += 1;
  return count;
}

function nextMissingSlot(model) {
  const slots = model?.slots || {};
  if (!slots.cuisine) return "cuisine";
  if (!slots.budgetLevel || slots.budgetLevel === "unknown") return "budget";
  if (!slots.speedPriority || slots.speedPriority === "balanced") return "speed";
  if (!slots.mealType || slots.mealType === "any") return "meal";
  if (slots.peopleCount == null) return "audience";
  if (!Array.isArray(slots.dietary) || slots.dietary.length === 0) return "dietary";
  return null;
}

function decideConversationMode({ intent, model }) {
  const directIntentTypes = new Set(["OFFERS", "DISCOVER_NEW", "EVALUATE", "SUPPORT"]);
  if (intent.supportIntent || directIntentTypes.has(intent.primaryIntent) || intent.comparisonIntent) {
    return { mode: "specialized", ready: true };
  }

  const filled = conversationCoreFilledCount(model);
  const minimumTurns =
    intent.primaryIntent === "RECOMMEND" || intent.primaryIntent === "MOOD_BASED" ? 2 : 3;
  const minimumSlots = intent.primaryIntent === "ORDER_DIRECT" ? 3 : 3;
  const ready = filled >= minimumSlots && model.turns >= minimumTurns;
  if (ready) return { mode: "recommendation", ready: true };
  return { mode: "discovery", ready: false, missingSlot: nextMissingSlot(model), filled };
}

function detectPrimaryIntent(normalizedText, supportIntent) {
  if (supportIntent) return "SUPPORT";
  if (containsAny(normalizedText, DISCOVER_NEW_KEYWORDS)) return "DISCOVER_NEW";
  if (containsAny(normalizedText, OFFERS_KEYWORDS)) return "OFFERS";
  if (containsAny(normalizedText, EVALUATE_KEYWORDS)) return "EVALUATE";
  if (containsAny(normalizedText, MOOD_BASED_KEYWORDS)) return "MOOD_BASED";
  if (containsAny(normalizedText, RECOMMEND_KEYWORDS)) return "RECOMMEND";
  if (containsAny(normalizedText, ORDER_KEYWORDS)) return "ORDER_DIRECT";
  return "BROWSE";
}

function extractCityAreaHints(normalizedText) {
  const hints = { city: null, area: null };
  if (
    normalizedText.includes(normalizeForNlp("\u0628\u0633\u0645\u0627\u064a\u0629")) ||
    normalizedText.includes(normalizeForNlp("\u0645\u062f\u064a\u0646\u0629 \u0628\u0633\u0645\u0627\u064a\u0629"))
  ) {
    hints.city = "\u0645\u062f\u064a\u0646\u0629 \u0628\u0633\u0645\u0627\u064a\u0629";
  }

  const blockMatch = normalizedText.match(
    /(?:block|bl|b|بلوك)\s*([a-z0-9\u0660-\u0669\u06F0-\u06F9]+)/iu
  );
  if (blockMatch?.[1]) {
    hints.area = `\u0628\u0644\u0648\u0643 ${normalizeDigits(blockMatch[1])}`;
  }

  return hints;
}

function detectIntent(message) {
  const rawMessage = String(message || "");
  const normalized = normalizeForNlp(rawMessage);
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
  const comparisonIntent = containsAny(normalized, COMPARISON_KEYWORDS);
  const supportIntent = containsAny(normalized, SUPPORT_KEYWORDS);
  const budgetIqd = extractBudgetIqd(normalized);
  const tokens = tokenize(normalized);
  const supportType = detectSupportType(normalized);
  const dietaryNotes = detectDietaryNotes(normalized);
  const mealType = detectMealType(normalized);
  const spiceLevel = detectSpiceLevel(normalized);
  const style = detectConversationStyle(normalized);
  const languageSwitch = detectLanguageSwitch(normalized);
  const inferredLanguage = languageSwitch || detectTextLanguage(rawMessage);
  const cityAreaHints = extractCityAreaHints(normalized);
  const peopleCount = extractPeopleCount(normalized, audienceType);

  const hasDomainTerms =
    containsAny(normalized, ORDER_DOMAIN_KEYWORDS) ||
    categoryHints.length > 0 ||
    budgetIqd != null ||
    supportIntent;

  const hardOrderSignals =
    orderIntent ||
    confirmIntent ||
    cancelIntent ||
    wantsCheap ||
    wantsTopRated ||
    wantsFreeDelivery ||
    wantsFast;

  const offTopicIntent =
    !hardOrderSignals &&
    !hasDomainTerms &&
    tokens.length > 0 &&
    smallTalkType !== "greeting";
  const offTopicTheme = offTopicIntent ? detectOffTopicTheme(normalized) : "none";
  const primaryIntent = detectPrimaryIntent(normalized, supportIntent);

  return {
    normalizedText: normalized,
    originalText: rawMessage,
    tokens,
    wantsCheap,
    wantsTopRated,
    wantsFreeDelivery,
    wantsFast,
    orderIntent,
    confirmIntent,
    cancelIntent,
    comparisonIntent,
    supportIntent,
    supportType,
    offTopicIntent,
    offTopicTheme,
    smallTalkType,
    audienceType,
    budgetIqd,
    mealType,
    spiceLevel,
    peopleCount,
    dietaryNotes,
    style,
    inferredLanguage,
    explicitLanguageSwitch: languageSwitch,
    primaryIntent,
    cityHint: cityAreaHints.city,
    areaHint: cityAreaHints.area,
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
    languagePreference: preferenceJson.languagePreference || "ar",
    personalityStyle: preferenceJson.personalityStyle || "neutral",
    city: preferenceJson.city || null,
    area: preferenceJson.area || null,
    dietaryNotes: Array.isArray(preferenceJson.dietaryNotes)
      ? preferenceJson.dietaryNotes.filter((x) => typeof x === "string")
      : [],
    preferredCuisines: Array.isArray(preferenceJson.preferredCuisines)
      ? preferenceJson.preferredCuisines.filter((x) => typeof x === "string")
      : [],
    budgetLevel: preferenceJson.budgetLevel || "unknown",
    speedPriority: preferenceJson.speedPriority || "balanced",
    qualityPriority: preferenceJson.qualityPriority || "balanced",
    favoriteRestaurants: Array.isArray(preferenceJson.favoriteRestaurants)
      ? preferenceJson.favoriteRestaurants.filter((x) => typeof x === "string")
      : [],
    dislikedRestaurants: Array.isArray(preferenceJson.dislikedRestaurants)
      ? preferenceJson.dislikedRestaurants.filter((x) => typeof x === "string")
      : [],
    issueHistory: Array.isArray(preferenceJson.issueHistory)
      ? preferenceJson.issueHistory.slice(0, 30)
      : [],
    satisfactionHistory: Array.isArray(preferenceJson.satisfactionHistory)
      ? preferenceJson.satisfactionHistory.slice(0, 25)
      : [],
    commonOrderTime: preferenceJson.commonOrderTime || null,
    averageRatingGiven:
      preferenceJson.averageRatingGiven == null
        ? null
        : Number(preferenceJson.averageRatingGiven),
    lastInteractionSummary: preferenceJson.lastInteractionSummary || null,
    loyaltyLevel: preferenceJson.loyaltyLevel || "new",
    learningConfidence: preferenceJson.learningConfidence || "low",
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
    conversationModel: normalizeConversationModel(preferenceJson.conversationModel),
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
    conversationModel: normalizeConversationModel(profile.conversationModel),
    dietaryNotes: [...(profile.dietaryNotes || [])],
    preferredCuisines: [...(profile.preferredCuisines || [])],
    favoriteRestaurants: [...(profile.favoriteRestaurants || [])],
    dislikedRestaurants: [...(profile.dislikedRestaurants || [])],
    issueHistory: [...(profile.issueHistory || [])],
    satisfactionHistory: [...(profile.satisfactionHistory || [])],
  };

  if (intent.wantsCheap) next.counters.cheap += 1;
  if (intent.wantsTopRated) next.counters.topRated += 1;
  if (intent.wantsFreeDelivery) next.counters.freeDelivery += 1;
  if (intent.orderIntent) next.counters.ordering += 1;
  if (intent.smallTalkType !== "none") next.conversation.smallTalkCount += 1;
  if (intent.offTopicIntent) next.conversation.offTopicCount += 1;
  if (intent.explicitLanguageSwitch) {
    next.languagePreference = intent.explicitLanguageSwitch;
  } else {
    next.languagePreference = profile.languagePreference || intent.inferredLanguage || "ar";
  }

  if (intent.style === "formal") next.personalityStyle = "formal";
  if (intent.style === "playful") next.personalityStyle = "playful";
  if (intent.style === "rush") next.personalityStyle = "rush";

  if (intent.cityHint) next.city = intent.cityHint;
  if (intent.areaHint) next.area = intent.areaHint;
  for (const dietary of intent.dietaryNotes || []) {
    if (!next.dietaryNotes.includes(dietary)) next.dietaryNotes.push(dietary);
  }

  for (const category of intent.categoryHints) {
    bumpMapCount(next.categorySignals, category, 1);
    if (!next.preferredCuisines.includes(category)) {
      next.preferredCuisines.push(category);
    }
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

  if (intent.budgetIqd != null) {
    if (intent.budgetIqd <= 12000) next.budgetLevel = "low";
    else if (intent.budgetIqd <= 30000) next.budgetLevel = "medium";
    else next.budgetLevel = "high";
  }

  if (intent.wantsFast) next.speedPriority = "high";
  else if (intent.wantsCheap) next.speedPriority = next.speedPriority || "balanced";

  if (intent.wantsTopRated) next.qualityPriority = "high";
  if (intent.wantsCheap && !intent.wantsTopRated) next.qualityPriority = "balanced";

  // Keep compact memory buffers.
  next.dietaryNotes = Array.from(new Set(next.dietaryNotes)).slice(0, 10);
  next.preferredCuisines = Array.from(new Set(next.preferredCuisines)).slice(0, 12);
  next.favoriteRestaurants = Array.from(new Set(next.favoriteRestaurants)).slice(0, 20);
  next.dislikedRestaurants = Array.from(new Set(next.dislikedRestaurants)).slice(0, 20);
  next.issueHistory = next.issueHistory.slice(0, 20);
  next.satisfactionHistory = next.satisfactionHistory.slice(0, 20);

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
      deliveryMinutesSum: 0,
      deliveryMinutesCount: 0,
      hasFreeDelivery: false,
      topProducts: [],
    };

    current.scoreSum += candidate.score;
    current.scoreCount += 1;
    current.minPrice = Math.min(current.minPrice, candidate.effectivePrice);
    current.maxPrice = Math.max(current.maxPrice, candidate.effectivePrice);
    current.hasFreeDelivery = current.hasFreeDelivery || candidate.freeDelivery;
    if (Number.isFinite(Number(candidate.merchantAvgDeliveryMinutes))) {
      current.deliveryMinutesSum += Number(candidate.merchantAvgDeliveryMinutes);
      current.deliveryMinutesCount += 1;
    }

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
      avgDeliveryMinutes:
        merchant.deliveryMinutesCount > 0
          ? merchant.deliveryMinutesSum / merchant.deliveryMinutesCount
          : null,
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
    languagePreference: profile.languagePreference,
    personalityStyle: profile.personalityStyle,
    city: profile.city,
    area: profile.area,
    dietaryNotes: profile.dietaryNotes,
    preferredCuisines: profile.preferredCuisines,
    budgetLevel: profile.budgetLevel,
    speedPriority: profile.speedPriority,
    qualityPriority: profile.qualityPriority,
    favoriteRestaurants: profile.favoriteRestaurants,
    dislikedRestaurants: profile.dislikedRestaurants,
    issueHistory: profile.issueHistory,
    satisfactionHistory: profile.satisfactionHistory,
    commonOrderTime: profile.commonOrderTime,
    averageRatingGiven: profile.averageRatingGiven,
    loyaltyLevel: profile.loyaltyLevel,
    learningConfidence: profile.learningConfidence,
    lastInteractionSummary: profile.lastInteractionSummary,
    pricePreference: profile.pricePreference,
    counters: profile.counters,
    topCategories,
    favoriteTokens,
    topMerchants,
    topAudiences,
    conversation: profile.conversation,
    conversationModel: profile.conversationModel,
  };
}

function resolveResponseLanguage(intent, profile) {
  if (intent.explicitLanguageSwitch) return intent.explicitLanguageSwitch;
  if (profile?.languagePreference === "en" || profile?.languagePreference === "ar") {
    return profile.languagePreference;
  }
  return intent.inferredLanguage || "ar";
}

function tr(lang, arText, enText) {
  return lang === "en" ? enText : arText;
}

function mapMerchantTypeLabel(type, lang) {
  const key = String(type || "").toLowerCase();
  const labelsEn = {
    restaurant: "restaurant",
    market: "market",
    grocery: "grocery",
    bakery: "bakery",
    pharmacy: "pharmacy",
    electronics: "electronics",
  };
  const labelsAr = {
    restaurant: "مطعم",
    market: "سوق",
    grocery: "بقالة",
    bakery: "معجنات",
    pharmacy: "صيدلية",
    electronics: "كهربائيات",
  };
  if (lang === "en") return labelsEn[key] || "store";
  return labelsAr[key] || "متجر";
}

function describePriceBand(merchant, lang) {
  const maxPrice = Number(merchant.maxPrice || 0);
  if (maxPrice <= 12000) return tr(lang, "رخيص", "cheap");
  if (maxPrice <= 28000) return tr(lang, "متوسط", "medium");
  return tr(lang, "غالي", "expensive");
}

function formatEtaText(avgDeliveryMinutes, lang) {
  if (avgDeliveryMinutes == null || !Number.isFinite(Number(avgDeliveryMinutes))) {
    return tr(lang, "غير متوفر حالياً", "not available");
  }
  const minutes = Math.max(7, Math.round(Number(avgDeliveryMinutes)));
  return lang === "en" ? `${minutes} min` : `${minutes} دقيقة`;
}

function formatDeliveryFeeText(hasFreeDelivery, lang) {
  if (hasFreeDelivery) return tr(lang, "مجاني", "free");
  return formatIqd(FIXED_DELIVERY_FEE);
}

function merchantReason(intent, merchant, lang) {
  const reasons = [];
  if (intent.wantsFast && merchant.avgDeliveryMinutes != null) {
    reasons.push(tr(lang, "توصيله أسرع من المعدل", "faster delivery window"));
  }
  if (intent.wantsCheap) {
    reasons.push(tr(lang, "سعره مناسب", "budget friendly"));
  }
  if (intent.wantsTopRated) {
    reasons.push(tr(lang, "تقييمه عالي", "high rating"));
  }
  if (intent.wantsFreeDelivery && merchant.hasFreeDelivery) {
    reasons.push(tr(lang, "يوفر توصيل مجاني", "offers free delivery"));
  }
  if (intent.categoryHints.length) {
    reasons.push(tr(lang, "قريب من الصنف اللي طلبته", "matches your requested category"));
  }
  if (!reasons.length) {
    reasons.push(tr(lang, "مناسب لطلباتك السابقة", "aligned with your recent orders"));
  }
  return reasons.slice(0, 2).join(tr(lang, "، ", ", "));
}

function pickSmartQuestion(intent, profile, lang, conversationModel = null) {
  const model = normalizeConversationModel(conversationModel || profile?.conversationModel);
  const missingSlot = nextMissingSlot(model);
  if (missingSlot) {
    return pickScenarioQuestion(
      missingSlot,
      lang,
      `${intent.originalText}|${model.turns}|${model.clarificationTurns}`
    );
  }

  if (intent.supportIntent) {
    return tr(
      lang,
      "تكدر ترسلي رقم الطلب حتى أتابعه إلك مباشرة؟",
      "Can you send the order number so I can follow it up now?"
    );
  }
  if (intent.primaryIntent === "OFFERS") {
    return tr(
      lang,
      "تحب عروض الشرقي لو البرغر والبيتزا؟",
      "Do you want Eastern offers or burger and pizza offers?"
    );
  }
  if (intent.primaryIntent === "MOOD_BASED") {
    return tr(
      lang,
      "مزاجك اليوم خفيف لو وجبة دسمة؟",
      "Do you want a light meal or a heavy meal today?"
    );
  }
  if (intent.wantsFast && !intent.wantsCheap) {
    return tr(
      lang,
      "تريد توصيل أسرع لو سعر أقل؟",
      "Do you prefer the fastest delivery or the lower price?"
    );
  }
  if (!intent.categoryHints.length) {
    return tr(
      lang,
      "تميل اليوم لشرقي لو غربي؟",
      "Do you prefer Eastern food or Western today?"
    );
  }
  if (intent.budgetIqd == null && profile.budgetLevel === "unknown") {
    return tr(
      lang,
      "شكد ميزانيتك تقريباً بالدينار؟",
      "What is your approximate budget in IQD?"
    );
  }
  if (intent.comparisonIntent) {
    return tr(
      lang,
      "تحب أقارنلك حسب السعر لو حسب سرعة التوصيل؟",
      "Should I compare by price or by delivery speed?"
    );
  }
  return tr(
    lang,
    "تحب أختارلك أفضل واحد وأكمل الطلب لو أعرض خيارات أكثر؟",
    "Do you want me to confirm one of these options, or show more?"
  );
}

function tonePrefix(intent, lang) {
  if (intent?.style === "formal") return tr(lang, "أكيد، ", "Certainly, ");
  if (intent?.style === "playful") return tr(lang, "حلو 😄 ", "Nice 😄 ");
  if (intent?.style === "rush") return tr(lang, "باختصار: ", "Quickly: ");
  return "";
}

function buildOffTopicSnippet(intent, lang) {
  const seed = `${intent.originalText}|${intent.normalizedText || ""}|${intent.offTopicTheme || "general"}`;
  const ar = {
    weather: "الجو يتغيّر بسرعة ببسماية، أقدر أرشّحلك خيارات أقرب وتوصيلها أسرع.",
    joke: "حتى لو الجو يخربط، الطلب المضبوط يبقى مزاج 😄",
    bot_identity: "أني مساعد تطبيق سوقي، شغلي أسهّل عليك الاختيار والطلب.",
    mood: "تمام الحمدلله، شلونك إنت اليوم؟",
    general: [
      "سوالفك حلوة، ومن تجهز نرتبلك طلب مضبوط بسرعة.",
      "تمام وياك، وبنفس الوقت أكدر أساعدك تختار طلب يناسبك.",
      "أحب الأجواء الحلوة، ومن تكتبلي مزاجك أطلعلك خيارات دقيقة.",
    ],
  };
  const en = {
    weather: "Weather keeps changing, so I can suggest closer options with quicker delivery.",
    joke: "Quick one: good food always improves the mood 😄",
    bot_identity: "I am Souqi in-app assistant, focused on smart ordering choices.",
    mood: "I am good, thanks. How are you today?",
    general: [
      "I enjoy the chat, and once you are ready I can rank precise options fast.",
      "All good, and I can still help you decide the right order when you are ready.",
      "Nice vibe. Share your mood any time and I will shape the best options.",
    ],
  };
  if (lang === "en") {
    const snippet = en[intent.offTopicTheme] || en.general;
    if (Array.isArray(snippet)) {
      return snippet[simpleHash(seed) % snippet.length];
    }
    return snippet;
  }

  const snippet = ar[intent.offTopicTheme] || ar.general;
  if (Array.isArray(snippet)) {
    return snippet[simpleHash(seed) % snippet.length];
  }
  return snippet;
}

function buildSmallTalkReply({
  intent,
  profile,
  merchants,
  products,
  conversationModel = null,
  conversationDecision = null,
  lang,
}) {
  const model = normalizeConversationModel(conversationModel || profile?.conversationModel);
  let intro = tr(lang, "هلا بيك 🌟", "Hey there 🌟");
  if (intent.smallTalkType === "greeting") {
    intro = tr(
      lang,
      "هلا بيك 🌟 شلونك اليوم؟ تحب أشوفلك عروض اليوم لو أختارلك مطعم حسب مزاجك؟",
      "Hey 🌟 how are you today? Want today's offers or a mood-based recommendation?"
    );
  } else if (intent.smallTalkType === "thanks") {
    intro = tr(lang, "تدلل 🙏", "You are welcome 🙏");
  } else if (intent.smallTalkType === "chitchat" || intent.offTopicIntent) {
    intro = buildOffTopicSnippet(intent, lang);
  }

  const quickHint = merchants.length
    ? tr(
        lang,
        `أقرب ترشيح عندي هسه: ${merchants[0].merchantName}.`,
        `Best current match: ${merchants[0].merchantName}.`
      )
    : tr(
        lang,
        "من تحدد شتريد أرتبلك الخيارات فوراً.",
        "Once you tell me what you want, I will rank the best options instantly."
      );

  const productHint = products.length > 0
    ? tr(
        lang,
        `مثال سريع: ${products[0].productName} بسعر ${formatIqd(products[0].effectivePrice)}.`,
        `Quick example: ${products[0].productName} at ${formatIqd(products[0].effectivePrice)}.`
      )
    : "";

  const transitionLine = tr(
    lang,
    "إذا تحب نكمل سوالف أكيد، وبمجرد تحب تطلب أنا حاضر.",
    "We can keep chatting, and whenever you want to order I am ready."
  );
  const followQuestion =
    conversationDecision?.mode === "discovery"
      ? pickScenarioQuestion(
          conversationDecision.missingSlot || nextMissingSlot(model) || "cuisine",
          lang,
          `${intent.originalText}|${model.turns}|${model.clarificationTurns}|smalltalk`
        )
      : pickSmartQuestion(intent, profile, lang, model);

  return `${intro} ${quickHint} ${productHint} ${transitionLine} ${followQuestion}`.trim();
}

function summarizeRecentContext(recentMessages, lang) {
  const recentUser = (recentMessages || [])
    .filter((msg) => msg.role === "user" && typeof msg.text === "string")
    .slice(-2)
    .map((msg) => msg.text.trim())
    .filter(Boolean);
  if (!recentUser.length) return null;
  if (recentUser.length === 1) {
    return tr(lang, `آخر طلب: ${recentUser[0]}.`, `Last request: ${recentUser[0]}.`);
  }
  return tr(
    lang,
    `آخر طلبين: ${recentUser[0]} بعدها ${recentUser[1]}.`,
    `Last two requests: ${recentUser[0]}, then ${recentUser[1]}.`
  );
}

function buildRecommendationLines(merchants, intent, lang) {
  return merchants.slice(0, 3).map((merchant, index) => {
    const priceBand = describePriceBand(merchant, lang);
    const etaText = formatEtaText(merchant.avgDeliveryMinutes, lang);
    const feeText = formatDeliveryFeeText(merchant.hasFreeDelivery, lang);
    const reasonText = merchantReason(intent, merchant, lang);
    const topDishes =
      merchant.topProducts && merchant.topProducts.length
        ? merchant.topProducts.slice(0, 2).join(" - ")
        : tr(lang, "غير متوفر حالياً", "not available");

    const header = `${index + 1}) ${merchant.merchantName} - (${mapMerchantTypeLabel(
      merchant.merchantType,
      lang
    )}) - ${priceBand} - ⭐ ${Number(merchant.avgRating || 0).toFixed(1)} (${Number(
      merchant.completedOrders || 0
    )}) - ⏱ ${etaText} - 🚚 ${feeText}`;

    const reasonLine = tr(lang, `- ليش مناسب: ${reasonText}`, `- Why it fits: ${reasonText}`);
    const dishesLine = tr(lang, `- أشهر شي: ${topDishes}`, `- Popular: ${topDishes}`);
    return `${header}\n${reasonLine}\n${dishesLine}`;
  });
}

function extractMerchantNameHint(message) {
  const raw = String(message || "").trim();
  if (!raw) return null;
  const arMatch = raw.match(/(?:مطعم|بمطعم|رأيك\s*(?:ب|في)?|قيم)\s+([^\n\r\.,!\?]+)/u);
  if (arMatch?.[1]) return arMatch[1].trim();
  const enMatch = raw.match(/(?:restaurant)\s+([^\n\r\.,!\?]+)/i);
  if (enMatch?.[1]) return enMatch[1].trim();
  return null;
}

function buildSupportReply(intent, lang) {
  const intro = tr(
    lang,
    "حقك علينا، آسف على الإزعاج 🙏",
    "Sorry about that, and thanks for your patience 🙏"
  );
  if (intent.supportType === "delay") {
    return `${intro} ${tr(
      lang,
      "أقدر أتابع حالة التأخير هسه، ارسل رقم الطلب واسم المطعم.",
      "I can follow up the delay right now. Please send the order number and restaurant name."
    )}`;
  }
  if (intent.supportType === "missing_items") {
    return `${intro} ${tr(
      lang,
      "ممكن تكتب شنو الأصناف الناقصة ورقم الطلب حتى أرفع البلاغ فوراً؟",
      "Please share the missing items and order number so I can open a complaint now."
    )}`;
  }
  if (intent.supportType === "wrong_order") {
    return `${intro} ${tr(
      lang,
      "ممكن توضح شنو الغلط بالطلب ورقمه حتى أعالجه ويا الدعم؟",
      "Please tell me what was wrong in the order and share the order number so I can escalate it."
    )}`;
  }
  return `${intro} ${tr(
    lang,
    "وضحلي باختصار رقم الطلب وشنو المشكلة بالضبط حتى أتابعها إلك.",
    "Please share order number and a short issue description so I can follow it up."
  )}`;
}

function describeCollectedPreferences(model, lang) {
  const slots = model?.slots || {};
  const pieces = [];
  if (slots.cuisine) {
    pieces.push(
      tr(
        lang,
        `نوع الأكل: ${slots.cuisine}`,
        `Cuisine: ${slots.cuisine}`
      )
    );
  }
  if (slots.budgetLevel && slots.budgetLevel !== "unknown") {
    pieces.push(
      tr(
        lang,
        `الميزانية: ${slots.budgetLevel}`,
        `Budget: ${slots.budgetLevel}`
      )
    );
  }
  if (slots.mealType && slots.mealType !== "any") {
    pieces.push(
      tr(
        lang,
        `الوجبة: ${slots.mealType}`,
        `Meal: ${slots.mealType}`
      )
    );
  }
  if (slots.peopleCount != null) {
    pieces.push(
      tr(
        lang,
        `عدد الأشخاص: ${slots.peopleCount}`,
        `People: ${slots.peopleCount}`
      )
    );
  }
  if (!pieces.length) return null;
  return pieces.slice(0, 2).join(tr(lang, " | ", " | "));
}

function buildDiscoveryReply({
  intent,
  profile,
  conversationModel,
  missingSlot,
  lang,
}) {
  const scenario = pickScenarioBlueprint({
    intent: intent.primaryIntent || "BROWSE",
    style: intent.style || profile.personalityStyle || "neutral",
    audience: conversationModel?.slots?.audienceType || intent.audienceType || "unknown",
    meal: conversationModel?.slots?.mealType || intent.mealType || "any",
    priority: deriveConversationPriority(intent, profile),
    seed: `${intent.originalText}|${conversationModel?.turns || 0}`,
  });

  const opener = lang === "en" ? scenario.openerEn : scenario.openerAr;
  const slotFromScenario = Array.isArray(scenario.trackOrder)
    ? scenario.trackOrder.find((key) => key === missingSlot)
    : null;
  const slot = slotFromScenario || missingSlot || "cuisine";
  const question = pickScenarioQuestion(
    slot,
    lang,
    `${intent.originalText}|${conversationModel?.turns || 0}|${conversationModel?.clarificationTurns || 0}`
  );
  const digest = describeCollectedPreferences(conversationModel, lang);
  const phaseLine = tr(
    lang,
    "خليني أفهمك أكثر وبعدين أطلعلك أفضل 3 خيارات مناسبة.",
    "Let me understand you first, then I will rank the best 3 options for you."
  );
  const digestLine = digest
    ? tr(lang, `اللي فهمته لحد الآن: ${digest}.`, `What I got so far: ${digest}.`)
    : "";
  return `${opener} ${phaseLine} ${digestLine} ${question}`.trim();
}

function buildOffersReply({ products, intent, profile, lang }) {
  const offerProducts = products
    .filter((p) => p.offerLabel || (p.discountedPrice != null && p.discountedPrice < p.basePrice))
    .slice(0, 5);

  if (!offerProducts.length) {
    return `${tr(
      lang,
      "حالياً ما عندي عروض مؤكدة ببيانات التطبيق لهذه اللحظة.",
      "I do not have confirmed offer records in the current data right now."
    )} ${pickSmartQuestion(intent, profile, lang)}`;
  }

  const lines = offerProducts.slice(0, 3).map((p, idx) => {
    const offerText = p.offerLabel || tr(lang, "خصم مباشر", "direct discount");
    return `${idx + 1}) ${p.merchantName} - ${p.productName} - ${offerText} - ${formatIqd(
      p.effectivePrice
    )}`;
  });

  return `${tr(
    lang,
    "عروض اليوم حسب بيانات التطبيق:",
    "Today's offers based on available app data:"
  )}\n${lines.join("\n")}\n${pickSmartQuestion(intent, profile, lang)}`;
}

function buildDiscoverReply({ merchants, intent, profile, lang }) {
  const latest = merchants.slice(0, 3);
  if (!latest.length) {
    return `${tr(
      lang,
      "حالياً ما عندي قائمة جاهزة للجديد، بس أقدر أجيبلك أفضل الخيارات إذا تحددلي المنطقة.",
      "I do not have a direct new list right now, but I can fetch best options if you share your area."
    )} ${pickSmartQuestion(intent, profile, lang)}`;
  }

  const lines = latest.map((m, idx) => {
    const eta = formatEtaText(m.avgDeliveryMinutes, lang);
    return `${idx + 1}) ${m.merchantName} - ⭐ ${Number(m.avgRating || 0).toFixed(1)} - ⏱ ${eta}`;
  });

  return `${tr(
    lang,
    "هذني أحدث الخيارات النشطة حالياً:",
    "These are the latest active options right now:"
  )}\n${lines.join("\n")}\n${pickSmartQuestion(intent, profile, lang)}`;
}

function buildEvaluateReply({ intent, merchantCatalog, lang }) {
  const hint = extractMerchantNameHint(intent.originalText);
  if (!hint) {
    return tr(
      lang,
      "اكتب اسم المطعم بالضبط وأنا أقيمه إلك بشفافية.",
      "Share the exact restaurant name and I will evaluate it transparently for you."
    );
  }

  const normalizedHint = normalizeForNlp(hint);
  const found = merchantCatalog.find((m) =>
    normalizeForNlp(m.merchantName).includes(normalizedHint)
  );
  if (!found) {
    return tr(
      lang,
      "ما لقيت هذا المطعم بالبيانات الحالية. تكدر تعيد كتابة الاسم بالضبط؟",
      "I could not find this restaurant in the current data. Can you re-send its exact name?"
    );
  }

  const positives = [
    tr(
      lang,
      `تقييمه ${Number(found.avgRating || 0).toFixed(1)} من 5`,
      `Rating is ${Number(found.avgRating || 0).toFixed(1)} / 5`
    ),
    tr(
      lang,
      `عدد الطلبات المكتملة ${Number(found.completedOrders || 0)}`,
      `Completed orders: ${Number(found.completedOrders || 0)}`
    ),
    tr(
      lang,
      `متوسط التوصيل ${formatEtaText(found.avgDeliveryMinutes, lang)}`,
      `Average delivery: ${formatEtaText(found.avgDeliveryMinutes, lang)}`
    ),
  ];

  const issues = [];
  if (!found.hasFreeDelivery) {
    issues.push(tr(lang, "أجور التوصيل مو مجانية", "Delivery is not free"));
  }
  if (found.avgDeliveryMinutes != null && Number(found.avgDeliveryMinutes) > 45) {
    issues.push(tr(lang, "ممكن يتأخر بالتوصيل عن المعدل", "Delivery can be slower than average"));
  }
  const issueText =
    issues.length > 0
      ? issues.join(tr(lang, "، ", ", "))
      : tr(lang, "ما عندي مشاكل مسجلة عليه حالياً.", "No issue records available right now.");

  return `${tr(lang, `تقييمي لمطعم ${found.merchantName}:`, `My evaluation for ${found.merchantName}:`)}
- ${positives.join("\n- ")}
- ${tr(lang, "ملاحظة", "Note")}: ${issueText}
${tr(
  lang,
  "تحب أطلعلك بديلين بنفس المستوى بس توصيلهم أسرع؟",
  "Do you want two alternatives in similar level but faster delivery?"
)}`;
}

function buildComparisonReply({ merchants, intent, profile, lang }) {
  if (merchants.length < 2) {
    return `${tr(
      lang,
      "ما عندي خيارين كافيين للمقارنة حالياً. خليه علي وأجهزلك أفضل خيار مباشرة.",
      "I do not have two strong options to compare yet. Let me rank the best one directly."
    )} ${pickSmartQuestion(intent, profile, lang)}`;
  }

  const left = merchants[0];
  const right = merchants[1];
  const leftEta = formatEtaText(left.avgDeliveryMinutes, lang);
  const rightEta = formatEtaText(right.avgDeliveryMinutes, lang);
  const leftPrice = describePriceBand(left, lang);
  const rightPrice = describePriceBand(right, lang);

  return `${tr(lang, "مقارنة سريعة:", "Quick comparison:")}
1) ${left.merchantName} - ${tr(lang, "السعر", "price")}: ${leftPrice} - ${tr(
    lang,
    "التوصيل",
    "delivery"
  )}: ${leftEta} - ⭐ ${Number(left.avgRating || 0).toFixed(1)}
2) ${right.merchantName} - ${tr(lang, "السعر", "price")}: ${rightPrice} - ${tr(
    lang,
    "التوصيل",
    "delivery"
  )}: ${rightEta} - ⭐ ${Number(right.avgRating || 0).toFixed(1)}
${pickSmartQuestion(intent, profile, lang)}`;
}

function buildIntentAwareReply({
  intent,
  merchants,
  products,
  draft,
  createdOrder,
  confirmFromDraft,
  profile,
  recentContext,
  merchantCatalog = [],
  conversationModel = null,
  conversationDecision = null,
  lang,
}) {
  if (createdOrder && confirmFromDraft) {
    return tr(
      lang,
      `تم تثبيت الطلب #${createdOrder.id} من ${createdOrder.merchantName} بمبلغ ${formatIqd(
        createdOrder.totalAmount
      )}. تكدر تتابعه من صفحة طلباتي.`,
      `Order #${createdOrder.id} was confirmed from ${createdOrder.merchantName} with total ${formatIqd(
        createdOrder.totalAmount
      )}. You can track it now from My Orders.`
    );
  }

  if (intent.explicitLanguageSwitch) {
    return `${tr(
      lang,
      "تمام، من هسه راح أحچي وياك بالعربي.",
      "Done, I will continue with you in English."
    )} ${pickSmartQuestion(intent, profile, lang)}`;
  }

  if (intent.supportIntent || intent.primaryIntent === "SUPPORT") {
    return buildSupportReply(intent, lang);
  }

  if (intent.offTopicIntent || intent.smallTalkType !== "none") {
    return buildSmallTalkReply({
      intent,
      profile,
      merchants,
      products,
      conversationModel,
      conversationDecision,
      lang,
    });
  }

  if (conversationDecision?.mode === "discovery") {
    return buildDiscoveryReply({
      intent,
      profile,
      conversationModel,
      missingSlot: conversationDecision.missingSlot,
      lang,
    });
  }

  if (intent.primaryIntent === "OFFERS") {
    return buildOffersReply({ products, intent, profile, lang });
  }

  if (intent.primaryIntent === "DISCOVER_NEW") {
    return buildDiscoverReply({
      merchants: merchantCatalog.length ? merchantCatalog : merchants,
      intent,
      profile,
      lang,
    });
  }

  if (intent.primaryIntent === "EVALUATE") {
    return buildEvaluateReply({ intent, merchantCatalog, lang });
  }

  if (intent.comparisonIntent) {
    return buildComparisonReply({ merchants, intent, profile, lang });
  }

  if (draft) {
    const firstItem = draft.items[0];
    const itemText = firstItem
      ? `${firstItem.productName} x${firstItem.quantity}`
      : tr(lang, "أصناف مناسبة", "matched items");
    const contextLine = recentContext ? `${recentContext}\n` : "";
    return `${contextLine}${tr(
      lang,
      `جهزت مسودة طلب من ${draft.merchantName} بمحتوى ${itemText}.`,
      `I prepared a draft from ${draft.merchantName} including ${itemText}.`
    )}\n${pickSmartQuestion(intent, profile, lang)}`;
  }

  if (!products.length || !merchants.length) {
    return `${tr(
      lang,
      "ما حصلت مطابقة قوية هسه. إذا تحددلي النوع أو الميزانية أضبطها بسرعة.",
      "I could not find strong matches yet. I can improve results fast if you set budget or food type."
    )} ${pickSmartQuestion(intent, profile, lang)}`;
  }

  const contextLine = recentContext ? `${recentContext}\n` : "";
  const lines = buildRecommendationLines(merchants, intent, lang);
  const intro = tr(lang, "رتبتلك أفضل 3 خيارات:", "I ranked the top 3 options for your request:");
  const followUp = pickSmartQuestion(intent, profile, lang);
  return `${contextLine}${intro}\n${lines.join("\n")}\n${followUp}`;
}

function buildAssistantReply(args) {
  const lang = args.lang || resolveResponseLanguage(args.intent || {}, args.profile || {});
  const text = buildIntentAwareReply({ ...args, lang });
  const prefix = tonePrefix(args.intent, lang);
  return `${prefix}${text}`.trim();
}

function resolveFinalIntent(intent) {
  if (!intent) return "BROWSE";
  if (intent.primaryIntent && intent.primaryIntent !== "BROWSE") return intent.primaryIntent;
  if (intent.supportIntent) return "SUPPORT";
  if (intent.orderIntent) return "ORDER_DIRECT";
  if (intent.offTopicIntent) return "SMALL_TALK";
  return "BROWSE";
}

function estimateSatisfaction({ intent, draft, createdOrder, merchants, products }) {
  if (createdOrder) return "High";
  if (intent?.supportIntent) return "Medium";
  if (draft) return "High";
  if ((merchants?.length || 0) >= 3 || (products?.length || 0) >= 3) return "High";
  if ((merchants?.length || 0) > 0 || (products?.length || 0) > 0) return "Medium";
  return "Low";
}

function detectUpsellOpportunity({ intent, draft, products, lang }) {
  if (intent?.supportIntent) return tr(lang, "لا يوجد حالياً", "none for now");
  if (draft && Number(draft.totalAmount || 0) < 15000) {
    return tr(
      lang,
      "إضافة مشروب أو حلوى لرفع قيمة السلة",
      "add a drink or dessert to increase basket value"
    );
  }
  if ((products || []).some((p) => p.offerLabel)) {
    return tr(lang, "ترويج منتج عليه عرض", "promote an offer product");
  }
  return tr(lang, "اقتراح منتج تكميلي", "suggest a complementary item");
}

function nextRecommendationStrategy({ intent, profile, merchants, lang }) {
  if (intent?.supportIntent) {
    return tr(
      lang,
      "تحويل المحادثة لمسار دعم + متابعة حالة الطلب",
      "switch to support flow and track order status"
    );
  }
  if (!merchants?.length) {
    return tr(
      lang,
      "جمع تفضيلات أكثر (نوع الأكل + الميزانية + المنطقة)",
      "collect more preferences (food type + budget + area)"
    );
  }
  if (profile?.pricePreference === "cheap" || intent?.wantsCheap) {
    return tr(lang, "التركيز على الأرخص مع تقييم مقبول", "prioritize cheaper options with acceptable rating");
  }
  if (intent?.wantsTopRated || profile?.qualityPriority === "high") {
    return tr(lang, "التركيز على الأعلى تقييماً", "prioritize top-rated options");
  }
  return tr(lang, "موازنة السعر مع سرعة التوصيل", "balance price with delivery speed");
}

function buildConversationSummaryText({ intent, draft, createdOrder, merchants, lang }) {
  const intentCode = resolveFinalIntent(intent);
  if (createdOrder) {
    return tr(
      lang,
      `تم تثبيت طلب مباشر. النية: ${intentCode}.`,
      `Confirmed a direct order. Intent: ${intentCode}.`
    );
  }
  if (draft) {
    return tr(
      lang,
      `تم تجهيز مسودة طلب. النية: ${intentCode}.`,
      `Prepared a draft order. Intent: ${intentCode}.`
    );
  }
  if ((merchants || []).length) {
    return tr(
      lang,
      `تم تقديم ${Math.min(3, merchants.length)} خيارات. النية: ${intentCode}.`,
      `Provided ${Math.min(3, merchants.length)} options. Intent: ${intentCode}.`
    );
  }
  return tr(
    lang,
    `تم طلب معلومات إضافية لإكمال الترشيح. النية: ${intentCode}.`,
    `Asked for more details to complete recommendation. Intent: ${intentCode}.`
  );
}

function enrichProfileAfterConversation(profile, context) {
  const next = {
    ...profile,
    issueHistory: [...(profile.issueHistory || [])],
    satisfactionHistory: [...(profile.satisfactionHistory || [])],
  };

  const hour = new Date().getHours().toString().padStart(2, "0");
  if (context.intent?.orderIntent || context.draft || context.createdOrder) {
    next.commonOrderTime = `${hour}:00`;
  }

  if (context.intent?.supportIntent) {
    next.issueHistory.unshift({
      at: new Date().toISOString(),
      type: context.intent.supportType || "general",
      text: String(context.intent.originalText || "").slice(0, 180),
    });
  }
  next.issueHistory = next.issueHistory.slice(0, 20);

  next.satisfactionHistory.unshift(context.satisfactionEstimate);
  next.satisfactionHistory = next.satisfactionHistory.slice(0, 20);

  const ordersScore =
    Number(next.counters?.ordering || 0) + Number(next.conversation?.confirmedDrafts || 0);
  if (ordersScore >= 20) next.loyaltyLevel = "vip";
  else if (ordersScore >= 8) next.loyaltyLevel = "active";
  else if (ordersScore >= 3) next.loyaltyLevel = "growing";
  else next.loyaltyLevel = "new";

  const signalSize =
    Object.keys(next.tokenSignals || {}).length +
    Object.keys(next.categorySignals || {}).length +
    Object.keys(next.merchantSignals || {}).length;
  if (signalSize >= 80) next.learningConfidence = "high";
  else if (signalSize >= 35) next.learningConfidence = "medium";
  else next.learningConfidence = "low";

  next.lastInteractionSummary = context.summaryText;
  return next;
}

function buildConversationArtifacts({
  intent,
  profile,
  updatedProfile,
  merchants,
  products,
  draft,
  createdOrder,
  summaryText,
  conversationMode = null,
  lang,
}) {
  const finalIntent = resolveFinalIntent(intent);
  const satisfactionEstimate = estimateSatisfaction({
    intent,
    draft,
    createdOrder,
    merchants,
    products,
  });

  const customerProfileUpdate = {
    customer_name: "",
    city: updatedProfile?.city || "",
    area: updatedProfile?.area || "",
    preferred_cuisines: (updatedProfile?.preferredCuisines || []).slice(0, 12),
    budget_level: updatedProfile?.budgetLevel || "unknown",
    speed_priority: updatedProfile?.speedPriority || "balanced",
    quality_priority: updatedProfile?.qualityPriority || "balanced",
    favorite_restaurants: (updatedProfile?.favoriteRestaurants || []).slice(0, 20),
    disliked_restaurants: (updatedProfile?.dislikedRestaurants || []).slice(0, 20),
    dietary_notes: (updatedProfile?.dietaryNotes || []).slice(0, 10),
    common_order_time: updatedProfile?.commonOrderTime || "",
    average_rating_given:
      updatedProfile?.averageRatingGiven == null
        ? ""
        : String(updatedProfile.averageRatingGiven),
    issue_history: (updatedProfile?.issueHistory || []).slice(0, 20),
    personality_style: updatedProfile?.personalityStyle || "neutral",
    loyalty_level: updatedProfile?.loyaltyLevel || "new",
    last_interaction_summary: updatedProfile?.lastInteractionSummary || summaryText,
    learning_confidence: updatedProfile?.learningConfidence || "low",
  };

  const adminSummary = {
    summary: summaryText,
    finalIntent,
    satisfactionEstimate,
    conversationMode: conversationMode || "unknown",
    scenarioLibrarySize: getScenarioLibrarySize(),
    upsellOpportunity: detectUpsellOpportunity({ intent, draft, products, lang }),
    recommendationStrategy: nextRecommendationStrategy({
      intent,
      profile: updatedProfile || profile,
      merchants,
      lang,
    }),
  };

  return { customerProfileUpdate, adminSummary, satisfactionEstimate };
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
    'هلا بيك 🌟 أني مساعد سوقي. أكدر أرتبلك أفضل خيارات الطلب وأجهزلك مسودة جاهزة.'
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

export async function startNewConversation(customerUserId) {
  await repo.expireOldDrafts(customerUserId);
  const session = await repo.createSession(customerUserId);
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
  const learnedProfile = learnFromConfirmedDraft(parseProfile(rawProfile), draft);
  const createdOrderApi = mapOrderForApi(createdOrder);
  const lang = resolveResponseLanguage(
    { inferredLanguage: learnedProfile.languagePreference || "ar" },
    learnedProfile
  );

  const assistantText = buildAssistantReply({
    intent: { offTopicIntent: false, smallTalkType: "none", categoryHints: [] },
    merchants: [],
    products: [],
    draft: null,
    createdOrder: createdOrderApi,
    confirmFromDraft: true,
    profile: learnedProfile,
    recentContext: null,
    lang,
  });

  const summaryText = buildConversationSummaryText({
    intent: { primaryIntent: "ORDER_DIRECT", orderIntent: true },
    draft: null,
    createdOrder: createdOrderApi,
    merchants: [],
    lang,
  });

  const updatedProfile = enrichProfileAfterConversation(learnedProfile, {
    intent: { primaryIntent: "ORDER_DIRECT", orderIntent: true },
    draft: null,
    createdOrder: createdOrderApi,
    satisfactionEstimate: "High",
    summaryText,
  });
  updatedProfile.conversationModel = normalizeConversationModel(updatedProfile.conversationModel);
  updatedProfile.conversationModel.phase = "checkout";
  updatedProfile.conversationModel.recommendationTurns += 1;

  const artifacts = buildConversationArtifacts({
    intent: { primaryIntent: "ORDER_DIRECT", orderIntent: true },
    profile: learnedProfile,
    updatedProfile,
    merchants: [],
    products: [],
    draft: null,
    createdOrder: createdOrderApi,
    summaryText,
    conversationMode: "checkout",
    lang,
  });

  await repo.upsertProfile(
    customerUserId,
    updatedProfile,
    artifacts.adminSummary.summary
  );

  const assistantMessage = await repo.insertMessage(session.id, "assistant", assistantText, {
    type: "draft_confirmed",
    draftToken: draft.token,
    orderId: createdOrder.id,
    scenarioLibrarySize: getScenarioLibrarySize(),
    language: lang,
    CUSTOMER_PROFILE_UPDATE: artifacts.customerProfileUpdate,
    ADMIN_SUMMARY: artifacts.adminSummary,
  });

  const payload = await buildSessionPayload(customerUserId, session.id, updatedProfile);
  return {
    ...payload,
    assistantMessage,
    suggestions: { merchants: [], products: [] },
    createdOrder: createdOrderApi,
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

    const rawProfile = await repo.getProfile(customerUserId);
    const profile = parseProfile(rawProfile);
    const lang = resolveResponseLanguage(intent, profile);
    const cancelText = tr(
      lang,
      "تم إلغاء المسودة ✅ إذا تريد، أرتبلك خيارات جديدة الآن حسب مزاجك وميزانيتك.",
      "Draft cancelled ✅ I can prepare fresh options now based on your mood and budget."
    );
    const summaryText = buildConversationSummaryText({
      intent: { primaryIntent: "BROWSE" },
      draft: null,
      createdOrder: null,
      merchants: [],
      lang,
    });
    const preArtifactsSatisfaction = "Medium";
    const updatedProfile = enrichProfileAfterConversation(profile, {
      intent: { primaryIntent: "BROWSE" },
      draft: null,
      createdOrder: null,
      satisfactionEstimate: preArtifactsSatisfaction,
      summaryText,
    });
    updatedProfile.conversationModel = normalizeConversationModel(updatedProfile.conversationModel);
    updatedProfile.conversationModel.phase = "discovery";
    const artifacts = buildConversationArtifacts({
      intent: { primaryIntent: "BROWSE" },
      profile,
      updatedProfile,
      merchants: [],
      products: [],
      draft: null,
      createdOrder: null,
      summaryText,
      conversationMode: "discovery",
      lang,
    });
    await repo.upsertProfile(customerUserId, updatedProfile, artifacts.adminSummary.summary);

    const cancelMessage = await repo.insertMessage(session.id, "assistant", cancelText, {
      type: "draft_cancelled",
      scenarioLibrarySize: getScenarioLibrarySize(),
      language: lang,
      CUSTOMER_PROFILE_UPDATE: artifacts.customerProfileUpdate,
      ADMIN_SUMMARY: artifacts.adminSummary,
    });

    const payload = await buildSessionPayload(customerUserId, session.id, updatedProfile);
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
  profile.conversationModel = mergeConversationModel(profile, intent);
  const conversationDecision = decideConversationMode({
    intent,
    model: profile.conversationModel,
  });
  const lang = resolveResponseLanguage(intent, profile);

  const historyWeights = buildHistoryWeights(historySignals, globalSignals);
  const ranked = rankProducts({
    pool,
    intent,
    profile,
    historyWeights,
  });
  const recentContext = summarizeRecentContext(recentMessages, lang);

  const merchantSuggestions = buildMerchantSuggestions(ranked);
  const productSuggestions = buildProductSuggestions(ranked);

  let createdDraft = null;
  const hasEnoughOrderSignals =
    intent.categoryHints.length > 0 ||
    intent.budgetIqd != null ||
    intent.peopleCount != null ||
    intent.mealType !== "any" ||
    intent.spiceLevel !== "unknown" ||
    intent.tokens.length >= 3;
  const shouldDraft =
    (dto.createDraft === true || (intent.orderIntent && hasEnoughOrderSignals)) &&
    !intent.offTopicIntent &&
    conversationDecision.mode === "recommendation";
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

  const canRecommendNow =
    conversationDecision.mode === "recommendation" ||
    (conversationDecision.mode === "specialized" && !intent.supportIntent);
  const visibleMerchants = canRecommendNow ? merchantSuggestions : [];
  const visibleProducts = canRecommendNow ? productSuggestions : [];
  if (conversationDecision.mode === "discovery") {
    profile.conversationModel.phase = "understanding";
    profile.conversationModel.clarificationTurns += 1;
    profile.conversationModel.lastQuestionSlot = conversationDecision.missingSlot || null;
    profile.conversationModel.lastQuestionAt = new Date().toISOString();
  } else if (conversationDecision.mode === "specialized") {
    profile.conversationModel.phase = intent.supportIntent ? "support" : "recommendation";
    profile.conversationModel.recommendationTurns += 1;
  } else {
    profile.conversationModel.phase = "recommendation";
    profile.conversationModel.recommendationTurns += 1;
  }

  const assistantText = buildAssistantReply({
    intent,
    merchants: visibleMerchants,
    products: visibleProducts,
    draft: createdDraft,
    createdOrder: null,
    confirmFromDraft: false,
    profile,
    recentContext,
    merchantCatalog: merchantSuggestions,
    conversationModel: profile.conversationModel,
    conversationDecision,
    lang,
  });

  const summaryText = buildConversationSummaryText({
    intent,
    draft: createdDraft,
    createdOrder: null,
    merchants: visibleMerchants,
    lang,
  });

  const preArtifactsSatisfaction = estimateSatisfaction({
    intent,
    draft: createdDraft,
    createdOrder: null,
    merchants: visibleMerchants,
    products: visibleProducts,
  });

  const updatedProfile = enrichProfileAfterConversation(profile, {
    intent,
    draft: createdDraft,
    createdOrder: null,
    satisfactionEstimate: preArtifactsSatisfaction,
    summaryText,
  });

  const artifacts = buildConversationArtifacts({
    intent,
    profile,
    updatedProfile,
    merchants: visibleMerchants,
    products: visibleProducts,
    draft: createdDraft,
    createdOrder: null,
    summaryText,
    conversationMode: conversationDecision.mode,
    lang,
  });

  await repo.upsertProfile(
    customerUserId,
    updatedProfile,
    artifacts.adminSummary.summary
  );

  const assistantMessage = await repo.insertMessage(session.id, "assistant", assistantText, {
    type:
      conversationDecision.mode === "discovery"
        ? "discovery"
        : createdDraft
        ? "draft_created"
        : "recommendation",
    draftToken: createdDraft?.token || null,
    merchantsCount: visibleMerchants.length,
    productsCount: visibleProducts.length,
    conversationPhase: profile.conversationModel?.phase || "discovery",
    conversationMode: conversationDecision.mode,
    scenarioLibrarySize: getScenarioLibrarySize(),
    language: lang,
    CUSTOMER_PROFILE_UPDATE: artifacts.customerProfileUpdate,
    ADMIN_SUMMARY: artifacts.adminSummary,
  });

  const payload = await buildSessionPayload(customerUserId, session.id, updatedProfile);

  return {
    ...payload,
    assistantMessage,
    suggestions: {
      merchants: visibleMerchants,
      products: visibleProducts,
    },
    createdOrder: null,
  };
}



import crypto from "crypto";

import { q } from "../../config/db.js";
import { aiQ, isAiDbConfigured } from "../../config/aiDb.js";
import { getRedisClient } from "../../config/redis.js";
import { AppError } from "../../shared/utils/errors.js";
import {
  createManyNotifications,
  getPushConfigStatus,
} from "../notifications/notifications.repo.js";
import * as assistantRepo from "./assistant.repo.js";
import * as aiRepo from "./assistant.ai.repo.js";

const OPENAI_ENABLED = readBooleanEnv("OPENAI_ENABLED", true);
const OPENAI_API_KEY = String(process.env.OPENAI_API_KEY || "").trim();
const OPENAI_BASE_URL = String(process.env.OPENAI_BASE_URL || "https://api.openai.com/v1")
  .trim()
  .replace(/\/+$/, "");
const OPENAI_MODEL = String(process.env.OPENAI_MODEL || "gpt-4.1-mini").trim();
const OPENAI_FALLBACK_MODEL = String(
  process.env.OPENAI_FALLBACK_MODEL || "gpt-4o-mini"
).trim();
const OPENAI_RETRIES = clampInt(process.env.OPENAI_RETRIES, 0, 3, 1);
const OPENAI_TIMEOUT_MS = clampInt(process.env.OPENAI_TIMEOUT_MS, 3000, 25000, 10000);
const OPENAI_EMBEDDING_MODEL = String(
  process.env.OPENAI_EMBEDDING_MODEL || "text-embedding-3-small"
).trim();

const AI_RECOMMENDATION_LIMIT = 12;
const AI_POST_SCAN_BATCH_LIMIT = 120;
const AI_MODEL_TAG = "openai";
const AI_LEARNING_VERSION = "v2.0";
const AI_LEARNING_DEEP_PARSE_ENABLED = readBooleanEnv(
  "AI_LEARNING_DEEP_PARSE_ENABLED",
  true
);
const AI_WEB_RESEARCH_ENABLED = readBooleanEnv("AI_WEB_RESEARCH_ENABLED", true);
const AI_WEB_RESEARCH_PROVIDER = String(
  process.env.AI_WEB_RESEARCH_PROVIDER || "serpapi_google"
)
  .trim()
  .toLowerCase();
const AI_WEB_RESEARCH_TIMEOUT_MS = clampInt(
  process.env.AI_WEB_RESEARCH_TIMEOUT_MS,
  3000,
  30000,
  12000
);
const AI_WEB_SEARCH_LIMIT = clampInt(process.env.AI_WEB_SEARCH_LIMIT, 1, 12, 5);
const SERPAPI_API_KEY = String(process.env.SERPAPI_API_KEY || "").trim();
const AI_WEB_AUTO_LEARN_ENABLED = readBooleanEnv("AI_WEB_AUTO_LEARN_ENABLED", false);
const AI_WEB_AUTO_LEARN_MAX_QUERIES = clampInt(
  process.env.AI_WEB_AUTO_LEARN_MAX_QUERIES,
  1,
  100,
  8
);
const AI_IDLE_LEARNING_INTERVAL_SEC = clampInt(
  process.env.AI_IDLE_LEARNING_INTERVAL_SEC,
  60,
  86400,
  900
);
const AI_IDLE_LEARNING_IDLE_WINDOW_MIN = clampInt(
  process.env.AI_IDLE_LEARNING_IDLE_WINDOW_MIN,
  1,
  360,
  15
);
let idleLearningTimer = null;
let dailyLearningTimer = null;
const AI_DAILY_LEARNING_ENABLED = readBooleanEnv("AI_DAILY_LEARNING_ENABLED", true);
const AI_DAILY_LEARNING_HOUR_BAGHDAD = clampInt(
  process.env.AI_DAILY_LEARNING_HOUR_BAGHDAD,
  0,
  23,
  4
);
const AI_DAILY_LEARNING_TICK_SEC = clampInt(
  process.env.AI_DAILY_LEARNING_TICK_SEC,
  60,
  3600,
  600
);
const AI_DAILY_LEARNING_LOCK_KEY = clampInt(
  process.env.AI_DAILY_LEARNING_LOCK_KEY,
  1,
  2147483647,
  719244389
);
const AI_DAILY_LEARNING_MAX_QUERIES = clampInt(
  process.env.AI_DAILY_LEARNING_MAX_QUERIES,
  1,
  50,
  12
);
const AI_DAILY_LEARNING_SYNTHETIC_CONVERSATIONS = clampInt(
  process.env.AI_DAILY_LEARNING_SYNTHETIC_CONVERSATIONS,
  0,
  10000,
  500
);
const AI_DAILY_LEARNING_SYNTHETIC_TURNS = clampInt(
  process.env.AI_DAILY_LEARNING_SYNTHETIC_TURNS,
  10,
  200,
  100
);
const AI_DAILY_SYNTHETIC_MAX_ROWS = clampInt(
  process.env.AI_DAILY_SYNTHETIC_MAX_ROWS,
  0,
  20000,
  1500
);
const AI_DAILY_MEMORY_PRUNE_ENABLED = readBooleanEnv(
  "AI_DAILY_MEMORY_PRUNE_ENABLED",
  true
);
const AI_DAILY_MEMORY_MAX_ROWS = clampInt(
  process.env.AI_DAILY_MEMORY_MAX_ROWS,
  10000,
  5000000,
  300000
);
const AI_DAILY_MEMORY_PRUNE_BATCH = clampInt(
  process.env.AI_DAILY_MEMORY_PRUNE_BATCH,
  500,
  50000,
  4000
);
const AI_REDIS_RECENT_OBSERVATIONS_LIMIT = clampInt(
  process.env.AI_REDIS_RECENT_OBSERVATIONS_LIMIT,
  20,
  2000,
  500
);
const AI_REDIS_STREAM_OBSERVATIONS_KEY = String(
  process.env.AI_REDIS_STREAM_OBSERVATIONS_KEY || "ai:stream:chat_observations"
).trim();
const AI_REDIS_STREAM_DAILY_CYCLES_KEY = String(
  process.env.AI_REDIS_STREAM_DAILY_CYCLES_KEY || "ai:stream:daily_cycles"
).trim();
const AI_REDIS_STREAM_MAXLEN = clampInt(
  process.env.AI_REDIS_STREAM_MAXLEN,
  500,
  500000,
  20000
);
const AI_REDIS_USER_WINDOW_TTL_SEC = clampInt(
  process.env.AI_REDIS_USER_WINDOW_TTL_SEC,
  300,
  2592000,
  604800
);
const AI_REDIS_USER_RECENT_TURNS_LIMIT = clampInt(
  process.env.AI_REDIS_USER_RECENT_TURNS_LIMIT,
  5,
  300,
  40
);
const AI_MEMORY_CONSENT_DEFAULT = Object.freeze({
  memoryEnabled: true,
  profileStorage: true,
  personalization: true,
  adminReview: true,
  improveModel: true,
});
const AI_MEMORY_CONSENT_KEYS = Object.freeze([
  "memoryEnabled",
  "profileStorage",
  "personalization",
  "adminReview",
  "improveModel",
]);
const AI_MEMORY_CONVERSATION_SUMMARY_MAXLEN = clampInt(
  process.env.AI_MEMORY_CONVERSATION_SUMMARY_MAXLEN,
  300,
  8000,
  1800
);
const AI_MEMORY_CAPTURE_RAW_MESSAGES = readBooleanEnv(
  "AI_MEMORY_CAPTURE_RAW_MESSAGES",
  true
);
const AI_KNOWLEDGE_LEXICAL_LIMIT = clampInt(
  process.env.AI_KNOWLEDGE_LEXICAL_LIMIT,
  2,
  80,
  18
);
const AI_KNOWLEDGE_SEMANTIC_ENABLED = readBooleanEnv(
  "AI_KNOWLEDGE_SEMANTIC_ENABLED",
  true
);
const AI_KNOWLEDGE_SEMANTIC_CANDIDATES = clampInt(
  process.env.AI_KNOWLEDGE_SEMANTIC_CANDIDATES,
  20,
  2000,
  320
);
const AI_KNOWLEDGE_SIMILARITY_THRESHOLD = clampFloat(
  process.env.AI_KNOWLEDGE_SIMILARITY_THRESHOLD,
  0.35,
  0.98,
  0.62
);

function clampInt(value, min, max, fallback) {
  const n = Number(value);
  if (!Number.isInteger(n)) return fallback;
  if (n < min) return min;
  if (n > max) return max;
  return n;
}

function clampFloat(value, min, max, fallback) {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  if (n < min) return min;
  if (n > max) return max;
  return n;
}

function readBooleanEnv(name, fallback = false) {
  const raw = String(process.env[name] || "").trim().toLowerCase();
  if (!raw) return fallback;
  if (["1", "true", "yes", "on"].includes(raw)) return true;
  if (["0", "false", "no", "off"].includes(raw)) return false;
  return fallback;
}

function safeText(value, max = 2000) {
  const text = String(value || "").trim();
  if (!text) return null;
  return text.slice(0, max);
}

function parseJsonSafe(value, fallback = null) {
  if (value == null) return fallback;
  if (typeof value === "object") return value;
  try {
    return JSON.parse(String(value));
  } catch (_) {
    return fallback;
  }
}

function normalizeConsentFlags(input) {
  const source = input && typeof input === "object" ? input : {};
  return {
    memoryEnabled: asBool(source.memoryEnabled, AI_MEMORY_CONSENT_DEFAULT.memoryEnabled),
    profileStorage: asBool(source.profileStorage, AI_MEMORY_CONSENT_DEFAULT.profileStorage),
    personalization: asBool(source.personalization, AI_MEMORY_CONSENT_DEFAULT.personalization),
    adminReview: asBool(source.adminReview, AI_MEMORY_CONSENT_DEFAULT.adminReview),
    improveModel: asBool(source.improveModel, AI_MEMORY_CONSENT_DEFAULT.improveModel),
  };
}

function buildConsentFlagsFromGranted(granted) {
  const value = granted === true;
  return {
    memoryEnabled: value,
    profileStorage: value,
    personalization: value,
    adminReview: value,
    improveModel: value,
  };
}

function consentFlagsNeedSync(currentFlags, expectedFlags) {
  const current = normalizeConsentFlags(currentFlags);
  const expected = normalizeConsentFlags(expectedFlags);
  return AI_MEMORY_CONSENT_KEYS.some((key) => current[key] !== expected[key]);
}

async function resolveDefaultConsentFlagsForUser(customerUserId) {
  const consentState = await aiRepo.getAppUserAiConsentState(customerUserId);
  const hasAiConsent = asBool(
    consentState?.ai_chat_review_consent,
    asBool(
      consentState?.chat_quality_review_consent,
      asBool(consentState?.analytics_consent_granted, true)
    )
  );
  return buildConsentFlagsFromGranted(hasAiConsent);
}

function asBool(value, fallback = false) {
  if (typeof value === "boolean") return value;
  if (value == null) return fallback;
  const normalized = String(value).trim().toLowerCase();
  if (["1", "true", "yes", "on"].includes(normalized)) return true;
  if (["0", "false", "no", "off"].includes(normalized)) return false;
  return fallback;
}

function normalizeTextList(values, { maxItems = 80, maxLen = 120 } = {}) {
  if (!Array.isArray(values)) return [];
  const out = [];
  for (const item of values) {
    const safe = safeText(item, maxLen);
    if (!safe) continue;
    if (!out.includes(safe)) out.push(safe);
    if (out.length >= maxItems) break;
  }
  return out;
}

function detectArabicText(text) {
  return /[\u0600-\u06ff]/.test(String(text || ""));
}

function inferDialectFromMessage(text, language = null) {
  const normalizedLanguage = String(language || "").trim().toLowerCase();
  if (normalizedLanguage === "en") return "en";
  const raw = String(text || "").toLowerCase();
  if (!detectArabicText(raw)) return normalizedLanguage || "ar";
  const iraqiHints = [
    "شلون",
    "هسه",
    "شكد",
    "مو",
    "هيج",
    "اني",
    "أريد",
    "اريد",
    "هاي",
    "شنو",
    "كول",
  ];
  return iraqiHints.some((hint) => raw.includes(hint)) ? "iraqi" : "ar";
}

function extractUserNamesFromMessage(text) {
  const source = String(text || "").trim();
  if (!source) return { realName: null, nickname: null };
  const normalized = source.replace(/\s+/g, " ").trim();
  const namePatterns = [
    /(?:اسمي|اني اسمي|أنا اسمي|my name is)\s+([^\n\r,.!?]{2,80})/iu,
    /(?:ناديني|سمّني|سمني|call me)\s+([^\n\r,.!?]{2,80})/iu,
  ];
  let realName = null;
  let nickname = null;
  for (const pattern of namePatterns) {
    const match = normalized.match(pattern);
    if (!match?.[1]) continue;
    const captured = safeText(match[1], 80);
    if (!captured) continue;
    if (pattern.source.includes("ناديني") || pattern.source.includes("call me")) {
      nickname = captured;
    } else {
      realName = captured;
    }
  }
  return { realName, nickname };
}

function conversationTitleFromText(text, lang = "ar") {
  const clean = safeText(text, 120);
  if (!clean) {
    return lang === "en" ? "Open Conversation" : "محادثة مفتوحة";
  }
  return clean;
}

async function withRedisSafe(fn) {
  try {
    const client = await getRedisClient();
    if (!client) return null;
    return await fn(client);
  } catch (_) {
    return null;
  }
}

function safeIsoNow() {
  return new Date().toISOString();
}

function normalizeRedisCounterHash(input = {}) {
  if (!input || typeof input !== "object") return {};
  const out = {};
  Object.entries(input).forEach(([key, value]) => {
    const safeKey = safeText(key, 80);
    const asNumber = Number(value);
    if (!safeKey || !Number.isFinite(asNumber) || asNumber <= 0) return;
    out[safeKey] = Math.round(asNumber);
  });
  return out;
}

function topCounterKeys(hash = {}, limit = 5) {
  return Object.entries(hash || {})
    .sort((a, b) => Number(b[1] || 0) - Number(a[1] || 0))
    .slice(0, Math.max(1, limit))
    .map(([key]) => String(key));
}

function parseRedisJsonRows(rows = []) {
  if (!Array.isArray(rows)) return [];
  return rows
    .map((row) => parseJsonSafe(row, null))
    .filter((row) => row && typeof row === "object");
}

async function getRedisAdaptiveLearningSnapshot({
  customerUserId,
  recentLimit = 4,
}) {
  const safeUserId = Number(customerUserId);
  if (!Number.isInteger(safeUserId) || safeUserId <= 0) {
    return null;
  }

  return withRedisSafe(async (redis) => {
    const userPrefix = `ai:user:${safeUserId}`;
    const replies = await redis
      .multi()
      .hgetall(`${userPrefix}:window`)
      .hgetall(`${userPrefix}:intent_count`)
      .hgetall(`${userPrefix}:topic_count`)
      .lrange(`${userPrefix}:recent_turns`, 0, Math.max(0, recentLimit - 1))
      .exec();

    if (!Array.isArray(replies) || replies.length < 4) return null;
    const windowHash = replies[0]?.[1] || {};
    const intentHash = normalizeRedisCounterHash(replies[1]?.[1] || {});
    const topicHash = normalizeRedisCounterHash(replies[2]?.[1] || {});
    const recentTurns = parseRedisJsonRows(replies[3]?.[1] || []);

    const intentTop = topCounterKeys(intentHash, 3);
    const topicTop = topCounterKeys(topicHash, 4);
    const lang = safeText(windowHash.last_language, 24);
    const mode = safeText(windowHash.last_mode, 24);

    const profileParts = [
      intentTop.length ? `intent=${intentTop.join(",")}` : null,
      topicTop.length ? `topic=${topicTop.join(",")}` : null,
      lang ? `lang=${lang}` : null,
      mode ? `mode=${mode}` : null,
    ].filter(Boolean);

    const snippets = recentTurns
      .slice(0, 3)
      .map((turn) => {
        const intent = safeText(turn.intent, 50) || "unknown";
        const msg = safeText(turn.userMessage, 120) || "";
        const reply = safeText(turn.assistantReply, 120) || "";
        if (!msg && !reply) return null;
        return `turn(${intent}): ${msg || reply}`;
      })
      .filter(Boolean);

    const line = [
      profileParts.length ? `redis_profile(${profileParts.join(" | ")})` : null,
      snippets.length ? `redis_recent(${snippets.join(" | ")})` : null,
    ]
      .filter(Boolean)
      .join(" ; ");

    return {
      profileParts,
      snippets,
      line: line || null,
      intentCounter: intentHash,
      topicCounter: topicHash,
      recentTurns,
    };
  });
}

async function getRedisMachineLearningSnapshot({ recentLimit = 12 } = {}) {
  return (
    (await withRedisSafe(async (redis) => {
      const safeRecentLimit = clampInt(recentLimit, 3, 80, 12);
      const replies = await redis
        .multi()
        .dbsize()
        .get("ai:metrics:observations_total")
        .hgetall("ai:metrics:intent_count")
        .hgetall("ai:metrics:language_count")
        .hgetall("ai:metrics:mode_count")
        .hgetall("ai:metrics:last")
        .hgetall("ai:daily:last_cycle")
        .llen("ai:recent:observations")
        .lrange("ai:recent:observations", 0, safeRecentLimit - 1)
        .xlen(AI_REDIS_STREAM_OBSERVATIONS_KEY)
        .xlen(AI_REDIS_STREAM_DAILY_CYCLES_KEY)
        .exec();

      if (!Array.isArray(replies) || replies.length < 11) {
        return { available: false, reason: "MULTI_EXEC_FAILED" };
      }

      const dbSize = Number(replies[0]?.[1] || 0);
      const observationsTotal = Number(replies[1]?.[1] || 0);
      const intentCount = normalizeRedisCounterHash(replies[2]?.[1] || {});
      const languageCount = normalizeRedisCounterHash(replies[3]?.[1] || {});
      const modeCount = normalizeRedisCounterHash(replies[4]?.[1] || {});
      const lastMetrics = replies[5]?.[1] || {};
      const lastDailyCycle = replies[6]?.[1] || {};
      const recentLength = Number(replies[7]?.[1] || 0);
      const recentRows = parseRedisJsonRows(replies[8]?.[1] || []);
      const streamObservationsLength = Number(replies[9]?.[1] || 0);
      const streamDailyLength = Number(replies[10]?.[1] || 0);

      return {
        available: true,
        dbSize,
        observationsTotal,
        intentCount,
        languageCount,
        modeCount,
        topIntents: topCounterKeys(intentCount, 8),
        topLanguages: topCounterKeys(languageCount, 5),
        topModes: topCounterKeys(modeCount, 5),
        lastMetrics,
        lastDailyCycle,
        recentLength,
        recentRows,
        streamStats: {
          observationsKey: AI_REDIS_STREAM_OBSERVATIONS_KEY,
          dailyCyclesKey: AI_REDIS_STREAM_DAILY_CYCLES_KEY,
          observationsLength: streamObservationsLength,
          dailyCyclesLength: streamDailyLength,
          maxLen: AI_REDIS_STREAM_MAXLEN,
        },
      };
    })) || { available: false, reason: "REDIS_UNAVAILABLE" }
  );
}

async function recordRedisObservationSnapshot({
  observationId,
  customerUserId,
  detectedIntent,
  qualityScore,
  responseQuality,
  language,
  conversationMode,
  extractedTopics = [],
  userMessage = null,
  assistantReply = null,
}) {
  await withRedisSafe(async (redis) => {
    const intentKey = safeText(detectedIntent, 64) || "unknown";
    const langKey = safeText(language, 32) || "unknown";
    const modeKey = safeText(conversationMode, 32) || "default";
    const score = Number.isFinite(Number(qualityScore)) ? Number(qualityScore) : 0;
    const replyScore = Number.isFinite(Number(responseQuality))
      ? Number(responseQuality)
      : 0;
    const payload = {
      observationId: Number(observationId) || null,
      customerUserId: Number(customerUserId) || null,
      intent: intentKey,
      language: langKey,
      mode: modeKey,
      qualityScore: score,
      responseQuality: replyScore,
      extractedTopics: Array.isArray(extractedTopics)
        ? extractedTopics.map((topic) => safeText(topic, 64)).filter(Boolean).slice(0, 10)
        : [],
      userMessage: safeText(userMessage, 260),
      assistantReply: safeText(assistantReply, 260),
      createdAt: safeIsoNow(),
    };
    const multi = redis.multi();
    multi.incr("ai:metrics:observations_total");
    multi.hincrby("ai:metrics:intent_count", intentKey, 1);
    multi.hincrby("ai:metrics:language_count", langKey, 1);
    multi.hincrby("ai:metrics:mode_count", modeKey, 1);
    multi.hset("ai:metrics:last", {
      last_observation_id: String(payload.observationId || ""),
      last_customer_user_id: String(payload.customerUserId || ""),
      last_intent: intentKey,
      last_language: langKey,
      last_mode: modeKey,
      last_quality_score: String(score),
      last_response_quality: String(replyScore),
      last_observation_at: payload.createdAt,
    });
    multi.lpush("ai:recent:observations", JSON.stringify(payload));
    multi.ltrim(
      "ai:recent:observations",
      0,
      AI_REDIS_RECENT_OBSERVATIONS_LIMIT - 1
    );
    multi.xadd(
      AI_REDIS_STREAM_OBSERVATIONS_KEY,
      "MAXLEN",
      "~",
      String(AI_REDIS_STREAM_MAXLEN),
      "*",
      "observation_id",
      String(payload.observationId || ""),
      "user_id",
      String(payload.customerUserId || ""),
      "intent",
      intentKey,
      "language",
      langKey,
      "mode",
      modeKey,
      "quality_score",
      String(score),
      "response_quality",
      String(replyScore),
      "created_at",
      payload.createdAt
    );

    if (Number(payload.customerUserId) > 0) {
      const userPrefix = `ai:user:${Number(payload.customerUserId)}`;
      multi.hset(`${userPrefix}:window`, {
        last_observation_id: String(payload.observationId || ""),
        last_intent: intentKey,
        last_language: langKey,
        last_mode: modeKey,
        last_quality_score: String(score),
        last_response_quality: String(replyScore),
        last_seen_at: payload.createdAt,
      });
      multi.hincrby(`${userPrefix}:intent_count`, intentKey, 1);
      for (const topic of payload.extractedTopics) {
        const key = safeText(topic, 64);
        if (!key) continue;
        multi.hincrby(`${userPrefix}:topic_count`, key, 1);
      }
      multi.lpush(
        `${userPrefix}:recent_turns`,
        JSON.stringify({
          observationId: payload.observationId,
          intent: intentKey,
          language: langKey,
          mode: modeKey,
          userMessage: payload.userMessage,
          assistantReply: payload.assistantReply,
          createdAt: payload.createdAt,
        })
      );
      multi.ltrim(
        `${userPrefix}:recent_turns`,
        0,
        AI_REDIS_USER_RECENT_TURNS_LIMIT - 1
      );
      multi.expire(`${userPrefix}:window`, AI_REDIS_USER_WINDOW_TTL_SEC);
      multi.expire(`${userPrefix}:intent_count`, AI_REDIS_USER_WINDOW_TTL_SEC);
      multi.expire(`${userPrefix}:topic_count`, AI_REDIS_USER_WINDOW_TTL_SEC);
      multi.expire(`${userPrefix}:recent_turns`, AI_REDIS_USER_WINDOW_TTL_SEC);
    }
    await multi.exec();
  });
}

async function recordRedisDailyCycleSnapshot({
  runId,
  cycleDate,
  scannedQueries,
  insertedMemories,
  status = "success",
}) {
  await withRedisSafe(async (redis) => {
    const nowIso = safeIsoNow();
    const payload = {
      runId: Number(runId) || null,
      cycleDate: safeText(cycleDate, 16) || null,
      scannedQueries: Number(scannedQueries) || 0,
      insertedMemories: Number(insertedMemories) || 0,
      status: safeText(status, 16) || "success",
      finishedAt: nowIso,
    };
    const multi = redis.multi();
    multi.hset("ai:daily:last_cycle", {
      run_id: String(payload.runId || ""),
      cycle_date: payload.cycleDate || "",
      scanned_queries: String(payload.scannedQueries),
      inserted_memories: String(payload.insertedMemories),
      status: payload.status,
      finished_at: nowIso,
    });
    multi.lpush("ai:daily:history", JSON.stringify(payload));
    multi.ltrim("ai:daily:history", 0, 119);
    multi.incrby("ai:metrics:daily_inserted_total", payload.insertedMemories);
    multi.xadd(
      AI_REDIS_STREAM_DAILY_CYCLES_KEY,
      "MAXLEN",
      "~",
      String(AI_REDIS_STREAM_MAXLEN),
      "*",
      "run_id",
      String(payload.runId || ""),
      "cycle_date",
      payload.cycleDate || "",
      "scanned_queries",
      String(payload.scannedQueries),
      "inserted_memories",
      String(payload.insertedMemories),
      "status",
      payload.status,
      "finished_at",
      nowIso
    );
    await multi.exec();
  });
}

async function qAi(text, params) {
  if (isAiDbConfigured()) {
    return aiQ(text, params);
  }
  return q(text, params);
}

function parseFirstJsonObject(text) {
  const raw = String(text || "").trim();
  if (!raw) return null;
  const direct = parseJsonSafe(raw, null);
  if (direct && typeof direct === "object") return direct;

  const first = raw.indexOf("{");
  const last = raw.lastIndexOf("}");
  if (first < 0 || last <= first) return null;
  const clipped = raw.slice(first, last + 1);
  return parseJsonSafe(clipped, null);
}

function openAiReady() {
  return OPENAI_ENABLED && OPENAI_API_KEY.length > 0;
}

function modelsInOrder() {
  const list = [OPENAI_MODEL];
  if (OPENAI_FALLBACK_MODEL && OPENAI_FALLBACK_MODEL !== OPENAI_MODEL) {
    list.push(OPENAI_FALLBACK_MODEL);
  }
  return list;
}

async function callOpenAiJson({
  systemPrompt,
  userPayload,
  temperature = 0.2,
  maxTokens = 900,
}) {
  if (!openAiReady()) {
    return { ok: false, reason: "OPENAI_NOT_CONFIGURED" };
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), OPENAI_TIMEOUT_MS);
  try {
    const baseMessages = [
      { role: "system", content: String(systemPrompt || "").trim() || "Return valid JSON only." },
      {
        role: "user",
        content: JSON.stringify(userPayload || {}),
      },
    ];

    for (let attempt = 0; attempt <= OPENAI_RETRIES; attempt += 1) {
      for (const model of modelsInOrder()) {
        try {
          const response = await fetch(`${OPENAI_BASE_URL}/chat/completions`, {
            method: "POST",
            headers: {
              Authorization: `Bearer ${OPENAI_API_KEY}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              model,
              temperature: clampFloat(temperature, 0, 1.2, 0.2),
              max_tokens: clampInt(maxTokens, 128, 2000, 900),
              response_format: { type: "json_object" },
              messages: baseMessages,
            }),
            signal: controller.signal,
          });
          if (!response.ok) {
            continue;
          }
          const out = await response.json();
          const content = String(out?.choices?.[0]?.message?.content || "").trim();
          const parsed = parseFirstJsonObject(content);
          if (!parsed || typeof parsed !== "object") {
            continue;
          }
          return {
            ok: true,
            model,
            usage: out?.usage || null,
            json: parsed,
          };
        } catch (_) {
          // retry with fallback model or next attempt
        }
      }
    }

    return { ok: false, reason: "OPENAI_NO_VALID_JSON" };
  } finally {
    clearTimeout(timeout);
  }
}

export async function translateSocialText({
  text,
  targetLanguage = "ar",
} = {}) {
  const input = safeText(text, 4000);
  const normalizedTarget = safeText(targetLanguage, 12).toLowerCase() || "ar";
  if (!input) {
    return { ok: false, reason: "EMPTY_TEXT" };
  }
  const translated = await callOpenAiJson({
    systemPrompt: [
      "You translate short chat messages for a social messaging product.",
      "Return JSON only with keys: translatedText, sourceLanguage, targetLanguage.",
      "Do not explain the translation.",
      "Keep usernames, hashtags, @mentions, URLs, phone numbers, emojis, and numbers intact when possible.",
      "If the input is already in the requested language, return it naturally in the same language.",
    ].join(" "),
    userPayload: {
      text: input,
      targetLanguage: normalizedTarget,
    },
    temperature: 0.1,
    maxTokens: 600,
  });
  if (!translated?.ok) {
    return translated;
  }
  const translatedText = safeText(
    translated?.json?.translatedText || translated?.json?.translation || "",
    5000
  );
  if (!translatedText) {
    return { ok: false, reason: "OPENAI_INVALID_TRANSLATION" };
  }
  return {
    ok: true,
    translatedText,
    sourceLanguage:
      safeText(translated?.json?.sourceLanguage || translated?.json?.detectedLanguage || "", 12)
        .toLowerCase() || null,
    targetLanguage:
      safeText(translated?.json?.targetLanguage || normalizedTarget, 12).toLowerCase() ||
      normalizedTarget,
    provider: "openai",
    model: translated.model || OPENAI_MODEL,
    usage: translated.usage || null,
  };
}

function normalizeEmbeddingVector(value) {
  if (!Array.isArray(value)) return null;
  const vector = value
    .map((item) => Number(item))
    .filter((item) => Number.isFinite(item));
  if (!vector.length) return null;
  return vector;
}

function cosineSimilarity(vecA, vecB) {
  if (!Array.isArray(vecA) || !Array.isArray(vecB)) return 0;
  const len = Math.min(vecA.length, vecB.length);
  if (len <= 0) return 0;

  let dot = 0;
  let normA = 0;
  let normB = 0;
  for (let i = 0; i < len; i += 1) {
    const a = Number(vecA[i]);
    const b = Number(vecB[i]);
    if (!Number.isFinite(a) || !Number.isFinite(b)) continue;
    dot += a * b;
    normA += a * a;
    normB += b * b;
  }
  if (normA <= 0 || normB <= 0) return 0;
  return dot / (Math.sqrt(normA) * Math.sqrt(normB));
}

async function callOpenAiEmbedding(text) {
  const input = safeText(text, 4000);
  if (!input || !openAiReady()) return null;

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), OPENAI_TIMEOUT_MS);
  try {
    for (let attempt = 0; attempt <= OPENAI_RETRIES; attempt += 1) {
      try {
        const response = await fetch(`${OPENAI_BASE_URL}/embeddings`, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${OPENAI_API_KEY}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            model: OPENAI_EMBEDDING_MODEL,
            input,
          }),
          signal: controller.signal,
        });
        if (!response.ok) continue;
        const out = await response.json();
        const embedding = normalizeEmbeddingVector(out?.data?.[0]?.embedding);
        if (embedding) return embedding;
      } catch (_) {
        // retry
      }
    }
    return null;
  } finally {
    clearTimeout(timeout);
  }
}

async function fetchJsonWithTimeout(url, options = {}, timeoutMs = AI_WEB_RESEARCH_TIMEOUT_MS) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, {
      ...options,
      signal: controller.signal,
    });
    if (!response.ok) {
      return { ok: false, status: response.status, json: null };
    }
    const json = await response.json();
    return { ok: true, status: response.status, json };
  } catch (error) {
    return { ok: false, status: 0, json: null, error: String(error?.message || error) };
  } finally {
    clearTimeout(timeout);
  }
}

function normalizeWebSearchResults(payload, { provider = "serpapi_google", limit = 5 } = {}) {
  if (!payload || typeof payload !== "object") return [];
  const safeLimit = clampInt(limit, 1, 12, 5);
  if (provider === "serpapi_google") {
    const list = Array.isArray(payload?.organic_results) ? payload.organic_results : [];
    return list
      .map((item) => ({
        title: safeText(item?.title, 220),
        url: safeText(item?.link, 1200),
        snippet: safeText(item?.snippet, 1200),
        source: "google",
      }))
      .filter((item) => item.title && item.url)
      .slice(0, safeLimit);
  }
  return [];
}

export async function searchWebKnowledge({
  query,
  language = "ar",
  country = "iq",
  limit = AI_WEB_SEARCH_LIMIT,
} = {}) {
  const safeQuery = safeText(query, 800);
  if (!safeQuery) {
    return { ok: false, reason: "EMPTY_QUERY", provider: null, results: [] };
  }
  if (!AI_WEB_RESEARCH_ENABLED) {
    return { ok: false, reason: "WEB_SEARCH_DISABLED", provider: null, results: [] };
  }

  const provider = AI_WEB_RESEARCH_PROVIDER;
  if (provider === "serpapi_google") {
    if (!SERPAPI_API_KEY) {
      return { ok: false, reason: "SERPAPI_KEY_MISSING", provider, results: [] };
    }
    const url = new URL("https://serpapi.com/search.json");
    url.searchParams.set("engine", "google");
    url.searchParams.set("q", safeQuery);
    url.searchParams.set("hl", String(language || "ar").toLowerCase() === "en" ? "en" : "ar");
    url.searchParams.set("gl", String(country || "iq").toLowerCase() || "iq");
    url.searchParams.set("num", String(clampInt(limit, 1, 12, AI_WEB_SEARCH_LIMIT)));
    url.searchParams.set("api_key", SERPAPI_API_KEY);

    const response = await fetchJsonWithTimeout(url.toString(), {}, AI_WEB_RESEARCH_TIMEOUT_MS);
    if (!response.ok) {
      return {
        ok: false,
        reason: "SERPAPI_REQUEST_FAILED",
        provider,
        status: response.status,
        results: [],
      };
    }
    const results = normalizeWebSearchResults(response.json, { provider, limit });
    return {
      ok: true,
      provider,
      results,
      raw: response.json,
    };
  }

  return { ok: false, reason: "UNSUPPORTED_WEB_PROVIDER", provider, results: [] };
}

export async function buildWebGroundedAnswer({
  query,
  language = "ar",
  context = null,
  persistToMemory = true,
} = {}) {
  const safeQuery = safeText(query, 800);
  if (!safeQuery) {
    return { ok: false, reason: "EMPTY_QUERY", answer: null, results: [] };
  }

  const searchResult = await searchWebKnowledge({
    query: safeQuery,
    language,
  });
  if (!searchResult.ok || !Array.isArray(searchResult.results) || !searchResult.results.length) {
    return {
      ok: false,
      reason: searchResult.reason || "NO_WEB_RESULTS",
      provider: searchResult.provider || null,
      answer: null,
      results: searchResult.results || [],
    };
  }

  const snippets = searchResult.results.slice(0, AI_WEB_SEARCH_LIMIT).map((item, idx) => ({
    index: idx + 1,
    title: item.title,
    url: item.url,
    snippet: item.snippet,
  }));

  let answer = null;
  let confidence = 0.58;
  let model = "web_rules";

  const aiResult = await callOpenAiJson({
    systemPrompt:
      String(language || "ar").toLowerCase() === "en"
        ? "You answer the user's question using only provided web snippets. Return strict JSON: {answer:string, confidence:number(0..1), followUpQuestion:string|null, keyPoints:string[]}. If evidence is weak, explicitly say uncertainty."
        : "جاوب المستخدم اعتماداً فقط على المقاطع المرسلة من الويب. ارجع JSON حصراً بهذا الشكل: {answer:string, confidence:number بين 0 و1, followUpQuestion:string|null, keyPoints:string[]}. اذا الدليل ضعيف وضح ذلك بصراحة.",
    userPayload: {
      query: safeQuery,
      language: String(language || "ar").toLowerCase() === "en" ? "en" : "ar",
      context: context && typeof context === "object" ? context : null,
      snippets,
    },
    temperature: 0.15,
    maxTokens: 1100,
  });

  if (aiResult.ok) {
    answer = safeText(aiResult.json?.answer, 5000);
    confidence = clampFloat(aiResult.json?.confidence, 0, 1, 0.72);
    model = aiResult.model || OPENAI_MODEL;
  }

  if (!answer) {
    const summary = snippets
      .slice(0, 3)
      .map((row) => `${row.title}: ${row.snippet || ""}`.trim())
      .filter(Boolean)
      .join(" | ");
    answer =
      String(language || "ar").toLowerCase() === "en"
        ? `I found relevant web results: ${summary}`
        : `وجدت نتائج ويب مرتبطة بسؤالك: ${summary}`;
    confidence = 0.54;
  }

  if (persistToMemory) {
    try {
      await aiRepo.insertTrainingMemory({
        scope: "global",
        ownerUserId: null,
        question: safeQuery,
        answer,
        tags: [
          "web_research",
          String(language || "ar").toLowerCase() === "en" ? "lang_en" : "lang_ar",
          searchResult.provider || "web",
        ],
        source: "web_research",
        qualityScore: clampFloat(confidence, 0, 1, 0.65),
        isActive: true,
        createdByUserId: null,
      });
    } catch (error) {
      console.error("[assistant-ai] failed to persist web answer", String(error?.message || error));
    }
  }

  return {
    ok: true,
    provider: searchResult.provider || null,
    model,
    confidence,
    answer,
    results: snippets,
  };
}

export async function runAutoWebLearning({
  seedQueries = [],
  actorUserId = null,
  maxQueries = AI_WEB_AUTO_LEARN_MAX_QUERIES,
} = {}) {
  if (!AI_WEB_AUTO_LEARN_ENABLED) {
    return {
      ok: false,
      reason: "AUTO_WEB_LEARNING_DISABLED",
      inserted: 0,
      scanned: 0,
      items: [],
    };
  }

  const baseQueries = Array.isArray(seedQueries) ? seedQueries : [];
  const normalizedQueries = baseQueries
    .map((item) => safeText(item, 220))
    .filter(Boolean)
    .slice(0, clampInt(maxQueries, 1, 200, AI_WEB_AUTO_LEARN_MAX_QUERIES));

  const items = [];
  for (const query of normalizedQueries) {
    const out = await buildWebGroundedAnswer({
      query,
      language: "ar",
      context: { channel: "auto_web_learning" },
      persistToMemory: true,
    });
    items.push({
      query,
      ok: out.ok === true,
      confidence: out.ok ? Number(out.confidence || 0) : 0,
      provider: out.provider || null,
    });
  }

  const inserted = items.filter((item) => item.ok).length;
  if (inserted > 0 && Number(actorUserId) > 0) {
    try {
      await aiRepo.insertTrainingMemory({
        scope: "global",
        ownerUserId: null,
        question: "AUTO_WEB_LEARNING_RUN",
        answer: `Inserted ${inserted} web-grounded memories.`,
        tags: ["auto_web_learning", "summary"],
        source: "system_learning",
        qualityScore: 0.8,
        isActive: true,
        createdByUserId: Number(actorUserId),
      });
    } catch (_) {
      // ignore summary persistence failure
    }
  }

  return {
    ok: true,
    scanned: normalizedQueries.length,
    inserted,
    items,
  };
}

function parseProfileJson(rawProfile) {
  const preference = parseJsonSafe(rawProfile?.preference_json, {});
  return {
    city: safeText(preference?.city, 80),
    area: safeText(preference?.area, 80),
    preferredCuisines: Array.isArray(preference?.preferredCuisines)
      ? preference.preferredCuisines
          .map((item) => safeText(item, 50))
          .filter(Boolean)
          .slice(0, 8)
      : [],
    budgetLevel: safeText(preference?.budgetLevel, 40),
    speedPriority: safeText(preference?.speedPriority, 40),
    qualityPriority: safeText(preference?.qualityPriority, 40),
    personalityStyle: safeText(preference?.personalityStyle, 40),
  };
}

function jobCard(item) {
  const salaryMin = Number(item.salary_min || 0);
  const salaryMax = Number(item.salary_max || 0);
  return {
    id: Number(item.id),
    title: item.title || "",
    companyName: item.company_name || item.merchant_name || "",
    category: item.category || "",
    activityType: item.activity_type || "",
    department: item.department || "",
    city: item.city || "",
    area: item.area || "",
    employmentType: item.employment_type || "",
    workplaceType: item.workplace_type || "",
    experienceLevel: item.experience_level || "",
    salaryMin: Number.isFinite(salaryMin) ? salaryMin : 0,
    salaryMax: Number.isFinite(salaryMax) ? salaryMax : 0,
    salaryCurrency: item.salary_currency || "IQD",
    salaryPeriod: item.salary_period || "month",
    isFeatured: item.is_featured === true,
    applicationsCount: Number(item.applications_count || 0),
    publishedAt: item.published_at || null,
    expiresAt: item.expires_at || null,
  };
}

function commerceCard(item) {
  return {
    productId: Number(item.product_id),
    productName: item.product_name || "",
    productDescription: item.product_description || "",
    merchantId: Number(item.merchant_id),
    merchantName: item.merchant_name || "",
    merchantType: item.merchant_type || "",
    categoryName: item.category_name || "",
    effectivePrice: Number(item.effective_price || 0),
    basePrice: Number(item.base_price || 0),
    discountedPrice: Number(item.discounted_price || 0),
    freeDelivery: item.free_delivery === true,
    offerLabel: item.offer_label || null,
    avgRating: Number(item.merchant_avg_rating || 0),
    avgDeliveryMinutes: Number(item.merchant_avg_delivery_minutes || 0),
    completedOrders: Number(item.merchant_completed_orders || 0),
  };
}

function rankWithFallbackByQuery(items, queryText) {
  const query = String(queryText || "").trim().toLowerCase();
  if (!query) {
    return items
      .map((item, idx) => ({ ...item, score: Number((0.85 - idx * 0.01).toFixed(3)) }))
      .slice(0, AI_RECOMMENDATION_LIMIT);
  }
  return items
    .map((item) => {
      const hay = JSON.stringify(item).toLowerCase();
      const hit = hay.includes(query) ? 1 : 0;
      return {
        ...item,
        score: hit ? 0.9 : 0.55,
      };
    })
    .sort((a, b) => b.score - a.score)
    .slice(0, AI_RECOMMENDATION_LIMIT);
}

function buildRecommendationResponse({
  items,
  summary = null,
  modelName = null,
  confidence = 0.65,
}) {
  return {
    ok: true,
    summary: safeText(summary, 1800),
    model: modelName || (openAiReady() ? OPENAI_MODEL : "fallback_rules"),
    confidence: clampFloat(confidence, 0, 1, 0.65),
    items,
  };
}

const LEARNING_TOPIC_HINTS = [
  { topic: "restaurants", words: ["restaurant", "food", "مطعم", "مطاعم", "اكل", "طعام"] },
  { topic: "shopping", words: ["market", "shop", "store", "متجر", "تسوق", "سوق"] },
  { topic: "delivery_speed", words: ["fast", "quick", "urgent", "سريع", "عاجل"] },
  { topic: "pricing", words: ["cheap", "discount", "offer", "سعر", "رخيص", "خصم", "عرض"] },
  { topic: "taxi", words: ["taxi", "ride", "trip", "تكسي", "رحلة", "مشوار"] },
  { topic: "jobs", words: ["job", "career", "وظيفة", "توظيف", "راتب", "cv"] },
  { topic: "community", words: ["community", "social", "منشور", "مجتمع", "بلوك", "عمارة"] },
  { topic: "support", words: ["problem", "issue", "error", "help", "مشكلة", "عطل", "مساعدة"] },
];

const LEARNING_STYLE_HINTS = {
  urgent: ["urgent", "asap", "now", "عاجل", "فورا", "حالاً", "سريع"],
  friendly: ["thanks", "thank you", "شكرا", "ممتاز", "حبيبي", "ورد"],
  formal: ["please", "regards", "يرجى", "لو سمحت", "تحياتي"],
};

function normalizeDigitsToAscii(value) {
  return String(value || "")
    .replace(/[٠-٩]/g, (d) => String("٠١٢٣٤٥٦٧٨٩".indexOf(d)))
    .replace(/[۰-۹]/g, (d) => String("۰۱۲۳۴۵۶۷۸۹".indexOf(d)));
}

function normalizeLearningText(value) {
  const ascii = normalizeDigitsToAscii(value)
    .toLowerCase()
    .replace(/[\u064B-\u065F\u0670]/g, "")
    .replace(/[^\p{L}\p{N}\s]/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
  return ascii;
}

function tokenizeLearningText(value) {
  const normalized = normalizeLearningText(value);
  if (!normalized) return [];
  return normalized
    .split(" ")
    .map((part) => part.trim())
    .filter((part) => part.length >= 2);
}

function jaccardSimilarity(leftTokens = [], rightTokens = []) {
  const left = new Set(Array.isArray(leftTokens) ? leftTokens : []);
  const right = new Set(Array.isArray(rightTokens) ? rightTokens : []);
  if (!left.size || !right.size) return 0;
  let overlap = 0;
  for (const token of left) {
    if (right.has(token)) overlap += 1;
  }
  const union = new Set([...left, ...right]).size || 1;
  return overlap / union;
}

function trigramDiceSimilarity(leftText, rightText) {
  const left = String(leftText || "");
  const right = String(rightText || "");
  if (!left || !right) return 0;
  if (left === right) return 1;

  const toTrigrams = (text) => {
    const padded = `  ${text}  `;
    const grams = [];
    for (let i = 0; i < padded.length - 2; i += 1) {
      grams.push(padded.slice(i, i + 3));
    }
    return grams;
  };

  const leftGrams = toTrigrams(left);
  const rightGrams = toTrigrams(right);
  if (!leftGrams.length || !rightGrams.length) return 0;

  const rightMap = new Map();
  rightGrams.forEach((gram) => {
    rightMap.set(gram, Number(rightMap.get(gram) || 0) + 1);
  });

  let overlap = 0;
  leftGrams.forEach((gram) => {
    const count = Number(rightMap.get(gram) || 0);
    if (count > 0) {
      overlap += 1;
      rightMap.set(gram, count - 1);
    }
  });

  return (2 * overlap) / (leftGrams.length + rightGrams.length);
}

function hashText(value) {
  const normalized = normalizeLearningText(value);
  if (!normalized) return null;
  return crypto.createHash("sha256").update(normalized).digest("hex");
}

function incrementCounter(counter, key, amount = 1) {
  const safeKey = safeText(key, 64);
  if (!safeKey) return;
  counter[safeKey] = Number(counter[safeKey] || 0) + amount;
}

function normalizeCounterObject(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return {};
  const out = {};
  for (const [key, value] of Object.entries(raw)) {
    const safeKey = safeText(key, 64);
    if (!safeKey) continue;
    const n = Number(value);
    if (!Number.isFinite(n) || n <= 0) continue;
    out[safeKey] = Number(n);
  }
  return out;
}

function mergeCounterObjects(baseRaw, nextRaw) {
  const base = normalizeCounterObject(baseRaw);
  const next = normalizeCounterObject(nextRaw);
  for (const [key, value] of Object.entries(next)) {
    base[key] = Number(base[key] || 0) + Number(value);
  }
  return base;
}

function detectTopicsFromText(text) {
  const normalized = normalizeLearningText(text);
  if (!normalized) return [];
  const topics = [];
  for (const entry of LEARNING_TOPIC_HINTS) {
    const hit = entry.words.some((word) => normalized.includes(normalizeLearningText(word)));
    if (hit) topics.push(entry.topic);
  }
  return [...new Set(topics)].slice(0, 16);
}

function detectStyleFromText(text) {
  const normalized = normalizeLearningText(text);
  if (!normalized) return null;
  const scores = {};
  for (const [style, words] of Object.entries(LEARNING_STYLE_HINTS)) {
    for (const word of words) {
      if (normalized.includes(normalizeLearningText(word))) {
        scores[style] = Number(scores[style] || 0) + 1;
      }
    }
  }
  const sorted = Object.entries(scores).sort((a, b) => b[1] - a[1]);
  return sorted[0]?.[0] || null;
}

function extractBudgetCandidates(text) {
  const normalized = normalizeDigitsToAscii(String(text || ""));
  const matches = [...normalized.matchAll(/\b(\d{3,8})\b/g)];
  const values = matches
    .map((m) => Number(m[1]))
    .filter((n) => Number.isFinite(n) && n >= 500 && n <= 3000000)
    .slice(0, 8);
  return [...new Set(values)];
}

function deriveLearningSignalsLight({
  userMessage,
  assistantReply,
  detectedIntent,
  conversationMode,
  language,
  styleSignature,
  metadata,
}) {
  const normalizedUserMessage = normalizeLearningText(userMessage);
  const normalizedReply = normalizeLearningText(assistantReply);
  const topics = detectTopicsFromText(`${userMessage} ${assistantReply}`);
  const budgetCandidates = extractBudgetCandidates(userMessage);
  const styleHint = detectStyleFromText(userMessage);
  const meta = metadata && typeof metadata === "object" ? metadata : {};
  const questionLike = /[?؟]/.test(String(userMessage || ""));
  const urgency = /(\burgent\b|\bnow\b|عاجل|فورا|حالاً|حالا|سريع)/i.test(String(userMessage || ""));
  const sentiment =
    /(مشكلة|سيء|worst|bad|angry|زعلان|تعبان)/i.test(String(userMessage || ""))
      ? "negative"
      : /(ممتاز|رائع|great|awesome|شكرا|thanks)/i.test(String(userMessage || ""))
      ? "positive"
      : "neutral";

  const detectedIntentSafe = safeText(detectedIntent, 64) || "unknown";
  const languageSafe = safeText(language, 8) || "unknown";
  const conversationModeSafe = safeText(conversationMode, 40) || "unknown";

  const extractionConfidence = clampFloat(
    0.55 +
      Math.min(topics.length, 4) * 0.06 +
      (budgetCandidates.length ? 0.08 : 0) +
      (questionLike ? 0.04 : 0),
    0.3,
    0.98,
    0.62
  );
  const intentConfidence = clampFloat(
    detectedIntentSafe !== "unknown" ? 0.78 : 0.42,
    0.2,
    0.99,
    0.65
  );
  const qualityScore = clampFloat(
    0.52 +
      Math.min(String(userMessage || "").trim().length, 180) / 600 +
      (String(assistantReply || "").trim().length >= 30 ? 0.08 : 0),
    0.2,
    0.99,
    0.65
  );
  const responseQuality = clampFloat(
    0.45 + Math.min(String(assistantReply || "").trim().length, 300) / 700,
    0.2,
    0.98,
    0.62
  );

  const extractedEntities = {
    budgets_iqd: budgetCandidates,
    category_hints: topics,
    keywords: normalizedUserMessage.split(" ").filter(Boolean).slice(0, 24),
  };

  const extractedSlots = {
    intent: detectedIntentSafe,
    conversation_mode: conversationModeSafe,
    language: languageSafe,
    style_signature: safeText(styleSignature, 80),
    support_intent: meta.supportIntent === true,
    comparison_intent: meta.comparisonIntent === true,
    llm_used: meta.llmUsed === true,
  };

  const derivedSignals = {
    message_length: String(userMessage || "").trim().length,
    reply_length: String(assistantReply || "").trim().length,
    question_like: questionLike,
    urgency,
    sentiment,
    off_topic_count: Number(meta.offTopicCount || 0),
    merchants_count: Number(meta.merchantsCount || 0),
    products_count: Number(meta.productsCount || 0),
  };

  const facts = [];
  if (detectedIntentSafe && detectedIntentSafe !== "unknown") {
    facts.push({
      key: "dominant_intent",
      value: detectedIntentSafe,
      type: "intent",
      confidence: intentConfidence,
    });
  }
  if (languageSafe && languageSafe !== "unknown") {
    facts.push({
      key: "preferred_language",
      value: languageSafe,
      type: "profile",
      confidence: 0.88,
    });
  }
  if (conversationModeSafe && conversationModeSafe !== "unknown") {
    facts.push({
      key: "conversation_mode",
      value: conversationModeSafe,
      type: "behavior",
      confidence: 0.7,
    });
  }
  if (budgetCandidates.length) {
    facts.push({
      key: "budget_hint_iqd",
      value: String(budgetCandidates[0]),
      type: "budget",
      confidence: 0.78,
      metadata: { source: "message_number_parser" },
    });
  }
  for (const topic of topics.slice(0, 6)) {
    facts.push({
      key: "interest_topic",
      value: topic,
      type: "interest",
      confidence: 0.72,
    });
  }
  if (styleHint) {
    facts.push({
      key: "style_hint",
      value: styleHint,
      type: "style",
      confidence: 0.66,
    });
  }

  const profilePatch = {
    intents: { [detectedIntentSafe]: 1 },
    topics: topics.reduce((acc, topic) => {
      acc[topic] = 1;
      return acc;
    }, {}),
    languages: { [languageSafe]: 1 },
    preferences: {
      last_sentiment: sentiment,
      last_conversation_mode: conversationModeSafe,
      last_budget_hint_iqd: budgetCandidates[0] ?? null,
      style_hint: styleHint || null,
      urgency_preference: urgency === true,
    },
  };

  return {
    normalizedUserMessage,
    messageHash: hashText(userMessage),
    intentConfidence,
    extractionConfidence,
    qualityScore,
    responseQuality,
    extractedEntities,
    extractedSlots,
    extractedTopics: topics,
    derivedSignals,
    facts: facts.slice(0, 24),
    profilePatch,
    originChannel: "assistant_chat",
    assistantAction:
      conversationModeSafe === "checkout"
        ? "checkout"
        : conversationModeSafe === "discovery"
        ? "discover"
        : "respond",
    learningVersion: AI_LEARNING_VERSION,
    learnedAt: new Date().toISOString(),
  };
}

function normalizeLearningFacts(rawFacts = []) {
  const dedupe = new Set();
  const out = [];
  for (const fact of Array.isArray(rawFacts) ? rawFacts : []) {
    const key = safeText(fact?.key, 64);
    const value = safeText(fact?.value, 700);
    if (!key || !value) continue;
    const dedupeKey = `${key}::${value}`;
    if (dedupe.has(dedupeKey)) continue;
    dedupe.add(dedupeKey);
    out.push({
      key,
      value,
      type: safeText(fact?.type, 40) || "preference",
      confidence: clampFloat(fact?.confidence, 0.2, 0.99, 0.62),
      metadata: fact?.metadata && typeof fact.metadata === "object" ? fact.metadata : {},
    });
  }
  return out.slice(0, 30);
}

async function enrichLearningSignalsWithOpenAi(baseSignals, payload) {
  if (!AI_LEARNING_DEEP_PARSE_ENABLED || !openAiReady()) {
    return {
      signals: baseSignals,
      deepModel: null,
    };
  }

  const userMessage = safeText(payload?.userMessage, 2200);
  if (!userMessage || userMessage.length < 10) {
    return {
      signals: baseSignals,
      deepModel: null,
    };
  }

  const aiResult = await callOpenAiJson({
    systemPrompt:
      "You analyze a customer-assistant chat turn for machine learning memory. Return strict JSON only with schema {intentConfidence:number(0..1), extractionConfidence:number(0..1), qualityScore:number(0..1), responseQuality:number(0..1), topics:string[], facts:[{key:string,value:string,type:string,confidence:number}], preferences:object, sentiment:string, urgency:boolean}. Keep it compact, factual, and do not invent unavailable data.",
    userPayload: {
      message: userMessage,
      assistantReply: safeText(payload?.assistantReply, 2200),
      detectedIntent: safeText(payload?.detectedIntent, 64),
      conversationMode: safeText(payload?.conversationMode, 40),
      language: safeText(payload?.language, 8),
      metadata: payload?.metadata && typeof payload.metadata === "object" ? payload.metadata : {},
      currentSignals: baseSignals,
    },
    temperature: 0.1,
    maxTokens: 700,
  });

  if (!aiResult.ok || !aiResult.json || typeof aiResult.json !== "object") {
    return {
      signals: baseSignals,
      deepModel: null,
    };
  }

  const aiTopics = Array.isArray(aiResult.json?.topics)
    ? aiResult.json.topics.map((topic) => safeText(topic, 48)).filter(Boolean)
    : [];
  const mergedTopics = [...new Set([...(baseSignals.extractedTopics || []), ...aiTopics])].slice(
    0,
    20
  );
  const aiFacts = normalizeLearningFacts(aiResult.json?.facts);
  const mergedFacts = normalizeLearningFacts([...(baseSignals.facts || []), ...aiFacts]);

  const signals = {
    ...baseSignals,
    intentConfidence: clampFloat(
      aiResult.json?.intentConfidence,
      0.2,
      0.99,
      baseSignals.intentConfidence
    ),
    extractionConfidence: clampFloat(
      aiResult.json?.extractionConfidence,
      0.2,
      0.99,
      baseSignals.extractionConfidence
    ),
    qualityScore: clampFloat(aiResult.json?.qualityScore, 0.2, 0.99, baseSignals.qualityScore),
    responseQuality: clampFloat(
      aiResult.json?.responseQuality,
      0.2,
      0.99,
      baseSignals.responseQuality
    ),
    extractedTopics: mergedTopics,
    extractedEntities: {
      ...(baseSignals.extractedEntities || {}),
      ai_preferences:
        aiResult.json?.preferences && typeof aiResult.json.preferences === "object"
          ? aiResult.json.preferences
          : {},
    },
    derivedSignals: {
      ...(baseSignals.derivedSignals || {}),
      ai_sentiment: safeText(aiResult.json?.sentiment, 32),
      ai_urgency:
        typeof aiResult.json?.urgency === "boolean"
          ? aiResult.json.urgency
          : baseSignals?.derivedSignals?.urgency,
    },
    facts: mergedFacts,
  };

  if (
    aiResult.json?.preferences &&
    typeof aiResult.json.preferences === "object" &&
    !Array.isArray(aiResult.json.preferences)
  ) {
    signals.profilePatch = {
      ...(signals.profilePatch || {}),
      preferences: {
        ...(signals.profilePatch?.preferences || {}),
        ...aiResult.json.preferences,
      },
    };
  }

  return {
    signals,
    deepModel: aiResult.model || OPENAI_MODEL,
  };
}

function buildLearningProfileSummary(profile) {
  const topIntents = Object.entries(normalizeCounterObject(profile?.intents_json))
    .sort((a, b) => b[1] - a[1])
    .slice(0, 3)
    .map(([key, value]) => `${key}:${value}`);
  const topTopics = Object.entries(normalizeCounterObject(profile?.topics_json))
    .sort((a, b) => b[1] - a[1])
    .slice(0, 4)
    .map(([key]) => key);
  const topLang = Object.entries(normalizeCounterObject(profile?.language_json))
    .sort((a, b) => b[1] - a[1])[0]?.[0];

  return [
    topIntents.length ? `top_intents=${topIntents.join(",")}` : null,
    topTopics.length ? `top_topics=${topTopics.join(",")}` : null,
    topLang ? `language=${topLang}` : null,
  ]
    .filter(Boolean)
    .join(" | ");
}

async function persistLearningProjection({
  customerUserId,
  observationId,
  styleSignature,
  signals,
}) {
  const existing = await aiRepo.getAiUserLearningProfile(customerUserId);
  const intentsCurrent = normalizeCounterObject(existing?.intents_json);
  const topicsCurrent = normalizeCounterObject(existing?.topics_json);
  const languagesCurrent = normalizeCounterObject(existing?.language_json);

  const nextIntents = mergeCounterObjects(intentsCurrent, signals?.profilePatch?.intents || {});
  const nextTopics = mergeCounterObjects(topicsCurrent, signals?.profilePatch?.topics || {});
  const nextLanguages = mergeCounterObjects(
    languagesCurrent,
    signals?.profilePatch?.languages || {}
  );

  const existingPreferences =
    existing?.preferences_json && typeof existing.preferences_json === "object"
      ? existing.preferences_json
      : {};
  const nextPreferences = {
    ...existingPreferences,
    ...(signals?.profilePatch?.preferences || {}),
    updated_at: new Date().toISOString(),
  };

  const confidence = clampFloat(
    ((Number(existing?.confidence || 0.6) * Math.max(Number(existing?.samples_count || 0), 0)) +
      Number(signals?.qualityScore || 0.6)) /
      (Math.max(Number(existing?.samples_count || 0), 0) + 1),
    0.2,
    0.99,
    0.6
  );

  await aiRepo.upsertAiUserLearningProfile({
    customerUserId,
    intents: nextIntents,
    preferences: nextPreferences,
    topics: nextTopics,
    languages: nextLanguages,
    styleSignature: safeText(styleSignature, 80) || existing?.style_signature || null,
    summary: buildLearningProfileSummary({
      intents_json: nextIntents,
      topics_json: nextTopics,
      language_json: nextLanguages,
    }),
    confidence,
    samplesCountIncrement: 1,
    lastObservationId: observationId,
  });

  await aiRepo.upsertAiLearningFacts({
    customerUserId,
    scope: "user",
    sourceObservationId: observationId,
    facts: normalizeLearningFacts(signals?.facts || []),
  });
}

function isLikelyKnowledgeQuestion(userMessage) {
  const text = normalizeLearningText(userMessage);
  if (!text) return false;
  if (/[?؟]/.test(String(userMessage || ""))) return true;
  const starters = [
    "what",
    "how",
    "why",
    "when",
    "which",
    "كم",
    "شلون",
    "شنو",
    "ليش",
    "كيف",
    "متى",
    "ما هي",
    "ما هو",
  ];
  return starters.some((item) => text.startsWith(normalizeLearningText(item)));
}

async function maybePromoteObservationToMemory({
  customerUserId,
  userMessage,
  assistantReply,
  qualityScore,
  responseQuality,
  extractedTopics = [],
}) {
  const question = safeText(userMessage, 1200);
  const answer = safeText(assistantReply, 2000);
  if (!question || !answer) return null;
  if (!isLikelyKnowledgeQuestion(question)) return null;

  const compositeQuality = clampFloat(
    (Number(qualityScore || 0.6) + Number(responseQuality || 0.6)) / 2,
    0,
    1,
    0.6
  );
  if (compositeQuality < 0.78) return null;

  const existing = await aiRepo.listTrainingMemoryForPrompt({
    queryText: question,
    limit: 1,
    ownerUserId: Number(customerUserId),
  });
  if ((existing || []).length > 0) {
    const row = existing[0];
    const prevQuestion = normalizeLearningText(row?.question || "");
    const nextQuestion = normalizeLearningText(question);
    if (prevQuestion && nextQuestion && prevQuestion === nextQuestion) {
      return null;
    }
  }

  const tags = [
    "self_learning",
    "chat_observation",
    ...((Array.isArray(extractedTopics) ? extractedTopics : []).slice(0, 6)),
  ];

  return aiRepo.insertTrainingMemory({
    scope: "user",
    ownerUserId: Number(customerUserId),
    question,
    answer,
    tags,
    source: "self_learning",
    qualityScore: compositeQuality,
    isActive: true,
    createdByUserId: null,
  });
}

export async function recommendJobsForCustomer(customerUserId, dto = {}) {
  const limit = clampInt(dto.limit, 1, 40, AI_RECOMMENDATION_LIMIT);
  const queryText = safeText(dto.query, 300) || "";

  const rawProfile = await assistantRepo.getProfile(customerUserId);
  const profile = parseProfileJson(rawProfile);
  const jobsRaw = await aiRepo.listJobsForRecommendations({
    city: profile.city,
    area: profile.area,
    search: queryText,
    limit: 220,
  });
  const candidates = jobsRaw.map(jobCard);
  if (!candidates.length) {
    return buildRecommendationResponse({
      items: [],
      summary: "لا توجد وظائف مناسبة حالياً حسب بياناتك.",
      confidence: 0.9,
      modelName: "fallback_rules",
    });
  }

  let rankedItems = [];
  let modelName = "fallback_rules";
  let confidence = 0.62;
  let summary = null;

  const aiResult = await callOpenAiJson({
    systemPrompt:
      "You are a strict job recommendation engine for a mobile app. Return JSON only. Output schema: {summary:string, confidence:number(0..1), picks:[{id:number, score:number(0..1), reason:string}]}. Never invent ids.",
    userPayload: {
      queryText,
      customerProfile: profile,
      candidates: candidates.slice(0, 60),
    },
    temperature: 0.15,
    maxTokens: 1100,
  });

  if (aiResult.ok) {
    modelName = aiResult.model || OPENAI_MODEL;
    confidence = clampFloat(aiResult.json?.confidence, 0.35, 0.99, 0.75);
    summary = safeText(aiResult.json?.summary, 1800);
    const picks = Array.isArray(aiResult.json?.picks) ? aiResult.json.picks : [];
    const byId = new Map(candidates.map((item) => [Number(item.id), item]));
    rankedItems = picks
      .map((pick) => {
        const id = Number(pick?.id || 0);
        const card = byId.get(id);
        if (!card) return null;
        return {
          ...card,
          score: clampFloat(pick?.score, 0, 1, 0.7),
          reason: safeText(pick?.reason, 400),
        };
      })
      .filter(Boolean)
      .slice(0, limit);
  }

  if (!rankedItems.length) {
    rankedItems = rankWithFallbackByQuery(candidates, queryText)
      .slice(0, limit)
      .map((item) => ({
        ...item,
        reason: "تم ترتيب الوظيفة حسب الملاءمة النصية والبيانات المتاحة.",
      }));
    summary = summary || "هذه أفضل الوظائف المتاحة حالياً حسب البيانات الحالية.";
  }

  await aiRepo.saveRecommendationSnapshot({
    customerUserId,
    recommendationType: "jobs",
    queryText,
    items: rankedItems,
    modelName,
    confidence,
  });

  return buildRecommendationResponse({
    items: rankedItems,
    summary,
    modelName,
    confidence,
  });
}

export async function recommendCommerceForCustomer(customerUserId, dto = {}) {
  const limit = clampInt(dto.limit, 1, 60, AI_RECOMMENDATION_LIMIT);
  const queryText = safeText(dto.query, 300) || "";
  const kindRaw = String(dto.kind || "shopping").trim().toLowerCase();
  const kind = kindRaw === "restaurants" ? "restaurants" : "shopping";

  const rawProfile = await assistantRepo.getProfile(customerUserId);
  const profile = parseProfileJson(rawProfile);

  const poolRaw = await aiRepo.listCommercePoolForRecommendations({
    kind,
    search: queryText,
    limit: 500,
  });
  const candidates = poolRaw.map(commerceCard);
  if (!candidates.length) {
    return buildRecommendationResponse({
      items: [],
      summary:
        kind === "restaurants"
          ? "لا توجد مطاعم مناسبة حالياً حسب الفلاتر."
          : "لا توجد منتجات مناسبة حالياً حسب الفلاتر.",
      confidence: 0.9,
      modelName: "fallback_rules",
    });
  }

  let rankedItems = [];
  let modelName = "fallback_rules";
  let confidence = 0.62;
  let summary = null;

  const aiResult = await callOpenAiJson({
    systemPrompt:
      "You are a shopping recommendation engine. Return JSON only using schema {summary:string, confidence:number, picks:[{productId:number, score:number(0..1), reason:string}]}. Never invent product ids.",
    userPayload: {
      queryText,
      kind,
      customerProfile: profile,
      candidates: candidates.slice(0, 80),
    },
    temperature: 0.18,
    maxTokens: 1200,
  });

  if (aiResult.ok) {
    modelName = aiResult.model || OPENAI_MODEL;
    confidence = clampFloat(aiResult.json?.confidence, 0.35, 0.99, 0.75);
    summary = safeText(aiResult.json?.summary, 1800);
    const picks = Array.isArray(aiResult.json?.picks) ? aiResult.json.picks : [];
    const byProductId = new Map(candidates.map((item) => [Number(item.productId), item]));
    rankedItems = picks
      .map((pick) => {
        const productId = Number(pick?.productId || 0);
        const card = byProductId.get(productId);
        if (!card) return null;
        return {
          ...card,
          score: clampFloat(pick?.score, 0, 1, 0.7),
          reason: safeText(pick?.reason, 400),
        };
      })
      .filter(Boolean)
      .slice(0, limit);
  }

  if (!rankedItems.length) {
    rankedItems = rankWithFallbackByQuery(candidates, queryText)
      .slice(0, limit)
      .map((item) => ({
        ...item,
        reason: "تم الترتيب حسب التوافق مع البحث والتقييم والسعر.",
      }));
    summary =
      summary ||
      (kind === "restaurants"
        ? "هذه أفضل خيارات المطاعم المتاحة الآن."
        : "هذه أفضل المنتجات المتاحة الآن.");
  }

  await aiRepo.saveRecommendationSnapshot({
    customerUserId,
    recommendationType: kind === "restaurants" ? "restaurants" : "shopping",
    queryText,
    items: rankedItems,
    modelName,
    confidence,
  });

  return buildRecommendationResponse({
    items: rankedItems,
    summary,
    modelName,
    confidence,
  });
}

function fallbackPostModerationEvaluation(post) {
  const text = `${post?.caption || ""} ${post?.media_url || ""}`.toLowerCase();
  const severeWords = [
    "قتل",
    "انتحار",
    "drugs",
    "خدر",
    "كلاوات",
    "scam",
    "نصب",
    "احتيال",
    "terror",
    "تهديد",
  ];
  const mediumWords = ["سب", "شتم", "اهانة", "hate", "nsfw", "اباحي"];
  const severeHit = severeWords.some((word) => text.includes(word));
  const mediumHit = mediumWords.some((word) => text.includes(word));

  if (severeHit) {
    return {
      riskLevel: "high",
      confidence: 0.72,
      shouldReport: true,
      reason: "Detected potentially harmful terms by fallback moderation rules.",
      details: "Keyword-based fallback detected high-risk terms.",
      categories: ["safety"],
      suggestedAction: "request_edit",
      source: "fallback_rules",
    };
  }
  if (mediumHit) {
    return {
      riskLevel: "medium",
      confidence: 0.61,
      shouldReport: false,
      reason: "Potentially sensitive tone detected.",
      details: "Fallback rules flagged medium-risk language.",
      categories: ["toxicity"],
      suggestedAction: "keep",
      source: "fallback_rules",
    };
  }
  return {
    riskLevel: "low",
    confidence: 0.9,
    shouldReport: false,
    reason: "No suspicious pattern detected.",
    details: null,
    categories: [],
    suggestedAction: "keep",
    source: "fallback_rules",
  };
}

async function evaluatePostModeration(post) {
  if (!openAiReady()) return fallbackPostModerationEvaluation(post);

  const aiResult = await callOpenAiJson({
    systemPrompt:
      "You are a social content moderation classifier. Return JSON only with schema {riskLevel:'low|medium|high|critical', confidence:number(0..1), shouldReport:boolean, reason:string, details:string|null, categories:string[], suggestedAction:'keep|request_edit|delete'}.",
    userPayload: {
      post: {
        id: Number(post?.id || 0),
        caption: safeText(post?.caption, 3000),
        postKind: post?.post_kind || "normal",
        mediaKind: post?.media_kind || null,
        mediaUrl: safeText(post?.media_url, 1500),
        scopeType: post?.audience_scope_type || "global",
        scopeCode: post?.audience_scope_code || null,
      },
    },
    temperature: 0.1,
    maxTokens: 700,
  });

  if (!aiResult.ok) {
    return fallbackPostModerationEvaluation(post);
  }

  const riskRaw = String(aiResult.json?.riskLevel || "low").trim().toLowerCase();
  const riskLevel = ["low", "medium", "high", "critical"].includes(riskRaw)
    ? riskRaw
    : "low";
  const suggestedRaw = String(aiResult.json?.suggestedAction || "keep")
    .trim()
    .toLowerCase();
  const suggestedAction = ["keep", "request_edit", "delete"].includes(suggestedRaw)
    ? suggestedRaw
    : "keep";
  const categories = Array.isArray(aiResult.json?.categories)
    ? aiResult.json.categories
        .map((item) => safeText(item, 60))
        .filter(Boolean)
        .slice(0, 10)
    : [];
  const confidence = clampFloat(aiResult.json?.confidence, 0, 1, 0.7);
  const shouldReport =
    aiResult.json?.shouldReport === true || ["high", "critical"].includes(riskLevel);

  return {
    riskLevel,
    confidence,
    shouldReport,
    reason:
      safeText(aiResult.json?.reason, 2000) ||
      "AI moderation detected suspicious content.",
    details: safeText(aiResult.json?.details, 8000),
    categories,
    suggestedAction,
    source: aiResult.model || OPENAI_MODEL,
    payload: aiResult.json,
  };
}

async function notifyBackofficeAboutAiReport({ postId, findingId, riskLevel, confidence }) {
  const adminUserIds = await aiRepo.listBackofficeUserIds(500);
  if (!adminUserIds.length) return;
  const rows = adminUserIds.map((userId) => ({
    userId,
    type: "social.report.post.ai_created",
    title: "AI moderation report",
    body: `AI flagged post #${Number(postId)} with risk ${String(riskLevel || "medium").toUpperCase()}.`,
    payload: {
      postId: Number(postId),
      findingId: Number(findingId || 0),
      source: "ai",
      riskLevel,
      confidence,
      target: "admin_social_reports",
    },
  }));
  await createManyNotifications(rows);
}

async function persistModerationResult({
  post,
  evaluation,
  triggeredBy,
  reviewerUserId = null,
}) {
  const openFinding = await aiRepo.findOpenAiModerationFindingByPostId(post.id);
  if (openFinding && evaluation.shouldReport !== true) {
    return {
      finding: openFinding,
      reportId: null,
      reported: false,
    };
  }

  const finding = await aiRepo.createAiPostModerationFinding({
    postId: Number(post.id),
    riskLevel: evaluation.riskLevel,
    reason: evaluation.reason,
    details: evaluation.details,
    modelName: `${AI_MODEL_TAG}:${evaluation.source || "fallback"}`,
    confidence: evaluation.confidence,
    payload: {
      categories: evaluation.categories || [],
      suggestedAction: evaluation.suggestedAction || "keep",
      originalPayload: evaluation.payload || null,
    },
    triggeredBy,
  });

  let report = null;
  if (evaluation.shouldReport === true) {
    report = await aiRepo.upsertAiPostReport({
      postId: Number(post.id),
      reason: evaluation.reason,
      details: evaluation.details,
      sourceModel: `${AI_MODEL_TAG}:${evaluation.source || "fallback"}`,
      sourceConfidence: evaluation.confidence,
      aiFindingId: Number(finding?.id || 0) || null,
    });
    if (report?.id) {
      await notifyBackofficeAboutAiReport({
        postId: Number(post.id),
        findingId: Number(finding?.id || 0),
        riskLevel: evaluation.riskLevel,
        confidence: evaluation.confidence,
      });
    }
  } else if (finding?.id && ["low", "medium"].includes(evaluation.riskLevel)) {
    await aiRepo.markAiPostModerationFindingReviewed({
      findingId: Number(finding.id),
      status: "resolved",
      actionTaken: "no_action",
      reviewedByUserId: reviewerUserId,
    });
  }

  return {
    finding,
    reportId: Number(report?.id || 0) || null,
    reported: Boolean(report?.id),
  };
}

export async function moderatePostWithAi({
  postId,
  triggeredBy = "manual",
  reviewerUserId = null,
}) {
  const post = await aiRepo.findPostForAiModeration(postId);
  if (!post) {
    throw new AppError("POST_NOT_FOUND", { status: 404 });
  }
  const evaluation = await evaluatePostModeration(post);
  const persisted = await persistModerationResult({
    post,
    evaluation,
    triggeredBy,
    reviewerUserId,
  });
  return {
    ok: true,
    postId: Number(post.id),
    evaluation: {
      riskLevel: evaluation.riskLevel,
      confidence: evaluation.confidence,
      shouldReport: evaluation.shouldReport === true,
      reason: evaluation.reason,
      details: evaluation.details,
      categories: evaluation.categories || [],
      suggestedAction: evaluation.suggestedAction || "keep",
      model: `${AI_MODEL_TAG}:${evaluation.source || "fallback"}`,
    },
    findingId: Number(persisted.finding?.id || 0) || null,
    reportId: persisted.reportId,
    reported: persisted.reported === true,
  };
}

export async function scanRecentPostsWithAi({
  limit = 50,
  reviewerUserId = null,
}) {
  const safeLimit = clampInt(limit, 1, AI_POST_SCAN_BATCH_LIMIT, 50);
  const posts = await aiRepo.listRecentPostsForAiScan({ limit: safeLimit });

  let scanned = 0;
  let reported = 0;
  let highRisk = 0;
  const sample = [];

  for (const post of posts) {
    scanned += 1;
    const evaluation = await evaluatePostModeration(post);
    if (["high", "critical"].includes(evaluation.riskLevel)) {
      highRisk += 1;
    }
    const persisted = await persistModerationResult({
      post,
      evaluation,
      triggeredBy: "auto",
      reviewerUserId,
    });
    if (persisted.reported) reported += 1;
    if (sample.length < 20) {
      sample.push({
        postId: Number(post.id),
        riskLevel: evaluation.riskLevel,
        confidence: evaluation.confidence,
        reported: persisted.reported,
        reason: evaluation.reason,
      });
    }
  }

  return {
    ok: true,
    scanned,
    reported,
    highRisk,
    sample,
  };
}

export async function listAiModerationFindings(query = {}) {
  return {
    items: await aiRepo.listAiPostModerationFindings({
      status: query?.status || "open",
      limit: clampInt(query?.limit, 1, 300, 80),
      beforeId:
        query?.beforeId == null || query.beforeId === ""
          ? null
          : Number(query.beforeId),
    }),
  };
}

export async function reviewAiModerationFinding({
  findingId,
  status,
  actionTaken = null,
  reviewedByUserId = null,
}) {
  const safeStatus = String(status || "").trim().toLowerCase();
  if (!["resolved", "ignored", "open"].includes(safeStatus)) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: ["status"] },
    });
  }
  const row = await aiRepo.markAiPostModerationFindingReviewed({
    findingId,
    status: safeStatus,
    actionTaken,
    reviewedByUserId,
  });
  if (!row) {
    throw new AppError("AI_FINDING_NOT_FOUND", { status: 404 });
  }
  return { finding: row };
}

function normalizeIssueKey(moduleKey) {
  return String(moduleKey || "").trim().toLowerCase().slice(0, 64) || "unknown";
}

function mapFindingsByKey(openItems = []) {
  const map = new Map();
  for (const item of openItems) {
    const key = `${normalizeIssueKey(item.module_key)}::${String(item.title || "")
      .trim()
      .toLowerCase()}`;
    if (!map.has(key)) map.set(key, item);
  }
  return map;
}

async function upsertSystemIssue({ openMap, issue }) {
  const key = `${normalizeIssueKey(issue.moduleKey)}::${String(issue.title || "")
    .trim()
    .toLowerCase()}`;
  if (openMap.has(key)) return openMap.get(key);
  const inserted = await aiRepo.insertAiSystemFinding(issue);
  openMap.set(key, inserted);
  return inserted;
}

async function runSystemChecks() {
  const checks = [];

  try {
    await q("SELECT 1 AS ok");
    checks.push({
      moduleKey: "core.database",
      healthy: true,
      severity: "info",
      title: "Database health",
      details: "Database connection is healthy.",
      fixHint: null,
      metadata: { source: "db_ping" },
    });
  } catch (error) {
    checks.push({
      moduleKey: "core.database",
      healthy: false,
      severity: "critical",
      title: "Database health failure",
      details: `Database ping failed: ${String(error?.message || "unknown")}`,
      fixHint: "Check DATABASE_URL and database availability immediately.",
      metadata: { source: "db_ping", error: String(error?.message || "") },
    });
  }

  if (!openAiReady()) {
    checks.push({
      moduleKey: "ai.openai",
      healthy: false,
      severity: "warning",
      title: "OpenAI configuration missing",
      details: "OPENAI_ENABLED is false or OPENAI_API_KEY is not configured.",
      fixHint: "Set OPENAI_ENABLED=true and OPENAI_API_KEY in runtime environment.",
      metadata: {
        enabled: OPENAI_ENABLED,
        hasApiKey: OPENAI_API_KEY.length > 0,
      },
    });
  } else {
    checks.push({
      moduleKey: "ai.openai",
      healthy: true,
      severity: "info",
      title: "OpenAI configuration",
      details: "OpenAI runtime configuration is available.",
      fixHint: null,
      metadata: { model: OPENAI_MODEL, baseUrl: OPENAI_BASE_URL },
    });
  }

  const push = getPushConfigStatus();
  if (!push.configured) {
    checks.push({
      moduleKey: "notifications.push",
      healthy: false,
      severity: "warning",
      title: "Push notification service is not fully configured",
      details:
        "FCM/Firebase service account is missing, push notifications may not reach all devices.",
      fixHint:
        "Provide FIREBASE_SERVICE_ACCOUNT_JSON or split FIREBASE_* credentials.",
      metadata: push,
    });
  } else {
    checks.push({
      moduleKey: "notifications.push",
      healthy: true,
      severity: "info",
      title: "Push notification configuration",
      details: "Push notification credentials are configured.",
      fixHint: null,
      metadata: push,
    });
  }

  try {
    const backlog = await q(
      `SELECT COUNT(*)::int AS total
       FROM social_post_report
       WHERE created_at < NOW() - INTERVAL '6 hours'`
    );
    const total = Number(backlog.rows[0]?.total || 0);
    if (total >= 30) {
      checks.push({
        moduleKey: "social.reports_backlog",
        healthy: false,
        severity: "warning",
        title: "Social reports backlog",
        details: `${total} social reports are older than 6 hours and still pending review.`,
        fixHint: "Open admin social reports and process old reports first.",
        metadata: { staleReports: total },
      });
    } else {
      checks.push({
        moduleKey: "social.reports_backlog",
        healthy: true,
        severity: "info",
        title: "Social reports backlog",
        details: "No risky backlog in social reports queue.",
        fixHint: null,
        metadata: { staleReports: total },
      });
    }
  } catch (error) {
    checks.push({
      moduleKey: "social.reports_backlog",
      healthy: false,
      severity: "warning",
      title: "Failed to evaluate social backlog",
      details: `Could not query social_post_report: ${String(error?.message || "unknown")}`,
      fixHint: "Check schema migrations and report table integrity.",
      metadata: { error: String(error?.message || "") },
    });
  }

  try {
    const users = await q(
      `SELECT COUNT(*)::int AS total
       FROM app_user
       WHERE locked_until IS NOT NULL
         AND locked_until >= NOW()`
    );
    const locked = Number(users.rows[0]?.total || 0);
    if (locked >= 8) {
      checks.push({
        moduleKey: "auth.lock_pressure",
        healthy: false,
        severity: "warning",
        title: "High auth lock pressure",
        details: `${locked} user accounts are currently locked.`,
        fixHint: "Review auth abuse logs, consider rate limit tuning.",
        metadata: { lockedUsers: locked },
      });
    } else {
      checks.push({
        moduleKey: "auth.lock_pressure",
        healthy: true,
        severity: "info",
        title: "Auth lock pressure",
        details: "No abnormal auth lock pressure detected.",
        fixHint: null,
        metadata: { lockedUsers: locked },
      });
    }
  } catch (error) {
    checks.push({
      moduleKey: "auth.lock_pressure",
      healthy: false,
      severity: "warning",
      title: "Failed to evaluate auth lock pressure",
      details: String(error?.message || "unknown"),
      fixHint: "Check app_user auth columns and migration state.",
      metadata: { error: String(error?.message || "") },
    });
  }

  return checks;
}

export async function runAiSupportScan({ actorUserId = null } = {}) {
  const checks = await runSystemChecks();
  const openFindings = await aiRepo.listAiSystemFindings({ status: "open", limit: 500 });
  const openMap = mapFindingsByKey(openFindings);

  const created = [];
  const resolvedModules = [];

  for (const check of checks) {
    if (check.healthy) {
      await aiRepo.resolveOpenSystemFindingsByModule(check.moduleKey);
      resolvedModules.push(check.moduleKey);
      continue;
    }
    const finding = await upsertSystemIssue({
      openMap,
      issue: {
        moduleKey: check.moduleKey,
        severity: check.severity,
        title: check.title,
        details: check.details,
        fixHint: check.fixHint,
        metadata: {
          actorUserId: Number(actorUserId || 0) || null,
          ...check.metadata,
        },
      },
    });
    created.push(finding);
  }

  const items = await aiRepo.listAiSystemFindings({ status: "all", limit: 200 });
  return {
    ok: true,
    checks,
    createdCount: created.length,
    resolvedModules: [...new Set(resolvedModules)],
    items,
  };
}

export async function listAiSupportFindings(query = {}) {
  const status = String(query?.status || "open").trim().toLowerCase();
  const limit = clampInt(query?.limit, 1, 400, 100);
  const items = await aiRepo.listAiSystemFindings({ status, limit });
  return { items };
}

export async function setAiSupportFindingStatus({
  findingId,
  status,
  actorUserId = null,
}) {
  const safeStatus = String(status || "").trim().toLowerCase();
  if (!["open", "resolved", "ignored"].includes(safeStatus)) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: ["status"] },
    });
  }
  const updated = await aiRepo.setAiSystemFindingStatus({
    findingId,
    status: safeStatus,
    resolvedByUserId: actorUserId,
  });
  if (!updated) {
    throw new AppError("AI_SUPPORT_FINDING_NOT_FOUND", { status: 404 });
  }
  return { finding: updated };
}

function normalizeTags(tags) {
  if (!Array.isArray(tags)) return [];
  return tags
    .map((entry) => safeText(entry, 48))
    .filter(Boolean)
    .slice(0, 20);
}

export async function createTrainingMemoryEntry({
  actorUserId,
  dto,
}) {
  const question = safeText(dto?.question, 10000);
  const answer = safeText(dto?.answer, 12000);
  if (!question || !answer) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: ["question", "answer"] },
    });
  }
  const scopeRaw = String(dto?.scope || "global").trim().toLowerCase();
  const scope = scopeRaw === "user" ? "user" : "global";
  const ownerUserId =
    scope === "user" && Number(dto?.ownerUserId) > 0 ? Number(dto.ownerUserId) : null;

  const memory = await aiRepo.insertTrainingMemory({
    scope,
    ownerUserId,
    question,
    answer,
    tags: normalizeTags(dto?.tags),
    source: safeText(dto?.source, 24) || "admin_teaching",
    qualityScore: clampFloat(dto?.qualityScore, 0, 1, 0.9),
    isActive: dto?.isActive !== false,
    createdByUserId: Number(actorUserId || 0) || null,
  });
  return { memory };
}

export async function listTrainingMemoryEntries(query = {}) {
  const limit = clampInt(query?.limit, 1, 300, 40);
  const offset = clampInt(query?.offset, 0, 50000, 0);
  const activeOnly = query?.activeOnly === true || String(query?.activeOnly) === "true";
  const search = safeText(query?.search, 200) || "";
  const [items, total] = await Promise.all([
    aiRepo.listTrainingMemory({ search, limit, offset, activeOnly }),
    aiRepo.countTrainingMemory({ search, activeOnly }),
  ]);
  return { items, total, limit, offset };
}

export async function listAiChatSessionsForAdmin(query = {}) {
  const limit = clampInt(query?.limit, 1, 200, 40);
  const offset = clampInt(query?.offset, 0, 50000, 0);
  const search = safeText(query?.search, 120) || "";
  const [items, total] = await Promise.all([
    aiRepo.listAdminAiChatSessions({ search, limit, offset }),
    aiRepo.countAdminAiChatSessions({ search }),
  ]);
  return { items, total, limit, offset };
}

export async function listAiChatMessagesForAdmin(sessionId, query = {}) {
  const id = Number(sessionId);
  if (!Number.isInteger(id) || id <= 0) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: ["sessionId"] },
    });
  }
  const items = await aiRepo.listAdminAiChatMessages({
    sessionId: id,
    limit: clampInt(query?.limit, 1, 300, 120),
    beforeId:
      query?.beforeId == null || query.beforeId === ""
        ? null
        : Number(query.beforeId),
  });
  return { items };
}

async function getOrCreateAiUserProfile(customerUserId) {
  const defaultConsentFlags = await resolveDefaultConsentFlagsForUser(customerUserId);
  const existing = await aiRepo.getAiUserProfileV2(customerUserId);
  if (existing) {
    const currentConsent = normalizeConsentFlags(existing.consent_flags_json);
    if (consentFlagsNeedSync(currentConsent, defaultConsentFlags)) {
      const synced = await aiRepo.setAiUserConsentFlags({
        customerUserId,
        consentFlags: defaultConsentFlags,
      });
      return {
        ...synced,
        consent_flags_json: normalizeConsentFlags(synced?.consent_flags_json),
      };
    }
    return {
      ...existing,
      consent_flags_json: currentConsent,
    };
  }
  const created = await aiRepo.upsertAiUserProfileV2({
    customerUserId,
    consentFlags: defaultConsentFlags,
  });
  return {
    ...created,
    consent_flags_json: normalizeConsentFlags(created?.consent_flags_json),
  };
}

export async function setUserMemoryConsent({
  customerUserId,
  consentFlags = {},
}) {
  const profile = await getOrCreateAiUserProfile(customerUserId);
  const previousConsent = normalizeConsentFlags(profile?.consent_flags_json);
  const nextConsent = normalizeConsentFlags({
    ...previousConsent,
    ...consentFlags,
  });

  const updated = await aiRepo.setAiUserConsentFlags({
    customerUserId,
    consentFlags: nextConsent,
  });

  await aiRepo.insertAiMemoryAuditLogV2({
    actorUserId: Number(customerUserId),
    actorRole: "user",
    targetUserId: Number(customerUserId),
    actionKey: "user.memory_consent.updated",
    details: {
      previousConsent,
      nextConsent,
    },
  });

  return {
    profile: updated,
    consentFlags: normalizeConsentFlags(updated?.consent_flags_json),
  };
}

export async function getUserAiProfile({
  customerUserId,
}) {
  const profile = await getOrCreateAiUserProfile(customerUserId);
  const preferences = parseJsonSafe(profile?.preferences_json, {}) || {};
  return {
    profile: {
      ...profile,
      consentFlags: normalizeConsentFlags(profile?.consent_flags_json),
      preferences,
      interests: normalizeTextList(parseJsonSafe(profile?.interests, []) || []),
      goals: normalizeTextList(parseJsonSafe(profile?.goals, []) || []),
      painPoints: normalizeTextList(parseJsonSafe(profile?.pain_points, []) || []),
    },
  };
}

export async function updateUserAiProfile({
  customerUserId,
  dto = {},
}) {
  const previous = await getOrCreateAiUserProfile(customerUserId);
  const updated = await aiRepo.upsertAiUserProfileV2({
    customerUserId,
    displayName: safeText(dto?.displayName, 160),
    realName: safeText(dto?.realName, 160),
    nickname: safeText(dto?.nickname, 160),
    preferredLanguage: safeText(dto?.preferredLanguage, 12),
    dialect: safeText(dto?.dialect, 32),
    gender: safeText(dto?.gender, 20),
    ageRange: safeText(dto?.ageRange, 40),
    city: safeText(dto?.city, 120),
    bioSummary: safeText(dto?.bioSummary, 4000),
    occupation: safeText(dto?.occupation, 160),
    interests: normalizeTextList(dto?.interests),
    goals: normalizeTextList(dto?.goals, { maxItems: 80, maxLen: 180 }),
    personalityNotes: safeText(dto?.personalityNotes, 4000),
    familyNotes: safeText(dto?.familyNotes, 4000),
    painPoints: normalizeTextList(dto?.painPoints, { maxItems: 80, maxLen: 220 }),
    preferences: dto?.preferences && typeof dto.preferences === "object" ? dto.preferences : null,
    consentFlags:
      dto?.consentFlags && typeof dto.consentFlags === "object"
        ? normalizeConsentFlags({
            ...normalizeConsentFlags(previous?.consent_flags_json),
            ...dto.consentFlags,
          })
        : null,
  });

  const trackedPreferenceKeys = [
    "displayName",
    "realName",
    "nickname",
    "preferredLanguage",
    "dialect",
    "city",
    "occupation",
  ];

  await Promise.all(
    trackedPreferenceKeys.map(async (key) => {
      if (!Object.prototype.hasOwnProperty.call(dto || {}, key)) return;
      const previousValue = previous?.[keyToDbProfileField(key)] ?? null;
      const nextValue = dto?.[key] ?? null;
      if (String(previousValue ?? "") === String(nextValue ?? "")) return;
      await aiRepo.insertAiUserPreferenceHistoryV2({
        customerUserId,
        preferenceKey: key,
        oldValue: previousValue,
        newValue: nextValue,
        changedBy: "user",
      });
    })
  );

  await aiRepo.insertAiMemoryAuditLogV2({
    actorUserId: Number(customerUserId),
    actorRole: "user",
    targetUserId: Number(customerUserId),
    actionKey: "user.ai_profile.updated",
    details: {
      keys: Object.keys(dto || {}),
    },
  });

  return {
    profile: {
      ...updated,
      consentFlags: normalizeConsentFlags(updated?.consent_flags_json),
    },
  };
}

function keyToDbProfileField(key) {
  const map = {
    displayName: "display_name",
    realName: "real_name",
    nickname: "nickname",
    preferredLanguage: "preferred_language",
    dialect: "dialect",
    city: "city",
    occupation: "occupation",
  };
  return map[key] || key;
}

export async function listUserAiConversations({
  customerUserId,
  limit = 20,
  offset = 0,
}) {
  const items = await aiRepo.listAiConversationsV2({
    customerUserId,
    limit,
    offset,
  });
  return {
    items,
    limit,
    offset,
  };
}

export async function getUserAiConversation({
  customerUserId,
  conversationId,
  messageLimit = 120,
  beforeId = null,
}) {
  const id = Number(conversationId);
  if (!Number.isInteger(id) || id <= 0) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: ["conversationId"] },
    });
  }
  const conversation = await aiRepo.getAiConversationV2({
    conversationId: id,
    customerUserId,
  });
  if (!conversation) {
    throw new AppError("AI_CONVERSATION_NOT_FOUND", { status: 404 });
  }
  const messages = await aiRepo.listAiConversationMessagesV2({
    conversationId: id,
    customerUserId,
    limit: messageLimit,
    beforeId,
  });
  return { conversation, messages };
}

export async function listUserAiMemories({
  customerUserId,
  memoryType = null,
  activeOnly = true,
  limit = 120,
  offset = 0,
}) {
  const items = await aiRepo.listAiUserMemoriesV2({
    customerUserId,
    memoryType,
    activeOnly,
    limit,
    offset,
  });
  return { items, limit, offset };
}

export async function createUserAiMemory({
  customerUserId,
  dto = {},
}) {
  const profile = await getOrCreateAiUserProfile(customerUserId);
  const consentFlags = normalizeConsentFlags(profile?.consent_flags_json);
  if (!consentFlags.memoryEnabled) {
    throw new AppError("AI_MEMORY_DISABLED_BY_USER", {
      status: 403,
      details: { message: "AI_MEMORY_DISABLED_BY_USER" },
    });
  }

  const memory = await aiRepo.insertAiUserMemoryV2({
    customerUserId,
    memoryType: safeText(dto?.memoryType, 40) || "note",
    memoryKey: safeText(dto?.memoryKey, 120) || "manual_note",
    memoryValue: safeText(dto?.memoryValue, 4000),
    confidenceScore: clampFloat(dto?.confidenceScore, 0, 1, 0.75),
    sourceConversationId:
      dto?.sourceConversationId == null ? null : Number(dto.sourceConversationId),
    sourceMessageId: dto?.sourceMessageId == null ? null : Number(dto.sourceMessageId),
    isActive: dto?.isActive !== false,
  });

  if (!memory) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: ["memoryValue"] },
    });
  }

  await aiRepo.insertAiMemoryAuditLogV2({
    actorUserId: Number(customerUserId),
    actorRole: "user",
    targetUserId: Number(customerUserId),
    actionKey: "user.memory.created",
    details: {
      memoryId: Number(memory.id),
      memoryType: memory.memory_type,
      memoryKey: memory.memory_key,
    },
  });

  return { memory };
}

export async function updateUserAiMemory({
  customerUserId,
  memoryId,
  dto = {},
}) {
  const updated = await aiRepo.updateAiUserMemoryV2({
    memoryId,
    customerUserId,
    memoryType: dto?.memoryType,
    memoryKey: dto?.memoryKey,
    memoryValue: dto?.memoryValue,
    confidenceScore:
      dto?.confidenceScore == null ? null : clampFloat(dto.confidenceScore, 0, 1, 0.75),
    isActive: dto?.isActive == null ? null : dto.isActive === true,
  });

  if (!updated) {
    throw new AppError("AI_MEMORY_NOT_FOUND", { status: 404 });
  }

  await aiRepo.insertAiMemoryAuditLogV2({
    actorUserId: Number(customerUserId),
    actorRole: "user",
    targetUserId: Number(customerUserId),
    actionKey: "user.memory.updated",
    details: {
      memoryId: Number(memoryId),
      fields: Object.keys(dto || {}),
    },
  });

  return { memory: updated };
}

export async function deleteUserAiMemory({
  customerUserId,
  memoryId,
}) {
  const deleted = await aiRepo.deleteAiUserMemoryV2({
    memoryId,
    customerUserId,
  });
  if (!deleted) {
    throw new AppError("AI_MEMORY_NOT_FOUND", { status: 404 });
  }

  await aiRepo.insertAiMemoryAuditLogV2({
    actorUserId: Number(customerUserId),
    actorRole: "user",
    targetUserId: Number(customerUserId),
    actionKey: "user.memory.deleted",
    details: {
      memoryId: Number(memoryId),
    },
  });

  return { ok: true };
}

export async function clearUserAiMemories({
  customerUserId,
  activeOnly = false,
  memoryType = null,
}) {
  const out = await aiRepo.deleteAllAiUserMemoriesV2({
    customerUserId,
    activeOnly: activeOnly === true,
    memoryType: safeText(memoryType, 40) || null,
  });

  await aiRepo.insertAiMemoryAuditLogV2({
    actorUserId: Number(customerUserId),
    actorRole: "user",
    targetUserId: Number(customerUserId),
    actionKey: "user.memory.cleared",
    details: {
      activeOnly: activeOnly === true,
      memoryType: safeText(memoryType, 40) || null,
      deletedCount: Number(out?.deletedCount || 0),
    },
  });

  return {
    ok: true,
    deletedCount: Number(out?.deletedCount || 0),
    activeOnly: activeOnly === true,
    memoryType: safeText(memoryType, 40) || null,
  };
}

export async function listUserAiTopics({
  customerUserId,
  limit = 80,
}) {
  const items = await aiRepo.listAiUserTopicsV2({
    customerUserId,
    limit,
  });
  return { items };
}

export async function runAssistantAppSearch({
  customerUserId,
  dto = {},
}) {
  const kind = String(dto?.kind || "commerce").trim().toLowerCase();
  const queryText = safeText(dto?.query, 600);
  const limit = clampInt(dto?.limit, 1, 50, 12);

  if (kind === "jobs") {
    const out = await recommendJobsForCustomer(customerUserId, {
      query: queryText,
      limit,
    });
    return { kind, source: "app_data", ...out };
  }

  if (kind === "restaurants" || kind === "shopping" || kind === "commerce") {
    const out = await recommendCommerceForCustomer(customerUserId, {
      kind: kind === "restaurants" ? "restaurants" : "shopping",
      query: queryText,
      limit,
    });
    return { kind, source: "app_data", ...out };
  }

  return {
    kind,
    source: "app_data",
    items: [],
    warnings: ["UNSUPPORTED_APP_SEARCH_KIND"],
  };
}

export async function runAssistantWebSearch({
  customerUserId,
  dto = {},
}) {
  const query = safeText(dto?.query, 600);
  if (!query) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: ["query"] },
    });
  }
  const language = safeText(dto?.language, 8) || "ar";
  const result = await searchWebKnowledge({
    query,
    language,
    limit: clampInt(dto?.limit, 1, 10, 5),
  });

  if (result?.ok) {
    await aiRepo.insertAiMemoryAuditLogV2({
      actorUserId: Number(customerUserId),
      actorRole: "user",
      targetUserId: Number(customerUserId),
      actionKey: "user.web_search.executed",
      details: {
        query,
        sources: result.sources?.map((x) => x.url).slice(0, 5) || [],
      },
    });
  }

  return result;
}

export async function listAdminAiUsersIntelligence(query = {}) {
  const items = await aiRepo.listAiIntelligenceUsersV2({
    search: safeText(query?.search, 120) || "",
    limit: clampInt(query?.limit, 1, 200, 40),
    offset: clampInt(query?.offset, 0, 50000, 0),
  });
  return { items };
}

export async function getAdminAiUserIntelligenceDetails({
  customerUserId,
}) {
  const userId = Number(customerUserId);
  if (!Number.isInteger(userId) || userId <= 0) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: ["userId"] },
    });
  }
  const details = await aiRepo.getAiIntelligenceUserDetailsV2({
    customerUserId: userId,
    conversationsLimit: 40,
    memoriesLimit: 180,
  });
  return details;
}

export async function listAdminAiInsights(query = {}) {
  const items = await aiRepo.listAiInsightsOverviewV2({
    limit: clampInt(query?.limit, 10, 500, 120),
  });
  return { items };
}

export async function listAdminAiTopics(query = {}) {
  const items = await aiRepo.listAiTopicsOverviewV2({
    limit: clampInt(query?.limit, 10, 1000, 200),
  });
  return { items };
}

export async function listAdminAiFeedback(query = {}) {
  const items = await aiRepo.listAiFeedbackOverviewV2({
    limit: clampInt(query?.limit, 10, 1000, 200),
  });
  return { items };
}

export async function listAdminAiAuditLogs(query = {}) {
  const items = await aiRepo.listAiAuditLogsV2({
    targetUserId:
      query?.targetUserId == null || query.targetUserId === ""
        ? null
        : Number(query.targetUserId),
    limit: clampInt(query?.limit, 10, 1200, 200),
    offset: clampInt(query?.offset, 0, 50000, 0),
  });
  return { items };
}

async function summarizeLearnedFromData({
  memoryItems,
  observationItems,
  stats,
  advancedStats,
  topFacts,
  userProfiles,
}) {
  const fallbackSummary = [
    `ذاكرة التعلم الفعالة: ${Number(stats?.memory?.active_total || 0)} عنصر.`,
    `إجمالي الرسائل الملاحظة: ${Number(stats?.observations?.total || 0)}.`,
    `آخر 24 ساعة: ${Number(stats?.observations?.last_24h || 0)} رسالة.`,
    `Learning profiles: ${Number(advancedStats?.profiles?.total_profiles || 0)}.`,
    `Active learned facts: ${Number(advancedStats?.facts?.total_facts || 0)}.`,
  ].join(" ");

  if (!openAiReady()) {
    return { summary: fallbackSummary, model: "fallback_rules" };
  }

  const aiResult = await callOpenAiJson({
    systemPrompt:
      "You summarize AI learning progress for a super-admin. Return JSON only with schema {summary:string, keyLearnings:string[], risks:string[], nextActions:string[]}. Keep it concise and factual.",
    userPayload: {
      stats,
      advancedStats,
      memoryItems: memoryItems.slice(0, 20),
      observations: observationItems.slice(0, 30).map((item) => ({
        intent: item.detected_intent,
        mode: item.conversation_mode,
        language: item.language,
        userMessage: safeText(item.user_message, 280),
        assistantReply: safeText(item.assistant_reply, 280),
      })),
      topFacts: (topFacts || []).slice(0, 20).map((fact) => ({
        key: fact.fact_key,
        value: fact.fact_value,
        type: fact.fact_type,
        occurrences: Number(fact.occurrences || 0),
        confidence: clampFloat(fact.confidence, 0, 1, 0.6),
      })),
      userProfiles: (userProfiles || []).slice(0, 20).map((profile) => ({
        userId: Number(profile.user_id),
        intents: profile.intents_json,
        topics: profile.topics_json,
        confidence: clampFloat(profile.confidence, 0, 1, 0.6),
        samples: Number(profile.samples_count || 0),
      })),
    },
    temperature: 0.2,
    maxTokens: 900,
  });

  if (!aiResult.ok) {
    return { summary: fallbackSummary, model: "fallback_rules" };
  }

  return {
    summary: safeText(aiResult.json?.summary, 4000) || fallbackSummary,
    keyLearnings: Array.isArray(aiResult.json?.keyLearnings)
      ? aiResult.json.keyLearnings.map((x) => safeText(x, 240)).filter(Boolean).slice(0, 10)
      : [],
    risks: Array.isArray(aiResult.json?.risks)
      ? aiResult.json.risks.map((x) => safeText(x, 240)).filter(Boolean).slice(0, 10)
      : [],
    nextActions: Array.isArray(aiResult.json?.nextActions)
      ? aiResult.json.nextActions.map((x) => safeText(x, 240)).filter(Boolean).slice(0, 10)
      : [],
    model: aiResult.model || OPENAI_MODEL,
  };
}

export async function getMachineLearningDashboard(query = {}) {
  const observationsLimit = clampInt(query?.observationsLimit, 10, 500, 120);
  const [
    stats,
    advancedStats,
    memoryItems,
    observationItems,
    topFacts,
    userProfiles,
    intentStats,
    redisSnapshot,
  ] = await Promise.all([
    aiRepo.summarizeTrainingMemoryStats(),
    aiRepo.summarizeAdvancedLearningStats(),
    aiRepo.listTrainingMemory({ limit: 30, offset: 0, activeOnly: true }),
    aiRepo.listRecentChatObservations({ limit: observationsLimit }),
    aiRepo.listTopLearningFacts({ scope: "all", limit: 40 }),
    aiRepo.listAiUserLearningProfiles({ limit: 50 }),
    qAi(
      `SELECT
         COALESCE(NULLIF(TRIM(COALESCE(detected_intent, '')), ''), 'unknown') AS intent_key,
         COUNT(*)::int AS total
       FROM ai_chat_observation
       GROUP BY intent_key
       ORDER BY total DESC
       LIMIT 20`
    ),
    getRedisMachineLearningSnapshot({
      recentLimit: Math.min(observationsLimit, 16),
    }),
  ]);

  const learned = await summarizeLearnedFromData({
    memoryItems,
    observationItems,
    stats,
    advancedStats,
    topFacts,
    userProfiles,
  });

  return {
    stats,
    advancedStats,
    learned,
    topIntents: intentStats.rows || [],
    topFacts,
    userProfiles,
    recentMemory: memoryItems,
    recentObservations: observationItems,
    redisSnapshot,
  };
}

export async function summarizeAiLearnedNow() {
  const dashboard = await getMachineLearningDashboard({ observationsLimit: 80 });
  return {
    summary: dashboard.learned?.summary || "",
    keyLearnings: dashboard.learned?.keyLearnings || [],
    risks: dashboard.learned?.risks || [],
    nextActions: dashboard.learned?.nextActions || [],
    model: dashboard.learned?.model || "fallback_rules",
    stats: dashboard.stats || {},
    advancedStats: dashboard.advancedStats || {},
    topFacts: Array.isArray(dashboard.topFacts) ? dashboard.topFacts.slice(0, 12) : [],
  };
}

function buildFallbackLearningAnswer({
  question,
  summary,
  memoryItems,
  topIntents,
}) {
  const intentsText = (topIntents || [])
    .slice(0, 5)
    .map((item) => `${item.intent_key} (${item.total})`)
    .join(", ");
  const memoryLines = (memoryItems || [])
    .slice(0, 5)
    .map((item) => {
      const qText = safeText(item.question, 120) || "";
      const aText = safeText(item.answer, 140) || "";
      return qText && aText ? `• ${qText} => ${aText}` : null;
    })
    .filter(Boolean);

  const answer = [
    `سؤالك: ${safeText(question, 260) || ""}`,
    summary ? `ملخص التعلم الحالي: ${summary}` : null,
    intentsText ? `أكثر النوايا تكرارًا: ${intentsText}` : null,
    memoryLines.length ? `أمثلة من الذاكرة:\n${memoryLines.join("\n")}` : null,
  ]
    .filter(Boolean)
    .join("\n\n");

  return {
    answer,
    confidence: 0.63,
    keyPoints: memoryLines.slice(0, 3),
    model: "fallback_rules",
  };
}

export async function answerAdminLearningQuestion({
  question,
  limit = 8,
}) {
  const safeQuestion = safeText(question, 1000);
  if (!safeQuestion) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: ["question"] },
    });
  }

  const [dashboard, memoryRows] = await Promise.all([
    getMachineLearningDashboard({ observationsLimit: 120 }),
    aiRepo.listTrainingMemory({
      search: safeQuestion,
      limit: clampInt(limit, 1, 30, 8),
      offset: 0,
      activeOnly: true,
    }),
  ]);

  const fallback = buildFallbackLearningAnswer({
    question: safeQuestion,
    summary: safeText(dashboard.learned?.summary, 1200) || "",
    memoryItems: memoryRows,
    topIntents: dashboard.topIntents || [],
  });

  if (!openAiReady()) {
    return {
      question: safeQuestion,
      answer: fallback.answer,
      confidence: fallback.confidence,
      keyPoints: fallback.keyPoints,
      model: fallback.model,
    };
  }

  const aiResult = await callOpenAiJson({
    systemPrompt:
      "You answer a super-admin question about AI learning progress. Return JSON only with schema {answer:string, confidence:number(0..1), keyPoints:string[]}. Keep it factual, concise, and based on provided data only.",
    userPayload: {
      question: safeQuestion,
      learnedSummary: dashboard.learned || {},
      advancedStats: dashboard.advancedStats || {},
      topIntents: dashboard.topIntents || [],
      topFacts: (dashboard.topFacts || []).slice(0, 15).map((fact) => ({
        key: fact.fact_key,
        value: fact.fact_value,
        type: fact.fact_type,
        occurrences: Number(fact.occurrences || 0),
        confidence: clampFloat(fact.confidence, 0, 1, 0.6),
      })),
      profileSamples: (dashboard.userProfiles || []).slice(0, 10).map((profile) => ({
        userId: Number(profile.user_id),
        intents: profile.intents_json,
        topics: profile.topics_json,
        confidence: clampFloat(profile.confidence, 0, 1, 0.6),
      })),
      trainingMemorySample: memoryRows.slice(0, 12).map((item) => ({
        question: safeText(item.question, 220),
        answer: safeText(item.answer, 260),
        source: item.source || "admin_teaching",
        qualityScore: clampFloat(item.quality_score, 0, 1, 0.8),
      })),
    },
    temperature: 0.2,
    maxTokens: 900,
  });

  if (!aiResult.ok) {
    return {
      question: safeQuestion,
      answer: fallback.answer,
      confidence: fallback.confidence,
      keyPoints: fallback.keyPoints,
      model: fallback.model,
    };
  }

  const answer = safeText(aiResult.json?.answer, 8000) || fallback.answer;
  const confidence = clampFloat(aiResult.json?.confidence, 0, 1, 0.78);
  const keyPoints = Array.isArray(aiResult.json?.keyPoints)
    ? aiResult.json.keyPoints.map((item) => safeText(item, 260)).filter(Boolean).slice(0, 8)
    : fallback.keyPoints;

  return {
    question: safeQuestion,
    answer,
    confidence,
    keyPoints,
    model: aiResult.model || OPENAI_MODEL,
  };
}

export async function upsertKnowledgeEntryWithEmbedding({
  sourceType = "faq",
  intentCluster = null,
  language = "ar",
  dialect = null,
  queryText,
  answerText,
  tags = [],
  retrievalWeight = 1,
  isActive = true,
  embedding = null,
} = {}) {
  const safeQuery = safeText(queryText, 4000);
  const safeAnswer = safeText(answerText, 12000);
  if (!safeQuery || !safeAnswer) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: ["queryText", "answerText"] },
    });
  }

  let vector = normalizeEmbeddingVector(embedding);
  if (!vector && AI_KNOWLEDGE_SEMANTIC_ENABLED) {
    vector = await callOpenAiEmbedding(
      `${safeQuery}\n${safeAnswer.slice(0, 2200)}`
    );
  }

  const row = await aiRepo.upsertAiKnowledgeEntry({
    sourceType,
    intentCluster,
    language,
    dialect,
    queryText: safeQuery,
    answerText: safeAnswer,
    tags,
    embedding: vector,
    retrievalWeight,
    isActive,
  });
  return {
    item: row,
    embeddingGenerated: Array.isArray(vector) && vector.length > 0,
  };
}

export async function buildConversationRecallContext({
  customerUserId,
  queryText,
  limit = 5,
} = {}) {
  const safeUserId = Number(customerUserId);
  if (!Number.isInteger(safeUserId) || safeUserId <= 0) {
    return {
      line: null,
      snippets: [],
      topics: [],
      hasHistory: false,
      recallAnswerCandidate: null,
    };
  }

  const normalizedQuery = normalizeLearningText(queryText);
  const queryTokens = tokenizeLearningText(normalizedQuery);
  const wantsRecall =
    /(?:البارحة|أمس|امس|قبل شوي|شنو حكينا|ماذا تحدثنا|what did we talk|yesterday|last time|previous)/iu.test(
      String(queryText || "")
    );

  const conversations = await aiRepo.listAiConversationsV2({
    customerUserId: safeUserId,
    limit: clampInt(limit, 1, 12, 5),
    offset: 0,
  });
  const items = Array.isArray(conversations) ? conversations : [];
  if (!items.length) {
    return {
      line: null,
      snippets: [],
      topics: [],
      hasHistory: false,
      recallAnswerCandidate: wantsRecall
        ? "ما عندي محادثات سابقة محفوظة حتى ألخّصها لك حالياً."
        : null,
    };
  }

  const snippets = items
    .slice(0, 5)
    .map((item) => {
      const summary = safeText(item?.summary, 360);
      const topicList = normalizeTextList(parseJsonSafe(item?.topics_json, []), {
        maxItems: 6,
        maxLen: 80,
      });
      const stamp = safeText(item?.ended_at || item?.started_at, 64);
      return {
        id: Number(item?.id || 0),
        summary,
        topics: topicList,
        stamp,
      };
    })
    .filter((item) => item.summary || item.topics.length);

  const allTopics = normalizeTextList(
    snippets.flatMap((item) => item.topics),
    { maxItems: 10, maxLen: 80 }
  );
  const line = snippets.length
    ? `recent_conversations=${snippets
        .slice(0, 3)
        .map((item) => item.summary || item.topics.join(", "))
        .filter(Boolean)
        .join(" | ")}`
    : null;

  let recallAnswerCandidate = null;
  if (wantsRecall) {
    const ranked = snippets
      .map((item) => {
        const summaryNormalized = normalizeLearningText(item.summary);
        const topicNormalized = normalizeLearningText(item.topics.join(" "));
        const summaryTokens = tokenizeLearningText(
          `${summaryNormalized} ${topicNormalized}`.trim()
        );
        const score =
          jaccardSimilarity(queryTokens, summaryTokens) * 0.55 +
          trigramDiceSimilarity(
            normalizedQuery,
            `${summaryNormalized} ${topicNormalized}`.trim()
          ) *
            0.45;
        return { ...item, score: clampFloat(score, 0, 1, 0) };
      })
      .sort((a, b) => b.score - a.score);

    const top = ranked[0];
    const topSummaries = ranked
      .slice(0, 3)
      .map((item) => item.summary || item.topics.join("، "))
      .filter(Boolean);

    if (topSummaries.length) {
      recallAnswerCandidate =
        top && top.score >= 0.22
          ? `إي، آخر المحادثات كانت عن: ${topSummaries.join(" | ")}. تحب نكمل من أي نقطة؟`
          : `آخر شيء حكينا عنه: ${topSummaries.join(" | ")}. إذا تريد نكمل مباشرة گلي أي موضوع.`;
    }
  }

  return {
    line,
    snippets,
    topics: allTopics,
    hasHistory: true,
    recallAnswerCandidate,
  };
}

export async function resolveKnowledgeAnswer({
  queryText,
  language = "ar",
  dialect = null,
  intentCluster = null,
  lexicalLimit = AI_KNOWLEDGE_LEXICAL_LIMIT,
  semanticCandidatesLimit = AI_KNOWLEDGE_SEMANTIC_CANDIDATES,
  similarityThreshold = AI_KNOWLEDGE_SIMILARITY_THRESHOLD,
} = {}) {
  const safeQuery = safeText(queryText, 2000);
  const normalizedQuery = normalizeLearningText(safeQuery);
  if (!safeQuery || !normalizedQuery) return null;

  const lexicalRows = await aiRepo.searchAiKnowledgeEntries({
    query: safeQuery,
    language: safeText(language, 8),
    dialect: safeText(dialect, 32),
    intentCluster: safeText(intentCluster, 80),
    limit: clampInt(lexicalLimit, 2, 80, AI_KNOWLEDGE_LEXICAL_LIMIT),
  });

  let bestLexical = null;
  if (Array.isArray(lexicalRows) && lexicalRows.length) {
    const queryTokens = tokenizeLearningText(normalizedQuery);
    for (const row of lexicalRows) {
      const question = safeText(row?.query_text, 4000) || "";
      const answer = safeText(row?.answer_text, 9000) || "";
      if (!answer) continue;
      const candidateNormalized = normalizeLearningText(question);
      const lexicalRank = Number(row?.lexical_rank || 0);
      const retrievalWeight = clampFloat(row?.retrieval_weight, 0, 5, 1) / 5;
      const sim =
        jaccardSimilarity(queryTokens, tokenizeLearningText(candidateNormalized)) * 0.45 +
        trigramDiceSimilarity(normalizedQuery, candidateNormalized) * 0.35 +
        clampFloat(lexicalRank, 0, 1, 0) * 0.2;
      const score = clampFloat(sim + retrievalWeight * 0.08, 0, 1, 0);
      if (!bestLexical || score > bestLexical.score) {
        bestLexical = { row, score };
      }
    }
  }

  let bestSemantic = null;
  if (AI_KNOWLEDGE_SEMANTIC_ENABLED) {
    const queryEmbedding = await callOpenAiEmbedding(safeQuery);
    if (Array.isArray(queryEmbedding) && queryEmbedding.length) {
      const semanticRows = await aiRepo.listAiKnowledgeSemanticCandidates({
        language: safeText(language, 8),
        dialect: safeText(dialect, 32),
        intentCluster: safeText(intentCluster, 80),
        limit: clampInt(
          semanticCandidatesLimit,
          20,
          2000,
          AI_KNOWLEDGE_SEMANTIC_CANDIDATES
        ),
      });
      for (const row of semanticRows || []) {
        const embedding = normalizeEmbeddingVector(row?.embedding_json);
        if (!embedding) continue;
        const answer = safeText(row?.answer_text, 9000);
        if (!answer) continue;
        const cosine = cosineSimilarity(queryEmbedding, embedding);
        const retrievalWeight = clampFloat(row?.retrieval_weight, 0, 5, 1) / 5;
        const score = clampFloat(cosine * 0.88 + retrievalWeight * 0.12, 0, 1, 0);
        if (!bestSemantic || score > bestSemantic.score) {
          bestSemantic = { row, score, cosine };
        }
      }
    }
  }

  const threshold = clampFloat(
    similarityThreshold,
    0.35,
    0.98,
    AI_KNOWLEDGE_SIMILARITY_THRESHOLD
  );
  const candidate =
    bestSemantic && bestSemantic.score >= threshold
      ? {
          row: bestSemantic.row,
          score: bestSemantic.score,
          foundBy: "knowledge_semantic",
          similarity: bestSemantic.cosine,
        }
      : bestLexical && bestLexical.score >= threshold
      ? {
          row: bestLexical.row,
          score: bestLexical.score,
          foundBy: "knowledge_lexical",
          similarity: bestLexical.score,
        }
      : null;

  if (!candidate) return null;

  return {
    ok: true,
    foundBy: candidate.foundBy,
    knowledgeId: Number(candidate.row?.id || 0),
    answer: safeText(candidate.row?.answer_text, 9000),
    question: safeText(candidate.row?.query_text, 2400),
    confidence: clampFloat(0.58 + candidate.score * 0.36, 0, 0.97, 0.78),
    similarityScore: clampFloat(candidate.similarity, 0, 1, 0.7),
    source: candidate.row?.source_type || "knowledge",
    intentCluster: safeText(candidate.row?.intent_cluster, 80),
    tags: normalizeTextList(parseJsonSafe(candidate.row?.tags_json, []), {
      maxItems: 12,
      maxLen: 80,
    }),
  };
}

export async function buildPromptMemoryContext({
  customerUserId,
  queryText,
  limit = 6,
}) {
  const memoryRows = await aiRepo.listTrainingMemoryForPrompt({
    queryText: safeText(queryText, 400) || "",
    limit: clampInt(limit, 1, 20, 6),
    ownerUserId: Number(customerUserId),
  });
  return memoryRows.map((row) => ({
    id: Number(row.id),
    question: safeText(row.question, 600),
    answer: safeText(row.answer, 900),
    score: clampFloat(row.relevance_score, 0, 5, 0),
    qualityScore: clampFloat(row.quality_score, 0, 1, 0.8),
    source: row.source || "admin_teaching",
  }));
}

function scoreMemoryCandidate({
  row,
  queryNormalized,
  queryTokens,
}) {
  const question = safeText(row?.question, 2000) || "";
  const answer = safeText(row?.answer, 2500) || "";
  const candidateNormalized = normalizeLearningText(question);
  if (!candidateNormalized || !queryNormalized) return 0;

  const candidateTokens = tokenizeLearningText(candidateNormalized);
  const jaccard = jaccardSimilarity(queryTokens, candidateTokens);
  const dice = trigramDiceSimilarity(queryNormalized, candidateNormalized);
  const includesBoost =
    candidateNormalized.includes(queryNormalized) || queryNormalized.includes(candidateNormalized)
      ? 0.25
      : 0;
  const relevance = clampFloat(row?.score ?? row?.relevance_score, 0, 5, 0) / 5;
  const quality = clampFloat(row?.qualityScore ?? row?.quality_score, 0, 1, 0.75);
  const answerLengthBoost = answer.length >= 18 ? 0.06 : 0;

  return clampFloat(
    jaccard * 0.42 +
      dice * 0.28 +
      relevance * 0.12 +
      quality * 0.12 +
      includesBoost +
      answerLengthBoost,
    0,
    1,
    0
  );
}

export async function resolveStoredQaAnswer({
  customerUserId,
  queryText,
  limit = 60,
  similarThreshold = 0.48,
}) {
  const question = safeText(queryText, 1600);
  const queryNormalized = normalizeLearningText(question);
  if (!question || !queryNormalized) return null;

  const rows = await aiRepo.listTrainingMemoryForPrompt({
    queryText: question,
    limit: clampInt(limit, 10, 200, 60),
    ownerUserId: Number(customerUserId),
  });
  if (!Array.isArray(rows) || rows.length === 0) return null;

  const exact = rows.find((row) => {
    const candidate = normalizeLearningText(row?.question);
    return candidate && candidate === queryNormalized;
  });
  if (exact && safeText(exact.answer, 8000)) {
    return {
      ok: true,
      foundBy: "exact",
      memoryId: Number(exact.id),
      answer: safeText(exact.answer, 8000),
      question: safeText(exact.question, 1200),
      confidence: 0.98,
      qualityScore: clampFloat(exact.quality_score, 0, 1, 0.85),
      source: exact.source || "training_memory",
    };
  }

  const queryTokens = tokenizeLearningText(queryNormalized);
  let best = null;
  for (const row of rows) {
    const candidateAnswer = safeText(row?.answer, 8000);
    if (!candidateAnswer) continue;
    const score = scoreMemoryCandidate({
      row,
      queryNormalized,
      queryTokens,
    });
    if (!best || score > best.score) {
      best = { row, score };
    }
  }

  if (!best || best.score < clampFloat(similarThreshold, 0.2, 0.95, 0.48)) {
    return null;
  }

  return {
    ok: true,
    foundBy: "similar",
    memoryId: Number(best.row.id),
    answer: safeText(best.row.answer, 8000),
    question: safeText(best.row.question, 1200),
    confidence: clampFloat(0.55 + best.score * 0.4, 0, 0.95, 0.72),
    qualityScore: clampFloat(best.row.quality_score, 0, 1, 0.78),
    similarityScore: clampFloat(best.score, 0, 1, 0.6),
    source: best.row.source || "training_memory",
  };
}

export async function storeAnsweredQaPair({
  customerUserId,
  question,
  answer,
  source = "chat_runtime",
  qualityScore = 0.82,
  tags = [],
}) {
  const safeQuestion = safeText(question, 4000);
  const safeAnswer = safeText(answer, 9000);
  if (!safeQuestion || !safeAnswer) return { saved: false, reason: "invalid_input" };

  const queryNormalized = normalizeLearningText(safeQuestion);
  const answerNormalized = normalizeLearningText(safeAnswer);
  if (!queryNormalized || !answerNormalized) {
    return { saved: false, reason: "empty_normalized" };
  }

  const rows = await aiRepo.listTrainingMemoryForPrompt({
    queryText: safeQuestion,
    limit: 20,
    ownerUserId: Number(customerUserId),
  });

  const exact = (rows || []).find((row) => {
    const rowQuestion = normalizeLearningText(row?.question);
    return rowQuestion && rowQuestion === queryNormalized;
  });

  const normalizedTags = Array.isArray(tags)
    ? tags.map((tag) => safeText(tag, 48)).filter(Boolean).slice(0, 20)
    : [];

  if (exact) {
    const existingAnswer = normalizeLearningText(exact.answer);
    if (existingAnswer === answerNormalized) {
      await aiRepo.updateTrainingMemoryEntryById({
        id: Number(exact.id),
        source,
        qualityScore: clampFloat(qualityScore, 0, 1, 0.82),
        tags: normalizedTags,
      });
      return { saved: true, action: "refreshed", id: Number(exact.id) };
    }

    const updated = await aiRepo.updateTrainingMemoryEntryById({
      id: Number(exact.id),
      answer: safeAnswer,
      source,
      qualityScore: clampFloat(qualityScore, 0, 1, 0.82),
      tags: normalizedTags,
    });
    return {
      saved: Boolean(updated),
      action: "updated",
      id: Number(updated?.id || exact.id),
    };
  }

  const inserted = await aiRepo.insertTrainingMemory({
    scope: "user",
    ownerUserId: Number(customerUserId),
    question: safeQuestion,
    answer: safeAnswer,
    tags: normalizedTags,
    source: safeText(source, 24) || "chat_runtime",
    qualityScore: clampFloat(qualityScore, 0, 1, 0.82),
    isActive: true,
    createdByUserId: null,
  });

  return {
    saved: Boolean(inserted),
    action: "inserted",
    id: Number(inserted?.id || 0),
  };
}

export async function buildAdaptiveLearningContext({
  customerUserId,
  queryText,
  factLimit = 12,
}) {
  const safeUserId = Number(customerUserId);
  if (!Number.isInteger(safeUserId) || safeUserId <= 0) {
    return {
      profile: null,
      facts: [],
      line: null,
      snippets: [],
    };
  }

  const redisSnapshot = await getRedisAdaptiveLearningSnapshot({
    customerUserId: safeUserId,
    recentLimit: 5,
  });

  let profile = null;
  let facts = [];
  try {
    [profile, facts] = await Promise.all([
      aiRepo.getAiUserLearningProfile(safeUserId),
      aiRepo.listTopLearningFacts({
        scope: "user",
        customerUserId: safeUserId,
        limit: clampInt(factLimit, 4, 40, 12),
      }),
    ]);
  } catch (_) {
    profile = null;
    facts = [];
  }

  const intentTop = Object.entries(normalizeCounterObject(profile?.intents_json))
    .sort((a, b) => b[1] - a[1])
    .slice(0, 3)
    .map(([key]) => key);
  const topicTop = Object.entries(normalizeCounterObject(profile?.topics_json))
    .sort((a, b) => b[1] - a[1])
    .slice(0, 4)
    .map(([key]) => key);
  const languageTop = Object.entries(normalizeCounterObject(profile?.language_json))
    .sort((a, b) => b[1] - a[1])[0]?.[0];

  const factSnippets = (facts || [])
    .slice(0, 8)
    .map((fact) => {
      const key = safeText(fact.fact_key, 60);
      const value = safeText(fact.fact_value, 100);
      if (!key || !value) return null;
      return `${key}: ${value}`;
    })
    .filter(Boolean);

  const profileParts = [
    intentTop.length ? `intent=${intentTop.join(",")}` : null,
    topicTop.length ? `topic=${topicTop.join(",")}` : null,
    languageTop ? `lang=${languageTop}` : null,
    profile?.style_signature ? `style=${safeText(profile.style_signature, 40)}` : null,
    !intentTop.length &&
    !topicTop.length &&
    redisSnapshot?.profileParts?.length
        ? redisSnapshot.profileParts.join(" | ")
        : null,
  ].filter(Boolean);

  const mergedFactSnippets = factSnippets.length
    ? factSnippets
    : Array.isArray(redisSnapshot?.snippets)
        ? redisSnapshot.snippets
        : [];

  const lineParts = [
    profileParts.length ? `learned_profile(${profileParts.join(" | ")})` : null,
    mergedFactSnippets.length
      ? `learned_facts(${mergedFactSnippets.slice(0, 3).join(" | ")})`
      : null,
    queryText ? `query=${safeText(queryText, 200)}` : null,
  ].filter(Boolean);

  if (!lineParts.length && redisSnapshot?.line) {
    lineParts.push(redisSnapshot.line);
  }

  const line = lineParts.join(" ; ");

  return {
    profile: profile || null,
    facts: facts || [],
    line: line || null,
    snippets: mergedFactSnippets,
    redisSnapshot: redisSnapshot || null,
  };
}

function summarizeConversationTurn({
  userMessage,
  assistantReply,
  topics = [],
  intent = null,
  mode = null,
}) {
  const safeUser = safeText(userMessage, 280) || "";
  const safeReply = safeText(assistantReply, 500) || "";
  const safeTopics = normalizeTextList(topics, { maxItems: 6, maxLen: 80 });
  const parts = [];
  if (safeUser) parts.push(`U: ${safeUser}`);
  if (safeReply) parts.push(`A: ${safeReply}`);
  if (safeTopics.length) parts.push(`topics=${safeTopics.join(", ")}`);
  if (intent) parts.push(`intent=${safeText(intent, 40)}`);
  if (mode) parts.push(`mode=${safeText(mode, 40)}`);
  return parts.join(" | ").slice(0, AI_MEMORY_CONVERSATION_SUMMARY_MAXLEN);
}

async function captureV2MemoryTurn({
  sessionId,
  customerUserId,
  userMessage,
  assistantReply,
  language = null,
  detectedIntent = null,
  conversationMode = null,
  signals = null,
  metadata = null,
}) {
  const profile = await getOrCreateAiUserProfile(customerUserId);
  const consentFlags = normalizeConsentFlags(profile?.consent_flags_json);
  const inferredDialect = inferDialectFromMessage(userMessage, language);
  const extractedNames = extractUserNamesFromMessage(userMessage);
  const topicList = normalizeTextList(
    Array.isArray(signals?.extractedTopics) ? signals.extractedTopics : [],
    { maxItems: 16, maxLen: 80 }
  );

  const nextLanguage = safeText(language, 8) || profile?.preferred_language || "ar";
  const nextProfilePatch = {
    customerUserId,
    preferredLanguage: nextLanguage,
    dialect: inferredDialect || profile?.dialect || "iraqi",
  };

  if (!profile?.display_name && extractedNames.realName) {
    nextProfilePatch.displayName = extractedNames.realName;
    nextProfilePatch.realName = extractedNames.realName;
  }
  if (!profile?.nickname && extractedNames.nickname) {
    nextProfilePatch.nickname = extractedNames.nickname;
  }

  await aiRepo.upsertAiUserProfileV2(nextProfilePatch);

  const conversation = await aiRepo.upsertAiConversationV2({
    customerUserId,
    sessionId: asIntSafe(sessionId, 0) > 0 ? Number(sessionId) : null,
    title: conversationTitleFromText(userMessage, nextLanguage),
    summary: summarizeConversationTurn({
      userMessage,
      assistantReply,
      topics: topicList,
      intent: detectedIntent,
      mode: conversationMode,
    }),
    topics: topicList,
    sentiment: safeText(signals?.derivedSignals?.sentiment || metadata?.sentiment, 24),
    importantNotes: normalizeTextList(
      [
        extractedNames.realName ? `real_name:${extractedNames.realName}` : null,
        extractedNames.nickname ? `nickname:${extractedNames.nickname}` : null,
        detectedIntent ? `intent:${detectedIntent}` : null,
        conversationMode ? `mode:${conversationMode}` : null,
      ].filter(Boolean),
      { maxItems: 8, maxLen: 160 }
    ),
  });

  if (!conversation?.id) return;

  let userMessageRow = null;
  let assistantMessageRow = null;
  const shouldCaptureRaw =
    AI_MEMORY_CAPTURE_RAW_MESSAGES &&
    (consentFlags.adminReview || consentFlags.improveModel || consentFlags.memoryEnabled);
  if (shouldCaptureRaw) {
    userMessageRow = await aiRepo.appendAiMessageV2({
      conversationId: Number(conversation.id),
      customerUserId,
      role: "user",
      messageText: userMessage,
      messageType: "text",
      metadata: {
        source: "assistant_chat",
        detectedIntent: safeText(detectedIntent, 64),
        conversationMode: safeText(conversationMode, 40),
      },
    });
    assistantMessageRow = await aiRepo.appendAiMessageV2({
      conversationId: Number(conversation.id),
      customerUserId,
      role: "assistant",
      messageText: assistantReply,
      messageType: "text",
      metadata: {
        source: "assistant_chat",
        detectedIntent: safeText(detectedIntent, 64),
        conversationMode: safeText(conversationMode, 40),
      },
    });
  }

  if (consentFlags.personalization || consentFlags.memoryEnabled) {
    await Promise.all(
      topicList.map((topic) =>
        aiRepo.upsertAiUserTopicV2({
          customerUserId,
          topicName: topic,
          topicCategory:
            topic.includes("job") || topic.includes("وظيف")
              ? "jobs"
              : topic.includes("taxi") || topic.includes("تكسي")
              ? "taxi"
              : topic.includes("store") || topic.includes("مطعم")
              ? "commerce"
              : "general",
          scoreDelta: 1,
          mentionDelta: 1,
          discussedAt: new Date().toISOString(),
        })
      )
    );
  }

  if (consentFlags.memoryEnabled) {
    if (extractedNames.realName) {
      await aiRepo.insertAiUserMemoryV2({
        customerUserId,
        memoryType: "identity",
        memoryKey: "real_name",
        memoryValue: extractedNames.realName,
        confidenceScore: 0.95,
        sourceConversationId: Number(conversation.id),
        sourceMessageId: userMessageRow?.id ? Number(userMessageRow.id) : null,
        isActive: true,
      });
    }
    if (extractedNames.nickname) {
      await aiRepo.insertAiUserMemoryV2({
        customerUserId,
        memoryType: "identity",
        memoryKey: "nickname",
        memoryValue: extractedNames.nickname,
        confidenceScore: 0.92,
        sourceConversationId: Number(conversation.id),
        sourceMessageId: userMessageRow?.id ? Number(userMessageRow.id) : null,
        isActive: true,
      });
    }
    if (topicList.length) {
      await aiRepo.insertAiUserMemoryV2({
        customerUserId,
        memoryType: "topic",
        memoryKey: "recent_topics",
        memoryValue: topicList.join(", "),
        confidenceScore: 0.66,
        sourceConversationId: Number(conversation.id),
        sourceMessageId: assistantMessageRow?.id ? Number(assistantMessageRow.id) : null,
        isActive: true,
      });
    }
  }

  await aiRepo.upsertAiAdminUserInsightsV2({
    customerUserId,
    generatedSummary: summarizeConversationTurn({
      userMessage,
      assistantReply,
      topics: topicList,
      intent: detectedIntent,
      mode: conversationMode,
    }),
    keyPatterns: topicList,
    productFeedback:
      conversationMode === "recommendation" || conversationMode === "checkout"
        ? [{ intent: detectedIntent, note: safeText(userMessage, 180) }]
        : [],
    serviceRecommendations:
      conversationMode === "open_chat"
        ? []
        : [{ mode: conversationMode, recommendation: safeText(assistantReply, 220) }],
    lastGeneratedAt: new Date().toISOString(),
  });
}

export async function recordChatObservation({
  sessionId,
  customerUserId,
  userMessage,
  assistantReply,
  detectedIntent = null,
  conversationMode = null,
  language = null,
  styleSignature = null,
  modelName = null,
  latencyMs = null,
  tokensPrompt = null,
  tokensCompletion = null,
  metadata = null,
}) {
  try {
    const baseSignals = deriveLearningSignalsLight({
      userMessage,
      assistantReply,
      detectedIntent,
      conversationMode,
      language,
      styleSignature,
      metadata,
    });
    const { signals, deepModel } = await enrichLearningSignalsWithOpenAi(baseSignals, {
      userMessage,
      assistantReply,
      detectedIntent,
      conversationMode,
      language,
      metadata,
    });

    const observation = await aiRepo.insertChatObservation({
      sessionId,
      customerUserId,
      userMessage,
      assistantReply,
      detectedIntent,
      conversationMode,
      language,
      styleSignature,
      modelName,
      latencyMs,
      tokensPrompt,
      tokensCompletion,
      metadata,
      normalizedUserMessage: signals.normalizedUserMessage,
      messageHash: signals.messageHash,
      intentConfidence: signals.intentConfidence,
      extractionConfidence: signals.extractionConfidence,
      qualityScore: signals.qualityScore,
      responseQuality: signals.responseQuality,
      extractedEntities: signals.extractedEntities,
      extractedSlots: signals.extractedSlots,
      extractedTopics: signals.extractedTopics,
      derivedSignals: signals.derivedSignals,
      originChannel: signals.originChannel,
      assistantAction: signals.assistantAction,
      learningVersion: signals.learningVersion,
      learnedAt: signals.learnedAt,
    });

    if (observation?.id) {
      if (deepModel) {
        await aiRepo.upsertAiLearningFacts({
          customerUserId,
          scope: "user",
          sourceObservationId: Number(observation.id),
          facts: [
            {
              key: "deep_parse_model",
              value: deepModel,
              type: "system",
              confidence: 0.95,
            },
          ],
        });
      }
      await persistLearningProjection({
        customerUserId,
        observationId: Number(observation.id),
        styleSignature,
        signals,
      });

      await maybePromoteObservationToMemory({
        customerUserId,
        userMessage,
        assistantReply,
        qualityScore: signals.qualityScore,
        responseQuality: signals.responseQuality,
        extractedTopics: signals.extractedTopics || [],
      });

      await recordRedisObservationSnapshot({
        observationId: Number(observation.id),
        customerUserId,
        detectedIntent: signals?.detectedIntent || detectedIntent,
        qualityScore: signals?.qualityScore,
        responseQuality: signals?.responseQuality,
        language: signals?.language || language,
        conversationMode: signals?.conversationMode || conversationMode,
        extractedTopics: signals?.extractedTopics || [],
        userMessage,
        assistantReply,
      });
    }

    await captureV2MemoryTurn({
      sessionId,
      customerUserId,
      userMessage,
      assistantReply,
      language,
      detectedIntent,
      conversationMode,
      signals,
      metadata,
    });
  } catch (error) {
    console.error("[assistant-ai] failed to insert chat observation", {
      error: String(error?.message || error),
      sessionId,
      customerUserId,
    });
  }
}

const IDLE_LEARNING_SEED_QUERIES = [
  "أفضل طرق تحسين خدمة العملاء في المتاجر",
  "كيفية تقليل وقت توصيل الطلبات",
  "إدارة جودة المنشورات في المجتمعات المحلية",
  "نصائح مقابلات العمل في العراق",
  "how to improve delivery customer satisfaction",
  "كيفية كتابة إعلان وظيفة احترافي",
  "best practices for taxi ride safety",
  "خفض نسبة إلغاء الطلبات في تطبيقات التوصيل",
];

export function startAiIdleLearningWorker() {
  if (!AI_WEB_AUTO_LEARN_ENABLED) return;
  if (idleLearningTimer) return;

  const intervalMs = AI_IDLE_LEARNING_INTERVAL_SEC * 1000;
  idleLearningTimer = setInterval(async () => {
    try {
      const activity = await qAi(
        `SELECT COUNT(*)::int AS total
         FROM ai_chat_observation
         WHERE created_at >= NOW() - ($1::int * INTERVAL '1 minute')`,
        [AI_IDLE_LEARNING_IDLE_WINDOW_MIN]
      );
      const activeChats = Number(activity.rows[0]?.total || 0);
      if (activeChats > 0) return;

      const selectedQueries = IDLE_LEARNING_SEED_QUERIES.slice(
        0,
        Math.min(IDLE_LEARNING_SEED_QUERIES.length, AI_WEB_AUTO_LEARN_MAX_QUERIES)
      );
      const result = await runAutoWebLearning({
        seedQueries: selectedQueries,
        actorUserId: null,
        maxQueries: AI_WEB_AUTO_LEARN_MAX_QUERIES,
      });
      if (result?.ok) {
        console.log(
          `[assistant-ai] idle web learning run inserted=${Number(
            result.inserted || 0
          )} scanned=${Number(result.scanned || 0)}`
        );
      }
    } catch (error) {
      console.error(
        "[assistant-ai] idle web learning failed:",
        String(error?.message || error)
      );
    }
  }, intervalMs);

  if (typeof idleLearningTimer.unref === "function") {
    idleLearningTimer.unref();
  }
}

function getBaghdadCycleMeta(now = new Date()) {
  const hour = Number(
    new Intl.DateTimeFormat("en-GB", {
      hour: "2-digit",
      hour12: false,
      timeZone: "Asia/Baghdad",
    }).format(now)
  );
  const cycleDate = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Baghdad",
  }).format(now);
  return { hour, cycleDate };
}

async function withDailyLearningLock(fn) {
  const lock = await qAi(
    `SELECT pg_try_advisory_lock($1)::boolean AS ok`,
    [AI_DAILY_LEARNING_LOCK_KEY]
  );
  if (!lock.rows[0]?.ok) {
    return { ok: false, skipped: true, reason: "locked" };
  }

  try {
    return await fn();
  } finally {
    try {
      await qAi(`SELECT pg_advisory_unlock($1)`, [AI_DAILY_LEARNING_LOCK_KEY]);
    } catch (error) {
      console.error(
        "[assistant-ai] daily lock release failed:",
        String(error?.message || error)
      );
    }
  }
}

async function pruneDailyMemoryIfNeeded() {
  const current = await qAi(
    `SELECT COUNT(*)::bigint AS total FROM ai_training_memory`
  );
  const total = Number(current.rows[0]?.total || 0);
  if (!AI_DAILY_MEMORY_PRUNE_ENABLED) {
    return { enabled: false, totalBefore: total, deleted: 0 };
  }
  if (total <= AI_DAILY_MEMORY_MAX_ROWS) {
    return {
      enabled: true,
      totalBefore: total,
      deleted: 0,
      totalAfter: total,
    };
  }

  const targetDelete = total - AI_DAILY_MEMORY_MAX_ROWS;
  let deleted = 0;

  while (deleted < targetDelete) {
    const chunk = Math.min(
      AI_DAILY_MEMORY_PRUNE_BATCH,
      targetDelete - deleted
    );
    const result = await qAi(
      `WITH victims AS (
         SELECT id
         FROM ai_training_memory
         ORDER BY id ASC
         LIMIT $1
       )
       DELETE FROM ai_training_memory m
       USING victims v
       WHERE m.id = v.id`,
      [chunk]
    );
    const removed = Number(result.rowCount || 0);
    deleted += removed;
    if (removed === 0) break;
  }

  await qAi(`ANALYZE ai_training_memory`);

  const after = await qAi(
    `SELECT COUNT(*)::bigint AS total FROM ai_training_memory`
  );
  return {
    enabled: true,
    totalBefore: total,
    deleted,
    totalAfter: Number(after.rows[0]?.total || 0),
  };
}

function buildSyntheticDailyEntries({
  rowsTarget = 0,
  actorUserId = null,
}) {
  const target = Math.max(0, Number(rowsTarget) || 0);
  if (target === 0) return [];

  const intents = [
    "shopping",
    "food",
    "taxi",
    "community",
    "jobs",
    "billing",
  ];
  const tones = ["friendly_iraqi", "formal_ar", "quick_help"];
  const entries = [];

  for (let i = 0; i < target; i += 1) {
    const topic = IDLE_LEARNING_SEED_QUERIES[i % IDLE_LEARNING_SEED_QUERIES.length];
    const intent = intents[i % intents.length];
    const tone = tones[i % tones.length];
    entries.push({
      scope: "global",
      ownerUserId: null,
      question: `Daily synthetic #${i + 1}: ${topic}`,
      answer:
        `Response style=${tone}. Intent=${intent}. Prioritize clear Iraqi Arabic guidance with concise action steps.`,
      tags: ["daily_synthetic", intent, tone],
      source: "daily_synthetic",
      qualityScore: 0.75,
      isActive: true,
      createdByUserId: actorUserId,
    });
  }

  return entries;
}

async function runDailySyntheticLearning({
  actorUserId = null,
}) {
  const conversations = Math.max(
    0,
    Number(AI_DAILY_LEARNING_SYNTHETIC_CONVERSATIONS) || 0
  );
  const turns = Math.max(0, Number(AI_DAILY_LEARNING_SYNTHETIC_TURNS) || 0);
  if (conversations === 0 || turns === 0 || AI_DAILY_SYNTHETIC_MAX_ROWS === 0) {
    return {
      enabled: false,
      requestedRows: 0,
      inserted: 0,
      cap: AI_DAILY_SYNTHETIC_MAX_ROWS,
    };
  }

  const requestedRows = conversations * 2;
  const rowsTarget = Math.min(requestedRows, AI_DAILY_SYNTHETIC_MAX_ROWS);
  const entries = buildSyntheticDailyEntries({
    rowsTarget,
    actorUserId,
  });
  if (entries.length === 0) {
    return {
      enabled: true,
      requestedRows,
      inserted: 0,
      cap: AI_DAILY_SYNTHETIC_MAX_ROWS,
    };
  }

  const inserted = await aiRepo.insertTrainingMemoryBatch(entries);
  return {
    enabled: true,
    requestedRows,
    inserted: Number(inserted?.inserted || 0),
    cap: AI_DAILY_SYNTHETIC_MAX_ROWS,
  };
}

export async function runAiDailyLearningCycle({
  force = false,
  triggerSource = "system",
  triggeredByUserId = null,
} = {}) {
  if (!AI_DAILY_LEARNING_ENABLED && !force) {
    return { ok: false, skipped: true, reason: "disabled" };
  }

  const { hour, cycleDate } = getBaghdadCycleMeta();
  if (!force && hour !== AI_DAILY_LEARNING_HOUR_BAGHDAD) {
    return {
      ok: false,
      skipped: true,
      reason: "outside_hour_window",
      cycleDate,
      hour,
    };
  }

  return withDailyLearningLock(async () => {
    const latest = await aiRepo.getLatestLearningCycleRun({
      cycleType: "daily",
      cycleDate,
    });

    if (
      !force &&
      latest &&
      ["running", "success"].includes(
        String(latest.status || "").trim().toLowerCase()
      )
    ) {
      return {
        ok: true,
        skipped: true,
        reason: "already_ran",
        cycleDate,
        runId: Number(latest.id),
      };
    }

    const run = await aiRepo.createLearningCycleRun({
      cycleType: "daily",
      cycleDate,
      triggerSource,
      triggeredByUserId,
      notes: `Daily cycle for ${cycleDate}`,
      meta: {
        maxQueries: AI_DAILY_LEARNING_MAX_QUERIES,
        syntheticConversations: AI_DAILY_LEARNING_SYNTHETIC_CONVERSATIONS,
        syntheticTurns: AI_DAILY_LEARNING_SYNTHETIC_TURNS,
        syntheticCapRows: AI_DAILY_SYNTHETIC_MAX_ROWS,
      },
    });

    let scannedQueries = 0;
    let insertedMemories = 0;
    let pruneMeta = null;
    let webMeta = null;
    let syntheticMeta = null;

    try {
      pruneMeta = await pruneDailyMemoryIfNeeded();

      const seedQueries = IDLE_LEARNING_SEED_QUERIES.slice(
        0,
        Math.min(IDLE_LEARNING_SEED_QUERIES.length, AI_DAILY_LEARNING_MAX_QUERIES)
      );

      webMeta = await runAutoWebLearning({
        seedQueries,
        actorUserId: triggeredByUserId,
        maxQueries: AI_DAILY_LEARNING_MAX_QUERIES,
      });
      scannedQueries += Number(webMeta?.scanned || 0);
      insertedMemories += Number(webMeta?.inserted || 0);

      syntheticMeta = await runDailySyntheticLearning({
        actorUserId: triggeredByUserId,
      });
      insertedMemories += Number(syntheticMeta?.inserted || 0);

      await aiRepo.finishLearningCycleRun({
        runId: Number(run.id),
        status: "success",
        scannedQueries,
        insertedMemories,
        meta: {
          prune: pruneMeta,
          web: webMeta,
          synthetic: syntheticMeta,
        },
      });

      await recordRedisDailyCycleSnapshot({
        runId: Number(run.id),
        cycleDate,
        scannedQueries,
        insertedMemories,
        status: "success",
      });

      return {
        ok: true,
        runId: Number(run.id),
        cycleDate,
        scannedQueries,
        insertedMemories,
        prune: pruneMeta,
        web: webMeta,
        synthetic: syntheticMeta,
      };
    } catch (error) {
      await aiRepo.finishLearningCycleRun({
        runId: Number(run.id),
        status: "failed",
        scannedQueries,
        insertedMemories,
        notes: String(error?.message || error).slice(0, 3000),
        meta: {
          prune: pruneMeta,
          web: webMeta,
          synthetic: syntheticMeta,
        },
      });
      await recordRedisDailyCycleSnapshot({
        runId: Number(run.id),
        cycleDate,
        scannedQueries,
        insertedMemories,
        status: "failed",
      });
      throw error;
    }
  });
}

let lastDailyCycleDate = null;
export function startAiDailyLearningWorker() {
  if (!AI_DAILY_LEARNING_ENABLED) return;
  if (dailyLearningTimer) return;

  const intervalMs = AI_DAILY_LEARNING_TICK_SEC * 1000;
  const tick = async () => {
    try {
      const { hour, cycleDate } = getBaghdadCycleMeta();
      if (hour !== AI_DAILY_LEARNING_HOUR_BAGHDAD) return;
      if (lastDailyCycleDate === cycleDate) return;

      const result = await runAiDailyLearningCycle({
        force: false,
        triggerSource: "scheduler",
        triggeredByUserId: null,
      });

      if (result?.reason === "already_ran" || (result?.ok && !result?.skipped)) {
        lastDailyCycleDate = cycleDate;
      }

      if (result?.ok && !result?.skipped) {
        console.log(
          `[assistant-ai] daily cycle success date=${cycleDate} inserted=${Number(
            result.insertedMemories || 0
          )} scanned=${Number(result.scannedQueries || 0)}`
        );
      }
    } catch (error) {
      console.error(
        "[assistant-ai] daily learning cycle failed:",
        String(error?.message || error)
      );
    }
  };

  dailyLearningTimer = setInterval(() => {
    void tick();
  }, intervalMs);

  if (typeof dailyLearningTimer.unref === "function") {
    dailyLearningTimer.unref();
  }

  void tick();
}

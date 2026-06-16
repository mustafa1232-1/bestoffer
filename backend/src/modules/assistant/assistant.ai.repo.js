import { q as appQ } from "../../config/db.js";
import { aiQ, isAiDbConfigured } from "../../config/aiDb.js";

const AI_DEDICATED_TABLES = new Set([
  "ai_training_memory",
  "ai_training_job",
  "ai_chat_observation",
  "ai_recommendation_snapshot",
  "ai_post_moderation_finding",
  "ai_system_finding",
  "ai_user_learning_profile",
  "ai_learning_fact",
  "ai_learning_cycle_run",
  "ai_user_profiles",
  "ai_conversations",
  "ai_messages",
  "ai_user_memories",
  "ai_user_topics",
  "ai_shared_media",
  "ai_user_preference_history",
  "ai_admin_user_insights",
  "ai_memory_audit_log",
  "ai_knowledge_entry",
]);

const TABLE_REF_PATTERN =
  /\b(?:from|join|update|into|delete\s+from|truncate\s+table)\s+([a-z_][a-z0-9_.]*)/gi;
const CTE_PATTERN = /\b(?:with|,)\s*([a-z_][a-z0-9_]*)\s+as\b/gi;

function extractSqlTableNames(sql) {
  const raw = String(sql || "");
  const names = [];
  let match = TABLE_REF_PATTERN.exec(raw);
  while (match) {
    const relation = String(match[1] || "").trim().toLowerCase();
    if (relation && !relation.startsWith("(")) {
      const tableName = relation.split(".").pop();
      names.push(tableName);
    }
    match = TABLE_REF_PATTERN.exec(raw);
  }
  return names;
}

function extractCteNames(sql) {
  const raw = String(sql || "");
  const names = new Set();
  let match = CTE_PATTERN.exec(raw);
  while (match) {
    const cteName = String(match[1] || "").trim().toLowerCase();
    if (cteName) names.add(cteName);
    match = CTE_PATTERN.exec(raw);
  }
  return names;
}

function shouldRunOnAiDb(sql) {
  if (!isAiDbConfigured()) return false;
  const tableNames = extractSqlTableNames(sql);
  if (!tableNames.length) return false;
  const cteNames = extractCteNames(sql);
  return tableNames.every((name) => AI_DEDICATED_TABLES.has(name) || cteNames.has(name));
}

async function q(text, params) {
  if (shouldRunOnAiDb(text)) {
    return aiQ(text, params);
  }
  return appQ(text, params);
}

function asLimit(value, fallback = 20, max = 200) {
  const n = Number(value);
  if (!Number.isInteger(n) || n <= 0) return fallback;
  return Math.min(n, max);
}

function asOffset(value) {
  const n = Number(value);
  if (!Number.isInteger(n) || n < 0) return 0;
  return n;
}

function asNullablePositiveInt(value) {
  const n = Number(value);
  if (!Number.isInteger(n) || n <= 0) return null;
  return n;
}

function asText(value, max = 2000) {
  const raw = String(value ?? "").trim();
  if (!raw) return null;
  return raw.slice(0, max);
}

function asNullableFloat(value, { min = 0, max = 1 } = {}) {
  if (value === null || value === undefined || value === "") return null;
  const n = Number(value);
  if (!Number.isFinite(n)) return null;
  if (n < min || n > max) return null;
  return n;
}

function asTimestamp(value) {
  if (!value) return null;
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return null;
  return d.toISOString();
}

function asJson(value, fallback = {}) {
  try {
    if (value == null) return JSON.stringify(fallback);
    return JSON.stringify(value);
  } catch (_) {
    return JSON.stringify(fallback);
  }
}

function isMissingPostForeignKeyError(error) {
  if (String(error?.code || "") !== "23503") return false;
  const constraint = String(error?.constraint || "").trim().toLowerCase();
  const detail = String(error?.detail || "").trim().toLowerCase();
  return (
    constraint.includes("post_id") ||
    detail.includes("(post_id)") ||
    detail.includes("table \"social_post\"")
  );
}

export async function listJobsForRecommendations({
  city = null,
  area = null,
  search = "",
  limit = 120,
}) {
  const safeSearch = String(search || "").trim();
  const r = await q(
    `SELECT
       j.id,
       j.title,
       j.company_name,
       j.category,
       j.activity_type,
       j.department,
       j.city,
       j.area,
       j.workplace_type,
       j.employment_type,
       j.experience_level,
       j.salary_min,
       j.salary_max,
       j.salary_currency,
       j.salary_period,
       j.description,
       j.skills,
       j.is_featured,
       j.published_at,
       j.expires_at,
       j.merchant_id,
       m.name AS merchant_name,
       m.type AS merchant_type,
       COUNT(a.id)::int AS applications_count
     FROM job_post j
     LEFT JOIN merchant m ON m.id = j.merchant_id
     LEFT JOIN job_application a ON a.job_id = j.id
     WHERE j.deleted_at IS NULL
       AND j.status = 'active'
       AND (j.expires_at IS NULL OR j.expires_at >= NOW())
       AND ($1::text IS NULL OR j.city = $1::text)
       AND ($2::text IS NULL OR COALESCE(j.area, '') = $2::text)
       AND (
         $3::text = ''
         OR j.title ILIKE ('%' || $3 || '%')
         OR j.company_name ILIKE ('%' || $3 || '%')
         OR j.category ILIKE ('%' || $3 || '%')
         OR COALESCE(j.department, '') ILIKE ('%' || $3 || '%')
         OR COALESCE(j.description, '') ILIKE ('%' || $3 || '%')
       )
     GROUP BY j.id, m.id
     ORDER BY j.is_featured DESC, j.published_at DESC, j.id DESC
     LIMIT $4`,
    [city || null, area || null, safeSearch, asLimit(limit, 120, 500)]
  );
  return r.rows;
}

export async function listCommercePoolForRecommendations({
  kind = "shopping",
  search = "",
  limit = 300,
}) {
  const safeKind = String(kind || "shopping").trim().toLowerCase();
  const safeSearch = String(search || "").trim();
  const foodTypes = ["restaurant", "sweets", "coffee", "bakery", "cafe", "food"];
  const r = await q(
    `SELECT
       p.id AS product_id,
       p.name AS product_name,
       p.description AS product_description,
       p.price AS base_price,
       p.discounted_price,
       COALESCE(p.discounted_price, p.price) AS effective_price,
       p.free_delivery,
       p.offer_label,
       p.image_url AS product_image_url,
       c.name AS category_name,
       m.id AS merchant_id,
       m.name AS merchant_name,
       m.type AS merchant_type,
       m.image_url AS merchant_image_url,
       m.is_open,
       COALESCE(
         AVG(o.merchant_rating) FILTER (
           WHERE o.status = 'delivered'
             AND o.merchant_rating IS NOT NULL
         ),
         0
       )::double precision AS merchant_avg_rating,
       AVG(o.estimated_delivery_minutes) FILTER (
         WHERE o.estimated_delivery_minutes IS NOT NULL
       )::double precision AS merchant_avg_delivery_minutes,
       COUNT(o.id) FILTER (WHERE o.status = 'delivered')::int AS merchant_completed_orders
     FROM product p
     JOIN merchant m ON m.id = p.merchant_id
     LEFT JOIN merchant_category c ON c.id = p.category_id
     LEFT JOIN customer_order o ON o.merchant_id = m.id
     WHERE p.is_available = TRUE
       AND m.is_approved = TRUE
       AND COALESCE(m.is_disabled, FALSE) = FALSE
       AND COALESCE(m.is_open, TRUE) = TRUE
       AND (
         (
           $1::text = 'restaurants'
           AND LOWER(COALESCE(m.type::text, '')) = ANY($2::text[])
         )
         OR (
           $1::text <> 'restaurants'
           AND LOWER(COALESCE(m.type::text, '')) <> ALL($2::text[])
         )
       )
       AND (
         $3::text = ''
         OR p.name ILIKE ('%' || $3 || '%')
         OR COALESCE(p.description, '') ILIKE ('%' || $3 || '%')
         OR m.name ILIKE ('%' || $3 || '%')
         OR COALESCE(c.name, '') ILIKE ('%' || $3 || '%')
       )
     GROUP BY p.id, m.id, c.name
     ORDER BY p.id DESC
     LIMIT $4`,
    [safeKind, foodTypes, safeSearch, asLimit(limit, 300, 1200)]
  );
  return r.rows;
}

export async function saveRecommendationSnapshot({
  customerUserId,
  recommendationType,
  queryText = null,
  items = [],
  modelName = null,
  confidence = 0.6,
}) {
  await q(
    `INSERT INTO ai_recommendation_snapshot
      (
        customer_user_id,
        recommendation_type,
        query_text,
        items_json,
        model_name,
        confidence
      )
     VALUES ($1, $2, $3, $4, $5, $6)`,
    [
      Number(customerUserId),
      String(recommendationType || "generic").trim().slice(0, 32),
      asText(queryText, 2000),
      asJson(items, []),
      asText(modelName, 120),
      Number.isFinite(Number(confidence)) ? Number(confidence) : 0.6,
    ]
  );
}

export async function insertChatObservation({
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
  normalizedUserMessage = null,
  messageHash = null,
  intentConfidence = null,
  extractionConfidence = null,
  qualityScore = null,
  responseQuality = null,
  extractedEntities = null,
  extractedSlots = null,
  extractedTopics = null,
  derivedSignals = null,
  originChannel = null,
  assistantAction = null,
  learningVersion = null,
  learnedAt = null,
}) {
  const r = await q(
    `INSERT INTO ai_chat_observation
      (
        session_id,
        customer_user_id,
        user_message,
        assistant_reply,
        detected_intent,
        conversation_mode,
        language,
        style_signature,
        model_name,
        latency_ms,
        tokens_prompt,
        tokens_completion,
        metadata,
        normalized_user_message,
        message_hash,
        intent_confidence,
        extraction_confidence,
        quality_score,
        response_quality,
        extracted_entities,
        extracted_slots,
        extracted_topics,
        derived_signals,
        origin_channel,
        assistant_action,
        learning_version,
        learned_at
      )
     VALUES (
       $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,
       $14,$15,$16,$17,$18,$19,$20,$21,$22,$23,$24,$25,$26,$27
     )
     RETURNING id, created_at`,
    [
      asNullablePositiveInt(sessionId),
      Number(customerUserId),
      asText(userMessage, 12000) || "",
      asText(assistantReply, 12000) || "",
      asText(detectedIntent, 64),
      asText(conversationMode, 40),
      asText(language, 8),
      asText(styleSignature, 80),
      asText(modelName, 120),
      asNullablePositiveInt(latencyMs),
      asNullablePositiveInt(tokensPrompt),
      asNullablePositiveInt(tokensCompletion),
      metadata == null ? null : asJson(metadata, {}),
      asText(normalizedUserMessage, 12000),
      asText(messageHash, 128),
      asNullableFloat(intentConfidence),
      asNullableFloat(extractionConfidence),
      asNullableFloat(qualityScore),
      asNullableFloat(responseQuality),
      asJson(extractedEntities, {}),
      asJson(extractedSlots, {}),
      asJson(extractedTopics, []),
      asJson(derivedSignals, {}),
      asText(originChannel, 40),
      asText(assistantAction, 64),
      asText(learningVersion, 24),
      asTimestamp(learnedAt),
    ]
  );
  return r.rows[0] || null;
}

export async function getAiUserLearningProfile(customerUserId) {
  const r = await q(
    `SELECT
       user_id,
       intents_json,
       preferences_json,
       topics_json,
       language_json,
       style_signature,
       summary,
       confidence,
       samples_count,
       last_observation_id,
       created_at,
       updated_at
     FROM ai_user_learning_profile
     WHERE user_id = $1
     LIMIT 1`,
    [Number(customerUserId)]
  );
  return r.rows[0] || null;
}

export async function upsertAiUserLearningProfile({
  customerUserId,
  intents = {},
  preferences = {},
  topics = {},
  languages = {},
  styleSignature = null,
  summary = null,
  confidence = 0.6,
  samplesCountIncrement = 1,
  lastObservationId = null,
}) {
  const safeIncrement = Math.max(0, Number(samplesCountIncrement) || 0);
  const r = await q(
    `INSERT INTO ai_user_learning_profile
      (
        user_id,
        intents_json,
        preferences_json,
        topics_json,
        language_json,
        style_signature,
        summary,
        confidence,
        samples_count,
        last_observation_id
      )
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
     ON CONFLICT (user_id)
     DO UPDATE
       SET intents_json = EXCLUDED.intents_json,
           preferences_json = EXCLUDED.preferences_json,
           topics_json = EXCLUDED.topics_json,
           language_json = EXCLUDED.language_json,
           style_signature = COALESCE(EXCLUDED.style_signature, ai_user_learning_profile.style_signature),
           summary = COALESCE(EXCLUDED.summary, ai_user_learning_profile.summary),
           confidence = EXCLUDED.confidence,
           samples_count = ai_user_learning_profile.samples_count + $11::int,
           last_observation_id = COALESCE(EXCLUDED.last_observation_id, ai_user_learning_profile.last_observation_id)
     RETURNING *`,
    [
      Number(customerUserId),
      asJson(intents, {}),
      asJson(preferences, {}),
      asJson(topics, {}),
      asJson(languages, {}),
      asText(styleSignature, 80),
      asText(summary, 12000),
      asNullableFloat(confidence) ?? 0.6,
      safeIncrement,
      asNullablePositiveInt(lastObservationId),
      safeIncrement,
    ]
  );
  return r.rows[0] || null;
}

export async function upsertAiLearningFacts({
  customerUserId = null,
  scope = "user",
  sourceObservationId = null,
  facts = [],
}) {
  const safeScope = ["user", "global", "session"].includes(
    String(scope || "").trim().toLowerCase()
  )
    ? String(scope || "").trim().toLowerCase()
    : "user";
  const userId = asNullablePositiveInt(customerUserId);
  const written = [];
  for (const raw of Array.isArray(facts) ? facts : []) {
    const factKey = asText(raw?.key, 64);
    const factValue = asText(raw?.value, 700);
    if (!factKey || !factValue) continue;

    const factType = asText(raw?.type, 40) || "preference";
    const confidence = asNullableFloat(raw?.confidence) ?? 0.6;
    const metadata = raw?.metadata && typeof raw.metadata === "object" ? raw.metadata : {};

    const existing = await q(
      `SELECT id
       FROM ai_learning_fact
       WHERE is_active = TRUE
         AND COALESCE(customer_user_id, 0) = COALESCE($1, 0)
         AND scope = $2
         AND fact_key = $3
         AND fact_value = $4
       ORDER BY id DESC
       LIMIT 1`,
      [userId, safeScope, factKey, factValue]
    );

    if ((existing.rowCount || 0) > 0) {
      const updated = await q(
        `UPDATE ai_learning_fact
         SET occurrences = occurrences + 1,
             last_seen_at = NOW(),
             confidence = GREATEST(confidence, $2),
             source_observation_id = COALESCE($3, source_observation_id),
             metadata = COALESCE(metadata, '{}'::jsonb) || $4::jsonb
         WHERE id = $1
         RETURNING *`,
        [
          Number(existing.rows[0].id),
          confidence,
          asNullablePositiveInt(sourceObservationId),
          asJson(metadata, {}),
        ]
      );
      if ((updated.rowCount || 0) > 0) {
        written.push(updated.rows[0]);
      }
      continue;
    }

    const inserted = await q(
      `INSERT INTO ai_learning_fact
        (
          customer_user_id,
          scope,
          fact_key,
          fact_value,
          fact_type,
          confidence,
          source_observation_id,
          metadata
        )
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
       RETURNING *`,
      [
        userId,
        safeScope,
        factKey,
        factValue,
        factType,
        confidence,
        asNullablePositiveInt(sourceObservationId),
        asJson(metadata, {}),
      ]
    );
    if ((inserted.rowCount || 0) > 0) {
      written.push(inserted.rows[0]);
    }
  }
  return written;
}

export async function listAdminAiChatSessions({ search = "", limit = 40, offset = 0 }) {
  const safeSearch = String(search || "").trim();
  const r = await q(
    `SELECT
       s.id,
       s.customer_user_id,
       s.title,
       s.last_message_at,
       s.created_at,
       u.full_name,
       u.phone,
       u.ai_chat_review_consent,
       (
         SELECT COUNT(*)::int
         FROM ai_chat_message m
         WHERE m.session_id = s.id
       ) AS messages_count,
       (
         SELECT m.role
         FROM ai_chat_message m
         WHERE m.session_id = s.id
         ORDER BY m.id DESC
         LIMIT 1
       ) AS last_message_role,
       (
         SELECT m.text
         FROM ai_chat_message m
         WHERE m.session_id = s.id
         ORDER BY m.id DESC
         LIMIT 1
       ) AS last_message_text
     FROM ai_chat_session s
     JOIN app_user u ON u.id = s.customer_user_id
     WHERE COALESCE(u.ai_chat_review_consent, TRUE) = TRUE
       AND (
         $1::text = ''
         OR u.full_name ILIKE ('%' || $1 || '%')
         OR u.phone ILIKE ('%' || $1 || '%')
         OR COALESCE(s.title, '') ILIKE ('%' || $1 || '%')
       )
     ORDER BY s.last_message_at DESC, s.id DESC
     LIMIT $2
     OFFSET $3`,
    [safeSearch, asLimit(limit, 40, 200), asOffset(offset)]
  );
  return r.rows;
}

export async function countAdminAiChatSessions({ search = "" }) {
  const safeSearch = String(search || "").trim();
  const r = await q(
    `SELECT COUNT(*)::int AS total
     FROM ai_chat_session s
     JOIN app_user u ON u.id = s.customer_user_id
     WHERE COALESCE(u.ai_chat_review_consent, TRUE) = TRUE
       AND (
         $1::text = ''
         OR u.full_name ILIKE ('%' || $1 || '%')
         OR u.phone ILIKE ('%' || $1 || '%')
         OR COALESCE(s.title, '') ILIKE ('%' || $1 || '%')
       )`,
    [safeSearch]
  );
  return Number(r.rows[0]?.total || 0);
}

export async function listAdminAiChatMessages({
  sessionId,
  limit = 80,
  beforeId = null,
}) {
  const r = await q(
    `SELECT
       m.id,
       m.session_id,
       m.role,
       m.text,
       m.metadata,
       m.created_at,
       s.customer_user_id,
       u.full_name,
       u.phone
     FROM ai_chat_message m
     JOIN ai_chat_session s ON s.id = m.session_id
     JOIN app_user u ON u.id = s.customer_user_id
     WHERE m.session_id = $1
       AND COALESCE(u.ai_chat_review_consent, TRUE) = TRUE
       AND ($2::bigint IS NULL OR m.id < $2::bigint)
     ORDER BY m.id DESC
     LIMIT $3`,
    [
      Number(sessionId),
      beforeId == null ? null : Number(beforeId),
      asLimit(limit, 80, 300),
    ]
  );
  return r.rows;
}

export async function insertTrainingMemory({
  scope = "global",
  ownerUserId = null,
  question,
  answer,
  tags = [],
  source = "admin_teaching",
  qualityScore = 0.9,
  isActive = true,
  createdByUserId = null,
}) {
  const r = await q(
    `INSERT INTO ai_training_memory
      (
        scope,
        owner_user_id,
        question,
        answer,
        tags_json,
        source,
        quality_score,
        is_active,
        created_by_user_id
      )
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
     RETURNING *`,
    [
      String(scope || "global").trim().toLowerCase() === "user"
        ? "user"
        : "global",
      asNullablePositiveInt(ownerUserId),
      asText(question, 10000) || "",
      asText(answer, 12000) || "",
      asJson(Array.isArray(tags) ? tags : [], []),
      asText(source, 24) || "admin_teaching",
      Number.isFinite(Number(qualityScore)) ? Number(qualityScore) : 0.9,
      isActive === true,
      asNullablePositiveInt(createdByUserId),
    ]
  );
  return r.rows[0] || null;
}

export async function insertTrainingMemoryBatch(entries = []) {
  if (!Array.isArray(entries) || entries.length === 0) {
    return { inserted: 0 };
  }

  const chunkSize = 400;
  let inserted = 0;
  for (let i = 0; i < entries.length; i += chunkSize) {
    const chunk = entries.slice(i, i + chunkSize);
    const values = [];
    const placeholders = [];
    chunk.forEach((entry, idx) => {
      const base = idx * 9;
      placeholders.push(
        `($${base + 1},$${base + 2},$${base + 3},$${base + 4},$${base + 5},$${base + 6},$${base + 7},$${base + 8},$${base + 9})`
      );
      values.push(
        String(entry?.scope || "global").trim().toLowerCase() === "user"
          ? "user"
          : "global",
        asNullablePositiveInt(entry?.ownerUserId),
        asText(entry?.question, 10000) || "",
        asText(entry?.answer, 12000) || "",
        asJson(Array.isArray(entry?.tags) ? entry.tags : [], []),
        asText(entry?.source, 24) || "synthetic_training",
        Number.isFinite(Number(entry?.qualityScore))
          ? Number(entry.qualityScore)
          : 0.85,
        entry?.isActive !== false,
        asNullablePositiveInt(entry?.createdByUserId)
      );
    });

    await q(
      `INSERT INTO ai_training_memory
        (
          scope,
          owner_user_id,
          question,
          answer,
          tags_json,
          source,
          quality_score,
          is_active,
          created_by_user_id
        )
       VALUES ${placeholders.join(",")}`,
      values
    );
    inserted += chunk.length;
  }

  return { inserted };
}

export async function listTrainingMemory({
  search = "",
  limit = 40,
  offset = 0,
  activeOnly = false,
}) {
  const safeSearch = String(search || "").trim();
  const r = await q(
    `SELECT
       id,
       scope,
       owner_user_id,
       question,
       answer,
       tags_json,
       source,
       quality_score,
       is_active,
       created_by_user_id,
       created_at,
       updated_at
     FROM ai_training_memory
     WHERE ($1::boolean = FALSE OR is_active = TRUE)
       AND (
         $2::text = ''
         OR question ILIKE ('%' || $2 || '%')
         OR answer ILIKE ('%' || $2 || '%')
         OR tags_json::text ILIKE ('%' || $2 || '%')
       )
     ORDER BY updated_at DESC, id DESC
     LIMIT $3
     OFFSET $4`,
    [activeOnly === true, safeSearch, asLimit(limit, 40, 300), asOffset(offset)]
  );
  return r.rows;
}

export async function countTrainingMemory({ search = "", activeOnly = false }) {
  const safeSearch = String(search || "").trim();
  const r = await q(
    `SELECT COUNT(*)::int AS total
     FROM ai_training_memory
     WHERE ($1::boolean = FALSE OR is_active = TRUE)
       AND (
         $2::text = ''
         OR question ILIKE ('%' || $2 || '%')
         OR answer ILIKE ('%' || $2 || '%')
         OR tags_json::text ILIKE ('%' || $2 || '%')
       )`,
    [activeOnly === true, safeSearch]
  );
  return Number(r.rows[0]?.total || 0);
}

export async function listTrainingMemoryForPrompt({
  queryText = "",
  limit = 6,
  ownerUserId = null,
}) {
  const safeQuery = String(queryText || "").trim();
  const r = await q(
    `SELECT
       id,
       scope,
       owner_user_id,
       question,
       answer,
       tags_json,
       source,
       quality_score,
       created_at,
       CASE
         WHEN $1::text = '' THEN 0
         WHEN question ILIKE ('%' || $1 || '%') THEN 3
         WHEN answer ILIKE ('%' || $1 || '%') THEN 2
         WHEN tags_json::text ILIKE ('%' || $1 || '%') THEN 1
         ELSE 0
       END AS relevance_score
     FROM ai_training_memory
     WHERE is_active = TRUE
       AND (
         scope = 'global'
         OR (
           scope = 'user'
           AND owner_user_id = $2
         )
       )
     ORDER BY relevance_score DESC, quality_score DESC, updated_at DESC, id DESC
     LIMIT $3`,
    [safeQuery, asNullablePositiveInt(ownerUserId), asLimit(limit, 6, 30)]
  );
  return r.rows;
}

export async function updateTrainingMemoryEntryById({
  id,
  answer = null,
  source = null,
  qualityScore = null,
  tags = null,
}) {
  const safeId = asNullablePositiveInt(id);
  if (!safeId) return null;
  const hasTags = Array.isArray(tags);
  const r = await q(
    `UPDATE ai_training_memory
        SET answer = COALESCE($2::text, answer),
            source = COALESCE($3::text, source),
            quality_score = CASE
              WHEN $4::numeric IS NULL THEN quality_score
              ELSE GREATEST(quality_score, $4::numeric)
            END,
            tags_json = CASE
              WHEN $5::boolean = FALSE THEN tags_json
              ELSE COALESCE(tags_json, '[]'::jsonb) || $6::jsonb
            END,
            is_active = TRUE,
            updated_at = NOW()
      WHERE id = $1
      RETURNING *`,
    [
      safeId,
      asText(answer, 12000),
      asText(source, 24),
      qualityScore == null ? null : Number(qualityScore),
      hasTags,
      hasTags ? asJson(tags, []) : null,
    ]
  );
  return r.rows[0] || null;
}

export async function summarizeTrainingMemoryStats() {
  const [memoryCount, observationCount] = await Promise.all([
    q(
      `SELECT
         COUNT(*)::int AS total,
         COUNT(*) FILTER (WHERE is_active = TRUE)::int AS active_total,
         COUNT(*) FILTER (WHERE scope = 'global')::int AS global_total,
         COUNT(*) FILTER (WHERE scope = 'user')::int AS user_total
       FROM ai_training_memory`
    ),
    q(
      `SELECT
         COUNT(*)::int AS total,
         COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '24 hours')::int AS last_24h,
         COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '7 days')::int AS last_7d
       FROM ai_chat_observation`
    ),
  ]);

  return {
    memory: memoryCount.rows[0] || {},
    observations: observationCount.rows[0] || {},
  };
}

export async function summarizeAdvancedLearningStats() {
  const [profileStats, factStats] = await Promise.all([
    q(
      `SELECT
         COUNT(*)::int AS total_profiles,
         COUNT(*) FILTER (WHERE samples_count >= 5)::int AS mature_profiles,
         AVG(confidence)::double precision AS avg_confidence,
         SUM(samples_count)::int AS total_samples
       FROM ai_user_learning_profile`
    ),
    q(
      `SELECT
         COUNT(*)::int AS total_facts,
         COUNT(*) FILTER (WHERE scope = 'user')::int AS user_facts,
         COUNT(*) FILTER (WHERE scope = 'global')::int AS global_facts,
         COUNT(*) FILTER (WHERE last_seen_at >= NOW() - INTERVAL '24 hours')::int AS facts_last_24h
       FROM ai_learning_fact
       WHERE is_active = TRUE`
    ),
  ]);

  return {
    profiles: profileStats.rows[0] || {},
    facts: factStats.rows[0] || {},
  };
}

export async function listTopLearningFacts({
  scope = "all",
  customerUserId = null,
  limit = 30,
}) {
  const safeScope = String(scope || "all").trim().toLowerCase();
  const scopeFilter = ["all", "user", "global", "session"].includes(safeScope)
    ? safeScope
    : "all";
  const r = await q(
    `SELECT
       id,
       customer_user_id,
       scope,
       fact_key,
       fact_value,
       fact_type,
       confidence,
       occurrences,
       last_seen_at,
       first_seen_at,
       metadata
     FROM ai_learning_fact
     WHERE is_active = TRUE
       AND ($1::text = 'all' OR scope = $1::text)
       AND ($2::bigint IS NULL OR customer_user_id = $2::bigint)
     ORDER BY occurrences DESC, confidence DESC, last_seen_at DESC, id DESC
     LIMIT $3`,
    [scopeFilter, asNullablePositiveInt(customerUserId), asLimit(limit, 30, 200)]
  );
  return r.rows;
}

export async function listAiUserLearningProfiles({ limit = 40 }) {
  const r = await q(
    `SELECT
       p.user_id,
       p.intents_json,
       p.preferences_json,
       p.topics_json,
       p.language_json,
       p.style_signature,
       p.summary,
       p.confidence,
       p.samples_count,
       p.last_observation_id,
       p.updated_at,
       u.full_name,
       u.phone
     FROM ai_user_learning_profile p
     JOIN app_user u ON u.id = p.user_id
     ORDER BY p.samples_count DESC, p.confidence DESC, p.updated_at DESC
     LIMIT $1`,
    [asLimit(limit, 40, 300)]
  );
  return r.rows;
}

export async function listRecentChatObservations({ limit = 100 }) {
  const r = await q(
    `SELECT
       id,
       session_id,
       customer_user_id,
       user_message,
       assistant_reply,
       detected_intent,
       conversation_mode,
       language,
       style_signature,
       model_name,
       latency_ms,
       tokens_prompt,
       tokens_completion,
       metadata,
       normalized_user_message,
       message_hash,
       intent_confidence,
       extraction_confidence,
       quality_score,
       response_quality,
       extracted_entities,
       extracted_slots,
       extracted_topics,
       derived_signals,
       origin_channel,
       assistant_action,
       learning_version,
       learned_at,
       created_at
     FROM ai_chat_observation
     ORDER BY id DESC
     LIMIT $1`,
    [asLimit(limit, 100, 500)]
  );
  return r.rows;
}

export async function findPostForAiModeration(postId) {
  const r = await q(
    `SELECT
       p.id,
       p.user_id,
       p.post_kind,
       p.caption,
       p.media_url,
       p.media_kind,
       p.audience_scope_type,
       p.audience_scope_code,
       p.created_at,
       p.updated_at,
       u.full_name AS author_full_name,
       u.phone AS author_phone
     FROM social_post p
     JOIN app_user u ON u.id = p.user_id
     WHERE p.id = $1
       AND p.is_deleted = FALSE
       AND p.moderation_status = 'approved'
     LIMIT 1`,
    [Number(postId)]
  );
  return r.rows[0] || null;
}

export async function listRecentPostsForAiScan({ limit = 120 }) {
  const r = await q(
    `SELECT
       p.id,
       p.user_id,
       p.post_kind,
       p.caption,
       p.media_url,
       p.media_kind,
       p.audience_scope_type,
       p.audience_scope_code,
       p.created_at,
       p.updated_at,
       u.full_name AS author_full_name,
       u.phone AS author_phone
     FROM social_post p
     JOIN app_user u ON u.id = p.user_id
     WHERE p.is_deleted = FALSE
       AND p.moderation_status = 'approved'
       AND p.created_at >= NOW() - INTERVAL '14 days'
     ORDER BY p.id DESC
     LIMIT $1`,
    [asLimit(limit, 120, 2000)]
  );
  return r.rows;
}

export async function findOpenAiModerationFindingByPostId(postId) {
  const r = await q(
    `SELECT *
     FROM ai_post_moderation_finding
     WHERE post_id = $1
       AND status = 'open'
     ORDER BY id DESC
     LIMIT 1`,
    [Number(postId)]
  );
  return r.rows[0] || null;
}

export async function createAiPostModerationFinding({
  postId,
  riskLevel,
  reason,
  details = null,
  modelName = null,
  confidence = 0.5,
  payload = null,
  triggeredBy = "auto",
}) {
  try {
    const r = await q(
      `INSERT INTO ai_post_moderation_finding
        (
          post_id,
          risk_level,
          reason,
          details,
          model_name,
          confidence,
          payload,
          triggered_by
        )
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
       RETURNING *`,
      [
        Number(postId),
        String(riskLevel || "medium").trim().toLowerCase(),
        asText(reason, 2000) || "AI moderation finding",
        asText(details, 8000),
        asText(modelName, 120),
        Number.isFinite(Number(confidence)) ? Number(confidence) : 0.5,
        payload == null ? null : asJson(payload, {}),
        asText(triggeredBy, 24) || "auto",
      ]
    );
    return r.rows[0] || null;
  } catch (error) {
    if (isMissingPostForeignKeyError(error)) {
      return null;
    }
    throw error;
  }
}

export async function markAiPostModerationFindingReviewed({
  findingId,
  status,
  actionTaken = null,
  reviewedByUserId = null,
}) {
  const r = await q(
    `UPDATE ai_post_moderation_finding
     SET status = $2,
         action_taken = $3,
         reviewed_at = NOW(),
         reviewed_by_user_id = $4
     WHERE id = $1
     RETURNING *`,
    [
      Number(findingId),
      String(status || "resolved").trim().toLowerCase(),
      asText(actionTaken, 32),
      asNullablePositiveInt(reviewedByUserId),
    ]
  );
  return r.rows[0] || null;
}

export async function upsertAiPostReport({
  postId,
  reason,
  details = null,
  sourceModel = null,
  sourceConfidence = null,
  aiFindingId = null,
}) {
  const existing = await q(
    `SELECT id
     FROM social_post_report
     WHERE post_id = $1
       AND source = 'ai'
     ORDER BY id DESC
     LIMIT 1`,
    [Number(postId)]
  );

  try {
    if ((existing.rowCount || 0) > 0) {
      const reportId = Number(existing.rows[0].id);
      const updated = await q(
        `UPDATE social_post_report
         SET reason = $2,
             details = $3,
             source_model = $4,
             source_confidence = $5,
             ai_finding_id = $6,
             created_at = NOW()
         WHERE id = $1
         RETURNING id`,
        [
          reportId,
          asText(reason, 2000) || "AI report",
          asText(details, 8000),
          asText(sourceModel, 120),
          sourceConfidence == null ? null : Number(sourceConfidence),
          asNullablePositiveInt(aiFindingId),
        ]
      );
      return updated.rows[0] || null;
    }

    const inserted = await q(
      `INSERT INTO social_post_report
        (
          post_id,
          reporter_user_id,
          reason,
          details,
          source,
          source_model,
          source_confidence,
          ai_finding_id
        )
       VALUES ($1, NULL, $2, $3, 'ai', $4, $5, $6)
       RETURNING id`,
      [
        Number(postId),
        asText(reason, 2000) || "AI report",
        asText(details, 8000),
        asText(sourceModel, 120),
        sourceConfidence == null ? null : Number(sourceConfidence),
        asNullablePositiveInt(aiFindingId),
      ]
    );
    return inserted.rows[0] || null;
  } catch (error) {
    if (isMissingPostForeignKeyError(error)) {
      return null;
    }
    throw error;
  }
}

export async function listBackofficeUserIds(limit = 300) {
  const r = await q(
    `SELECT id
     FROM app_user
     WHERE COALESCE(is_account_disabled, FALSE) = FALSE
       AND (
         COALESCE(is_super_admin, FALSE) = TRUE
         OR LOWER(COALESCE(role::text, '')) IN ('admin', 'deputy_admin')
       )
     ORDER BY id DESC
     LIMIT $1`,
    [asLimit(limit, 300, 2000)]
  );
  return r.rows.map((row) => Number(row.id)).filter((id) => id > 0);
}

export async function listAiPostModerationFindings({
  status = "open",
  limit = 80,
  beforeId = null,
}) {
  const safeStatus = String(status || "open").trim().toLowerCase();
  const statusFilter = ["open", "resolved", "ignored", "all"].includes(safeStatus)
    ? safeStatus
    : "open";
  const r = await q(
    `SELECT
       f.id,
       f.post_id,
       f.status,
       f.risk_level,
       f.reason,
       f.details,
       f.model_name,
       f.confidence,
       f.payload,
       f.triggered_by,
       f.action_taken,
       f.reviewed_at,
       f.reviewed_by_user_id,
       f.created_at,
       p.user_id AS author_user_id,
       p.caption,
       p.media_url,
       p.media_kind,
       p.post_kind,
       u.full_name AS author_full_name,
       u.phone AS author_phone
     FROM ai_post_moderation_finding f
     JOIN social_post p ON p.id = f.post_id
     JOIN app_user u ON u.id = p.user_id
     WHERE ($1::text = 'all' OR f.status = $1::text)
       AND ($2::bigint IS NULL OR f.id < $2::bigint)
     ORDER BY f.id DESC
     LIMIT $3`,
    [statusFilter, beforeId == null ? null : Number(beforeId), asLimit(limit, 80, 300)]
  );
  return r.rows;
}

export async function listAiSystemFindings({ status = "open", limit = 80 }) {
  const safeStatus = String(status || "open").trim().toLowerCase();
  const statusFilter = ["open", "resolved", "ignored", "all"].includes(safeStatus)
    ? safeStatus
    : "open";
  const r = await q(
    `SELECT
       id,
       module_key,
       severity,
       title,
       details,
       fix_hint,
       status,
       metadata,
       detected_at,
       resolved_at,
       resolved_by_user_id
     FROM ai_system_finding
     WHERE ($1::text = 'all' OR status = $1::text)
     ORDER BY
       CASE severity WHEN 'critical' THEN 0 WHEN 'warning' THEN 1 ELSE 2 END ASC,
       detected_at DESC,
       id DESC
     LIMIT $2`,
    [statusFilter, asLimit(limit, 80, 400)]
  );
  return r.rows;
}

export async function insertAiSystemFinding({
  moduleKey,
  severity = "warning",
  title,
  details = null,
  fixHint = null,
  metadata = null,
}) {
  const r = await q(
    `INSERT INTO ai_system_finding
      (
        module_key,
        severity,
        title,
        details,
        fix_hint,
        status,
        metadata
      )
     VALUES ($1,$2,$3,$4,$5,'open',$6)
     RETURNING *`,
    [
      asText(moduleKey, 64) || "unknown",
      asText(severity, 16) || "warning",
      asText(title, 500) || "AI system finding",
      asText(details, 8000),
      asText(fixHint, 2000),
      metadata == null ? null : asJson(metadata, {}),
    ]
  );
  return r.rows[0] || null;
}

export async function setAiSystemFindingStatus({
  findingId,
  status,
  resolvedByUserId = null,
}) {
  const nextStatus = String(status || "resolved").trim().toLowerCase();
  const r = await q(
    `UPDATE ai_system_finding
     SET status = $2,
         resolved_at = CASE WHEN $2 = 'open' THEN NULL ELSE NOW() END,
         resolved_by_user_id = CASE
           WHEN $2 = 'open' THEN NULL
           ELSE $3
         END
     WHERE id = $1
     RETURNING *`,
    [Number(findingId), nextStatus, asNullablePositiveInt(resolvedByUserId)]
  );
  return r.rows[0] || null;
}

export async function resolveOpenSystemFindingsByModule(moduleKey) {
  await q(
    `UPDATE ai_system_finding
     SET status = 'resolved',
         resolved_at = NOW()
     WHERE module_key = $1
       AND status = 'open'`,
    [asText(moduleKey, 64) || "unknown"]
  );
}

export async function getLatestLearningCycleRun({
  cycleType = "daily",
  cycleDate = null,
} = {}) {
  const safeType = asText(cycleType, 24) || "daily";
  const safeDate = cycleDate == null ? null : String(cycleDate).trim();
  const r = await q(
    `SELECT
       id,
       cycle_type,
       cycle_date,
       status,
       trigger_source,
       triggered_by_user_id,
       started_at,
       finished_at,
       scanned_queries,
       inserted_memories,
       notes,
       meta
     FROM ai_learning_cycle_run
     WHERE cycle_type = $1
       AND ($2::date IS NULL OR cycle_date = $2::date)
     ORDER BY id DESC
     LIMIT 1`,
    [safeType, safeDate]
  );
  return r.rows[0] || null;
}

export async function createLearningCycleRun({
  cycleType = "daily",
  cycleDate,
  triggerSource = "system",
  triggeredByUserId = null,
  notes = null,
  meta = null,
}) {
  const safeType = asText(cycleType, 24) || "daily";
  const safeDate = String(cycleDate || "").trim();
  const safeSource = asText(triggerSource, 32) || "system";
  const r = await q(
    `INSERT INTO ai_learning_cycle_run
      (
        cycle_type,
        cycle_date,
        status,
        trigger_source,
        triggered_by_user_id,
        notes,
        meta
      )
     VALUES ($1,$2::date,'running',$3,$4,$5,$6)
     RETURNING *`,
    [
      safeType,
      safeDate,
      safeSource,
      asNullablePositiveInt(triggeredByUserId),
      asText(notes, 4000),
      meta == null ? null : asJson(meta, {}),
    ]
  );
  return r.rows[0] || null;
}

export async function finishLearningCycleRun({
  runId,
  status = "success",
  scannedQueries = 0,
  insertedMemories = 0,
  notes = null,
  meta = null,
}) {
  const nextStatus = asText(status, 16) || "success";
  const r = await q(
    `UPDATE ai_learning_cycle_run
     SET status = $2,
         finished_at = NOW(),
         scanned_queries = $3,
         inserted_memories = $4,
         notes = COALESCE($5, notes),
         meta = CASE
           WHEN $6::jsonb IS NULL THEN COALESCE(meta, '{}'::jsonb)
           ELSE COALESCE(meta, '{}'::jsonb) || $6::jsonb
         END
     WHERE id = $1
     RETURNING *`,
    [
      Number(runId),
      nextStatus,
      Number.isFinite(Number(scannedQueries)) ? Number(scannedQueries) : 0,
      Number.isFinite(Number(insertedMemories)) ? Number(insertedMemories) : 0,
      asText(notes, 4000),
      meta == null ? null : asJson(meta, {}),
    ]
  );
  return r.rows[0] || null;
}

export async function listLearningCycleRuns({
  cycleType = "daily",
  limit = 30,
}) {
  const safeType = asText(cycleType, 24) || "daily";
  const r = await q(
    `SELECT
       id,
       cycle_type,
       cycle_date,
       status,
       trigger_source,
       triggered_by_user_id,
       started_at,
       finished_at,
       scanned_queries,
       inserted_memories,
       notes,
       meta
     FROM ai_learning_cycle_run
     WHERE cycle_type = $1
     ORDER BY id DESC
     LIMIT $2`,
    [safeType, asLimit(limit, 30, 300)]
  );
  return r.rows;
}

export async function getTrainingJobByKey(jobKey) {
  const safeKey = asText(jobKey, 120);
  if (!safeKey) return null;
  const r = await q(
    `SELECT *
     FROM ai_training_job
     WHERE job_key = $1
     LIMIT 1`,
    [safeKey]
  );
  return r.rows[0] || null;
}

export async function createTrainingJob({
  jobKey,
  status = "running",
  targetConversations = 0,
  turnsPerConversation = 100,
  persistPerConversation = 4,
  storeMode = "distilled",
  flushRows = 3000,
  reportEvery = 250,
  batchSleepMs = 0,
  meta = null,
}) {
  const safeJobKey = asText(jobKey, 120);
  if (!safeJobKey) {
    throw new Error("INVALID_JOB_KEY");
  }
  const r = await q(
    `INSERT INTO ai_training_job
      (
        job_key,
        status,
        target_conversations,
        turns_per_conversation,
        persist_per_conversation,
        store_mode,
        flush_rows,
        report_every,
        batch_sleep_ms,
        meta
      )
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
     ON CONFLICT (job_key) DO NOTHING
     RETURNING *`,
    [
      safeJobKey,
      asText(status, 16) || "running",
      asIntSafe(targetConversations, 0),
      asIntSafe(turnsPerConversation, 100),
      asIntSafe(persistPerConversation, 4),
      asText(storeMode, 16) || "distilled",
      asIntSafe(flushRows, 3000),
      asIntSafe(reportEvery, 250),
      asIntSafe(batchSleepMs, 0),
      meta == null ? null : asJson(meta, {}),
    ]
  );
  return r.rows[0] || null;
}

export async function touchTrainingJobProgress({
  jobId,
  status = null,
  currentConversation = null,
  insertedRows = null,
  simulatedTurns = null,
  webBootstrapInserted = null,
  metaPatch = null,
  lastError = null,
}) {
  const r = await q(
    `UPDATE ai_training_job
     SET status = COALESCE($2, status),
         current_conversation = COALESCE($3, current_conversation),
         inserted_rows = COALESCE($4, inserted_rows),
         simulated_turns = COALESCE($5, simulated_turns),
         web_bootstrap_inserted = COALESCE($6, web_bootstrap_inserted),
         meta = CASE
           WHEN $7::jsonb IS NULL THEN meta
           ELSE COALESCE(meta, '{}'::jsonb) || $7::jsonb
         END,
         last_error = COALESCE($8, last_error),
         finished_at = CASE
           WHEN COALESCE($2, status) IN ('success', 'failed', 'cancelled')
             THEN COALESCE(finished_at, NOW())
           WHEN COALESCE($2, status) = 'running'
             THEN NULL
           ELSE finished_at
         END
     WHERE id = $1
     RETURNING *`,
    [
      asIntSafe(jobId, 0),
      status ? asText(status, 16) : null,
      currentConversation == null ? null : asIntSafe(currentConversation, 0),
      insertedRows == null ? null : asIntSafe(insertedRows, 0),
      simulatedTurns == null ? null : asIntSafe(simulatedTurns, 0),
      webBootstrapInserted == null ? null : asIntSafe(webBootstrapInserted, 0),
      metaPatch == null ? null : asJson(metaPatch, {}),
      lastError == null ? null : asText(lastError, 8000),
    ]
  );
  return r.rows[0] || null;
}

function asIntSafe(value, fallback = 0) {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  return Math.trunc(n);
}

function asBool(value, fallback = false) {
  if (typeof value === "boolean") return value;
  if (value == null) return fallback;
  const normalized = String(value).trim().toLowerCase();
  if (["1", "true", "yes", "on"].includes(normalized)) return true;
  if (["0", "false", "no", "off"].includes(normalized)) return false;
  return fallback;
}

function asTextArray(values, { maxItems = 80, maxLen = 120 } = {}) {
  if (!Array.isArray(values)) return [];
  const out = [];
  for (const item of values) {
    const safe = asText(item, maxLen);
    if (!safe) continue;
    if (!out.includes(safe)) out.push(safe);
    if (out.length >= maxItems) break;
  }
  return out;
}

export async function getAiUserProfileV2(customerUserId) {
  const r = await q(
    `SELECT *
     FROM ai_user_profiles
     WHERE user_id = $1
     LIMIT 1`,
    [Number(customerUserId)]
  );
  return r.rows[0] || null;
}

export async function getAppUserAiConsentState(customerUserId) {
  const r = await q(
    `SELECT
       id,
       analytics_consent_granted,
       chat_quality_review_consent,
       ai_chat_review_consent
     FROM app_user
     WHERE id = $1
     LIMIT 1`,
    [Number(customerUserId)]
  );
  return r.rows[0] || null;
}

export async function upsertAiUserProfileV2({
  customerUserId,
  displayName = null,
  realName = null,
  nickname = null,
  preferredLanguage = null,
  dialect = null,
  gender = null,
  ageRange = null,
  city = null,
  bioSummary = null,
  occupation = null,
  interests = null,
  goals = null,
  personalityNotes = null,
  familyNotes = null,
  painPoints = null,
  preferences = null,
  consentFlags = null,
}) {
  const r = await q(
    `INSERT INTO ai_user_profiles
      (
        user_id,
        display_name,
        real_name,
        nickname,
        preferred_language,
        dialect,
        gender,
        age_range,
        city,
        bio_summary,
        occupation,
        interests,
        goals,
        personality_notes,
        family_notes,
        pain_points,
        preferences_json,
        consent_flags_json
      )
     VALUES (
       $1,$2,$3,$4,
       COALESCE($5,'ar'),
       COALESCE($6,'iraqi'),
       $7,$8,$9,$10,$11,
       COALESCE($12,'[]'::jsonb),
       COALESCE($13,'[]'::jsonb),
       $14,$15,
       COALESCE($16,'[]'::jsonb),
       COALESCE($17,'{}'::jsonb),
       COALESCE($18,'{\"memoryEnabled\": true, \"profileStorage\": true, \"personalization\": true, \"adminReview\": true, \"improveModel\": true}'::jsonb)
     )
     ON CONFLICT (user_id)
     DO UPDATE
       SET display_name = COALESCE(EXCLUDED.display_name, ai_user_profiles.display_name),
           real_name = COALESCE(EXCLUDED.real_name, ai_user_profiles.real_name),
           nickname = COALESCE(EXCLUDED.nickname, ai_user_profiles.nickname),
           preferred_language = COALESCE(EXCLUDED.preferred_language, ai_user_profiles.preferred_language),
           dialect = COALESCE(EXCLUDED.dialect, ai_user_profiles.dialect),
           gender = COALESCE(EXCLUDED.gender, ai_user_profiles.gender),
           age_range = COALESCE(EXCLUDED.age_range, ai_user_profiles.age_range),
           city = COALESCE(EXCLUDED.city, ai_user_profiles.city),
           bio_summary = COALESCE(EXCLUDED.bio_summary, ai_user_profiles.bio_summary),
           occupation = COALESCE(EXCLUDED.occupation, ai_user_profiles.occupation),
           interests = CASE
             WHEN EXCLUDED.interests IS NULL THEN ai_user_profiles.interests
             ELSE EXCLUDED.interests
           END,
           goals = CASE
             WHEN EXCLUDED.goals IS NULL THEN ai_user_profiles.goals
             ELSE EXCLUDED.goals
           END,
           personality_notes = COALESCE(EXCLUDED.personality_notes, ai_user_profiles.personality_notes),
           family_notes = COALESCE(EXCLUDED.family_notes, ai_user_profiles.family_notes),
           pain_points = CASE
             WHEN EXCLUDED.pain_points IS NULL THEN ai_user_profiles.pain_points
             ELSE EXCLUDED.pain_points
           END,
           preferences_json = CASE
             WHEN EXCLUDED.preferences_json IS NULL THEN ai_user_profiles.preferences_json
             ELSE ai_user_profiles.preferences_json || EXCLUDED.preferences_json
           END,
           consent_flags_json = CASE
             WHEN EXCLUDED.consent_flags_json IS NULL THEN ai_user_profiles.consent_flags_json
             ELSE ai_user_profiles.consent_flags_json || EXCLUDED.consent_flags_json
           END
     RETURNING *`,
    [
      Number(customerUserId),
      asText(displayName, 160),
      asText(realName, 160),
      asText(nickname, 160),
      asText(preferredLanguage, 12),
      asText(dialect, 32),
      asText(gender, 20),
      asText(ageRange, 40),
      asText(city, 120),
      asText(bioSummary, 4000),
      asText(occupation, 160),
      interests == null ? null : asJson(asTextArray(interests, { maxItems: 80, maxLen: 120 }), []),
      goals == null ? null : asJson(asTextArray(goals, { maxItems: 80, maxLen: 180 }), []),
      asText(personalityNotes, 4000),
      asText(familyNotes, 4000),
      painPoints == null ? null : asJson(asTextArray(painPoints, { maxItems: 80, maxLen: 200 }), []),
      preferences == null ? null : asJson(preferences, {}),
      consentFlags == null ? null : asJson(consentFlags, {}),
    ]
  );
  return r.rows[0] || null;
}

export async function setAiUserConsentFlags({
  customerUserId,
  consentFlags,
}) {
  const existing = await getAiUserProfileV2(customerUserId);
  if (!existing) {
    return upsertAiUserProfileV2({
      customerUserId,
      consentFlags,
    });
  }
  const r = await q(
    `UPDATE ai_user_profiles
     SET consent_flags_json = COALESCE(consent_flags_json, '{}'::jsonb) || $2::jsonb
     WHERE user_id = $1
     RETURNING *`,
    [Number(customerUserId), asJson(consentFlags || {}, {})]
  );
  return r.rows[0] || null;
}

export async function upsertAiConversationV2({
  customerUserId,
  sessionId = null,
  title = null,
  startedAt = null,
  endedAt = null,
  summary = null,
  topics = null,
  sentiment = null,
  importantNotes = null,
}) {
  const safeSessionId = asNullablePositiveInt(sessionId);
  if (safeSessionId != null) {
    const existing = await q(
      `SELECT id
       FROM ai_conversations
       WHERE user_id = $1
         AND session_id = $2
       LIMIT 1`,
      [Number(customerUserId), safeSessionId]
    );
    if ((existing.rowCount || 0) > 0) {
      const updated = await q(
        `UPDATE ai_conversations
         SET title = COALESCE($3, title),
             started_at = COALESCE($4::timestamptz, started_at),
             ended_at = COALESCE($5::timestamptz, ended_at),
             summary = COALESCE($6, summary),
             topics_json = CASE
               WHEN $7::jsonb IS NULL THEN topics_json
               ELSE $7::jsonb
             END,
             sentiment = COALESCE($8, sentiment),
             important_notes_json = CASE
               WHEN $9::jsonb IS NULL THEN important_notes_json
               ELSE $9::jsonb
             END
         WHERE id = $1
         RETURNING *`,
        [
          Number(existing.rows[0].id),
          Number(customerUserId),
          asText(title, 220),
          asTimestamp(startedAt),
          asTimestamp(endedAt),
          asText(summary, 12000),
          topics == null ? null : asJson(asTextArray(topics, { maxItems: 80, maxLen: 120 }), []),
          asText(sentiment, 24),
          importantNotes == null
            ? null
            : asJson(asTextArray(importantNotes, { maxItems: 80, maxLen: 260 }), []),
        ]
      );
      return updated.rows[0] || null;
    }
  }

  const inserted = await q(
    `INSERT INTO ai_conversations
      (
        user_id,
        session_id,
        title,
        started_at,
        ended_at,
        summary,
        topics_json,
        sentiment,
        important_notes_json
      )
     VALUES ($1,$2,$3,COALESCE($4::timestamptz, NOW()),$5::timestamptz,$6,COALESCE($7,'[]'::jsonb),$8,COALESCE($9,'[]'::jsonb))
     RETURNING *`,
    [
      Number(customerUserId),
      safeSessionId,
      asText(title, 220),
      asTimestamp(startedAt),
      asTimestamp(endedAt),
      asText(summary, 12000),
      topics == null ? null : asJson(asTextArray(topics, { maxItems: 80, maxLen: 120 }), []),
      asText(sentiment, 24),
      importantNotes == null
        ? null
        : asJson(asTextArray(importantNotes, { maxItems: 80, maxLen: 260 }), []),
    ]
  );
  return inserted.rows[0] || null;
}

export async function listAiConversationsV2({
  customerUserId,
  limit = 30,
  offset = 0,
}) {
  const r = await q(
    `SELECT *
     FROM ai_conversations
     WHERE user_id = $1
     ORDER BY COALESCE(ended_at, started_at) DESC, id DESC
     LIMIT $2
     OFFSET $3`,
    [Number(customerUserId), asLimit(limit, 30, 200), asOffset(offset)]
  );
  return r.rows;
}

export async function getAiConversationV2({
  conversationId,
  customerUserId,
}) {
  const r = await q(
    `SELECT *
     FROM ai_conversations
     WHERE id = $1
       AND user_id = $2
     LIMIT 1`,
    [Number(conversationId), Number(customerUserId)]
  );
  return r.rows[0] || null;
}

export async function getAiConversationBySessionV2({
  sessionId,
  customerUserId,
}) {
  const safeSessionId = asNullablePositiveInt(sessionId);
  if (!safeSessionId) return null;
  const r = await q(
    `SELECT *
     FROM ai_conversations
     WHERE session_id = $1
       AND user_id = $2
     LIMIT 1`,
    [safeSessionId, Number(customerUserId)]
  );
  return r.rows[0] || null;
}

export async function appendAiMessageV2({
  conversationId,
  customerUserId,
  role,
  messageText,
  messageType = "text",
  metadata = null,
}) {
  const safeRole = asText(role, 24) || "assistant";
  const safeType = asText(messageType, 40) || "text";
  const safeTextValue = asText(messageText, 20000);
  if (!safeTextValue) return null;

  const r = await q(
    `INSERT INTO ai_messages
      (
        conversation_id,
        user_id,
        role,
        message_text,
        message_type,
        metadata_json
      )
     VALUES ($1,$2,$3,$4,$5,$6)
     RETURNING *`,
    [
      Number(conversationId),
      Number(customerUserId),
      safeRole,
      safeTextValue,
      safeType,
      metadata == null ? null : asJson(metadata, {}),
    ]
  );
  return r.rows[0] || null;
}

export async function listAiConversationMessagesV2({
  conversationId,
  customerUserId,
  limit = 120,
  beforeId = null,
}) {
  const r = await q(
    `SELECT m.*
     FROM ai_messages m
     JOIN ai_conversations c ON c.id = m.conversation_id
     WHERE m.conversation_id = $1
       AND c.user_id = $2
       AND ($3::bigint IS NULL OR m.id < $3::bigint)
     ORDER BY m.id DESC
     LIMIT $4`,
    [
      Number(conversationId),
      Number(customerUserId),
      beforeId == null ? null : Number(beforeId),
      asLimit(limit, 120, 500),
    ]
  );
  return r.rows.reverse();
}

export async function listAiUserMemoriesV2({
  customerUserId,
  memoryType = null,
  activeOnly = true,
  limit = 120,
  offset = 0,
}) {
  const r = await q(
    `SELECT *
     FROM ai_user_memories
     WHERE user_id = $1
       AND ($2::text IS NULL OR memory_type = $2::text)
       AND ($3::boolean = FALSE OR is_active = TRUE)
     ORDER BY updated_at DESC, id DESC
     LIMIT $4
     OFFSET $5`,
    [
      Number(customerUserId),
      asText(memoryType, 40),
      asBool(activeOnly, true),
      asLimit(limit, 120, 500),
      asOffset(offset),
    ]
  );
  return r.rows;
}

export async function insertAiUserMemoryV2({
  customerUserId,
  memoryType,
  memoryKey,
  memoryValue,
  confidenceScore = 0.6,
  sourceConversationId = null,
  sourceMessageId = null,
  isActive = true,
}) {
  const r = await q(
    `INSERT INTO ai_user_memories
      (
        user_id,
        memory_type,
        memory_key,
        memory_value,
        confidence_score,
        source_conversation_id,
        source_message_id,
        is_active
      )
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
     RETURNING *`,
    [
      Number(customerUserId),
      asText(memoryType, 40) || "fact",
      asText(memoryKey, 120) || "general",
      asText(memoryValue, 4000) || "",
      asNullableFloat(confidenceScore) ?? 0.6,
      asNullablePositiveInt(sourceConversationId),
      asNullablePositiveInt(sourceMessageId),
      asBool(isActive, true),
    ]
  );
  return r.rows[0] || null;
}

export async function updateAiUserMemoryV2({
  memoryId,
  customerUserId,
  memoryType = null,
  memoryKey = null,
  memoryValue = null,
  confidenceScore = null,
  isActive = null,
}) {
  const r = await q(
    `UPDATE ai_user_memories
     SET memory_type = COALESCE($3, memory_type),
         memory_key = COALESCE($4, memory_key),
         memory_value = COALESCE($5, memory_value),
         confidence_score = COALESCE($6, confidence_score),
         is_active = COALESCE($7, is_active)
     WHERE id = $1
       AND user_id = $2
     RETURNING *`,
    [
      Number(memoryId),
      Number(customerUserId),
      asText(memoryType, 40),
      asText(memoryKey, 120),
      asText(memoryValue, 4000),
      confidenceScore == null ? null : asNullableFloat(confidenceScore),
      isActive == null ? null : asBool(isActive, true),
    ]
  );
  return r.rows[0] || null;
}

export async function deleteAiUserMemoryV2({
  memoryId,
  customerUserId,
}) {
  const r = await q(
    `DELETE FROM ai_user_memories
     WHERE id = $1
       AND user_id = $2
     RETURNING id`,
    [Number(memoryId), Number(customerUserId)]
  );
  return (r.rowCount || 0) > 0;
}

export async function deleteAllAiUserMemoriesV2({
  customerUserId,
  memoryType = null,
  activeOnly = false,
}) {
  const r = await q(
    `DELETE FROM ai_user_memories
     WHERE user_id = $1
       AND ($2::text IS NULL OR memory_type = $2::text)
       AND ($3::boolean = FALSE OR is_active = TRUE)
     RETURNING id`,
    [Number(customerUserId), asText(memoryType, 40), asBool(activeOnly, false)]
  );
  return {
    deletedCount: Number(r.rowCount || 0),
  };
}

export async function upsertAiUserTopicV2({
  customerUserId,
  topicName,
  topicCategory = null,
  scoreDelta = 1,
  mentionDelta = 1,
  discussedAt = null,
}) {
  const safeTopic = asText(topicName, 120);
  if (!safeTopic) return null;
  const safeDiscussedAt = asTimestamp(discussedAt) || new Date().toISOString();
  const safeScoreDelta = Number.isFinite(Number(scoreDelta)) ? Number(scoreDelta) : 1;
  const safeMentionDelta = asIntSafe(mentionDelta, 1);

  const r = await q(
    `INSERT INTO ai_user_topics
      (
        user_id,
        topic_name,
        topic_category,
        interest_score,
        mention_count,
        last_discussed_at
      )
     VALUES ($1,$2,$3,$4,$5,$6::timestamptz)
     ON CONFLICT (user_id, topic_name)
     DO UPDATE
       SET topic_category = COALESCE(EXCLUDED.topic_category, ai_user_topics.topic_category),
           interest_score = ai_user_topics.interest_score + $4,
           mention_count = ai_user_topics.mention_count + $5,
           last_discussed_at = GREATEST(ai_user_topics.last_discussed_at, $6::timestamptz)
     RETURNING *`,
    [
      Number(customerUserId),
      safeTopic,
      asText(topicCategory, 64),
      safeScoreDelta,
      safeMentionDelta,
      safeDiscussedAt,
    ]
  );
  return r.rows[0] || null;
}

export async function listAiUserTopicsV2({
  customerUserId,
  limit = 60,
}) {
  const r = await q(
    `SELECT *
     FROM ai_user_topics
     WHERE user_id = $1
     ORDER BY interest_score DESC, mention_count DESC, updated_at DESC
     LIMIT $2`,
    [Number(customerUserId), asLimit(limit, 60, 400)]
  );
  return r.rows;
}

export async function insertAiUserPreferenceHistoryV2({
  customerUserId,
  preferenceKey,
  oldValue = null,
  newValue = null,
  changedBy = "system",
}) {
  const safeKey = asText(preferenceKey, 120);
  if (!safeKey) return null;
  const r = await q(
    `INSERT INTO ai_user_preference_history
      (
        user_id,
        preference_key,
        old_value,
        new_value,
        changed_by
      )
     VALUES ($1,$2,$3,$4,$5)
     RETURNING *`,
    [
      Number(customerUserId),
      safeKey,
      oldValue == null ? null : asText(String(oldValue), 4000),
      newValue == null ? null : asText(String(newValue), 4000),
      asText(changedBy, 24) || "system",
    ]
  );
  return r.rows[0] || null;
}

export async function upsertAiAdminUserInsightsV2({
  customerUserId,
  generatedSummary = null,
  keyPatterns = null,
  productFeedback = null,
  serviceRecommendations = null,
  lastGeneratedAt = null,
}) {
  const r = await q(
    `INSERT INTO ai_admin_user_insights
      (
        user_id,
        generated_summary,
        key_patterns_json,
        product_feedback_json,
        service_recommendations_json,
        last_generated_at
      )
     VALUES ($1,$2,COALESCE($3,'[]'::jsonb),COALESCE($4,'[]'::jsonb),COALESCE($5,'[]'::jsonb),COALESCE($6::timestamptz,NOW()))
     ON CONFLICT (user_id)
     DO UPDATE
       SET generated_summary = COALESCE(EXCLUDED.generated_summary, ai_admin_user_insights.generated_summary),
           key_patterns_json = CASE
             WHEN EXCLUDED.key_patterns_json IS NULL THEN ai_admin_user_insights.key_patterns_json
             ELSE EXCLUDED.key_patterns_json
           END,
           product_feedback_json = CASE
             WHEN EXCLUDED.product_feedback_json IS NULL THEN ai_admin_user_insights.product_feedback_json
             ELSE EXCLUDED.product_feedback_json
           END,
           service_recommendations_json = CASE
             WHEN EXCLUDED.service_recommendations_json IS NULL THEN ai_admin_user_insights.service_recommendations_json
             ELSE EXCLUDED.service_recommendations_json
           END,
           last_generated_at = COALESCE(EXCLUDED.last_generated_at, ai_admin_user_insights.last_generated_at)
     RETURNING *`,
    [
      Number(customerUserId),
      asText(generatedSummary, 16000),
      keyPatterns == null ? null : asJson(keyPatterns, []),
      productFeedback == null ? null : asJson(productFeedback, []),
      serviceRecommendations == null ? null : asJson(serviceRecommendations, []),
      asTimestamp(lastGeneratedAt),
    ]
  );
  return r.rows[0] || null;
}

export async function listAiIntelligenceUsersV2({
  search = "",
  limit = 40,
  offset = 0,
}) {
  const safeSearch = String(search || "").trim().toLowerCase();
  const r = await q(
    `SELECT
       p.user_id,
       COALESCE(p.display_name, p.real_name, p.nickname) AS preferred_name,
       p.preferred_language,
       p.dialect,
       p.city,
       p.occupation,
       p.interests,
       p.goals,
       p.consent_flags_json,
       c.total_conversations,
       c.last_conversation_at,
       COALESCE(t.topics, '[]'::jsonb) AS top_topics,
       i.generated_summary,
       i.last_generated_at
     FROM ai_user_profiles p
     LEFT JOIN LATERAL (
       SELECT
         COUNT(*)::int AS total_conversations,
         MAX(COALESCE(ended_at, started_at)) AS last_conversation_at
       FROM ai_conversations c
       WHERE c.user_id = p.user_id
     ) c ON TRUE
     LEFT JOIN LATERAL (
       SELECT jsonb_agg(jsonb_build_object(
         'topicName', topic_name,
         'category', topic_category,
         'score', interest_score,
         'mentionCount', mention_count
       ) ORDER BY interest_score DESC, mention_count DESC) AS topics
       FROM (
         SELECT *
         FROM ai_user_topics ut
         WHERE ut.user_id = p.user_id
         ORDER BY ut.interest_score DESC, ut.mention_count DESC
         LIMIT 5
       ) x
     ) t ON TRUE
     LEFT JOIN ai_admin_user_insights i ON i.user_id = p.user_id
     WHERE (
       $1::text = ''
       OR LOWER(COALESCE(p.display_name, '')) LIKE ('%' || $1 || '%')
       OR LOWER(COALESCE(p.real_name, '')) LIKE ('%' || $1 || '%')
       OR LOWER(COALESCE(p.nickname, '')) LIKE ('%' || $1 || '%')
       OR CAST(p.user_id AS TEXT) LIKE ('%' || $1 || '%')
     )
     ORDER BY COALESCE(c.last_conversation_at, p.updated_at) DESC, p.user_id DESC
     LIMIT $2
     OFFSET $3`,
    [safeSearch, asLimit(limit, 40, 400), asOffset(offset)]
  );
  return r.rows;
}

export async function getAiIntelligenceUserDetailsV2({
  customerUserId,
  conversationsLimit = 20,
  memoriesLimit = 120,
}) {
  const [profile, conversations, memories, topics, insights, preferenceChanges, auditLogs] =
    await Promise.all([
      getAiUserProfileV2(customerUserId),
      listAiConversationsV2({
        customerUserId,
        limit: conversationsLimit,
        offset: 0,
      }),
      listAiUserMemoriesV2({
        customerUserId,
        activeOnly: false,
        limit: memoriesLimit,
        offset: 0,
      }),
      listAiUserTopicsV2({ customerUserId, limit: 80 }),
      q(
        `SELECT *
         FROM ai_admin_user_insights
         WHERE user_id = $1
         LIMIT 1`,
        [Number(customerUserId)]
      ).then((res) => res.rows[0] || null),
      q(
        `SELECT *
         FROM ai_user_preference_history
         WHERE user_id = $1
         ORDER BY id DESC
         LIMIT 80`,
        [Number(customerUserId)]
      ).then((res) => res.rows),
      q(
        `SELECT *
         FROM ai_memory_audit_log
         WHERE target_user_id = $1
         ORDER BY id DESC
         LIMIT 120`,
        [Number(customerUserId)]
      ).then((res) => res.rows),
    ]);

  return {
    profile,
    conversations,
    memories,
    topics,
    insights,
    preferenceChanges,
    auditLogs,
  };
}

export async function listAiInsightsOverviewV2({ limit = 120 } = {}) {
  const r = await q(
    `SELECT
       i.user_id,
       i.generated_summary,
       i.key_patterns_json,
       i.product_feedback_json,
       i.service_recommendations_json,
       i.last_generated_at,
       p.display_name,
       p.real_name,
       p.nickname,
       p.preferred_language,
       p.city
     FROM ai_admin_user_insights i
     LEFT JOIN ai_user_profiles p ON p.user_id = i.user_id
     ORDER BY i.last_generated_at DESC NULLS LAST, i.updated_at DESC, i.user_id DESC
     LIMIT $1`,
    [asLimit(limit, 120, 500)]
  );
  return r.rows;
}

export async function listAiTopicsOverviewV2({ limit = 200 } = {}) {
  const r = await q(
    `SELECT
       topic_name,
       COALESCE(topic_category, 'general') AS topic_category,
       COUNT(*)::int AS users_count,
       SUM(mention_count)::int AS mentions,
       AVG(interest_score)::double precision AS avg_interest_score,
       MAX(last_discussed_at) AS last_discussed_at
     FROM ai_user_topics
     GROUP BY topic_name, COALESCE(topic_category, 'general')
     ORDER BY mentions DESC, avg_interest_score DESC, users_count DESC
     LIMIT $1`,
    [asLimit(limit, 200, 1000)]
  );
  return r.rows;
}

export async function listAiFeedbackOverviewV2({ limit = 300 } = {}) {
  const r = await q(
    `SELECT
       user_id,
       generated_summary,
       product_feedback_json,
       service_recommendations_json,
       last_generated_at
     FROM ai_admin_user_insights
     WHERE jsonb_array_length(COALESCE(product_feedback_json, '[]'::jsonb)) > 0
        OR jsonb_array_length(COALESCE(service_recommendations_json, '[]'::jsonb)) > 0
     ORDER BY last_generated_at DESC NULLS LAST, updated_at DESC
     LIMIT $1`,
    [asLimit(limit, 300, 1200)]
  );
  return r.rows;
}

export async function listAiAuditLogsV2({
  targetUserId = null,
  limit = 200,
  offset = 0,
}) {
  const r = await q(
    `SELECT *
     FROM ai_memory_audit_log
     WHERE ($1::bigint IS NULL OR target_user_id = $1::bigint)
     ORDER BY id DESC
     LIMIT $2
     OFFSET $3`,
    [
      targetUserId == null ? null : Number(targetUserId),
      asLimit(limit, 200, 1200),
      asOffset(offset),
    ]
  );
  return r.rows;
}

export async function insertAiMemoryAuditLogV2({
  actorUserId = null,
  actorRole = null,
  targetUserId = null,
  actionKey,
  details = null,
}) {
  const safeActionKey = asText(actionKey, 80);
  if (!safeActionKey) return null;
  const r = await q(
    `INSERT INTO ai_memory_audit_log
      (
        actor_user_id,
        actor_role,
        target_user_id,
        action_key,
        details_json
      )
     VALUES ($1,$2,$3,$4,$5)
     RETURNING *`,
    [
      asNullablePositiveInt(actorUserId),
      asText(actorRole, 24),
      asNullablePositiveInt(targetUserId),
      safeActionKey,
      details == null ? null : asJson(details, {}),
    ]
  );
  return r.rows[0] || null;
}

export async function upsertAiKnowledgeEntry({
  sourceType = "faq",
  intentCluster = null,
  language = "ar",
  dialect = null,
  queryText,
  answerText,
  tags = [],
  embedding = null,
  retrievalWeight = 1,
  isActive = true,
}) {
  const safeQuery = asText(queryText, 4000);
  const safeAnswer = asText(answerText, 12000);
  if (!safeQuery || !safeAnswer) return null;

  const existing = await q(
    `SELECT id
     FROM ai_knowledge_entry
     WHERE LOWER(query_text) = LOWER($1)
       AND language = $2
       AND COALESCE(dialect, '') = COALESCE($3, '')
     LIMIT 1`,
    [safeQuery, asText(language, 8) || "ar", asText(dialect, 32)]
  );

  if ((existing.rowCount || 0) > 0) {
    const updated = await q(
      `UPDATE ai_knowledge_entry
       SET source_type = COALESCE($2, source_type),
           intent_cluster = COALESCE($3, intent_cluster),
           answer_text = $4,
           tags_json = COALESCE($5::jsonb, tags_json),
           embedding_json = COALESCE($6::jsonb, embedding_json),
           retrieval_weight = COALESCE($7, retrieval_weight),
           is_active = COALESCE($8, is_active)
       WHERE id = $1
       RETURNING *`,
      [
        Number(existing.rows[0].id),
        asText(sourceType, 32) || "faq",
        asText(intentCluster, 80),
        safeAnswer,
        asJson(asTextArray(tags, { maxItems: 40, maxLen: 60 }), []),
        embedding == null ? null : asJson(embedding, []),
        Number.isFinite(Number(retrievalWeight)) ? Number(retrievalWeight) : 1,
        asBool(isActive, true),
      ]
    );
    return updated.rows[0] || null;
  }

  const inserted = await q(
    `INSERT INTO ai_knowledge_entry
      (
        source_type,
        intent_cluster,
        language,
        dialect,
        query_text,
        answer_text,
        tags_json,
        embedding_json,
        retrieval_weight,
        is_active
      )
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
     RETURNING *`,
    [
      asText(sourceType, 32) || "faq",
      asText(intentCluster, 80),
      asText(language, 8) || "ar",
      asText(dialect, 32),
      safeQuery,
      safeAnswer,
      asJson(asTextArray(tags, { maxItems: 40, maxLen: 60 }), []),
      embedding == null ? null : asJson(embedding, []),
      Number.isFinite(Number(retrievalWeight)) ? Number(retrievalWeight) : 1,
      asBool(isActive, true),
    ]
  );
  return inserted.rows[0] || null;
}

export async function searchAiKnowledgeEntries({
  query,
  language = null,
  dialect = null,
  intentCluster = null,
  limit = 10,
}) {
  const safeQuery = asText(query, 1200);
  if (!safeQuery) return [];

  const r = await q(
    `SELECT
       id,
       source_type,
       intent_cluster,
       language,
       dialect,
       query_text,
       answer_text,
       tags_json,
       retrieval_weight,
       ts_rank(search_tsv, plainto_tsquery('simple', $1)) AS lexical_rank
     FROM ai_knowledge_entry
     WHERE is_active = TRUE
       AND ($2::text IS NULL OR language = $2::text)
       AND ($3::text IS NULL OR COALESCE(dialect, '') = $3::text)
       AND ($4::text IS NULL OR intent_cluster = $4::text)
       AND search_tsv @@ plainto_tsquery('simple', $1)
     ORDER BY lexical_rank DESC, retrieval_weight DESC, id DESC
     LIMIT $5`,
    [
      safeQuery,
      asText(language, 8),
      asText(dialect, 32),
      asText(intentCluster, 80),
      asLimit(limit, 10, 60),
    ]
  );
  return r.rows;
}

export async function listAiKnowledgeSemanticCandidates({
  language = null,
  dialect = null,
  intentCluster = null,
  limit = 300,
}) {
  const r = await q(
    `SELECT
       id,
       source_type,
       intent_cluster,
       language,
       dialect,
       query_text,
       answer_text,
       tags_json,
       embedding_json,
       retrieval_weight
     FROM ai_knowledge_entry
     WHERE is_active = TRUE
       AND embedding_json IS NOT NULL
       AND jsonb_typeof(embedding_json) = 'array'
       AND jsonb_array_length(embedding_json) > 0
       AND ($1::text IS NULL OR language = $1::text)
       AND ($2::text IS NULL OR COALESCE(dialect, '') = $2::text)
       AND ($3::text IS NULL OR intent_cluster = $3::text)
     ORDER BY retrieval_weight DESC, id DESC
     LIMIT $4`,
    [
      asText(language, 8),
      asText(dialect, 32),
      asText(intentCluster, 80),
      asLimit(limit, 300, 3000),
    ]
  );
  return r.rows;
}

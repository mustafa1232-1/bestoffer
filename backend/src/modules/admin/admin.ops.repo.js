import { q } from "../../config/db.js";

function toInt(value, fallback = 0) {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  return Math.trunc(n);
}

function safeLimit(value, fallback = 50, max = 200) {
  const n = toInt(value, fallback);
  if (n <= 0) return fallback;
  return Math.min(n, max);
}

function normalizeCrashText(value, maxLength) {
  return String(value || "")
    .trim()
    .replace(/\s+/g, " ")
    .slice(0, maxLength);
}

export async function listOpsAlerts({
  status = "open",
  severity = null,
  beforeId = null,
  limit = 60,
} = {}) {
  const filters = [];
  const params = [];

  if (status && status !== "all") {
    params.push(String(status).trim().toLowerCase());
    filters.push(`a.status = $${params.length}`);
  }
  if (severity && severity !== "all") {
    params.push(String(severity).trim().toLowerCase());
    filters.push(`a.severity = $${params.length}`);
  }
  const safeBeforeId = toInt(beforeId, 0);
  if (safeBeforeId > 0) {
    params.push(safeBeforeId);
    filters.push(`a.id < $${params.length}`);
  }
  params.push(safeLimit(limit, 60, 200));
  const limitPlaceholder = `$${params.length}`;

  const where = filters.length > 0 ? `WHERE ${filters.join(" AND ")}` : "";
  const r = await q(
    `SELECT
       a.id,
       a.source,
       a.event_type,
       a.severity,
       a.status,
       a.title,
       a.details,
       a.dedupe_key,
       a.affected_user_id,
       a.affected_role,
       a.entity_type,
       a.entity_id,
       a.acked_by_user_id,
       a.acked_at,
       a.resolved_by_user_id,
       a.resolved_at,
       a.created_at,
       a.updated_at,
       au.full_name AS affected_user_name,
       ack.full_name AS acked_by_name
     FROM ops_alert a
     LEFT JOIN app_user au ON au.id = a.affected_user_id
     LEFT JOIN app_user ack ON ack.id = a.acked_by_user_id
     ${where}
     ORDER BY a.created_at DESC, a.id DESC
     LIMIT ${limitPlaceholder}`,
    params
  );

  return r.rows;
}

export async function acknowledgeOpsAlert({
  alertId,
  actorUserId,
  note = null,
  toStatus = "acknowledged",
}) {
  const safeAlertId = toInt(alertId, 0);
  const safeActorId = toInt(actorUserId, 0);
  if (safeAlertId <= 0 || safeActorId <= 0) return null;

  const status = String(toStatus || "acknowledged").trim().toLowerCase();
  const normalizedStatus =
    status === "resolved" || status === "ignored" || status === "acknowledged"
      ? status
      : "acknowledged";

  const before = await q(`SELECT status FROM ops_alert WHERE id = $1`, [
    safeAlertId,
  ]);
  const previousStatus = before.rows[0]?.status;
  if (!previousStatus) return null;

  const updateResult = await q(
    `UPDATE ops_alert
     SET status = $1,
         acked_by_user_id = CASE
           WHEN $1 = 'acknowledged' THEN $2
           ELSE acked_by_user_id
         END,
         acked_at = CASE
           WHEN $1 = 'acknowledged' THEN NOW()
           ELSE acked_at
         END,
         resolved_by_user_id = CASE
           WHEN $1 IN ('resolved','ignored') THEN $2
           ELSE resolved_by_user_id
         END,
         resolved_at = CASE
           WHEN $1 IN ('resolved','ignored') THEN NOW()
           ELSE resolved_at
         END,
         updated_at = NOW()
     WHERE id = $3
     RETURNING *`,
    [normalizedStatus, safeActorId, safeAlertId]
  );
  const row = updateResult.rows[0] || null;
  if (!row) return null;

  await q(
    `INSERT INTO ops_alert_ack
      (alert_id, actor_user_id, from_status, to_status, note)
     VALUES ($1, $2, $3, $4, $5)`,
    [safeAlertId, safeActorId, previousStatus, normalizedStatus, note]
  );
  return row;
}

export async function notificationOperationsOverview({
  windowHours = 24,
} = {}) {
  const safeHours = Math.max(1, Math.min(24 * 14, toInt(windowHours, 24)));
  const [statusRows, errorRows, latencyRow] = await Promise.all([
    q(
      `SELECT event_status, COUNT(*)::int AS count
       FROM notification_delivery_event
       WHERE created_at >= NOW() - make_interval(hours => $1)
       GROUP BY event_status`,
      [safeHours]
    ),
    q(
      `SELECT error_code, COUNT(*)::int AS count
       FROM notification_delivery_event
       WHERE created_at >= NOW() - make_interval(hours => $1)
         AND error_code IS NOT NULL
         AND error_code <> ''
       GROUP BY error_code
       ORDER BY count DESC
       LIMIT 10`,
      [safeHours]
    ),
    q(
      `SELECT
         AVG(latency_ms)::numeric(10,2) AS avg_latency_ms,
         PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY latency_ms) AS p95_latency_ms
       FROM notification_delivery_event
       WHERE created_at >= NOW() - make_interval(hours => $1)
         AND latency_ms IS NOT NULL
         AND latency_ms > 0`,
      [safeHours]
    ),
  ]);

  const statusCounts = {};
  for (const row of statusRows.rows) {
    statusCounts[String(row.event_status || "unknown")] = toInt(row.count, 0);
  }

  return {
    windowHours: safeHours,
    statusCounts,
    topErrors: errorRows.rows.map((row) => ({
      code: String(row.error_code || "").trim(),
      count: toInt(row.count, 0),
    })),
    latency: {
      avgMs: Number(latencyRow.rows[0]?.avg_latency_ms || 0),
      p95Ms: Number(latencyRow.rows[0]?.p95_latency_ms || 0),
    },
  };
}

export async function listDevicePushReliability({
  status = null,
  limit = 100,
} = {}) {
  const params = [];
  const filters = [];
  if (status && status !== "all") {
    params.push(String(status).trim().toLowerCase());
    filters.push(`d.last_status = $${params.length}`);
  }
  params.push(safeLimit(limit, 100, 300));
  const where = filters.length > 0 ? `WHERE ${filters.join(" AND ")}` : "";
  const r = await q(
    `SELECT
       d.push_token,
       d.user_id,
       d.platform,
       d.last_status,
       d.last_error_code,
       d.failure_count,
       d.success_count,
       d.last_seen_at,
       d.updated_at,
       u.full_name AS user_name,
       u.phone AS user_phone
     FROM device_push_health d
     LEFT JOIN app_user u ON u.id = d.user_id
     ${where}
     ORDER BY d.updated_at DESC
     LIMIT $${params.length}`,
    params
  );
  return r.rows;
}

export async function listCrashEvents({
  platform = null,
  beforeId = null,
  limit = 100,
} = {}) {
  const params = [];
  const filters = [];
  if (platform && platform !== "all") {
    params.push(String(platform).trim().toLowerCase());
    filters.push(`LOWER(c.platform) = $${params.length}`);
  }
  const safeBefore = toInt(beforeId, 0);
  if (safeBefore > 0) {
    params.push(safeBefore);
    filters.push(`c.id < $${params.length}`);
  }
  params.push(safeLimit(limit, 100, 300));
  const where = filters.length > 0 ? `WHERE ${filters.join(" AND ")}` : "";

  const r = await q(
    `SELECT
       c.id,
       c.user_id,
       c.app_role,
       c.platform,
       c.app_version,
       c.source,
       c.message,
       c.stack_trace,
       c.extra,
       c.created_at,
       u.full_name AS user_name,
       u.phone AS user_phone
     FROM app_crash_event c
     LEFT JOIN app_user u ON u.id = c.user_id
     ${where}
     ORDER BY c.created_at DESC, c.id DESC
     LIMIT $${params.length}`,
    params
  );
  return r.rows;
}

export async function insertCrashEvent({
  userId = null,
  appRole = null,
  platform = null,
  appVersion = null,
  source,
  message,
  stackTrace = null,
  extra = {},
}) {
  const safeUserId = userId ? toInt(userId, null) : null;
  const safeRole = appRole ? String(appRole).trim() : null;
  const safePlatform = platform ? String(platform).trim().toLowerCase() : null;
  const safeVersion = appVersion ? String(appVersion).trim() : null;
  const safeSource = normalizeCrashText(source || "unknown", 120);
  const safeMessage = normalizeCrashText(message, 1000);
  const safeStack = stackTrace ? String(stackTrace).slice(0, 10000) : null;
  const safeExtra =
    extra && typeof extra === "object" ? JSON.stringify(extra) : "{}";
  const dedupeResult = await q(
    `SELECT *
       FROM app_crash_event
      WHERE user_id IS NOT DISTINCT FROM $1
        AND app_role IS NOT DISTINCT FROM $2
        AND platform IS NOT DISTINCT FROM $3
        AND source = $4
        AND message = $5
        AND COALESCE(LEFT(stack_trace, 1000), '') = COALESCE($6, '')
        AND created_at >= NOW() - INTERVAL '2 minutes'
      ORDER BY id DESC
      LIMIT 1`,
    [
      safeUserId,
      safeRole,
      safePlatform,
      safeSource,
      safeMessage,
      safeStack ? safeStack.slice(0, 1000) : "",
    ]
  );
  if (dedupeResult.rows[0]) {
    return dedupeResult.rows[0];
  }

  const r = await q(
    `INSERT INTO app_crash_event
      (user_id, app_role, platform, app_version, source, message, stack_trace, extra)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8::jsonb)
     RETURNING *`,
    [
      safeUserId,
      safeRole,
      safePlatform,
      safeVersion,
      safeSource,
      safeMessage,
      safeStack,
      safeExtra,
    ]
  );
  return r.rows[0] || null;
}

export async function listFeatureFlags() {
  const r = await q(
    `SELECT
       id,
       flag_key,
       description,
       is_enabled,
       rollout_percent,
       target_roles,
       config_json,
       updated_by_user_id,
       created_at,
       updated_at
     FROM feature_flag
     ORDER BY flag_key ASC`
  );
  return r.rows;
}

export async function upsertFeatureFlag({
  flagKey,
  description = null,
  isEnabled = false,
  rolloutPercent = 0,
  targetRoles = [],
  configJson = {},
  actorUserId = null,
}) {
  const key = String(flagKey || "").trim().toLowerCase();
  if (!key) return null;

  const safeRoles = Array.isArray(targetRoles)
    ? targetRoles.map((v) => String(v || "").trim()).filter(Boolean)
    : [];
  const safeRollout = Math.max(0, Math.min(100, toInt(rolloutPercent, 0)));

  const r = await q(
    `INSERT INTO feature_flag
      (flag_key, description, is_enabled, rollout_percent, target_roles, config_json, updated_by_user_id)
     VALUES ($1, $2, $3, $4, $5::text[], $6::jsonb, $7)
     ON CONFLICT (flag_key)
     DO UPDATE SET
       description = EXCLUDED.description,
       is_enabled = EXCLUDED.is_enabled,
       rollout_percent = EXCLUDED.rollout_percent,
       target_roles = EXCLUDED.target_roles,
       config_json = EXCLUDED.config_json,
       updated_by_user_id = EXCLUDED.updated_by_user_id,
       updated_at = NOW()
     RETURNING *`,
    [
      key,
      description ? String(description).trim() : null,
      isEnabled === true,
      safeRollout,
      safeRoles,
      JSON.stringify(configJson && typeof configJson === "object" ? configJson : {}),
      actorUserId ? toInt(actorUserId, null) : null,
    ]
  );
  return r.rows[0] || null;
}

export async function listRolePermissionOverrides() {
  const r = await q(
    `SELECT
       id,
       role_key,
       capability_key,
       is_enabled,
       notes,
       updated_by_user_id,
       created_at,
       updated_at
     FROM role_permission_override
     ORDER BY role_key ASC, capability_key ASC`
  );
  return r.rows;
}

export async function upsertRolePermissionOverride({
  roleKey,
  capabilityKey,
  isEnabled,
  notes = null,
  actorUserId = null,
}) {
  const safeRole = String(roleKey || "").trim().toLowerCase();
  const safeCapability = String(capabilityKey || "").trim();
  if (!safeRole || !safeCapability) return null;

  const r = await q(
    `INSERT INTO role_permission_override
      (role_key, capability_key, is_enabled, notes, updated_by_user_id)
     VALUES ($1, $2, $3, $4, $5)
     ON CONFLICT (role_key, capability_key)
     DO UPDATE SET
       is_enabled = EXCLUDED.is_enabled,
       notes = EXCLUDED.notes,
       updated_by_user_id = EXCLUDED.updated_by_user_id,
       updated_at = NOW()
     RETURNING *`,
    [
      safeRole,
      safeCapability,
      isEnabled === true,
      notes ? String(notes).trim() : null,
      actorUserId ? toInt(actorUserId, null) : null,
    ]
  );
  return r.rows[0] || null;
}

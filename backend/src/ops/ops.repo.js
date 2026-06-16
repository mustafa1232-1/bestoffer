import { q } from "../config/db.js";
import { env } from "../config/env.js";
import {
  OPS_SETTINGS_DEFAULTS,
  normalizeActionStatus,
  normalizeIncidentStatus,
  normalizeRiskLevel,
  normalizeSeverity,
  severityToRank,
} from "./types.js";

function toInt(value, fallback = 0) {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  return Math.trunc(n);
}

function toPositiveIntOrNull(value) {
  const n = toInt(value, 0);
  return n > 0 ? n : null;
}

function safeLimit(value, fallback = 50, max = 200) {
  const n = toInt(value, fallback);
  if (n <= 0) return fallback;
  return Math.min(n, max);
}

function asJson(value, fallback = {}) {
  if (value === null || value === undefined) return fallback;
  if (typeof value === "object") return value;
  try {
    return JSON.parse(value);
  } catch (_) {
    return fallback;
  }
}

function asIso(value) {
  if (!value) return null;
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return null;
  return d.toISOString();
}

export async function createIncident({
  source,
  severity,
  status = "open",
  affectedService = null,
  affectedModule = null,
  title,
  summary = null,
  symptoms = [],
  probableRootCause = null,
  evidence = [],
  suggestedMitigation = null,
  longTermFix = null,
  riskLevel = "medium",
  createdBy = null,
  assignedTo = null,
}) {
  const result = await q(
    `INSERT INTO ops_incidents
      (
        source,
        severity,
        status,
        affected_service,
        affected_module,
        title,
        summary,
        symptoms_json,
        probable_root_cause,
        evidence_json,
        suggested_mitigation,
        long_term_fix,
        risk_level,
        created_by,
        assigned_to
      )
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8::jsonb,$9,$10::jsonb,$11,$12,$13,$14,$15)
     RETURNING *`,
    [
      String(source || "unknown").trim().toLowerCase(),
      normalizeSeverity(severity),
      normalizeIncidentStatus(status),
      affectedService ? String(affectedService).trim() : null,
      affectedModule ? String(affectedModule).trim() : null,
      String(title || "Ops incident").trim().slice(0, 300),
      summary ? String(summary).trim().slice(0, 2000) : null,
      JSON.stringify(Array.isArray(symptoms) ? symptoms : []),
      probableRootCause ? String(probableRootCause).trim().slice(0, 2000) : null,
      JSON.stringify(Array.isArray(evidence) ? evidence : []),
      suggestedMitigation ? String(suggestedMitigation).trim().slice(0, 2000) : null,
      longTermFix ? String(longTermFix).trim().slice(0, 4000) : null,
      normalizeRiskLevel(riskLevel),
      toPositiveIntOrNull(createdBy),
      toPositiveIntOrNull(assignedTo),
    ]
  );
  return result.rows[0] || null;
}

export async function createOpsAlert({ incidentId, source, payloadRedacted }) {
  const result = await q(
    `INSERT INTO ops_alerts
      (incident_id, source, payload_redacted_json)
     VALUES ($1,$2,$3::jsonb)
     RETURNING *`,
    [toPositiveIntOrNull(incidentId), String(source || "unknown").trim().toLowerCase(), JSON.stringify(payloadRedacted || {})]
  );
  return result.rows[0] || null;
}

export async function listIncidents({
  severity,
  status,
  source,
  affectedModule,
  search,
  dateFrom,
  dateTo,
  limit = 80,
  beforeId = null,
} = {}) {
  const params = [];
  const filters = [];

  if (severity && severity !== "all") {
    params.push(normalizeSeverity(severity));
    filters.push(`severity = $${params.length}`);
  }
  if (status && status !== "all") {
    params.push(normalizeIncidentStatus(status));
    filters.push(`status = $${params.length}`);
  }
  if (source && source !== "all") {
    params.push(String(source).trim().toLowerCase());
    filters.push(`source = $${params.length}`);
  }
  if (affectedModule && affectedModule !== "all") {
    params.push(String(affectedModule).trim());
    filters.push(`affected_module = $${params.length}`);
  }
  if (search) {
    params.push(`%${String(search).trim()}%`);
    filters.push(`(title ILIKE $${params.length} OR summary ILIKE $${params.length})`);
  }
  const fromIso = asIso(dateFrom);
  if (fromIso) {
    params.push(fromIso);
    filters.push(`created_at >= $${params.length}::timestamptz`);
  }
  const toIso = asIso(dateTo);
  if (toIso) {
    params.push(toIso);
    filters.push(`created_at <= $${params.length}::timestamptz`);
  }
  const safeBeforeId = toPositiveIntOrNull(beforeId);
  if (safeBeforeId) {
    params.push(safeBeforeId);
    filters.push(`id < $${params.length}`);
  }

  params.push(safeLimit(limit, 80, 300));
  const where = filters.length ? `WHERE ${filters.join(" AND ")}` : "";

  const result = await q(
    `SELECT *
     FROM ops_incidents
     ${where}
     ORDER BY created_at DESC, id DESC
     LIMIT $${params.length}`,
    params
  );

  return result.rows;
}

export async function getIncidentById(id) {
  const incidentId = toPositiveIntOrNull(id);
  if (!incidentId) return null;
  const incidentResult = await q(
    `SELECT *
     FROM ops_incidents
     WHERE id = $1
     LIMIT 1`,
    [incidentId]
  );
  const incident = incidentResult.rows[0] || null;
  if (!incident) return null;

  const [alertsResult, actionsResult] = await Promise.all([
    q(
      `SELECT *
       FROM ops_alerts
       WHERE incident_id = $1
       ORDER BY received_at DESC, id DESC`,
      [incidentId]
    ),
    q(
      `SELECT *
       FROM ops_actions
       WHERE incident_id = $1
       ORDER BY created_at DESC, id DESC`,
      [incidentId]
    ),
  ]);

  return {
    ...incident,
    alerts: alertsResult.rows,
    actions: actionsResult.rows,
  };
}

export async function markIncidentResolved({ incidentId, actorUserId }) {
  const id = toPositiveIntOrNull(incidentId);
  if (!id) return null;
  const result = await q(
    `UPDATE ops_incidents
     SET status = 'resolved',
         resolved_at = NOW(),
         updated_at = NOW(),
         assigned_to = COALESCE(assigned_to, $2)
     WHERE id = $1
     RETURNING *`,
    [id, toPositiveIntOrNull(actorUserId)]
  );
  return result.rows[0] || null;
}

export async function appendIncidentEvidence({ incidentId, evidenceItem }) {
  const id = toPositiveIntOrNull(incidentId);
  if (!id) return null;
  const current = await q(
    `SELECT evidence_json
     FROM ops_incidents
     WHERE id = $1
     LIMIT 1`,
    [id]
  );
  const existing = Array.isArray(current.rows[0]?.evidence_json)
    ? current.rows[0].evidence_json
    : asJson(current.rows[0]?.evidence_json, []);

  const merged = [...existing, evidenceItem].slice(-200);
  const result = await q(
    `UPDATE ops_incidents
     SET evidence_json = $2::jsonb,
         updated_at = NOW()
     WHERE id = $1
     RETURNING *`,
    [id, JSON.stringify(merged)]
  );
  return result.rows[0] || null;
}

export async function createAction({
  incidentId,
  actionType,
  riskLevel,
  status = "pending_approval",
  requestedBy = null,
  input = {},
  output = {},
}) {
  const result = await q(
    `INSERT INTO ops_actions
      (
        incident_id,
        action_type,
        risk_level,
        status,
        requested_by,
        input_json,
        output_json
      )
     VALUES ($1,$2,$3,$4,$5,$6::jsonb,$7::jsonb)
     RETURNING *`,
    [
      toPositiveIntOrNull(incidentId),
      String(actionType || "unknown").trim().toLowerCase(),
      normalizeRiskLevel(riskLevel),
      normalizeActionStatus(status),
      toPositiveIntOrNull(requestedBy),
      JSON.stringify(input || {}),
      JSON.stringify(output || {}),
    ]
  );
  return result.rows[0] || null;
}

export async function getActionById(actionId) {
  const id = toPositiveIntOrNull(actionId);
  if (!id) return null;
  const result = await q(
    `SELECT *
     FROM ops_actions
     WHERE id = $1
     LIMIT 1`,
    [id]
  );
  return result.rows[0] || null;
}

export async function getLatestActionByIncident({ incidentId, status = null }) {
  const id = toPositiveIntOrNull(incidentId);
  if (!id) return null;
  const params = [id];
  let extraFilter = "";
  if (status) {
    params.push(normalizeActionStatus(status));
    extraFilter = `AND status = $${params.length}`;
  }

  const result = await q(
    `SELECT *
     FROM ops_actions
     WHERE incident_id = $1
       ${extraFilter}
     ORDER BY created_at DESC, id DESC
     LIMIT 1`,
    params
  );

  return result.rows[0] || null;
}

export async function approveAction({
  actionId,
  approverUserId,
  comment = null,
}) {
  const id = toPositiveIntOrNull(actionId);
  const approverId = toPositiveIntOrNull(approverUserId);
  if (!id || !approverId) return null;

  const result = await q(
    `UPDATE ops_actions
     SET status = 'approved',
         approved_by = $2,
         approved_at = NOW(),
         updated_at = NOW()
     WHERE id = $1
     RETURNING *`,
    [id, approverId]
  );

  const row = result.rows[0] || null;
  if (!row) return null;

  await q(
    `INSERT INTO ops_action_approvals
      (action_id, approver_user_id, decision, comment)
     VALUES ($1,$2,'approved',$3)`,
    [id, approverId, comment ? String(comment).slice(0, 2000) : null]
  );

  return row;
}

export async function rejectAction({
  actionId,
  rejectorUserId,
  rejectionReason = null,
}) {
  const id = toPositiveIntOrNull(actionId);
  const rejectorId = toPositiveIntOrNull(rejectorUserId);
  if (!id || !rejectorId) return null;

  const result = await q(
    `UPDATE ops_actions
     SET status = 'rejected',
         rejected_by = $2,
         rejected_at = NOW(),
         rejection_reason = $3,
         updated_at = NOW()
     WHERE id = $1
     RETURNING *`,
    [id, rejectorId, rejectionReason ? String(rejectionReason).slice(0, 2000) : null]
  );

  const row = result.rows[0] || null;
  if (!row) return null;

  await q(
    `INSERT INTO ops_action_approvals
      (action_id, approver_user_id, decision, comment)
     VALUES ($1,$2,'rejected',$3)`,
    [id, rejectorId, rejectionReason ? String(rejectionReason).slice(0, 2000) : null]
  );

  return row;
}

export async function markActionExecuted({
  actionId,
  status = "executed",
  output = {},
}) {
  const id = toPositiveIntOrNull(actionId);
  if (!id) return null;
  const normalized = normalizeActionStatus(status, "executed");
  const result = await q(
    `UPDATE ops_actions
     SET status = $2::text,
         output_json = $3::jsonb,
         executed_at = CASE WHEN $2::text = 'executed' THEN NOW() ELSE executed_at END,
         updated_at = NOW()
     WHERE id = $1
     RETURNING *`,
    [id, normalized, JSON.stringify(output || {})]
  );
  return result.rows[0] || null;
}

export async function listPendingActions({ limit = 120 } = {}) {
  const result = await q(
    `SELECT a.*, i.title AS incident_title, i.severity, i.affected_module, i.affected_service
     FROM ops_actions a
     JOIN ops_incidents i ON i.id = a.incident_id
     WHERE a.status = 'pending_approval'
     ORDER BY a.created_at DESC, a.id DESC
     LIMIT $1`,
    [safeLimit(limit, 120, 300)]
  );
  return result.rows;
}

export async function listAuditLogs({ incidentId = null, limit = 200 } = {}) {
  const params = [];
  const filters = [];

  const id = toPositiveIntOrNull(incidentId);
  if (id) {
    params.push(String(id));
    filters.push(`target_id = $${params.length}`);
  }

  params.push(safeLimit(limit, 200, 500));
  const where = filters.length ? `WHERE ${filters.join(" AND ")}` : "";

  const result = await q(
    `SELECT *
     FROM ops_audit_logs
     ${where}
     ORDER BY created_at DESC, id DESC
     LIMIT $${params.length}`,
    params
  );
  return result.rows;
}

export async function getOpsSettings() {
  const result = await q(`SELECT key, value_json FROM ops_settings ORDER BY key ASC`);
  const merged = {
    ...OPS_SETTINGS_DEFAULTS,
    ai_analysis_enabled: env.opsEnableAiAnalysis,
    auto_restart_enabled: env.opsEnableAutoRestart,
    auto_rollback_enabled: env.opsEnableAutoRollback,
    feature_flag_disable_enabled: env.opsEnableFeatureFlagDisable,
    require_second_approval_for_critical: env.opsRequireSecondApprovalForCritical,
  };
  for (const row of result.rows) {
    merged[String(row.key)] = row.value_json;
  }
  return merged;
}

export async function upsertOpsSetting({ key, value, updatedBy }) {
  const settingKey = String(key || "").trim();
  if (!settingKey) return null;

  const result = await q(
    `INSERT INTO ops_settings (key, value_json, updated_by)
     VALUES ($1, $2::jsonb, $3)
     ON CONFLICT (key)
     DO UPDATE SET
       value_json = EXCLUDED.value_json,
       updated_by = EXCLUDED.updated_by,
       updated_at = NOW()
     RETURNING *`,
    [settingKey, JSON.stringify(value), toPositiveIntOrNull(updatedBy)]
  );
  return result.rows[0] || null;
}

export async function getOpsStatusOverview() {
  const [openCount, sev1Count, sev2Count, pendingActions, lastCritical] = await Promise.all([
    q(`SELECT COUNT(*)::int AS count FROM ops_incidents WHERE status <> 'resolved'`),
    q(
      `SELECT COUNT(*)::int AS count
       FROM ops_incidents
       WHERE status <> 'resolved' AND severity = 'SEV1'`
    ),
    q(
      `SELECT COUNT(*)::int AS count
       FROM ops_incidents
       WHERE status <> 'resolved' AND severity = 'SEV2'`
    ),
    q(
      `SELECT COUNT(*)::int AS count
       FROM ops_actions
       WHERE status = 'pending_approval'`
    ),
    q(
      `SELECT id, title, severity, status, affected_module, created_at
       FROM ops_incidents
       WHERE risk_level IN ('high','critical')
       ORDER BY created_at DESC, id DESC
       LIMIT 1`
    ),
  ]);

  return {
    openIncidents: Number(openCount.rows[0]?.count || 0),
    sev1Open: Number(sev1Count.rows[0]?.count || 0),
    sev2Open: Number(sev2Count.rows[0]?.count || 0),
    pendingApprovals: Number(pendingActions.rows[0]?.count || 0),
    lastCriticalIncident: lastCritical.rows[0] || null,
  };
}

export function mapRiskFromSeverity(severity) {
  const rank = severityToRank(severity);
  if (rank >= 4) return "critical";
  if (rank === 3) return "high";
  if (rank === 2) return "medium";
  return "low";
}

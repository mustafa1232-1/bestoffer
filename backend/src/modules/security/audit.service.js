/**
 * Purpose:
 * سجل تدقيق موحّد (المرحلة 11) مبني على جدول admin_audit_event الموجود.
 * يكتب: الفاعل، الفعل، المورد، قبل/بعد (مع إخفاء الحقول الحساسة)، الوقت من
 * الخادم، IP/session، السبب، رقم التذكرة، النتيجة، والصلاحية المستخدمة.
 *
 * لا يُسجّل tokens/كلمات مرور/أسرار. الكتابة best-effort ولا تُفشل الطلب الأصلي.
 */

import { q } from "../../config/db.js";

// حقول تُخفى دائماً إذا ظهرت في before/after.
const SENSITIVE_KEY_PATTERN =
  /(pin|password|pass_hash|token|secret|otp|cvv|card|iban|recovery)/i;

function maskValue(value, depth = 0) {
  if (value == null || depth > 6) return value;
  if (Array.isArray(value)) return value.map((v) => maskValue(v, depth + 1));
  if (typeof value === "object") {
    const out = {};
    for (const [k, v] of Object.entries(value)) {
      out[k] = SENSITIVE_KEY_PATTERN.test(k) ? "***" : maskValue(v, depth + 1);
    }
    return out;
  }
  return value;
}

/**
 * يكتب حدث تدقيق. لا يرمي استثناءً (يسجّل تحذيراً فقط عند الفشل).
 */
export async function recordAudit({
  actorUserId = null,
  actorRole = null,
  actionKey,
  summary,
  targetType = null,
  targetId = null,
  targetLabel = null,
  metadata = null,
  before = null,
  after = null,
  reason = null,
  result = "ok",
  permissionKey = null,
  ipAddress = null,
  sessionId = null,
  ticketId = null,
}) {
  try {
    await q(
      `INSERT INTO admin_audit_event
         (actor_user_id, actor_role, action_key, summary, target_type, target_id,
          target_label, metadata, before_json, after_json, reason, result,
          permission_key, ip_address, session_id, ticket_id)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16)`,
      [
        actorUserId ? Number(actorUserId) : null,
        actorRole ? String(actorRole).slice(0, 40) : null,
        String(actionKey).slice(0, 120),
        String(summary || actionKey).slice(0, 2000),
        targetType ? String(targetType).slice(0, 80) : null,
        targetId != null ? Number(targetId) || null : null,
        targetLabel ? String(targetLabel).slice(0, 200) : null,
        metadata ? JSON.stringify(maskValue(metadata)) : null,
        before ? JSON.stringify(maskValue(before)) : null,
        after ? JSON.stringify(maskValue(after)) : null,
        reason ? String(reason).slice(0, 2000) : null,
        String(result || "ok").slice(0, 16),
        permissionKey ? String(permissionKey).slice(0, 80) : null,
        ipAddress ? String(ipAddress).slice(0, 128) : null,
        sessionId != null ? Number(sessionId) || null : null,
        ticketId != null ? Number(ticketId) || null : null,
      ]
    );
    return { ok: true };
  } catch (error) {
    console.warn("[audit] recordAudit failed", error?.message || error);
    return { ok: false };
  }
}

/**
 * يستخرج سياق التدقيق (الفاعل/الدور/IP/الجلسة) من request بشكل موحّد.
 */
export function auditContextFromReq(req) {
  return {
    actorUserId: req?.userId || null,
    actorRole: req?.userRole || null,
    ipAddress:
      req?.authDeviceContext?.ipAddress ||
      req?.headers?.["x-forwarded-for"] ||
      req?.ip ||
      null,
    sessionId: req?.authSessionId || null,
  };
}

export async function searchAuditEvents({
  actorUserId = null,
  targetType = null,
  targetId = null,
  actionKey = null,
  from = null,
  to = null,
  limit = 50,
  offset = 0,
} = {}) {
  const safeLimit = Math.max(1, Math.min(200, Number(limit) || 50));
  const safeOffset = Math.max(0, Number(offset) || 0);
  const conds = [];
  const params = [];

  if (actorUserId) {
    params.push(Number(actorUserId));
    conds.push(`actor_user_id = $${params.length}`);
  }
  if (targetType) {
    params.push(String(targetType));
    conds.push(`target_type = $${params.length}`);
  }
  if (targetId) {
    params.push(Number(targetId));
    conds.push(`target_id = $${params.length}`);
  }
  if (actionKey) {
    params.push(String(actionKey));
    conds.push(`action_key = $${params.length}`);
  }
  if (from) {
    params.push(from);
    conds.push(`created_at >= $${params.length}`);
  }
  if (to) {
    params.push(to);
    conds.push(`created_at <= $${params.length}`);
  }
  const where = conds.length ? `WHERE ${conds.join(" AND ")}` : "";

  const countRes = await q(
    `SELECT COUNT(*)::int AS total FROM admin_audit_event ${where}`,
    params
  );
  params.push(safeLimit);
  params.push(safeOffset);
  const rows = await q(
    `SELECT id, actor_user_id, actor_role, action_key, summary, target_type,
            target_id, target_label, metadata, before_json, after_json, reason,
            result, permission_key, ip_address, session_id, ticket_id, created_at
     FROM admin_audit_event
     ${where}
     ORDER BY created_at DESC, id DESC
     LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );

  return {
    total: Number(countRes.rows[0]?.total || 0),
    limit: safeLimit,
    offset: safeOffset,
    items: rows.rows,
  };
}

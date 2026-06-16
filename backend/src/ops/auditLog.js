import { q } from "../config/db.js";

function toInt(value, fallback = null) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return fallback;
  const out = Math.trunc(parsed);
  return out > 0 ? out : fallback;
}

export function buildAuditActor(req) {
  return {
    actorUserId: toInt(req?.userId) ?? toInt(req?.authUserId),
    actorRole: String(req?.userRole || req?.authUserRole || "unknown")
      .trim()
      .toLowerCase(),
    ipAddress:
      String(req?.headers?.["x-forwarded-for"] || req?.ip || req?.socket?.remoteAddress || "")
        .split(",")[0]
        .trim() || null,
    userAgent: String(req?.headers?.["user-agent"] || "").trim() || null,
  };
}

export async function insertOpsAuditLog({
  actorUserId = null,
  actorRole = null,
  action,
  targetType,
  targetId = null,
  metadata = {},
  ipAddress = null,
  userAgent = null,
}) {
  const result = await q(
    `INSERT INTO ops_audit_logs
      (
        actor_user_id,
        actor_role,
        action,
        target_type,
        target_id,
        metadata_json,
        ip_address,
        user_agent
      )
     VALUES ($1,$2,$3,$4,$5,$6::jsonb,$7,$8)
     RETURNING *`,
    [
      toInt(actorUserId),
      actorRole ? String(actorRole).trim().toLowerCase() : null,
      String(action || "unknown").trim().toLowerCase(),
      String(targetType || "unknown").trim().toLowerCase(),
      targetId == null ? null : String(targetId),
      JSON.stringify(metadata && typeof metadata === "object" ? metadata : {}),
      ipAddress ? String(ipAddress).slice(0, 128) : null,
      userAgent ? String(userAgent).slice(0, 512) : null,
    ]
  );
  return result.rows[0] || null;
}

import { q } from "../../config/db.js";

const ALLOWED_SCOPES = new Set(["customer", "store", "courier"]);
const ALLOWED_ACTIONS = new Set(["cancel", "return"]);

export function normalizeOrderActionScope(value, { fallback = null } = {}) {
  const normalized = String(value || "").trim().toLowerCase();
  if (ALLOWED_SCOPES.has(normalized)) return normalized;
  return fallback;
}

export function normalizeOrderActionKind(value, { fallback = null } = {}) {
  const normalized = String(value || "").trim().toLowerCase();
  if (ALLOWED_ACTIONS.has(normalized)) return normalized;
  return fallback;
}

export async function listOrderActionReasons({
  actorScope = null,
  actionKind = null,
} = {}) {
  const scope = normalizeOrderActionScope(actorScope);
  const action = normalizeOrderActionKind(actionKind);
  if (actorScope != null && !scope) return [];
  if (actionKind != null && !action) return [];

  const params = [];
  const where = ["is_active = TRUE"];
  if (scope) {
    params.push(scope);
    where.push(`actor_scope = $${params.length}`);
  }
  if (action) {
    params.push(action);
    where.push(`action_kind = $${params.length}`);
  }

  const r = await q(
    `SELECT
       actor_scope,
       action_kind,
       reason_code,
       reason_label_ar,
       reason_label_en,
       allows_other_text,
       sort_order
     FROM order_action_reason_catalog
     WHERE ${where.join(" AND ")}
     ORDER BY actor_scope ASC, action_kind ASC, sort_order ASC, id ASC`
  ,
    params
  );

  return r.rows.map((row) => ({
    actorScope: String(row.actor_scope || ""),
    actionKind: String(row.action_kind || ""),
    reasonCode: String(row.reason_code || ""),
    reasonLabelAr: String(row.reason_label_ar || ""),
    reasonLabelEn:
      row.reason_label_en == null ? null : String(row.reason_label_en),
    allowsOtherText: row.allows_other_text === true,
    sortOrder: Number(row.sort_order || 0),
  }));
}

export async function getOrderActionReason({
  actorScope,
  actionKind,
  reasonCode,
}) {
  const scope = normalizeOrderActionScope(actorScope);
  const action = normalizeOrderActionKind(actionKind);
  const code = String(reasonCode || "").trim().toLowerCase();
  if (!scope || !action || !code) return null;

  const r = await q(
    `SELECT
       actor_scope,
       action_kind,
       reason_code,
       reason_label_ar,
       reason_label_en,
       allows_other_text,
       sort_order
     FROM order_action_reason_catalog
     WHERE actor_scope = $1
       AND action_kind = $2
       AND reason_code = $3
       AND is_active = TRUE
     LIMIT 1`,
    [scope, action, code]
  );
  const row = r.rows[0];
  if (!row) return null;
  return {
    actorScope: String(row.actor_scope || ""),
    actionKind: String(row.action_kind || ""),
    reasonCode: String(row.reason_code || ""),
    reasonLabelAr: String(row.reason_label_ar || ""),
    reasonLabelEn: row.reason_label_en == null ? null : String(row.reason_label_en),
    allowsOtherText: row.allows_other_text === true,
    sortOrder: Number(row.sort_order || 0),
  };
}

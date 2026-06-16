import { normalizeActionType, normalizeRiskLevel } from "./types.js";

const CRITICAL_ACTION_TYPES = new Set([
  "rollback_payment_service",
  "rollback_order_service",
  "rollback_database",
  "database_migration",
  "payment_logic_change",
  "deploy_production",
  "merge_pull_request",
  "secret_change",
  "auth_change",
  "authorization_change",
]);

const FORBIDDEN_ACTION_TYPES = new Set([
  "merge_to_main",
  "merge_pull_request",
  "deploy_production",
  "edit_secret",
  "edit_env",
  "destructive_sql",
  "delete_production_data",
  "auto_payment_change",
  "auto_wallet_change",
  "auto_settlement_change",
  "auto_commission_change",
]);

const SAFE_AUTO_ACTIONS = new Set([
  "analyze_incident",
  "create_github_issue",
  "request_code_fix",
  "notify_admin",
  "re_analyze",
]);

const SAFE_APPROVAL_ACTIONS = new Set([
  "restart_service",
  "disable_feature_flag",
  "clear_cache",
  "rollback_service",
]);

function hasSensitiveScope(input) {
  const json = JSON.stringify(input || {}).toLowerCase();
  return [
    "payment",
    "wallet",
    "settlement",
    "refund",
    "commission",
    "auth",
    "authorization",
    "permission",
    "secret",
    "env",
    "migration",
    "database",
    "production",
  ].some((token) => json.includes(token));
}

export function classifyActionRisk(actionType, input = {}) {
  const normalized = normalizeActionType(actionType, String(actionType || "").toLowerCase());
  if (CRITICAL_ACTION_TYPES.has(normalized)) return "critical";
  if (FORBIDDEN_ACTION_TYPES.has(normalized)) return "critical";
  if (hasSensitiveScope(input)) return "high";
  if (SAFE_APPROVAL_ACTIONS.has(normalized)) return "medium";
  if (SAFE_AUTO_ACTIONS.has(normalized)) return "low";
  return "medium";
}

export function isForbiddenAction(actionType) {
  const normalized = String(actionType || "").trim().toLowerCase();
  return FORBIDDEN_ACTION_TYPES.has(normalized);
}

export function requiresHumanApproval(actionType, riskLevel) {
  const normalizedRisk = normalizeRiskLevel(riskLevel, "medium");
  if (normalizedRisk === "low") return false;
  return true;
}

export function requiresTypedConfirmation(riskLevel) {
  const normalizedRisk = normalizeRiskLevel(riskLevel, "medium");
  return normalizedRisk === "high" || normalizedRisk === "critical";
}

export function canAutoExecuteAction({
  actionType,
  riskLevel,
  settings = {},
  input = {},
}) {
  const normalizedType = String(actionType || "").trim().toLowerCase();
  const normalizedRisk = normalizeRiskLevel(riskLevel, "medium");

  if (isForbiddenAction(normalizedType)) {
    return {
      allowed: false,
      reason: "forbidden_action_type",
    };
  }

  if (normalizedRisk !== "low") {
    return {
      allowed: false,
      reason: "human_approval_required",
    };
  }

  if (!SAFE_AUTO_ACTIONS.has(normalizedType)) {
    return {
      allowed: false,
      reason: "not_in_safe_auto_actions",
    };
  }

  if (normalizedType === "request_code_fix") {
    const content = JSON.stringify(input || {}).toLowerCase();
    if (hasSensitiveScope(content)) {
      return {
        allowed: false,
        reason: "sensitive_scope_requires_approval",
      };
    }
  }

  if (normalizedType === "restart_service" && settings.auto_restart_enabled !== true) {
    return {
      allowed: false,
      reason: "auto_restart_disabled",
    };
  }

  if (normalizedType === "rollback_service" && settings.auto_rollback_enabled !== true) {
    return {
      allowed: false,
      reason: "auto_rollback_disabled",
    };
  }

  if (
    normalizedType === "disable_feature_flag" &&
    settings.feature_flag_disable_enabled !== true
  ) {
    return {
      allowed: false,
      reason: "feature_flag_disable_disabled",
    };
  }

  return {
    allowed: true,
    reason: "safe_auto_action",
  };
}

export function validateTypedConfirmation({ riskLevel, confirmationText }) {
  if (!requiresTypedConfirmation(riskLevel)) {
    return {
      ok: true,
      reason: "not_required",
    };
  }

  const normalized = String(confirmationText || "")
    .trim()
    .toUpperCase();

  if (
    normalized === "APPROVE" ||
    normalized === "CONFIRM" ||
    normalized === "CONFIRM CRITICAL ACTION"
  ) {
    return {
      ok: true,
      reason: "confirmed",
    };
  }

  return {
    ok: false,
    reason: "typed_confirmation_required",
  };
}

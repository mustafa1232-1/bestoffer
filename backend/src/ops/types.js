export const OPS_SEVERITIES = ["SEV1", "SEV2", "SEV3", "SEV4"];
export const OPS_RISK_LEVELS = ["low", "medium", "high", "critical"];

export const OPS_INCIDENT_STATUSES = [
  "open",
  "investigating",
  "waiting_approval",
  "in_progress",
  "resolved",
  "rejected",
];

export const OPS_ACTION_STATUSES = [
  "pending_approval",
  "approved",
  "rejected",
  "executing",
  "executed",
  "failed",
  "cancelled",
];

export const OPS_ALLOWED_ACTION_TYPES = [
  "analyze_incident",
  "create_github_issue",
  "request_code_fix",
  "restart_service",
  "rollback_service",
  "disable_feature_flag",
  "clear_cache",
  "notify_admin",
  "mark_resolved",
  "re_analyze",
];

export const OPS_PERMISSION_KEYS = {
  access: "ai_dev_support_access",
  viewIncidents: "ai_dev_support_view_incidents",
  approveAction: "ai_dev_support_approve_action",
  rejectAction: "ai_dev_support_reject_action",
  requestCodeFix: "ai_dev_support_request_code_fix",
  createGithubIssue: "ai_dev_support_create_github_issue",
  manageSettings: "ai_dev_support_manage_settings",
  viewAuditLogs: "ai_dev_support_view_audit_logs",
};

export const OPS_SETTINGS_DEFAULTS = {
  ai_analysis_enabled: true,
  sentry_webhook_enabled: true,
  datadog_webhook_enabled: true,
  github_issue_creation_enabled: true,
  auto_restart_enabled: false,
  auto_rollback_enabled: false,
  feature_flag_disable_enabled: false,
  notification_min_severity: "SEV2",
  require_second_approval_for_critical: false,
};

export function normalizeSeverity(value, fallback = "SEV3") {
  const normalized = String(value || "").trim().toUpperCase();
  return OPS_SEVERITIES.includes(normalized) ? normalized : fallback;
}

export function normalizeRiskLevel(value, fallback = "medium") {
  const normalized = String(value || "").trim().toLowerCase();
  return OPS_RISK_LEVELS.includes(normalized) ? normalized : fallback;
}

export function normalizeIncidentStatus(value, fallback = "open") {
  const normalized = String(value || "").trim().toLowerCase();
  return OPS_INCIDENT_STATUSES.includes(normalized) ? normalized : fallback;
}

export function normalizeActionStatus(value, fallback = "pending_approval") {
  const normalized = String(value || "").trim().toLowerCase();
  return OPS_ACTION_STATUSES.includes(normalized) ? normalized : fallback;
}

export function normalizeActionType(value, fallback = "analyze_incident") {
  const normalized = String(value || "").trim().toLowerCase();
  return OPS_ALLOWED_ACTION_TYPES.includes(normalized) ? normalized : fallback;
}

export function severityToRank(severity) {
  switch (normalizeSeverity(severity, "SEV4")) {
    case "SEV1":
      return 4;
    case "SEV2":
      return 3;
    case "SEV3":
      return 2;
    default:
      return 1;
  }
}

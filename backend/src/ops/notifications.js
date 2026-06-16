import { q } from "../config/db.js";
import { createManyNotifications } from "../modules/notifications/notifications.repo.js";
import { normalizeSeverity, severityToRank } from "./types.js";

function toInt(value, fallback = null) {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  const out = Math.trunc(n);
  return out > 0 ? out : fallback;
}

function shouldNotify(minSeverity, severity) {
  return severityToRank(severity) >= severityToRank(minSeverity || "SEV2");
}

export async function listSuperAdminRecipients() {
  const result = await q(
    `SELECT id
     FROM app_user
     WHERE is_super_admin = TRUE
     ORDER BY id ASC`
  );
  return result.rows.map((row) => Number(row.id)).filter((id) => Number.isInteger(id) && id > 0);
}

export async function createOpsNotificationRecords({
  incidentId,
  recipients,
  title,
  body,
  priority = "high",
  channel = "in_app",
}) {
  const userIds = Array.isArray(recipients)
    ? recipients.map((value) => toInt(value)).filter((value) => value != null)
    : [];

  if (userIds.length <= 0) return [];

  const values = [];
  const params = [];
  userIds.forEach((userId, index) => {
    const offset = index * 6;
    values.push(`($${offset + 1},$${offset + 2},$${offset + 3},$${offset + 4},$${offset + 5},$${offset + 6})`);
    params.push(incidentId, userId, channel, title, body, priority);
  });

  const result = await q(
    `INSERT INTO ops_notifications
      (incident_id, user_id, channel, title, body, priority)
     VALUES ${values.join(",")}
     RETURNING *`,
    params
  );

  return result.rows;
}

export async function notifySuperAdminsAboutIncident({ incident, settings = {} }) {
  const severity = normalizeSeverity(incident?.severity || "SEV3");
  if (!shouldNotify(settings.notification_min_severity, severity)) {
    return {
      sent: false,
      reason: "below_min_severity",
    };
  }

  const recipients = await listSuperAdminRecipients();
  if (recipients.length <= 0) {
    return {
      sent: false,
      reason: "no_super_admins",
    };
  }

  const title =
    severity === "SEV1"
      ? "??? ??? ?? ????? - SEV1"
      : `AI DEV SUPPORT Alert - ${severity}`;

  const body =
    severity === "SEV1"
      ? `?? ?????? ??? ??? ?? ${incident?.affected_module || "??????"}. ???? AI DEV SUPPORT ???????? ????????? ??? ??????? ???????.`
      : `?? ?????? ??? ???? ?? ${incident?.affected_module || "??????"}.`; 

  await createOpsNotificationRecords({
    incidentId: incident?.id,
    recipients,
    title,
    body,
    priority: severity === "SEV1" ? "critical" : "high",
    channel: "in_app",
  });

  await createManyNotifications(
    recipients.map((userId) => ({
      userId,
      type: "admin.ops.ai_dev_support.incident",
      title,
      body,
      payload: {
        target: "admin_ai_dev_support_incident_details",
        entityType: "ops_incident",
        entityId: incident?.id,
        incidentId: incident?.id,
        severity,
        affectedModule: incident?.affected_module || null,
      },
    }))
  );

  return {
    sent: true,
    recipientsCount: recipients.length,
  };
}

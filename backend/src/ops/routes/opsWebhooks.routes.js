import { Router } from "express";

import { env as runtimeEnv } from "../../config/env.js";
import { insertOpsAuditLog } from "../auditLog.js";
import { analyzeIncidentWithAi } from "../aiOpsAgent.js";
import { createAction, createIncident, createOpsAlert, getOpsSettings } from "../ops.repo.js";
import { requireOpsWebhookApiKey } from "../opsAuth.js";
import { notifySuperAdminsAboutIncident } from "../notifications.js";
import { mapDatadogWebhookToIncident } from "../tools/datadogTool.js";
import { mapSentryWebhookToIncident } from "../tools/sentryTool.js";

function mapGithubWebhook(payload = {}) {
  const workflow = String(payload?.workflow || payload?.workflow_name || "GitHub Actions").trim();
  const conclusion = String(payload?.conclusion || payload?.workflow_run?.conclusion || "").trim();
  const status = String(payload?.status || payload?.workflow_run?.status || "").trim();
  const branch = String(payload?.workflow_run?.head_branch || payload?.ref || "").trim();
  const title = `GitHub Actions ${workflow}`;
  const summary = `status=${status || "unknown"} conclusion=${conclusion || "n/a"} branch=${branch || "n/a"}`;

  return {
    source: "github_actions",
    title,
    summary,
    payload,
    metadata: {
      workflow,
      status,
      conclusion,
      branch,
      runUrl: payload?.workflow_run?.html_url || payload?.html_url || null,
    },
  };
}

async function createIncidentFromWebhook({ env, sourceEvent }) {
  const settings = await getOpsSettings();
  const analysisOut = await analyzeIncidentWithAi({
    env,
    source: sourceEvent.source,
    title: sourceEvent.title,
    summary: sourceEvent.summary,
    payload: sourceEvent.payload,
    logs: Array.isArray(sourceEvent.payload?.logs) ? sourceEvent.payload.logs : [],
    settings,
  });

  const analysis = analysisOut.analysis;
  const incident = await createIncident({
    source: sourceEvent.source,
    severity: analysis.severity,
    status: "open",
    affectedService: analysis.affected_service,
    affectedModule: analysis.affected_module,
    title: sourceEvent.title,
    summary: sourceEvent.summary,
    symptoms: analysis.symptoms,
    probableRootCause: analysis.probable_root_cause,
    evidence: [
      ...analysis.evidence,
      sourceEvent.metadata,
    ].filter(Boolean),
    suggestedMitigation: analysis.immediate_mitigation,
    longTermFix: analysis.long_term_fix,
    riskLevel: analysis.risk_level,
    createdBy: null,
    assignedTo: null,
  });

  await createOpsAlert({
    incidentId: incident.id,
    source: sourceEvent.source,
    payloadRedacted: {
      payload: sourceEvent.payload,
      metadata: sourceEvent.metadata,
      redactionMeta: analysisOut.redactionMeta,
    },
  });

  await createAction({
    incidentId: incident.id,
    actionType: "notify_admin",
    riskLevel: analysis.risk_level,
    status: "executed",
    requestedBy: null,
    input: {
      source: sourceEvent.source,
    },
    output: {
      provider: analysisOut.provider,
    },
  });

  const shouldProposeRestart =
    ["railway", "datadog"].includes(String(sourceEvent.source || "").toLowerCase()) &&
    ["high", "critical"].includes(String(analysis.risk_level || "").toLowerCase());

  if (shouldProposeRestart) {
    await createAction({
      incidentId: incident.id,
      actionType: "restart_service",
      riskLevel: String(analysis.risk_level || "high").toLowerCase(),
      status: "pending_approval",
      requestedBy: null,
      input: {
        serviceName: String(env.railwayBestofferServiceName || "bestoffer"),
        serviceId: String(env.railwayBestofferServiceId || "").trim() || null,
        reason: "Auto-proposed restart based on high-risk infrastructure alert",
        source: sourceEvent.source,
      },
      output: {
        policy: "human_approval_required",
      },
    });
  }

  await notifySuperAdminsAboutIncident({ incident, settings });
  await insertOpsAuditLog({
    actorUserId: null,
    actorRole: "system",
    action: "ops_webhook_incident_created",
    targetType: "incident",
    targetId: incident.id,
    metadata: {
      source: sourceEvent.source,
      provider: analysisOut.provider,
    },
  });

  return {
    incident,
    analysis,
    provider: analysisOut.provider,
  };
}

export function createOpsWebhooksRouter({ env = runtimeEnv } = {}) {
  const router = Router();
  router.use(requireOpsWebhookApiKey(env));

  router.post("/sentry", async (req, res, next) => {
    try {
      const settings = await getOpsSettings();
      if (settings.sentry_webhook_enabled === false) {
        return res.status(202).json({ accepted: false, reason: "sentry_webhook_disabled" });
      }

      const sourceEvent = mapSentryWebhookToIncident(req.body || {});
      const out = await createIncidentFromWebhook({ env, sourceEvent });
      return res.status(202).json({ accepted: true, ...out });
    } catch (error) {
      return next(error);
    }
  });

  router.post("/datadog", async (req, res, next) => {
    try {
      const settings = await getOpsSettings();
      if (settings.datadog_webhook_enabled === false) {
        return res.status(202).json({ accepted: false, reason: "datadog_webhook_disabled" });
      }

      const sourceEvent = mapDatadogWebhookToIncident(req.body || {});
      const out = await createIncidentFromWebhook({ env, sourceEvent });
      return res.status(202).json({ accepted: true, ...out });
    } catch (error) {
      return next(error);
    }
  });

  router.post("/github-actions", async (req, res, next) => {
    try {
      const sourceEvent = mapGithubWebhook(req.body || {});
      const out = await createIncidentFromWebhook({ env, sourceEvent });
      return res.status(202).json({ accepted: true, ...out });
    } catch (error) {
      return next(error);
    }
  });

  return router;
}

import { Router } from "express";

import { env as runtimeEnv } from "../../config/env.js";
import { buildAuditActor, insertOpsAuditLog } from "../auditLog.js";
import { analyzeIncidentWithAi } from "../aiOpsAgent.js";
import {
  appendIncidentEvidence,
  approveAction,
  createAction,
  createIncident,
  createOpsAlert,
  getIncidentById,
  getActionById,
  getLatestActionByIncident,
  getOpsSettings,
  getOpsStatusOverview,
  listAuditLogs,
  listIncidents,
  listPendingActions,
  mapRiskFromSeverity,
  markActionExecuted,
  markIncidentResolved,
  rejectAction,
  upsertOpsSetting,
} from "../ops.repo.js";
import { requireOpsAuth } from "../opsAuth.js";
import {
  canAutoExecuteAction,
  classifyActionRisk,
  requiresHumanApproval,
  validateTypedConfirmation,
} from "../policies.js";
import { notifySuperAdminsAboutIncident } from "../notifications.js";
import { disableFeatureFlag } from "../tools/featureFlagTool.js";
import {
  buildCodeFixPrompt,
  createCodeFixPullRequest,
  createGithubIssue,
  githubConfigFromEnv,
  isGithubConfigured,
} from "../tools/githubTool.js";
import {
  fetchRailwayStatus,
  railwayConfigFromEnv,
  restartRailwayService,
} from "../tools/railwayTool.js";
import {
  OPS_PERMISSION_KEYS,
  normalizeActionStatus,
  normalizeRiskLevel,
  normalizeSeverity,
} from "../types.js";

function toInt(value, fallback = 0) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.trunc(parsed);
}

function positiveIntOrNull(value) {
  const n = toInt(value, 0);
  return n > 0 ? n : null;
}

function badRequest(res, fields = [], message = "VALIDATION_ERROR") {
  return res.status(400).json({ message, fields });
}

function permissionMiddleware(permission) {
  return requireOpsAuth([OPS_PERMISSION_KEYS.access, permission]);
}

async function audit(req, action, targetType, targetId, metadata = {}) {
  const actor = buildAuditActor(req);
  await insertOpsAuditLog({
    actorUserId: actor.actorUserId,
    actorRole: actor.actorRole,
    action,
    targetType,
    targetId,
    metadata,
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });
}

async function resolveOpsStatus(env) {
  const overview = await getOpsStatusOverview();
  const railway = await fetchRailwayStatus(railwayConfigFromEnv(env));
  const railwayEnabled = railway?.ok === true;
  return {
    overview,
    integrations: {
      sentry: {
        enabled: Boolean(String(env.sentryDsn || "").trim()),
      },
      datadog: {
        enabled: Boolean(String(env.ddApiKey || "").trim()),
      },
      railway: {
        enabled: railwayEnabled,
        status: railwayEnabled ? railway?.status || null : null,
        reason: railwayEnabled ? null : railway?.reason || "railway_status_failed",
      },
      github: {
        enabled: isGithubConfigured(githubConfigFromEnv(env)),
      },
      openai: {
        enabled: Boolean(String(env.openaiApiKey || "").trim()),
      },
    },
    release: {
      version: String(env.appVersion || "unknown"),
      commit: String(env.gitCommitSha || "unknown"),
      environment: String(env.appEnv || env.nodeEnv || "development"),
    },
  };
}

function asPlainObject(value) {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return value;
  }
  if (typeof value === "string") {
    try {
      const parsed = JSON.parse(value);
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
        return parsed;
      }
    } catch (_) {
      // ignore invalid json
    }
  }
  return {};
}

function firstNonEmpty(values = []) {
  for (const value of values) {
    const out = String(value || "").trim();
    if (out) return out;
  }
  return "";
}

async function executeApprovedAction({
  env,
  action,
  incident,
  actorUserId,
  settings,
}) {
  const actionType = String(action?.action_type || "").trim().toLowerCase();
  const input = asPlainObject(action?.input_json);
  const output = {
    actionType,
    executedBy: actorUserId || null,
    attemptedAt: new Date().toISOString(),
  };

  if (!incident) {
    return {
      attempted: true,
      status: "failed",
      output: {
        ...output,
        reason: "incident_not_found",
      },
    };
  }

  if (actionType === "notify_admin") {
    const notifyResult = await notifySuperAdminsAboutIncident({ incident, settings });
    return {
      attempted: true,
      status: "executed",
      output: {
        ...output,
        notifyResult,
      },
    };
  }

  if (actionType === "restart_service") {
    const config = railwayConfigFromEnv(env);
    const serviceId = firstNonEmpty([
      input.serviceId,
      input.service_id,
      input.targetServiceId,
      input.target_service_id,
      env.railwayBestofferServiceId,
    ]);
    const serviceName = firstNonEmpty([
      input.serviceName,
      input.service_name,
      input.targetServiceName,
      input.target_service_name,
      env.railwayBestofferServiceName,
    ]);

    const restartResult = await restartRailwayService({
      config,
      serviceId,
      serviceName,
    });

    return {
      attempted: true,
      status: restartResult?.ok ? "executed" : "failed",
      output: {
        ...output,
        restartResult,
      },
    };
  }

  if (actionType === "disable_feature_flag") {
    const flagKey = firstNonEmpty([
      input.flagKey,
      input.flag_key,
      input.key,
    ]);
    const flagResult = await disableFeatureFlag({
      flagKey,
      actorUserId,
    });

    return {
      attempted: true,
      status: flagResult?.ok ? "executed" : "failed",
      output: {
        ...output,
        flagResult,
      },
    };
  }

  if (actionType === "create_github_issue") {
    if (settings?.github_issue_creation_enabled === false) {
      return {
        attempted: true,
        status: "failed",
        output: {
          ...output,
          reason: "github_issue_creation_disabled",
        },
      };
    }

    const githubResult = await createGithubIssue({
      config: githubConfigFromEnv(env),
      incident,
      title: firstNonEmpty([input.title, incident?.title]),
      body: firstNonEmpty([input.body, incident?.summary]),
      labels: Array.isArray(input.labels) ? input.labels : [],
    });

    if (githubResult?.ok) {
      await appendIncidentEvidence({
        incidentId: incident?.id,
        evidenceItem: {
          type: "github_issue",
          issue: githubResult.issue,
          at: new Date().toISOString(),
          source: "approved_action_execution",
        },
      });
    }

    return {
      attempted: true,
      status: githubResult?.ok ? "executed" : "failed",
      output: {
        ...output,
        githubResult,
      },
    };
  }

  if (actionType === "request_code_fix") {
    return {
      attempted: true,
      status: "executed",
      output: {
        ...output,
        info: "Action approved. Use request-code-fix with head branch for draft PR creation.",
      },
    };
  }

  return {
    attempted: false,
    status: "approved",
    output: {
      ...output,
      reason: "unsupported_action_type",
    },
  };
}

export function createOpsRouter({ env = runtimeEnv } = {}) {
  const router = Router();

  router.post(
    "/incidents/analyze",
    permissionMiddleware(OPS_PERMISSION_KEYS.viewIncidents),
    async (req, res, next) => {
      try {
        const source = String(req.body?.source || "manual").trim().toLowerCase();
        const title = String(req.body?.title || "New incident").trim();
        const summary = String(req.body?.summary || "").trim();
        if (!title) return badRequest(res, ["title"]);

        const settings = await getOpsSettings();
        const analysisOut = await analyzeIncidentWithAi({
          env,
          source,
          title,
          summary,
          payload: req.body?.payload || {},
          logs: Array.isArray(req.body?.logs) ? req.body.logs : [],
          settings,
        });

        const analysis = analysisOut.analysis;
        const incident = await createIncident({
          source,
          severity: normalizeSeverity(analysis.severity),
          status: "open",
          affectedService: analysis.affected_service,
          affectedModule: analysis.affected_module,
          title,
          summary,
          symptoms: analysis.symptoms,
          probableRootCause: analysis.probable_root_cause,
          evidence: analysis.evidence,
          suggestedMitigation: analysis.immediate_mitigation,
          longTermFix: analysis.long_term_fix,
          riskLevel: normalizeRiskLevel(analysis.risk_level),
          createdBy: req.userId,
          assignedTo: null,
        });

        await createOpsAlert({
          incidentId: incident.id,
          source,
          payloadRedacted: {
            payload: req.body?.payload || {},
            logs: req.body?.logs || [],
            redactionMeta: analysisOut.redactionMeta,
          },
        });

        const proposedActionType = String(req.body?.proposedActionType || "notify_admin")
          .trim()
          .toLowerCase();
        const inferredRisk = classifyActionRisk(proposedActionType, req.body?.proposedActionInput || {});
        const actionRisk = normalizeRiskLevel(
          inferredRisk === "low" ? analysis.risk_level || "low" : inferredRisk,
          mapRiskFromSeverity(incident.severity)
        );

        const action = await createAction({
          incidentId: incident.id,
          actionType: proposedActionType,
          riskLevel: actionRisk,
          status: requiresHumanApproval(proposedActionType, actionRisk)
            ? "pending_approval"
            : "approved",
          requestedBy: req.userId,
          input: req.body?.proposedActionInput || {
            reason: "auto proposal from incident analysis",
          },
          output: {
            provider: analysisOut.provider,
            recommendation: analysis.immediate_mitigation,
          },
        });

        let actionOut = action;
        let executionOut = null;
        if (String(action?.status || "").toLowerCase() === "approved") {
          executionOut = await executeApprovedAction({
            env,
            action,
            incident,
            actorUserId: req.userId,
            settings,
          });

          if (executionOut?.attempted) {
            actionOut =
              (await markActionExecuted({
                actionId: action.id,
                status: executionOut.status,
                output: {
                  ...asPlainObject(action.output_json),
                  execution: executionOut.output,
                },
              })) || action;

            await audit(
              req,
              executionOut.status === "executed"
                ? "ops_action_auto_executed"
                : "ops_action_auto_execution_failed",
              "action",
              action.id,
              {
                incidentId: incident.id,
                actionType: action.action_type,
                status: executionOut.status,
              }
            );
          }
        }

        await notifySuperAdminsAboutIncident({ incident, settings });
        await audit(req, "ops_incident_analyzed", "incident", incident.id, {
          source,
          provider: analysisOut.provider,
          actionId: actionOut?.id || null,
        });

        return res.status(201).json({
          incident,
          action: actionOut,
          execution: executionOut,
          analysis,
          provider: analysisOut.provider,
          redaction: analysisOut.redactionMeta,
        });
      } catch (error) {
        return next(error);
      }
    }
  );

  router.get(
    "/incidents",
    permissionMiddleware(OPS_PERMISSION_KEYS.viewIncidents),
    async (req, res, next) => {
      try {
        const items = await listIncidents({
          severity: req.query?.severity || "all",
          status: req.query?.status || "all",
          source: req.query?.source || "all",
          affectedModule: req.query?.affectedModule || req.query?.affected_module || "all",
          dateFrom: req.query?.dateFrom || req.query?.from || null,
          dateTo: req.query?.dateTo || req.query?.to || null,
          search: req.query?.search || null,
          limit: req.query?.limit || 80,
          beforeId: req.query?.beforeId || null,
        });
        await audit(req, "ops_incidents_list", "incident", null, {
          count: items.length,
        });
        return res.json({ items });
      } catch (error) {
        return next(error);
      }
    }
  );

  router.get(
    "/incidents/:id",
    permissionMiddleware(OPS_PERMISSION_KEYS.viewIncidents),
    async (req, res, next) => {
      try {
        const incidentId = positiveIntOrNull(req.params?.id);
        if (!incidentId) return badRequest(res, ["id"]);
        const item = await getIncidentById(incidentId);
        if (!item) return res.status(404).json({ message: "INCIDENT_NOT_FOUND" });
        await audit(req, "ops_incident_details", "incident", incidentId, {});
        return res.json({ item });
      } catch (error) {
        return next(error);
      }
    }
  );

  router.post(
    "/incidents/:id/approve-action",
    permissionMiddleware(OPS_PERMISSION_KEYS.approveAction),
    async (req, res, next) => {
      try {
        const incidentId = positiveIntOrNull(req.params?.id);
        if (!incidentId) return badRequest(res, ["id"]);

        const targetActionId = positiveIntOrNull(req.body?.actionId);
        const action =
          targetActionId != null
            ? await getActionById(targetActionId)
            : await getLatestActionByIncident({ incidentId, status: "pending_approval" });

        if (!action) {
          return res.status(404).json({ message: "PENDING_ACTION_NOT_FOUND" });
        }

        if (Number(action.incident_id) !== incidentId) {
          return res.status(409).json({
            message: "ACTION_MISMATCH",
            details: { actionIncidentId: action.incident_id },
          });
        }
        if (String(action.status || "").toLowerCase() !== "pending_approval") {
          return res.status(409).json({
            message: "ACTION_NOT_PENDING_APPROVAL",
          });
        }

        const confirmation = validateTypedConfirmation({
          riskLevel: action.risk_level,
          confirmationText: req.body?.confirmationText,
        });

        if (!confirmation.ok) {
          return badRequest(res, ["confirmationText"], "CRITICAL_CONFIRMATION_REQUIRED");
        }

        const approved = await approveAction({
          actionId: action.id,
          approverUserId: req.userId,
          comment: req.body?.comment || null,
        });

        const incident = await getIncidentById(incidentId);
        const settings = await getOpsSettings();
        const execution = await executeApprovedAction({
          env,
          action: approved || action,
          incident,
          actorUserId: req.userId,
          settings,
        });

        let itemOut = approved;
        if (execution?.attempted) {
          itemOut =
            (await markActionExecuted({
              actionId: action.id,
              status: execution.status,
              output: {
                ...asPlainObject(approved?.output_json),
                execution: execution.output,
              },
            })) || approved;

          await audit(
            req,
            execution.status === "executed"
              ? "ops_action_executed_after_approval"
              : "ops_action_execution_failed_after_approval",
            "action",
            action.id,
            {
              incidentId,
              actionType: action.action_type,
              status: execution.status,
            }
          );
        }

        await audit(req, "ops_action_approved", "action", action.id, {
          incidentId,
          riskLevel: action.risk_level,
          confirmation: confirmation.reason,
        });

        return res.json({ item: itemOut, execution });
      } catch (error) {
        return next(error);
      }
    }
  );

  router.post(
    "/incidents/:id/reject-action",
    permissionMiddleware(OPS_PERMISSION_KEYS.rejectAction),
    async (req, res, next) => {
      try {
        const incidentId = positiveIntOrNull(req.params?.id);
        if (!incidentId) return badRequest(res, ["id"]);

        const action = await getLatestActionByIncident({
          incidentId,
          status: "pending_approval",
        });

        if (!action) {
          return res.status(404).json({ message: "PENDING_ACTION_NOT_FOUND" });
        }

        const rejected = await rejectAction({
          actionId: action.id,
          rejectorUserId: req.userId,
          rejectionReason: req.body?.reason || req.body?.comment || null,
        });

        await audit(req, "ops_action_rejected", "action", action.id, {
          incidentId,
          reason: req.body?.reason || null,
        });

        return res.json({ item: rejected });
      } catch (error) {
        return next(error);
      }
    }
  );

  router.post(
    "/incidents/:id/create-github-issue",
    permissionMiddleware(OPS_PERMISSION_KEYS.createGithubIssue),
    async (req, res, next) => {
      try {
        const incidentId = positiveIntOrNull(req.params?.id);
        if (!incidentId) return badRequest(res, ["id"]);

        const incident = await getIncidentById(incidentId);
        if (!incident) return res.status(404).json({ message: "INCIDENT_NOT_FOUND" });
        const settings = await getOpsSettings();
        if (settings.github_issue_creation_enabled === false) {
          return res.status(409).json({ message: "GITHUB_ISSUE_CREATION_DISABLED" });
        }

        const cfg = githubConfigFromEnv(env);
        const result = await createGithubIssue({
          config: cfg,
          incident,
          title: req.body?.title || incident.title,
          body:
            req.body?.body ||
            [
              incident.summary || "",
              "",
              `Severity: ${incident.severity}`,
              `Risk: ${incident.risk_level}`,
              `Affected module: ${incident.affected_module || "n/a"}`,
              `Mitigation: ${incident.suggested_mitigation || "n/a"}`,
              `Long-term fix: ${incident.long_term_fix || "n/a"}`,
            ]
              .filter(Boolean)
              .join("\n"),
          labels: req.body?.labels || [],
        });

        const action = await createAction({
          incidentId,
          actionType: "create_github_issue",
          riskLevel: "low",
          status: result.ok ? "executed" : "failed",
          requestedBy: req.userId,
          input: req.body || {},
          output: result,
        });

        if (result.ok) {
          await appendIncidentEvidence({
            incidentId,
            evidenceItem: {
              type: "github_issue",
              issue: result.issue,
              at: new Date().toISOString(),
            },
          });
        }

        await audit(req, "ops_github_issue_create", "incident", incidentId, {
          actionId: action?.id || null,
          ok: result.ok,
        });

        return res.status(result.ok ? 200 : 502).json({ result, action });
      } catch (error) {
        return next(error);
      }
    }
  );

  router.post(
    "/incidents/:id/request-code-fix",
    permissionMiddleware(OPS_PERMISSION_KEYS.requestCodeFix),
    async (req, res, next) => {
      try {
        const incidentId = positiveIntOrNull(req.params?.id);
        if (!incidentId) return badRequest(res, ["id"]);

        const incident = await getIncidentById(incidentId);
        if (!incident) return res.status(404).json({ message: "INCIDENT_NOT_FOUND" });

        const riskLevel = normalizeRiskLevel(incident.risk_level || mapRiskFromSeverity(incident.severity));
        const settings = await getOpsSettings();
        const actionType = "request_code_fix";
        const issueRef = req.body?.issue || null;
        const prompt =
          req.body?.prompt || buildCodeFixPrompt({ incident, issueUrl: issueRef?.url || null });

        const canAuto = canAutoExecuteAction({
          actionType,
          riskLevel,
          settings,
          input: {
            incident,
            payload: req.body || {},
          },
        });

        let status = normalizeActionStatus(
          canAuto.allowed ? "approved" : "pending_approval",
          "pending_approval"
        );

        const action = await createAction({
          incidentId,
          actionType,
          riskLevel,
          status,
          requestedBy: req.userId,
          input: {
            prompt,
            issue: issueRef,
            requestedBy: req.userId,
            branchName: req.body?.branchName || null,
            head: req.body?.head || null,
          },
          output: {
            policy: canAuto,
          },
        });

        let prResult = null;
        if (canAuto.allowed && riskLevel === "low") {
          const githubCfg = githubConfigFromEnv(env);
          if (isGithubConfigured(githubCfg) && req.body?.head) {
            prResult = await createCodeFixPullRequest({
              config: githubCfg,
              incident,
              issue: issueRef,
              branchName: req.body?.branchName,
              head: req.body?.head,
              base: req.body?.base || "main",
              title: req.body?.title,
              body: `${req.body?.body || ""}\n\nGenerated prompt:\n\n${prompt}`,
            });

            await markActionExecuted({
              actionId: action.id,
              status: prResult.ok ? "executed" : "failed",
              output: {
                prompt,
                prResult,
              },
            });

            status = prResult.ok ? "executed" : "failed";
          } else {
            await markActionExecuted({
              actionId: action.id,
              status: "executed",
              output: {
                prompt,
                info: "Prompt prepared. Provide head branch to auto-open draft PR.",
              },
            });
            status = "executed";
          }
        }

        await audit(req, "ops_code_fix_requested", "incident", incidentId, {
          actionId: action.id,
          riskLevel,
          auto: canAuto.allowed,
          finalStatus: status,
        });

        return res.json({
          action: {
            ...action,
            status,
          },
          prompt,
          policy: canAuto,
          prResult,
        });
      } catch (error) {
        return next(error);
      }
    }
  );

  router.post(
    "/incidents/:id/mark-resolved",
    permissionMiddleware(OPS_PERMISSION_KEYS.approveAction),
    async (req, res, next) => {
      try {
        const incidentId = positiveIntOrNull(req.params?.id);
        if (!incidentId) return badRequest(res, ["id"]);

        const item = await markIncidentResolved({
          incidentId,
          actorUserId: req.userId,
        });
        if (!item) return res.status(404).json({ message: "INCIDENT_NOT_FOUND" });

        await createAction({
          incidentId,
          actionType: "mark_resolved",
          riskLevel: "low",
          status: "executed",
          requestedBy: req.userId,
          input: {
            reason: req.body?.reason || null,
          },
          output: {
            resolvedAt: item.resolved_at,
          },
        });

        await audit(req, "ops_incident_resolved", "incident", incidentId, {
          reason: req.body?.reason || null,
        });

        return res.json({ item });
      } catch (error) {
        return next(error);
      }
    }
  );

  router.get(
    "/actions/pending",
    permissionMiddleware(OPS_PERMISSION_KEYS.viewIncidents),
    async (req, res, next) => {
      try {
        const items = await listPendingActions({ limit: req.query?.limit || 120 });
        await audit(req, "ops_pending_actions_list", "action", null, {
          count: items.length,
        });
        return res.json({ items });
      } catch (error) {
        return next(error);
      }
    }
  );

  router.get(
    "/audit-logs",
    permissionMiddleware(OPS_PERMISSION_KEYS.viewAuditLogs),
    async (req, res, next) => {
      try {
        const items = await listAuditLogs({
          incidentId: req.query?.incidentId || null,
          limit: req.query?.limit || 200,
        });
        return res.json({ items });
      } catch (error) {
        return next(error);
      }
    }
  );

  router.get(
    "/status",
    permissionMiddleware(OPS_PERMISSION_KEYS.viewIncidents),
    async (req, res, next) => {
      try {
        const out = await resolveOpsStatus(env);
        await audit(req, "ops_status_view", "ops", null, {
          openIncidents: out.overview.openIncidents,
        });
        return res.json(out);
      } catch (error) {
        return next(error);
      }
    }
  );

  router.get(
    "/settings",
    permissionMiddleware(OPS_PERMISSION_KEYS.manageSettings),
    async (req, res, next) => {
      try {
        const settings = await getOpsSettings();
        await audit(req, "ops_settings_view", "ops_settings", null, {});
        return res.json({ settings });
      } catch (error) {
        return next(error);
      }
    }
  );

  router.put(
    "/settings",
    permissionMiddleware(OPS_PERMISSION_KEYS.manageSettings),
    async (req, res, next) => {
      try {
        const raw = req.body?.settings;
        if (!raw || typeof raw !== "object") {
          return badRequest(res, ["settings"]);
        }

        const entries = Object.entries(raw);
        if (entries.length <= 0) {
          return badRequest(res, ["settings"]);
        }

        const changed = [];
        for (const [key, value] of entries) {
          // eslint-disable-next-line no-await-in-loop
          const item = await upsertOpsSetting({
            key,
            value,
            updatedBy: req.userId,
          });
          if (item) changed.push(item);
        }

        const settings = await getOpsSettings();
        await audit(req, "ops_settings_update", "ops_settings", null, {
          changedKeys: changed.map((row) => row.key),
        });
        return res.json({ settings, changedCount: changed.length });
      } catch (error) {
        return next(error);
      }
    }
  );

  return router;
}

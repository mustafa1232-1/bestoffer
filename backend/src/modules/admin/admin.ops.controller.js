import * as repo from "./admin.ops.repo.js";
import { cleanupLoadArtifactsByRunTag } from "../../shared/utils/testArtifactCleanup.js";

function toInt(value, fallback = 0) {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  return Math.trunc(n);
}

function badRequest(res, fields) {
  return res.status(400).json({
    message: "VALIDATION_ERROR",
    fields,
  });
}

export async function listOpsAlerts(req, res, next) {
  try {
    const items = await repo.listOpsAlerts({
      status: req.query?.status || "open",
      severity: req.query?.severity || null,
      beforeId: req.query?.beforeId ?? null,
      limit: req.query?.limit ?? 60,
    });
    return res.json({ items });
  } catch (error) {
    return next(error);
  }
}

export async function acknowledgeOpsAlert(req, res, next) {
  try {
    const alertId = toInt(req.params?.alertId, 0);
    if (alertId <= 0) return badRequest(res, ["alertId"]);
    const status = String(req.body?.status || "acknowledged")
      .trim()
      .toLowerCase();
    if (!["acknowledged", "resolved", "ignored"].includes(status)) {
      return badRequest(res, ["status"]);
    }
    const reason = String(req.body?.reason || req.body?.note || "").trim();
    if (reason.length < 8) return badRequest(res, ["reason"]);
    const item = await repo.acknowledgeOpsAlert({
      alertId,
      actorUserId: req.userId,
      note: reason,
      toStatus: status,
    });
    if (!item) {
      return res.status(404).json({ message: "ALERT_NOT_FOUND" });
    }
    return res.json({ item });
  } catch (error) {
    return next(error);
  }
}

export async function assignOpsAlert(req, res, next) {
  try {
    const alertId = toInt(req.params?.alertId, 0);
    const assigneeUserId = toInt(req.body?.assigneeUserId, 0);
    const reason = String(req.body?.reason || "").trim();
    if (alertId <= 0) return badRequest(res, ["alertId"]);
    if (assigneeUserId <= 0) return badRequest(res, ["assigneeUserId"]);
    if (reason.length < 8) return badRequest(res, ["reason"]);
    const item = await repo.assignOpsAlert({
      alertId,
      actorUserId: req.userId,
      assigneeUserId,
      reason,
    });
    if (!item) {
      return res.status(404).json({ message: "ALERT_NOT_FOUND" });
    }
    return res.json({ item });
  } catch (error) {
    return next(error);
  }
}

export async function resolveOpsAlert(req, res, next) {
  req.body = { ...req.body, status: "resolved" };
  return acknowledgeOpsAlert(req, res, next);
}

export async function notificationOperationsOverview(req, res, next) {
  try {
    const summary = await repo.notificationOperationsOverview({
      windowHours: req.query?.windowHours ?? 24,
    });
    return res.json(summary);
  } catch (error) {
    return next(error);
  }
}

export async function devicePushReliability(req, res, next) {
  try {
    const items = await repo.listDevicePushReliability({
      status: req.query?.status || null,
      limit: req.query?.limit ?? 100,
    });
    return res.json({ items });
  } catch (error) {
    return next(error);
  }
}

export async function listCrashEvents(req, res, next) {
  try {
    const items = await repo.listCrashEvents({
      platform: req.query?.platform || null,
      beforeId: req.query?.beforeId ?? null,
      limit: req.query?.limit ?? 100,
    });
    return res.json({ items });
  } catch (error) {
    return next(error);
  }
}

export async function listFeatureFlags(req, res, next) {
  try {
    const items = await repo.listFeatureFlags();
    return res.json({ items });
  } catch (error) {
    return next(error);
  }
}

export async function upsertFeatureFlag(req, res, next) {
  try {
    const flagKey = String(req.body?.flagKey || req.body?.key || "").trim();
    if (!flagKey) return badRequest(res, ["flagKey"]);
    const item = await repo.upsertFeatureFlag({
      flagKey,
      description: req.body?.description || null,
      isEnabled: req.body?.isEnabled === true,
      rolloutPercent: req.body?.rolloutPercent ?? 0,
      targetRoles: req.body?.targetRoles ?? [],
      configJson: req.body?.config ?? req.body?.configJson ?? {},
      actorUserId: req.userId,
    });
    return res.json({ item });
  } catch (error) {
    return next(error);
  }
}

export async function listPermissionOverrides(req, res, next) {
  try {
    const overrides = await repo.listRolePermissionOverrides();
    return res.json({
      roles: [
        "customer",
        "owner",
        "delivery",
        "taxi_captain",
        "admin",
        "super_admin",
        "accountant",
        "hr",
        "company_manager",
      ],
      items: overrides,
    });
  } catch (error) {
    return next(error);
  }
}

export async function upsertPermissionOverride(req, res, next) {
  try {
    const roleKey = String(req.body?.roleKey || "").trim().toLowerCase();
    const capabilityKey = String(req.body?.capabilityKey || "").trim();
    if (!roleKey || !capabilityKey) {
      return badRequest(res, ["roleKey", "capabilityKey"]);
    }
    const item = await repo.upsertRolePermissionOverride({
      roleKey,
      capabilityKey,
      isEnabled: req.body?.isEnabled === true,
      notes: req.body?.notes || null,
      actorUserId: req.userId,
    });
    return res.json({ item });
  } catch (error) {
    return next(error);
  }
}

export async function reportCrashEvent(req, res, next) {
  try {
    const source = String(req.body?.source || "").trim();
    const message = String(req.body?.message || "").trim();
    if (!source || !message) {
      return badRequest(res, ["source", "message"]);
    }
    const resolvedUserId =
      Number.isInteger(Number(req.userId)) && Number(req.userId) > 0
        ? Number(req.userId)
        : Number.isInteger(Number(req.authUserId)) && Number(req.authUserId) > 0
          ? Number(req.authUserId)
          : null;
    const role = String(req.userRole || req.authUserRole || "")
      .trim()
      .toLowerCase();
    const item = await repo.insertCrashEvent({
      userId: resolvedUserId,
      appRole: role || null,
      platform: req.body?.platform || null,
      appVersion: req.body?.appVersion || null,
      source,
      message,
      stackTrace: req.body?.stackTrace || null,
      extra: req.body?.extra || {},
    });
    return res.status(201).json({ item });
  } catch (error) {
    return next(error);
  }
}

export async function cleanupTestArtifacts(req, res, next) {
  try {
    const runTag = String(req.body?.runTag || "").trim();
    if (!runTag) return badRequest(res, ["runTag"]);
    const summary = await cleanupLoadArtifactsByRunTag(runTag);
    return res.json({ summary });
  } catch (error) {
    return next(error);
  }
}

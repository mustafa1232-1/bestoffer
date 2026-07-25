/**
 * Purpose:
 * قراءة/بحث سجل التدقيق الموحّد (المرحلة 11). خلف requirePermission('audit.read').
 * قراءة السجل نفسها فعل حسّاس فتُسجَّل.
 */

import { searchAuditEvents, recordAudit, auditContextFromReq } from "./audit.service.js";

export async function listAuditEvents(req, res, next) {
  try {
    const out = await searchAuditEvents({
      actorUserId: req.query?.actorUserId ? Number(req.query.actorUserId) : null,
      targetType:
        typeof req.query?.targetType === "string" && req.query.targetType.trim()
          ? req.query.targetType.trim()
          : null,
      targetId: req.query?.targetId ? Number(req.query.targetId) : null,
      actionKey:
        typeof req.query?.actionKey === "string" && req.query.actionKey.trim()
          ? req.query.actionKey.trim()
          : null,
      from: req.query?.from || null,
      to: req.query?.to || null,
      limit: req.query?.limit ? Number(req.query.limit) : 50,
      offset: req.query?.offset ? Number(req.query.offset) : 0,
    });

    void recordAudit({
      ...auditContextFromReq(req),
      actionKey: "audit.read",
      summary: "قراءة سجل التدقيق",
      permissionKey: "audit.read",
      metadata: { filters: req.query || {} },
    });

    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

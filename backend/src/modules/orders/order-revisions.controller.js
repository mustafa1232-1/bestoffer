import * as service from "./order-revisions.service.js";
import {
  validateCreateOrderRevision,
  validatePatchOrderRevision,
  validateRevisionDecision,
} from "./order-revisions.validators.js";
import { recordAudit, auditContextFromReq } from "../security/audit.service.js";

function idParam(req, name) {
  const id = Number(req.params?.[name]);
  return Number.isInteger(id) && id > 0 ? id : null;
}

function badRequest(res, fields) {
  return res.status(400).json({ message: "VALIDATION_ERROR", fields });
}

function audit(req, { actionKey, orderId, revisionId, summary, metadata = null }) {
  void recordAudit({
    ...auditContextFromReq(req),
    actionKey,
    summary,
    targetType: "order_revision",
    targetId: revisionId || null,
    metadata: { orderId, revisionId, ...(metadata || {}) },
    permissionKey: actionKey,
  });
}

export async function adminCreateFromTicket(req, res, next) {
  try {
    const ticketId = idParam(req, "ticketId");
    if (!ticketId) return badRequest(res, ["ticketId"]);
    const v = validateCreateOrderRevision(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);
    if (!v.value.orderId) return badRequest(res, ["orderId"]);
    const out = await service.createRevisionFromSupportTicket({
      ticketId,
      actorUserId: req.userId,
      actorRole: req.userRole || "agent",
      ...v.value,
    });
    audit(req, {
      actionKey: "orders.revisions.create",
      orderId: v.value.orderId,
      revisionId: out.revision.id,
      summary: `Created order revision #${out.revision.id} for order #${v.value.orderId}`,
    });
    return res.status(201).json(out);
  } catch (error) {
    return next(error);
  }
}

export async function adminListForTicket(req, res, next) {
  try {
    const ticketId = idParam(req, "ticketId");
    if (!ticketId) return badRequest(res, ["ticketId"]);
    const out = await service.listRevisionsForTicket(ticketId);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function adminGetRevision(req, res, next) {
  try {
    const orderId = idParam(req, "orderId");
    const revisionId = idParam(req, "revisionId");
    if (!orderId || !revisionId) return badRequest(res, ["orderId", "revisionId"]);
    const out = await service.getRevisionDetails({ orderId, revisionId });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function adminPatchRevision(req, res, next) {
  try {
    const orderId = idParam(req, "orderId");
    const revisionId = idParam(req, "revisionId");
    if (!orderId || !revisionId) return badRequest(res, ["orderId", "revisionId"]);
    const v = validatePatchOrderRevision(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);
    const out = await service.patchRevision({
      orderId,
      revisionId,
      actorUserId: req.userId,
      actorRole: req.userRole || "agent",
      patch: v.value,
    });
    audit(req, {
      actionKey: "orders.modify",
      orderId,
      revisionId,
      summary: `Updated order revision #${revisionId}`,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function adminSubmitRevision(req, res, next) {
  try {
    const orderId = idParam(req, "orderId");
    const revisionId = idParam(req, "revisionId");
    if (!orderId || !revisionId) return badRequest(res, ["orderId", "revisionId"]);
    const out = await service.submitRevision({
      orderId,
      revisionId,
      actorUserId: req.userId,
      actorRole: req.userRole || "agent",
    });
    audit(req, {
      actionKey: "orders.revisions.submit",
      orderId,
      revisionId,
      summary: `Submitted order revision #${revisionId}`,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function adminApplyRevision(req, res, next) {
  try {
    const orderId = idParam(req, "orderId");
    const revisionId = idParam(req, "revisionId");
    if (!orderId || !revisionId) return badRequest(res, ["orderId", "revisionId"]);
    const out = await service.applyRevision({
      orderId,
      revisionId,
      actorUserId: req.userId,
      actorRole: req.userRole || "agent",
    });
    audit(req, {
      actionKey: "orders.revisions.apply",
      orderId,
      revisionId,
      summary: `Applied order revision #${revisionId}`,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function customerApprove(req, res, next) {
  try {
    const orderId = idParam(req, "orderId");
    const revisionId = idParam(req, "revisionId");
    if (!orderId || !revisionId) return badRequest(res, ["orderId", "revisionId"]);
    const v = validateRevisionDecision(req.body || {});
    const out = await service.customerApprove({
      orderId,
      revisionId,
      userId: req.userId,
      note: v.value.note,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function merchantApprove(req, res, next) {
  try {
    const orderId = idParam(req, "orderId");
    const revisionId = idParam(req, "revisionId");
    if (!orderId || !revisionId) return badRequest(res, ["orderId", "revisionId"]);
    const v = validateRevisionDecision(req.body || {});
    const out = await service.merchantApprove({
      orderId,
      revisionId,
      ownerUserId: req.userId,
      note: v.value.note,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function rejectRevision(req, res, next) {
  try {
    const orderId = idParam(req, "orderId");
    const revisionId = idParam(req, "revisionId");
    if (!orderId || !revisionId) return badRequest(res, ["orderId", "revisionId"]);
    const v = validateRevisionDecision(req.body || {});
    const out = await service.rejectRevision({
      orderId,
      revisionId,
      userId: req.userId,
      role: req.userRole || "user",
      note: v.value.note,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

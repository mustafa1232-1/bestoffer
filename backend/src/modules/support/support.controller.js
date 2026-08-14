import * as service from "./support.service.js";
import * as repo from "./support.repo.js";
import { recordAudit, auditContextFromReq } from "../security/audit.service.js";
import { buildUploadedFileUrl } from "../../shared/utils/upload.js";
import {
  validateCreateTicket,
  validateAgentCreateTicket,
  validateMessage,
  validateResolve,
  validateTransition,
  validateAssign,
  validateLinkEntity,
  validatePresence,
  validateCannedResponse,
  validateKnowledgeArticle,
  validateCallback,
  validateCallbackUpdate,
  validateRating,
} from "./support.validators.js";

function badRequest(res, fields) {
  return res.status(400).json({ message: "VALIDATION_ERROR", fields });
}

/**
 * رفع مرفق (صورة/ملف) لمحادثة الدعم. يعيد بيانات المرفق ليُرفق برسالة لاحقاً.
 * يُستخدم من المستخدم والموظف على السواء (requireAuth).
 */
export async function uploadAttachment(req, res, next) {
  try {
    if (!req.file) return badRequest(res, ["file"]);
    const fileUrl = buildUploadedFileUrl(req, req.file);
    if (!fileUrl) return badRequest(res, ["file"]);
    return res.status(201).json({
      attachment: {
        fileUrl,
        storageKey: req.file.key || req.file.filename || null,
        fileName: req.file.originalname || null,
        mimeType: req.file.mimetype || null,
        fileSizeBytes:
          typeof req.file.size === "number" ? req.file.size : null,
      },
    });
  } catch (error) {
    return next(error);
  }
}

function ticketId(req, res) {
  const id = Number(req.params?.ticketId);
  if (!Number.isInteger(id) || id <= 0) {
    badRequest(res, ["ticketId"]);
    return null;
  }
  return id;
}

function positiveId(req, res, name) {
  const id = Number(req.params?.[name]);
  if (!Number.isInteger(id) || id <= 0) {
    badRequest(res, [name]);
    return null;
  }
  return id;
}

function boolQuery(value) {
  return value === true || value === "true" || value === "1" || value === 1;
}

function audit(req, { actionKey, summary, targetId, metadata = null }) {
  void recordAudit({
    ...auditContextFromReq(req),
    actionKey,
    summary,
    targetType: "support_ticket",
    targetId,
    metadata,
    permissionKey: actionKey,
  });
}

export async function createTicket(req, res, next) {
  try {
    const v = validateCreateTicket(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);
    const ticket = await service.createTicket({ userId: req.userId, ...v.value });
    return res.status(201).json({ ticket });
  } catch (error) {
    return next(error);
  }
}

export async function listMyTickets(req, res, next) {
  try {
    const out = await service.listMyTickets({
      userId: req.userId,
      status: req.query?.status || null,
      limit: req.query?.limit ? Number(req.query.limit) : 25,
      offset: req.query?.offset ? Number(req.query.offset) : 0,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function getMyTicket(req, res, next) {
  try {
    const id = ticketId(req, res);
    if (!id) return;
    const out = await service.getTicketForViewer({
      ticketId: id,
      viewer: { userId: req.userId, isAgent: false, canReadInternal: false },
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function postMyMessage(req, res, next) {
  try {
    const id = ticketId(req, res);
    if (!id) return;
    const v = validateMessage(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);
    const message = await service.addCustomerMessage({
      ticketId: id,
      userId: req.userId,
      body: v.value.body,
      attachments: v.value.attachments,
    });
    return res.status(201).json({ message });
  } catch (error) {
    return next(error);
  }
}

export async function reopenMyTicket(req, res, next) {
  try {
    const id = ticketId(req, res);
    if (!id) return;
    const ticket = await service.reopenTicket({
      ticketId: id,
      actorUserId: req.userId,
      actorRole: "customer",
      reason: typeof req.body?.reason === "string" ? req.body.reason.trim() : null,
    });
    return res.json({ ticket });
  } catch (error) {
    return next(error);
  }
}

export async function rateMyTicket(req, res, next) {
  try {
    const id = ticketId(req, res);
    if (!id) return;
    const v = validateRating(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);
    const ticket = await service.rateTicket({
      ticketId: id,
      userId: req.userId,
      ...v.value,
    });
    return res.json({ ticket });
  } catch (error) {
    return next(error);
  }
}

// الموظف يفتح تذكرة نيابةً عن العميل (توثيق مكالمة/تواصل خارجي).
export async function adminCreateTicket(req, res, next) {
  try {
    const v = validateAgentCreateTicket(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);
    const ticket = await service.createTicketByAgent({
      agentUserId: req.userId,
      agentRole: req.userRole || "agent",
      ...v.value,
    });
    audit(req, {
      actionKey: "support.tickets.reply",
      summary: `Agent opened support ticket #${ticket.id} on behalf of a customer (${v.value.channel})`,
      targetId: Number(ticket.id),
      metadata: {
        channel: v.value.channel,
        callOutcome: v.value.callOutcome,
        onBehalfOfUserId: Number(ticket.user_id),
      },
    });
    return res.status(201).json({ ticket });
  } catch (error) {
    return next(error);
  }
}

export async function adminListTickets(req, res, next) {
  try {
    const out = await service.listTicketsForAgent({
      actorUserId: req.userId,
      permissionScope: req.permissionScope || "assigned",
      team: req.query?.team || null,
      my: boolQuery(req.query?.my),
      domain: req.query?.domain || null,
      status: req.query?.status || null,
      priority: req.query?.priority || null,
      waiting: boolQuery(req.query?.waiting),
      urgent: boolQuery(req.query?.urgent),
      breachedSla: boolQuery(req.query?.breachedSla),
      search: req.query?.search || null,
      from: req.query?.from || null,
      to: req.query?.to || null,
      limit: req.query?.limit ? Number(req.query.limit) : 25,
      offset: req.query?.offset ? Number(req.query.offset) : 0,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function adminGetMyPresence(req, res, next) {
  try {
    const presence = await service.getMyPresence(req.userId);
    return res.json({ presence });
  } catch (error) {
    return next(error);
  }
}

export async function adminUpdateMyPresence(req, res, next) {
  try {
    const v = validatePresence(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);
    const presence = await service.updateMyPresence({
      agentUserId: req.userId,
      ...v.value,
    });
    audit(req, {
      actionKey: "support.tickets.reply",
      summary: `Updated support presence to ${v.value.status}`,
      targetId: req.userId,
      metadata: v.value,
    });
    return res.json({ presence });
  } catch (error) {
    return next(error);
  }
}

export async function adminListPresence(req, res, next) {
  try {
    const out = await service.listPresence({
      team: req.query?.team || null,
      status: req.query?.status || null,
      limit: req.query?.limit ? Number(req.query.limit) : 100,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function adminSupervisorOverview(req, res, next) {
  try {
    const overview = await service.getSupervisorOverview();
    return res.json(overview);
  } catch (error) {
    return next(error);
  }
}

export async function adminSupportKpis(req, res, next) {
  try {
    const report = await service.getSupportKpiReport({
      from: req.query?.from || null,
      to: req.query?.to || null,
      team: req.query?.team || null,
      limit: req.query?.limit ? Number(req.query.limit) : 20,
    });
    return res.json(report);
  } catch (error) {
    return next(error);
  }
}

export async function adminListCannedResponses(req, res, next) {
  try {
    const out = await service.listCannedResponses({
      domain: req.query?.domain || null,
      type: req.query?.type || null,
      includeInactive: boolQuery(req.query?.includeInactive),
      limit: req.query?.limit ? Number(req.query.limit) : 100,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function adminCreateCannedResponse(req, res, next) {
  try {
    const v = validateCannedResponse(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);
    const response = await service.createCannedResponse({
      actorUserId: req.userId,
      ...v.value,
    });
    audit(req, {
      actionKey: "support.sla.manage",
      summary: `Created support canned response #${response.id}`,
      targetId: Number(response.id),
      metadata: { domain: response.domain, type: response.type },
    });
    return res.status(201).json({ response });
  } catch (error) {
    return next(error);
  }
}

export async function adminUpdateCannedResponse(req, res, next) {
  try {
    const id = positiveId(req, res, "responseId");
    if (!id) return;
    const v = validateCannedResponse(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);
    const response = await service.updateCannedResponse({
      id,
      actorUserId: req.userId,
      ...v.value,
    });
    audit(req, {
      actionKey: "support.sla.manage",
      summary: `Updated support canned response #${id}`,
      targetId: id,
      metadata: { domain: response.domain, type: response.type },
    });
    return res.json({ response });
  } catch (error) {
    return next(error);
  }
}

export async function adminListKnowledgeArticles(req, res, next) {
  try {
    const out = await service.listKnowledgeArticles({
      domain: req.query?.domain || null,
      search: req.query?.search || null,
      includeUnpublished: boolQuery(req.query?.includeUnpublished),
      limit: req.query?.limit ? Number(req.query.limit) : 50,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function adminCreateKnowledgeArticle(req, res, next) {
  try {
    const v = validateKnowledgeArticle(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);
    const article = await service.createKnowledgeArticle({
      actorUserId: req.userId,
      ...v.value,
    });
    audit(req, {
      actionKey: "support.sla.manage",
      summary: `Created support knowledge article #${article.id}`,
      targetId: Number(article.id),
      metadata: { domain: article.domain },
    });
    return res.status(201).json({ article });
  } catch (error) {
    return next(error);
  }
}

export async function adminUpdateKnowledgeArticle(req, res, next) {
  try {
    const id = positiveId(req, res, "articleId");
    if (!id) return;
    const v = validateKnowledgeArticle(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);
    const article = await service.updateKnowledgeArticle({
      id,
      actorUserId: req.userId,
      ...v.value,
    });
    audit(req, {
      actionKey: "support.sla.manage",
      summary: `Updated support knowledge article #${id}`,
      targetId: id,
      metadata: { domain: article.domain },
    });
    return res.json({ article });
  } catch (error) {
    return next(error);
  }
}

export async function adminListCallbacks(req, res, next) {
  try {
    const out = await service.listCallbacks({
      assignedUserId: boolQuery(req.query?.my) ? req.userId : null,
      status: req.query?.status || null,
      limit: req.query?.limit ? Number(req.query.limit) : 50,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function adminListTicketCallbacks(req, res, next) {
  try {
    const id = ticketId(req, res);
    if (!id) return;
    await service.getTicketForViewer({
      ticketId: id,
      viewer: {
        userId: req.userId,
        isAgent: true,
        canReadInternal: true,
        permissionScope: req.permissionScope || "assigned",
        team: req.query?.team || null,
      },
    });
    const out = await service.listCallbacks({ ticketId: id, limit: 50 });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function adminCreateTicketCallback(req, res, next) {
  try {
    const id = ticketId(req, res);
    if (!id) return;
    const v = validateCallback(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);
    const callback = await service.createCallback({
      ticketId: id,
      actorUserId: req.userId,
      ...v.value,
    });
    audit(req, {
      actionKey: "support.tickets.reply",
      summary: `Scheduled callback for support ticket #${id}`,
      targetId: id,
      metadata: { callbackId: Number(callback.id), scheduledAt: callback.scheduled_at },
    });
    return res.status(201).json({ callback });
  } catch (error) {
    return next(error);
  }
}

export async function adminUpdateCallback(req, res, next) {
  try {
    const id = positiveId(req, res, "callbackId");
    if (!id) return;
    const v = validateCallbackUpdate(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);
    const callback = await service.updateCallback({
      callbackId: id,
      actorUserId: req.userId,
      ...v.value,
    });
    audit(req, {
      actionKey: "support.tickets.reply",
      summary: `Updated support callback #${id} to ${callback.status}`,
      targetId: Number(callback.ticket_id),
      metadata: { callbackId: id, status: callback.status },
    });
    return res.json({ callback });
  } catch (error) {
    return next(error);
  }
}

export async function adminGetTicket(req, res, next) {
  try {
    const id = ticketId(req, res);
    if (!id) return;
    const out = await service.getTicketForViewer({
      ticketId: id,
      viewer: {
        userId: req.userId,
        isAgent: true,
        canReadInternal: true,
        permissionScope: req.permissionScope || "assigned",
        team: req.query?.team || null,
      },
    });
    audit(req, {
      actionKey: "support.tickets.read",
      summary: `Read support ticket #${id}`,
      targetId: id,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function adminLinkSuggestions(req, res, next) {
  try {
    const id = ticketId(req, res);
    if (!id) return;
    const ticket = await repo.getTicketById(id);
    if (!ticket) {
      return res.status(404).json({ message: "TICKET_NOT_FOUND" });
    }
    const suggestions = await repo.listLinkSuggestionsForUser(ticket.user_id, {
      limit: req.query?.limit ? Number(req.query.limit) : 5,
    });
    return res.json(suggestions);
  } catch (error) {
    return next(error);
  }
}

export async function adminAssign(req, res, next) {
  try {
    const id = ticketId(req, res);
    if (!id) return;
    const v = validateAssign(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);
    const ticket = await service.assignTicket({
      ticketId: id,
      actorUserId: req.userId,
      actorRole: req.userRole || "agent",
      assigneeUserId: v.value.assigneeUserId,
      team: v.value.team,
    });
    audit(req, {
      actionKey: "support.tickets.assign",
      summary: `Assigned support ticket #${id}`,
      targetId: id,
      metadata: v.value,
    });
    return res.json({ ticket });
  } catch (error) {
    return next(error);
  }
}

export async function adminJoin(req, res, next) {
  try {
    const id = ticketId(req, res);
    if (!id) return;
    const message = await service.joinConversation({
      ticketId: id,
      agentUserId: req.userId,
      agentRole: req.userRole || "agent",
    });
    audit(req, {
      actionKey: "support.tickets.reply",
      summary: `Joined support ticket #${id}`,
      targetId: id,
      metadata: { messageId: Number(message.id) },
    });
    return res.status(201).json({ message });
  } catch (error) {
    return next(error);
  }
}

export async function adminReply(req, res, next) {
  try {
    const id = ticketId(req, res);
    if (!id) return;
    const v = validateMessage(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);
    if (v.value.isInternal) {
      const note = await service.addInternalNote({
        ticketId: id,
        agentUserId: req.userId,
        agentRole: req.userRole || "agent",
        body: v.value.body,
        attachments: v.value.attachments,
      });
      audit(req, {
        actionKey: "support.tickets.reply",
        summary: `Added internal note to support ticket #${id}`,
        targetId: id,
        metadata: { noteId: Number(note.id) },
      });
      return res.status(201).json({ note, internal: true });
    }
    const out = await service.agentReply({
      ticketId: id,
      agentUserId: req.userId,
      agentRole: req.userRole || "agent",
      body: v.value.body,
      attachments: v.value.attachments,
    });
    audit(req, {
      actionKey: "support.tickets.reply",
      summary: `Replied to support ticket #${id}`,
      targetId: id,
      metadata: { messageId: Number(out.message.id) },
    });
    return res.status(201).json(out);
  } catch (error) {
    return next(error);
  }
}

export async function adminLinkEntity(req, res, next) {
  try {
    const id = ticketId(req, res);
    if (!id) return;
    const v = validateLinkEntity(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);
    const link = await service.linkEntity({
      ticketId: id,
      actorUserId: req.userId,
      actorRole: req.userRole || "agent",
      ...v.value,
    });
    audit(req, {
      actionKey: "support.tickets.assign",
      summary: `Linked entity to support ticket #${id}`,
      targetId: id,
      metadata: v.value,
    });
    return res.status(201).json({ link });
  } catch (error) {
    return next(error);
  }
}

export async function adminTransition(req, res, next) {
  try {
    const id = ticketId(req, res);
    if (!id) return;
    const v = validateTransition(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);
    if (v.value.toStatus === "ESCALATED") {
      return res.status(403).json({ message: "USE_ESCALATE_ENDPOINT" });
    }
    const ticket = await service.transitionTicket({
      ticketId: id,
      actorUserId: req.userId,
      actorRole: req.userRole || "agent",
      toStatus: v.value.toStatus,
    });
    audit(req, {
      actionKey: "support.tickets.reply",
      summary: `Changed support ticket #${id} status to ${v.value.toStatus}`,
      targetId: id,
      metadata: { toStatus: v.value.toStatus },
    });
    return res.json({ ticket });
  } catch (error) {
    return next(error);
  }
}

export async function adminEscalate(req, res, next) {
  try {
    const id = ticketId(req, res);
    if (!id) return;
    const ticket = await service.escalateTicket({
      ticketId: id,
      actorUserId: req.userId,
      actorRole: req.userRole || "agent",
      reason:
        typeof req.body?.reason === "string"
          ? req.body.reason.trim() || "manual_escalation"
          : "manual_escalation",
    });
    audit(req, {
      actionKey: "support.tickets.escalate",
      summary: `Escalated support ticket #${id}`,
      targetId: id,
    });
    return res.json({ ticket });
  } catch (error) {
    return next(error);
  }
}

export async function adminResolve(req, res, next) {
  try {
    const id = ticketId(req, res);
    if (!id) return;
    const v = validateResolve(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);
    const ticket = await service.resolveTicket({
      ticketId: id,
      actorUserId: req.userId,
      actorRole: req.userRole || "agent",
      summary: v.value.summary,
      reason: v.value.reason,
    });
    audit(req, {
      actionKey: "support.tickets.resolve",
      summary: `Resolved support ticket #${id}`,
      targetId: id,
      metadata: { reason: v.value.reason },
    });
    return res.json({ ticket });
  } catch (error) {
    return next(error);
  }
}

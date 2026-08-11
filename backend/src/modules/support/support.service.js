import { AppError } from "../../shared/utils/errors.js";
import { emitRealtimeToUser } from "../../shared/realtime/realtime-gateway.js";
import { createNotification } from "../notifications/notifications.repo.js";
import * as repo from "./support.repo.js";
import {
  canTransition,
  computeDueDates,
  computeSlaState,
  isTerminalStatus,
} from "./support.policy.js";

const REOPEN_WINDOW_MS = 7 * 24 * 60 * 60 * 1000;

function queueNotification(payload) {
  createNotification(payload).catch((error) => {
    console.warn("[support] notification failed", error?.message || error);
  });
}

function queueRealtime(userId, event, payload) {
  if (!userId) return;
  emitRealtimeToUser(Number(userId), event, payload).catch((error) => {
    console.warn("[support] realtime failed", error?.message || error);
  });
}

function toMs(value) {
  if (!value) return null;
  const t = new Date(value).getTime();
  return Number.isFinite(t) ? t : null;
}

function withSla(ticket) {
  if (!ticket) return ticket;
  const sla = computeSlaState({
    status: ticket.status,
    createdAtMs: toMs(ticket.created_at),
    firstResponseDueAtMs: toMs(ticket.sla_first_response_due_at),
    resolutionDueAtMs: toMs(ticket.sla_resolution_due_at),
    firstResponseAtMs: toMs(ticket.first_response_at),
    resolvedAtMs: toMs(ticket.resolved_at),
    nowMs: Date.now(),
  });
  return { ...ticket, sla };
}

function supportPayload(ticketId, extra = {}) {
  return { ticketId: Number(ticketId), target: "support_ticket", ...extra };
}

function notifyTicketUser(ticket, type, title, body, extra = {}) {
  queueNotification({
    userId: Number(ticket.user_id),
    type,
    title,
    body,
    payload: supportPayload(ticket.id, extra),
  });
  queueRealtime(Number(ticket.user_id), "support_ticket", {
    type,
    ticketId: Number(ticket.id),
    ticketNumber: ticket.ticket_number,
    ...extra,
  });
}

function notifyAssignee(ticket, type, title, body, extra = {}) {
  if (!ticket.assigned_user_id) return;
  queueNotification({
    userId: Number(ticket.assigned_user_id),
    type,
    title,
    body,
    payload: supportPayload(ticket.id, extra),
  });
  queueRealtime(Number(ticket.assigned_user_id), "support_ticket", {
    type,
    ticketId: Number(ticket.id),
    ticketNumber: ticket.ticket_number,
    ...extra,
  });
}

function agentCanRead(ticket, viewer) {
  if (!viewer?.isAgent) return false;
  const scope = viewer.permissionScope || "assigned";
  if (scope === "all") return true;
  if (scope === "department") {
    if (viewer.team && ticket.team && String(viewer.team) === String(ticket.team)) {
      return true;
    }
    return Number(ticket.assigned_user_id) === Number(viewer.userId);
  }
  return Number(ticket.assigned_user_id) === Number(viewer.userId);
}

function assertAgentCanRead(ticket, viewer) {
  if (agentCanRead(ticket, viewer)) return;
  throw new AppError("TICKET_FORBIDDEN", { status: 403 });
}

export async function createTicket({
  userId,
  domain,
  type,
  priority = "normal",
  subject,
  description = null,
  entityType = null,
  entityId = null,
  entityLabel = null,
  attachments = [],
  channel = "app",
  createdByUserId = null,
  callOutcome = null,
}) {
  const due = computeDueDates(priority, Date.now());
  const ticket = await repo.createTicket({
    userId,
    domain,
    type,
    priority,
    subject,
    description,
    entityType,
    entityId,
    entityLabel,
    attachments,
    slaFirstResponseDueAt: due.firstResponseDueAt,
    slaResolutionDueAt: due.resolutionDueAt,
    channel,
    createdByUserId,
    callOutcome,
  });
  return withSla(ticket);
}

/**
 * ينشئ الموظف تذكرةً نيابةً عن العميل (توثيق مكالمة هاتفية أو تواصل خارجي).
 * يُحلّ العميل عبر userId صريح أو رقم هاتف. اختيارياً يُسند التذكرة للموظف الذي
 * تولّى المكالمة (assignToSelf) ويضيف ملخّص المكالمة كملاحظة داخلية.
 */
export async function createTicketByAgent({
  agentUserId,
  agentRole = "agent",
  customerUserId = null,
  customerPhone = null,
  domain,
  type,
  priority = "normal",
  subject,
  description = null,
  channel = "phone",
  callOutcome = null,
  entityType = null,
  entityId = null,
  entityLabel = null,
  internalNote = null,
  assignToSelf = true,
}) {
  let resolvedUserId = customerUserId ? Number(customerUserId) : null;
  if (!resolvedUserId && customerPhone) {
    const found = await repo.findCustomerByPhone(customerPhone);
    if (!found) {
      throw new AppError("CUSTOMER_NOT_FOUND", {
        status: 404,
        details: { phone: customerPhone },
      });
    }
    resolvedUserId = Number(found.id);
  }
  if (!resolvedUserId) {
    throw new AppError("CUSTOMER_REQUIRED", { status: 400 });
  }

  const ticket = await createTicket({
    userId: resolvedUserId,
    domain,
    type,
    priority,
    subject,
    description,
    entityType,
    entityId,
    entityLabel,
    channel,
    createdByUserId: agentUserId,
    callOutcome,
  });

  // ملخّص المكالمة كملاحظة داخلية (لا يراها العميل).
  if (internalNote && String(internalNote).trim().length > 0) {
    await repo.addInternalNote({
      ticketId: ticket.id,
      authorUserId: agentUserId,
      authorRole: agentRole,
      body: String(internalNote).trim(),
      attachments: [],
    });
  }

  // الموظف الذي تولّى المكالمة يملك التذكرة افتراضياً وتنتقل لِ IN_PROGRESS.
  let finalTicket = ticket;
  if (assignToSelf) {
    const assigned = await repo.assignTicket({
      ticketId: ticket.id,
      actorUserId: agentUserId,
      actorRole: agentRole,
      assigneeUserId: agentUserId,
      team: ticket.team || null,
    });
    if (assigned.code === "OK") {
      const moved = await repo.transitionStatus({
        ticketId: ticket.id,
        toStatus: "IN_PROGRESS",
        actorUserId: agentUserId,
        actorRole: agentRole,
        eventType: "status_changed",
        allowedFrom: ["ASSIGNED"],
      });
      finalTicket = moved.code === "OK" ? moved.ticket : assigned.ticket;
    }
  }

  // إن كانت المشكلة حُلّت أثناء المكالمة، توثَّق كمحلولة مباشرةً (بعد أن تصبح
  // قيد المعالجة، حتى يكون الانتقال سليماً).
  if (callOutcome === "resolved_on_call" && finalTicket.status === "IN_PROGRESS") {
    const resolved = await repo.transitionStatus({
      ticketId: ticket.id,
      toStatus: "RESOLVED",
      actorUserId: agentUserId,
      actorRole: agentRole,
      eventType: "resolved",
      allowedFrom: [finalTicket.status],
      extraSet: {
        resolved_at: new Date().toISOString(),
        resolution_summary: subject,
        resolution_reason: "resolved_on_call",
      },
      metadata: { reason: "resolved_on_call" },
    });
    if (resolved.code === "OK") finalTicket = resolved.ticket;
  }

  return withSla(finalTicket);
}

export function createUrgentRideTicket({ userId, rideId, subject, description, attachments = [] }) {
  return createTicket({
    userId,
    domain: "TAXI",
    type: "SAFETY",
    priority: "urgent",
    subject,
    description,
    entityType: "ride",
    entityId: rideId,
    entityLabel: rideId ? `Ride #${rideId}` : null,
    attachments,
  });
}

export async function listMyTickets({ userId, status = null, limit, offset }) {
  const out = await repo.listTickets({ userId, status, limit, offset });
  return { ...out, items: out.items.map(withSla) };
}

export async function listTicketsForAgent({
  actorUserId,
  permissionScope = "assigned",
  team = null,
  my = false,
  domain = null,
  status = null,
  priority = null,
  waiting = false,
  urgent = false,
  breachedSla = false,
  search = null,
  from = null,
  to = null,
  limit,
  offset,
}) {
  const filters = {
    domain,
    status,
    priority,
    waiting,
    urgent,
    breachedSla,
    search,
    from,
    to,
    limit,
    offset,
  };
  if (permissionScope === "all" && !my) {
    const out = await repo.listTickets({ ...filters, team });
    return { ...out, items: out.items.map(withSla) };
  }
  if (permissionScope === "department" && team && !my) {
    const out = await repo.listTickets({ ...filters, team });
    return { ...out, items: out.items.map(withSla) };
  }
  const out = await repo.listTickets({ ...filters, assignedUserId: actorUserId });
  return { ...out, items: out.items.map(withSla) };
}

export async function getTicketForViewer({ ticketId, viewer }) {
  const ticket = await repo.getTicketById(ticketId);
  if (!ticket) throw new AppError("TICKET_NOT_FOUND", { status: 404 });

  const isReporter = Number(ticket.user_id) === Number(viewer.userId);
  if (!isReporter) {
    assertAgentCanRead(ticket, viewer);
  }

  const includeInternal = Boolean(viewer.isAgent && viewer.canReadInternal);
  const [messages, events, links, attachments, internalNotes] = await Promise.all([
    repo.listMessages(ticketId, { includeInternal }),
    repo.listEvents(ticketId),
    repo.listLinks(ticketId),
    repo.listAttachments(ticketId, { includeInternal }),
    includeInternal ? repo.listInternalNotes(ticketId) : Promise.resolve([]),
  ]);

  return {
    ticket: withSla(ticket),
    messages,
    internalNotes,
    links,
    attachments,
    events,
  };
}

export async function addCustomerMessage({ ticketId, userId, body, attachments = [] }) {
  const ticket = await repo.getTicketById(ticketId);
  if (!ticket) throw new AppError("TICKET_NOT_FOUND", { status: 404 });
  if (Number(ticket.user_id) !== Number(userId)) {
    throw new AppError("TICKET_FORBIDDEN", { status: 403 });
  }
  if (isTerminalStatus(ticket.status)) {
    throw new AppError("TICKET_CLOSED", { status: 409 });
  }

  const message = await repo.addMessage({
    ticketId,
    authorUserId: userId,
    authorRole: "customer",
    isInternal: false,
    body,
    attachments,
  });

  if (ticket.status === "WAITING_FOR_CUSTOMER") {
    await repo.transitionStatus({
      ticketId,
      toStatus: "IN_PROGRESS",
      actorUserId: userId,
      actorRole: "customer",
      eventType: "customer_replied",
      allowedFrom: ["WAITING_FOR_CUSTOMER"],
    });
  }

  notifyAssignee(
    ticket,
    "support.ticket.customer_reply",
    "New customer reply",
    `Ticket ${ticket.ticket_number}`,
    { messageId: Number(message.id) }
  );
  return message;
}

export async function agentReply({
  ticketId,
  agentUserId,
  agentRole,
  body,
  attachments = [],
}) {
  const ticket = await repo.getTicketById(ticketId);
  if (!ticket) throw new AppError("TICKET_NOT_FOUND", { status: 404 });
  if (isTerminalStatus(ticket.status)) {
    throw new AppError("TICKET_CLOSED", { status: 409 });
  }

  const firstResponse = !ticket.first_response_at;
  const message = await repo.addMessage({
    ticketId,
    authorUserId: agentUserId,
    authorRole: agentRole || "agent",
    isInternal: false,
    body,
    attachments,
    markFirstResponse: firstResponse,
  });

  notifyTicketUser(
    ticket,
    "support.ticket.agent_reply",
    "Support replied",
    `Ticket ${ticket.ticket_number}`,
    { messageId: Number(message.id), firstResponse }
  );
  return { message, firstResponse };
}

export async function addInternalNote({
  ticketId,
  agentUserId,
  agentRole,
  body,
  attachments = [],
}) {
  const ticket = await repo.getTicketById(ticketId);
  if (!ticket) throw new AppError("TICKET_NOT_FOUND", { status: 404 });
  return repo.addInternalNote({
    ticketId,
    authorUserId: agentUserId,
    authorRole: agentRole || "agent",
    body,
    attachments: attachments.map((a) => ({ ...a, visibility: "internal" })),
  });
}

export async function joinConversation({ ticketId, agentUserId, agentRole }) {
  const ticket = await repo.getTicketById(ticketId);
  if (!ticket) throw new AppError("TICKET_NOT_FOUND", { status: 404 });
  if (isTerminalStatus(ticket.status)) {
    throw new AppError("TICKET_CLOSED", { status: 409 });
  }
  const message = await repo.joinConversation({ ticketId, agentUserId, agentRole });
  notifyTicketUser(
    ticket,
    "support.ticket.agent_joined",
    "Support joined",
    `Ticket ${ticket.ticket_number}`,
    { messageId: Number(message.id) }
  );
  return message;
}

export async function assignTicket({
  ticketId,
  actorUserId,
  actorRole,
  assigneeUserId,
  team = null,
}) {
  const ticket = await repo.getTicketById(ticketId);
  if (!ticket) throw new AppError("TICKET_NOT_FOUND", { status: 404 });

  const result = await repo.assignTicket({
    ticketId,
    actorUserId,
    actorRole,
    assigneeUserId,
    team,
  });
  if (result.code !== "OK") {
    throw new AppError("TICKET_ASSIGN_FAILED", { status: 409 });
  }
  if (assigneeUserId) {
    queueNotification({
      userId: Number(assigneeUserId),
      type: "support.ticket.assigned",
      title: "Ticket assigned",
      body: `Ticket ${ticket.ticket_number}`,
      payload: supportPayload(ticketId, { team }),
    });
    queueRealtime(Number(assigneeUserId), "support_ticket", {
      type: "support.ticket.assigned",
      ticketId: Number(ticketId),
      ticketNumber: ticket.ticket_number,
      team,
    });
  }
  return withSla(result.ticket);
}

export async function linkEntity({
  ticketId,
  actorUserId,
  actorRole,
  entityType,
  entityId,
  label = null,
  reason = null,
}) {
  const ticket = await repo.getTicketById(ticketId);
  if (!ticket) throw new AppError("TICKET_NOT_FOUND", { status: 404 });
  const link = await repo.linkEntity({
    ticketId,
    entityType,
    entityId,
    label,
    actorUserId,
    actorRole,
    reason,
  });
  queueRealtime(Number(ticket.user_id), "support_ticket", {
    type: "support.ticket.entity_linked",
    ticketId: Number(ticketId),
    entityType,
    entityId: Number(entityId),
  });
  return link;
}

export async function transitionTicket({
  ticketId,
  actorUserId,
  actorRole,
  toStatus,
}) {
  const ticket = await repo.getTicketById(ticketId);
  if (!ticket) throw new AppError("TICKET_NOT_FOUND", { status: 404 });
  if (!canTransition(ticket.status, toStatus)) {
    throw new AppError("TICKET_INVALID_TRANSITION", {
      status: 409,
      details: { currentStatus: ticket.status, toStatus },
    });
  }
  const result = await repo.transitionStatus({
    ticketId,
    toStatus,
    actorUserId,
    actorRole,
    eventType: toStatus === "ESCALATED" ? "escalated" : "status_changed",
    allowedFrom: [ticket.status],
  });
  if (result.code !== "OK") {
    throw new AppError("TICKET_INVALID_TRANSITION", {
      status: 409,
      details: { currentStatus: result.currentStatus },
    });
  }
  notifyTicketUser(
    { ...ticket, id: ticketId },
    "support.ticket.status_changed",
    "Ticket updated",
    `Ticket ${ticket.ticket_number}`,
    { status: toStatus }
  );
  return withSla(result.ticket);
}

export async function resolveTicket({
  ticketId,
  actorUserId,
  actorRole,
  summary,
  reason = null,
}) {
  const ticket = await repo.getTicketById(ticketId);
  if (!ticket) throw new AppError("TICKET_NOT_FOUND", { status: 404 });
  if (!canTransition(ticket.status, "RESOLVED")) {
    throw new AppError("TICKET_INVALID_TRANSITION", {
      status: 409,
      details: { currentStatus: ticket.status },
    });
  }
  const result = await repo.transitionStatus({
    ticketId,
    toStatus: "RESOLVED",
    actorUserId,
    actorRole,
    eventType: "resolved",
    allowedFrom: [ticket.status],
    extraSet: {
      resolved_at: new Date().toISOString(),
      resolution_summary: summary,
      resolution_reason: reason,
    },
    metadata: { reason: reason || null },
  });
  if (result.code !== "OK") {
    throw new AppError("TICKET_INVALID_TRANSITION", { status: 409 });
  }
  notifyTicketUser(
    ticket,
    "support.ticket.resolved",
    "Ticket resolved",
    `Ticket ${ticket.ticket_number} is ready for confirmation or reopening.`,
    { reason: reason || null }
  );
  return withSla(result.ticket);
}

export async function reopenTicket({ ticketId, actorUserId, actorRole, reason = null }) {
  const ticket = await repo.getTicketById(ticketId);
  if (!ticket) throw new AppError("TICKET_NOT_FOUND", { status: 404 });

  const isReporter = Number(ticket.user_id) === Number(actorUserId);
  const isAgent = actorRole && actorRole !== "customer";
  if (!isReporter && !isAgent) {
    throw new AppError("TICKET_FORBIDDEN", { status: 403 });
  }
  if (!["RESOLVED", "CLOSED"].includes(ticket.status)) {
    throw new AppError("TICKET_NOT_REOPENABLE", {
      status: 409,
      details: { currentStatus: ticket.status },
    });
  }
  const closedRef = toMs(ticket.resolved_at) || toMs(ticket.closed_at);
  if (isReporter && !isAgent && closedRef && Date.now() - closedRef > REOPEN_WINDOW_MS) {
    throw new AppError("TICKET_REOPEN_WINDOW_EXPIRED", { status: 409 });
  }

  const result = await repo.transitionStatus({
    ticketId,
    toStatus: "REOPENED",
    actorUserId,
    actorRole: actorRole || "customer",
    eventType: "reopened",
    allowedFrom: [ticket.status],
    extraSet: { reopened_count: Number(ticket.reopened_count || 0) + 1 },
    metadata: { reason: reason || null },
  });
  if (result.code !== "OK") {
    throw new AppError("TICKET_NOT_REOPENABLE", { status: 409 });
  }
  notifyAssignee(ticket, "support.ticket.reopened", "Ticket reopened", `Ticket ${ticket.ticket_number}`, {
    reason: reason || null,
  });
  return withSla(result.ticket);
}

export async function rateTicket({
  ticketId,
  userId,
  rating,
  speed = null,
  quality = null,
  comment = null,
}) {
  const ticket = await repo.getTicketById(ticketId);
  if (!ticket) throw new AppError("TICKET_NOT_FOUND", { status: 404 });
  if (Number(ticket.user_id) !== Number(userId)) {
    throw new AppError("TICKET_FORBIDDEN", { status: 403 });
  }
  if (!["RESOLVED", "CLOSED"].includes(ticket.status)) {
    throw new AppError("TICKET_NOT_RATABLE", {
      status: 409,
      details: { currentStatus: ticket.status },
    });
  }
  const result = await repo.transitionStatus({
    ticketId,
    toStatus: ticket.status,
    actorUserId: userId,
    actorRole: "customer",
    eventType: "rated",
    extraSet: {
      rating: Number(rating),
      rating_speed: speed != null ? Number(speed) : null,
      rating_quality: quality != null ? Number(quality) : null,
      rating_comment: comment,
    },
    metadata: { rating: Number(rating), speed, quality },
  });
  if (result.code !== "OK") {
    throw new AppError("TICKET_RATE_FAILED", { status: 409 });
  }
  notifyAssignee(ticket, "support.ticket.rated", "Ticket rated", `Ticket ${ticket.ticket_number}`, {
    rating: Number(rating),
  });
  return withSla(result.ticket);
}

import { pool, q } from "../../config/db.js";

function formatTicketNumber(id) {
  return `TKT-${String(id).padStart(6, "0")}`;
}

function json(value, fallback = null) {
  if (value === undefined) return fallback;
  return JSON.stringify(value ?? fallback);
}

function normalizeAttachment(input = {}, fallbackVisibility = "customer") {
  const fileUrl = String(input.fileUrl || input.file_url || "").trim();
  if (!fileUrl) return null;
  const visibility = input.visibility === "internal" ? "internal" : fallbackVisibility;
  return {
    visibility,
    fileUrl,
    storageKey: input.storageKey || input.storage_key || null,
    fileName: input.fileName || input.file_name || null,
    mimeType: input.mimeType || input.mime_type || null,
    fileSizeBytes:
      input.fileSizeBytes != null || input.file_size_bytes != null
        ? Number(input.fileSizeBytes ?? input.file_size_bytes)
        : null,
    metadata: input.metadata || input.metadata_json || {},
  };
}

async function insertAttachments(
  client,
  {
    ticketId,
    uploadedByUserId,
    messageId = null,
    internalNoteId = null,
    visibility = "customer",
    attachments = [],
  }
) {
  const rows = [];
  for (const raw of Array.isArray(attachments) ? attachments : []) {
    const a = normalizeAttachment(raw, visibility);
    if (!a) continue;
    const inserted = await client.query(
      `INSERT INTO support_ticket_attachment
         (ticket_id, message_id, internal_note_id, uploaded_by_user_id, visibility,
          file_url, storage_key, file_name, mime_type, file_size_bytes, metadata_json)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11::jsonb)
       RETURNING *`,
      [
        Number(ticketId),
        messageId ? Number(messageId) : null,
        internalNoteId ? Number(internalNoteId) : null,
        uploadedByUserId ? Number(uploadedByUserId) : null,
        a.visibility,
        a.fileUrl,
        a.storageKey,
        a.fileName,
        a.mimeType,
        Number.isFinite(a.fileSizeBytes) ? a.fileSizeBytes : null,
        json(a.metadata, {}),
      ]
    );
    rows.push(inserted.rows[0]);
  }
  return rows;
}

async function insertEvent(
  client,
  {
    ticketId,
    actorUserId = null,
    actorRole = null,
    eventType,
    fromStatus = null,
    toStatus = null,
    metadata = null,
  }
) {
  await client.query(
    `INSERT INTO support_ticket_event
       (ticket_id, actor_user_id, actor_role, event_type, from_status, to_status, metadata)
     VALUES ($1,$2,$3,$4,$5,$6,$7::jsonb)`,
    [
      Number(ticketId),
      actorUserId ? Number(actorUserId) : null,
      actorRole,
      eventType,
      fromStatus,
      toStatus,
      metadata ? json(metadata, {}) : null,
    ]
  );
}

export async function createTicket({
  userId,
  domain,
  type,
  priority,
  subject,
  description,
  entityType = null,
  entityId = null,
  entityLabel = null,
  attachments = [],
  slaFirstResponseDueAt = null,
  slaResolutionDueAt = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const ins = await client.query(
      `INSERT INTO support_ticket
         (user_id, domain, type, priority, subject, description,
          entity_type, entity_id, sla_first_response_due_at, sla_resolution_due_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
       RETURNING *`,
      [
        Number(userId),
        domain,
        type,
        priority,
        subject,
        description || null,
        entityType,
        entityId != null ? Number(entityId) : null,
        slaFirstResponseDueAt,
        slaResolutionDueAt,
      ]
    );
    const row = ins.rows[0];
    const upd = await client.query(
      `UPDATE support_ticket SET ticket_number = $2 WHERE id = $1 RETURNING *`,
      [row.id, formatTicketNumber(row.id)]
    );
    if (entityType && entityId != null) {
      await client.query(
        `INSERT INTO support_ticket_link
           (ticket_id, entity_type, entity_id, label, linked_by_user_id, reason)
         VALUES ($1,$2,$3,$4,$5,'initial_ticket_link')
         ON CONFLICT (ticket_id, entity_type, entity_id) DO NOTHING`,
        [row.id, entityType, Number(entityId), entityLabel, Number(userId)]
      );
    }
    const attachmentRows = await insertAttachments(client, {
      ticketId: row.id,
      uploadedByUserId: userId,
      visibility: "customer",
      attachments,
    });
    await insertEvent(client, {
      ticketId: row.id,
      actorUserId: userId,
      actorRole: "customer",
      eventType: "created",
      toStatus: "NEW",
      metadata: {
        entityType: entityType || null,
        entityId: entityId != null ? Number(entityId) : null,
        attachmentCount: attachmentRows.length,
      },
    });
    await client.query("COMMIT");
    return upd.rows[0];
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function getTicketById(ticketId) {
  const r = await q(`SELECT * FROM support_ticket WHERE id = $1`, [
    Number(ticketId),
  ]);
  return r.rows[0] || null;
}

export async function getUserDisplayName(userId) {
  const r = await q(
    `SELECT COALESCE(NULLIF(full_name, ''), NULLIF(username, ''), 'Support') AS name
     FROM app_user
     WHERE id = $1`,
    [Number(userId)]
  );
  return r.rows[0]?.name || "Support";
}

export async function listTickets({
  userId = null,
  assignedUserId = null,
  team = null,
  domain = null,
  status = null,
  priority = null,
  waiting = false,
  urgent = false,
  breachedSla = false,
  search = null,
  from = null,
  to = null,
  limit = 25,
  offset = 0,
} = {}) {
  const safeLimit = Math.max(1, Math.min(100, Number(limit) || 25));
  const safeOffset = Math.max(0, Number(offset) || 0);
  const conds = [];
  const params = [];
  const add = (value, sql) => {
    params.push(value);
    conds.push(sql(params.length));
  };
  if (userId) add(Number(userId), (i) => `user_id = $${i}`);
  if (assignedUserId) {
    add(Number(assignedUserId), (i) => `assigned_user_id = $${i}`);
  }
  if (team) add(String(team), (i) => `team = $${i}`);
  if (domain) add(String(domain), (i) => `domain = $${i}`);
  if (status) add(String(status), (i) => `status = $${i}`);
  if (priority) add(String(priority), (i) => `priority = $${i}`);
  if (waiting) {
    conds.push(
      `status IN ('WAITING_FOR_CUSTOMER','WAITING_FOR_MERCHANT','WAITING_FOR_CAPTAIN','WAITING_FOR_DELIVERY')`
    );
  }
  if (urgent) conds.push(`priority = 'urgent'`);
  if (breachedSla) {
    conds.push(
      `(
        (first_response_at IS NULL AND sla_first_response_due_at < NOW())
        OR (resolved_at IS NULL AND status NOT IN ('RESOLVED','CLOSED') AND sla_resolution_due_at < NOW())
      )`
    );
  }
  if (search) {
    add(`%${String(search).trim()}%`, (i) =>
      `(ticket_number ILIKE $${i} OR subject ILIKE $${i} OR description ILIKE $${i})`
    );
  }
  if (from) add(from, (i) => `created_at >= $${i}`);
  if (to) add(to, (i) => `created_at <= $${i}`);
  const where = conds.length ? `WHERE ${conds.join(" AND ")}` : "";
  const countRes = await q(
    `SELECT COUNT(*)::int AS total FROM support_ticket ${where}`,
    params
  );
  params.push(safeLimit, safeOffset);
  const rows = await q(
    `SELECT *
     FROM support_ticket
     ${where}
     ORDER BY updated_at DESC, id DESC
     LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );
  return {
    total: Number(countRes.rows[0]?.total || 0),
    limit: safeLimit,
    offset: safeOffset,
    items: rows.rows,
  };
}

export async function addMessage({
  ticketId,
  authorUserId,
  authorRole,
  isInternal = false,
  body,
  attachments = [],
  markFirstResponse = false,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const ins = await client.query(
      `INSERT INTO support_ticket_message
         (ticket_id, author_user_id, author_role, is_internal, body, attachments_json)
       VALUES ($1,$2,$3,$4,$5,$6::jsonb)
       RETURNING *`,
      [
        Number(ticketId),
        authorUserId ? Number(authorUserId) : null,
        authorRole,
        Boolean(isInternal),
        body,
        json(attachments || [], []),
      ]
    );
    const attachmentRows = await insertAttachments(client, {
      ticketId,
      uploadedByUserId: authorUserId,
      messageId: ins.rows[0].id,
      visibility: isInternal ? "internal" : "customer",
      attachments,
    });
    if (markFirstResponse) {
      await client.query(
        `UPDATE support_ticket
         SET first_response_at = COALESCE(first_response_at, NOW()), updated_at = NOW()
         WHERE id = $1`,
        [Number(ticketId)]
      );
    } else {
      await client.query(
        `UPDATE support_ticket SET updated_at = NOW() WHERE id = $1`,
        [Number(ticketId)]
      );
    }
    await insertEvent(client, {
      ticketId,
      actorUserId: authorUserId,
      actorRole: authorRole,
      eventType: isInternal ? "internal_message_added" : "message_added",
      metadata: { attachmentCount: attachmentRows.length },
    });
    await client.query("COMMIT");
    return ins.rows[0];
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function addInternalNote({
  ticketId,
  authorUserId,
  authorRole,
  body,
  attachments = [],
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const ins = await client.query(
      `INSERT INTO support_ticket_internal_note
         (ticket_id, author_user_id, author_role, body, attachments_json)
       VALUES ($1,$2,$3,$4,$5::jsonb)
       RETURNING *`,
      [
        Number(ticketId),
        authorUserId ? Number(authorUserId) : null,
        authorRole || "agent",
        body,
        json(attachments || [], []),
      ]
    );
    const attachmentRows = await insertAttachments(client, {
      ticketId,
      uploadedByUserId: authorUserId,
      internalNoteId: ins.rows[0].id,
      visibility: "internal",
      attachments,
    });
    await client.query(
      `UPDATE support_ticket SET updated_at = NOW() WHERE id = $1`,
      [Number(ticketId)]
    );
    await insertEvent(client, {
      ticketId,
      actorUserId: authorUserId,
      actorRole: authorRole || "agent",
      eventType: "internal_note_added",
      metadata: { attachmentCount: attachmentRows.length },
    });
    await client.query("COMMIT");
    return ins.rows[0];
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function listMessages(
  ticketId,
  { includeInternal = false, limit = 100, offset = 0 } = {}
) {
  const safeLimit = Math.max(1, Math.min(200, Number(limit) || 100));
  const safeOffset = Math.max(0, Number(offset) || 0);
  const r = await q(
    `SELECT *
     FROM support_ticket_message
     WHERE ticket_id = $1 ${includeInternal ? "" : "AND is_internal = FALSE"}
     ORDER BY created_at ASC, id ASC
     LIMIT $2 OFFSET $3`,
    [Number(ticketId), safeLimit, safeOffset]
  );
  return r.rows;
}

export async function listInternalNotes(ticketId, { limit = 100, offset = 0 } = {}) {
  const safeLimit = Math.max(1, Math.min(200, Number(limit) || 100));
  const safeOffset = Math.max(0, Number(offset) || 0);
  const r = await q(
    `SELECT *
     FROM support_ticket_internal_note
     WHERE ticket_id = $1
     ORDER BY created_at ASC, id ASC
     LIMIT $2 OFFSET $3`,
    [Number(ticketId), safeLimit, safeOffset]
  );
  return r.rows;
}

export async function listEvents(ticketId, { limit = 200, offset = 0 } = {}) {
  const safeLimit = Math.max(1, Math.min(500, Number(limit) || 200));
  const safeOffset = Math.max(0, Number(offset) || 0);
  const r = await q(
    `SELECT *
     FROM support_ticket_event
     WHERE ticket_id = $1
     ORDER BY created_at ASC, id ASC
     LIMIT $2 OFFSET $3`,
    [Number(ticketId), safeLimit, safeOffset]
  );
  return r.rows;
}

export async function listLinks(ticketId) {
  const r = await q(
    `SELECT *
     FROM support_ticket_link
     WHERE ticket_id = $1
     ORDER BY created_at DESC, id DESC`,
    [Number(ticketId)]
  );
  return r.rows;
}

export async function listAttachments(ticketId, { includeInternal = false } = {}) {
  const r = await q(
    `SELECT *
     FROM support_ticket_attachment
     WHERE ticket_id = $1 ${includeInternal ? "" : "AND visibility = 'customer'"}
     ORDER BY created_at DESC, id DESC`,
    [Number(ticketId)]
  );
  return r.rows;
}

export async function assignTicket({
  ticketId,
  actorUserId,
  actorRole,
  assigneeUserId,
  team = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const lock = await client.query(
      `SELECT * FROM support_ticket WHERE id = $1 FOR UPDATE`,
      [Number(ticketId)]
    );
    const ticket = lock.rows[0];
    if (!ticket) {
      await client.query("ROLLBACK");
      return { code: "TICKET_NOT_FOUND" };
    }
    const nextStatus =
      ticket.status === "NEW" || ticket.status === "TRIAGED"
        ? "ASSIGNED"
        : ticket.status;
    const action = assigneeUserId
      ? ticket.assigned_user_id && Number(ticket.assigned_user_id) !== Number(assigneeUserId)
        ? "reassigned"
        : "assigned"
      : "unassigned";
    await client.query(
      `UPDATE support_ticket_assignment
       SET active = FALSE
       WHERE ticket_id = $1 AND active = TRUE`,
      [Number(ticketId)]
    );
    if (assigneeUserId || team) {
      await client.query(
        `INSERT INTO support_ticket_assignment
           (ticket_id, assigned_user_id, team, assigned_by_user_id, action, active)
         VALUES ($1,$2,$3,$4,$5,TRUE)`,
        [
          Number(ticketId),
          assigneeUserId ? Number(assigneeUserId) : null,
          team,
          actorUserId ? Number(actorUserId) : null,
          action,
        ]
      );
    }
    const upd = await client.query(
      `UPDATE support_ticket
       SET status = $2,
           assigned_user_id = $3,
           team = $4,
           updated_at = NOW()
       WHERE id = $1
       RETURNING *`,
      [
        Number(ticketId),
        nextStatus,
        assigneeUserId ? Number(assigneeUserId) : null,
        team,
      ]
    );
    await insertEvent(client, {
      ticketId,
      actorUserId,
      actorRole,
      eventType: action,
      fromStatus: ticket.status,
      toStatus: nextStatus,
      metadata: { assigneeUserId: assigneeUserId || null, team },
    });
    await client.query("COMMIT");
    return { code: "OK", ticket: upd.rows[0], previousStatus: ticket.status };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function joinConversation({ ticketId, agentUserId, agentRole }) {
  const name = await getUserDisplayName(agentUserId);
  const body = `انضم ${name} إلى المحادثة.`;
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const message = await client.query(
      `INSERT INTO support_ticket_message
         (ticket_id, author_user_id, author_role, is_internal, body, attachments_json)
       VALUES ($1,$2,$3,FALSE,$4,'[]'::jsonb)
       RETURNING *`,
      [Number(ticketId), Number(agentUserId), agentRole || "agent", body]
    );
    await client.query(
      `UPDATE support_ticket
       SET first_response_at = COALESCE(first_response_at, NOW()), updated_at = NOW()
       WHERE id = $1`,
      [Number(ticketId)]
    );
    await insertEvent(client, {
      ticketId,
      actorUserId: agentUserId,
      actorRole: agentRole || "agent",
      eventType: "agent_joined",
      metadata: { agentName: name },
    });
    await client.query("COMMIT");
    return message.rows[0];
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function linkEntity({
  ticketId,
  entityType,
  entityId,
  label = null,
  actorUserId = null,
  actorRole = null,
  reason = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const inserted = await client.query(
      `INSERT INTO support_ticket_link
         (ticket_id, entity_type, entity_id, label, linked_by_user_id, reason)
       VALUES ($1,$2,$3,$4,$5,$6)
       ON CONFLICT (ticket_id, entity_type, entity_id)
       DO UPDATE SET label = COALESCE(EXCLUDED.label, support_ticket_link.label),
                     reason = COALESCE(EXCLUDED.reason, support_ticket_link.reason)
       RETURNING *`,
      [
        Number(ticketId),
        entityType,
        Number(entityId),
        label,
        actorUserId ? Number(actorUserId) : null,
        reason,
      ]
    );
    await client.query(
      `UPDATE support_ticket
       SET entity_type = COALESCE(entity_type, $2),
           entity_id = COALESCE(entity_id, $3),
           updated_at = NOW()
       WHERE id = $1`,
      [Number(ticketId), entityType, Number(entityId)]
    );
    await insertEvent(client, {
      ticketId,
      actorUserId,
      actorRole,
      eventType: "entity_linked",
      metadata: { entityType, entityId: Number(entityId), label, reason },
    });
    await client.query("COMMIT");
    return inserted.rows[0];
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function transitionStatus({
  ticketId,
  toStatus,
  actorUserId = null,
  actorRole = null,
  eventType = "status_changed",
  extraSet = {},
  metadata = null,
  allowedFrom = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const lock = await client.query(
      `SELECT * FROM support_ticket WHERE id = $1 FOR UPDATE`,
      [Number(ticketId)]
    );
    const ticket = lock.rows[0];
    if (!ticket) {
      await client.query("ROLLBACK");
      return { code: "TICKET_NOT_FOUND" };
    }
    if (Array.isArray(allowedFrom) && !allowedFrom.includes(ticket.status)) {
      await client.query("ROLLBACK");
      return { code: "INVALID_TRANSITION", currentStatus: ticket.status };
    }

    const sets = ["status = $2", "updated_at = NOW()"];
    const params = [Number(ticketId), toStatus];
    for (const [col, val] of Object.entries(extraSet)) {
      params.push(val);
      sets.push(`${col} = $${params.length}`);
    }
    const upd = await client.query(
      `UPDATE support_ticket SET ${sets.join(", ")} WHERE id = $1 RETURNING *`,
      params
    );
    await insertEvent(client, {
      ticketId,
      actorUserId,
      actorRole,
      eventType,
      fromStatus: ticket.status,
      toStatus,
      metadata,
    });
    await client.query("COMMIT");
    return { code: "OK", ticket: upd.rows[0], previousStatus: ticket.status };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

// اقتراح عناصر لربطها بتذكرة عامة: أحدث طلبات ورحلات صاحب التذكرة.
export async function listLinkSuggestionsForUser(userId, { limit = 5 } = {}) {
  const safeLimit = Math.max(1, Math.min(20, Number(limit) || 5));
  const orders = await q(
    `SELECT id, status::text AS status, total_amount, created_at
     FROM customer_order
     WHERE customer_user_id = $1
     ORDER BY created_at DESC
     LIMIT $2`,
    [Number(userId), safeLimit]
  );
  const rides = await q(
    `SELECT id, status, pickup_label, dropoff_label, created_at
     FROM taxi_ride_request
     WHERE customer_user_id = $1
     ORDER BY created_at DESC
     LIMIT $2`,
    [Number(userId), safeLimit]
  );
  return {
    orders: orders.rows.map((o) => ({
      entityType: "order",
      entityId: Number(o.id),
      label: `طلب #${o.id}`,
      status: o.status,
      total: o.total_amount,
      createdAt: o.created_at,
    })),
    rides: rides.rows.map((r) => ({
      entityType: "ride",
      entityId: Number(r.id),
      label: `رحلة #${r.id}`,
      status: r.status,
      route: [r.pickup_label, r.dropoff_label].filter(Boolean).join(" → "),
      createdAt: r.created_at,
    })),
  };
}

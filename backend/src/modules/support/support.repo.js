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
  channel = "app",
  createdByUserId = null,
  callOutcome = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const ins = await client.query(
      `INSERT INTO support_ticket
         (user_id, domain, type, priority, subject, description,
          entity_type, entity_id, sla_first_response_due_at, sla_resolution_due_at,
          channel, created_by_user_id, call_outcome)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)
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
        channel || "app",
        createdByUserId != null ? Number(createdByUserId) : null,
        callOutcome || null,
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
      actorUserId: createdByUserId != null ? Number(createdByUserId) : Number(userId),
      actorRole: createdByUserId != null ? "agent" : "customer",
      eventType: "created",
      toStatus: "NEW",
      metadata: {
        entityType: entityType || null,
        entityId: entityId != null ? Number(entityId) : null,
        attachmentCount: attachmentRows.length,
        channel: channel || "app",
        onBehalf: createdByUserId != null,
        callOutcome: callOutcome || null,
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

// بحث عن عميل برقم الهاتف (مطابقة بالأرقام فقط) لفتح تذكرة نيابةً عنه.
export async function findCustomerByPhone(phone) {
  const raw = String(phone || "").trim();
  if (!raw) return null;
  const r = await q(
    `SELECT id, full_name, phone, role
     FROM app_user
     WHERE regexp_replace(phone, '\\D', '', 'g') = regexp_replace($1, '\\D', '', 'g')
     ORDER BY id ASC
     LIMIT 1`,
    [raw]
  );
  return r.rows[0] || null;
}

export async function upsertAgentPresence({
  agentUserId,
  status = "available",
  team = null,
  skillDomains = [],
  currentTicketId = null,
}) {
  const domains = Array.isArray(skillDomains)
    ? skillDomains
        .map((item) => String(item || "").trim().toUpperCase())
        .filter(Boolean)
    : [];
  const r = await q(
    `INSERT INTO support_agent_presence
       (agent_user_id, status, team, skill_domains, current_ticket_id, last_seen_at, updated_at)
     VALUES ($1,$2,$3,$4::jsonb,$5,NOW(),NOW())
     ON CONFLICT (agent_user_id)
     DO UPDATE SET
       status = EXCLUDED.status,
       team = EXCLUDED.team,
       skill_domains = EXCLUDED.skill_domains,
       current_ticket_id = EXCLUDED.current_ticket_id,
       last_seen_at = NOW(),
       updated_at = NOW()
     RETURNING *`,
    [
      Number(agentUserId),
      String(status || "available"),
      team ? String(team) : null,
      json(domains, []),
      currentTicketId ? Number(currentTicketId) : null,
    ]
  );
  return r.rows[0] || null;
}

export async function markAgentAssigned({ agentUserId, ticketId }) {
  const r = await q(
    `INSERT INTO support_agent_presence
       (agent_user_id, status, current_ticket_id, last_assigned_at, last_seen_at, updated_at)
     VALUES ($1,'on_ticket',$2,NOW(),NOW(),NOW())
     ON CONFLICT (agent_user_id)
     DO UPDATE SET
       status = 'on_ticket',
       current_ticket_id = EXCLUDED.current_ticket_id,
       last_assigned_at = NOW(),
       last_seen_at = NOW(),
       updated_at = NOW()
     RETURNING *`,
    [Number(agentUserId), Number(ticketId)]
  );
  return r.rows[0] || null;
}

export async function markAgentAfterTicketDone({ agentUserId, ticketId, status = "acw" }) {
  const r = await q(
    `UPDATE support_agent_presence
     SET status = $3,
         current_ticket_id = NULL,
         last_seen_at = NOW(),
         updated_at = NOW()
     WHERE agent_user_id = $1
       AND (current_ticket_id = $2 OR current_ticket_id IS NULL)
     RETURNING *`,
    [Number(agentUserId), Number(ticketId), String(status || "acw")]
  );
  return r.rows[0] || null;
}

export async function getAgentPresence(agentUserId) {
  const r = await q(
    `SELECT * FROM support_agent_presence WHERE agent_user_id = $1`,
    [Number(agentUserId)]
  );
  return r.rows[0] || null;
}

export async function listAgentPresence({ team = null, status = null, limit = 100 } = {}) {
  const params = [];
  const conds = [];
  if (team) {
    params.push(String(team));
    conds.push(`p.team = $${params.length}`);
  }
  if (status) {
    params.push(String(status));
    conds.push(`p.status = $${params.length}`);
  }
  params.push(Math.max(1, Math.min(500, Number(limit) || 100)));
  const where = conds.length ? `WHERE ${conds.join(" AND ")}` : "";
  const r = await q(
    `WITH load AS (
       SELECT assigned_user_id, COUNT(*)::int AS open_count
       FROM support_ticket
       WHERE assigned_user_id IS NOT NULL
         AND status NOT IN ('RESOLVED','CLOSED')
       GROUP BY assigned_user_id
     )
     SELECT p.*, u.full_name, u.phone, COALESCE(l.open_count, 0)::int AS open_count
     FROM support_agent_presence p
     JOIN app_user u ON u.id = p.agent_user_id
     LEFT JOIN load l ON l.assigned_user_id = p.agent_user_id
     ${where}
     ORDER BY p.status ASC, COALESCE(l.open_count, 0) ASC,
              p.last_assigned_at ASC NULLS FIRST, p.updated_at ASC
     LIMIT $${params.length}`,
    params
  );
  return r.rows;
}

export async function findBestAvailableAgent({ domain, team = null }) {
  const normalizedDomain = String(domain || "").trim().toUpperCase();
  const params = [normalizedDomain];
  const conds = [`p.status = 'available'`];
  if (team) {
    params.push(String(team));
    conds.push(`p.team = $${params.length}`);
  }
  const r = await q(
    `WITH load AS (
       SELECT assigned_user_id, COUNT(*)::int AS open_count
       FROM support_ticket
       WHERE assigned_user_id IS NOT NULL
         AND status NOT IN ('RESOLVED','CLOSED')
       GROUP BY assigned_user_id
     )
     SELECT p.*, COALESCE(l.open_count, 0)::int AS open_count
     FROM support_agent_presence p
     LEFT JOIN load l ON l.assigned_user_id = p.agent_user_id
     WHERE ${conds.join(" AND ")}
       AND (
         jsonb_array_length(p.skill_domains) = 0
         OR p.skill_domains ? $1
       )
     ORDER BY COALESCE(l.open_count, 0) ASC,
              p.last_assigned_at ASC NULLS FIRST,
              p.updated_at ASC
     LIMIT 1`,
    params
  );
  return r.rows[0] || null;
}

export async function updateTicketRouting({ ticketId, strategy, team = null }) {
  const r = await q(
    `UPDATE support_ticket
     SET routed_at = NOW(),
         routing_strategy = $2,
         team = COALESCE($3, team),
         updated_at = NOW()
     WHERE id = $1
     RETURNING *`,
    [Number(ticketId), String(strategy || "auto"), team ? String(team) : null]
  );
  return r.rows[0] || null;
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

export async function markSlaWarning(ticketId) {
  const r = await q(
    `UPDATE support_ticket
     SET sla_warning_notified_at = NOW(),
         updated_at = NOW()
     WHERE id = $1
       AND sla_warning_notified_at IS NULL
       AND status NOT IN ('RESOLVED','CLOSED')
     RETURNING *`,
    [Number(ticketId)]
  );
  return r.rows[0] || null;
}

export async function listSlaWarningCandidates({ withinMinutes = 30, limit = 50 } = {}) {
  const safeLimit = Math.max(1, Math.min(200, Number(limit) || 50));
  const safeWindow = Math.max(1, Math.min(240, Number(withinMinutes) || 30));
  const r = await q(
    `SELECT *
     FROM support_ticket
     WHERE status NOT IN ('RESOLVED','CLOSED')
       AND sla_warning_notified_at IS NULL
       AND (
         (
           first_response_at IS NULL
           AND sla_first_response_due_at IS NOT NULL
           AND sla_first_response_due_at > NOW()
           AND sla_first_response_due_at <= NOW() + ($1::text || ' minutes')::interval
         )
         OR (
           resolved_at IS NULL
           AND sla_resolution_due_at IS NOT NULL
           AND sla_resolution_due_at > NOW()
           AND sla_resolution_due_at <= NOW() + ($1::text || ' minutes')::interval
         )
       )
     ORDER BY LEAST(
       COALESCE(sla_first_response_due_at, 'infinity'::timestamptz),
       COALESCE(sla_resolution_due_at, 'infinity'::timestamptz)
     ) ASC
     LIMIT $2`,
    [safeWindow, safeLimit]
  );
  return r.rows;
}

export async function listSlaBreachCandidates({ limit = 50 } = {}) {
  const safeLimit = Math.max(1, Math.min(200, Number(limit) || 50));
  const r = await q(
    `SELECT *,
       CASE
         WHEN first_response_at IS NULL
          AND sla_first_response_due_at IS NOT NULL
          AND sla_first_response_due_at < NOW()
           THEN 'first_response'
         ELSE 'resolution'
       END AS sla_breach_type
     FROM support_ticket
     WHERE status NOT IN ('RESOLVED','CLOSED')
       AND sla_escalated_at IS NULL
       AND (
         (
           first_response_at IS NULL
           AND sla_first_response_due_at IS NOT NULL
           AND sla_first_response_due_at < NOW()
         )
         OR (
           resolved_at IS NULL
           AND sla_resolution_due_at IS NOT NULL
           AND sla_resolution_due_at < NOW()
         )
       )
     ORDER BY LEAST(
       COALESCE(sla_first_response_due_at, 'infinity'::timestamptz),
       COALESCE(sla_resolution_due_at, 'infinity'::timestamptz)
     ) ASC
     LIMIT $1`,
    [safeLimit]
  );
  return r.rows;
}

export async function getSupervisorOverview() {
  const [queues, agents, sla] = await Promise.all([
    q(
      `SELECT
         COALESCE(team, 'general') AS team,
         COUNT(*)::int AS open_count,
         COUNT(*) FILTER (WHERE assigned_user_id IS NULL)::int AS unassigned_count,
         MIN(created_at) FILTER (WHERE assigned_user_id IS NULL) AS oldest_unassigned_at,
         COUNT(*) FILTER (WHERE priority = 'urgent')::int AS urgent_count
       FROM support_ticket
       WHERE status NOT IN ('RESOLVED','CLOSED')
       GROUP BY COALESCE(team, 'general')
       ORDER BY open_count DESC, team ASC`
    ),
    q(
      `WITH load AS (
         SELECT assigned_user_id, COUNT(*)::int AS open_count
         FROM support_ticket
         WHERE assigned_user_id IS NOT NULL
           AND status NOT IN ('RESOLVED','CLOSED')
         GROUP BY assigned_user_id
       )
       SELECT p.*, u.full_name, COALESCE(l.open_count, 0)::int AS open_count
       FROM support_agent_presence p
       JOIN app_user u ON u.id = p.agent_user_id
       LEFT JOIN load l ON l.assigned_user_id = p.agent_user_id
       ORDER BY p.team ASC NULLS LAST, p.status ASC, open_count DESC`
    ),
    q(
      `SELECT
         COUNT(*) FILTER (
           WHERE first_response_at IS NULL
             AND sla_first_response_due_at IS NOT NULL
             AND sla_first_response_due_at < NOW()
         )::int AS first_response_breached,
         COUNT(*) FILTER (
           WHERE resolved_at IS NULL
             AND sla_resolution_due_at IS NOT NULL
             AND sla_resolution_due_at < NOW()
         )::int AS resolution_breached,
         COUNT(*) FILTER (WHERE status = 'ESCALATED')::int AS escalated_open
       FROM support_ticket
       WHERE status NOT IN ('RESOLVED','CLOSED')`
    ),
  ]);
  return {
    queues: queues.rows,
    agents: agents.rows,
    sla: sla.rows[0] || {
      first_response_breached: 0,
      resolution_breached: 0,
      escalated_open: 0,
    },
  };
}

export async function escalateTicketForSla({
  ticketId,
  escalationTeam,
  escalatedToUserId = null,
  reason = "sla_breached",
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
    if (ticket.sla_escalated_at || ["RESOLVED", "CLOSED"].includes(ticket.status)) {
      await client.query("ROLLBACK");
      return { code: "SKIPPED", ticket };
    }
    const upd = await client.query(
      `UPDATE support_ticket
       SET status = 'ESCALATED',
           escalation_team = $2,
           escalated_to_user_id = $3,
           escalation_reason = $4,
           sla_escalated_at = NOW(),
           assigned_user_id = COALESCE($3, assigned_user_id),
           team = COALESCE($2, team),
           updated_at = NOW()
       WHERE id = $1
       RETURNING *`,
      [
        Number(ticketId),
        escalationTeam ? String(escalationTeam) : null,
        escalatedToUserId ? Number(escalatedToUserId) : null,
        String(reason || "sla_breached").slice(0, 64),
      ]
    );
    await insertEvent(client, {
      ticketId,
      actorUserId: null,
      actorRole: "system",
      eventType: "sla_escalated",
      fromStatus: ticket.status,
      toStatus: "ESCALATED",
      metadata: {
        escalationTeam: escalationTeam || null,
        escalatedToUserId: escalatedToUserId ? Number(escalatedToUserId) : null,
        reason,
      },
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
    `SELECT id, status::text AS status, total_amount, created_at,
            COALESCE(customer_confirmed_at, delivered_at) AS ended_at
     FROM customer_order
     WHERE customer_user_id = $1
     ORDER BY created_at DESC
     LIMIT $2`,
    [Number(userId), safeLimit]
  );
  const rides = await q(
    `SELECT id, status, pickup_label, dropoff_label, created_at,
            COALESCE(completed_at, cancelled_at) AS ended_at
     FROM taxi_ride_request
     WHERE customer_user_id = $1
     ORDER BY created_at DESC
     LIMIT $2`,
    [Number(userId), safeLimit]
  );
  // حالات منتهية للطلب/الرحلة — ما عداها يُعتبر جارياً.
  const ORDER_ENDED = new Set([
    "delivered",
    "delivered_by_courier",
    "received_by_customer",
    "completed",
    "cancelled",
    "cancelled_by_store",
    "cancelled_by_admin",
    "cancelled_by_customer",
  ]);
  const RIDE_ONGOING = new Set([
    "searching",
    "price_raise_required",
    "captain_assigned",
    "captain_arriving",
    "ride_started",
  ]);
  return {
    orders: orders.rows.map((o) => ({
      entityType: "order",
      entityId: Number(o.id),
      label: `طلب #${o.id}`,
      status: o.status,
      total: o.total_amount,
      createdAt: o.created_at,
      endedAt: o.ended_at,
      ongoing: !ORDER_ENDED.has(String(o.status || "")),
    })),
    rides: rides.rows.map((r) => ({
      entityType: "ride",
      entityId: Number(r.id),
      label: `رحلة #${r.id}`,
      status: r.status,
      route: [r.pickup_label, r.dropoff_label].filter(Boolean).join(" → "),
      createdAt: r.created_at,
      endedAt: r.ended_at,
      ongoing: RIDE_ONGOING.has(String(r.status || "")),
    })),
  };
}

export async function listCannedResponses({
  domain = null,
  type = null,
  includeInactive = false,
  limit = 100,
} = {}) {
  const safeLimit = Math.max(1, Math.min(200, Number(limit) || 100));
  const params = [];
  const where = [];
  if (!includeInactive) where.push("is_active = TRUE");
  if (domain) {
    params.push(String(domain).toUpperCase());
    where.push(`(domain IS NULL OR domain = $${params.length})`);
  }
  if (type) {
    params.push(String(type).toUpperCase());
    where.push(`(type IS NULL OR type = $${params.length})`);
  }
  params.push(safeLimit);
  const r = await q(
    `SELECT cr.*, u.full_name AS created_by_name
     FROM support_canned_response cr
     LEFT JOIN app_user u ON u.id = cr.created_by_user_id
     ${where.length ? `WHERE ${where.join(" AND ")}` : ""}
     ORDER BY cr.domain NULLS FIRST, cr.type NULLS FIRST, cr.title ASC
     LIMIT $${params.length}`,
    params
  );
  return r.rows;
}

export async function createCannedResponse({
  title,
  body,
  domain = null,
  type = null,
  actorUserId = null,
}) {
  const r = await q(
    `INSERT INTO support_canned_response
       (title, body, domain, type, created_by_user_id, updated_by_user_id)
     VALUES ($1,$2,$3,$4,$5,$5)
     RETURNING *`,
    [
      String(title),
      String(body),
      domain ? String(domain).toUpperCase() : null,
      type ? String(type).toUpperCase() : null,
      actorUserId ? Number(actorUserId) : null,
    ]
  );
  return r.rows[0];
}

export async function updateCannedResponse({
  id,
  title,
  body,
  domain = null,
  type = null,
  isActive = true,
  actorUserId = null,
}) {
  const r = await q(
    `UPDATE support_canned_response
     SET title = $2,
         body = $3,
         domain = $4,
         type = $5,
         is_active = $6,
         updated_by_user_id = $7,
         updated_at = NOW()
     WHERE id = $1
     RETURNING *`,
    [
      Number(id),
      String(title),
      String(body),
      domain ? String(domain).toUpperCase() : null,
      type ? String(type).toUpperCase() : null,
      Boolean(isActive),
      actorUserId ? Number(actorUserId) : null,
    ]
  );
  return r.rows[0] || null;
}

export async function listKnowledgeArticles({
  domain = null,
  search = null,
  includeUnpublished = false,
  limit = 50,
} = {}) {
  const safeLimit = Math.max(1, Math.min(100, Number(limit) || 50));
  const params = [];
  const where = [];
  if (!includeUnpublished) where.push("is_published = TRUE");
  if (domain) {
    params.push(String(domain).toUpperCase());
    where.push(`(domain IS NULL OR domain = $${params.length})`);
  }
  if (search) {
    params.push(`%${String(search).trim()}%`);
    where.push(`(title ILIKE $${params.length} OR body ILIKE $${params.length})`);
  }
  params.push(safeLimit);
  const r = await q(
    `SELECT ka.*, u.full_name AS created_by_name
     FROM support_knowledge_article ka
     LEFT JOIN app_user u ON u.id = ka.created_by_user_id
     ${where.length ? `WHERE ${where.join(" AND ")}` : ""}
     ORDER BY ka.domain NULLS FIRST, ka.updated_at DESC, ka.title ASC
     LIMIT $${params.length}`,
    params
  );
  return r.rows;
}

export async function createKnowledgeArticle({
  title,
  body,
  domain = null,
  tags = [],
  actorUserId = null,
}) {
  const r = await q(
    `INSERT INTO support_knowledge_article
       (title, body, domain, tags, created_by_user_id, updated_by_user_id)
     VALUES ($1,$2,$3,$4::jsonb,$5,$5)
     RETURNING *`,
    [
      String(title),
      String(body),
      domain ? String(domain).toUpperCase() : null,
      json(tags, []),
      actorUserId ? Number(actorUserId) : null,
    ]
  );
  return r.rows[0];
}

export async function updateKnowledgeArticle({
  id,
  title,
  body,
  domain = null,
  tags = [],
  isPublished = true,
  actorUserId = null,
}) {
  const r = await q(
    `UPDATE support_knowledge_article
     SET title = $2,
         body = $3,
         domain = $4,
         tags = $5::jsonb,
         is_published = $6,
         updated_by_user_id = $7,
         updated_at = NOW()
     WHERE id = $1
     RETURNING *`,
    [
      Number(id),
      String(title),
      String(body),
      domain ? String(domain).toUpperCase() : null,
      json(tags, []),
      Boolean(isPublished),
      actorUserId ? Number(actorUserId) : null,
    ]
  );
  return r.rows[0] || null;
}

export async function createCallback({
  ticketId,
  customerUserId = null,
  assignedUserId = null,
  createdByUserId = null,
  scheduledAt,
  phone = null,
  notes = null,
}) {
  const r = await q(
    `INSERT INTO support_ticket_callback
       (ticket_id, customer_user_id, assigned_user_id, created_by_user_id,
        scheduled_at, phone, notes)
     VALUES ($1,$2,$3,$4,$5,$6,$7)
     RETURNING *`,
    [
      Number(ticketId),
      customerUserId ? Number(customerUserId) : null,
      assignedUserId ? Number(assignedUserId) : null,
      createdByUserId ? Number(createdByUserId) : null,
      scheduledAt,
      phone || null,
      notes || null,
    ]
  );
  await q(
    `INSERT INTO support_ticket_event
       (ticket_id, actor_user_id, actor_role, event_type, metadata)
     VALUES ($1,$2,'agent','callback_scheduled',$3::jsonb)`,
    [
      Number(ticketId),
      createdByUserId ? Number(createdByUserId) : null,
      json(
        { callbackId: r.rows[0].id, scheduledAt, assignedUserId, phone },
        {}
      ),
    ]
  );
  return r.rows[0];
}

export async function listCallbacks({
  ticketId = null,
  assignedUserId = null,
  status = null,
  limit = 50,
} = {}) {
  const safeLimit = Math.max(1, Math.min(100, Number(limit) || 50));
  const params = [];
  const where = [];
  if (ticketId) {
    params.push(Number(ticketId));
    where.push(`cb.ticket_id = $${params.length}`);
  }
  if (assignedUserId) {
    params.push(Number(assignedUserId));
    where.push(`cb.assigned_user_id = $${params.length}`);
  }
  if (status) {
    params.push(String(status));
    where.push(`cb.status = $${params.length}`);
  }
  params.push(safeLimit);
  const r = await q(
    `SELECT cb.*, t.ticket_number, t.subject, u.full_name AS assigned_user_name
     FROM support_ticket_callback cb
     JOIN support_ticket t ON t.id = cb.ticket_id
     LEFT JOIN app_user u ON u.id = cb.assigned_user_id
     ${where.length ? `WHERE ${where.join(" AND ")}` : ""}
     ORDER BY cb.scheduled_at ASC
     LIMIT $${params.length}`,
    params
  );
  return r.rows;
}

export async function updateCallback({
  callbackId,
  status,
  notes = null,
  actorUserId = null,
}) {
  const completedAt = status === "completed" ? "NOW()" : "completed_at";
  const r = await q(
    `UPDATE support_ticket_callback
     SET status = $2,
         notes = COALESCE($3, notes),
         completed_at = ${completedAt},
         updated_at = NOW()
     WHERE id = $1
     RETURNING *`,
    [Number(callbackId), String(status), notes || null]
  );
  const row = r.rows[0] || null;
  if (row) {
    await q(
      `INSERT INTO support_ticket_event
         (ticket_id, actor_user_id, actor_role, event_type, metadata)
       VALUES ($1,$2,'agent','callback_updated',$3::jsonb)`,
      [
        Number(row.ticket_id),
        actorUserId ? Number(actorUserId) : null,
        json({ callbackId: row.id, status, notes }, {}),
      ]
    );
  }
  return row;
}

export async function getSupportKpiReport({
  from = null,
  to = null,
  team = null,
  limit = 20,
} = {}) {
  const params = [];
  const where = ["1=1"];
  if (from) {
    params.push(from);
    where.push(`t.created_at >= $${params.length}`);
  }
  if (to) {
    params.push(to);
    where.push(`t.created_at <= $${params.length}`);
  }
  if (team) {
    params.push(String(team));
    where.push(`COALESCE(t.team, 'general') = $${params.length}`);
  }
  const whereSql = where.join(" AND ");
  const summary = await q(
    `SELECT
       COUNT(*)::int AS total_tickets,
       COUNT(*) FILTER (WHERE t.status NOT IN ('RESOLVED','CLOSED'))::int AS open_tickets,
       COUNT(*) FILTER (WHERE t.assigned_user_id IS NULL AND t.status NOT IN ('RESOLVED','CLOSED'))::int AS unassigned_tickets,
       COUNT(*) FILTER (WHERE t.resolved_at IS NOT NULL)::int AS resolved_tickets,
       SUM(t.reopened_count)::int AS reopened_tickets,
       ROUND((AVG(EXTRACT(EPOCH FROM (t.first_response_at - t.created_at)) / 60.0)
         FILTER (WHERE t.first_response_at IS NOT NULL))::numeric, 1) AS avg_first_response_minutes,
       ROUND((AVG(EXTRACT(EPOCH FROM (t.resolved_at - t.created_at)) / 60.0)
         FILTER (WHERE t.resolved_at IS NOT NULL))::numeric, 1) AS avg_resolution_minutes,
       ROUND(AVG(t.rating)::numeric, 2) AS avg_csat,
       COUNT(*) FILTER (
         WHERE t.first_response_at IS NOT NULL
           AND t.sla_first_response_due_at IS NOT NULL
           AND t.first_response_at <= t.sla_first_response_due_at
       )::int AS first_response_sla_met,
       COUNT(*) FILTER (
         WHERE t.resolved_at IS NOT NULL
           AND t.sla_resolution_due_at IS NOT NULL
           AND t.resolved_at <= t.sla_resolution_due_at
       )::int AS resolution_sla_met,
       COUNT(*) FILTER (WHERE t.first_response_at IS NOT NULL AND t.sla_first_response_due_at IS NOT NULL)::int
         AS first_response_sla_measured,
       COUNT(*) FILTER (WHERE t.resolved_at IS NOT NULL AND t.sla_resolution_due_at IS NOT NULL)::int
         AS resolution_sla_measured
     FROM support_ticket t
     WHERE ${whereSql}`,
    params
  );
  params.push(Math.max(1, Math.min(100, Number(limit) || 20)));
  const agents = await q(
    `SELECT
       t.assigned_user_id,
       COALESCE(NULLIF(u.full_name, ''), NULLIF(u.username, ''), 'Support') AS agent_name,
       COUNT(*)::int AS total_assigned,
       COUNT(*) FILTER (WHERE t.status NOT IN ('RESOLVED','CLOSED'))::int AS open_count,
       COUNT(*) FILTER (WHERE t.resolved_at IS NOT NULL)::int AS resolved_count,
       ROUND((AVG(EXTRACT(EPOCH FROM (t.first_response_at - t.created_at)) / 60.0)
         FILTER (WHERE t.first_response_at IS NOT NULL))::numeric, 1) AS avg_first_response_minutes,
       ROUND((AVG(EXTRACT(EPOCH FROM (t.resolved_at - t.created_at)) / 60.0)
         FILTER (WHERE t.resolved_at IS NOT NULL))::numeric, 1) AS avg_resolution_minutes,
       ROUND(AVG(t.rating)::numeric, 2) AS avg_csat
     FROM support_ticket t
     LEFT JOIN app_user u ON u.id = t.assigned_user_id
     WHERE ${whereSql}
       AND t.assigned_user_id IS NOT NULL
     GROUP BY t.assigned_user_id, agent_name
     ORDER BY resolved_count DESC, open_count DESC, agent_name ASC
     LIMIT $${params.length}`,
    params
  );
  return {
    summary: summary.rows[0] || {},
    agents: agents.rows,
  };
}

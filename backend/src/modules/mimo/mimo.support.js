/**
 * Mimo as first-line support.
 *
 *  diagnose → looks at the user's real state (account, orders, taxi, tickets,
 *             saved addresses, push registration, app/device info) to spot
 *             what's wrong.
 *  escalate → opens a real support ticket (channel "mimo", urgent/high) with
 *             Mimo's summary as an internal note ("عمو مشكلة…"), and sends an
 *             emergency notification to admins so someone jumps in.
 *  learn    → when an admin resolves a Mimo ticket (or teaches him directly),
 *             Mimo turns the case into a reusable "playbook" in his knowledge.
 */

import { ORDER_STATUS_GUIDE } from "./mimo.appguide.js";
import { normalizeText, questionKey } from "./mimo.knowledge.js";

const clean = (v, max = 600) => String(v ?? "").replace(/\s+/g, " ").trim().slice(0, max);
const MIN = 60 * 1000;

// Same as ORDER_ACTIVE_STATUSES (admin monitoring) + waiting for the
// customer to confirm receipt.
export const ACTIVE_ORDER = new Set([
  "pending", "approved", "accepted_by_store", "preparing", "ready_for_delivery",
  "courier_requested", "courier_assigned", "on_the_way", "picked_up", "arrived",
  "delivered_by_courier",
]);

export const ESCALATION_DOMAINS = [
  "SHOPPING", "DELIVERY", "TAXI", "SERVICES", "REAL_ESTATE", "CARS",
  "JOBS", "COMMUNITY", "ACCOUNT", "PAYMENTS", "OTHER",
];

export function createDefaultSupportDeps() {
  const db = () => import("../../config/db.js");
  const support = () => import("../support/support.service.js");
  return {
    async account(userId) {
      const { q } = await db();
      const r = await q(
        `SELECT id, full_name, role, is_account_disabled, locked_until, failed_login_attempts, created_at
         FROM app_user WHERE id = $1`,
        [userId]
      );
      return r.rows[0] || null;
    },
    async recentOrders(userId) {
      const m = await import("../orders/orders.repo.js");
      return m.listCustomerOrders(userId, { paginate: true, limit: 5 });
    },
    async currentRide(userId) {
      try {
        const m = await import("../taxi/taxi.service.js");
        return await m.getCurrentRideForCustomer(userId);
      } catch {
        return null;
      }
    },
    async counts(userId) {
      const { q } = await db();
      const [addresses, tokens] = await Promise.all([
        q(`SELECT COUNT(*)::int AS n FROM customer_address WHERE user_id = $1`, [userId]).catch(() => ({ rows: [{ n: null }] })),
        q(`SELECT COUNT(*)::int AS n FROM user_push_token WHERE user_id = $1 AND is_active = TRUE`, [userId]).catch(() => ({ rows: [{ n: null }] })),
      ]);
      return { addresses: addresses.rows[0]?.n ?? null, pushTokens: tokens.rows[0]?.n ?? null };
    },
    async myTickets(userId) {
      const m = await support();
      const out = await m.listMyTickets({ userId, limit: 5, offset: 0 });
      return out?.items || [];
    },
    async lastAgentMessage(ticketId) {
      const { q } = await db();
      const r = await q(
        `SELECT body, created_at FROM support_ticket_message
         WHERE ticket_id = $1 AND is_internal = FALSE AND author_role NOT IN ('customer','user')
         ORDER BY created_at DESC LIMIT 1`,
        [ticketId]
      );
      return r.rows[0] || null;
    },
    async createTicket(input) {
      const m = await support();
      return m.createTicket(input);
    },
    async addMimoNote(ticketId, body) {
      const { q } = await db();
      await q(
        `INSERT INTO support_ticket_internal_note (ticket_id, author_user_id, author_role, body)
         VALUES ($1, NULL, 'mimo', $2)`,
        [ticketId, body]
      );
    },
    async admins() {
      const { q } = await db();
      const r = await q(
        `SELECT id FROM app_user
         WHERE (is_super_admin = TRUE OR role IN ('admin', 'deputy_admin'))
           AND COALESCE(is_account_disabled, FALSE) = FALSE
           AND COALESCE(account_deleted, FALSE) = FALSE
         ORDER BY id LIMIT 30`
      );
      return r.rows.map((x) => Number(x.id));
    },
    async notify(payload) {
      const m = await import("../notifications/notifications.repo.js");
      return m.createNotification(payload);
    },
    async realtime(userId, event, payload) {
      const m = await import("../../shared/realtime/realtime-gateway.js");
      return m.emitRealtimeToUser(userId, event, payload);
    },
    async ticketTranscript(ticketId) {
      const { q } = await db();
      const [t, msgs, notes] = await Promise.all([
        q(`SELECT id, ticket_number, domain, type, subject, description, channel, user_id, resolution_summary
           FROM support_ticket WHERE id = $1`, [ticketId]),
        q(`SELECT author_role, body FROM support_ticket_message WHERE ticket_id = $1 ORDER BY created_at ASC LIMIT 60`, [ticketId]),
        q(`SELECT author_role, body FROM support_ticket_internal_note WHERE ticket_id = $1 ORDER BY created_at ASC LIMIT 40`, [ticketId]),
      ]);
      return { ticket: t.rows[0] || null, messages: msgs.rows, notes: notes.rows };
    },
    async savePlaybook(row) {
      const { q } = await db();
      await q(
        `INSERT INTO mimo_knowledge (question, question_key, answer, topic, status, evidence, search_text)
         VALUES ($1, $2, $3, $4, 'verified', $5::jsonb, $6)
         ON CONFLICT (question_key) DO UPDATE
           SET answer = EXCLUDED.answer, status = 'verified', evidence = EXCLUDED.evidence,
               search_text = EXCLUDED.search_text, topic = EXCLUDED.topic, updated_at = NOW()`,
        [row.question, row.question_key, row.answer, row.topic, JSON.stringify(row.evidence || []), row.search_text]
      );
    },
  };
}

/** Snapshot of the user's real state, with problems Mimo can spot himself. */
export async function diagnose(deps, userId, { clientInfo = {}, area = null, now = Date.now() } = {}) {
  const [account, orders, ride, counts, tickets] = await Promise.all([
    deps.account(userId).catch(() => null),
    deps.recentOrders(userId).catch(() => []),
    deps.currentRide(userId).catch(() => null),
    deps.counts(userId).catch(() => ({})),
    deps.myTickets(userId).catch(() => []),
  ]);
  const findings = [];
  if (account?.is_account_disabled) findings.push("The account is DISABLED by admins — only support can help.");
  if (account?.locked_until && new Date(account.locked_until).getTime() > now) {
    findings.push(`Account temporarily locked after failed logins until ${account.locked_until}.`);
  }
  const activeOrders = orders.filter((o) => ACTIVE_ORDER.has(String(o.status)));
  for (const o of activeOrders) {
    const age = (now - new Date(o.created_at).getTime()) / MIN;
    const status = String(o.status);
    if (status === "pending" && age > 20) findings.push(`Order #${o.id} still waiting for the store after ${Math.round(age)} min.`);
    if (status === "courier_requested" && age > 35) findings.push(`Order #${o.id} still looking for a courier after ${Math.round(age)} min.`);
    if (["picked_up", "courier_assigned", "on_the_way", "arrived"].includes(status) && age > 90) findings.push(`Order #${o.id} is late (${Math.round(age)} min since ordering).`);
    if (status === "delivered_by_courier") findings.push(`Order #${o.id} marked delivered — the user should confirm receipt (or report if not received).`);
  }
  if (counts.addresses === 0) findings.push("No saved delivery address — checkout needs one.");
  if (counts.pushTokens === 0) findings.push("This device isn't registered for push notifications — log out/in and allow notifications.");
  if (clientInfo.online === false) findings.push("The app reports no internet connection.");
  return {
    area: area || null,
    account: account
      ? {
          disabled: account.is_account_disabled === true,
          locked: Boolean(account.locked_until && new Date(account.locked_until).getTime() > now),
        }
      : null,
    activeOrders: activeOrders.map((o) => ({
      id: Number(o.id),
      store: clean(o.merchant_name, 50),
      status: o.status,
      meaning: ORDER_STATUS_GUIDE[o.status] || o.status,
      minutesAgo: Math.round((now - new Date(o.created_at).getTime()) / MIN),
    })),
    lastOrders: orders.slice(0, 3).map((o) => ({ id: Number(o.id), status: o.status, meaning: ORDER_STATUS_GUIDE[o.status] || o.status })),
    taxi: ride ? { id: Number(ride.id), status: ride.status } : null,
    openTickets: tickets
      .filter((t) => !["RESOLVED", "CLOSED"].includes(String(t.status)))
      .map((t) => ({ id: Number(t.id), number: t.ticket_number, status: t.status, subject: clean(t.subject, 80) })),
    device: {
      platform: clean(clientInfo.platform, 20) || null,
      appVersion: clean(clientInfo.appVersion, 20) || null,
      online: clientInfo.online ?? null,
    },
    findings,
  };
}

/** Opens a Mimo ticket + emergency alert to the admins. */
export async function escalate(deps, userId, { domain, problem, stepsTried = [], urgency = "high", orderId = null, userName = null, transcript = "", attachments = [] }) {
  const dom = ESCALATION_DOMAINS.includes(String(domain || "").toUpperCase()) ? String(domain).toUpperCase() : "OTHER";
  const priority = urgency === "urgent" ? "urgent" : "high";
  const subject = `🤖 ميمو: ${clean(problem, 90)}`;
  const ticket = await deps.createTicket({
    userId,
    domain: dom,
    type: "PROBLEM",
    priority,
    subject,
    description: clean(problem, 1500),
    entityType: orderId ? "order" : null,
    entityId: orderId ? Number(orderId) : null,
    attachments: attachments.map((a) => ({ ...a, visibility: "customer" })),
    channel: "mimo",
  });
  const tried = stepsTried.filter(Boolean).map((s) => `• ${clean(s, 160)}`).join("\n");
  const note = [
    `عمو مشكلة 🙏 ${userName ? `${userName} ` : "المستخدم "}حائر ويحتاج مساعدتك.`,
    `المشكلة: ${clean(problem, 600)}`,
    tried ? `جربنا سوا:\n${tried}` : null,
    transcript ? `آخر المحادثة:\n${clean(transcript, 900)}` : null,
    attachments.length ? `📷 المستخدم أرفق ${attachments.length} صورة — موجودة بالتذكرة.` : null,
    "علّمني الحل، أو حلّها انت وأني أتعلم منك. لما تخلص دوس «تم الحل» 👀",
  ]
    .filter(Boolean)
    .join("\n\n");
  await deps.addMimoNote(ticket.id, note).catch(() => {});

  const admins = await deps.admins().catch(() => []);
  const recipients = new Set(admins);
  if (ticket.assigned_user_id) recipients.add(Number(ticket.assigned_user_id));
  const ticketRef = ticket.ticket_number || `#${Number(ticket.id)}`;
  const problemLine = clean(problem, 110);
  const who = clean(userName, 40) || "مستخدم";
  const whoEn = clean(userName, 40) || "A user";
  const urgentCopy = priority === "urgent";
  const copy = {
    title: urgentCopy ? `🚨 تذكرة دعم عاجلة: ${problemLine}` : `تذكرة دعم من ميمو: ${problemLine}`,
    body: `${ticketRef} — ${who} يحتاج مساعدة، ميمو ما گدر يحلها.`,
    textEn: {
      title: urgentCopy ? `🚨 Urgent support ticket: ${problemLine}` : `Support ticket from Mimo: ${problemLine}`,
      body: `${ticketRef} — ${whoEn} needs help that Mimo could not solve.`,
    },
  };
  const payload = {
    ticketId: Number(ticket.id),
    ticketNumber: ticket.ticket_number,
    requestId: Number(ticket.id),
    entityId: Number(ticket.id),
    targetEntity: "support_ticket",
    target: "admin_support_ticket",
    targetModule: "admin",
    roleScope: "admin",
    route: "support_ticket",
    source: "mimo",
    priority,
    requiresAction: urgentCopy,
    textEn: copy.textEn,
  };
  await Promise.allSettled(
    [...recipients].map((adminId) =>
      Promise.all([
        deps.notify({
          userId: adminId,
          type: "support.mimo.escalation",
          title: copy.title,
          body: copy.body,
          payload,
        }),
        deps.realtime(adminId, "support_ticket", { type: "support.mimo.escalation", ...payload }),
      ])
    )
  );
  return {
    ticketId: Number(ticket.id),
    ticketNumber: ticket.ticket_number,
    priority,
    notifiedAdmins: recipients.size,
    firstResponseDueAt: ticket.sla?.firstResponseDueAt || ticket.sla_first_response_due_at || null,
  };
}

/** The user's tickets with the latest reply from support (for Mimo to relay). */
export async function ticketsStatus(deps, userId) {
  const tickets = await deps.myTickets(userId);
  const out = [];
  for (const t of tickets.slice(0, 3)) {
    const reply = await deps.lastAgentMessage(t.id).catch(() => null);
    out.push({
      id: Number(t.id),
      number: t.ticket_number,
      status: t.status,
      subject: clean(t.subject, 90),
      fromMimo: t.channel === "mimo",
      lastSupportReply: reply ? clean(reply.body, 400) : null,
      resolution: t.resolution_summary ? clean(t.resolution_summary, 400) : null,
    });
  }
  return out;
}

const PLAYBOOK_SYSTEM = `You turn a resolved customer-support case from the Maslaki app into a reusable playbook for "Mimo" (the in-app assistant).
Return ONLY JSON: {"problem":"the general problem, phrased like a user would ask it (no names, phones, ids)","solution":"what fixes it: short steps Mimo can tell a user, in Iraqi Arabic, or what support must do","self_service":true|false,"topic":"orders|taxi|services|account|community|payments|app|other"}
self_service=false when only staff can fix it (then the solution says what to tell the user and that support handles it).`;

/** Learns a playbook from a resolved Mimo ticket (or an admin's direct teaching). */
export async function learnPlaybook(deps, llm, { ticketId, adminSolution = null }) {
  const { ticket, messages, notes } = await deps.ticketTranscript(ticketId);
  if (!ticket) return { learned: false, reason: "TICKET_NOT_FOUND" };
  const convo = [
    `Subject: ${ticket.subject}`,
    `Description: ${ticket.description || ""}`,
    ...messages.map((m) => `${m.author_role}: ${m.body}`),
    ...notes.filter((n) => n.author_role !== "mimo").map((n) => `[internal ${n.author_role}]: ${n.body}`),
    ticket.resolution_summary ? `Resolution: ${ticket.resolution_summary}` : null,
    adminSolution ? `Admin taught Mimo: ${adminSolution}` : null,
  ]
    .filter(Boolean)
    .join("\n")
    .slice(0, 9000);
  let parsed = null;
  try {
    const res = await llm.complete({
      kind: "utility",
      messages: [
        { role: "system", content: PLAYBOOK_SYSTEM },
        { role: "user", content: convo },
      ],
      maxTokens: 600,
      json: true,
    });
    const s = res.content;
    parsed = JSON.parse(s.slice(s.indexOf("{"), s.lastIndexOf("}") + 1));
  } catch {
    parsed = null;
  }
  if (!parsed?.problem || !parsed?.solution) return { learned: false, reason: "COULD_NOT_SUMMARIZE" };
  const question = clean(parsed.problem, 300);
  const answer = clean(
    parsed.self_service === false ? `${parsed.solution} (هاي يحلها فريق الدعم)` : parsed.solution,
    900
  );
  await deps.savePlaybook({
    question,
    question_key: `support:${questionKey(question)}`,
    answer,
    topic: `support:${clean(parsed.topic, 20) || "other"}`,
    evidence: [{ title: `ticket ${ticket.ticket_number || ticket.id}`, ticketId: Number(ticket.id) }],
    search_text: normalizeText(`${question} ${answer} ${ticket.subject}`),
  });
  return { learned: true, problem: question, solution: answer, selfService: parsed.self_service !== false };
}

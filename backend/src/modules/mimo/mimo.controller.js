import { env } from "../../config/env.js";
import { runMimoTurn } from "./mimo.agent.js";
import { buildDashboard, createDefaultDashboardDeps, estimateCost } from "./mimo.dashboard.js";
import { loadDirectory } from "./mimo.directory.js";
import { createMimoLlm, meterLlm } from "./mimo.llm.js";
import { createDefaultProactiveDeps, pickNudge } from "./mimo.proactive.js";
import { createDefaultKnowledgeDeps } from "./mimo.knowledge.js";
import { createDefaultMemoryDeps, loadMimoMemory } from "./mimo.memory.js";
import { createDefaultSupportDeps, learnPlaybook } from "./mimo.support.js";
import { createMimoToolbox } from "./mimo.tools.js";

let sharedLlm = null;
let memoryDeps = null;
function mem() {
  memoryDeps ??= createDefaultMemoryDeps();
  return memoryDeps;
}
let supportDeps = null;
function supportD() {
  supportDeps ??= createDefaultSupportDeps();
  return supportDeps;
}
let dashboardDeps = null;
function dashboard() {
  dashboardDeps ??= createDefaultDashboardDeps();
  return dashboardDeps;
}
let proactiveDeps = null;
function proactive() {
  proactiveDeps ??= createDefaultProactiveDeps();
  return proactiveDeps;
}
let knowledgeDeps = null;
function knowledge() {
  knowledgeDeps ??= createDefaultKnowledgeDeps();
  return knowledgeDeps;
}

/** Test seam. */
export function __setMimoMemoryDepsForTests(value) {
  memoryDeps = value;
}
function llm() {
  sharedLlm ??= createMimoLlm();
  return sharedLlm;
}

/** Test seam. */
export function __setMimoLlmForTests(value) {
  sharedLlm = value;
}

let firstNameOf = (userId) => loadFirstName(userId);
/** Test seam. */
export function __setMimoFirstNameForTests(fn) {
  firstNameOf = fn || ((userId) => loadFirstName(userId));
}

async function loadFirstName(userId) {
  try {
    const { findUserByIdWithAuthFields } = await import("../auth/auth.repo.js");
    const user = await findUserByIdWithAuthFields(userId);
    const full = String(user?.full_name || "").trim();
    return full ? full.split(/\s+/)[0] : null;
  } catch {
    return null;
  }
}

export function validateMimoChatBody(body = {}) {
  const errors = {};
  if (!Array.isArray(body.messages) || body.messages.length === 0) {
    errors.messages = "REQUIRED";
  } else if (body.messages.length > 40) {
    errors.messages = "TOO_MANY";
  } else {
    const last = body.messages[body.messages.length - 1];
    if (last?.role !== "user" || !String(last?.content || "").trim()) {
      errors.messages = "LAST_MUST_BE_USER";
    }
  }
  if (body.lang != null && !["ar", "en"].includes(body.lang)) errors.lang = "INVALID";
  if (body.summary != null && (typeof body.summary !== "string" || body.summary.length > 4000)) {
    errors.summary = "INVALID";
  }
  if (body.attachments != null && (!Array.isArray(body.attachments) || body.attachments.length > 4)) {
    errors.attachments = "INVALID";
  }
  return { ok: Object.keys(errors).length === 0, errors };
}

/** POST /api/mimo/feedback — 👍/👎 on a Mimo answer (learning signal). */
export async function feedback(req, res, next) {
  try {
    const body = req.body || {};
    const up = body.rating === "up";
    if (!["up", "down"].includes(body.rating)) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: { rating: "INVALID" } });
    }
    const memory = await loadMimoMemory(mem(), req.userId).catch(() => null);
    await mem().logEvent({
      userId: memory?.improveOn === false ? null : req.userId,
      kind: up ? "feedback_up" : "feedback_down",
      text: String(body.answer || "").slice(0, 600),
      detail: {
        question: String(body.question || "").slice(0, 400),
        reason: String(body.reason || "").slice(0, 200),
        refs: String(body.refs || "").slice(0, 300),
      },
    });
    return res.json({ ok: true });
  } catch (error) {
    return next(error);
  }
}

/** POST /api/mimo/cart-added — the user confirmed a Mimo cart proposal. */
export async function cartAdded(req, res, next) {
  try {
    const items = Array.isArray(req.body?.items) ? req.body.items.slice(0, 20) : [];
    const memory = await loadMimoMemory(mem(), req.userId).catch(() => null);
    await mem().logEvent({
      userId: memory?.improveOn === false ? null : req.userId,
      kind: "cart_added",
      text: null,
      detail: { items: items.map((i) => ({ productId: Number(i.productId) || null, quantity: Number(i.quantity) || 1 })) },
    });
    return res.json({ ok: true });
  } catch (error) {
    return next(error);
  }
}

/**
 * POST /api/mimo/admin/tickets/:ticketId/teach — an admin teaches Mimo how
 * this problem is solved (also learned automatically when the ticket resolves).
 */
export async function adminTeach(req, res, next) {
  try {
    const ticketId = Number(req.params.ticketId);
    const solution = String(req.body?.solution || "").trim().slice(0, 2000);
    if (!ticketId || solution.length < 5) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: { solution: "REQUIRED" } });
    }
    const client = llm();
    const out = await learnPlaybook(supportD(), client, { ticketId, adminSolution: solution });
    if (out.learned) {
      await supportD()
        .addMimoNote(ticketId, `تعلمت 🙏 من هسه إذا أحد گال "${out.problem}" راح أگله: ${out.solution}`)
        .catch(() => {});
    }
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

/** Called when any support ticket is resolved: Mimo learns from his own tickets. */
export function onSupportTicketResolved(ticket) {
  if (!ticket || ticket.channel !== "mimo") return;
  const client = llm();
  if (!client.enabled) return;
  learnPlaybook(supportD(), client, { ticketId: Number(ticket.id) })
    .then((out) => {
      if (out.learned) {
        return supportD().addMimoNote(
          Number(ticket.id),
          `شفت شلون انحلت 👀 وتعلمتها: إذا أحد گال "${out.problem}" — ${out.solution}`
        );
      }
      return null;
    })
    .catch(() => {});
}

/** GET /api/mimo/admin/insights — what people ask for that the app lacks. */
export async function insights(req, res, next) {
  try {
    const days = Math.max(1, Math.min(180, Number(req.query?.days) || 30));
    return res.json(await mem().insights({ days }));
  } catch (error) {
    return next(error);
  }
}

/** Hosts our uploads live on: this API and the public R2 bucket. */
export function uploadHosts(req) {
  const hosts = new Set();
  const host = req?.get?.("host");
  if (host) hosts.add(String(host).toLowerCase());
  try {
    if (env.cfR2PublicBaseUrl) hosts.add(new URL(env.cfR2PublicBaseUrl).host.toLowerCase());
  } catch {
    // ignore a malformed base URL
  }
  return hosts;
}

function isOwnUpload(fileUrl, hosts) {
  if (/^\/uploads\/[^\s]+$/i.test(fileUrl)) return true;
  try {
    const u = new URL(fileUrl);
    return /^https?:$/.test(u.protocol) && hosts.has(u.host.toLowerCase());
  } catch {
    return false;
  }
}

/**
 * Only our own uploaded files (from /api/support/attachments) are accepted —
 * never an arbitrary external link (it would land in a ticket admins open).
 */
export function safeAttachments(list, hosts = new Set()) {
  if (!Array.isArray(list)) return [];
  return list
    .slice(0, 4)
    .filter((a) => a && typeof a.fileUrl === "string" && isOwnUpload(a.fileUrl, hosts))
    .filter((a) => !a.mimeType || /^image\//i.test(String(a.mimeType)))
    .map((a) => ({
      fileUrl: String(a.fileUrl).slice(0, 600),
      storageKey: a.storageKey ? String(a.storageKey).slice(0, 300) : null,
      fileName: a.fileName ? String(a.fileName).slice(0, 200) : null,
      mimeType: a.mimeType ? String(a.mimeType).slice(0, 60) : "image/jpeg",
      fileSizeBytes: Number(a.fileSizeBytes) || null,
    }));
}

/** GET /api/mimo/admin/dashboard?days=30 */
export async function adminDashboard(req, res, next) {
  try {
    return res.json(await buildDashboard(dashboard(), { days: req.query?.days }));
  } catch (error) {
    return next(error);
  }
}

/** GET /api/mimo/admin/knowledge?status=&q=&offset= */
export async function adminKnowledge(req, res, next) {
  try {
    const status = ["verified", "community", "rejected"].includes(req.query?.status) ? req.query.status : null;
    const q = typeof req.query?.q === "string" && req.query.q.trim() ? req.query.q.trim().slice(0, 80) : null;
    const offset = Math.max(0, Number(req.query?.offset) || 0);
    return res.json({ items: await dashboard().knowledge({ status, q, limit: 50, offset }) });
  } catch (error) {
    return next(error);
  }
}

/** PATCH /api/mimo/admin/knowledge/:id {status?, answer?} */
export async function adminUpdateKnowledge(req, res, next) {
  try {
    const id = Number(req.params.id);
    const status = req.body?.status;
    const answer = typeof req.body?.answer === "string" ? req.body.answer.trim().slice(0, 900) : null;
    if (!id || (status != null && !["verified", "community", "rejected"].includes(status)) || (answer != null && answer.length < 2)) {
      return res.status(400).json({ message: "VALIDATION_ERROR" });
    }
    const row = await dashboard().updateKnowledge(id, { status: status || null, answer });
    if (!row) return res.status(404).json({ message: "NOT_FOUND" });
    return res.json({ item: row });
  } catch (error) {
    return next(error);
  }
}

/** DELETE /api/mimo/admin/knowledge/:id */
export async function adminDeleteKnowledge(req, res, next) {
  try {
    const ok = await dashboard().deleteKnowledge(Number(req.params.id));
    return ok ? res.json({ ok: true }) : res.status(404).json({ message: "NOT_FOUND" });
  } catch (error) {
    return next(error);
  }
}

/** GET /api/mimo/directory — every store & service, for Mimo's instant offline brain. */
export async function directory(req, res, next) {
  try {
    res.setHeader("Cache-Control", "private, max-age=60");
    return res.json(await loadDirectory());
  } catch (error) {
    return next(error);
  }
}

/** GET /api/mimo/nudge?lang=ar — today's proactive suggestion (or null). */
export async function nudge(req, res, next) {
  try {
    const lang = req.query?.lang === "en" ? "en" : "ar";
    return res.json({ nudge: await pickNudge(proactive(), req.userId, { lang }) });
  } catch (error) {
    return next(error);
  }
}

/** POST /api/mimo/proactive {nudgeId, event: shown|tapped} */
export async function proactiveEvent(req, res, next) {
  try {
    const event = req.body?.event;
    if (!["shown", "tapped"].includes(event)) return res.status(400).json({ message: "VALIDATION_ERROR" });
    await mem().logEvent({
      userId: req.userId,
      kind: event === "shown" ? "proactive_shown" : "proactive_tapped",
      text: String(req.body?.nudgeId || "").slice(0, 120),
      detail: { kind: String(req.body?.kind || "").slice(0, 30) },
    });
    return res.json({ ok: true });
  } catch (error) {
    return next(error);
  }
}

const FALLBACK_SECTIONS = [
  ["shopping", "التسوق", "Shopping"],
  ["taxi", "التكسي", "Taxi"],
  ["services", "الخدمات", "Services"],
  ["pharmacy", "الصيدليات", "Pharmacy"],
  ["offers", "العروض", "Offers"],
  ["orders", "طلباتي", "My orders"],
];

/**
 * Offline brain: used when the LLM is unavailable (no credit, disabled,
 * provider down). It offers buttons that OPEN the sections directly — quick
 * replies would just ask the same unavailable brain again and loop.
 */
export function fallbackReply(lang = "ar") {
  const ar = lang !== "en";
  return {
    text: ar
      ? "هسه دماغي شوية تعبان 😅 ما أگدر أجاوب على الأسئلة بهاللحظة، بس أگدر أوديك مباشرة للي تريده:"
      : "My brain is resting right now 😅 I can't answer questions at the moment, but I can take you straight there:",
    ui: [
      ...FALLBACK_SECTIONS.map(([section, arLabel, enLabel]) => ({
        type: "open_section",
        section,
        label: ar ? arLabel : enLabel,
      })),
      { type: "mood", mood: "thinking" },
    ],
  };
}

/**
 * POST /api/mimo/chat — body {messages:[{role,content}], lang, context}.
 * Streams Server-Sent Events: status, delta, ui, done (and error).
 */
export async function chat(req, res, next) {
  const body = req.body || {};
  const v = validateMimoChatBody(body);
  if (!v.ok) {
    return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
  }
  const lang = body.lang === "en" ? "en" : "ar";
  const context = body.context && typeof body.context === "object" ? body.context : {};

  res.status(200);
  res.setHeader("Content-Type", "text/event-stream; charset=utf-8");
  res.setHeader("Cache-Control", "no-cache, no-transform");
  res.setHeader("Connection", "keep-alive");
  res.setHeader("X-Accel-Buffering", "no");
  res.flushHeaders?.();

  const abort = new AbortController();
  // `req` has already emitted "close" once its body was read, so watch the
  // response: it closes when the user stops/leaves before Mimo finished.
  res.on("close", () => {
    if (!res.writableFinished) abort.abort();
  });
  const emit = (event, data) => {
    if (res.writableEnded) return;
    res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
  };
  const heartbeat = setInterval(() => {
    if (!res.writableEnded) res.write(": ping\n\n");
  }, 15000);

  try {
    const base = llm();
    if (!base.enabled) throw Object.assign(new Error("MIMO_LLM_DISABLED"), { code: "MIMO_LLM_DISABLED" });
    const meter = meterLlm(base);
    const client = meter.llm;
    const started = Date.now();
    const attachments = safeAttachments(body.attachments, uploadHosts(req));
    const [firstName, memory] = await Promise.all([
      firstNameOf(req.userId),
      loadMimoMemory(mem(), req.userId).catch(() => null),
    ]);
    await runMimoTurn({
      llm: client,
      toolbox: createMimoToolbox({
        userId: req.userId,
        lang,
        memoryDeps: mem(),
        memory,
        llm: client,
        knowledgeDeps: knowledge(),
        signal: abort.signal,
        supportDeps: supportD(),
        clientInfo: context.client && typeof context.client === "object" ? context.client : {},
        userName: firstName,
        attachments,
      }),
      attachments,
      summary: typeof body.summary === "string" ? body.summary : "",
      memory,
      memoryDeps: mem(),
      userId: req.userId,
      history: body.messages,
      firstName,
      lang,
      context,
      emit,
      signal: abort.signal,
      onFinish: (turn) => {
        const input = meter.calls.reduce((a, c) => a + (c.inputTokens || 0), 0);
        const output = meter.calls.reduce((a, c) => a + (c.outputTokens || 0), 0);
        mem()
          .logEvent({
            userId: memory?.improveOn === false ? null : req.userId,
            kind: "usage",
            text: null,
            detail: {
              ms: Date.now() - started,
              steps: turn.steps,
              tools: turn.tools || [],
              models: [...new Set(meter.calls.map((c) => c.model))],
              calls: meter.calls.length,
              webSearches: meter.calls.filter((c) => c.webSearch).length,
              inputTokens: input,
              outputTokens: output,
              costUsd: estimateCost(meter.calls),
            },
          })
          .catch(() => {});
      },
    });
  } catch (error) {
    if (!abort.signal.aborted) {
      // Visible in the server logs (e.g. MIMO_LLM_NO_CREDIT = OpenAI credit ran out).
      console.warn(`[mimo] fallback reply: ${error?.code || error?.message || "MIMO_FAILED"}`);
      const fb = fallbackReply(lang);
      emit("delta", { text: fb.text });
      for (const event of fb.ui) emit("ui", event);
      emit("done", { text: fb.text, fallback: true, reason: error?.code || "MIMO_FAILED" });
    }
  } finally {
    clearInterval(heartbeat);
    if (!res.writableEnded) res.end();
  }
  return undefined;
}

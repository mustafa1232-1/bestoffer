/**
 * Data for the admin "Mimo" dashboard: usage, estimated cost, quality
 * (👍/👎 and the worst answers), what people want that the app lacks,
 * what Mimo learned (with approve/reject/edit), and Mimo's support tickets.
 * Pure SQL on our own tables — no AI calls.
 */

import { normalizeText } from "./mimo.knowledge.js";

/**
 * Approximate USD per 1M tokens. Override with MIMO_PRICES (JSON), e.g.
 * {"gpt-4.1":{"in":2,"out":8}}. Shown in the dashboard as an ESTIMATE.
 */
const DEFAULT_PRICES = {
  "gpt-4.1": { in: 2.0, out: 8.0 },
  "gpt-4.1-mini": { in: 0.4, out: 1.6 },
  "gpt-4.1-nano": { in: 0.1, out: 0.4 },
  "gpt-5.5": { in: 1.25, out: 10.0 },
  "gpt-5.4": { in: 1.25, out: 10.0 },
  "gpt-5.4-mini": { in: 0.25, out: 2.0 },
  "gpt-5-search-api": { in: 1.25, out: 10.0 },
  o3: { in: 2.0, out: 8.0 },
};
const DEFAULT_WEB_SEARCH_USD = 0.01;

export function priceTable(env = process.env) {
  let custom = {};
  try {
    custom = env.MIMO_PRICES ? JSON.parse(env.MIMO_PRICES) : {};
  } catch {
    custom = {};
  }
  return {
    models: { ...DEFAULT_PRICES, ...custom },
    webSearchUsd: Number(env.MIMO_WEB_SEARCH_USD) || DEFAULT_WEB_SEARCH_USD,
  };
}

/** Estimated USD cost of one reply's metered calls. */
export function estimateCost(calls = [], prices = priceTable()) {
  let usd = 0;
  for (const c of calls) {
    // Longest matching name wins ("gpt-5.4-mini" must not price as "gpt-5.4").
    const key =
      Object.keys(prices.models)
        .filter((m) => String(c.model || "").startsWith(m))
        .sort((x, y) => y.length - x.length)[0] || null;
    const p = key ? prices.models[key] : { in: 2, out: 8 };
    usd += ((Number(c.inputTokens) || 0) * p.in + (Number(c.outputTokens) || 0) * p.out) / 1e6;
    if (c.webSearch) usd += prices.webSearchUsd;
  }
  return Math.round(usd * 1e6) / 1e6;
}

export function createDefaultDashboardDeps() {
  const db = () => import("../../config/db.js");
  const run = async (sql, params = []) => (await (await db()).q(sql, params)).rows;
  return {
    async kpis(days) {
      const since = `NOW() - ($1::int * INTERVAL '1 day')`;
      const [q, fb, usage, tickets, know, carts, pro] = await Promise.all([
        run(`SELECT COUNT(*)::int AS questions, COUNT(DISTINCT user_id)::int AS users
             FROM mimo_learning_event WHERE kind = 'question' AND created_at > ${since}`, [days]),
        run(`SELECT kind, COUNT(*)::int AS n FROM mimo_learning_event
             WHERE kind IN ('feedback_up','feedback_down') AND created_at > ${since} GROUP BY kind`, [days]),
        run(`SELECT COUNT(*)::int AS replies,
                    COALESCE(SUM((detail->>'costUsd')::numeric), 0)::float AS cost_usd,
                    COALESCE(AVG((detail->>'ms')::numeric), 0)::float AS avg_ms,
                    COALESCE(SUM((detail->>'inputTokens')::numeric), 0)::bigint AS input_tokens,
                    COALESCE(SUM((detail->>'outputTokens')::numeric), 0)::bigint AS output_tokens
             FROM mimo_learning_event WHERE kind = 'usage' AND created_at > ${since}`, [days]),
        run(`SELECT status, COUNT(*)::int AS n FROM support_ticket
             WHERE channel = 'mimo' AND created_at > ${since} GROUP BY status`, [days]),
        run(`SELECT status, COUNT(*)::int AS n,
                    COUNT(*) FILTER (WHERE question_key LIKE 'support:%')::int AS playbooks
             FROM mimo_knowledge GROUP BY status`),
        run(`SELECT COUNT(*)::int AS n FROM mimo_learning_event WHERE kind = 'cart_added' AND created_at > ${since}`, [days]),
        run(`SELECT kind, COUNT(*)::int AS n FROM mimo_learning_event
             WHERE kind IN ('proactive_shown','proactive_tapped') AND created_at > ${since} GROUP BY kind`, [days]),
      ]);
      return { q: q[0], fb, usage: usage[0], tickets, know, carts: carts[0]?.n || 0, pro };
    },
    async daily(days) {
      return run(
        `SELECT to_char(date_trunc('day', created_at AT TIME ZONE 'Asia/Baghdad'), 'YYYY-MM-DD') AS day,
                COUNT(*) FILTER (WHERE kind = 'question')::int AS questions,
                COUNT(DISTINCT user_id) FILTER (WHERE kind = 'question')::int AS users,
                COALESCE(SUM((detail->>'costUsd')::numeric) FILTER (WHERE kind = 'usage'), 0)::float AS cost_usd
         FROM mimo_learning_event
         WHERE created_at > NOW() - ($1::int * INTERVAL '1 day')
         GROUP BY 1 ORDER BY 1`,
        [days]
      );
    },
    async tools(days) {
      return run(
        `SELECT t AS tool, COUNT(*)::int AS n
         FROM mimo_learning_event, jsonb_array_elements_text(COALESCE(detail->'tools', '[]'::jsonb)) AS t
         WHERE kind = 'usage' AND created_at > NOW() - ($1::int * INTERVAL '1 day')
         GROUP BY t ORDER BY n DESC LIMIT 20`,
        [days]
      );
    },
    async badAnswers(days, limit = 30) {
      return run(
        `SELECT id, text AS answer, detail->>'question' AS question, detail->>'reason' AS reason, created_at
         FROM mimo_learning_event
         WHERE kind = 'feedback_down' AND created_at > NOW() - ($1::int * INTERVAL '1 day')
         ORDER BY created_at DESC LIMIT $2`,
        [days, limit]
      );
    },
    async demand(days) {
      const [unmet, misses] = await Promise.all([
        run(`SELECT LOWER(text) AS text, COUNT(*)::int AS times, MAX(created_at) AS last_at FROM mimo_learning_event
             WHERE kind = 'unmet_need' AND text IS NOT NULL AND created_at > NOW() - ($1::int * INTERVAL '1 day')
             GROUP BY 1 ORDER BY 2 DESC LIMIT 30`, [days]),
        run(`SELECT LOWER(text) AS text, COUNT(*)::int AS times FROM mimo_learning_event
             WHERE kind = 'search_miss' AND text IS NOT NULL AND created_at > NOW() - ($1::int * INTERVAL '1 day')
             GROUP BY 1 ORDER BY 2 DESC LIMIT 30`, [days]),
      ]);
      const synonyms = await run(`SELECT term, alias, hits FROM mimo_learned_synonym ORDER BY hits DESC LIMIT 30`);
      return { unmet, misses, synonyms };
    },
    async knowledge({ status = null, q = null, limit = 50, offset = 0 }) {
      return run(
        `SELECT id, question, answer, topic, status, confirmations, disputes, uses, evidence, created_at, updated_at,
                (question_key LIKE 'support:%') AS playbook
         FROM mimo_knowledge
         WHERE ($1::text IS NULL OR status = $1)
           AND ($2::text IS NULL OR question ILIKE '%' || $2 || '%' OR answer ILIKE '%' || $2 || '%')
         ORDER BY updated_at DESC LIMIT $3 OFFSET $4`,
        [status, q, limit, offset]
      );
    },
    async updateKnowledge(id, { status, answer }) {
      const current = answer == null ? null : (await run(`SELECT question FROM mimo_knowledge WHERE id = $1`, [id]))[0];
      const searchText = current ? normalizeText(`${current.question} ${answer}`) : null;
      const rows = await run(
        `UPDATE mimo_knowledge
         SET status = COALESCE($2, status), answer = COALESCE($3, answer),
             search_text = CASE WHEN $3::text IS NULL THEN search_text ELSE $4 END,
             updated_at = NOW()
         WHERE id = $1 RETURNING id, status, answer`,
        [id, status, answer, searchText]
      );
      return rows[0] || null;
    },
    async deleteKnowledge(id) {
      const rows = await run(`DELETE FROM mimo_knowledge WHERE id = $1 RETURNING id`, [id]);
      return rows.length > 0;
    },
    async tickets(limit = 30) {
      return run(
        `SELECT id, ticket_number, status, priority, domain, subject, created_at, resolved_at
         FROM support_ticket WHERE channel = 'mimo' ORDER BY created_at DESC LIMIT $1`,
        [limit]
      );
    },
  };
}

const byKind = (rows, key = "kind") => Object.fromEntries((rows || []).map((r) => [r[key], Number(r.n) || 0]));

/** Everything the dashboard's overview needs, in one response. */
export async function buildDashboard(deps, { days = 30 } = {}) {
  const d = Math.max(1, Math.min(180, Number(days) || 30));
  const [k, daily, tools, bad, demand, tickets] = await Promise.all([
    deps.kpis(d),
    deps.daily(d),
    deps.tools(d),
    deps.badAnswers(d, 15),
    deps.demand(d),
    deps.tickets(15),
  ]);
  const fb = byKind(k.fb);
  const up = fb.feedback_up || 0;
  const down = fb.feedback_down || 0;
  const tix = byKind(k.tickets, "status");
  const ticketTotal = Object.values(tix).reduce((a, b) => a + b, 0);
  const solved = (tix.RESOLVED || 0) + (tix.CLOSED || 0);
  const knowStatus = byKind(k.know, "status");
  const playbooks = (k.know || []).reduce((a, r) => a + (Number(r.playbooks) || 0), 0);
  const pro = byKind(k.pro);
  const questions = Number(k.q?.questions) || 0;
  const costUsd = Number(k.usage?.cost_usd) || 0;
  return {
    days: d,
    kpis: {
      questions,
      users: Number(k.q?.users) || 0,
      replies: Number(k.usage?.replies) || 0,
      avgReplySeconds: Math.round((Number(k.usage?.avg_ms) || 0) / 100) / 10,
      estimatedCostUsd: Math.round(costUsd * 100) / 100,
      costPerQuestionUsd: questions ? Math.round((costUsd / questions) * 10000) / 10000 : 0,
      tokens: { input: Number(k.usage?.input_tokens) || 0, output: Number(k.usage?.output_tokens) || 0 },
      feedbackUp: up,
      feedbackDown: down,
      satisfaction: up + down ? Math.round((up / (up + down)) * 100) : null,
      cartAdds: k.carts,
      escalations: ticketTotal,
      escalationsSolved: solved,
      escalationsOpen: ticketTotal - solved,
      learnedVerified: knowStatus.verified || 0,
      learnedCommunity: knowStatus.community || 0,
      learnedRejected: knowStatus.rejected || 0,
      playbooks,
      nudgesShown: pro.proactive_shown || 0,
      nudgesTapped: pro.proactive_tapped || 0,
    },
    daily,
    tools,
    badAnswers: bad,
    demand,
    tickets,
    costNote: "تقدير تقريبي حسب أسعار تقريبية لكل نموذج (قابلة للتعديل من MIMO_PRICES).",
  };
}

/**
 * Client for OpenAI-compatible Chat Completions used by Mimo:
 *   - chat():     streaming answer with tool calling (the main brain)
 *   - complete(): one-shot calls for helpers — deep reasoning, web search,
 *                 fact verification, conversation summaries.
 * Handles both classic models (gpt-4.1) and reasoning families (gpt-5.x, o3)
 * which take different parameters, and falls back to the next model.
 */

const DEFAULT_BASE_URL = "https://api.openai.com/v1";

function clampInt(value, min, max, fallback) {
  const n = Number.parseInt(String(value ?? ""), 10);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(min, Math.min(max, n));
}

const list = (...v) => [...new Set(v.map((x) => String(x || "").trim()).filter(Boolean))];

export function mimoLlmConfigFromEnv(env = process.env) {
  return {
    apiKey: String(env.MIMO_API_KEY || env.OPENAI_API_KEY || "").trim(),
    baseUrl: String(env.MIMO_BASE_URL || env.OPENAI_BASE_URL || DEFAULT_BASE_URL)
      .trim()
      .replace(/\/+$/, ""),
    // Main conversational brain (tool calling + streaming).
    models: list(env.MIMO_MODEL || "gpt-4.1", env.MIMO_FALLBACK_MODEL || env.OPENAI_MODEL || "gpt-4.1-mini"),
    // Hard logic / math / multi-step reasoning.
    deepModels: list(env.MIMO_DEEP_MODEL || "gpt-5.5", "o3", "gpt-4.1"),
    // Live web search via the Responses API web_search tool (high rate
    // limits); the dedicated search model is only a last resort (45k TPM).
    searchModels: list(env.MIMO_SEARCH_MODEL || "gpt-5.4-mini", "gpt-4.1", "gpt-5-search-api"),
    // Cheap helpers: summaries, fact judging.
    utilityModels: list(env.MIMO_UTILITY_MODEL || "gpt-5.4-mini", "gpt-4.1-mini"),
    reasoningEffort: String(env.MIMO_REASONING_EFFORT || "low"),
    timeoutMs: clampInt(env.MIMO_TIMEOUT_MS, 5000, 120000, 60000),
    temperature: Number.isFinite(Number(env.MIMO_TEMPERATURE)) ? Number(env.MIMO_TEMPERATURE) : 0.45,
  };
}

/** gpt-5.x / o-series: no temperature, max_completion_tokens, reasoning_effort. */
export function isReasoningFamily(model) {
  return /^(gpt-5|o\d)/i.test(String(model || ""));
}

function isSearchModel(model) {
  return /search/i.test(String(model || ""));
}

export function buildRequestBody(model, { messages, tools, toolChoice, maxTokens, temperature, reasoningEffort, stream, responseFormat }) {
  const body = {
    model,
    messages,
    ...(stream ? { stream: true, stream_options: { include_usage: true } } : {}),
  };
  if (isSearchModel(model)) {
    body.web_search_options = { search_context_size: "medium" };
    body.max_completion_tokens = maxTokens;
    return body; // search models reject temperature/tools
  }
  if (isReasoningFamily(model)) {
    body.max_completion_tokens = maxTokens;
    if (!/chat/i.test(model) && reasoningEffort) body.reasoning_effort = reasoningEffort;
  } else {
    body.max_tokens = maxTokens;
    if (temperature != null) body.temperature = temperature;
  }
  if (tools?.length) {
    body.tools = tools;
    body.tool_choice = toolChoice || "auto";
    body.parallel_tool_calls = true;
  }
  if (responseFormat) body.response_format = responseFormat;
  return body;
}

/** 429 because the account ran out of credit (not a temporary rate limit). */
async function isOutOfCredit(res) {
  try {
    const j = await res.clone().json();
    return ["insufficient_quota", "credit_balance_exhausted", "billing_hard_limit_reached"].includes(j?.error?.code);
  } catch {
    return false;
  }
}

/** Parses an OpenAI SSE body into JSON chunks. */
async function* readSseJson(body) {
  const decoder = new TextDecoder();
  let buffer = "";
  for await (const chunk of body) {
    buffer += typeof chunk === "string" ? chunk : decoder.decode(chunk, { stream: true });
    let idx;
    while ((idx = buffer.indexOf("\n")) >= 0) {
      const line = buffer.slice(0, idx).trim();
      buffer = buffer.slice(idx + 1);
      if (!line.startsWith("data:")) continue;
      const data = line.slice(5).trim();
      if (!data || data === "[DONE]") continue;
      try {
        yield JSON.parse(data);
      } catch {
        // Ignore keep-alives / partial garbage.
      }
    }
  }
}

/** Token counts from chat (prompt/completion) or responses (input/output). */
export function normalizeUsage(u) {
  if (!u) return { inputTokens: 0, outputTokens: 0 };
  return {
    inputTokens: Number(u.prompt_tokens ?? u.input_tokens ?? 0) || 0,
    outputTokens: Number(u.completion_tokens ?? u.output_tokens ?? 0) || 0,
  };
}

/**
 * Wraps an llm so every call made during one Mimo reply is metered (for the
 * admin dashboard's usage & estimated-cost view).
 */
export function meterLlm(llm) {
  const calls = [];
  const record = (u) => calls.push(u);
  return {
    calls,
    llm: {
      ...llm,
      chat: (args) => llm.chat({ ...args, onUsage: record }),
      complete: (args) => llm.complete({ ...args, onUsage: record }),
    },
  };
}

export function createMimoLlm(config = mimoLlmConfigFromEnv(), { fetchImpl = fetch } = {}) {
  const enabled = Boolean(config.apiKey) && config.models.length > 0;

  async function post(body, opts = {}) {
    // Retry the SAME model on rate limits / transient errors before falling back.
    for (let attempt = 0; ; attempt += 1) {
      const res = await postOnce(body, opts);
      if (res.status === 429 && (await isOutOfCredit(res))) {
        // No balance left: retrying or switching models can't help.
        const err = new Error("MIMO_LLM_NO_CREDIT");
        err.code = "MIMO_LLM_NO_CREDIT";
        throw err;
      }
      const transient = res.status === 429 || res.status >= 500;
      if (!transient || attempt >= 2 || opts.signal?.aborted) return res;
      const retryAfter = Number(res.headers?.get?.("retry-after"));
      const waitMs = Number.isFinite(retryAfter) && retryAfter > 0 ? Math.min(retryAfter * 1000, 8000) : 800 * (attempt + 1) ** 2;
      try {
        await res.body?.cancel?.();
      } catch {
        // ignore
      }
      await new Promise((r) => setTimeout(r, waitMs));
    }
  }

  async function postOnce(body, { signal, timeoutMs = config.timeoutMs, path = "/chat/completions" } = {}) {
    const timeout = new AbortController();
    const timer = setTimeout(() => timeout.abort(), timeoutMs);
    const onOuterAbort = () => timeout.abort();
    signal?.addEventListener?.("abort", onOuterAbort, { once: true });
    try {
      return await fetchImpl(`${config.baseUrl}${path}`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${config.apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
        signal: timeout.signal,
      });
    } finally {
      clearTimeout(timer);
      signal?.removeEventListener?.("abort", onOuterAbort);
    }
  }

  function assertEnabled() {
    if (!enabled) {
      const err = new Error("MIMO_LLM_DISABLED");
      err.code = "MIMO_LLM_DISABLED";
      throw err;
    }
  }

  /**
   * Streaming main brain.
   * @returns {Promise<{content: string, toolCalls: Array<{id,name,arguments}>, model: string}>}
   */
  async function chat({ messages, tools, onDelta, onToolDelta, signal, maxTokens = 1400, toolChoice = "auto", onUsage }) {
    assertEnabled();
    let lastError = null;
    for (const model of config.models) {
      try {
        const response = await post(
          buildRequestBody(model, {
            messages,
            tools,
            toolChoice,
            maxTokens: isReasoningFamily(model) ? maxTokens + 2000 : maxTokens,
            temperature: config.temperature,
            reasoningEffort: config.reasoningEffort,
            stream: true,
          }),
          { signal }
        );
        if (!response.ok || !response.body) {
          lastError = new Error(`MIMO_LLM_HTTP_${response.status}`);
          continue;
        }
        let content = "";
        let usage = null;
        const calls = new Map();
        for await (const json of readSseJson(response.body)) {
          if (json?.usage) usage = json.usage;
          const delta = json?.choices?.[0]?.delta;
          if (!delta) continue;
          if (typeof delta.content === "string" && delta.content) {
            content += delta.content;
            onDelta?.(delta.content);
          }
          for (const tc of delta.tool_calls || []) {
            const key = tc.index ?? 0;
            const prev = calls.get(key) || { id: "", name: "", arguments: "" };
            if (tc.id) prev.id = tc.id;
            if (tc.function?.name) prev.name += tc.function.name;
            if (tc.function?.arguments) prev.arguments += tc.function.arguments;
            calls.set(key, prev);
            if (tc.function?.arguments) onToolDelta?.(key, prev.name, tc.function.arguments);
          }
        }
        const result = { content, toolCalls: [...calls.values()].filter((c) => c.name), model, usage: normalizeUsage(usage) };
        onUsage?.({ model, ...result.usage, kind: "chat" });
        return result;
      } catch (error) {
        if (signal?.aborted || error?.code === "MIMO_LLM_NO_CREDIT") throw error;
        lastError = error;
      }
    }
    throw lastError || new Error("MIMO_LLM_FAILED");
  }

  /** Web search through the Responses API `web_search` tool. */
  async function searchWithResponses(model, { messages, maxTokens, signal, timeoutMs, onUsage }) {
    const instructions = messages.filter((m) => m.role === "system").map((m) => m.content).join("\n\n");
    const input = messages
      .filter((m) => m.role !== "system")
      .map((m) => m.content)
      .join("\n\n");
    const body = {
      model,
      tools: [{ type: "web_search" }],
      instructions: instructions || undefined,
      input,
      max_output_tokens: isReasoningFamily(model) ? maxTokens + 3000 : maxTokens,
      ...(isReasoningFamily(model) ? { reasoning: { effort: "low" } } : { temperature: 0.2 }),
    };
    const response = await post(body, { signal, timeoutMs, path: "/responses" });
    if (!response.ok) throw new Error(`MIMO_LLM_HTTP_${response.status}`);
    const data = await response.json();
    let text = "";
    const sources = [];
    for (const item of data?.output || []) {
      if (item.type !== "message") continue;
      for (const c of item.content || []) {
        if (typeof c.text === "string") text += c.text;
        for (const a of c.annotations || []) {
          if (a?.type === "url_citation" && a.url && !sources.some((s) => s.url === a.url)) {
            sources.push({ title: String(a.title || "").slice(0, 120), url: a.url });
          }
        }
      }
    }
    text = text.trim();
    if (!text) throw new Error("MIMO_LLM_EMPTY");
    const usage = normalizeUsage(data?.usage);
    onUsage?.({ model, ...usage, kind: "search", webSearch: true });
    return { content: text, sources: sources.slice(0, 6), model, usage };
  }

  /**
   * One-shot helper call. `kind` picks the model family:
   *   "deep" (reasoning), "search" (web), "utility" (cheap helpers).
   * @returns {Promise<{content: string, sources: Array<{title,url}>, model: string}>}
   */
  async function complete({ kind = "utility", messages, maxTokens = 900, reasoningEffort, json = false, signal, timeoutMs, onUsage }) {
    assertEnabled();
    const models =
      kind === "deep" ? config.deepModels : kind === "search" ? config.searchModels : config.utilityModels;
    let lastError = null;
    for (const model of models) {
      if (kind === "search" && !isSearchModel(model)) {
        try {
          return await searchWithResponses(model, {
            messages,
            maxTokens,
            signal,
            timeoutMs: timeoutMs || config.timeoutMs,
            onUsage,
          });
        } catch (error) {
          if (signal?.aborted || error?.code === "MIMO_LLM_NO_CREDIT") throw error;
          lastError = error;
          continue;
        }
      }
      try {
        const response = await post(
          buildRequestBody(model, {
            messages,
            maxTokens: isReasoningFamily(model) && !isSearchModel(model) ? maxTokens + 4000 : maxTokens,
            temperature: 0.2,
            reasoningEffort: reasoningEffort || (kind === "deep" ? "high" : "none"),
            responseFormat: json && !isSearchModel(model) ? { type: "json_object" } : undefined,
          }),
          { signal, timeoutMs: timeoutMs || (kind === "deep" ? 90000 : config.timeoutMs) }
        );
        if (!response.ok) {
          lastError = new Error(`MIMO_LLM_HTTP_${response.status}`);
          continue;
        }
        const data = await response.json();
        const msg = data?.choices?.[0]?.message || {};
        const content = String(msg.content || "").trim();
        if (!content) {
          lastError = new Error("MIMO_LLM_EMPTY");
          continue;
        }
        const sources = [];
        for (const a of msg.annotations || []) {
          const c = a?.url_citation;
          if (c?.url && !sources.some((s) => s.url === c.url)) {
            sources.push({ title: String(c.title || "").slice(0, 120), url: c.url });
          }
        }
        const usage = normalizeUsage(data?.usage);
        onUsage?.({ model, ...usage, kind, webSearch: kind === "search" });
        return { content, sources: sources.slice(0, 6), model, usage };
      } catch (error) {
        if (signal?.aborted || error?.code === "MIMO_LLM_NO_CREDIT") throw error;
        lastError = error;
      }
    }
    throw lastError || new Error("MIMO_LLM_FAILED");
  }

  return { enabled, chat, complete, models: config.models, config };
}

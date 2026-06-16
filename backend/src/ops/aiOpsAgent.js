import { classifyIncident } from "./incidentClassifier.js";
import { aiOpsSystemPrompt } from "./prompts/aiOpsSystemPrompt.js";
import { redactSensitiveData, sanitizeOpsLogs } from "./redaction.js";
import { normalizeRiskLevel, normalizeSeverity } from "./types.js";

function clean(value) {
  return String(value || "").trim();
}

function parseJsonSafely(value) {
  if (!value) return null;
  try {
    return JSON.parse(value);
  } catch (_) {
    return null;
  }
}

function normalizeAnalysis(raw, fallback) {
  const out = {
    severity: normalizeSeverity(raw?.severity || fallback?.severity || "SEV3"),
    affected_service: clean(raw?.affected_service || fallback?.affected_service || "maslaki"),
    affected_module: clean(raw?.affected_module || fallback?.affected_module || "general"),
    symptoms: Array.isArray(raw?.symptoms)
      ? raw.symptoms.map((v) => clean(v)).filter(Boolean)
      : fallback?.symptoms || [],
    evidence: Array.isArray(raw?.evidence)
      ? raw.evidence.map((v) => clean(v)).filter(Boolean)
      : fallback?.evidence || [],
    probable_root_cause: clean(
      raw?.probable_root_cause || fallback?.probable_root_cause || "Unknown"
    ),
    immediate_mitigation: clean(
      raw?.immediate_mitigation || fallback?.immediate_mitigation || "Escalate to super admin"
    ),
    long_term_fix: clean(raw?.long_term_fix || fallback?.long_term_fix || "Improve tests and observability"),
    safe_auto_actions: Array.isArray(raw?.safe_auto_actions)
      ? raw.safe_auto_actions.map((v) => clean(v)).filter(Boolean)
      : fallback?.safe_auto_actions || [],
    requires_human_approval: Array.isArray(raw?.requires_human_approval)
      ? raw.requires_human_approval.map((v) => clean(v)).filter(Boolean)
      : fallback?.requires_human_approval || [],
    recommended_github_issue_title: clean(
      raw?.recommended_github_issue_title || fallback?.recommended_github_issue_title || ""
    ),
    recommended_github_issue_body: clean(
      raw?.recommended_github_issue_body || fallback?.recommended_github_issue_body || ""
    ),
    recommended_code_fix_prompt: clean(
      raw?.recommended_code_fix_prompt || fallback?.recommended_code_fix_prompt || ""
    ),
    customer_message_ar: clean(raw?.customer_message_ar || fallback?.customer_message_ar || ""),
    admin_message_ar: clean(raw?.admin_message_ar || fallback?.admin_message_ar || ""),
    risk_level: normalizeRiskLevel(raw?.risk_level || fallback?.risk_level || "medium"),
  };

  return out;
}

async function callOpenAiAnalysis({ env, input }) {
  const apiKey = clean(env.openaiApiKey);
  if (!apiKey) return null;

  const model = clean(env.openaiModelTriage || "gpt-5.4-mini");
  const baseUrl = clean(env.openaiBaseUrl || "https://api.openai.com/v1");

  const response = await fetch(`${baseUrl}/chat/completions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model,
      temperature: 0.1,
      messages: [
        {
          role: "system",
          content: aiOpsSystemPrompt,
        },
        {
          role: "user",
          content: JSON.stringify(input),
        },
      ],
      response_format: {
        type: "json_object",
      },
    }),
  });

  if (!response.ok) {
    return null;
  }

  const json = await response.json();
  const text = json?.choices?.[0]?.message?.content;
  if (!text) return null;
  return parseJsonSafely(text);
}

export async function analyzeIncidentWithAi({
  env,
  source = "manual",
  title = "",
  summary = "",
  payload = {},
  logs = [],
  settings = {},
}) {
  const redactedPayload = redactSensitiveData(payload);
  const redactedLogs = sanitizeOpsLogs(logs);

  const baseline = classifyIncident({
    source,
    title,
    summary,
    payload: redactedPayload.payload,
    logs: redactedLogs,
  });

  if (settings.ai_analysis_enabled === false) {
    return {
      provider: "heuristic",
      analysis: baseline,
      redactionMeta: redactedPayload.meta,
    };
  }

  try {
    const aiInput = {
      source,
      title,
      summary,
      payload_redacted: redactedPayload.payload,
      logs_redacted: redactedLogs,
      baseline,
    };

    const aiResult = await callOpenAiAnalysis({ env, input: aiInput });
    if (!aiResult) {
      return {
        provider: "heuristic",
        analysis: baseline,
        redactionMeta: redactedPayload.meta,
      };
    }

    return {
      provider: "openai",
      analysis: normalizeAnalysis(aiResult, baseline),
      redactionMeta: redactedPayload.meta,
    };
  } catch (_) {
    return {
      provider: "heuristic",
      analysis: baseline,
      redactionMeta: redactedPayload.meta,
    };
  }
}

import assert from "node:assert/strict";
import test from "node:test";

import { analyzeIncidentWithAi } from "../ops/aiOpsAgent.js";

test("analyzeIncidentWithAi falls back to heuristic without API key", async () => {
  const out = await analyzeIncidentWithAi({
    env: { openaiApiKey: "" },
    source: "manual",
    title: "Checkout timeout",
    summary: "latency timeout",
    payload: { token: "secret" },
    logs: ["error timeout"],
    settings: { ai_analysis_enabled: true },
  });
  assert.equal(out.provider, "heuristic");
  assert.ok(out.analysis.severity);
});

test("analyzeIncidentWithAi uses OpenAI when response is valid JSON", async () => {
  const originalFetch = global.fetch;
  global.fetch = async () => {
    return new Response(
      JSON.stringify({
        choices: [
          {
            message: {
              content: JSON.stringify({
                severity: "SEV2",
                affected_service: "backend_api",
                affected_module: "orders",
                symptoms: ["error spike"],
                evidence: ["trace"],
                probable_root_cause: "deploy regression",
                immediate_mitigation: "rollback",
                long_term_fix: "add tests",
                safe_auto_actions: ["create_github_issue"],
                requires_human_approval: ["rollback_service"],
                recommended_github_issue_title: "issue",
                recommended_github_issue_body: "body",
                recommended_code_fix_prompt: "prompt",
                customer_message_ar: "msg",
                admin_message_ar: "admin",
                risk_level: "high",
              }),
            },
          },
        ],
      }),
      { status: 200, headers: { 'content-type': 'application/json' } }
    );
  };

  try {
    const out = await analyzeIncidentWithAi({
      env: { openaiApiKey: "k", openaiBaseUrl: "https://example.com", openaiModelTriage: "model" },
      source: "sentry",
      title: "Order error",
      summary: "major error",
      payload: { phone: "07701234567" },
      logs: ["stack"],
      settings: { ai_analysis_enabled: true },
    });

    assert.equal(out.provider, "openai");
    assert.equal(out.analysis.severity, "SEV2");
    assert.equal(out.analysis.risk_level, "high");
  } finally {
    global.fetch = originalFetch;
  }
});

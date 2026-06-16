import assert from "node:assert/strict";
import test from "node:test";

import { classifyIncident } from "../ops/incidentClassifier.js";

test("classifyIncident marks payment failure as SEV1 critical", () => {
  const out = classifyIncident({
    source: "sentry",
    title: "Payment failed in checkout",
    summary: "payment failed with fatal exception",
  });
  assert.equal(out.severity, "SEV1");
  assert.equal(out.risk_level, "critical");
  assert.equal(out.affected_module, "payments");
});

test("classifyIncident marks warning as SEV4", () => {
  const out = classifyIncident({
    source: "datadog",
    title: "warning threshold reached",
    summary: "minor warning",
  });
  assert.equal(out.severity, "SEV4");
});

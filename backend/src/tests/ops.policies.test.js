import assert from "node:assert/strict";
import test from "node:test";

import {
  canAutoExecuteAction,
  classifyActionRisk,
  requiresHumanApproval,
  validateTypedConfirmation,
} from "../ops/policies.js";

test("classifyActionRisk blocks forbidden action types", () => {
  const risk = classifyActionRisk("merge_to_main", {});
  assert.equal(risk, "critical");
});

test("canAutoExecuteAction allows low-risk code-fix request", () => {
  const out = canAutoExecuteAction({
    actionType: "request_code_fix",
    riskLevel: "low",
    settings: {},
    input: { module: "ui" },
  });
  assert.equal(out.allowed, true);
});

test("requiresHumanApproval true for medium+", () => {
  assert.equal(requiresHumanApproval("restart_service", "medium"), true);
  assert.equal(requiresHumanApproval("notify_admin", "low"), false);
});

test("validateTypedConfirmation enforces typed text for critical", () => {
  assert.equal(
    validateTypedConfirmation({ riskLevel: "critical", confirmationText: "approve" }).ok,
    true
  );
  assert.equal(
    validateTypedConfirmation({ riskLevel: "critical", confirmationText: "no" }).ok,
    false
  );
});

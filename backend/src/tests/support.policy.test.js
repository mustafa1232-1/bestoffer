import assert from "node:assert/strict";
import test from "node:test";

import {
  canTransition,
  computeDueDates,
  computeSlaState,
  isTerminalStatus,
  SLA_TARGETS,
} from "../modules/support/support.policy.js";

test("state machine allows sane transitions and blocks nonsense", () => {
  assert.equal(canTransition("NEW", "ASSIGNED"), true);
  assert.equal(canTransition("ASSIGNED", "RESOLVED"), true);
  assert.equal(canTransition("RESOLVED", "REOPENED"), true);
  assert.equal(canTransition("CLOSED", "REOPENED"), true);
  assert.equal(canTransition("RESOLVED", "NEW"), false);
  assert.equal(canTransition("CLOSED", "IN_PROGRESS"), false);
  assert.equal(canTransition("NEW", "NEW"), false);
});

test("terminal status is CLOSED only", () => {
  assert.equal(isTerminalStatus("CLOSED"), true);
  assert.equal(isTerminalStatus("RESOLVED"), false);
  assert.equal(isTerminalStatus("NEW"), false);
});

test("due dates scale with priority", () => {
  const created = 1_000_000_000_000;
  const urgent = computeDueDates("urgent", created);
  const low = computeDueDates("low", created);
  assert.ok(new Date(urgent.firstResponseDueAt).getTime() < new Date(low.firstResponseDueAt).getTime());
  assert.equal(
    new Date(urgent.resolutionDueAt).getTime() - created,
    SLA_TARGETS.urgent.resolutionMins * 60_000
  );
});

test("SLA state: green within window, yellow near due, red overdue, met once satisfied", () => {
  const created = 0;
  const frDue = 100_000; // 100s window
  const resDue = 1_000_000;

  // green: plenty of time, no first response yet
  let s = computeSlaState({
    status: "ASSIGNED", createdAtMs: created,
    firstResponseDueAtMs: frDue, resolutionDueAtMs: resDue, nowMs: 10_000,
  });
  assert.equal(s.firstResponse, "green");

  // yellow: within last 20% of the window
  s = computeSlaState({
    status: "ASSIGNED", createdAtMs: created,
    firstResponseDueAtMs: frDue, resolutionDueAtMs: resDue, nowMs: 90_000,
  });
  assert.equal(s.firstResponse, "yellow");

  // red: past due, still no response
  s = computeSlaState({
    status: "ASSIGNED", createdAtMs: created,
    firstResponseDueAtMs: frDue, resolutionDueAtMs: resDue, nowMs: 200_000,
  });
  assert.equal(s.firstResponse, "red");

  // met: first response happened before due
  s = computeSlaState({
    status: "IN_PROGRESS", createdAtMs: created,
    firstResponseDueAtMs: frDue, resolutionDueAtMs: resDue,
    firstResponseAtMs: 50_000, nowMs: 200_000,
  });
  assert.equal(s.firstResponse, "met");

  // breached: first response after due
  s = computeSlaState({
    status: "IN_PROGRESS", createdAtMs: created,
    firstResponseDueAtMs: frDue, resolutionDueAtMs: resDue,
    firstResponseAtMs: 150_000, nowMs: 200_000,
  });
  assert.equal(s.firstResponse, "breached");
});

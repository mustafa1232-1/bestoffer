import assert from "node:assert/strict";
import test from "node:test";

import { __ordersRepoTestables } from "../modules/orders/orders.repo.js";

const {
  buildReportTimeFilter,
  normalizeReportPeriod,
  periodStartExpression,
} = __ordersRepoTestables;

test("owner report periods support all-time without forcing a date filter", () => {
  assert.equal(normalizeReportPeriod("all"), "all");
  assert.equal(normalizeReportPeriod("day"), "day");
  assert.equal(normalizeReportPeriod("bogus"), null);
  assert.equal(periodStartExpression("all"), null);
  assert.equal(buildReportTimeFilter("all"), null);
  assert.equal(buildReportTimeFilter("day"), "o.created_at >= DATE_TRUNC('day', NOW())");
  assert.equal(buildReportTimeFilter("week"), "o.created_at >= DATE_TRUNC('week', NOW())");
  assert.equal(
    buildReportTimeFilter("month"),
    "o.created_at >= DATE_TRUNC('month', NOW())"
  );
  assert.equal(
    buildReportTimeFilter("year"),
    "o.created_at >= DATE_TRUNC('year', NOW())"
  );
});

test("owner report period accepts friendly aliases without INVALID_PERIOD", () => {
  // 'all' family -> all-time, no restrictive date window.
  for (const alias of ["all", "total", "lifetime", "all_time", "alltime", "ALL", " Total "]) {
    assert.equal(normalizeReportPeriod(alias), "all", `alias ${alias}`);
    assert.equal(buildReportTimeFilter(alias), null, `alias ${alias} filter`);
  }
  // 'today' -> day.
  assert.equal(normalizeReportPeriod("today"), "day");
  assert.equal(normalizeReportPeriod("TODAY"), "day");
  assert.equal(
    buildReportTimeFilter("today"),
    "o.created_at >= DATE_TRUNC('day', NOW())"
  );
  // Genuinely invalid values still return null so the controller can raise a
  // controlled 400 INVALID_PERIOD (never a crash).
  assert.equal(normalizeReportPeriod("quarter"), null);
  assert.equal(normalizeReportPeriod(""), "day"); // empty defaults to day
});

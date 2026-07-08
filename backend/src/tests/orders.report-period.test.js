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

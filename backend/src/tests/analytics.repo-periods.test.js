import assert from "node:assert/strict";
import test from "node:test";

import { __analyticsRepoTestables } from "../modules/analytics/analytics.repo.js";

const { periodStart } = __analyticsRepoTestables;

test("analytics periods support week and all-time", () => {
  assert.equal(
    periodStart("day"),
    "(DATE_TRUNC('day', NOW() AT TIME ZONE 'Asia/Baghdad') AT TIME ZONE 'Asia/Baghdad')",
  );
  assert.equal(
    periodStart("week"),
    "(DATE_TRUNC('week', NOW() AT TIME ZONE 'Asia/Baghdad') AT TIME ZONE 'Asia/Baghdad')",
  );
  assert.equal(
    periodStart("month"),
    "(DATE_TRUNC('month', NOW() AT TIME ZONE 'Asia/Baghdad') AT TIME ZONE 'Asia/Baghdad')",
  );
  assert.equal(
    periodStart("year"),
    "(DATE_TRUNC('year', NOW() AT TIME ZONE 'Asia/Baghdad') AT TIME ZONE 'Asia/Baghdad')",
  );
  assert.equal(periodStart("all"), null);
});

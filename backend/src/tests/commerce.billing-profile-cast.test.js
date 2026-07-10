import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import test from "node:test";

// Regression guard for a 42804 that broke merchant approval:
// the merchant_billing_profile upsert must cast effective_from ($19, timestamptz)
// to ::timestamptz, NOT grace_period_days ($18, integer). A misplaced cast made
// PATCH /api/admin/merchants/:id/approve return 500
// (column "grace_period_days" is of type integer but expression is of type
// timestamp with time zone).
test("merchant_billing_profile upsert casts effective_from ($19), not grace_period_days ($18)", () => {
  const repoPath = fileURLToPath(
    new URL("../modules/commerce/commerce.repo.js", import.meta.url)
  );
  // Normalize CRLF so the checks are line-ending agnostic.
  const src = readFileSync(repoPath, "utf8").replace(/\r\n/g, "\n");
  const idx = src.indexOf("INSERT INTO merchant_billing_profile\n");
  assert.ok(idx >= 0, "merchant_billing_profile insert must exist");
  const body = src.slice(idx, idx + 1500);

  // effective_from is the 19th column and MUST carry the timestamptz cast.
  assert.ok(
    body.includes("$18,$19::timestamptz,$20"),
    "effective_from ($19) must carry the ::timestamptz cast"
  );
  // grace_period_days is the 18th column (integer) and must NOT be cast.
  assert.ok(
    !body.includes("$18::timestamptz"),
    "grace_period_days ($18) must NOT be cast to timestamptz"
  );

  // Column order sanity: grace_period_days precedes effective_from.
  const graceIdx = body.indexOf("grace_period_days");
  const effectiveIdx = body.indexOf("effective_from");
  assert.ok(graceIdx >= 0 && effectiveIdx >= 0 && graceIdx < effectiveIdx);
});

/* eslint-disable no-console */
import "dotenv/config";

import { pool } from "../config/db.js";

const POLICY_NOTE =
  "Provider account policy applied to old and new accounts. Registration is free; Maslaki records a 10% commission on each completed booking. Cash is handled through the office and electronic payment is not available yet.";

const LEGACY_REVIEW_STATUSES = [
  "pending",
  "pending_review",
  "submitted",
  "under_review",
  "draft",
  "not_submitted",
];

const dryRun = process.argv.includes("--dry-run");

async function main() {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const before = await client.query(
      `SELECT
         COUNT(*)::int AS total,
         COUNT(*) FILTER (WHERE provider_approval_status = ANY($1::text[]))::int AS legacy_review,
         COUNT(*) FILTER (WHERE accepts_cash IS DISTINCT FROM TRUE)::int AS cash_not_enabled,
         COUNT(*) FILTER (WHERE accepts_electronic IS DISTINCT FROM FALSE)::int AS electronic_enabled
       FROM service_provider_profiles`,
      [LEGACY_REVIEW_STATUSES],
    );

    const update = await client.query(
      `UPDATE service_provider_profiles
       SET
         provider_approval_status = CASE
           WHEN provider_approval_status = ANY($1::text[]) THEN 'approved'
           ELSE provider_approval_status
         END,
         approval_note = $2,
         accepts_cash = TRUE,
         accepts_electronic = FALSE,
         approved_at = CASE
           WHEN provider_approval_status = ANY($1::text[])
           THEN COALESCE(approved_at, NOW())
           ELSE approved_at
         END,
         updated_at = NOW()
       WHERE
         provider_approval_status = ANY($1::text[])
         OR accepts_cash IS DISTINCT FROM TRUE
         OR accepts_electronic IS DISTINCT FROM FALSE
         OR approval_note IS DISTINCT FROM $2
       RETURNING id, user_id, provider_approval_status`,
      [LEGACY_REVIEW_STATUSES, POLICY_NOTE],
    );

    if (dryRun) {
      await client.query("ROLLBACK");
    } else {
      await client.query("COMMIT");
    }

    const beforeRow = before.rows[0] || {};
    console.log(
      `[service-provider-policy] ${dryRun ? "DRY_RUN" : "PASS"} total=${beforeRow.total || 0} legacyReview=${beforeRow.legacy_review || 0} cashNotEnabled=${beforeRow.cash_not_enabled || 0} electronicEnabled=${beforeRow.electronic_enabled || 0} updated=${update.rowCount}`,
    );
  } catch (error) {
    try {
      await client.query("ROLLBACK");
    } catch {
      // ignore
    }
    console.error("[service-provider-policy] FAIL", error?.message || error);
    process.exitCode = 1;
  } finally {
    client.release();
    await pool.end();
  }
}

main();

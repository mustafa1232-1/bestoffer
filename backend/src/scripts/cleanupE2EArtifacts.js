/* eslint-disable no-console */
import "dotenv/config";

import { ensureSchema, pool } from "../config/db.js";
import { validateRuntimeEnv } from "../config/env.js";

const DEFAULT_PATTERNS = [
  "%jobs-e2e-%",
  "E2E Streams %",
  "Real Estate streams-%",
  "Residence update streams-%",
  "Baseline post before restriction streams-%",
  "Allowed post after revoke streams-%",
  "Property seller streams-%",
  "Created by streams-%",
  "Jobs Merchant %",
  "Jobs Merchant Outsider %",
  "Jobs Candidate %",
  "Jobs HR %",
];

function uniquePatterns() {
  const raw = String(process.env.CLEANUP_E2E_PATTERNS || "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
  return [...new Set([...DEFAULT_PATTERNS, ...raw])];
}

async function fetchCleanupTargets(client, patterns) {
  const patternArray = patterns;

  const users = await client.query(
    `SELECT id
     FROM app_user
     WHERE full_name ILIKE ANY($1::text[])
        OR phone = ANY(
          ARRAY(
            SELECT DISTINCT phone
            FROM app_user
            WHERE full_name ILIKE ANY($1::text[])
          )
        )`,
    [patternArray]
  );

  const merchants = await client.query(
    `SELECT id
     FROM merchant
     WHERE name ILIKE ANY($1::text[])
        OR description ILIKE ANY($1::text[])
        OR tagline ILIKE ANY($1::text[])
        OR service_area_note ILIKE ANY($1::text[])`,
    [patternArray]
  );

  const jobs = await client.query(
    `SELECT id
     FROM job_post
     WHERE title ILIKE ANY($1::text[])
        OR description ILIKE ANY($1::text[])
        OR requirements ILIKE ANY($1::text[])
        OR responsibilities ILIKE ANY($1::text[])
        OR benefits ILIKE ANY($1::text[])`,
    [patternArray]
  );

  const posts = await client.query(
    `SELECT id
     FROM social_post
     WHERE caption ILIKE ANY($1::text[])`,
    [patternArray]
  );

  const listings = await client.query(
    `SELECT id
     FROM real_estate_listing
     WHERE title ILIKE ANY($1::text[])
        OR COALESCE(description, '') ILIKE ANY($1::text[])
        OR COALESCE(furnishing_description, '') ILIKE ANY($1::text[])
        OR COALESCE(details_json::text, '') ILIKE ANY($1::text[])`,
    [patternArray]
  );

  const paymentRequests = await client.query(
    `SELECT id
     FROM merchant_payment_request
     WHERE note ILIKE ANY($1::text[])`,
    [patternArray]
  );

  const residenceRequests = await client.query(
    `SELECT id
     FROM residence_change_request
     WHERE note ILIKE ANY($1::text[])
        OR review_note ILIKE ANY($1::text[])`,
    [patternArray]
  );

  const restrictions = await client.query(
    `SELECT id
     FROM social_capability_restriction
     WHERE reason ILIKE ANY($1::text[])`,
    [patternArray]
  );

  return {
    userIds: users.rows.map((row) => Number(row.id)).filter(Boolean),
    merchantIds: merchants.rows.map((row) => Number(row.id)).filter(Boolean),
    jobIds: jobs.rows.map((row) => Number(row.id)).filter(Boolean),
    postIds: posts.rows.map((row) => Number(row.id)).filter(Boolean),
    listingIds: listings.rows.map((row) => Number(row.id)).filter(Boolean),
    paymentRequestIds: paymentRequests.rows
      .map((row) => Number(row.id))
      .filter(Boolean),
    residenceRequestIds: residenceRequests.rows
      .map((row) => Number(row.id))
      .filter(Boolean),
    restrictionIds: restrictions.rows.map((row) => Number(row.id)).filter(Boolean),
  };
}

async function cleanup() {
  validateRuntimeEnv();
  await ensureSchema();

  const patterns = uniquePatterns();
  const client = await pool.connect();

  try {
    await client.query("BEGIN");

    const target = await fetchCleanupTargets(client, patterns);
    const {
      userIds,
      merchantIds,
      jobIds,
      postIds,
      listingIds,
      paymentRequestIds,
      residenceRequestIds,
      restrictionIds,
    } = target;

    if (restrictionIds.length > 0) {
      await client.query(
        `DELETE FROM social_capability_restriction
         WHERE id = ANY($1::bigint[])`,
        [restrictionIds]
      );
    }

    if (residenceRequestIds.length > 0) {
      await client.query(
        `DELETE FROM residence_change_request
         WHERE id = ANY($1::bigint[])`,
        [residenceRequestIds]
      );
    }

    if (listingIds.length > 0) {
      await client.query(
        `DELETE FROM real_estate_listing
         WHERE id = ANY($1::bigint[])`,
        [listingIds]
      );
    }

    if (postIds.length > 0) {
      await client.query(
        `DELETE FROM social_post_comment_like
         WHERE post_comment_id IN (
           SELECT id FROM social_post_comment WHERE post_id = ANY($1::bigint[])
         )`,
        [postIds]
      );
      await client.query(
        `DELETE FROM social_post_report_review_log
         WHERE post_id = ANY($1::bigint[])`,
        [postIds]
      );
      await client.query(
        `DELETE FROM social_post_report
         WHERE post_id = ANY($1::bigint[])`,
        [postIds]
      );
      await client.query(
        `DELETE FROM social_post_comment
         WHERE post_id = ANY($1::bigint[])`,
        [postIds]
      );
      await client.query(
        `DELETE FROM social_post_like
         WHERE post_id = ANY($1::bigint[])`,
        [postIds]
      );
      await client.query(
        `DELETE FROM social_post
         WHERE id = ANY($1::bigint[])`,
        [postIds]
      );
    }

    if (paymentRequestIds.length > 0) {
      await client.query(
        `DELETE FROM merchant_payment_invoice_allocation
         WHERE payment_request_id = ANY($1::bigint[])`,
        [paymentRequestIds]
      );
      await client.query(
        `DELETE FROM merchant_payment_allocation
         WHERE payment_request_id = ANY($1::bigint[])`,
        [paymentRequestIds]
      );
      await client.query(
        `DELETE FROM merchant_payment_request_status_history
         WHERE payment_request_id = ANY($1::bigint[])`,
        [paymentRequestIds]
      );
      await client.query(
        `DELETE FROM merchant_payment_request
         WHERE id = ANY($1::bigint[])`,
        [paymentRequestIds]
      );
    }

    if (jobIds.length > 0) {
      await client.query(
        `DELETE FROM job_application_status_history
         WHERE job_id = ANY($1::bigint[])`,
        [jobIds]
      );
      await client.query(
        `DELETE FROM job_recommendation
         WHERE job_id = ANY($1::bigint[])`,
        [jobIds]
      );
      await client.query(
        `DELETE FROM job_application
         WHERE job_id = ANY($1::bigint[])`,
        [jobIds]
      );
      await client.query(
        `DELETE FROM job_post
         WHERE id = ANY($1::bigint[])`,
        [jobIds]
      );
    }

    if (merchantIds.length > 0) {
      await client.query(
        `DELETE FROM merchant_hr_staff
         WHERE merchant_id = ANY($1::bigint[])`,
        [merchantIds]
      );
      await client.query(
        `DELETE FROM merchant_billing_profile_audit
         WHERE merchant_id = ANY($1::bigint[])`,
        [merchantIds]
      );
      await client.query(
        `DELETE FROM merchant_billing_profile
         WHERE merchant_id = ANY($1::bigint[])`,
        [merchantIds]
      );
      await client.query(
        `DELETE FROM merchant_settlement
         WHERE merchant_id = ANY($1::bigint[])`,
        [merchantIds]
      );
      await client.query(
        `DELETE FROM merchant
         WHERE id = ANY($1::bigint[])`,
        [merchantIds]
      );
    }

    if (userIds.length > 0) {
      await client.query(
        `DELETE FROM paid_upgrade_audit
         WHERE actor_user_id = ANY($1::bigint[])`,
        [userIds]
      );
      await client.query(
        `DELETE FROM paid_upgrade_subscription
         WHERE user_id = ANY($1::bigint[])`,
        [userIds]
      );
      await client.query(
        `DELETE FROM paid_upgrade_request
         WHERE user_id = ANY($1::bigint[])`,
        [userIds]
      );
      await client.query(
        `DELETE FROM merchant_hr_staff
         WHERE hr_user_id = ANY($1::bigint[])`,
        [userIds]
      );
      await client.query(
        `DELETE FROM user_residence_info
         WHERE user_id = ANY($1::bigint[])`,
        [userIds]
      );
      await client.query(
        `DELETE FROM customer_address
         WHERE customer_user_id = ANY($1::bigint[])`,
        [userIds]
      );
      await client.query(
        `DELETE FROM social_user_relation
         WHERE user_a_id = ANY($1::bigint[])
            OR user_b_id = ANY($1::bigint[])`,
        [userIds]
      );
      await client.query(
        `DELETE FROM user_activity_event
         WHERE user_id = ANY($1::bigint[])`,
        [userIds]
      );
      await client.query(
        `DELETE FROM user_push_token
         WHERE user_id = ANY($1::bigint[])`,
        [userIds]
      );
      await client.query(
        `DELETE FROM user_session
         WHERE user_id = ANY($1::bigint[])`,
        [userIds]
      );
      await client.query(
        `DELETE FROM app_notification
         WHERE user_id = ANY($1::bigint[])`,
        [userIds]
      );
      await client.query(
        `DELETE FROM app_user
         WHERE id = ANY($1::bigint[])`,
        [userIds]
      );
    }

    await client.query("COMMIT");

    console.log(
      JSON.stringify(
        {
          patterns,
          deleted: {
            users: userIds.length,
            merchants: merchantIds.length,
            jobs: jobIds.length,
            posts: postIds.length,
            listings: listingIds.length,
            paymentRequests: paymentRequestIds.length,
            residenceRequests: residenceRequestIds.length,
            restrictions: restrictionIds.length,
          },
        },
        null,
        2
      )
    );
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
    await pool.end();
  }
}

cleanup().catch((error) => {
  console.error("[cleanup-e2e] failed", error);
  process.exit(1);
});

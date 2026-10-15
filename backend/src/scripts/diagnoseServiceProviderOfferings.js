/* eslint-disable no-console */
import "dotenv/config";

import { pool } from "../config/db.js";
import { closeRedisClient } from "../config/redis.js";
import { createOfferingForProvider } from "../modules/services/services.repo.js";

const userId = Number(process.argv[2]);
const verifyReplay = process.argv.includes("--verify-replay");

if (!Number.isInteger(userId) || userId <= 0) {
  throw new Error(
    "Usage: node src/scripts/diagnoseServiceProviderOfferings.js <user-id>",
  );
}

async function main() {
  const providerResult = await pool.query(
    `SELECT sp.id,
            sp.user_id,
            sp.business_name,
            sp.provider_approval_status,
            sp.is_active,
            u.role,
            COALESCE(u.is_account_disabled, FALSE) AS user_disabled
       FROM service_provider_profiles sp
       JOIN app_user u ON u.id = sp.user_id
      WHERE sp.user_id = $1`,
    [userId],
  );
  const provider = providerResult.rows[0] || null;
  if (!provider) {
    console.log(JSON.stringify({ userId, provider: null }, null, 2));
    return;
  }

  const offerings = await pool.query(
    `SELECT so.id,
            so.name,
            so.normalized_name,
            so.main_category_id,
            mc.name AS main_category_name,
            mc.is_active AS main_category_active,
            mc.is_public AS main_category_public,
            so.subcategory_id,
            sc.name AS subcategory_name,
            so.subcategory_id_resolved,
            so.moderation_status,
            so.is_active,
            so.is_temporarily_paused,
            so.starts_from_price,
            so.created_at,
            so.updated_at,
            COUNT(DISTINCT som.id)::int AS media_count,
            COUNT(DISTINCT sop.id)::int AS pricing_count,
            (
              so.is_active = TRUE
              AND so.is_temporarily_paused = FALSE
              AND so.moderation_status = 'approved'
              AND sp.is_active = TRUE
              AND sp.is_temporarily_paused = FALSE
              AND sp.provider_approval_status = 'approved'
            ) AS public_visible
       FROM service_offerings so
       JOIN service_provider_profiles sp ON sp.id = so.provider_id
       LEFT JOIN service_categories mc ON mc.id = so.main_category_id
       LEFT JOIN service_categories sc ON sc.id = so.subcategory_id
       LEFT JOIN service_offering_media som ON som.offering_id = so.id
       LEFT JOIN service_pricing_options sop ON sop.offering_id = so.id
      WHERE so.provider_id = $1
      GROUP BY so.id, sp.id, mc.id, sc.id
      ORDER BY so.id ASC`,
    [Number(provider.id)],
  );

  let replayVerification = null;
  if (verifyReplay && offerings.rows.length > 0) {
    const original = offerings.rows[0];
    const replayed = await createOfferingForProvider({
      userId,
      dto: {
        mainCategoryId: Number(original.main_category_id),
        subcategoryId: original.subcategory_id
          ? Number(original.subcategory_id)
          : null,
        name: original.name,
        description: "idempotency verification; must not be persisted",
        executionMode: "home",
        startsFromPrice: 1,
        pricingOptions: [],
      },
    });
    const after = await pool.query(
      `SELECT COUNT(DISTINCT so.id)::int AS matching_count,
              MAX(starts_from_price) AS starts_from_price,
              COUNT(DISTINCT som.id)::int AS media_count,
              COUNT(DISTINCT sop.id)::int AS pricing_count
         FROM service_offerings so
         LEFT JOIN service_offering_media som ON som.offering_id = so.id
         LEFT JOIN service_pricing_options sop ON sop.offering_id = so.id
        WHERE so.provider_id = $1
          AND so.normalized_name = $2`,
      [Number(provider.id), original.normalized_name],
    );
    replayVerification = {
      originalId: Number(original.id),
      replayedId: Number(replayed?.id || 0),
      unchanged:
        Number(replayed?.id || 0) === Number(original.id) &&
        Number(after.rows[0]?.matching_count || 0) === 1 &&
        Number(after.rows[0]?.starts_from_price || 0) ===
          Number(original.starts_from_price || 0) &&
        Number(after.rows[0]?.media_count || 0) ===
          Number(original.media_count || 0) &&
        Number(after.rows[0]?.pricing_count || 0) ===
          Number(original.pricing_count || 0),
      after: after.rows[0],
    };
  }

  console.log(
    JSON.stringify(
      {
        userId,
        provider,
        offeringCount: offerings.rowCount,
        offerings: offerings.rows,
        replayVerification,
      },
      null,
      2,
    ),
  );
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await closeRedisClient().catch(() => {});
    await pool.end().catch(() => {});
  });

/* eslint-disable no-console */
import "dotenv/config";

import { pool } from "../config/db.js";
import { closeRedisClient } from "../config/redis.js";

async function main() {
  const result = await pool.query(
    `SELECT so.id,
            so.name,
            sp.id AS provider_id,
            sp.business_name,
            so.main_category_id,
            mc.name AS main_category_name,
            so.subcategory_id,
            sc.name AS subcategory_name,
            so.moderation_status,
            so.is_active,
            so.is_temporarily_paused,
            sp.provider_approval_status,
            sp.is_active AS provider_is_active,
            sp.is_temporarily_paused AS provider_is_temporarily_paused,
            COUNT(DISTINCT som.id)::int AS media_count,
            COUNT(DISTINCT spo.id)::int AS pricing_count,
            ARRAY_REMOVE(ARRAY[
              CASE WHEN so.main_category_id IS NULL THEN 'MISSING_MAIN_CATEGORY' END,
              CASE WHEN mc.id IS NULL THEN 'MAIN_CATEGORY_NOT_FOUND' END,
              CASE WHEN COALESCE(mc.is_active, FALSE) = FALSE THEN 'MAIN_CATEGORY_INACTIVE' END,
              CASE WHEN COALESCE(mc.is_public, FALSE) = FALSE THEN 'MAIN_CATEGORY_PRIVATE' END,
              CASE WHEN so.moderation_status <> 'approved' THEN 'OFFERING_NOT_APPROVED' END,
              CASE WHEN so.is_active = FALSE THEN 'OFFERING_INACTIVE' END,
              CASE WHEN so.is_temporarily_paused = TRUE THEN 'OFFERING_PAUSED' END,
              CASE WHEN sp.provider_approval_status <> 'approved' THEN 'PROVIDER_NOT_APPROVED' END,
              CASE WHEN sp.is_active = FALSE THEN 'PROVIDER_INACTIVE' END,
              CASE WHEN sp.is_temporarily_paused = TRUE THEN 'PROVIDER_PAUSED' END,
              CASE WHEN COUNT(DISTINCT spo.id) = 0 THEN 'MISSING_PRICING' END
            ], NULL) AS blockers
       FROM service_offerings so
       JOIN service_provider_profiles sp ON sp.id = so.provider_id
       LEFT JOIN service_categories mc ON mc.id = so.main_category_id
       LEFT JOIN service_categories sc ON sc.id = so.subcategory_id
       LEFT JOIN service_offering_media som ON som.offering_id = so.id
       LEFT JOIN service_pricing_options spo ON spo.offering_id = so.id
      GROUP BY so.id, sp.id, mc.id, sc.id
      ORDER BY sp.id ASC, so.id ASC`,
  );

  const rows = result.rows.map((row) => ({
    ...row,
    publicVisible: Array.isArray(row.blockers) && row.blockers.length === 0,
  }));
  console.log(
    JSON.stringify(
      {
        total: rows.length,
        visible: rows.filter((row) => row.publicVisible).length,
        blocked: rows.filter((row) => !row.publicVisible).length,
        rows,
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

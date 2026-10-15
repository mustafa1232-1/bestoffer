/* eslint-disable no-console */
import "dotenv/config";

import { pool } from "../config/db.js";
import { closeRedisClient } from "../config/redis.js";

async function printRows(label, rows, { limit = 50 } = {}) {
  console.log(`\n[${label}] rows=${rows.length}`);
  for (const row of rows.slice(0, limit)) {
    console.log(JSON.stringify(row));
  }
  if (rows.length > limit) {
    console.log(`[${label}] truncated=${rows.length - limit}`);
  }
}

async function main() {
  const client = await pool.connect();
  try {
    const summary = await client.query(
      `SELECT
         COUNT(*)::int AS merchants_total,
         COUNT(*) FILTER (WHERE COALESCE(is_open, FALSE) = TRUE)::int AS merchants_open,
         COUNT(*) FILTER (WHERE COALESCE(is_approved, FALSE) = TRUE)::int AS merchants_approved,
         COUNT(*) FILTER (WHERE owner_user_id IS NULL)::int AS merchants_without_owner,
         COUNT(*) FILTER (
           WHERE owner_user_id IS NOT NULL
             AND NOT EXISTS (SELECT 1 FROM app_user u WHERE u.id = merchant.owner_user_id)
         )::int AS merchants_with_missing_owner,
         COUNT(*) FILTER (
           WHERE owner_user_id IS NOT NULL
             AND EXISTS (
               SELECT 1
               FROM app_user u
               WHERE u.id = merchant.owner_user_id
                 AND (u.role::text <> 'owner' OR COALESCE(u.is_account_disabled, FALSE) = TRUE)
             )
         )::int AS merchants_with_invalid_owner,
         (SELECT COUNT(*)::int FROM product WHERE deleted_at IS NULL) AS products_total,
         (SELECT COUNT(*)::int FROM product WHERE deleted_at IS NULL AND COALESCE(is_available, FALSE) = TRUE) AS products_available
       FROM merchant`,
    );
    await printRows("summary", summary.rows);

    const badOwners = await client.query(
      `SELECT
         m.id AS merchant_id,
         m.name AS merchant_name,
         m.is_open,
         m.is_approved,
         m.owner_user_id,
         u.role::text AS owner_role,
         u.phone AS owner_phone,
         u.is_account_disabled AS owner_disabled
       FROM merchant m
       LEFT JOIN app_user u ON u.id = m.owner_user_id
       WHERE m.owner_user_id IS NULL
          OR u.id IS NULL
          OR u.role::text <> 'owner'
          OR COALESCE(u.is_account_disabled, FALSE) = TRUE
       ORDER BY m.id`,
    );
    await printRows("owner_link_issues", badOwners.rows);

    const openWithoutProducts = await client.query(
      `SELECT
         m.id AS merchant_id,
         m.name AS merchant_name,
         m.owner_user_id,
         COUNT(p.id)::int AS product_count,
         COUNT(p.id) FILTER (WHERE COALESCE(p.is_available, FALSE) = TRUE)::int AS available_product_count
       FROM merchant m
       LEFT JOIN product p
         ON p.merchant_id = m.id
        AND p.deleted_at IS NULL
       WHERE COALESCE(m.is_open, FALSE) = TRUE
         AND COALESCE(m.is_approved, FALSE) = TRUE
         AND COALESCE(m.is_disabled, FALSE) = FALSE
       GROUP BY m.id, m.name, m.owner_user_id
       HAVING COUNT(p.id) FILTER (WHERE COALESCE(p.is_available, FALSE) = TRUE) = 0
       ORDER BY m.id`,
    );
    await printRows("open_approved_stores_without_available_products", openWithoutProducts.rows);

    const categoryIssues = await client.query(
      `SELECT
         p.id AS product_id,
         p.name AS product_name,
         p.merchant_id AS product_merchant_id,
         p.category_id,
         c.merchant_id AS category_merchant_id
       FROM product p
       JOIN merchant_category c ON c.id = p.category_id
       WHERE p.deleted_at IS NULL
         AND c.merchant_id <> p.merchant_id
       ORDER BY p.id`,
    );
    await printRows("product_category_cross_store_issues", categoryIssues.rows);

    const topStores = await client.query(
      `SELECT
         m.id AS merchant_id,
         m.name AS merchant_name,
         m.owner_user_id,
         u.phone AS owner_phone,
         COUNT(p.id)::int AS product_count,
         COUNT(p.id) FILTER (WHERE COALESCE(p.is_available, FALSE) = TRUE)::int AS available_product_count,
         MAX(p.updated_at) AS last_product_update
       FROM merchant m
       LEFT JOIN app_user u ON u.id = m.owner_user_id
       LEFT JOIN product p
         ON p.merchant_id = m.id
        AND p.deleted_at IS NULL
       GROUP BY m.id, m.name, m.owner_user_id, u.phone
       ORDER BY available_product_count DESC, product_count DESC, m.id
       LIMIT 60`,
    );
    await printRows("store_product_snapshot", topStores.rows, { limit: 60 });
  } finally {
    client.release();
  }
}

main()
  .catch((error) => {
    console.error(`[diagnose-store-catalog-integrity] failed: ${error?.message || error}`);
    process.exitCode = 1;
  })
  .finally(async () => {
    await closeRedisClient().catch(() => {});
    await pool.end().catch(() => {});
  });

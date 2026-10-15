import { pool } from "../config/db.js";

async function main() {
  const merchantSummary = await pool.query(
    `SELECT
       COUNT(*)::int AS merchants_total,
       COUNT(*) FILTER (WHERE COALESCE(is_open, FALSE) = TRUE)::int AS merchants_open,
       COUNT(*) FILTER (WHERE COALESCE(is_approved, FALSE) = TRUE)::int AS merchants_approved,
       COUNT(*) FILTER (
         WHERE COALESCE(is_open, FALSE) = TRUE
           AND COALESCE(is_approved, FALSE) = TRUE
           AND COALESCE(is_disabled, FALSE) = FALSE
       )::int AS merchants_live,
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
       )::int AS merchants_with_invalid_owner
     FROM merchant`
  );

  const catalogSummary = await pool.query(
    `SELECT
       COUNT(*)::int AS products_total,
       COUNT(*) FILTER (WHERE COALESCE(is_available, FALSE) = TRUE)::int AS products_available,
       COUNT(*) FILTER (WHERE merchant_id IS NULL)::int AS products_without_merchant,
       COUNT(*) FILTER (
         WHERE merchant_id IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM merchant m WHERE m.id = product.merchant_id)
       )::int AS products_with_missing_merchant
     FROM product
     WHERE deleted_at IS NULL`
  );

  const openWithoutProducts = await pool.query(
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
     ORDER BY m.id
     LIMIT 30`
  );

  const crossStoreCategories = await pool.query(
    `SELECT COUNT(*)::int AS count
       FROM product p
       JOIN merchant_category c ON c.id = p.category_id
      WHERE p.deleted_at IS NULL
        AND c.merchant_id <> p.merchant_id`
  );

  const orderSummary = await pool.query(
    `SELECT
       COUNT(*) FILTER (
         WHERE status::text IN ('pending','approved','preparing','ready_for_delivery','courier_requested','on_the_way','arrived')
       )::int AS active_store_orders,
       COUNT(*) FILTER (
         WHERE delivery_assignment_status = 'PENDING_NO_DRIVER'
           AND status::text IN ('approved','preparing','ready_for_delivery')
       )::int AS pending_no_driver,
       COUNT(*) FILTER (
         WHERE created_at >= NOW() - INTERVAL '24 hours'
       )::int AS orders_24h,
       MAX(created_at) AS latest_order_at
     FROM customer_order`
  );

  const deliverySummary = await pool.query(
    `SELECT
       COUNT(*) FILTER (
         WHERE cp.active_status = TRUE
           AND cp.availability_status = 'online'
       )::int AS profile_online,
       COUNT(*) FILTER (
         WHERE cp.active_status = TRUE
           AND cp.availability_status = 'online'
           AND p.is_online = TRUE
           AND p.updated_at >= NOW() - INTERVAL '90 seconds'
       )::int AS fresh_online,
       COUNT(*) FILTER (
         WHERE cp.active_status = TRUE
           AND cp.availability_status = 'online'
           AND p.is_online = TRUE
           AND (p.updated_at IS NULL OR p.updated_at < NOW() - INTERVAL '90 seconds')
       )::int AS stale_online
     FROM courier_profile cp
     LEFT JOIN courier_presence p ON p.courier_user_id = cp.user_id`
  );

  console.log(
    JSON.stringify(
      {
        merchants: merchantSummary.rows[0] || {},
        catalog: catalogSummary.rows[0] || {},
        openLiveStoresWithoutAvailableProducts: openWithoutProducts.rows,
        productCategoryCrossStoreIssues:
          Number(crossStoreCategories.rows[0]?.count || 0),
        orders: orderSummary.rows[0] || {},
        delivery: deliverySummary.rows[0] || {},
      },
      null,
      2
    )
  );
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await pool.end();
  });

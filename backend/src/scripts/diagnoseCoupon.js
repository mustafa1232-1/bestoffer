import { q } from "../config/db.js";
import { resolveCouponLifecycleStatus } from "../modules/coupons/coupons.repo.js";

const code = String(process.argv[2] || "").trim().toUpperCase();

if (!code) {
  console.error("Usage: node src/scripts/diagnoseCoupon.js <code>");
  process.exit(1);
}

const result = await q(
  `SELECT
     c.id,
     c.code,
     c.description,
     c.discount_type,
     c.discount_value,
     c.min_order_total,
     c.max_uses,
     c.uses_count,
     c.merchant_id,
     m.name AS merchant_name,
     c.company_id,
     c.scope_kind,
     c.valid_from,
     c.valid_until,
     c.is_active,
     c.surface_scope,
     c.target_user_id,
     c.new_customers_only,
     c.created_at,
     COUNT(cr.id)::INT AS redemption_rows,
     COUNT(cr.id) FILTER (WHERE COALESCE(cr.is_void, FALSE) = FALSE)::INT
       AS active_redemptions
   FROM coupon c
   LEFT JOIN merchant m ON m.id = c.merchant_id
   LEFT JOIN coupon_redemption cr ON cr.coupon_id = c.id
   WHERE UPPER(c.code) = $1
   GROUP BY c.id, m.name
   ORDER BY c.id DESC`,
  [code],
);

console.log(
  JSON.stringify(
    result.rows.map((row) => ({
      ...row,
      lifecycleStatus: resolveCouponLifecycleStatus(row),
    })),
    null,
    2,
  ),
);

process.exit(0);

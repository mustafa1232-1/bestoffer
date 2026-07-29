-- Employee referral / sales-attribution coupons.
--
-- `agent_user_id` links a coupon to the employee it belongs to. When a customer
-- redeems the coupon at checkout, coupon_redemption records the customer + order,
-- so the admin knows that customer came through this employee. The discount can
-- be zero (attribution-only) — the admin may add a percent/fixed discount later.

ALTER TABLE coupon
  ADD COLUMN IF NOT EXISTS agent_user_id INT REFERENCES app_user(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_coupon_agent_user ON coupon(agent_user_id);

-- Allow zero-discount coupons (attribution-only). The original constraint only
-- permitted discount_value > 0.
ALTER TABLE coupon DROP CONSTRAINT IF EXISTS coupon_discount_value_check;
ALTER TABLE coupon
  ADD CONSTRAINT coupon_discount_value_check CHECK (discount_value >= 0);

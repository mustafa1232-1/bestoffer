-- Employee coupon earnings ("كوبوني").
--
-- When a customer redeems an employee's referral coupon, the employee earns a
-- share of the COMPANY's commission on that (completed) order. Example: order
-- subtotal 10,000 IQD, company commission 10% = 1,000 IQD, employee share 25%
-- => employee earns 250 IQD. The share is per-coupon and admin-configurable at
-- creation time; it defaults to 25%.
ALTER TABLE coupon
  ADD COLUMN IF NOT EXISTS agent_commission_share_percent NUMERIC(5,2);

-- Existing employee coupons predate this column — default them to 25% so their
-- earnings compute immediately.
UPDATE coupon
   SET agent_commission_share_percent = 25
 WHERE agent_user_id IS NOT NULL
   AND agent_commission_share_percent IS NULL;

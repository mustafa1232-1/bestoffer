-- Repair coupons whose scope_kind was left at the column default ('merchant')
-- while they have no merchant and no company. createCoupon never wrote
-- scope_kind, so global coupons defaulted to 'merchant' with a NULL merchant_id
-- and could never satisfy the validation query (the global branch needs
-- scope_kind='global'; the merchant branch needs a non-null merchant_id).
-- This made every such global coupon report as "invalid".
--
-- Idempotent and safe: only touches rows with no merchant_id and no company_id.
UPDATE coupon
SET scope_kind = 'global'
WHERE merchant_id IS NULL
  AND company_id IS NULL
  AND scope_kind <> 'global';

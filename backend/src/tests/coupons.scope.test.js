import assert from "node:assert/strict";
import test from "node:test";

import { resolveCouponScopeKind } from "../modules/coupons/coupons.repo.js";

// Regression: createCoupon used to omit scope_kind, so global coupons defaulted
// to 'merchant' (the column default) with a NULL merchant_id and could never be
// matched by the validation query → every global coupon reported "invalid".

test("global coupon (no merchant, no company) resolves to 'global'", () => {
  assert.equal(resolveCouponScopeKind({}), "global");
  assert.equal(resolveCouponScopeKind({ merchantId: null }), "global");
  assert.equal(
    resolveCouponScopeKind({ merchantId: null, companyId: null }),
    "global"
  );
});

test("merchant-scoped coupon resolves to 'merchant'", () => {
  assert.equal(resolveCouponScopeKind({ merchantId: 12 }), "merchant");
});

test("company-scoped coupon resolves to 'company'", () => {
  assert.equal(
    resolveCouponScopeKind({ companyId: 4, merchantId: 12 }),
    "company"
  );
  assert.equal(resolveCouponScopeKind({ companyId: 4 }), "company");
});

import assert from "node:assert/strict";
import test from "node:test";

import {
  resolveCouponLifecycleStatus,
  resolveCouponScopeKind,
  resolveCouponValidationReason,
} from "../modules/coupons/coupons.repo.js";

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

test("coupon lifecycle status resolves active, scheduled, expired, inactive, exhausted", () => {
  assert.equal(
    resolveCouponLifecycleStatus({
      is_active: true,
      valid_from: null,
      valid_until: null,
      uses_count: 0,
      max_uses: null,
    }),
    "active"
  );
  assert.equal(
    resolveCouponLifecycleStatus({
      is_active: true,
      valid_from: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
      valid_until: null,
      uses_count: 0,
      max_uses: null,
    }),
    "scheduled"
  );
  assert.equal(
    resolveCouponLifecycleStatus({
      is_active: true,
      valid_from: null,
      valid_until: new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString(),
      uses_count: 0,
      max_uses: null,
    }),
    "expired"
  );
  assert.equal(
    resolveCouponLifecycleStatus({
      is_active: false,
      valid_from: null,
      valid_until: null,
      uses_count: 0,
      max_uses: null,
    }),
    "inactive"
  );
  assert.equal(
    resolveCouponLifecycleStatus({
      is_active: true,
      valid_from: null,
      valid_until: null,
      uses_count: 5,
      max_uses: 5,
    }),
    "exhausted"
  );
});

test("coupon validation reason matches lifecycle and target restrictions", () => {
  assert.equal(
    resolveCouponValidationReason(null, {}),
    "COUPON_NOT_FOUND"
  );
  assert.equal(
    resolveCouponValidationReason(
      {
        is_active: true,
        valid_from: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
        valid_until: null,
        uses_count: 0,
        max_uses: null,
      },
      {}
    ),
    "COUPON_NOT_STARTED"
  );
  assert.equal(
    resolveCouponValidationReason(
      {
        is_active: true,
        valid_from: null,
        valid_until: new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString(),
        uses_count: 0,
        max_uses: null,
      },
      {}
    ),
    "COUPON_EXPIRED"
  );
  assert.equal(
    resolveCouponValidationReason(
      {
        is_active: true,
        valid_from: null,
        valid_until: null,
        uses_count: 0,
        max_uses: null,
        scope_kind: "merchant",
        merchant_id: 5,
      },
      { merchantId: 7 }
    ),
    "COUPON_NOT_TARGETED"
  );
  assert.equal(
    resolveCouponValidationReason(
      {
        is_active: true,
        valid_from: null,
        valid_until: null,
        uses_count: 3,
        max_uses: 3,
      },
      {}
    ),
    "COUPON_TOTAL_LIMIT_REACHED"
  );
});

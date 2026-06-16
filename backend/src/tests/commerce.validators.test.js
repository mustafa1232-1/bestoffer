import assert from "node:assert/strict";
import test from "node:test";

import { validateMerchantFinancialApprovalTerms } from "../modules/commerce/commerce.validators.js";

test("validateMerchantFinancialApprovalTerms accepts empty body with defaults", () => {
  const result = validateMerchantFinancialApprovalTerms({});
  assert.equal(result.ok, true);
  assert.equal(result.data.commissionType, "percentage");
  assert.equal(result.data.commissionValue, 10);
  assert.equal(result.data.serviceFeeType, "fixed");
  assert.equal(result.data.serviceFeeValue, 250);
  assert.equal(result.data.deliveryFeeMode, "dynamic");
});

test("validateMerchantFinancialApprovalTerms keeps validation for invalid overrides", () => {
  const result = validateMerchantFinancialApprovalTerms({
    commissionType: "percentage",
    commissionValue: 150,
  });
  assert.equal(result.ok, false);
  assert.ok(result.errors.includes("commissionValue"));
});

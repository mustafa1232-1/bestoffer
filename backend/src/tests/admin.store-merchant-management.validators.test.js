import assert from "node:assert/strict";
import test from "node:test";

import {
  validateAdminMerchantProfilePatch,
  validateStoreActivityUpsert,
  validateStoreCatalogTemplatePatch,
  validateStoreCatalogTemplateUpsert,
} from "../modules/admin/admin.validators.js";

test("admin merchant profile patch accepts single-field store name edit", () => {
  const result = validateAdminMerchantProfilePatch({ name: "New Store Name" });

  assert.equal(result.ok, true);
  assert.equal(result.value.name, "New Store Name");
  assert.equal(result.value.activityType, null);
});

test("admin merchant profile patch rejects an empty body", () => {
  const result = validateAdminMerchantProfilePatch({});

  assert.equal(result.ok, false);
  assert.ok(result.errors.includes("body"));
});

test("store activity upsert normalizes marketplace section code", () => {
  const result = validateStoreActivityUpsert({
    activityType: "Smoking Supplies",
    baseType: "market",
    displayNameAr: "Smoking Supplies",
    displayNameEn: "Smoking Supplies",
    isActive: true,
  });

  assert.equal(result.ok, true);
  assert.equal(result.value.activityType, "smoking_supplies");
  assert.equal(result.value.baseType, "market");
  assert.equal(result.value.isActive, true);
});

test("store activity upsert rejects unsupported base type", () => {
  const result = validateStoreActivityUpsert({
    activityType: "custom",
    baseType: "taxi",
    displayNameAr: "Custom",
    displayNameEn: "Custom",
  });

  assert.equal(result.ok, false);
  assert.ok(result.errors.includes("baseType"));
});

test("store catalog template upsert normalizes code and accepts catalog type", () => {
  const result = validateStoreCatalogTemplateUpsert({
    activityType: "smoking_supplies",
    code: "Vapes",
    nameAr: "Vapes",
    nameEn: "Vapes",
    catalogType: "vapes",
    orderIndex: 40,
    isActive: true,
  });

  assert.equal(result.ok, true);
  assert.equal(result.value.code, "vapes");
  assert.equal(result.value.catalogType, "vapes");
});

test("store catalog template patch rejects empty body", () => {
  const result = validateStoreCatalogTemplatePatch({});

  assert.equal(result.ok, false);
  assert.ok(result.errors.includes("body"));
});

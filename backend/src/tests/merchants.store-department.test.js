import assert from "node:assert/strict";
import test from "node:test";

import {
  activityRequiresDepartment,
  departmentMatchesSection,
  inferDepartmentFromText,
  normalizeStoreDepartment,
  resolveStoreDepartmentForWrite,
} from "../modules/merchants/store-department.logic.js";
import { browseResponseCacheKey } from "../modules/merchants/merchants.controller.js";
import { merchantBrowseCacheKey } from "../modules/merchants/merchants.repo.js";

test("only fashion/clothing activity requires a department", () => {
  assert.equal(activityRequiresDepartment("fashion_clothing"), true);
  assert.equal(activityRequiresDepartment("clothing"), true);
  assert.equal(activityRequiresDepartment("men_fashion"), true);
  assert.equal(activityRequiresDepartment("restaurant"), false);
  assert.equal(activityRequiresDepartment("electronics"), false);
  assert.equal(activityRequiresDepartment("pharmacy"), false);
});

test("fashion store creation without a department is rejected", () => {
  for (const empty of [undefined, null, ""]) {
    assert.throws(
      () => resolveStoreDepartmentForWrite({ activityType: "fashion_clothing", department: empty }),
      (error) => {
        assert.equal(error.message, "VALIDATION_ERROR");
        assert.equal(error.status, 400);
        assert.equal(error.details.fields.department, "DEPARTMENT_REQUIRED");
        return true;
      }
    );
  }
});

test("fashion store creation with men / women works (aliases normalized)", () => {
  assert.equal(resolveStoreDepartmentForWrite({ activityType: "fashion_clothing", department: "men" }), "men");
  assert.equal(resolveStoreDepartmentForWrite({ activityType: "fashion_clothing", department: "women" }), "women");
  assert.equal(resolveStoreDepartmentForWrite({ activityType: "fashion_clothing", department: "رجالي" }), "men");
  assert.equal(resolveStoreDepartmentForWrite({ activityType: "fashion_clothing", department: "نسائي" }), "women");
  assert.equal(resolveStoreDepartmentForWrite({ activityType: "fashion_clothing", department: "unisex" }), "unisex");
});

test("invalid or needs_review department values are rejected for fashion", () => {
  for (const bad of ["kids", "xyz", "needs_review"]) {
    assert.throws(
      () => resolveStoreDepartmentForWrite({ activityType: "fashion_clothing", department: bad }),
      (error) => {
        assert.equal(error.message, "VALIDATION_ERROR");
        assert.equal(error.details.fields.department, "INVALID_DEPARTMENT");
        return true;
      }
    );
  }
});

test("restaurant / non-fashion stores do NOT require a department", () => {
  assert.equal(resolveStoreDepartmentForWrite({ activityType: "restaurant", department: undefined }), null);
  assert.equal(resolveStoreDepartmentForWrite({ activityType: "electronics", department: "men" }), null);
});

test("customer section matching: men/women only, unisex in both, needs_review/null hidden", () => {
  // Men section
  assert.equal(departmentMatchesSection("men", "men"), true);
  assert.equal(departmentMatchesSection("women", "men"), false);
  assert.equal(departmentMatchesSection("unisex", "men"), true);
  // Women section
  assert.equal(departmentMatchesSection("women", "women"), true);
  assert.equal(departmentMatchesSection("men", "women"), false);
  assert.equal(departmentMatchesSection("unisex", "women"), true);
  // Never shown in a customer section
  assert.equal(departmentMatchesSection("needs_review", "men"), false);
  assert.equal(departmentMatchesSection("needs_review", "women"), false);
  assert.equal(departmentMatchesSection(null, "men"), false);
  assert.equal(departmentMatchesSection(undefined, "women"), false);
  // Only men/women are valid target sections
  assert.equal(departmentMatchesSection("men", "unisex"), false);
  assert.equal(departmentMatchesSection("men", "kids"), false);
});

test("normalizeStoreDepartment maps aliases", () => {
  assert.equal(normalizeStoreDepartment("mens"), "men");
  assert.equal(normalizeStoreDepartment("womens"), "women");
  assert.equal(normalizeStoreDepartment("men_fashion"), "men");
  assert.equal(normalizeStoreDepartment("women_fashion"), "women");
  assert.equal(normalizeStoreDepartment("both"), "unisex");
  assert.equal(normalizeStoreDepartment("garbage"), null);
});

test("keyword inference is conservative (single-gender only)", () => {
  assert.equal(inferDepartmentFromText("متجر أزياء نسائية"), "women");
  assert.equal(inferDepartmentFromText("Men's Gents Fashion"), "men");
  assert.equal(inferDepartmentFromText("ملابس رجالية ونسائية"), null); // both -> unknown
  assert.equal(inferDepartmentFromText("General Store"), null); // neither
});

test("merchant browse cache keys separate men and women sections", () => {
  const menKey = merchantBrowseCacheKey({
    version: "1",
    type: "all",
    search: null,
    activityType: "fashion_clothing",
    discoverySubcategory: null,
    department: "men",
  });
  const womenKey = merchantBrowseCacheKey({
    version: "1",
    type: "all",
    search: null,
    activityType: "fashion_clothing",
    discoverySubcategory: null,
    department: "women",
  });

  assert.notEqual(menKey, womenKey);
  assert.match(menKey, /department:men/);
  assert.match(womenKey, /department:women/);
});

test("public browse response cache keys separate men and women sections", () => {
  const menKey = browseResponseCacheKey({
    activityType: "fashion_clothing",
    department: "men",
  });
  const womenKey = browseResponseCacheKey({
    activityType: "fashion_clothing",
    department: "women",
  });

  assert.notEqual(menKey, womenKey);
  assert.match(menKey, /men/);
  assert.match(womenKey, /women/);
});

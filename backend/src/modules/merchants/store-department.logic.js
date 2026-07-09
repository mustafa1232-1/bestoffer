import { AppError } from "../../shared/utils/errors.js";

/**
 * Pure helpers for the store department / gender section used by the Fashion
 * Market (نسائي / رجالي). No DB access here so the rules are unit-testable.
 *
 * - Only fashion/clothing stores require a department.
 * - Customer-selectable departments are men / women (a store that sells both
 *   can be 'unisex' and appears in both sections).
 * - 'needs_review' is an admin/legacy backfill state — never a valid explicit
 *   choice at write time, and never shown in the customer sections.
 */

export const FASHION_ACTIVITY_TYPE = "fashion_clothing";

export const STORE_DEPARTMENTS = Object.freeze([
  "men",
  "women",
  "unisex",
  "needs_review",
]);

// The two top-level choices the customer sees first in the Fashion Market.
export const CUSTOMER_FASHION_DEPARTMENTS = Object.freeze(["women", "men"]);

const FASHION_ACTIVITY_ALIASES = new Set([
  "fashion",
  "clothes",
  "clothing",
  "style",
  "women_fashion",
  "men_fashion",
  "fashion_clothing",
]);

export function isFashionActivity(activityType) {
  const value = String(activityType || "").trim().toLowerCase();
  return FASHION_ACTIVITY_ALIASES.has(value);
}

export function activityRequiresDepartment(activityType) {
  return isFashionActivity(activityType);
}

export function normalizeStoreDepartment(value) {
  const v = String(value || "").trim().toLowerCase();
  if (!v) return null;
  if (["women", "womens", "women_fashion", "ladies", "female", "نسائي", "نسائية"].includes(v)) {
    return "women";
  }
  if (["men", "mens", "men_fashion", "gents", "male", "رجالي", "رجالية"].includes(v)) {
    return "men";
  }
  if (["unisex", "both", "mixed", "كلاهما"].includes(v)) return "unisex";
  if (["needs_review", "unclassified", "review"].includes(v)) return "needs_review";
  return null;
}

/**
 * Validates + normalizes the department for a create/update write.
 * - Non-fashion activity: department is not required and is ignored (returns null).
 * - Fashion activity: a valid customer department (men/women/unisex) is REQUIRED.
 *   Missing -> DEPARTMENT_REQUIRED; invalid/needs_review -> INVALID_DEPARTMENT.
 */
export function resolveStoreDepartmentForWrite({ activityType, department } = {}) {
  if (!activityRequiresDepartment(activityType)) {
    return null;
  }
  if (department == null || String(department).trim() === "") {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: { department: "DEPARTMENT_REQUIRED" } },
    });
  }
  const normalized = normalizeStoreDepartment(department);
  if (normalized == null || normalized === "needs_review") {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: { department: "INVALID_DEPARTMENT" } },
    });
  }
  return normalized;
}

/**
 * Customer-facing department filter for listing: a store is in the selected
 * section if its department matches OR it is unisex. `needs_review` and NULL
 * never match a customer section.
 */
export function departmentMatchesSection(storeDepartment, section) {
  const dept = normalizeStoreDepartment(storeDepartment);
  const target = normalizeStoreDepartment(section);
  if (target !== "men" && target !== "women") return false;
  if (dept == null || dept === "needs_review") return false;
  return dept === target || dept === "unisex";
}

/** Conservative keyword inference (AR + EN) used by backfill tooling / tests. */
export function inferDepartmentFromText(text) {
  const v = String(text || "").toLowerCase();
  const women = /(نساء|نسائي|نسائية|بناتي|women|woman|ladies|female|فساتين|عبايات)/.test(v);
  const men = /(رجال|رجالي|رجالية|men|man|gents|male|بدلات)/.test(v);
  if (women && !men) return "women";
  if (men && !women) return "men";
  return null;
}

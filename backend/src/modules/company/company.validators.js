function isNonEmptyString(value, max = 255) {
  return typeof value === "string" && value.trim().length > 0 && value.trim().length <= max;
}

function isOptionalString(value, max = 1000) {
  return (
    value === undefined ||
    value === null ||
    (typeof value === "string" && value.trim().length <= max)
  );
}

function isPositiveInt(value) {
  const n = Number(value);
  return Number.isInteger(n) && n > 0;
}

function isOptionalPositiveInt(value) {
  return value === undefined || value === null || value === "" || isPositiveInt(value);
}

function isValidNumber(value) {
  if (value === undefined || value === null || value === "") return false;
  const n = Number(value);
  return Number.isFinite(n);
}

function isOptionalBool(value) {
  return value === undefined || typeof value === "boolean";
}

function isIsoDate(value) {
  if (value === undefined || value === null || value === "") return true;
  const d = new Date(value);
  return !Number.isNaN(d.getTime());
}

export function validateCompanyCreate(body = {}) {
  const errors = [];
  if (!isNonEmptyString(body.name, 180)) errors.push("name");
  if (!isOptionalString(body.legalName, 220)) errors.push("legalName");
  if (!isOptionalString(body.brandName, 220)) errors.push("brandName");
  if (!isOptionalString(body.code, 40)) errors.push("code");
  if (!isOptionalString(body.contactPhone, 30)) errors.push("contactPhone");
  if (!isOptionalString(body.contactEmail, 180)) errors.push("contactEmail");
  if (!isOptionalString(body.logoUrl, 1000)) errors.push("logoUrl");
  if (!isOptionalString(body.summary, 4000)) errors.push("summary");
  if (!isOptionalString(body.businessType, 80)) errors.push("businessType");
  if (!isOptionalString(body.headquartersAddress, 240)) errors.push("headquartersAddress");
  if (!isOptionalString(body.primaryContactName, 180)) errors.push("primaryContactName");
  if (!isOptionalString(body.supportPhone, 30)) errors.push("supportPhone");
  if (!isOptionalString(body.websiteUrl, 1000)) errors.push("websiteUrl");
  if (!isOptionalString(body.registrationNumber, 80)) errors.push("registrationNumber");
  if (!isOptionalString(body.taxNumber, 80)) errors.push("taxNumber");
  if (!isOptionalString(body.notes, 2000)) errors.push("notes");
  return { ok: errors.length === 0, errors };
}

export function validateCompanyPatch(body = {}) {
  const errors = [];
  if (body.name !== undefined && !isNonEmptyString(body.name, 180)) errors.push("name");
  if (body.legalName !== undefined && !isOptionalString(body.legalName, 220)) errors.push("legalName");
  if (body.brandName !== undefined && !isOptionalString(body.brandName, 220)) errors.push("brandName");
  if (body.code !== undefined && !isOptionalString(body.code, 40)) errors.push("code");
  if (body.contactPhone !== undefined && !isOptionalString(body.contactPhone, 30)) errors.push("contactPhone");
  if (body.contactEmail !== undefined && !isOptionalString(body.contactEmail, 180)) errors.push("contactEmail");
  if (body.logoUrl !== undefined && !isOptionalString(body.logoUrl, 1000)) errors.push("logoUrl");
  if (body.summary !== undefined && !isOptionalString(body.summary, 4000)) errors.push("summary");
  if (body.businessType !== undefined && !isOptionalString(body.businessType, 80)) errors.push("businessType");
  if (body.headquartersAddress !== undefined && !isOptionalString(body.headquartersAddress, 240)) errors.push("headquartersAddress");
  if (body.primaryContactName !== undefined && !isOptionalString(body.primaryContactName, 180)) errors.push("primaryContactName");
  if (body.supportPhone !== undefined && !isOptionalString(body.supportPhone, 30)) errors.push("supportPhone");
  if (body.websiteUrl !== undefined && !isOptionalString(body.websiteUrl, 1000)) errors.push("websiteUrl");
  if (body.registrationNumber !== undefined && !isOptionalString(body.registrationNumber, 80)) errors.push("registrationNumber");
  if (body.taxNumber !== undefined && !isOptionalString(body.taxNumber, 80)) errors.push("taxNumber");
  if (body.notes !== undefined && !isOptionalString(body.notes, 2000)) errors.push("notes");
  if (body.status !== undefined && !isOptionalString(body.status, 24)) errors.push("status");
  return { ok: errors.length === 0, errors };
}

export function validateCompanyUserCreate(body = {}) {
  const errors = [];
  if (!isNonEmptyString(body.fullName, 180)) errors.push("fullName");
  if (!isNonEmptyString(body.phone, 30)) errors.push("phone");
  if (!isNonEmptyString(body.pin, 20)) errors.push("pin");
  if (
    !["company_owner", "company_manager", "finance_viewer", "operations_viewer"].includes(
      String(body.role || "").trim()
    )
  ) {
    errors.push("role");
  }
  if (!isOptionalString(body.workTitle, 160)) errors.push("workTitle");
  if (!isOptionalString(body.workCompany, 180)) errors.push("workCompany");
  return { ok: errors.length === 0, errors };
}

export function validateBranchRequestCreate(body = {}) {
  const errors = [];
  if (!isNonEmptyString(body.name, 180)) errors.push("name");
  if (!["restaurant", "market"].includes(String(body.type || "").trim())) {
    errors.push("type");
  }
  if (!isOptionalString(body.description, 1200)) errors.push("description");
  if (!isOptionalString(body.phone, 30)) errors.push("phone");
  if (!isOptionalString(body.imageUrl, 1000)) errors.push("imageUrl");
  if (!isOptionalString(body.tagline, 160)) errors.push("tagline");
  if (!isOptionalString(body.workingHours, 160)) errors.push("workingHours");
  if (!isOptionalString(body.serviceAreaNote, 240)) errors.push("serviceAreaNote");
  if (!isOptionalString(body.branchLocationLabel, 180)) errors.push("branchLocationLabel");
  if (!isNonEmptyString(body.ownerFullName, 180)) errors.push("ownerFullName");
  if (!isNonEmptyString(body.ownerPhone, 30)) errors.push("ownerPhone");
  if (!isNonEmptyString(body.ownerPin, 20)) errors.push("ownerPin");
  if (!isNonEmptyString(body.ownerBlock, 20)) errors.push("ownerBlock");
  if (!isNonEmptyString(body.ownerBuildingNumber, 20)) errors.push("ownerBuildingNumber");
  if (!isNonEmptyString(body.ownerApartment, 20)) errors.push("ownerApartment");
  return { ok: errors.length === 0, errors };
}

export function validateProductCopy(body = {}) {
  const errors = [];
  if (!isPositiveInt(body.sourceMerchantId)) errors.push("sourceMerchantId");
  if (!Array.isArray(body.targetMerchantIds) || body.targetMerchantIds.length === 0) {
    errors.push("targetMerchantIds");
  }
  if (
    Array.isArray(body.targetMerchantIds) &&
    !body.targetMerchantIds.every(isPositiveInt)
  ) {
    errors.push("targetMerchantIds");
  }
  if (
    body.productIds !== undefined &&
    (!Array.isArray(body.productIds) || !body.productIds.every(isPositiveInt))
  ) {
    errors.push("productIds");
  }
  if (
    !["skip", "update", "duplicate"].includes(
      String(body.conflictStrategy || "skip").trim().toLowerCase()
    )
  ) {
    errors.push("conflictStrategy");
  }
  if (!isOptionalBool(body.copyImages)) errors.push("copyImages");
  if (!isOptionalBool(body.copyPrices)) errors.push("copyPrices");
  return { ok: errors.length === 0, errors };
}

export function validateCompanyCouponCreate(body = {}) {
  const errors = [];
  if (!isNonEmptyString(body.code, 50)) errors.push("code");
  if (!isOptionalString(body.description, 1000)) errors.push("description");
  if (!["percent", "fixed"].includes(String(body.discountType || "").trim())) {
    errors.push("discountType");
  }
  if (!isValidNumber(body.discountValue) || Number(body.discountValue) <= 0) {
    errors.push("discountValue");
  }
  if (String(body.discountType || "").trim() === "percent" && Number(body.discountValue) > 100) {
    errors.push("discountValue");
  }
  if (!isOptionalPositiveInt(body.maxUses)) errors.push("maxUses");
  if (!isIsoDate(body.validFrom)) errors.push("validFrom");
  if (!isIsoDate(body.validUntil)) errors.push("validUntil");
  if (!isOptionalBool(body.appliesToAllBranches)) errors.push("appliesToAllBranches");
  if (
    body.targetMerchantIds !== undefined &&
    (!Array.isArray(body.targetMerchantIds) || !body.targetMerchantIds.every(isPositiveInt))
  ) {
    errors.push("targetMerchantIds");
  }
  return { ok: errors.length === 0, errors };
}

export function validateCompanyCampaignCreate(body = {}) {
  const errors = [];
  if (!isNonEmptyString(body.title, 160)) errors.push("title");
  if (!isOptionalString(body.description, 600)) errors.push("description");
  if (
    !["percentage", "fixed_amount", "buy_x_get_y"].includes(
      String(body.offerType || "").trim()
    )
  ) {
    errors.push("offerType");
  }
  if (!isIsoDate(body.startsAt)) errors.push("startsAt");
  if (!isIsoDate(body.endsAt)) errors.push("endsAt");
  if (!isOptionalBool(body.appliesToAllBranches)) errors.push("appliesToAllBranches");
  if (
    body.targetMerchantIds !== undefined &&
    (!Array.isArray(body.targetMerchantIds) || !body.targetMerchantIds.every(isPositiveInt))
  ) {
    errors.push("targetMerchantIds");
  }
  if (
    body.offerType === "percentage" || body.offerType === "fixed_amount"
  ) {
    if (!isValidNumber(body.discountValue) || Number(body.discountValue) <= 0) {
      errors.push("discountValue");
    }
  }
  if (body.offerType === "percentage" && Number(body.discountValue) > 100) {
    errors.push("discountValue");
  }
  if (body.offerType === "buy_x_get_y") {
    if (!isPositiveInt(body.buyQuantity)) errors.push("buyQuantity");
    if (!isPositiveInt(body.getQuantity)) errors.push("getQuantity");
  }
  return { ok: errors.length === 0, errors };
}

export function validateInventoryItemPatch(body = {}) {
  const errors = [];
  if (!isOptionalPositiveInt(body.quantity) && body.quantity !== 0) errors.push("quantity");
  if (!isOptionalPositiveInt(body.reorderThreshold) && body.reorderThreshold !== 0) {
    errors.push("reorderThreshold");
  }
  if (!isOptionalBool(body.manualDisabled)) errors.push("manualDisabled");
  return { ok: errors.length === 0, errors };
}

export function validateInventorySettingsPatch(body = {}) {
  const errors = [];
  if (!isOptionalBool(body.inventoryEnabled)) errors.push("inventoryEnabled");
  if (
    body.dailyUpdateMode !== undefined &&
    !["strict_daily", "soft_reminder", "manual_override"].includes(
      String(body.dailyUpdateMode || "").trim()
    )
  ) {
    errors.push("dailyUpdateMode");
  }
  if (!isOptionalPositiveInt(body.lowStockThreshold) && body.lowStockThreshold !== 0) {
    errors.push("lowStockThreshold");
  }
  if (!isOptionalBool(body.autoDisableOutOfStock)) errors.push("autoDisableOutOfStock");
  if (!isOptionalBool(body.showAllWithoutAutoDisable)) {
    errors.push("showAllWithoutAutoDisable");
  }
  return { ok: errors.length === 0, errors };
}

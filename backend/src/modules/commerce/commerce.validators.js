function toOptionalString(value, max = 4000) {
  if (value == null) return null;
  const text = String(value).trim();
  if (!text) return null;
  return text.slice(0, max);
}

function toPositiveInt(value) {
  const n = Number(value);
  if (!Number.isInteger(n) || n <= 0) return null;
  return n;
}

function toOptionalPositiveInt(value) {
  if (value == null || value === "") return null;
  return toPositiveInt(value);
}

function toNonNegativeInt(value) {
  const n = Number(value);
  if (!Number.isInteger(n) || n < 0) return null;
  return n;
}

function toOptionalNonNegativeInt(value) {
  if (value == null || value === "") return null;
  return toNonNegativeInt(value);
}

function toOptionalNumber(value) {
  if (value == null || value === "") return null;
  const normalized = String(value)
    .trim()
    .replace(/[\u0660-\u0669]/g, (m) => String(m.charCodeAt(0) - 1632))
    .replace(/[\u06F0-\u06F9]/g, (m) => String(m.charCodeAt(0) - 1776))
    .replace(/,/g, "");
  const n = Number(normalized);
  if (!Number.isFinite(n)) return null;
  return n;
}

function toOptionalDateIso(value) {
  if (value == null || value === "") return null;
  const raw = String(value).trim();
  if (!raw) return null;
  const parsed = new Date(raw);
  if (Number.isNaN(parsed.getTime())) return null;
  return parsed.toISOString();
}

function toOptionalBoolean(value) {
  if (typeof value === "boolean") return value;
  if (typeof value !== "string") return null;
  const normalized = value.trim().toLowerCase();
  if (["1", "true", "yes", "on"].includes(normalized)) return true;
  if (["0", "false", "no", "off"].includes(normalized)) return false;
  return null;
}

function toOptionalStringArray(value, { maxItems = 500, maxLen = 120 } = {}) {
  if (value == null) return [];
  if (!Array.isArray(value)) return null;
  const out = [];
  for (const item of value.slice(0, maxItems)) {
    const text = toOptionalString(item, maxLen);
    if (text == null) return null;
    out.push(text);
  }
  return out;
}

function toOptionalPositiveIntArray(value, { maxItems = 500 } = {}) {
  if (value == null) return [];
  if (!Array.isArray(value)) return null;
  const out = [];
  for (const item of value.slice(0, maxItems)) {
    const parsed = toPositiveInt(item);
    if (parsed == null) return null;
    out.push(parsed);
  }
  return out;
}

function toOptionalObject(value) {
  if (value == null) return null;
  if (typeof value !== "object" || Array.isArray(value)) return null;
  return value;
}

function errorField(fields, field, condition) {
  if (!condition) fields.push(field);
}

export function parseOrderId(params) {
  const orderId = toPositiveInt(params?.orderId);
  return {
    ok: orderId != null,
    errors: orderId != null ? [] : ["orderId"],
    value: orderId,
  };
}

export function validateOwnerStartPreparing(body = {}) {
  const errors = [];
  const preferredCourierUserId = toOptionalPositiveInt(body.preferredCourierUserId);
  const estimatedPrepMinutes = toOptionalPositiveInt(body.estimatedPrepMinutes);
  const note = toOptionalString(body.note, 1200);

  if (body.preferredCourierUserId != null && preferredCourierUserId == null) {
    errors.push("preferredCourierUserId");
  }
  if (body.estimatedPrepMinutes != null && estimatedPrepMinutes == null) {
    errors.push("estimatedPrepMinutes");
  }
  if (body.note != null && note == null) {
    errors.push("note");
  }

  return {
    ok: errors.length === 0,
    errors,
    data: { preferredCourierUserId, estimatedPrepMinutes, note },
  };
}

export function validateOwnerAssignCourier(body = {}) {
  const errors = [];
  const courierUserId = toPositiveInt(body.courierUserId);
  const assignmentMode = toOptionalString(body.assignmentMode, 30) || "manual";
  const note = toOptionalString(body.note, 1200);

  errorField(errors, "courierUserId", courierUserId != null);
  errorField(
    errors,
    "assignmentMode",
    ["manual", "broadcast", "admin_selected", "store_selected"].includes(
      String(assignmentMode).toLowerCase()
    )
  );

  return {
    ok: errors.length === 0,
    errors,
    data: {
      courierUserId,
      assignmentMode: String(assignmentMode).toLowerCase(),
      note,
    },
  };
}

export function validateReadyForPickup(body = {}) {
  const errors = [];
  const estimatedDeliveryMinutes = toOptionalPositiveInt(body.estimatedDeliveryMinutes);
  const note = toOptionalString(body.note, 1200);

  if (body.estimatedDeliveryMinutes != null && estimatedDeliveryMinutes == null) {
    errors.push("estimatedDeliveryMinutes");
  }

  return {
    ok: errors.length === 0,
    errors,
    data: {
      estimatedDeliveryMinutes,
      note,
    },
  };
}

export function validateCourierAction(body = {}) {
  const note = toOptionalString(body.note, 1200);
  return { ok: true, errors: [], data: { note } };
}

export function validateOrderChatMessage(body = {}) {
  const message = toOptionalString(body.message, 4000);
  return {
    ok: message != null,
    errors: message != null ? [] : ["message"],
    data: { message },
  };
}

export function validateCourierCancelRequest(body = {}) {
  const reasonCode =
    body?.reasonCode == null ? null : toOptionalString(body.reasonCode, 64);
  const legacyReason = toOptionalString(body.reason, 2000);
  const reasonText = toOptionalString(body.reasonText, 2000);
  const normalizedCode =
    reasonCode == null
      ? legacyReason != null
        ? "other"
        : null
      : String(reasonCode).toLowerCase();
  const normalizedText = reasonText ?? legacyReason;
  return {
    ok:
      normalizedCode != null &&
      (normalizedCode !== "other" || normalizedText != null),
    errors:
      normalizedCode == null
        ? ["reasonCode"]
        : normalizedCode === "other" && normalizedText == null
        ? ["reasonText"]
        : [],
    data: { reasonCode: normalizedCode, reasonText: normalizedText },
  };
}

export function validateCancelRequestReview(body = {}) {
  const errors = [];
  const approved = toOptionalBoolean(body.approved);
  const reviewNote = toOptionalString(body.reviewNote, 2000);
  if (approved == null) errors.push("approved");
  return {
    ok: errors.length === 0,
    errors,
    data: {
      approved: approved === true,
      reviewNote,
    },
  };
}

export function validateMerchantCourierUpsert(body = {}) {
  const errors = [];
  const deliveryUserId = toOptionalPositiveInt(body.deliveryUserId);
  const vehicleType = toOptionalString(body.vehicleType, 60);
  const coverageBlock = toOptionalString(body.coverageBlock, 30);

  if (body.deliveryUserId != null && deliveryUserId == null) errors.push("deliveryUserId");

  return {
    ok: errors.length === 0,
    errors,
    data: {
      deliveryUserId,
      vehicleType,
      coverageBlock,
    },
  };
}

export function validateMerchantCourierPatch(body = {}) {
  const errors = [];
  const isActive = toOptionalBoolean(body.isActive);
  const availabilityStatus = toOptionalString(body.availabilityStatus, 20);
  const vehicleType = toOptionalString(body.vehicleType, 60);

  if (body.isActive != null && isActive == null) errors.push("isActive");

  return {
    ok: errors.length === 0,
    errors,
    data: {
      isActive,
      availabilityStatus,
      vehicleType,
    },
  };
}

export function validatePaymentRequest(body = {}) {
  const errors = [];
  const requestType = toOptionalString(body.requestType, 40) || "store_pays_app";
  const paymentScope = toOptionalString(body.paymentScope, 20) || "all";
  const amount = toOptionalNumber(body.amount);
  const note = toOptionalString(body.note, 1200);
  const proofFileUrl = toOptionalString(body.proofFileUrl, 2000);
  const paymentMethod = toOptionalString(body.paymentMethod, 40);
  const paymentMethodOther = toOptionalString(body.paymentMethodOther, 120);
  const paymentDate = toOptionalDateIso(body.paymentDate ?? body.paymentAt);
  const referenceCode = toOptionalString(body.referenceCode, 120);
  const receiverName = toOptionalString(body.receiverName, 160);
  const selectionMode = toOptionalString(body.selectionMode, 40);
  const selectedInvoiceIds = toOptionalPositiveIntArray(body.selectedInvoiceIds);
  const targetAmount = toOptionalNumber(body.targetAmount);
  const confirmedAdjustedAmount = toOptionalNumber(body.confirmedAdjustedAmount);
  const selectionMeta = toOptionalObject(body.selectionMeta);
  const allowedPaymentMethods = [
    "cash",
    "bank_transfer",
    "zain_cash",
    "asiacell_cash",
    "manual_handover",
    "other",
  ];
  const normalizedRequestType = requestType.toLowerCase();
  const normalizedPaymentScope = paymentScope.toLowerCase();
  const normalizedSelectionMode =
    normalizedRequestType === "store_pays_app"
      ? (selectionMode || "all_invoices").toLowerCase()
      : null;

  errorField(
    errors,
    "requestType",
    ["store_pays_app", "app_pays_store"].includes(requestType.toLowerCase())
  );
  errorField(
    errors,
    "paymentScope",
    ["commission", "delivery", "service", "all"].includes(
      normalizedPaymentScope
    )
  );
  if (
    normalizedRequestType === "app_pays_store" &&
    !(amount != null && amount > 0)
  ) {
    errors.push("amount");
  }
  if (
    paymentMethod != null &&
    !allowedPaymentMethods.includes(paymentMethod.toLowerCase())
  ) {
    errors.push("paymentMethod");
  }
  if (
    paymentMethod != null &&
    paymentMethod.toLowerCase() === "other" &&
    paymentMethodOther == null
  ) {
    errors.push("paymentMethodOther");
  }
  if (body.paymentDate != null && paymentDate == null) {
    errors.push("paymentDate");
  }
  if (body.paymentAt != null && paymentDate == null) {
    errors.push("paymentAt");
  }
  if (body.selectedInvoiceIds != null && selectedInvoiceIds == null) {
    errors.push("selectedInvoiceIds");
  }
  if (body.selectionMeta != null && selectionMeta == null) {
    errors.push("selectionMeta");
  }
  if (
    normalizedRequestType === "store_pays_app" &&
    !["all_invoices", "manual_selection", "auto_match_amount"].includes(
      normalizedSelectionMode
    )
  ) {
    errors.push("selectionMode");
  }
  if (
    normalizedRequestType === "store_pays_app" &&
    normalizedSelectionMode === "manual_selection" &&
    (!selectedInvoiceIds || selectedInvoiceIds.length === 0)
  ) {
    errors.push("selectedInvoiceIds");
  }
  if (
    normalizedRequestType === "store_pays_app" &&
    normalizedSelectionMode === "auto_match_amount" &&
    !(targetAmount != null && targetAmount > 0)
  ) {
    errors.push("targetAmount");
  }
  if (
    normalizedRequestType === "store_pays_app" &&
    normalizedSelectionMode === "all_invoices" &&
    body.amount == null &&
    !(targetAmount != null && targetAmount > 0)
  ) {
    // amount can be derived server-side, but the client must send some intention
    // metadata or accept the derived total.
  }

  return {
    ok: errors.length === 0,
    errors,
    data: {
      requestType: normalizedRequestType,
      paymentScope: normalizedPaymentScope,
      amount,
      note,
      proofFileUrl,
      paymentMethod: paymentMethod == null ? null : paymentMethod.toLowerCase(),
      paymentMethodOther,
      paymentDate,
      referenceCode,
      receiverName,
      selectionMode: normalizedSelectionMode,
      selectedInvoiceIds: selectedInvoiceIds ?? [],
      targetAmount,
      confirmedAdjustedAmount,
      selectionMeta: selectionMeta ?? null,
    },
  };
}

export function validatePaymentRequestListQuery(query = {}) {
  const errors = [];
  const requestType = toOptionalString(query.requestType, 40);
  const status = toOptionalString(query.status, 40);
  const limit = toOptionalPositiveInt(query.limit) ?? 100;
  const offset = toOptionalPositiveInt(query.offset) ?? 0;
  if (
    requestType != null &&
    !["store_pays_app", "app_pays_store"].includes(requestType.toLowerCase())
  ) {
    errors.push("requestType");
  }
  return {
    ok: errors.length === 0,
    errors,
    data: {
      requestType: requestType == null ? null : requestType.toLowerCase(),
      status: status == null ? null : status.toLowerCase(),
      limit: Math.min(limit, 300),
      offset: Number(offset) || 0,
    },
  };
}

export function validateAdminFinancialWindowQuery(query = {}) {
  const errors = [];
  const periodRaw = toOptionalString(query.period, 20) || "day";
  const period = periodRaw.toLowerCase();
  const from = toOptionalDateIso(query.from);
  const to = toOptionalDateIso(query.to);
  const search = toOptionalString(query.search, 140);
  const limit = toOptionalPositiveInt(query.limit) ?? 120;
  const offset = Number.isFinite(Number(query.offset))
    ? Math.max(0, Number(query.offset))
    : 0;

  if (!["all", "day", "yesterday", "week", "month", "year", "custom"].includes(period)) {
    errors.push("period");
  }
  if (period === "custom") {
    if (!from) errors.push("from");
    if (!to) errors.push("to");
    if (from && to && new Date(from).getTime() > new Date(to).getTime()) {
      errors.push("dateRange");
    }
  }

  return {
    ok: errors.length === 0,
    errors,
    data: {
      period,
      from,
      to,
      search,
      limit: Math.min(limit, 500),
      offset,
    },
  };
}

export function validateAdminMerchantFinancialDetailsQuery(query = {}) {
  const errors = [];
  const base = validateAdminFinancialWindowQuery(query);
  const limit = toOptionalPositiveInt(query.limit) ?? 100;
  const offset = Number.isFinite(Number(query.offset))
    ? Math.max(0, Number(query.offset))
    : 0;
  const onlyOpen =
    query.onlyOpen == null ? undefined : toOptionalBoolean(query.onlyOpen);

  if (!base.ok) {
    errors.push(...base.errors);
  }
  if (query.onlyOpen != null && onlyOpen == null) {
    errors.push("onlyOpen");
  }

  return {
    ok: errors.length === 0,
    errors,
    data: {
      ...base.data,
      limit: Math.min(limit, 500),
      offset,
      onlyOpen,
    },
  };
}

export function validateMerchantPaymentRequestPatch(body = {}) {
  const errors = [];
  const paymentScope = toOptionalString(body.paymentScope, 20);
  const amount = toOptionalNumber(body.amount);
  const note = toOptionalString(body.note, 1200);
  const proofFileUrl = toOptionalString(body.proofFileUrl, 2000);
  const paymentMethod = toOptionalString(body.paymentMethod, 40);
  const paymentMethodOther = toOptionalString(body.paymentMethodOther, 120);
  const paymentDate = toOptionalDateIso(body.paymentDate ?? body.paymentAt);
  const referenceCode = toOptionalString(body.referenceCode, 120);
  const receiverName = toOptionalString(body.receiverName, 160);
  const resubmit = toOptionalBoolean(body.resubmit);
  const selectionMode = toOptionalString(body.selectionMode, 40);
  const selectedInvoiceIds = toOptionalPositiveIntArray(body.selectedInvoiceIds);
  const targetAmount = toOptionalNumber(body.targetAmount);
  const confirmedAdjustedAmount = toOptionalNumber(body.confirmedAdjustedAmount);
  const selectionMeta = toOptionalObject(body.selectionMeta);
  const allowedPaymentMethods = [
    "cash",
    "bank_transfer",
    "zain_cash",
    "asiacell_cash",
    "manual_handover",
    "other",
  ];

  if (
    paymentScope != null &&
    !["commission", "delivery", "service", "all"].includes(paymentScope.toLowerCase())
  ) {
    errors.push("paymentScope");
  }
  if (body.amount != null && !(amount != null && amount > 0)) {
    errors.push("amount");
  }
  if (body.paymentDate != null && paymentDate == null) {
    errors.push("paymentDate");
  }
  if (body.paymentAt != null && paymentDate == null) {
    errors.push("paymentAt");
  }
  if (
    paymentMethod != null &&
    !allowedPaymentMethods.includes(paymentMethod.toLowerCase())
  ) {
    errors.push("paymentMethod");
  }
  if (
    paymentMethod != null &&
    paymentMethod.toLowerCase() === "other" &&
    paymentMethodOther == null
  ) {
    errors.push("paymentMethodOther");
  }
  if (body.resubmit != null && resubmit == null) {
    errors.push("resubmit");
  }
  if (
    selectionMode != null &&
    !["all_invoices", "manual_selection", "auto_match_amount"].includes(
      selectionMode.toLowerCase()
    )
  ) {
    errors.push("selectionMode");
  }
  if (body.selectedInvoiceIds != null && selectedInvoiceIds == null) {
    errors.push("selectedInvoiceIds");
  }
  if (body.selectionMeta != null && selectionMeta == null) {
    errors.push("selectionMeta");
  }
  if (
    selectionMode != null &&
    selectionMode.toLowerCase() === "manual_selection" &&
    (!selectedInvoiceIds || selectedInvoiceIds.length === 0)
  ) {
    errors.push("selectedInvoiceIds");
  }
  if (
    selectionMode != null &&
    selectionMode.toLowerCase() === "auto_match_amount" &&
    !(targetAmount != null && targetAmount > 0)
  ) {
    errors.push("targetAmount");
  }

  return {
    ok: errors.length === 0,
    errors,
    data: {
      paymentScope: paymentScope == null ? null : paymentScope.toLowerCase(),
      amount,
      note,
      proofFileUrl,
      paymentMethod,
      paymentMethodOther,
      paymentDate,
      referenceCode,
      receiverName,
      resubmit: resubmit === true,
      selectionMode: selectionMode == null ? null : selectionMode.toLowerCase(),
      selectedInvoiceIds: selectedInvoiceIds ?? [],
      targetAmount,
      confirmedAdjustedAmount,
      selectionMeta,
    },
  };
}

export function validatePaymentSelectionPreview(body = {}) {
  const errors = [];
  const selectionMode = toOptionalString(body.selectionMode, 40);
  const selectedInvoiceIds = toOptionalPositiveIntArray(body.selectedInvoiceIds);
  const targetAmount = toOptionalNumber(body.targetAmount);
  const confirmedAdjustedAmount = toOptionalNumber(body.confirmedAdjustedAmount);
  const amount = toOptionalNumber(body.amount);

  if (
    selectionMode == null ||
    !["all_invoices", "manual_selection", "auto_match_amount"].includes(
      selectionMode.toLowerCase()
    )
  ) {
    errors.push("selectionMode");
  }
  if (body.selectedInvoiceIds != null && selectedInvoiceIds == null) {
    errors.push("selectedInvoiceIds");
  }
  if (
    selectionMode != null &&
    selectionMode.toLowerCase() === "manual_selection" &&
    (!selectedInvoiceIds || selectedInvoiceIds.length === 0)
  ) {
    errors.push("selectedInvoiceIds");
  }
  if (
    selectionMode != null &&
    selectionMode.toLowerCase() === "auto_match_amount" &&
    !(targetAmount != null && targetAmount > 0)
  ) {
    errors.push("targetAmount");
  }
  if (
    selectionMode != null &&
    ["all_invoices", "manual_selection"].includes(selectionMode.toLowerCase()) &&
    body.amount != null &&
    !(amount != null && amount > 0)
  ) {
    errors.push("amount");
  }

  return {
    ok: errors.length === 0,
    errors,
    data: {
      selectionMode: selectionMode == null ? null : selectionMode.toLowerCase(),
      selectedInvoiceIds: selectedInvoiceIds ?? [],
      targetAmount,
      confirmedAdjustedAmount,
      amount,
    },
  };
}

export function validateMerchantPaymentRequestConfirm(body = {}) {
  const note = toOptionalString(body.note, 1200);
  return {
    ok: true,
    errors: [],
    data: { note },
  };
}

export function validateMerchantPaymentRequestIssue(body = {}) {
  const issueNote = toOptionalString(body.issueNote ?? body.note, 1600);
  return {
    ok: issueNote != null,
    errors: issueNote != null ? [] : ["issueNote"],
    data: { issueNote },
  };
}

export function validateAdminPaymentRequestApprove(body = {}) {
  const reviewNote = toOptionalString(body.reviewNote ?? body.note, 1600);
  const internalAdminNote = toOptionalString(body.internalAdminNote, 2000);
  return {
    ok: true,
    errors: [],
    data: {
      reviewNote,
      internalAdminNote,
    },
  };
}

export function validateAdminPaymentRequestAssign(body = {}) {
  const errors = [];
  const assignedToUserId = toOptionalPositiveInt(body.assignedToUserId);
  const assignedToName = toOptionalString(body.assignedToName, 160);
  const internalAdminNote = toOptionalString(body.internalAdminNote, 2000);
  const reviewNote = toOptionalString(body.reviewNote ?? body.note, 1600);

  if (body.assignedToUserId != null && assignedToUserId == null) {
    errors.push("assignedToUserId");
  }

  return {
    ok: errors.length === 0,
    errors,
    data: {
      assignedToUserId,
      assignedToName,
      internalAdminNote,
      reviewNote,
    },
  };
}

export function validateAdminPaymentRequestMarkPaid(body = {}) {
  const errors = [];
  const paidAmount = toOptionalNumber(body.paidAmount);
  const paymentMethod = toOptionalString(body.paymentMethod, 40);
  const paymentDate = toOptionalDateIso(body.paymentDate);
  const referenceCode = toOptionalString(body.referenceCode, 120);
  const paymentActorName = toOptionalString(body.paymentActorName, 160);
  const assignedToUserId = toOptionalPositiveInt(body.assignedToUserId);
  const assignedToName = toOptionalString(body.assignedToName, 160);
  const reviewNote = toOptionalString(body.reviewNote ?? body.note, 1600);
  const internalAdminNote = toOptionalString(body.internalAdminNote, 2000);

  if (body.paidAmount != null && !(paidAmount != null && paidAmount > 0)) {
    errors.push("paidAmount");
  }
  if (body.paymentDate != null && paymentDate == null) {
    errors.push("paymentDate");
  }
  if (body.assignedToUserId != null && assignedToUserId == null) {
    errors.push("assignedToUserId");
  }

  return {
    ok: errors.length === 0,
    errors,
    data: {
      paidAmount,
      paymentMethod,
      paymentDate,
      referenceCode,
      paymentActorName,
      assignedToUserId,
      assignedToName,
      reviewNote,
      internalAdminNote,
    },
  };
}

export function validateAdminPaymentRequestReturnForRevision(body = {}) {
  const reviewNote = toOptionalString(body.reviewNote ?? body.note, 1600);
  const internalAdminNote = toOptionalString(body.internalAdminNote, 2000);
  return {
    ok: true,
    errors: [],
    data: { reviewNote, internalAdminNote },
  };
}

export function validateAdminAppPayablesAdjustment(body = {}) {
  const errors = [];
  const amount = toOptionalNumber(body.amount);
  const direction = toOptionalString(body.direction, 20);
  const entryType = toOptionalString(body.entryType, 40) || "adjustment";
  const note = toOptionalString(body.note, 1600);
  const referenceCode = toOptionalString(body.referenceCode, 120);
  const orderId = toOptionalPositiveInt(body.orderId);

  if (!(amount != null && amount > 0)) {
    errors.push("amount");
  }
  if (
    direction == null ||
    !["debit", "credit"].includes(direction.toLowerCase())
  ) {
    errors.push("direction");
  }
  if (body.orderId != null && orderId == null) {
    errors.push("orderId");
  }

  return {
    ok: errors.length === 0,
    errors,
    data: {
      amount,
      direction: direction == null ? null : direction.toLowerCase(),
      entryType: entryType.toLowerCase(),
      note,
      referenceCode,
      orderId,
    },
  };
}

export function validateBillingProfilePatch(body = {}) {
  const errors = [];
  const commissionType = toOptionalString(body.commissionType, 20);
  const commissionValue = toOptionalNumber(body.commissionValue);
  const commissionRate = toOptionalNumber(body.commissionRate);
  const commissionModel = toOptionalString(body.commissionModel, 32);
  const monthlySubscriptionAmount = toOptionalNumber(body.monthlySubscriptionAmount);
  const serviceFeeType = toOptionalString(body.serviceFeeType, 30);
  const serviceFeeMode = toOptionalString(body.serviceFeeMode, 20);
  const serviceFeeValue = toOptionalNumber(body.serviceFeeValue);
  const deliveryFeeMode = toOptionalString(body.deliveryFeeMode, 20);
  const appDeliveryFeeValue = toOptionalNumber(body.appDeliveryFeeValue);
  const storeDeliveryFeeValue = toOptionalNumber(body.storeDeliveryFeeValue);
  const deliveryFeeValue = toOptionalNumber(body.deliveryFeeValue);
  const appDeliveryEnabled = toOptionalBoolean(body.appDeliveryEnabled);
  const merchantDeliveryEnabled = toOptionalBoolean(body.merchantDeliveryEnabled);
  const settlementCycle = toOptionalString(body.settlementCycle, 20);
  const distributionPolicy = toOptionalString(body.distributionPolicy, 40);
  const gracePeriodDays = toOptionalNonNegativeInt(body.gracePeriodDays);
  const effectiveFrom = toOptionalDateIso(body.effectiveFrom);

  if (
    commissionType &&
    !["percentage", "fixed"].includes(commissionType.toLowerCase())
  ) {
    errors.push("commissionType");
  }
  if (
    commissionModel &&
    !["percentage", "monthly_subscription"].includes(commissionModel.toLowerCase())
  ) {
    errors.push("commissionModel");
  }
  if (commissionRate != null && (commissionRate < 0 || commissionRate > 1)) {
    errors.push("commissionRate");
  }
  if (commissionValue != null && commissionValue < 0) {
    errors.push("commissionValue");
  }
  if (monthlySubscriptionAmount != null && monthlySubscriptionAmount < 0) {
    errors.push("monthlySubscriptionAmount");
  }
  if (
    serviceFeeType &&
    !["fixed", "percentage", "per_order", "global_rule"].includes(
      serviceFeeType.toLowerCase()
    )
  ) {
    errors.push("serviceFeeType");
  }
  if (serviceFeeMode && !["fixed", "percentage"].includes(serviceFeeMode.toLowerCase())) {
    errors.push("serviceFeeMode");
  }
  if (
    deliveryFeeMode &&
    !["app_defined", "store_defined", "dynamic", "fixed", "percentage"].includes(
      deliveryFeeMode.toLowerCase()
    )
  ) {
    errors.push("deliveryFeeMode");
  }
  if (serviceFeeValue != null && serviceFeeValue < 0) errors.push("serviceFeeValue");
  if (appDeliveryFeeValue != null && appDeliveryFeeValue < 0) {
    errors.push("appDeliveryFeeValue");
  }
  if (storeDeliveryFeeValue != null && storeDeliveryFeeValue < 0) {
    errors.push("storeDeliveryFeeValue");
  }
  if (deliveryFeeValue != null && deliveryFeeValue < 0) errors.push("deliveryFeeValue");
  if (body.gracePeriodDays != null && gracePeriodDays == null) errors.push("gracePeriodDays");
  if (body.effectiveFrom != null && effectiveFrom == null) errors.push("effectiveFrom");

  return {
    ok: errors.length === 0,
    errors,
    data: {
      commissionType: commissionType ? commissionType.toLowerCase() : null,
      commissionValue,
      commissionRate,
      commissionModel: commissionModel ? commissionModel.toLowerCase() : null,
      monthlySubscriptionAmount,
      serviceFeeType: serviceFeeType ? serviceFeeType.toLowerCase() : null,
      serviceFeeMode: serviceFeeMode ? serviceFeeMode.toLowerCase() : null,
      serviceFeeValue,
      deliveryFeeMode: deliveryFeeMode ? deliveryFeeMode.toLowerCase() : null,
      appDeliveryFeeValue,
      storeDeliveryFeeValue,
      deliveryFeeValue,
      appDeliveryEnabled,
      merchantDeliveryEnabled,
      settlementCycle,
      distributionPolicy,
      gracePeriodDays,
      effectiveFrom,
    },
  };
}

export function validateMerchantFinancialApprovalTerms(body = {}) {
  const normalizedBody = {
    commissionType: "percentage",
    commissionValue: 10,
    commissionModel: "percentage",
    monthlySubscriptionAmount: 0,
    serviceFeeType: "fixed",
    serviceFeeValue: 500,
    deliveryFeeMode: "dynamic",
    appDeliveryFeeValue: 1000,
    storeDeliveryFeeValue: 1000,
    effectiveFrom: new Date().toISOString(),
    ...(body && typeof body === "object" ? body : {}),
  };

  const base = validateBillingProfilePatch(normalizedBody);
  const errors = [...base.errors];
  const data = base.data;

  const requiredFields = [
    "commissionType",
    "commissionValue",
    "commissionModel",
    "monthlySubscriptionAmount",
    "serviceFeeType",
    "serviceFeeValue",
    "deliveryFeeMode",
    "appDeliveryFeeValue",
    "storeDeliveryFeeValue",
    "effectiveFrom",
  ];

  for (const field of requiredFields) {
    if (data[field] == null) {
      errors.push(field);
    }
  }

  if (
    data.commissionType === "percentage" &&
    data.commissionValue != null &&
    data.commissionValue > 100
  ) {
    errors.push("commissionValue");
  }

  if (
    data.serviceFeeType === "percentage" &&
    data.serviceFeeValue != null &&
    data.serviceFeeValue > 100
  ) {
    errors.push("serviceFeeValue");
  }

  return {
    ok: errors.length === 0,
    errors: [...new Set(errors)],
    data,
  };
}

export function validateCompetitionCreate(body = {}) {
  const errors = [];
  const title = toOptionalString(body.title, 180);
  const description = toOptionalString(body.description, 2000);
  const competitionType = toOptionalString(body.competitionType, 40) || "completed_orders";
  const targetValue = toOptionalNumber(body.targetValue);
  const rewardAmount = toOptionalNumber(body.rewardAmount);
  const rewardType = toOptionalString(body.rewardType, 30) || "cash";
  const startAt = toOptionalString(body.startAt, 60);
  const endAt = toOptionalString(body.endAt, 60);
  const isActive = toOptionalBoolean(body.isActive);
  const status = toOptionalString(body.status, 20);
  const filters = body.filters && typeof body.filters === "object" ? body.filters : {};
  const rawTiers = Array.isArray(body.tiers) ? body.tiers : [];
  const tiers = [];
  for (let i = 0; i < rawTiers.length; i += 1) {
    const raw = rawTiers[i];
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
      errors.push(`tiers[${i}]`);
      continue;
    }
    const titleValue = toOptionalString(raw.title, 80) || `Rank ${i + 1}`;
    const requiredCompletedOrders = toOptionalPositiveInt(
      raw.requiredCompletedOrders ?? raw.required_completed_orders
    );
    const rewardAmountValue = toOptionalNumber(
      raw.rewardAmount ?? raw.reward_amount
    );
    const rewardLabel = toOptionalString(raw.rewardLabel ?? raw.reward_label, 120);
    if (requiredCompletedOrders == null || requiredCompletedOrders <= 0) {
      errors.push(`tiers[${i}].requiredCompletedOrders`);
    }
    if (rewardAmountValue == null || rewardAmountValue < 0) {
      errors.push(`tiers[${i}].rewardAmount`);
    }
    if (requiredCompletedOrders != null && rewardAmountValue != null) {
      tiers.push({
        title: titleValue,
        requiredCompletedOrders,
        rewardAmount: rewardAmountValue,
        rewardLabel,
      });
    }
  }
  if (tiers.length > 0) {
    tiers.sort((a, b) => b.requiredCompletedOrders - a.requiredCompletedOrders);
    for (let i = 1; i < tiers.length; i += 1) {
      if (tiers[i].requiredCompletedOrders >= tiers[i - 1].requiredCompletedOrders) {
        errors.push("tiers.requiredCompletedOrders");
        break;
      }
    }
    for (let i = 0; i < tiers.length; i += 1) {
      tiers[i].sortOrder = i + 1;
    }
  }

  errorField(errors, "title", title != null);
  errorField(errors, "competitionType", competitionType != null);
  if (tiers.length === 0) {
    errorField(errors, "targetValue", targetValue != null && targetValue > 0);
    errorField(errors, "rewardAmount", rewardAmount != null && rewardAmount >= 0);
  }
  if (status != null) {
    errorField(
      errors,
      "status",
      ["draft", "active", "ended", "cancelled"].includes(status.toLowerCase())
    );
  }

  return {
    ok: errors.length === 0,
    errors,
    data: {
      title,
      description,
      competitionType,
      targetValue,
      rewardAmount,
      rewardType,
      startAt,
      endAt,
      isActive: isActive == null ? true : isActive,
      status: status ? status.toLowerCase() : null,
      filters,
      tiers,
    },
  };
}

export function validateCompetitionPatch(body = {}) {
  const errors = [];
  const title = toOptionalString(body.title, 180);
  const description = toOptionalString(body.description, 2000);
  const targetValue = toOptionalNumber(body.targetValue);
  const rewardAmount = toOptionalNumber(body.rewardAmount);
  const rewardType = toOptionalString(body.rewardType, 30);
  const startAt = toOptionalString(body.startAt, 60);
  const endAt = toOptionalString(body.endAt, 60);
  const isActive = toOptionalBoolean(body.isActive);
  const status = toOptionalString(body.status, 20);
  const filters = body.filters && typeof body.filters === "object" ? body.filters : null;
  const rawTiers = Array.isArray(body.tiers) ? body.tiers : null;
  let tiers = null;
  if (rawTiers != null) {
    tiers = [];
    for (let i = 0; i < rawTiers.length; i += 1) {
      const raw = rawTiers[i];
      if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
        errors.push(`tiers[${i}]`);
        continue;
      }
      const titleValue = toOptionalString(raw.title, 80) || `Rank ${i + 1}`;
      const requiredCompletedOrders = toOptionalPositiveInt(
        raw.requiredCompletedOrders ?? raw.required_completed_orders
      );
      const rewardAmountValue = toOptionalNumber(
        raw.rewardAmount ?? raw.reward_amount
      );
      const rewardLabel = toOptionalString(raw.rewardLabel ?? raw.reward_label, 120);
      if (requiredCompletedOrders == null || requiredCompletedOrders <= 0) {
        errors.push(`tiers[${i}].requiredCompletedOrders`);
      }
      if (rewardAmountValue == null || rewardAmountValue < 0) {
        errors.push(`tiers[${i}].rewardAmount`);
      }
      if (requiredCompletedOrders != null && rewardAmountValue != null) {
        tiers.push({
          title: titleValue,
          requiredCompletedOrders,
          rewardAmount: rewardAmountValue,
          rewardLabel,
        });
      }
    }
    if (tiers.length > 0) {
      tiers.sort((a, b) => b.requiredCompletedOrders - a.requiredCompletedOrders);
      for (let i = 1; i < tiers.length; i += 1) {
        if (tiers[i].requiredCompletedOrders >= tiers[i - 1].requiredCompletedOrders) {
          errors.push("tiers.requiredCompletedOrders");
          break;
        }
      }
      for (let i = 0; i < tiers.length; i += 1) {
        tiers[i].sortOrder = i + 1;
      }
    }
  }
  if (status != null) {
    errorField(
      errors,
      "status",
      ["draft", "active", "ended", "cancelled"].includes(status.toLowerCase())
    );
  }

  return {
    ok: errors.length === 0,
    errors,
    data: {
      title,
      description,
      targetValue,
      rewardAmount,
      rewardType,
      startAt,
      endAt,
      isActive,
      status: status ? status.toLowerCase() : null,
      filters,
      tiers,
    },
  };
}

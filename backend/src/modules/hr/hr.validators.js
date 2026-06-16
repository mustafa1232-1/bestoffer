function toNonEmptyTrimmed(value, max = 120) {
  if (typeof value !== "string") return null;
  const out = value.trim();
  if (!out) return null;
  return out.slice(0, max);
}

function toOptionalTrimmed(value, max = 3000) {
  if (value === undefined || value === null || value === "") return null;
  if (typeof value !== "string") return null;
  return value.trim().slice(0, max);
}

function toOptionalInt(value) {
  if (value === undefined || value === null || value === "") return null;
  const n = Number(value);
  if (!Number.isInteger(n)) return null;
  return n;
}

function toOptionalNumber(value) {
  if (value === undefined || value === null || value === "") return null;
  const n = Number(value);
  if (!Number.isFinite(n)) return null;
  return n;
}

function toOptionalBool(value) {
  if (value === undefined || value === null || value === "") return null;
  if (typeof value === "boolean") return value;
  if (typeof value === "string") {
    const lowered = value.trim().toLowerCase();
    if (["true", "1", "yes"].includes(lowered)) return true;
    if (["false", "0", "no"].includes(lowered)) return false;
  }
  return null;
}

export function validateUpsertEmployee(body = {}) {
  const errors = [];
  const merchantId = toOptionalInt(body.merchantId);
  const employeeUserId = toOptionalInt(body.employeeUserId);
  const roleTag = toNonEmptyTrimmed(body.roleTag ?? "staff", 80);
  const employmentType = toNonEmptyTrimmed(body.employmentType ?? "full_time", 32);
  const baseSalary = toOptionalNumber(body.baseSalary);
  const currency = toNonEmptyTrimmed(body.currency ?? "IQD", 10);
  const workDaysPerWeek = toOptionalInt(body.workDaysPerWeek);
  const isActive = toOptionalBool(body.isActive);
  const shiftStartTime = toOptionalTrimmed(body.shiftStartTime, 20);
  const shiftEndTime = toOptionalTrimmed(body.shiftEndTime, 20);

  if (employeeUserId == null || employeeUserId <= 0) errors.push("employeeUserId");
  if (!roleTag) errors.push("roleTag");
  if (!employmentType) errors.push("employmentType");
  if (baseSalary == null || baseSalary < 0) errors.push("baseSalary");
  if (!currency) errors.push("currency");
  if (workDaysPerWeek == null || workDaysPerWeek < 1 || workDaysPerWeek > 7) {
    errors.push("workDaysPerWeek");
  }
  if (body.isActive !== undefined && isActive == null) errors.push("isActive");
  if (body.shiftStartTime !== undefined && !shiftStartTime) errors.push("shiftStartTime");
  if (body.shiftEndTime !== undefined && !shiftEndTime) errors.push("shiftEndTime");

  return {
    ok: errors.length === 0,
    errors,
    value: {
      merchantId,
      employeeUserId,
      roleTag,
      employmentType,
      baseSalary,
      currency,
      workDaysPerWeek,
      shiftStartTime,
      shiftEndTime,
      joinedAt: toOptionalTrimmed(body.joinedAt, 32),
      isActive: isActive ?? true,
      notes: toOptionalTrimmed(body.notes, 3000),
    },
  };
}

export function validateUpsertAttendance(body = {}) {
  const errors = [];
  const merchantId = toOptionalInt(body.merchantId);
  const employeeUserId = toOptionalInt(body.employeeUserId);
  const attendanceDate = toOptionalTrimmed(body.attendanceDate, 32);
  const status = toNonEmptyTrimmed(body.status ?? "present", 24);
  const checkInAt = toOptionalTrimmed(body.checkInAt, 64);
  const checkOutAt = toOptionalTrimmed(body.checkOutAt, 64);

  if (employeeUserId == null || employeeUserId <= 0) errors.push("employeeUserId");
  if (!attendanceDate) errors.push("attendanceDate");
  if (!status) errors.push("status");

  return {
    ok: errors.length === 0,
    errors,
    value: {
      merchantId,
      employeeUserId,
      attendanceDate,
      checkInAt,
      checkOutAt,
      status,
      note: toOptionalTrimmed(body.note, 3000),
    },
  };
}

export function validatePayrollBuild(body = {}) {
  const errors = [];
  const merchantId = toOptionalInt(body.merchantId);
  const periodYear = toOptionalInt(body.periodYear);
  const periodMonth = toOptionalInt(body.periodMonth);
  if (periodYear == null || periodYear < 2000 || periodYear > 2100) {
    errors.push("periodYear");
  }
  if (periodMonth == null || periodMonth < 1 || periodMonth > 12) {
    errors.push("periodMonth");
  }
  if (body.adjustments !== undefined && !Array.isArray(body.adjustments)) {
    errors.push("adjustments");
  }
  return {
    ok: errors.length === 0,
    errors,
    value: {
      merchantId,
      periodYear,
      periodMonth,
      summaryNote: toOptionalTrimmed(body.summaryNote, 3000),
      adjustments: Array.isArray(body.adjustments) ? body.adjustments : [],
    },
  };
}

export function validateSelfAttendance(body = {}) {
  const merchantId = toOptionalInt(body.merchantId);
  return {
    ok: true,
    errors: [],
    value: {
      merchantId,
      note: toOptionalTrimmed(body.note, 3000),
    },
  };
}

export function validateCreateLeaveRequest(body = {}) {
  const errors = [];
  const merchantId = toOptionalInt(body.merchantId);
  const employeeUserId = toOptionalInt(body.employeeUserId);
  const leaveType = toNonEmptyTrimmed(body.leaveType ?? "annual", 24);
  const payPolicy = toNonEmptyTrimmed(body.payPolicy ?? "paid", 24);
  const dateFrom = toOptionalTrimmed(body.dateFrom, 32);
  const dateTo = toOptionalTrimmed(body.dateTo, 32);
  const daysCount = toOptionalNumber(body.daysCount);
  const supportedTypes = new Set([
    "annual",
    "sick",
    "emergency",
    "maternity",
    "other",
  ]);
  const supportedPolicies = new Set(["paid", "half_paid", "unpaid", "sick_paid"]);

  if (employeeUserId == null || employeeUserId <= 0) errors.push("employeeUserId");
  if (!dateFrom) errors.push("dateFrom");
  if (!dateTo) errors.push("dateTo");
  if (daysCount == null || daysCount <= 0) errors.push("daysCount");
  if (!leaveType || !supportedTypes.has(leaveType)) errors.push("leaveType");
  if (!payPolicy || !supportedPolicies.has(payPolicy)) errors.push("payPolicy");

  return {
    ok: errors.length === 0,
    errors,
    value: {
      merchantId,
      employeeUserId,
      leaveType,
      payPolicy,
      dateFrom,
      dateTo,
      daysCount,
      reason: toOptionalTrimmed(body.reason, 3000),
    },
  };
}

export function validateCreateMyLeaveRequest(body = {}) {
  const errors = [];
  const merchantId = toOptionalInt(body.merchantId);
  const leaveType = toNonEmptyTrimmed(body.leaveType ?? "annual", 24);
  const payPolicy = toNonEmptyTrimmed(body.payPolicy ?? "paid", 24);
  const dateFrom = toOptionalTrimmed(body.dateFrom, 32);
  const dateTo = toOptionalTrimmed(body.dateTo, 32);
  const daysCount = toOptionalNumber(body.daysCount);
  const supportedTypes = new Set([
    "annual",
    "sick",
    "emergency",
    "maternity",
    "other",
  ]);
  const supportedPolicies = new Set(["paid", "half_paid", "unpaid", "sick_paid"]);

  if (!dateFrom) errors.push("dateFrom");
  if (!dateTo) errors.push("dateTo");
  if (daysCount == null || daysCount <= 0) errors.push("daysCount");
  if (!leaveType || !supportedTypes.has(leaveType)) errors.push("leaveType");
  if (!payPolicy || !supportedPolicies.has(payPolicy)) errors.push("payPolicy");

  return {
    ok: errors.length === 0,
    errors,
    value: {
      merchantId,
      leaveType,
      payPolicy,
      dateFrom,
      dateTo,
      daysCount,
      reason: toOptionalTrimmed(body.reason, 3000),
    },
  };
}

export function validateDecideLeaveRequest(body = {}) {
  const errors = [];
  const status = toNonEmptyTrimmed(body.status, 24);
  const allowed = new Set(["approved", "rejected", "cancelled"]);
  if (!status || !allowed.has(status)) errors.push("status");
  return {
    ok: errors.length === 0,
    errors,
    value: {
      merchantId: toOptionalInt(body.merchantId),
      status,
      decisionNote: toOptionalTrimmed(body.decisionNote, 3000),
    },
  };
}

export function validateCreateSalaryAction(body = {}) {
  const errors = [];
  const merchantId = toOptionalInt(body.merchantId);
  const employeeUserId = toOptionalInt(body.employeeUserId);
  const actionType = toNonEmptyTrimmed(body.actionType, 24);
  const amount = toOptionalNumber(body.amount);
  const effectiveYear = toOptionalInt(body.effectiveYear);
  const effectiveMonth = toOptionalInt(body.effectiveMonth);
  const allowedActions = new Set(["bonus", "allowance", "deduction", "advance"]);

  if (employeeUserId == null || employeeUserId <= 0) errors.push("employeeUserId");
  if (!actionType || !allowedActions.has(actionType)) errors.push("actionType");
  if (amount == null || amount <= 0) errors.push("amount");
  if (effectiveYear == null || effectiveYear < 2000 || effectiveYear > 2100) {
    errors.push("effectiveYear");
  }
  if (effectiveMonth == null || effectiveMonth < 1 || effectiveMonth > 12) {
    errors.push("effectiveMonth");
  }

  return {
    ok: errors.length === 0,
    errors,
    value: {
      merchantId,
      employeeUserId,
      actionType,
      amount,
      currency: toNonEmptyTrimmed(body.currency ?? "IQD", 10),
      effectiveYear,
      effectiveMonth,
      description: toOptionalTrimmed(body.description, 3000),
    },
  };
}

export function validateUpdateSalaryActionStatus(body = {}) {
  const errors = [];
  const status = toNonEmptyTrimmed(body.status, 24);
  const allowed = new Set(["active", "cancelled"]);
  if (!status || !allowed.has(status)) errors.push("status");
  return {
    ok: errors.length === 0,
    errors,
    value: {
      merchantId: toOptionalInt(body.merchantId),
      status,
    },
  };
}

export function validateCreateAdvanceRequest(body = {}) {
  const errors = [];
  const merchantId = toOptionalInt(body.merchantId);
  const requestedAmount = toOptionalNumber(body.requestedAmount);
  if (requestedAmount == null || requestedAmount <= 0) {
    errors.push("requestedAmount");
  }
  return {
    ok: errors.length === 0,
    errors,
    value: {
      merchantId,
      requestedAmount,
      currency: toNonEmptyTrimmed(body.currency ?? "IQD", 10),
      reason: toOptionalTrimmed(body.reason, 3000),
    },
  };
}

export function validateDecideAdvanceRequest(body = {}) {
  const errors = [];
  const status = toNonEmptyTrimmed(body.status, 24);
  const allowed = new Set(["approved", "rejected"]);
  if (!status || !allowed.has(status)) errors.push("status");
  const effectiveYear = toOptionalInt(body.effectiveYear);
  const effectiveMonth = toOptionalInt(body.effectiveMonth);
  if (
    body.effectiveYear !== undefined &&
    (effectiveYear == null || effectiveYear < 2000 || effectiveYear > 2100)
  ) {
    errors.push("effectiveYear");
  }
  if (
    body.effectiveMonth !== undefined &&
    (effectiveMonth == null || effectiveMonth < 1 || effectiveMonth > 12)
  ) {
    errors.push("effectiveMonth");
  }
  return {
    ok: errors.length === 0,
    errors,
    value: {
      merchantId: toOptionalInt(body.merchantId),
      status,
      decisionNote: toOptionalTrimmed(body.decisionNote, 3000),
      effectiveYear,
      effectiveMonth,
    },
  };
}

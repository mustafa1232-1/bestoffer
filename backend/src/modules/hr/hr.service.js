import { AppError } from "../../shared/utils/errors.js";
import { createManyNotifications } from "../notifications/notifications.repo.js";
import * as repo from "./hr.repo.js";
import {
  buildWorkspacePermissionPayload,
  hasPermission,
  STORE_EMPLOYEE_PERMISSION_KEYS,
} from "../../shared/workspaces/employee-permissions.js";
import { createUser, findUserByPhone } from "../auth/auth.repo.js";
import { runWithGeneratedAppUserUsername } from "../auth/auth.service.js";
import { hashPin } from "../../shared/utils/hash.js";

const MANAGER_ROLES = new Set(["owner", "admin", "deputy_admin", "call_center", "hr"]);

function normalizeRole(role) {
  return String(role || "").trim().toLowerCase();
}

function toActorUserId(actor) {
  const id = Number(actor?.userId || 0);
  if (!Number.isInteger(id) || id <= 0) {
    throw new AppError("UNAUTHORIZED", { status: 401 });
  }
  return id;
}

function toNullableNumber(value) {
  if (value === null || value === undefined || value === "") return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

function toNonNegativeNumber(value, fallback = 0) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 0) return fallback;
  return parsed;
}

function toDateOnly(value, fallback = null) {
  if (!value) return fallback;
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return fallback;
  return d.toISOString().slice(0, 10);
}

function asTrimmed(value, fallback = "") {
  const out = String(value ?? "").trim();
  return out || fallback;
}

function normalizeDigits(value) {
  return String(value || "")
    .replace(/[\u0660-\u0669]/g, (d) => String(d.charCodeAt(0) - 0x0660))
    .replace(/[\u06F0-\u06F9]/g, (d) => String(d.charCodeAt(0) - 0x06f0));
}

function normalizePhone(value) {
  return normalizeDigits(value).replace(/[^\d]/g, "");
}

function normalizePin(value) {
  return normalizeDigits(value).replace(/[^\d]/g, "");
}

function mapMerchant(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    name: row.name,
    type: row.type,
    ownerUserId: row.owner_user_id == null ? null : Number(row.owner_user_id),
  };
}

function mapEmployeeProfileRow(row) {
  if (!row) return null;
  const permissions = Array.isArray(row.permissions_json)
    ? row.permissions_json
    : [];
  const permissionPayload = buildWorkspacePermissionPayload(
    permissions,
    "merchant"
  );
  return {
    id: Number(row.id),
    roleTag: row.role_tag || "staff",
    displayName: row.display_name || null,
    contactEmail: row.contact_email || null,
    permissions,
    permissionMap: permissionPayload.permissionMap,
    employmentType: row.employment_type || "full_time",
    baseSalary: row.base_salary == null ? 0 : Number(row.base_salary || 0),
    currency: row.currency || "IQD",
    workDaysPerWeek: Number(row.work_days_per_week || 6),
    shiftStartTime: row.shift_start_time || null,
    shiftEndTime: row.shift_end_time || null,
    joinedAt: row.joined_at || null,
    isActive: row.profile_is_active !== false && row.is_active !== false,
    archivedAt: row.archived_at || null,
    notes: row.notes || null,
    invitedByUserId:
      row.invited_by_user_id == null ? null : Number(row.invited_by_user_id),
    updatedByUserId:
      row.updated_by_user_id == null ? null : Number(row.updated_by_user_id),
  };
}

function mapEmployee(row) {
  const profile = mapEmployeeProfileRow(row);
  return {
    userId: Number(row.id),
    fullName: row.full_name,
    phone: row.phone,
    role: row.role,
    imageUrl: row.image_url || null,
    workTitle: row.work_title || null,
    workCompany: row.work_company || null,
    displayName: row.display_name || row.full_name || null,
    contactEmail: row.contact_email || null,
    flags: {
      isDeliveryAgent: row.is_delivery_agent === true,
      isAccountant: row.is_accountant === true,
      isHrStaff: row.is_hr_staff === true,
    },
    profile: row.employee_profile_id ? profile : null,
  };
}

function mapEmployeeActivityLog(row) {
  return {
    id: Number(row.id),
    workspaceKind: row.workspace_kind || "merchant",
    workspaceId: Number(row.workspace_id),
    employeeProfileId:
      row.employee_profile_id == null ? null : Number(row.employee_profile_id),
    employeeUserId: Number(row.employee_user_id),
    employeeFullName: row.employee_full_name || "",
    employeePhone: row.employee_phone || "",
    actorUserId: row.actor_user_id == null ? null : Number(row.actor_user_id),
    actorFullName: row.actor_full_name || null,
    actorRole: row.actor_role || "",
    actionKey: row.action_key || "",
    reason: row.reason || null,
    oldValue: row.old_value && typeof row.old_value === "object" ? row.old_value : {},
    newValue: row.new_value && typeof row.new_value === "object" ? row.new_value : {},
    note: row.note || null,
    createdAt: row.created_at || null,
  };
}

function mapAttendance(row) {
  return {
    id: Number(row.id),
    merchantId: Number(row.merchant_id),
    employeeUserId: Number(row.employee_user_id),
    employeeFullName: row.employee_full_name || "",
    employeePhone: row.employee_phone || "",
    attendanceDate: row.attendance_date,
    checkInAt: row.check_in_at || null,
    checkOutAt: row.check_out_at || null,
    checkInImageUrl: row.check_in_image_url || null,
    checkOutImageUrl: row.check_out_image_url || null,
    status: row.status,
    source: row.source,
    note: row.note || null,
    recordedByUserId:
      row.recorded_by_user_id == null ? null : Number(row.recorded_by_user_id),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function mapLeaveRequest(row) {
  return {
    id: Number(row.id),
    merchantId: Number(row.merchant_id),
    employeeUserId: Number(row.employee_user_id),
    employeeFullName: row.employee_full_name || "",
    employeePhone: row.employee_phone || "",
    leaveType: row.leave_type,
    payPolicy: row.pay_policy,
    dateFrom: row.date_from,
    dateTo: row.date_to,
    daysCount: Number(row.days_count || 0),
    reason: row.reason || null,
    status: row.status,
    requestedByUserId:
      row.requested_by_user_id == null ? null : Number(row.requested_by_user_id),
    requestedByFullName: row.requested_by_full_name || null,
    decidedByUserId:
      row.decided_by_user_id == null ? null : Number(row.decided_by_user_id),
    decidedByFullName: row.decided_by_full_name || null,
    decidedAt: row.decided_at || null,
    decisionNote: row.decision_note || null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function mapSalaryAction(row) {
  return {
    id: Number(row.id),
    merchantId: Number(row.merchant_id),
    employeeUserId: Number(row.employee_user_id),
    employeeFullName: row.employee_full_name || "",
    employeePhone: row.employee_phone || "",
    actionType: row.action_type,
    amount: Number(row.amount || 0),
    currency: row.currency || "IQD",
    effectiveYear: Number(row.effective_year),
    effectiveMonth: Number(row.effective_month),
    description: row.description || null,
    status: row.status,
    createdByUserId:
      row.created_by_user_id == null ? null : Number(row.created_by_user_id),
    createdByFullName: row.created_by_full_name || null,
    appliedBatchId:
      row.applied_batch_id == null ? null : Number(row.applied_batch_id),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function mapAdvanceRequest(row) {
  return {
    id: Number(row.id),
    merchantId: Number(row.merchant_id),
    employeeUserId: Number(row.employee_user_id),
    employeeFullName: row.employee_full_name || "",
    employeePhone: row.employee_phone || "",
    requestedAmount: Number(row.requested_amount || 0),
    currency: row.currency || "IQD",
    reason: row.reason || null,
    status: row.status,
    requestedByUserId:
      row.requested_by_user_id == null ? null : Number(row.requested_by_user_id),
    requestedByFullName: row.requested_by_full_name || null,
    decidedByUserId:
      row.decided_by_user_id == null ? null : Number(row.decided_by_user_id),
    decidedByFullName: row.decided_by_full_name || null,
    decidedAt: row.decided_at || null,
    decisionNote: row.decision_note || null,
    linkedSalaryActionId:
      row.linked_salary_action_id == null
          ? null
          : Number(row.linked_salary_action_id),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function mapPayrollBatch(row) {
  return {
    id: Number(row.id),
    merchantId: Number(row.merchant_id),
    periodYear: Number(row.period_year),
    periodMonth: Number(row.period_month),
    status: row.status,
    summaryNote: row.summary_note || null,
    createdByUserId:
      row.created_by_user_id == null ? null : Number(row.created_by_user_id),
    acknowledgedByUserId:
      row.acknowledged_by_user_id == null
        ? null
        : Number(row.acknowledged_by_user_id),
    acknowledgedAt: row.acknowledged_at || null,
    closedByUserId:
      row.closed_by_user_id == null ? null : Number(row.closed_by_user_id),
    closedAt: row.closed_at || null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    employeesCount:
      row.employees_count == null ? null : Number(row.employees_count),
    totalNetSalary:
      row.total_net_salary == null ? null : Number(row.total_net_salary),
    totalPaidSalary:
      row.total_paid_salary == null ? null : Number(row.total_paid_salary),
    totalPendingSalary:
      row.total_pending_salary == null ? null : Number(row.total_pending_salary),
  };
}

function mapPayrollItem(row) {
  return {
    id: Number(row.id),
    batchId: Number(row.batch_id),
    merchantId: Number(row.merchant_id),
    employeeUserId: Number(row.employee_user_id),
    employeeFullName: row.employee_full_name || "",
    employeePhone: row.employee_phone || "",
    employeeImageUrl: row.employee_image_url || null,
    baseSalary: Number(row.base_salary || 0),
    bonuses: Number(row.bonuses || 0),
    deductions: Number(row.deductions || 0),
    leaveAdjustment: Number(row.leave_adjustment || 0),
    netSalary: Number(row.net_salary || 0),
    status: row.status,
    hrNote: row.hr_note || null,
    payoutNote: row.payout_note || null,
    paidByUserId: row.paid_by_user_id == null ? null : Number(row.paid_by_user_id),
    paidAt: row.paid_at || null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

async function resolveMerchantForManagement(actor, merchantId = null) {
  const actorUserId = toActorUserId(actor);
  const role = normalizeRole(actor?.role);
  const isSuperAdmin = actor?.isSuperAdmin === true;

  if (!MANAGER_ROLES.has(role) && !isSuperAdmin) {
    throw new AppError("FORBIDDEN_HR_MANAGEMENT", { status: 403 });
  }

  if (isSuperAdmin || role === "admin" || role === "deputy_admin" || role === "call_center") {
    if (!merchantId) {
      throw new AppError("MERCHANT_REQUIRED", { status: 400 });
    }
    const merchant = await repo.findMerchantById(merchantId);
    if (!merchant || merchant.is_disabled === true) {
      throw new AppError("MERCHANT_NOT_FOUND", { status: 404 });
    }
    return merchant;
  }

  if (role === "owner") {
    const merchant =
      (await repo.findOwnerMerchantByUserId(actorUserId)) ||
      (await repo.findMerchantByEmployeeUserId(actorUserId));
    if (!merchant) {
      throw new AppError("MERCHANT_NOT_FOUND", { status: 404 });
    }
    return merchant;
  }

  if (role === "hr") {
    const merchant =
      (await repo.findHrMerchantByUserId(actorUserId)) ||
      (await repo.findMerchantByEmployeeUserId(actorUserId));
    if (!merchant) {
      throw new AppError("HR_MERCHANT_NOT_FOUND", { status: 404 });
    }
    return merchant;
  }

  throw new AppError("FORBIDDEN_HR_MANAGEMENT", { status: 403 });
}

async function ensureMerchantPermission(actor, merchantId, permission) {
  const actorUserId = toActorUserId(actor);
  const role = normalizeRole(actor?.role);
  if (
    actor?.isSuperAdmin === true ||
    role === "admin" ||
    role === "deputy_admin" ||
    role === "call_center"
  ) {
    return;
  }

  const ownerMerchant = await repo.findOwnerMerchantByUserId(actorUserId);
  if (ownerMerchant && Number(ownerMerchant.id) === Number(merchantId)) {
    return;
  }

  const profile = await repo.findEmployeeProfileForMerchant({
    merchantId,
    employeeUserId: actorUserId,
  });
  if (!profile || profile.is_active !== true || profile.archived_at) {
    throw new AppError("FORBIDDEN_MERCHANT_EMPLOYEE_ONLY", { status: 403 });
  }

  const permissions = Array.isArray(profile.permissions_json)
    ? profile.permissions_json
    : [];
  if (!hasPermission(permissions, permission)) {
    throw new AppError("FORBIDDEN_MERCHANT_PERMISSION", { status: 403 });
  }
}

function assertPayrollDraftStatus(batch) {
  if (!batch) {
    throw new AppError("PAYROLL_BATCH_NOT_FOUND", { status: 404 });
  }
  if (String(batch.status) !== "draft") {
    throw new AppError("PAYROLL_BATCH_NOT_DRAFT", { status: 409 });
  }
}

export async function getDashboard(actor, { merchantId } = {}) {
  const merchant = await resolveMerchantForManagement(actor, merchantId);
  const stats = await repo.getDashboardStats(merchant.id);
  return {
    merchant: mapMerchant(merchant),
    stats,
  };
}

export async function listEmployees(actor, { merchantId, search, limit }) {
  const merchant = await resolveMerchantForManagement(actor, merchantId);
  await ensureMerchantPermission(actor, merchant.id, "manage_employees");
  const rows = await repo.listMerchantEmployees({
    merchantId: merchant.id,
    search,
    limit,
  });
  return {
    merchant: mapMerchant(merchant),
    items: rows.map(mapEmployee),
    availablePermissions: STORE_EMPLOYEE_PERMISSION_KEYS,
  };
}

export async function upsertEmployee(actor, dto) {
  const merchant = await resolveMerchantForManagement(actor, dto.merchantId);
  await ensureMerchantPermission(actor, merchant.id, "manage_employees");
  const actorUserId = toActorUserId(actor);
  const employeeUserId = Number(dto.employeeUserId);
  if (!Number.isInteger(employeeUserId) || employeeUserId <= 0) {
    throw new AppError("EMPLOYEE_REQUIRED", { status: 400 });
  }
  const roleTag = asTrimmed(dto.roleTag, "staff").slice(0, 80);
  const employmentType = asTrimmed(dto.employmentType, "full_time").slice(0, 32);
  const baseSalary = toNonNegativeNumber(dto.baseSalary, 0);
  const currency = asTrimmed(dto.currency, "IQD").slice(0, 10);
  const workDaysPerWeek = Math.max(
    1,
    Math.min(7, Number(dto.workDaysPerWeek || 6) || 6)
  );
  const permissions = Array.isArray(dto.permissions)
    ? dto.permissions
    : [];
  const permissionPayload = buildWorkspacePermissionPayload(
    permissions,
    "merchant"
  );
  const previousProfile = await repo.findAnyEmployeeProfileForMerchant({
    merchantId: merchant.id,
    employeeUserId,
  });

  const out = await repo.upsertEmployeeProfile({
    merchantId: merchant.id,
    employeeUserId,
    roleTag,
    displayName: dto.displayName || null,
    contactEmail: dto.contactEmail || null,
    employmentType,
    baseSalary,
    currency,
    workDaysPerWeek,
    shiftStartTime: dto.shiftStartTime || null,
    shiftEndTime: dto.shiftEndTime || null,
    joinedAt: toDateOnly(dto.joinedAt, null),
    isActive: dto.isActive !== false,
    archivedAt: dto.archivedAt || (dto.isActive === false ? new Date().toISOString() : null),
    notes: dto.notes || null,
    permissions: permissionPayload.permissions,
    invitedByUserId: dto.invitedByUserId == null ? actorUserId : Number(dto.invitedByUserId),
    updatedByUserId: actorUserId,
  });

  await repo.insertEmployeeActivityLog({
    workspaceKind: "merchant",
    workspaceId: merchant.id,
    employeeProfileId: Number(out.id),
    employeeUserId,
    actorUserId,
    actorRole: normalizeRole(actor?.role),
    actionKey: "merchant.employee.updated",
    reason: dto.reason || null,
    oldValue: previousProfile
      ? {
          displayName: previousProfile.display_name || null,
          contactEmail: previousProfile.contact_email || null,
          permissions: Array.isArray(previousProfile.permissions_json)
            ? previousProfile.permissions_json
            : [],
          isActive: previousProfile.is_active === true,
          archivedAt: previousProfile.archived_at || null,
        }
      : {},
    newValue: {
      displayName: out.display_name || null,
      contactEmail: out.contact_email || null,
      permissions: permissionPayload.permissions,
      isActive: out.is_active === true,
      archivedAt: out.archived_at || null,
    },
    note: dto.notes || null,
  });

  return {
    merchant: mapMerchant(merchant),
    profile: mapEmployeeProfileRow(out),
  };
}

export async function inviteEmployee(actor, dto) {
  const merchant = await resolveMerchantForManagement(actor, dto.merchantId);
  await ensureMerchantPermission(actor, merchant.id, "manage_employees");
  const actorUserId = toActorUserId(actor);

  const phone = normalizePhone(dto.phone);
  const pin = normalizePin(dto.pin);
  const fullName = String(dto.fullName || "").trim();
  const displayName = String(dto.displayName || fullName || "").trim();
  const contactEmail = String(dto.contactEmail || "").trim() || null;
  if (!fullName) {
    throw new AppError("FULL_NAME_REQUIRED", { status: 400 });
  }
  if (!/^\d{8,20}$/.test(phone)) {
    throw new AppError("PHONE_INVALID", { status: 400 });
  }
  if (!/^\d{4,8}$/.test(pin)) {
    throw new AppError("PIN_INVALID", { status: 400 });
  }

  const existing = await findUserByPhone(phone);
  if (existing) {
    throw new AppError("PHONE_EXISTS", { status: 409 });
  }

  const pinHash = await hashPin(pin);
  const created = await runWithGeneratedAppUserUsername({
    fullName,
    phone,
    execute: (username) =>
      createUser({
        fullName,
        username,
        phone,
        pinHash,
        block: "A",
        buildingNumber: "A101",
        apartment: "101",
        imageUrl: null,
        role: "owner",
        analyticsConsentGranted: true,
        analyticsConsentVersion: "merchant_employee_invite_v1",
        analyticsConsentGrantedAt: new Date(),
        chatQualityReviewConsent: true,
      }),
  });

  const permissions = buildWorkspacePermissionPayload(
    dto.permissions,
    "merchant"
  ).permissions;
  const out = await repo.upsertEmployeeProfile({
    merchantId: merchant.id,
    employeeUserId: Number(created.id),
    roleTag: String(dto.roleTag || "staff").trim().slice(0, 80) || "staff",
    displayName,
    contactEmail,
    employmentType: String(dto.employmentType || "full_time").trim().slice(0, 32) || "full_time",
    baseSalary: Number(dto.baseSalary || 0),
    currency: String(dto.currency || "IQD").trim().slice(0, 10) || "IQD",
    workDaysPerWeek: Math.max(1, Math.min(7, Number(dto.workDaysPerWeek || 6) || 6)),
    shiftStartTime: dto.shiftStartTime || null,
    shiftEndTime: dto.shiftEndTime || null,
    joinedAt: dto.joinedAt || null,
    isActive: dto.isActive !== false,
    archivedAt: dto.archivedAt || null,
    notes: dto.notes || null,
    permissions,
    invitedByUserId: actorUserId,
    updatedByUserId: actorUserId,
  });

  await repo.insertEmployeeActivityLog({
    workspaceKind: "merchant",
    workspaceId: merchant.id,
    employeeProfileId: Number(out.id),
    employeeUserId: Number(created.id),
    actorUserId,
    actorRole: normalizeRole(actor?.role),
    actionKey: "merchant.employee.invited",
    reason: dto.reason || null,
    oldValue: {},
    newValue: {
      displayName: out.display_name || displayName,
      contactEmail: out.contact_email || contactEmail,
      permissions,
      isActive: out.is_active === true,
    },
    note: dto.notes || null,
  });

  return {
    merchant: mapMerchant(merchant),
    user: {
      id: Number(created.id),
      fullName: created.full_name,
      phone: created.phone,
      role: created.role,
    },
    profile: mapEmployeeProfileRow(out),
  };
}

export async function listEmployeeActivityLogs(actor, { merchantId, employeeUserId, limit } = {}) {
  const merchant = await resolveMerchantForManagement(actor, merchantId);
  await ensureMerchantPermission(actor, merchant.id, "view_audit_log");
  const rows = await repo.listEmployeeActivityLogs({
    merchantId: merchant.id,
    employeeUserId: employeeUserId == null ? null : Number(employeeUserId),
    limit,
  });
  return {
    merchant: mapMerchant(merchant),
    items: rows.map(mapEmployeeActivityLog),
  };
}

export async function listAttendance(actor, query = {}) {
  const merchant = await resolveMerchantForManagement(actor, query.merchantId);
  const rows = await repo.listAttendanceLogs({
    merchantId: merchant.id,
    employeeUserId: query.employeeUserId ? Number(query.employeeUserId) : null,
    dateFrom: query.dateFrom || null,
    dateTo: query.dateTo || null,
    limit: query.limit,
  });
  return {
    merchant: mapMerchant(merchant),
    items: rows.map(mapAttendance),
  };
}

export async function upsertAttendance(actor, dto) {
  const merchant = await resolveMerchantForManagement(actor, dto.merchantId);
  const actorUserId = toActorUserId(actor);
  const employeeUserId = Number(dto.employeeUserId);
  if (!Number.isInteger(employeeUserId) || employeeUserId <= 0) {
    throw new AppError("EMPLOYEE_REQUIRED", { status: 400 });
  }
  const attendanceDate = toDateOnly(dto.attendanceDate, null);
  if (!attendanceDate) {
    throw new AppError("ATTENDANCE_DATE_INVALID", { status: 400 });
  }

  const out = await repo.upsertAttendanceLog({
    merchantId: merchant.id,
    employeeUserId,
    attendanceDate,
    checkInAt: dto.checkInAt || null,
    checkOutAt: dto.checkOutAt || null,
    checkInImageUrl: dto.checkInImageUrl || null,
    checkOutImageUrl: dto.checkOutImageUrl || null,
    status: asTrimmed(dto.status, "present").slice(0, 24),
    source: "manual",
    note: dto.note || null,
    recordedByUserId: actorUserId,
  });
  return {
    merchant: mapMerchant(merchant),
    item: mapAttendance({
      ...out,
      employee_full_name: "",
      employee_phone: "",
    }),
  };
}

function defaultRoleTagFromRole(role) {
  const normalized = normalizeRole(role);
  if (normalized === "delivery") return "delivery";
  if (normalized === "accountant") return "accountant";
  if (normalized === "hr") return "hr";
  if (normalized === "owner") return "owner_staff";
  return "staff";
}

async function inferMerchantForEmployeeActor({
  actorUserId,
  role,
  merchantId = null,
}) {
  if (merchantId) {
    const merchant = await repo.findMerchantById(Number(merchantId));
    if (!merchant || merchant.is_disabled === true) {
      throw new AppError("MERCHANT_NOT_FOUND", { status: 404 });
    }
    return merchant;
  }

  const normalizedRole = normalizeRole(role);
  if (normalizedRole === "owner") {
    return repo.findOwnerMerchantByUserId(actorUserId);
  }
  if (normalizedRole === "hr") {
    return repo.findHrMerchantByUserId(actorUserId);
  }
  if (normalizedRole === "delivery") {
    return repo.findDeliveryMerchantByUserId(actorUserId);
  }
  if (normalizedRole === "accountant") {
    return repo.findAccountantMerchantByUserId(actorUserId);
  }
  return null;
}

async function resolveOrCreateEmployeeProfile(actor, merchantId = null) {
  const actorUserId = toActorUserId(actor);
  const preferredMerchantId = merchantId ? Number(merchantId) : null;

  if (preferredMerchantId) {
    const profile = await repo.findEmployeeProfileForMerchant({
      merchantId: preferredMerchantId,
      employeeUserId: actorUserId,
    });
    if (profile && profile.is_active === true) {
      return profile;
    }
  } else {
    const profiles = await repo.listEmployeeProfilesByUserId(actorUserId);
    if (profiles.length > 0) {
      return profiles[0];
    }
  }

  const merchant = await inferMerchantForEmployeeActor({
    actorUserId,
    role: actor?.role,
    merchantId: preferredMerchantId,
  });
  if (!merchant) {
    throw new AppError("EMPLOYEE_PROFILE_NOT_FOUND", { status: 404 });
  }

  await repo.upsertEmployeeProfile({
    merchantId: Number(merchant.id),
    employeeUserId: actorUserId,
    roleTag: defaultRoleTagFromRole(actor?.role),
    employmentType: "full_time",
    baseSalary: 0,
    currency: "IQD",
    workDaysPerWeek: 6,
    shiftStartTime: null,
    shiftEndTime: null,
    joinedAt: null,
    isActive: true,
    notes: "auto_created_for_staff_portal",
    updatedByUserId: actorUserId,
  });

  const createdProfile = await repo.findEmployeeProfileForMerchant({
    merchantId: Number(merchant.id),
    employeeUserId: actorUserId,
  });
  if (!createdProfile || createdProfile.is_active !== true) {
    throw new AppError("EMPLOYEE_PROFILE_NOT_FOUND", { status: 404 });
  }
  return createdProfile;
}

async function resolveSelfAttendanceProfile(actor, merchantId = null) {
  return resolveOrCreateEmployeeProfile(actor, merchantId);
}

export async function selfCheckIn(actor, { merchantId, note, imageUrl } = {}) {
  const profile = await resolveSelfAttendanceProfile(actor, merchantId);
  const out = await repo.upsertAttendanceLog({
    merchantId: Number(profile.merchant_id),
    employeeUserId: Number(profile.employee_user_id),
    attendanceDate: toDateOnly(new Date().toISOString(), null),
    checkInAt: new Date().toISOString(),
    checkOutAt: null,
    checkInImageUrl: imageUrl || null,
    checkOutImageUrl: null,
    status: "present",
    source: "self_check_in",
    note: note || null,
    recordedByUserId: Number(profile.employee_user_id),
  });
  return {
    merchantId: Number(profile.merchant_id),
    item: mapAttendance({
      ...out,
      employee_full_name: "",
      employee_phone: "",
    }),
  };
}

export async function selfCheckOut(actor, { merchantId, note, imageUrl } = {}) {
  const profile = await resolveSelfAttendanceProfile(actor, merchantId);
  const out = await repo.upsertAttendanceLog({
    merchantId: Number(profile.merchant_id),
    employeeUserId: Number(profile.employee_user_id),
    attendanceDate: toDateOnly(new Date().toISOString(), null),
    checkInAt: null,
    checkOutAt: new Date().toISOString(),
    checkInImageUrl: null,
    checkOutImageUrl: imageUrl || null,
    status: "present",
    source: "self_check_out",
    note: note || null,
    recordedByUserId: Number(profile.employee_user_id),
  });
  return {
    merchantId: Number(profile.merchant_id),
    item: mapAttendance({
      ...out,
      employee_full_name: "",
      employee_phone: "",
    }),
  };
}

function normalizeAdjustments(rawAdjustments) {
  if (!Array.isArray(rawAdjustments)) return new Map();
  const out = new Map();
  for (const raw of rawAdjustments) {
    if (!raw || typeof raw !== "object") continue;
    const employeeUserId = Number(raw.employeeUserId);
    if (!Number.isInteger(employeeUserId) || employeeUserId <= 0) continue;
    out.set(employeeUserId, {
      bonuses: toNonNegativeNumber(raw.bonuses, 0),
      deductions: toNonNegativeNumber(raw.deductions, 0),
      leaveAdjustment: toNullableNumber(raw.leaveAdjustment) ?? 0,
      hrNote: raw.hrNote ? String(raw.hrNote).slice(0, 3000) : null,
    });
  }
  return out;
}

function aggregateSalaryActions(rows) {
  const byEmployee = new Map();
  for (const row of rows || []) {
    const employeeUserId = Number(row.employee_user_id);
    if (!Number.isInteger(employeeUserId) || employeeUserId <= 0) continue;
    const current = byEmployee.get(employeeUserId) || {
      bonusLike: 0,
      deductionLike: 0,
      actionIds: [],
    };
    const amount = toNonNegativeNumber(row.amount, 0);
    const actionType = String(row.action_type || "").trim().toLowerCase();
    if (actionType === "bonus" || actionType === "allowance") {
      current.bonusLike += amount;
    } else if (actionType === "deduction" || actionType === "advance") {
      current.deductionLike += amount;
    }
    const actionId = Number(row.id);
    if (Number.isInteger(actionId) && actionId > 0) {
      current.actionIds.push(actionId);
    }
    byEmployee.set(employeeUserId, current);
  }
  return byEmployee;
}

function aggregateLeaveAdjustments(rows, profiles) {
  const workDaysByEmployee = new Map();
  const baseSalaryByEmployee = new Map();
  for (const profile of profiles || []) {
    const employeeUserId = Number(profile.employee_user_id);
    if (!Number.isInteger(employeeUserId) || employeeUserId <= 0) continue;
    workDaysByEmployee.set(
      employeeUserId,
      Math.max(1, Number(profile.work_days_per_week || 6))
    );
    baseSalaryByEmployee.set(
      employeeUserId,
      Math.max(0, Number(profile.base_salary || 0))
    );
  }
  const out = new Map();
  for (const row of rows || []) {
    const employeeUserId = Number(row.employee_user_id);
    if (!Number.isInteger(employeeUserId) || employeeUserId <= 0) continue;
    const payPolicy = String(row.pay_policy || "").trim().toLowerCase();
    if (payPolicy === "paid" || payPolicy === "sick_paid") continue;

    const daysCount = Math.max(0, Number(row.days_count || 0));
    if (daysCount <= 0) continue;
    const workDaysPerWeek = workDaysByEmployee.get(employeeUserId) || 6;
    const monthlyBase = baseSalaryByEmployee.get(employeeUserId) || 0;

    // Convert monthly base salary into daily rate using 30-day month standard.
    const dailyRate = monthlyBase / 30;
    const policyFactor = payPolicy === "half_paid" ? 0.5 : 1;
    const deductionValue = dailyRate * daysCount * policyFactor;

    const current = out.get(employeeUserId) || {
      leaveAdjustment: 0,
      leaveDaysCount: 0,
      notes: [],
    };
    current.leaveAdjustment -= deductionValue;
    current.leaveDaysCount += daysCount;
    current.notes.push(
      `leave(${payPolicy}) ${daysCount.toFixed(2)}d @${workDaysPerWeek}d/week`
    );
    out.set(employeeUserId, current);
  }
  return out;
}

export async function buildPayrollBatch(actor, dto) {
  const merchant = await resolveMerchantForManagement(actor, dto.merchantId);
  const actorUserId = toActorUserId(actor);

  const periodYear = Number(dto.periodYear);
  const periodMonth = Number(dto.periodMonth);
  if (!Number.isInteger(periodYear) || periodYear < 2000 || periodYear > 2100) {
    throw new AppError("PAYROLL_PERIOD_YEAR_INVALID", { status: 400 });
  }
  if (!Number.isInteger(periodMonth) || periodMonth < 1 || periodMonth > 12) {
    throw new AppError("PAYROLL_PERIOD_MONTH_INVALID", { status: 400 });
  }

  const profiles = await repo.listActiveEmployeeProfiles(merchant.id);
  if (!profiles.length) {
    throw new AppError("PAYROLL_NO_ACTIVE_EMPLOYEES", { status: 409 });
  }

  const batch = await repo.createOrReusePayrollBatch({
    merchantId: merchant.id,
    periodYear,
    periodMonth,
    summaryNote: dto.summaryNote || null,
    createdByUserId: actorUserId,
  });
  assertPayrollDraftStatus(batch);

  const adjustmentByEmployee = normalizeAdjustments(dto.adjustments);
  const salaryActionRows = await repo.listSalaryActionsByPeriod({
    merchantId: merchant.id,
    periodYear,
    periodMonth,
  });
  const approvedLeaveRows = await repo.listApprovedLeaveByPeriod({
    merchantId: merchant.id,
    periodYear,
    periodMonth,
  });
  const salaryActionByEmployee = aggregateSalaryActions(salaryActionRows);
  const leaveAdjustmentByEmployee = aggregateLeaveAdjustments(
    approvedLeaveRows,
    profiles
  );
  const actionIdsToApply = new Set();

  for (const profile of profiles) {
    const employeeUserId = Number(profile.employee_user_id);
    const manualAdjustment = adjustmentByEmployee.get(employeeUserId) || {
      bonuses: 0,
      deductions: 0,
      leaveAdjustment: 0,
      hrNote: null,
    };
    const salaryAction = salaryActionByEmployee.get(employeeUserId) || {
      bonusLike: 0,
      deductionLike: 0,
      actionIds: [],
    };
    const leaveAuto = leaveAdjustmentByEmployee.get(employeeUserId) || {
      leaveAdjustment: 0,
      leaveDaysCount: 0,
      notes: [],
    };

    for (const actionId of salaryAction.actionIds) {
      actionIdsToApply.add(actionId);
    }

    const bonuses =
      Number(manualAdjustment.bonuses || 0) + Number(salaryAction.bonusLike || 0);
    const deductions =
      Number(manualAdjustment.deductions || 0) +
      Number(salaryAction.deductionLike || 0);
    const leaveAdjustment =
      Number(manualAdjustment.leaveAdjustment || 0) +
      Number(leaveAuto.leaveAdjustment || 0);

    const hrNotes = [];
    if (manualAdjustment.hrNote) hrNotes.push(String(manualAdjustment.hrNote));
    if (salaryAction.bonusLike > 0 || salaryAction.deductionLike > 0) {
      hrNotes.push(
        `salary-actions bonus=${Number(salaryAction.bonusLike || 0).toFixed(2)} deduction=${Number(salaryAction.deductionLike || 0).toFixed(2)}`
      );
    }
    if ((leaveAuto.notes || []).length > 0) {
      hrNotes.push(leaveAuto.notes.join(" | "));
    }

    const baseSalary = Number(profile.base_salary || 0);
    const netSalary = Math.max(
      0,
      baseSalary +
        bonuses -
        deductions +
        leaveAdjustment
    );
    await repo.upsertPayrollItem({
      batchId: Number(batch.id),
      merchantId: merchant.id,
      employeeUserId,
      baseSalary,
      bonuses,
      deductions,
      leaveAdjustment,
      netSalary,
      hrNote: hrNotes.length ? hrNotes.join("\n") : null,
    });
  }

  await repo.markSalaryActionsApplied({
    merchantId: merchant.id,
    actionIds: [...actionIdsToApply],
    batchId: Number(batch.id),
  });

  const items = await repo.listPayrollItemsByBatch(batch.id);
  const withTotals = await repo.findPayrollBatchById({
    merchantId: merchant.id,
    batchId: batch.id,
  });

  return {
    merchant: mapMerchant(merchant),
    batch: mapPayrollBatch(withTotals || batch),
    items: items.map(mapPayrollItem),
  };
}

export async function listPayrollBatches(actor, query = {}) {
  const merchant = await resolveMerchantForManagement(actor, query.merchantId);
  const rows = await repo.listPayrollBatches({
    merchantId: merchant.id,
    limit: query.limit,
    status: query.status || null,
  });
  return {
    merchant: mapMerchant(merchant),
    items: rows.map(mapPayrollBatch),
  };
}

export async function getPayrollBatch(actor, batchId, query = {}) {
  const merchant = await resolveMerchantForManagement(actor, query.merchantId);
  const batch = await repo.findPayrollBatchById({
    merchantId: merchant.id,
    batchId: Number(batchId),
  });
  if (!batch) {
    throw new AppError("PAYROLL_BATCH_NOT_FOUND", { status: 404 });
  }
  const items = await repo.listPayrollItemsByBatch(batch.id);
  return {
    merchant: mapMerchant(merchant),
    batch: mapPayrollBatch(batch),
    items: items.map(mapPayrollItem),
  };
}

export async function submitPayrollBatch(actor, batchId, query = {}) {
  const merchant = await resolveMerchantForManagement(actor, query.merchantId);
  const batch = await repo.findPayrollBatchById({
    merchantId: merchant.id,
    batchId: Number(batchId),
  });
  assertPayrollDraftStatus(batch);

  const items = await repo.listPayrollItemsByBatch(batch.id);
  if (!items.length) {
    throw new AppError("PAYROLL_BATCH_EMPTY", { status: 409 });
  }

  const updated = await repo.updatePayrollBatchStatus({
    merchantId: merchant.id,
    batchId: batch.id,
    status: "submitted",
    actorUserId: toActorUserId(actor),
  });

  const accountantUserIds = await repo.listMerchantAccountantUsers(merchant.id);
  if (accountantUserIds.length > 0) {
    await createManyNotifications(
      accountantUserIds.map((userId) => ({
        userId,
        type: "accountant.payroll.submitted",
        title: "Payroll batch ready",
        body: `A payroll batch for ${merchant.name} is waiting for processing.`,
        payload: {
          target: "accountant_dashboard",
          payrollBatchId: Number(batch.id),
          merchantId: Number(merchant.id),
          periodYear: Number(batch.period_year),
          periodMonth: Number(batch.period_month),
        },
      }))
    );
  }

  return {
    merchant: mapMerchant(merchant),
    batch: mapPayrollBatch(updated || batch),
  };
}

export async function closePayrollBatch(actor, batchId, query = {}) {
  const merchant = await resolveMerchantForManagement(actor, query.merchantId);
  const batch = await repo.findPayrollBatchById({
    merchantId: merchant.id,
    batchId: Number(batchId),
  });
  if (!batch) {
    throw new AppError("PAYROLL_BATCH_NOT_FOUND", { status: 404 });
  }
  if (String(batch.status) === "closed") {
    return {
      merchant: mapMerchant(merchant),
      batch: mapPayrollBatch(batch),
    };
  }

  const items = await repo.listPayrollItemsByBatch(batch.id);
  const hasPending = items.some((item) => String(item.status) !== "paid");
  if (hasPending) {
    throw new AppError("PAYROLL_BATCH_HAS_PENDING_ITEMS", { status: 409 });
  }

  const updated = await repo.updatePayrollBatchStatus({
    merchantId: merchant.id,
    batchId: batch.id,
    status: "closed",
    actorUserId: toActorUserId(actor),
  });

  return {
    merchant: mapMerchant(merchant),
    batch: mapPayrollBatch(updated || batch),
  };
}

async function resolveEmployeeProfileFromActor(actor, merchantId = null) {
  return resolveOrCreateEmployeeProfile(actor, merchantId);
}

async function notifyHrAndOwnerForEmployeeRequest({
  merchant,
  actorUserId,
  type,
  title,
  body,
  payload,
}) {
  const recipientIds = new Set();
  const hrUsers = await repo.listMerchantHrUsers(merchant.id);
  for (const userId of hrUsers) recipientIds.add(Number(userId));
  if (merchant.owner_user_id) recipientIds.add(Number(merchant.owner_user_id));
  recipientIds.delete(Number(actorUserId));
  if (!recipientIds.size) return;

  await createManyNotifications(
    [...recipientIds].map((userId) => ({
      userId,
      type,
      title,
      body,
      payload: {
        target: "hr_dashboard",
        merchantId: Number(merchant.id),
        ...payload,
      },
    }))
  );
}

export async function listMyEmployeeProfiles(actor, { merchantId } = {}) {
  const profile = await resolveEmployeeProfileFromActor(actor, merchantId);
  const merchant = await repo.findMerchantById(profile.merchant_id);
  return {
    merchant: mapMerchant(merchant),
    profile: {
      id: Number(profile.id),
      merchantId: Number(profile.merchant_id),
      employeeUserId: Number(profile.employee_user_id),
      roleTag: profile.role_tag || "staff",
      employmentType: profile.employment_type || "full_time",
      baseSalary: Number(profile.base_salary || 0),
      currency: profile.currency || "IQD",
      workDaysPerWeek: Number(profile.work_days_per_week || 6),
      shiftStartTime: profile.shift_start_time || null,
      shiftEndTime: profile.shift_end_time || null,
      joinedAt: profile.joined_at || null,
      isActive: profile.is_active !== false,
      notes: profile.notes || null,
      merchantName: profile.merchant_name || merchant?.name || "",
      merchantType: profile.merchant_type || merchant?.type || "",
    },
  };
}

export async function listMyAttendance(actor, query = {}) {
  const profile = await resolveEmployeeProfileFromActor(actor, query.merchantId);
  const merchant = await repo.findMerchantById(profile.merchant_id);
  const rows = await repo.listAttendanceLogs({
    merchantId: Number(profile.merchant_id),
    employeeUserId: Number(profile.employee_user_id),
    dateFrom: query.dateFrom || null,
    dateTo: query.dateTo || null,
    limit: query.limit,
  });
  return {
    merchant: mapMerchant(merchant),
    items: rows.map(mapAttendance),
  };
}

export async function listMyLeaveRequests(actor, query = {}) {
  const profile = await resolveEmployeeProfileFromActor(actor, query.merchantId);
  const merchant = await repo.findMerchantById(profile.merchant_id);
  const rows = await repo.listLeaveRequests({
    merchantId: Number(profile.merchant_id),
    employeeUserId: Number(profile.employee_user_id),
    status: query.status || null,
    limit: query.limit,
  });
  return {
    merchant: mapMerchant(merchant),
    items: rows.map(mapLeaveRequest),
  };
}

export async function createMyLeaveRequest(actor, dto) {
  const actorUserId = toActorUserId(actor);
  const profile = await resolveEmployeeProfileFromActor(actor, dto.merchantId);
  const merchant = await repo.findMerchantById(profile.merchant_id);
  if (!merchant) {
    throw new AppError("MERCHANT_NOT_FOUND", { status: 404 });
  }
  const from = toDateOnly(dto.dateFrom, null);
  const to = toDateOnly(dto.dateTo, null);
  if (!from || !to || from > to) {
    throw new AppError("LEAVE_DATE_RANGE_INVALID", { status: 400 });
  }

  const created = await repo.createLeaveRequest({
    merchantId: Number(profile.merchant_id),
    employeeUserId: Number(profile.employee_user_id),
    leaveType: dto.leaveType,
    payPolicy: dto.payPolicy,
    dateFrom: from,
    dateTo: to,
    daysCount: dto.daysCount,
    reason: dto.reason || null,
    requestedByUserId: actorUserId,
  });

  await notifyHrAndOwnerForEmployeeRequest({
    merchant,
    actorUserId,
    type: "hr.leave.request_created",
    title: "New leave request",
    body: "An employee submitted a leave request.",
    payload: {
      section: "leave_requests",
      leaveId: Number(created?.id || 0),
    },
  });

  return {
    merchant: mapMerchant(merchant),
    item: created ? mapLeaveRequest(created) : null,
  };
}

export async function listAdvanceRequests(actor, query = {}) {
  const merchant = await resolveMerchantForManagement(actor, query.merchantId);
  const rows = await repo.listAdvanceRequests({
    merchantId: merchant.id,
    employeeUserId: query.employeeUserId ? Number(query.employeeUserId) : null,
    status: query.status || null,
    limit: query.limit,
  });
  return {
    merchant: mapMerchant(merchant),
    items: rows.map(mapAdvanceRequest),
  };
}

export async function listMyAdvanceRequests(actor, query = {}) {
  const profile = await resolveEmployeeProfileFromActor(actor, query.merchantId);
  const merchant = await repo.findMerchantById(profile.merchant_id);
  const rows = await repo.listAdvanceRequests({
    merchantId: Number(profile.merchant_id),
    employeeUserId: Number(profile.employee_user_id),
    status: query.status || null,
    limit: query.limit,
  });
  return {
    merchant: mapMerchant(merchant),
    items: rows.map(mapAdvanceRequest),
  };
}

export async function createMyAdvanceRequest(actor, dto) {
  const actorUserId = toActorUserId(actor);
  const profile = await resolveEmployeeProfileFromActor(actor, dto.merchantId);
  const merchant = await repo.findMerchantById(profile.merchant_id);
  if (!merchant) {
    throw new AppError("MERCHANT_NOT_FOUND", { status: 404 });
  }
  const requestedAmount = Number(dto.requestedAmount || 0);
  if (!Number.isFinite(requestedAmount) || requestedAmount <= 0) {
    throw new AppError("ADVANCE_AMOUNT_INVALID", { status: 400 });
  }

  const created = await repo.createAdvanceRequest({
    merchantId: Number(profile.merchant_id),
    employeeUserId: Number(profile.employee_user_id),
    requestedAmount,
    currency: dto.currency || "IQD",
    reason: dto.reason || null,
    requestedByUserId: actorUserId,
  });

  await notifyHrAndOwnerForEmployeeRequest({
    merchant,
    actorUserId,
    type: "hr.advance.request_created",
    title: "New salary advance request",
    body: "An employee requested a salary advance.",
    payload: {
      section: "advance_requests",
      advanceRequestId: Number(created?.id || 0),
    },
  });

  return {
    merchant: mapMerchant(merchant),
    item: created ? mapAdvanceRequest(created) : null,
  };
}

export async function decideAdvanceRequest(actor, requestId, dto) {
  const merchant = await resolveMerchantForManagement(actor, dto.merchantId);
  const actorUserId = toActorUserId(actor);
  const current = await repo.findAdvanceRequestById({
    merchantId: merchant.id,
    requestId: Number(requestId),
  });
  if (!current) {
    throw new AppError("ADVANCE_REQUEST_NOT_FOUND", { status: 404 });
  }
  if (String(current.status) !== "pending") {
    throw new AppError("ADVANCE_REQUEST_ALREADY_DECIDED", { status: 409 });
  }

  let updatedRequest = null;
  let salaryAction = null;
  if (String(dto.status) === "approved") {
    const now = new Date();
    const out = await repo.approveAdvanceRequest({
      merchantId: merchant.id,
      requestId: Number(requestId),
      decidedByUserId: actorUserId,
      decisionNote: dto.decisionNote || null,
      effectiveYear: Number(dto.effectiveYear || now.getUTCFullYear()),
      effectiveMonth: Number(dto.effectiveMonth || now.getUTCMonth() + 1),
    });
    if (!out) {
      throw new AppError("ADVANCE_REQUEST_NOT_FOUND", { status: 404 });
    }
    updatedRequest = out.request || null;
    salaryAction = out.salaryAction || null;
  } else {
    updatedRequest = await repo.rejectAdvanceRequest({
      merchantId: merchant.id,
      requestId: Number(requestId),
      decidedByUserId: actorUserId,
      decisionNote: dto.decisionNote || null,
    });
  }

  const employeeUserId = Number(current.employee_user_id || 0);
  if (employeeUserId > 0) {
    await createManyNotifications([
      {
        userId: employeeUserId,
        type: "employee.advance.request_decided",
        title: "Advance request updated",
        body: `Your advance request was ${String(dto.status)}.`,
        payload: {
          target: "employee_portal",
          section: "advance_requests",
          advanceRequestId: Number(requestId),
          status: String(dto.status),
          merchantId: Number(merchant.id),
        },
      },
    ]);
  }

  return {
    merchant: mapMerchant(merchant),
    item: updatedRequest ? mapAdvanceRequest(updatedRequest) : null,
    salaryAction: salaryAction ? mapSalaryAction(salaryAction) : null,
  };
}

export async function listLeaveRequests(actor, query = {}) {
  const merchant = await resolveMerchantForManagement(actor, query.merchantId);
  const rows = await repo.listLeaveRequests({
    merchantId: merchant.id,
    employeeUserId: query.employeeUserId ? Number(query.employeeUserId) : null,
    dateFrom: query.dateFrom || null,
    dateTo: query.dateTo || null,
    status: query.status || null,
    limit: query.limit,
  });
  return {
    merchant: mapMerchant(merchant),
    items: rows.map(mapLeaveRequest),
  };
}

export async function createLeaveRequest(actor, dto) {
  const merchant = await resolveMerchantForManagement(actor, dto.merchantId);
  const actorUserId = toActorUserId(actor);
  const employeeUserId = Number(dto.employeeUserId);
  if (!Number.isInteger(employeeUserId) || employeeUserId <= 0) {
    throw new AppError("EMPLOYEE_REQUIRED", { status: 400 });
  }
  const profile = await repo.findEmployeeProfileForMerchant({
    merchantId: merchant.id,
    employeeUserId,
  });
  if (!profile) {
    throw new AppError("EMPLOYEE_PROFILE_NOT_FOUND", { status: 404 });
  }
  const from = toDateOnly(dto.dateFrom, null);
  const to = toDateOnly(dto.dateTo, null);
  if (!from || !to) {
    throw new AppError("LEAVE_DATE_INVALID", { status: 400 });
  }
  if (from > to) {
    throw new AppError("LEAVE_DATE_RANGE_INVALID", { status: 400 });
  }

  const created = await repo.createLeaveRequest({
    merchantId: merchant.id,
    employeeUserId,
    leaveType: dto.leaveType,
    payPolicy: dto.payPolicy,
    dateFrom: from,
    dateTo: to,
    daysCount: dto.daysCount,
    reason: dto.reason,
    requestedByUserId: actorUserId,
  });

  const recipientIds = new Set();
  const hrUsers = await repo.listMerchantHrUsers(merchant.id);
  for (const userId of hrUsers) recipientIds.add(Number(userId));
  if (merchant.owner_user_id) recipientIds.add(Number(merchant.owner_user_id));
  recipientIds.delete(actorUserId);

  if (recipientIds.size > 0) {
    await createManyNotifications(
      [...recipientIds].map((userId) => ({
        userId,
        type: "hr.leave.request_created",
        title: "New leave request",
        body: `A new leave request was added for ${created?.date_from ?? ""} - ${created?.date_to ?? ""}.`,
        payload: {
          target: "hr_dashboard",
          merchantId: Number(merchant.id),
          leaveId: Number(created?.id || 0),
          section: "leave_requests",
        },
      }))
    );
  }

  return {
    merchant: mapMerchant(merchant),
    item: created ? mapLeaveRequest(created) : null,
  };
}

export async function decideLeaveRequest(actor, leaveId, dto) {
  const merchant = await resolveMerchantForManagement(actor, dto.merchantId);
  const actorUserId = toActorUserId(actor);
  const current = await repo.findLeaveRequestById({
    merchantId: merchant.id,
    leaveId: Number(leaveId),
  });
  if (!current) {
    throw new AppError("LEAVE_REQUEST_NOT_FOUND", { status: 404 });
  }
  if (String(current.status) !== "pending") {
    throw new AppError("LEAVE_REQUEST_ALREADY_DECIDED", { status: 409 });
  }

  const decided = await repo.decideLeaveRequest({
    merchantId: merchant.id,
    leaveId: Number(leaveId),
    status: dto.status,
    decisionNote: dto.decisionNote || null,
    decidedByUserId: actorUserId,
  });

  const employeeUserId = Number(current.employee_user_id || 0);
  if (employeeUserId > 0) {
    await createManyNotifications([
      {
        userId: employeeUserId,
        type: "employee.leave.request_decided",
        title: "Leave request updated",
        body: `Your leave request has been marked as ${String(dto.status)}.`,
        payload: {
          target: "hr_dashboard",
          section: "leave_requests",
          leaveId: Number(leaveId),
          status: String(dto.status),
          merchantId: Number(merchant.id),
        },
      },
    ]);
  }

  return {
    merchant: mapMerchant(merchant),
    item: decided ? mapLeaveRequest(decided) : mapLeaveRequest(current),
  };
}

export async function listSalaryActions(actor, query = {}) {
  const merchant = await resolveMerchantForManagement(actor, query.merchantId);
  const rows = await repo.listSalaryActions({
    merchantId: merchant.id,
    employeeUserId: query.employeeUserId ? Number(query.employeeUserId) : null,
    periodYear: query.periodYear ? Number(query.periodYear) : null,
    periodMonth: query.periodMonth ? Number(query.periodMonth) : null,
    status: query.status || null,
    limit: query.limit,
  });
  return {
    merchant: mapMerchant(merchant),
    items: rows.map(mapSalaryAction),
  };
}

export async function createSalaryAction(actor, dto) {
  const merchant = await resolveMerchantForManagement(actor, dto.merchantId);
  const actorUserId = toActorUserId(actor);
  const employeeUserId = Number(dto.employeeUserId);
  if (!Number.isInteger(employeeUserId) || employeeUserId <= 0) {
    throw new AppError("EMPLOYEE_REQUIRED", { status: 400 });
  }
  const profile = await repo.findEmployeeProfileForMerchant({
    merchantId: merchant.id,
    employeeUserId,
  });
  if (!profile) {
    throw new AppError("EMPLOYEE_PROFILE_NOT_FOUND", { status: 404 });
  }

  const created = await repo.createSalaryAction({
    merchantId: merchant.id,
    employeeUserId,
    actionType: dto.actionType,
    amount: dto.amount,
    currency: dto.currency || "IQD",
    effectiveYear: dto.effectiveYear,
    effectiveMonth: dto.effectiveMonth,
    description: dto.description || null,
    createdByUserId: actorUserId,
  });

  if (employeeUserId > 0) {
    await createManyNotifications([
      {
        userId: employeeUserId,
        type: "employee.salary.action_created",
        title: "Compensation update",
        body: `A ${String(dto.actionType)} action was added to your payroll workflow.`,
        payload: {
          target: "hr_dashboard",
          section: "salary_actions",
          salaryActionId: Number(created?.id || 0),
          merchantId: Number(merchant.id),
        },
      },
    ]);
  }

  return {
    merchant: mapMerchant(merchant),
    item: created ? mapSalaryAction(created) : null,
  };
}

export async function updateSalaryActionStatus(actor, actionId, dto) {
  const merchant = await resolveMerchantForManagement(actor, dto.merchantId);
  const updated = await repo.updateSalaryActionStatus({
    merchantId: merchant.id,
    actionId: Number(actionId),
    status: dto.status,
  });
  if (!updated) {
    throw new AppError("SALARY_ACTION_NOT_FOUND", { status: 404 });
  }
  return {
    merchant: mapMerchant(merchant),
    item: mapSalaryAction(updated),
  };
}

export async function getAttendanceArchive(actor, query = {}) {
  const merchant = await resolveMerchantForManagement(actor, query.merchantId);
  const periodYear = Number(query.periodYear || new Date().getUTCFullYear());
  const periodMonth = Number(query.periodMonth || new Date().getUTCMonth() + 1);
  if (!Number.isInteger(periodYear) || periodYear < 2000 || periodYear > 2100) {
    throw new AppError("ARCHIVE_PERIOD_YEAR_INVALID", { status: 400 });
  }
  if (!Number.isInteger(periodMonth) || periodMonth < 1 || periodMonth > 12) {
    throw new AppError("ARCHIVE_PERIOD_MONTH_INVALID", { status: 400 });
  }

  const [attendanceRows, leaveRows, salaryActionRows] = await Promise.all([
    repo.getAttendanceMonthlyArchive({
      merchantId: merchant.id,
      periodYear,
      periodMonth,
    }),
    repo.listLeaveRequests({
      merchantId: merchant.id,
      dateFrom: `${periodYear}-${String(periodMonth).padStart(2, "0")}-01`,
      dateTo: `${periodYear}-${String(periodMonth).padStart(2, "0")}-31`,
      limit: 300,
    }),
    repo.listSalaryActions({
      merchantId: merchant.id,
      periodYear,
      periodMonth,
      limit: 300,
    }),
  ]);

  return {
    merchant: mapMerchant(merchant),
    periodYear,
    periodMonth,
    attendance: attendanceRows.map((row) => ({
      employeeUserId: Number(row.employee_user_id),
      employeeFullName: row.employee_full_name || "",
      totalDays: Number(row.total_days || 0),
      presentDays: Number(row.present_days || 0),
      absentDays: Number(row.absent_days || 0),
      leaveDays: Number(row.leave_days || 0),
    })),
    leaveRequests: leaveRows.map(mapLeaveRequest),
    salaryActions: salaryActionRows.map(mapSalaryAction),
  };
}

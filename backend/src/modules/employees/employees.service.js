/**
 * Purpose:
 * منطق إدارة موظفي الشركة (المرحلة 6): تحقق + تفويض إلى repo.
 */

import { AppError } from "../../shared/utils/errors.js";
import { hashPin } from "../../shared/utils/hash.js";
import * as repo from "./employees.repo.js";
import { createUser, findUserByPhone } from "../auth/auth.repo.js";
import { runWithGeneratedAppUserUsername } from "../auth/auth.service.js";
import {
  assignAdminRole,
  grantUserPermission,
} from "../security/permissions.service.js";
import { ROLE_TEMPLATES } from "../security/permissions.catalog.js";
import { JOB_ROLE_METADATA } from "../security/permissions.metadata.js";

// Maps a job role to its HR department bucket (company_employee_profile enum).
const JOB_ROLE_DEPARTMENT = Object.freeze({
  follow_up_manager: "management",
  sales_agent: "marketing",
  marketing_agent: "marketing",
  subscriptions_monitor: "monitoring",
  residents_moderator: "monitoring",
});

function assertEnum(value, allowed, code) {
  if (!allowed.includes(String(value || ""))) {
    throw new AppError(code, { status: 400 });
  }
}

export async function saveEmployee({ actorUserId, dto }) {
  const userId = Number(dto?.userId);
  if (!Number.isInteger(userId) || userId <= 0) {
    throw new AppError("INVALID_EMPLOYEE_USER", { status: 400 });
  }
  assertEnum(dto.department, repo.DEPARTMENTS, "INVALID_DEPARTMENT");
  const employmentType = dto.employmentType || "full_time";
  assertEnum(employmentType, repo.EMPLOYMENT_TYPES, "INVALID_EMPLOYMENT_TYPE");
  const status = dto.status || "active";
  assertEnum(status, repo.EMPLOYEE_STATUSES, "INVALID_EMPLOYEE_STATUS");

  const result = await repo.upsertEmployee({
    userId,
    department: dto.department,
    jobTitle: dto.jobTitle || null,
    employmentType,
    managerUserId: dto.managerUserId || null,
    status,
    startDate: dto.startDate || null,
    baseSalaryIqd:
      dto.baseSalaryIqd != null && dto.baseSalaryIqd !== ""
        ? Number(dto.baseSalaryIqd)
        : null,
    notes: dto.notes || null,
    actorUserId,
  });

  // إعطاء الصلاحيات عند الإنشاء/التعديل: قالب دور اختياري + منح فردية اختيارية.
  // تمرّ عبر خدمة RBAC التي تفرض أن يملك المنفِّذ employees.permissions.manage
  // وتسجّل التدقيق وترفع permission_version — فتُصبح الصلاحيات سارية فوراً.
  if (dto.adminRoleKey !== undefined) {
    await assignAdminRole({
      actorUserId,
      targetUserId: userId,
      roleKey: dto.adminRoleKey || null,
      reason: "assigned during employee save",
    });
  }
  if (Array.isArray(dto.permissions)) {
    for (const grant of dto.permissions) {
      if (!grant || !grant.permissionKey) continue;
      await grantUserPermission({
        actorUserId,
        targetUserId: userId,
        permissionKey: String(grant.permissionKey),
        scope: grant.scope || "all",
        effect: grant.effect === "revoke" ? "revoke" : "grant",
        expiresAt: grant.expiresAt || null,
        reason: grant.reason || "assigned during employee save",
      });
    }
  }

  return result;
}

/**
 * Creates a brand-new, standalone employee account — NOT linked to any existing
 * user and fully separated from the customer surface. The account gets the
 * dedicated `staff` base role (routes to the permission-gated admin dashboard,
 * never the customer UI, and never passes admin-only routes), a job-role
 * template, an HR profile (residence, employee code, salary), and optional
 * individual permission overrides. RBAC enforces the actor's authority to grant
 * the role/permissions. On any downstream failure the half-created account is
 * removed so no orphan is left behind.
 */
export async function createEmployeeAccount({ actorUserId, dto }) {
  const fullName = String(dto?.fullName || "").trim();
  const phone = String(dto?.phone || "").trim();
  const pin = String(dto?.pin || "").trim();
  const jobRoleKey = String(dto?.jobRoleKey || "").trim();

  if (fullName.length < 2) {
    throw new AppError("INVALID_EMPLOYEE_NAME", { status: 400 });
  }
  if (!/^\d{6,15}$/.test(phone)) {
    throw new AppError("INVALID_EMPLOYEE_PHONE", { status: 400 });
  }
  if (!/^\d{4,8}$/.test(pin)) {
    throw new AppError("INVALID_EMPLOYEE_PIN", { status: 400 });
  }
  if (!JOB_ROLE_METADATA[jobRoleKey] || !ROLE_TEMPLATES[jobRoleKey]) {
    throw new AppError("INVALID_JOB_ROLE", { status: 400 });
  }

  const residence = String(dto?.residence || "").trim();
  const employeeCode = String(dto?.employeeCode || "").trim() || null;
  const jobTitle =
    String(dto?.jobTitle || "").trim() ||
    JOB_ROLE_METADATA[jobRoleKey].labelAr ||
    null;
  const department = JOB_ROLE_DEPARTMENT[jobRoleKey] || "other";
  const baseSalaryIqd =
    dto?.baseSalaryIqd != null && dto.baseSalaryIqd !== ""
      ? Number(dto.baseSalaryIqd)
      : null;
  if (
    baseSalaryIqd != null &&
    (!Number.isFinite(baseSalaryIqd) || baseSalaryIqd < 0)
  ) {
    throw new AppError("INVALID_SALARY_AMOUNT", { status: 400 });
  }
  const permissions = Array.isArray(dto?.permissions) ? dto.permissions : [];

  const exists = await findUserByPhone(phone);
  if (exists) {
    throw new AppError("PHONE_EXISTS", { status: 409 });
  }

  const pinHash = await hashPin(pin);
  const user = await runWithGeneratedAppUserUsername({
    fullName,
    phone,
    execute: (username) =>
      createUser({
        fullName,
        username,
        phone,
        pinHash,
        block: residence,
        buildingNumber: "",
        apartment: "",
        role: "staff",
        analyticsConsentGranted: true,
        analyticsConsentVersion: "employee_created_v1",
        analyticsConsentGrantedAt: new Date(),
      }),
  });

  try {
    await repo.upsertEmployee({
      userId: Number(user.id),
      department,
      jobTitle,
      employmentType: "full_time",
      status: "active",
      baseSalaryIqd,
      employeeCode,
      actorUserId,
    });
    // RBAC guards apply here: the actor must be allowed to grant this role's keys.
    await assignAdminRole({
      actorUserId,
      targetUserId: Number(user.id),
      roleKey: jobRoleKey,
      reason: "employee account creation",
    });
    for (const grant of permissions) {
      if (!grant || !grant.permissionKey) continue;
      await grantUserPermission({
        actorUserId,
        targetUserId: Number(user.id),
        permissionKey: String(grant.permissionKey),
        scope: grant.scope || "all",
        effect: grant.effect === "revoke" ? "revoke" : "grant",
        reason: "employee account creation",
      });
    }
  } catch (error) {
    // Roll back the half-created account so no orphan staff row survives.
    await repo.deleteStaffAccount(Number(user.id)).catch(() => {});
    throw error;
  }

  return {
    id: Number(user.id),
    fullName: user.full_name,
    phone: user.phone,
    role: user.role,
    jobRoleKey,
    jobTitle,
    department,
    employeeCode,
    baseSalaryIqd,
  };
}

export async function listEmployees(query) {
  return repo.listEmployees(query);
}

/// The signed-in employee's own dashboard (self-scoped). Returns null when the
/// caller has no employee profile (e.g. a plain admin) so the UI can say so.
export async function getMyEmployeeDashboard(userId) {
  return repo.getMyEmployeeDashboard(userId);
}

export async function lookupUsers(query) {
  return repo.lookupUsers(query);
}

export async function getEmployeeProfile(userId) {
  const employee = await repo.getEmployeeByUserId(userId);
  if (!employee) throw new AppError("EMPLOYEE_NOT_FOUND", { status: 404 });
  const salaryHistory = await repo.listSalaryHistory(userId);
  return { employee, salaryHistory };
}

export async function updateSalary({ actorUserId, userId, dto }) {
  const amount = Number(dto?.baseSalaryIqd);
  if (!Number.isFinite(amount) || amount < 0) {
    throw new AppError("INVALID_SALARY_AMOUNT", { status: 400 });
  }
  const existing = await repo.getEmployeeByUserId(userId);
  if (!existing) throw new AppError("EMPLOYEE_NOT_FOUND", { status: 404 });
  return repo.setSalary({
    userId,
    baseSalaryIqd: amount,
    effectiveFrom: dto.effectiveFrom || new Date().toISOString().slice(0, 10),
    reason: dto.reason || null,
    actorUserId,
  });
}

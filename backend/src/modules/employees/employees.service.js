/**
 * Purpose:
 * منطق إدارة موظفي الشركة (المرحلة 6): تحقق + تفويض إلى repo.
 */

import { AppError } from "../../shared/utils/errors.js";
import * as repo from "./employees.repo.js";

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

  return repo.upsertEmployee({
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
}

export async function listEmployees(query) {
  return repo.listEmployees(query);
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

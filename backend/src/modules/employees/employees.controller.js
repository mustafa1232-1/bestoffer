/**
 * Purpose:
 * controllers إدارة موظفي الشركة (المرحلة 6). خلف requireBackoffice + صلاحيات
 * employees.*. قراءة/تعديل الراتب أفعال حساسة تُسجَّل في التدقيق.
 */

import * as service from "./employees.service.js";
import { recordAudit, auditContextFromReq } from "../security/audit.service.js";

function parseUserId(req, res) {
  const id = Number(req.params?.userId);
  if (!Number.isInteger(id) || id <= 0) {
    res.status(400).json({ message: "VALIDATION_ERROR", fields: ["userId"] });
    return null;
  }
  return id;
}

export async function lookupUsers(req, res, next) {
  try {
    const items = await service.lookupUsers({
      search: req.query?.q || req.query?.search || "",
      limit: req.query?.limit ? Number(req.query.limit) : 15,
    });
    return res.json({ items });
  } catch (error) {
    return next(error);
  }
}

export async function listEmployees(req, res, next) {
  try {
    const out = await service.listEmployees({
      department: req.query?.department || null,
      status: req.query?.status || null,
      search: req.query?.search || null,
      limit: req.query?.limit ? Number(req.query.limit) : 25,
      offset: req.query?.offset ? Number(req.query.offset) : 0,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function getEmployee(req, res, next) {
  try {
    const userId = parseUserId(req, res);
    if (!userId) return;
    const out = await service.getEmployeeProfile(userId);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function createEmployeeAccount(req, res, next) {
  try {
    const result = await service.createEmployeeAccount({
      actorUserId: req.userId,
      dto: { ...(req.body || {}) },
    });
    void recordAudit({
      ...auditContextFromReq(req),
      actionKey: "employees.create",
      summary: `إنشاء حساب موظف #${result.id} (${result.jobRoleKey})`,
      targetType: "company_employee",
      targetId: result.id,
      permissionKey: "employees.create",
      after: result,
    });
    return res.status(201).json({ employee: result });
  } catch (error) {
    return next(error);
  }
}

export async function saveEmployee(req, res, next) {
  try {
    const dto = { ...(req.body || {}) };
    if (req.params?.userId) dto.userId = Number(req.params.userId);
    const result = await service.saveEmployee({
      actorUserId: req.userId,
      dto,
    });
    void recordAudit({
      ...auditContextFromReq(req),
      actionKey: result.created ? "employees.create" : "employees.update",
      summary: `${result.created ? "إنشاء" : "تعديل"} موظف #${result.employee.user_id}`,
      targetType: "company_employee",
      targetId: result.employee.user_id,
      permissionKey: result.created ? "employees.create" : "employees.update",
      before: result.before,
      after: result.employee,
    });
    return res.status(result.created ? 201 : 200).json({ employee: result.employee });
  } catch (error) {
    return next(error);
  }
}

export async function getSalary(req, res, next) {
  try {
    const userId = parseUserId(req, res);
    if (!userId) return;
    const out = await service.getEmployeeProfile(userId);
    void recordAudit({
      ...auditContextFromReq(req),
      actionKey: "employees.salary.read",
      summary: `عرض راتب الموظف #${userId}`,
      targetType: "company_employee",
      targetId: userId,
      permissionKey: "employees.salary.read",
    });
    return res.json({
      baseSalaryIqd: out.employee.base_salary_iqd,
      salaryHistory: out.salaryHistory,
    });
  } catch (error) {
    return next(error);
  }
}

export async function updateSalary(req, res, next) {
  try {
    const userId = parseUserId(req, res);
    if (!userId) return;
    const contract = await service.updateSalary({
      actorUserId: req.userId,
      userId,
      dto: req.body || {},
    });
    void recordAudit({
      ...auditContextFromReq(req),
      actionKey: "employees.salary.update",
      summary: `تحديث راتب الموظف #${userId}`,
      targetType: "company_employee",
      targetId: userId,
      permissionKey: "employees.salary.update",
      after: { baseSalaryIqd: contract.base_salary_iqd, effectiveFrom: contract.effective_from },
      reason: req.body?.reason || null,
    });
    return res.status(201).json({ contract });
  } catch (error) {
    return next(error);
  }
}

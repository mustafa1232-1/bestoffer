/**
 * Purpose:
 * endpoints الخدمة الذاتية لموظف الشركة (المرحلة 7): حضور/خروج، مصاريف، كشوف
 * رواتبه، وتأكيد الاستلام. requireAuth + يجب أن يكون موظف شركة.
 */

import { AppError } from "../../shared/utils/errors.js";
import * as attendance from "./attendance.repo.js";
import * as payroll from "./payroll.repo.js";
import * as evaluation from "./evaluation.repo.js";
import { getEmployeeByUserId } from "./employees.repo.js";

const EXPENSE_CATEGORIES = ["food", "transport", "communication", "work_task", "other"];

async function assertEmployee(userId) {
  const emp = await getEmployeeByUserId(userId);
  if (!emp) throw new AppError("NOT_COMPANY_EMPLOYEE", { status: 403 });
  return emp;
}

export async function checkIn(req, res, next) {
  try {
    await assertEmployee(req.userId);
    const result = await attendance.checkIn({
      employeeUserId: req.userId,
      note: typeof req.body?.note === "string" ? req.body.note.trim() : null,
    });
    if (result.code === "ALREADY_CHECKED_IN") {
      throw new AppError("ATTENDANCE_ALREADY_OPEN", { status: 409 });
    }
    return res.status(201).json({ attendance: result.attendance });
  } catch (error) {
    return next(error);
  }
}

export async function checkOut(req, res, next) {
  try {
    await assertEmployee(req.userId);
    const result = await attendance.checkOut({
      employeeUserId: req.userId,
      note: typeof req.body?.note === "string" ? req.body.note.trim() : null,
    });
    if (result.code === "NOT_CHECKED_IN") {
      throw new AppError("ATTENDANCE_NOT_OPEN", { status: 409 });
    }
    return res.json({ attendance: result.attendance });
  } catch (error) {
    return next(error);
  }
}

export async function myStatus(req, res, next) {
  try {
    await assertEmployee(req.userId);
    const open = await attendance.currentOpenSession(req.userId);
    return res.json({ checkedIn: Boolean(open), openSession: open || null });
  } catch (error) {
    return next(error);
  }
}

export async function myAttendance(req, res, next) {
  try {
    await assertEmployee(req.userId);
    const rows = await attendance.listForEmployee({
      employeeUserId: req.userId,
      limit: req.query?.limit ? Number(req.query.limit) : 30,
      offset: req.query?.offset ? Number(req.query.offset) : 0,
    });
    return res.json({ items: rows });
  } catch (error) {
    return next(error);
  }
}

export async function submitExpense(req, res, next) {
  try {
    await assertEmployee(req.userId);
    const category = String(req.body?.category || "").trim();
    const amount = Number(req.body?.amountIqd);
    if (!EXPENSE_CATEGORIES.includes(category)) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: ["category"] });
    }
    if (!Number.isFinite(amount) || amount < 0) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: ["amountIqd"] });
    }
    const expense = await attendance.submitExpense({
      employeeUserId: req.userId,
      category,
      amountIqd: amount,
      expenseDate: req.body?.expenseDate || null,
      reason: typeof req.body?.reason === "string" ? req.body.reason.trim() : null,
      receiptUrl: typeof req.body?.receiptUrl === "string" ? req.body.receiptUrl.trim() : null,
    });
    return res.status(201).json({ expense });
  } catch (error) {
    return next(error);
  }
}

export async function myExpenses(req, res, next) {
  try {
    await assertEmployee(req.userId);
    const rows = await attendance.listMyExpenses({ employeeUserId: req.userId });
    return res.json({ items: rows });
  } catch (error) {
    return next(error);
  }
}

export async function myPayslips(req, res, next) {
  try {
    await assertEmployee(req.userId);
    const rows = await payroll.listItemsForEmployee({ employeeUserId: req.userId });
    return res.json({ items: rows });
  } catch (error) {
    return next(error);
  }
}

export async function objectToReview(req, res, next) {
  try {
    await assertEmployee(req.userId);
    const p = String(req.params?.period || "").trim();
    if (!/^\d{4}-\d{2}$/.test(p)) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: ["period"] });
    }
    const text = typeof req.body?.objectionText === "string" ? req.body.objectionText.trim() : "";
    if (!text) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: ["objectionText"] });
    }
    const result = await evaluation.addObjection({
      employeeUserId: req.userId,
      period: p,
      objectionText: text,
    });
    if (result.code !== "OK") throw new AppError("REVIEW_NOT_FOUND", { status: 404 });
    return res.json({ review: result.review });
  } catch (error) {
    return next(error);
  }
}

export async function acknowledgePayslip(req, res, next) {
  try {
    await assertEmployee(req.userId);
    const runId = Number(req.params?.runId);
    if (!Number.isInteger(runId) || runId <= 0) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: ["runId"] });
    }
    const result = await payroll.acknowledgeItem({ runId, employeeUserId: req.userId });
    if (result.code !== "OK") {
      throw new AppError("PAYSLIP_NOT_FOUND", { status: 404 });
    }
    return res.json({ item: result.item });
  } catch (error) {
    return next(error);
  }
}

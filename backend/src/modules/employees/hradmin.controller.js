/**
 * Purpose:
 * controllers إدارية للحضور والمصاريف والرواتب (المرحلة 7). خلف صلاحيات
 * attendance.* و payroll.*. أفعال الإطلاق/التسديد حساسة وتُسجَّل.
 */

import { AppError } from "../../shared/utils/errors.js";
import * as attendance from "./attendance.repo.js";
import * as payroll from "./payroll.repo.js";
import { recordAudit, auditContextFromReq } from "../security/audit.service.js";

// ---------- الحضور ----------

export async function listAttendance(req, res, next) {
  try {
    const rows = await attendance.adminList({
      employeeUserId: req.query?.userId ? Number(req.query.userId) : null,
      limit: req.query?.limit ? Number(req.query.limit) : 50,
      offset: req.query?.offset ? Number(req.query.offset) : 0,
    });
    return res.json({ items: rows });
  } catch (error) {
    return next(error);
  }
}

export async function correctAttendance(req, res, next) {
  try {
    const attendanceId = Number(req.params?.attendanceId);
    if (!Number.isInteger(attendanceId) || attendanceId <= 0) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: ["attendanceId"] });
    }
    const reason = typeof req.body?.reason === "string" ? req.body.reason.trim() : "";
    if (!reason) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: ["reason"] });
    }
    const result = await attendance.adminCorrect({
      attendanceId,
      checkInAt: req.body?.checkInAt || null,
      checkOutAt: req.body?.checkOutAt || null,
      reason,
      correctedByUserId: req.userId,
    });
    if (result.code !== "OK") throw new AppError("ATTENDANCE_NOT_FOUND", { status: 404 });
    void recordAudit({
      ...auditContextFromReq(req),
      actionKey: "attendance.approve",
      summary: `تصحيح حضور #${attendanceId}`,
      targetType: "company_attendance",
      targetId: attendanceId,
      permissionKey: "attendance.approve",
      reason,
    });
    return res.json({ attendance: result.attendance });
  } catch (error) {
    return next(error);
  }
}

// ---------- المصاريف ----------

export async function listExpenses(req, res, next) {
  try {
    const rows = await attendance.adminListExpenses({
      status: req.query?.status || null,
      limit: req.query?.limit ? Number(req.query.limit) : 100,
    });
    return res.json({ items: rows });
  } catch (error) {
    return next(error);
  }
}

export async function reviewExpense(req, res, next) {
  try {
    const expenseId = Number(req.params?.expenseId);
    if (!Number.isInteger(expenseId) || expenseId <= 0) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: ["expenseId"] });
    }
    const decision = String(req.body?.status || "").trim();
    if (!["approved", "rejected"].includes(decision)) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: ["status"] });
    }
    const result = await attendance.reviewExpense({
      expenseId,
      status: decision,
      reviewedByUserId: req.userId,
    });
    if (result.code !== "OK") throw new AppError("EXPENSE_NOT_REVIEWABLE", { status: 409 });
    return res.json({ expense: result.expense });
  } catch (error) {
    return next(error);
  }
}

// ---------- الرواتب ----------

export async function listRuns(req, res, next) {
  try {
    const rows = await payroll.listRuns({ limit: req.query?.limit ? Number(req.query.limit) : 24 });
    return res.json({ items: rows });
  } catch (error) {
    return next(error);
  }
}

export async function createRun(req, res, next) {
  try {
    const periodMonth = String(req.body?.periodMonth || "").trim();
    if (!/^\d{4}-\d{2}$/.test(periodMonth)) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: ["periodMonth"] });
    }
    const result = await payroll.createRun({
      periodMonth,
      createdByUserId: req.userId,
      notes: typeof req.body?.notes === "string" ? req.body.notes.trim() : null,
    });
    if (result.code === "PERIOD_EXISTS") {
      throw new AppError("PAYROLL_PERIOD_EXISTS", { status: 409 });
    }
    return res.status(201).json({ run: result.run });
  } catch (error) {
    return next(error);
  }
}

export async function getRun(req, res, next) {
  try {
    const runId = Number(req.params?.runId);
    const out = await payroll.getRun(runId);
    if (!out) throw new AppError("PAYROLL_RUN_NOT_FOUND", { status: 404 });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function calculateRun(req, res, next) {
  try {
    const runId = Number(req.params?.runId);
    const result = await payroll.calculateRun({ runId, actorUserId: req.userId });
    if (result.code === "RUN_NOT_FOUND") throw new AppError("PAYROLL_RUN_NOT_FOUND", { status: 404 });
    if (result.code !== "OK") {
      throw new AppError("PAYROLL_NOT_RECALCULABLE", {
        status: 409,
        details: { currentStatus: result.currentStatus },
      });
    }
    return res.json({ run: result.run, employeeCount: result.employeeCount });
  } catch (error) {
    return next(error);
  }
}

async function doTransition(req, res, next, toStatus, permissionKey) {
  try {
    const runId = Number(req.params?.runId);
    const result = await payroll.transitionRun({
      runId,
      toStatus,
      actorUserId: req.userId,
      requireDistinctApprover: true,
    });
    if (result.code === "RUN_NOT_FOUND") throw new AppError("PAYROLL_RUN_NOT_FOUND", { status: 404 });
    if (result.code === "SEPARATION_OF_DUTIES") {
      throw new AppError("PAYROLL_SEPARATION_OF_DUTIES", { status: 409 });
    }
    if (result.code !== "OK") {
      throw new AppError("PAYROLL_INVALID_TRANSITION", {
        status: 409,
        details: { currentStatus: result.currentStatus },
      });
    }
    void recordAudit({
      ...auditContextFromReq(req),
      actionKey: permissionKey,
      summary: `دورة الراتب #${runId} → ${toStatus}`,
      targetType: "company_payroll_run",
      targetId: runId,
      permissionKey,
      before: { status: result.previousStatus },
      after: { status: toStatus },
    });
    return res.json({ run: result.run });
  } catch (error) {
    return next(error);
  }
}

export const submitRunForReview = (req, res, next) =>
  doTransition(req, res, next, "UNDER_REVIEW", "payroll.review");
export const approveRun = (req, res, next) =>
  doTransition(req, res, next, "APPROVED", "payroll.approve");
export const releaseRun = (req, res, next) =>
  doTransition(req, res, next, "RELEASED", "payroll.release");
const PAYMENT_METHODS = ["cash", "bank_transfer", "wallet", "card", "other"];

export async function markRunPaid(req, res, next) {
  try {
    const runId = Number(req.params?.runId);
    const paymentMethod = String(req.body?.paymentMethod || "").trim();
    if (!PAYMENT_METHODS.includes(paymentMethod)) {
      return res
        .status(400)
        .json({ message: "VALIDATION_ERROR", fields: ["paymentMethod"] });
    }
    const paymentReference =
      typeof req.body?.paymentReference === "string"
        ? req.body.paymentReference.trim() || null
        : null;
    const result = await payroll.transitionRun({
      runId,
      toStatus: "PAID",
      actorUserId: req.userId,
      requireDistinctApprover: true,
      paymentMethod,
      paymentReference,
    });
    if (result.code === "RUN_NOT_FOUND") {
      throw new AppError("PAYROLL_RUN_NOT_FOUND", { status: 404 });
    }
    if (result.code !== "OK") {
      throw new AppError("PAYROLL_INVALID_TRANSITION", {
        status: 409,
        details: { currentStatus: result.currentStatus },
      });
    }
    void recordAudit({
      ...auditContextFromReq(req),
      actionKey: "payroll.mark_paid",
      summary: `تسديد دورة الراتب #${runId} عبر ${paymentMethod}`,
      targetType: "company_payroll_run",
      targetId: runId,
      permissionKey: "payroll.mark_paid",
      before: { status: result.previousStatus },
      after: { status: "PAID", paymentMethod, paymentReference },
    });
    return res.json({ run: result.run });
  } catch (error) {
    return next(error);
  }
}
export const acknowledgeRun = (req, res, next) =>
  doTransition(req, res, next, "ACKNOWLEDGED", "payroll.review");
export const archiveRun = (req, res, next) =>
  doTransition(req, res, next, "ARCHIVED", "payroll.review");

/**
 * انتقال حر (للاستخدام الداخلي/المرونة). الصلاحية تُفرض على مستوى المسار.
 */
export async function transitionRun(req, res, next) {
  try {
    const runId = Number(req.params?.runId);
    const toStatus = String(req.body?.toStatus || "").trim().toUpperCase();
    const result = await payroll.transitionRun({
      runId,
      toStatus,
      actorUserId: req.userId,
      requireDistinctApprover: true,
    });
    if (result.code === "RUN_NOT_FOUND") throw new AppError("PAYROLL_RUN_NOT_FOUND", { status: 404 });
    if (result.code === "SEPARATION_OF_DUTIES") {
      throw new AppError("PAYROLL_SEPARATION_OF_DUTIES", { status: 409 });
    }
    if (result.code !== "OK") {
      throw new AppError("PAYROLL_INVALID_TRANSITION", {
        status: 409,
        details: { currentStatus: result.currentStatus },
      });
    }
    void recordAudit({
      ...auditContextFromReq(req),
      actionKey: `payroll.${toStatus.toLowerCase()}`,
      summary: `دورة الراتب #${runId} → ${toStatus}`,
      targetType: "company_payroll_run",
      targetId: runId,
      permissionKey: "payroll.review",
      before: { status: result.previousStatus },
      after: { status: toStatus },
    });
    return res.json({ run: result.run });
  } catch (error) {
    return next(error);
  }
}

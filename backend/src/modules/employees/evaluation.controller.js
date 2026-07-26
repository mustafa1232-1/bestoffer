/**
 * Purpose:
 * تقييم الموظفين (المرحلة 5) — إداري. لا يعتمد على عدد التذاكر وحده: يجمع
 * الجودة (تقييم المستخدم) + SLA + أوقات الاستجابة/الحل + الحضور + ملاحظة المشرف.
 * تقييم المستخدم الأصلي يُقرأ فقط ولا يُعدَّل.
 */

import * as repo from "./evaluation.repo.js";

function period(req) {
  const p = String(req.query?.period || req.body?.period || "").trim();
  return /^\d{4}-\d{2}$/.test(p) ? p : null;
}
function range(req) {
  return { from: req.query?.from || null, to: req.query?.to || null };
}

export async function listEvaluation(req, res, next) {
  try {
    const { from, to } = range(req);
    const agents = await repo.listAgentsWithTickets({ from, to, limit: 100 });
    const items = [];
    for (const a of agents) {
      const tickets = await repo.computeTicketMetrics({ agentUserId: a.user_id, from, to });
      const attendance = await repo.computeAttendanceMetrics({ employeeUserId: a.user_id, from, to });
      items.push({
        userId: Number(a.user_id),
        fullName: a.full_name,
        tickets,
        attendance,
      });
    }
    return res.json({ items, from, to });
  } catch (error) {
    return next(error);
  }
}

export async function getEvaluation(req, res, next) {
  try {
    const userId = Number(req.params?.userId);
    if (!Number.isInteger(userId) || userId <= 0) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: ["userId"] });
    }
    const { from, to } = range(req);
    const tickets = await repo.computeTicketMetrics({ agentUserId: userId, from, to });
    const attendance = await repo.computeAttendanceMetrics({ employeeUserId: userId, from, to });
    const review = period(req)
      ? await repo.getReview({ employeeUserId: userId, period: period(req) })
      : null;
    return res.json({ userId, tickets, attendance, review, from, to });
  } catch (error) {
    return next(error);
  }
}

export async function upsertReview(req, res, next) {
  try {
    const userId = Number(req.params?.userId);
    const p = period(req);
    if (!Number.isInteger(userId) || userId <= 0 || !p) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: ["userId", "period"] });
    }
    const supervisorRating =
      req.body?.supervisorRating != null && req.body.supervisorRating !== ""
        ? Number(req.body.supervisorRating)
        : null;
    if (supervisorRating != null && (supervisorRating < 1 || supervisorRating > 5)) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: ["supervisorRating"] });
    }
    const review = await repo.upsertReview({
      employeeUserId: userId,
      period: p,
      supervisorRating,
      supervisorNote: typeof req.body?.supervisorNote === "string" ? req.body.supervisorNote.trim() : null,
      reviewedByUserId: req.userId,
    });
    return res.json({ review });
  } catch (error) {
    return next(error);
  }
}

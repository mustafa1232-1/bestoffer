/**
 * Purpose:
 * لوحة المتابعة الموحدة (المرحلة 3). تعرض البطاقات التشغيلية حسب صلاحيات
 * الموظف فقط، بعدّادات فورية حقيقية للوحدات الموصولة، مع قوائم مُصفّحة خادمياً.
 *
 * البطاقات غير الموصولة بعد تُعلَّم available:false (لا أرقام وهمية).
 */

import * as taxiService from "../taxi/taxi.service.js";
import * as monitoringRepo from "./monitoring.repo.js";
import { resolveEffectivePermissions } from "../security/permissions.service.js";

const CARD_DEFS = [
  {
    key: "taxi",
    title: "متابعة الرحلات",
    permission: "taxi.rides.read",
    wired: true,
    detailPath: "/admin/monitoring/taxi/rides",
    counters: () => taxiService.getTaxiMonitoringCounters(),
  },
  {
    key: "orders",
    title: "متابعة الطلبات",
    permission: "orders.read",
    wired: true,
    detailPath: null,
    counters: () => monitoringRepo.getOrderMonitoringCounters(),
  },
  { key: "services", title: "متابعة الخدمات", permission: "services.read", wired: false },
  { key: "real_estate", title: "متابعة العقارات", permission: "real_estate.read", wired: false },
  { key: "cars", title: "متابعة السيارات", permission: "cars.read", wired: false },
  { key: "jobs", title: "متابعة الوظائف", permission: "jobs.read", wired: false },
  { key: "community", title: "متابعة المجتمع", permission: "community.users.read", wired: false },
  { key: "tickets", title: "الشكاوى والتذاكر", permission: "support.tickets.read", wired: false },
];

function hasPermission(effective, key) {
  if (effective.isSuperAdmin || effective.permissions === "ALL") return true;
  return effective.permissions instanceof Map && effective.permissions.has(key);
}

export async function overview(req, res, next) {
  try {
    const effective = await resolveEffectivePermissions(req.userId);
    const generatedAt = new Date().toISOString();

    // البطاقات المسموح للموظف رؤيتها فقط.
    const permittedCards = CARD_DEFS.filter((card) =>
      hasPermission(effective, card.permission)
    );

    const cards = await Promise.all(
      permittedCards.map(async (card) => {
        if (!card.wired) {
          return {
            key: card.key,
            title: card.title,
            available: false,
            counters: null,
            detailPath: card.detailPath || null,
            updatedAt: generatedAt,
          };
        }
        try {
          const counters = await card.counters();
          return {
            key: card.key,
            title: card.title,
            available: true,
            counters,
            detailPath: card.detailPath || null,
            updatedAt: generatedAt,
          };
        } catch (error) {
          return {
            key: card.key,
            title: card.title,
            available: true,
            counters: null,
            error: "COUNTER_UNAVAILABLE",
            detailPath: card.detailPath || null,
            updatedAt: generatedAt,
          };
        }
      })
    );

    return res.json({ generatedAt, cards });
  } catch (error) {
    return next(error);
  }
}

export async function taxiRides(req, res, next) {
  try {
    const status =
      typeof req.query?.status === "string" && req.query.status.trim()
        ? req.query.status.trim()
        : null;
    const from = req.query?.from ? new Date(req.query.from) : null;
    const to = req.query?.to ? new Date(req.query.to) : null;
    const limit = req.query?.limit ? Number(req.query.limit) : 25;
    const offset = req.query?.offset ? Number(req.query.offset) : 0;

    if (from && Number.isNaN(from.getTime())) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: ["from"] });
    }
    if (to && Number.isNaN(to.getTime())) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: ["to"] });
    }

    const out = await taxiService.listRidesForMonitoring({
      status,
      from: from ? from.toISOString() : null,
      to: to ? to.toISOString() : null,
      limit,
      offset,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

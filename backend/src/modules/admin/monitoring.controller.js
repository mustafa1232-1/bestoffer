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
import { recordAudit, auditContextFromReq } from "../security/audit.service.js";

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
    detailPath: "/admin/monitoring/orders",
    counters: () => monitoringRepo.getOrderMonitoringCounters(),
  },
  {
    key: "delivery",
    title: "متابعة الدلفري",
    permission: "orders.read",
    wired: true,
    detailPath: "/admin/monitoring/delivery/couriers",
    counters: () => monitoringRepo.getDeliveryMonitoringCounters(),
  },
  {
    key: "services",
    title: "متابعة الخدمات",
    permission: "services.read",
    wired: true,
    detailPath: "/admin/monitoring/services/requests",
    counters: () => monitoringRepo.getServiceMonitoringCounters(),
  },
  {
    key: "real_estate",
    title: "متابعة العقارات",
    permission: "real_estate.read",
    wired: true,
    detailPath: "/admin/monitoring/real-estate/listings",
    counters: () => monitoringRepo.getRealEstateMonitoringCounters(),
  },
  {
    key: "cars",
    title: "متابعة السيارات",
    permission: "cars.read",
    wired: true,
    detailPath: "/admin/monitoring/cars/listings",
    counters: () => monitoringRepo.getCarMonitoringCounters(),
  },
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

function readListQuery(req) {
  const status =
    typeof req.query?.status === "string" && req.query.status.trim()
      ? req.query.status.trim()
      : null;
  const search =
    typeof req.query?.search === "string" && req.query.search.trim()
      ? req.query.search.trim()
      : "";
  const region =
    typeof req.query?.region === "string" && req.query.region.trim()
      ? req.query.region.trim()
      : null;
  const sort =
    typeof req.query?.sort === "string" && req.query.sort.trim()
      ? req.query.sort.trim()
      : undefined;
  const from = req.query?.from ? new Date(req.query.from) : null;
  const to = req.query?.to ? new Date(req.query.to) : null;
  const limit = req.query?.limit ? Number(req.query.limit) : 25;
  const offset = req.query?.offset ? Number(req.query.offset) : 0;
  const merchantId = req.query?.merchantId ? Number(req.query.merchantId) : null;
  const userId = req.query?.userId ? Number(req.query.userId) : null;
  const deliveryUserId = req.query?.deliveryUserId
    ? Number(req.query.deliveryUserId)
    : null;
  const providerUserId = req.query?.providerUserId
    ? Number(req.query.providerUserId)
    : null;

  return {
    status,
    search,
    region,
    sort,
    from,
    to,
    limit,
    offset,
    merchantId,
    userId,
    deliveryUserId,
    providerUserId,
  };
}

function validateListDates(query, res) {
  if (query.from && Number.isNaN(query.from.getTime())) {
    res.status(400).json({ message: "VALIDATION_ERROR", fields: ["from"] });
    return false;
  }
  if (query.to && Number.isNaN(query.to.getTime())) {
    res.status(400).json({ message: "VALIDATION_ERROR", fields: ["to"] });
    return false;
  }
  return true;
}

export async function orders(req, res, next) {
  try {
    const query = readListQuery(req);
    if (!validateListDates(query, res)) return;
    const out = await monitoringRepo.listOrdersForMonitoring({
      ...query,
      from: query.from ? query.from.toISOString() : null,
      to: query.to ? query.to.toISOString() : null,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function deliveryCouriers(req, res, next) {
  try {
    const query = readListQuery(req);
    if (!validateListDates(query, res)) return;
    void recordAudit({
      ...auditContextFromReq(req),
      actionKey: "monitoring.delivery.couriers.read",
      summary: "عرض متابعة الدلفري",
      targetType: "courier_profile",
      metadata: {
        status: query.status,
        region: query.region,
        limit: query.limit,
        offset: query.offset,
      },
      permissionKey: "orders.read",
    });
    const out = await monitoringRepo.listCouriersForMonitoring({
      ...query,
      from: query.from ? query.from.toISOString() : null,
      to: query.to ? query.to.toISOString() : null,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function serviceRequests(req, res, next) {
  try {
    const query = readListQuery(req);
    if (!validateListDates(query, res)) return;
    void recordAudit({
      ...auditContextFromReq(req),
      actionKey: "monitoring.services.requests.read",
      summary: "عرض متابعة طلبات الخدمات",
      targetType: "service_requests",
      metadata: {
        status: query.status,
        region: query.region,
        limit: query.limit,
        offset: query.offset,
      },
      permissionKey: "services.read",
    });
    const out = await monitoringRepo.listServiceRequestsForMonitoring({
      ...query,
      from: query.from ? query.from.toISOString() : null,
      to: query.to ? query.to.toISOString() : null,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function realEstateListings(req, res, next) {
  try {
    const query = readListQuery(req);
    if (!validateListDates(query, res)) return;
    void recordAudit({
      ...auditContextFromReq(req),
      actionKey: "monitoring.real_estate.listings.read",
      summary: "عرض متابعة إعلانات العقارات",
      targetType: "real_estate_listing",
      metadata: {
        status: query.status,
        region: query.region,
        limit: query.limit,
        offset: query.offset,
      },
      permissionKey: "real_estate.read",
    });
    const out = await monitoringRepo.listRealEstateListingsForMonitoring({
      ...query,
      from: query.from ? query.from.toISOString() : null,
      to: query.to ? query.to.toISOString() : null,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function carListings(req, res, next) {
  try {
    const query = readListQuery(req);
    if (!validateListDates(query, res)) return;
    void recordAudit({
      ...auditContextFromReq(req),
      actionKey: "monitoring.cars.listings.read",
      summary: "عرض متابعة إعلانات السيارات",
      targetType: "car_listing",
      metadata: {
        status: query.status,
        region: query.region,
        limit: query.limit,
        offset: query.offset,
      },
      permissionKey: "cars.read",
    });
    const out = await monitoringRepo.listCarListingsForMonitoring({
      ...query,
      from: query.from ? query.from.toISOString() : null,
      to: query.to ? query.to.toISOString() : null,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

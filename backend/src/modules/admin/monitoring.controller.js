/**
 * Purpose:
 * لوحة المتابعة الموحدة (المرحلة 3). تعرض البطاقات التشغيلية حسب صلاحيات
 * الموظف فقط، بعدّادات فورية حقيقية للوحدات الموصولة، مع قوائم مُصفّحة خادمياً.
 *
 * البطاقات غير الموصولة بعد تُعلَّم available:false (لا أرقام وهمية).
 */

import { Readable } from "node:stream";

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
  {
    key: "jobs",
    title: "متابعة الوظائف",
    permission: "jobs.read",
    wired: true,
    detailPath: "/admin/monitoring/jobs",
    counters: () => monitoringRepo.getJobMonitoringCounters(),
  },
  {
    key: "community",
    title: "متابعة المجتمع",
    permission: "community.users.read",
    wired: true,
    detailPath: "/admin/monitoring/community/users",
    counters: () => monitoringRepo.getCommunityMonitoringCounters(),
  },
  {
    key: "tickets",
    title: "الشكاوى والتذاكر",
    permission: "support.tickets.read",
    wired: true,
    detailPath: "/admin/support/tickets",
    counters: () => monitoringRepo.getTicketMonitoringCounters(),
  },
  {
    key: "ops_alerts",
    title: "التنبيهات التشغيلية",
    permission: "settings.guides.manage",
    wired: true,
    detailPath: "/admin/ops/alerts",
    counters: () => monitoringRepo.getOpsAlertMonitoringCounters(),
  },
];

function hasPermission(effective, key) {
  if (effective.isSuperAdmin || effective.permissions === "ALL") return true;
  return effective.permissions instanceof Map && effective.permissions.has(key);
}

function truthy(value) {
  return ["1", "true", "yes", "on"].includes(
    String(value || "").trim().toLowerCase()
  );
}

function readReason(req) {
  return String(req.query?.reason || req.body?.reason || "").trim().slice(0, 1000);
}

async function ensureSensitivePermission(req, res, permissionKey) {
  const effective = await resolveEffectivePermissions(req.userId);
  if (!hasPermission(effective, permissionKey)) {
    res.status(403).json({ message: "FORBIDDEN_PERMISSION", permission: permissionKey });
    return false;
  }
  return true;
}

function ensureReason(req, res) {
  const reason = readReason(req);
  if (reason.length < 8) {
    res.status(400).json({ message: "SENSITIVE_ACCESS_REASON_REQUIRED" });
    return null;
  }
  return reason;
}

async function auditSensitiveRead(req, {
  actionKey,
  targetType,
  targetId,
  permissionKey,
  reason,
  metadata = null,
}) {
  await recordAudit({
    ...auditContextFromReq(req),
    actionKey,
    summary: "sensitive monitoring detail read",
    targetType,
    targetId,
    metadata,
    reason,
    permissionKey,
  });
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

export async function taxiRideDetail(req, res, next) {
  try {
    const rideId = Number(req.params.rideId);
    const includeLive = truthy(req.query?.includeLive);
    const includeMessages = truthy(req.query?.includeMessages);
    let reason = null;

    if (includeLive) {
      if (!(await ensureSensitivePermission(req, res, "taxi.rides.track_live"))) return;
      reason = ensureReason(req, res);
      if (!reason) return;
    }
    if (includeMessages) {
      if (!(await ensureSensitivePermission(req, res, "taxi.rides.messages.read"))) return;
      reason = reason || ensureReason(req, res);
      if (!reason) return;
    }

    const out = await monitoringRepo.getTaxiRideMonitoringDetail(rideId, {
      includeLive,
      includeMessages,
    });
    if (!out) return res.status(404).json({ message: "RIDE_NOT_FOUND" });

    if (includeLive) {
      await auditSensitiveRead(req, {
        actionKey: "monitoring.taxi.rides.live.read",
        targetType: "taxi_ride_request",
        targetId: rideId,
        permissionKey: "taxi.rides.track_live",
        reason,
      });
    }
    if (includeMessages) {
      await auditSensitiveRead(req, {
        actionKey: "monitoring.taxi.rides.messages.read",
        targetType: "taxi_ride_request",
        targetId: rideId,
        permissionKey: "taxi.rides.messages.read",
        reason,
        metadata: { messageCount: Array.isArray(out.messages) ? out.messages.length : 0 },
      });
    }
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

export async function orderDetail(req, res, next) {
  try {
    const orderId = Number(req.params.orderId);
    const includePhone = truthy(req.query?.includePhone);
    let reason = null;
    if (includePhone) {
      if (!(await ensureSensitivePermission(req, res, "orders.customer_phone.read"))) return;
      reason = ensureReason(req, res);
      if (!reason) return;
    }
    const out = await monitoringRepo.getOrderMonitoringDetail(orderId, { includePhone });
    if (!out) return res.status(404).json({ message: "ORDER_NOT_FOUND" });
    if (includePhone) {
      await auditSensitiveRead(req, {
        actionKey: "monitoring.orders.phone.read",
        targetType: "customer_order",
        targetId: orderId,
        permissionKey: "orders.customer_phone.read",
        reason,
      });
    }
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

export async function deliveryCourierDetail(req, res, next) {
  try {
    const courierId = Number(req.params.courierId);
    const includePhone = truthy(req.query?.includePhone);
    let reason = null;
    if (includePhone) {
      if (!(await ensureSensitivePermission(req, res, "delivery.couriers.phone.read"))) return;
      reason = ensureReason(req, res);
      if (!reason) return;
    }
    const out = await monitoringRepo.getDeliveryCourierMonitoringDetail(courierId, {
      includePhone,
    });
    if (!out) return res.status(404).json({ message: "COURIER_NOT_FOUND" });
    if (includePhone) {
      await auditSensitiveRead(req, {
        actionKey: "monitoring.delivery.couriers.phone.read",
        targetType: "courier_profile",
        targetId: courierId,
        permissionKey: "delivery.couriers.phone.read",
        reason,
      });
    }
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

export async function serviceRequestDetail(req, res, next) {
  try {
    const requestId = Number(req.params.requestId);
    const includeMessages = truthy(req.query?.includeMessages);
    let reason = null;
    if (includeMessages) {
      if (!(await ensureSensitivePermission(req, res, "services.messages.case_bound_read"))) return;
      reason = ensureReason(req, res);
      if (!reason) return;
    }
    const out = await monitoringRepo.getServiceRequestMonitoringDetail(requestId, {
      includeMessages,
    });
    if (!out) return res.status(404).json({ message: "SERVICE_REQUEST_NOT_FOUND" });
    if (includeMessages) {
      await auditSensitiveRead(req, {
        actionKey: "monitoring.services.requests.messages.read",
        targetType: "service_requests",
        targetId: requestId,
        permissionKey: "services.messages.case_bound_read",
        reason,
      });
    }
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

export async function realEstateListingDetail(req, res, next) {
  try {
    const listingId = Number(req.params.listingId);
    const includeContact = truthy(req.query?.includeContact);
    let reason = null;
    if (includeContact) {
      if (!(await ensureSensitivePermission(req, res, "real_estate.contact.read"))) return;
      reason = ensureReason(req, res);
      if (!reason) return;
    }
    const out = await monitoringRepo.getRealEstateListingMonitoringDetail(listingId, {
      includeContact,
    });
    if (!out) return res.status(404).json({ message: "REAL_ESTATE_LISTING_NOT_FOUND" });
    if (includeContact) {
      await auditSensitiveRead(req, {
        actionKey: "monitoring.real_estate.contact.read",
        targetType: "real_estate_listing",
        targetId: listingId,
        permissionKey: "real_estate.contact.read",
        reason,
      });
    }
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

export async function carListingDetail(req, res, next) {
  try {
    const listingId = Number(req.params.listingId);
    const includeContact = truthy(req.query?.includeContact);
    let reason = null;
    if (includeContact) {
      if (!(await ensureSensitivePermission(req, res, "cars.contact.read"))) return;
      reason = ensureReason(req, res);
      if (!reason) return;
    }
    const out = await monitoringRepo.getCarListingMonitoringDetail(listingId, {
      includeContact,
    });
    if (!out) return res.status(404).json({ message: "CAR_LISTING_NOT_FOUND" });
    if (includeContact) {
      await auditSensitiveRead(req, {
        actionKey: "monitoring.cars.contact.read",
        targetType: "car_listing",
        targetId: listingId,
        permissionKey: "cars.contact.read",
        reason,
      });
    }
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function jobs(req, res, next) {
  try {
    const query = readListQuery(req);
    if (!validateListDates(query, res)) return;
    void recordAudit({
      ...auditContextFromReq(req),
      actionKey: "monitoring.jobs.read",
      summary: "عرض متابعة الوظائف",
      targetType: "job_post",
      metadata: {
        status: query.status,
        region: query.region,
        limit: query.limit,
        offset: query.offset,
      },
      permissionKey: "jobs.read",
    });
    const out = await monitoringRepo.listJobsForMonitoring({
      ...query,
      from: query.from ? query.from.toISOString() : null,
      to: query.to ? query.to.toISOString() : null,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function jobDetail(req, res, next) {
  try {
    const out = await monitoringRepo.getJobMonitoringDetail(req.params.jobId);
    if (!out) return res.status(404).json({ message: "JOB_NOT_FOUND" });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function jobApplications(req, res, next) {
  try {
    const out = await monitoringRepo.listJobApplicationsForMonitoring({
      jobId: req.params.jobId,
      status: req.query?.status || null,
      limit: req.query?.limit ? Number(req.query.limit) : 25,
      offset: req.query?.offset ? Number(req.query.offset) : 0,
    });
    if (!out) return res.status(404).json({ message: "JOB_NOT_FOUND" });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function jobApplicationDetail(req, res, next) {
  try {
    const out = await monitoringRepo.getJobApplicationMonitoringDetail(
      req.params.applicationId
    );
    if (!out) return res.status(404).json({ message: "JOB_APPLICATION_NOT_FOUND" });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function jobApplicationCv(req, res, next) {
  try {
    const reason = ensureReason(req, res);
    if (!reason) return;
    const out = await monitoringRepo.getJobApplicationCvForMonitoring(
      req.params.applicationId
    );
    if (!out) return res.status(404).json({ message: "JOB_APPLICATION_NOT_FOUND" });
    if (!out.resume_url) return res.status(404).json({ message: "JOB_APPLICATION_CV_NOT_FOUND" });

    await auditSensitiveRead(req, {
      actionKey: "monitoring.jobs.cv.download",
      targetType: "job_application",
      targetId: req.params.applicationId,
      permissionKey: "jobs.cv.download",
      reason,
      metadata: { jobId: out.job_id },
    });

    const upstream = await fetch(out.resume_url, {
      headers: { "User-Agent": "maslaki-admin-cv-proxy/1" },
    });
    if (!upstream.ok || !upstream.body) {
      return res.status(502).json({ message: "CV_FETCH_FAILED" });
    }
    const size = Number(upstream.headers.get("content-length") || 0);
    if (size > 10 * 1024 * 1024) {
      return res.status(413).json({ message: "CV_TOO_LARGE" });
    }
    const contentType = upstream.headers.get("content-type") || "application/octet-stream";
    const safeName = String(out.full_name || "cv")
      .replace(/[^a-zA-Z0-9._-]+/g, "_")
      .slice(0, 80);
    res.setHeader("Content-Type", contentType);
    res.setHeader("Cache-Control", "no-store");
    res.setHeader(
      "Content-Disposition",
      `attachment; filename="${safeName || "cv"}-${out.id}.bin"`
    );
    return Readable.fromWeb(upstream.body).pipe(res);
  } catch (error) {
    return next(error);
  }
}

export async function communityUsers(req, res, next) {
  try {
    const query = readListQuery(req);
    if (!validateListDates(query, res)) return;
    void recordAudit({
      ...auditContextFromReq(req),
      actionKey: "monitoring.community.users.read",
      summary: "عرض متابعة مستخدمي المجتمع",
      targetType: "community_user",
      metadata: {
        status: query.status,
        limit: query.limit,
        offset: query.offset,
      },
      permissionKey: "community.users.read",
    });
    const out = await monitoringRepo.listCommunityUsersForMonitoring({
      ...query,
      from: query.from ? query.from.toISOString() : null,
      to: query.to ? query.to.toISOString() : null,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function communityUserDetail(req, res, next) {
  try {
    const out = await monitoringRepo.getCommunityUserMonitoringDetail(req.params.userId);
    if (!out) return res.status(404).json({ message: "COMMUNITY_USER_NOT_FOUND" });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function communityUserContent(req, res, next) {
  try {
    const out = await monitoringRepo.listCommunityUserContentForMonitoring(
      req.params.userId,
      {
        limit: req.query?.limit ? Number(req.query.limit) : 25,
        offset: req.query?.offset ? Number(req.query.offset) : 0,
      }
    );
    if (!out) return res.status(404).json({ message: "COMMUNITY_USER_NOT_FOUND" });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function communityUserReports(req, res, next) {
  try {
    const out = await monitoringRepo.listCommunityUserReportsForMonitoring(
      req.params.userId,
      {
        limit: req.query?.limit ? Number(req.query.limit) : 25,
        offset: req.query?.offset ? Number(req.query.offset) : 0,
      }
    );
    if (!out) return res.status(404).json({ message: "COMMUNITY_USER_NOT_FOUND" });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

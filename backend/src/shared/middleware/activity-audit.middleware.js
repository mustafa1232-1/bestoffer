import { trackAutomaticEvent } from "../../modules/behavior/behavior.service.js";

const skipAuditPrefixes = [
  "/health",
  "/ready",
  "/api/notifications/stream",
];

function shouldSkip(req) {
  if (!req.path?.startsWith("/api/")) return true;
  if (req.method === "OPTIONS") return true;
  return skipAuditPrefixes.some((prefix) => req.path.startsWith(prefix));
}

function extractId(pathPart) {
  const n = Number(pathPart);
  return Number.isInteger(n) && n > 0 ? n : null;
}

function inferEvent(req) {
  const path = req.path || "";
  const method = req.method || "GET";
  const segments = path.split("/").filter(Boolean);
  const api = segments[0];
  const moduleName = segments[1] || "unknown";
  const id = extractId(segments[2]);

  if (path.startsWith("/api/cars/smart-search") && method === "POST") {
    return {
      eventName: "cars.smart_search",
      category: "cars",
      action: "smart_search",
      metadata: {
        budgetMinM: req.body?.budgetMinM,
        budgetMaxM: req.body?.budgetMaxM,
        usage: req.body?.usage,
        bodyType: req.body?.bodyType,
        condition: req.body?.condition,
        fuelPreference: req.body?.fuelPreference,
        priority: req.body?.priority,
        minSeats: req.body?.minSeats,
      },
    };
  }

  if (path.startsWith("/api/cars/browse") && method === "GET") {
    return {
      eventName: "cars.browse",
      category: "cars",
      action: "browse",
      metadata: {
        brand: req.query?.brand || null,
        model: req.query?.model || null,
        condition: req.query?.condition || null,
        bodyType: req.query?.bodyType || null,
      },
    };
  }

  if (path.startsWith("/api/orders") && method === "POST") {
    return {
      eventName: "orders.create_attempt",
      category: "orders",
      action: "create",
      metadata: {
        merchantId: req.body?.merchantId || null,
        itemsCount: Array.isArray(req.body?.items) ? req.body.items.length : null,
      },
    };
  }

  if (path.startsWith("/api/assistant/chat") && method === "POST") {
    return {
      eventName: "assistant.chat",
      category: "assistant",
      action: "chat",
    };
  }

  return {
    eventName: `${moduleName}.${method.toLowerCase()}`,
    category: moduleName,
    action: method.toLowerCase(),
    entityType: id ? moduleName : null,
    entityId: id,
  };
}

function normalizeIp(req) {
  const forwarded = req.headers["x-forwarded-for"];
  const firstForwarded = Array.isArray(forwarded)
    ? forwarded[0]
    : String(forwarded || "").split(",")[0].trim();
  return firstForwarded || req.ip || req.socket?.remoteAddress || null;
}

export function activityAuditMiddleware() {
  return function activityAudit(req, res, next) {
    if (shouldSkip(req)) return next();

    const userId = req.userId || req.authUserId;
    const userRole = req.userRole || req.authUserRole;
    if (!userId) return next();

    res.on("finish", () => {
      if (res.statusCode >= 500) return;

      const inferred = inferEvent(req);
      void trackAutomaticEvent({
        userId,
        userRole,
        eventName: inferred.eventName,
        category: inferred.category,
        action: inferred.action,
        source: "api_auto",
        path: req.originalUrl,
        method: req.method,
        entityType: inferred.entityType,
        entityId: inferred.entityId,
        statusCode: res.statusCode,
        metadata: inferred.metadata || null,
        ipAddress: normalizeIp(req),
        userAgent: req.headers["user-agent"] || null,
      }).catch((error) => {
        console.warn("[activity-audit] failed", error?.message || error);
      });
    });

    return next();
  };
}

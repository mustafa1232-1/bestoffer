import { trackAutomaticEvent } from "../../modules/behavior/behavior.service.js";

const skipAuditPrefixes = [
  "/health",
  "/ready",
  "/api/notifications/stream",
  "/api/taxi/stream",
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

function trimOrNull(value) {
  if (value === undefined || value === null) return null;
  const out = String(value).trim();
  return out.length ? out : null;
}

function pickQuery(req, keys = []) {
  for (const key of keys) {
    const value = trimOrNull(req?.query?.[key]);
    if (value) return value;
  }
  return null;
}

function countArray(value) {
  return Array.isArray(value) ? value.length : 0;
}

function inferEvent(req) {
  const path = req.path || "";
  const method = req.method || "GET";
  const segments = path.split("/").filter(Boolean);
  const queryText = pickQuery(req, ["q", "query", "search"]);
  const typeFilter = pickQuery(req, ["type", "merchantType", "category"]);
  const moduleName = segments[1] || "unknown";
  const id = extractId(segments[2]);

  if (path === "/api/merchants/discovery" && method === "GET") {
    return {
      eventName: "discovery.load",
      category: "discovery",
      action: queryText ? "search" : "load",
      metadata: {
        searchQuery: queryText,
        type: typeFilter,
      },
    };
  }

  if (path === "/api/merchants" && method === "GET") {
    return {
      eventName: queryText ? "merchants.search" : "merchants.list",
      category: "merchants",
      action: queryText ? "search" : "list",
      metadata: {
        searchQuery: queryText,
        type: typeFilter,
      },
    };
  }

  if (segments[1] === "merchants" && segments[3] === "products" && method === "GET") {
    return {
      eventName: "merchant.products_view",
      category: "catalog",
      action: "view_products",
      entityType: "merchant",
      entityId: id,
      metadata: {
        merchantId: id,
      },
    };
  }

  if (segments[1] === "merchants" && segments[3] === "categories" && method === "GET") {
    return {
      eventName: "merchant.categories_view",
      category: "catalog",
      action: "view_categories",
      entityType: "merchant",
      entityId: id,
      metadata: {
        merchantId: id,
      },
    };
  }

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
        transmissionPref: req.body?.transmissionPref,
        priority: req.body?.priority,
        minSeats: req.body?.minSeats,
        freeText: trimOrNull(req.body?.freeText),
      },
    };
  }

  if (path.startsWith("/api/cars/browse") && method === "GET") {
    return {
      eventName: "cars.browse",
      category: "cars",
      action: "browse",
      metadata: {
        searchQuery: queryText,
        brand: req.query?.brand || null,
        model: req.query?.model || null,
        condition: req.query?.condition || null,
        bodyType: req.query?.bodyType || null,
        yearFrom: req.query?.yearFrom || null,
        yearTo: req.query?.yearTo || null,
      },
    };
  }

  if (path.startsWith("/api/cars/brands") && method === "GET") {
    return {
      eventName: "cars.brands_list",
      category: "cars",
      action: "browse_brands",
    };
  }

  if (path.startsWith("/api/cars/models") && method === "GET") {
    return {
      eventName: "cars.models_list",
      category: "cars",
      action: "browse_models",
      metadata: {
        brand: req.query?.brand || null,
      },
    };
  }

  if (path.startsWith("/api/orders") && method === "POST") {
    if (segments[3] === "reorder") {
      return {
        eventName: "orders.reorder",
        category: "orders",
        action: "reorder",
        entityType: "order",
        entityId: id,
      };
    }

    if (segments[3] === "confirm-delivered") {
      return {
        eventName: "orders.confirm_delivered",
        category: "orders",
        action: "confirm_delivered",
        entityType: "order",
        entityId: id,
      };
    }

    if (segments[3] === "rate-delivery") {
      return {
        eventName: "orders.rate_delivery",
        category: "orders",
        action: "rate_delivery",
        entityType: "order",
        entityId: id,
        metadata: {
          rating: req.body?.rating,
        },
      };
    }

    if (segments[3] === "rate-merchant") {
      return {
        eventName: "orders.rate_merchant",
        category: "orders",
        action: "rate_merchant",
        entityType: "order",
        entityId: id,
        metadata: {
          rating: req.body?.rating,
        },
      };
    }

    if (segments[2] === "favorites") {
      return {
        eventName: "favorites.add",
        category: "favorites",
        action: "add",
        entityType: "product",
        entityId: extractId(segments[3]),
      };
    }

    return {
      eventName: "orders.create_attempt",
      category: "orders",
      action: "create",
      metadata: {
        merchantId: req.body?.merchantId || null,
        itemsCount: Array.isArray(req.body?.items) ? req.body.items.length : null,
        hasImage: !!req.file,
        hasNote: !!trimOrNull(req.body?.note),
      },
    };
  }

  if (path.startsWith("/api/orders/my") && method === "GET") {
    return {
      eventName: "orders.list_mine",
      category: "orders",
      action: "list",
    };
  }

  if (path.startsWith("/api/orders/favorites") && method === "GET") {
    return {
      eventName: "favorites.list",
      category: "favorites",
      action: "list",
    };
  }

  if (segments[1] === "orders" && segments[2] === "favorites" && method === "DELETE") {
    return {
      eventName: "favorites.remove",
      category: "favorites",
      action: "remove",
      entityType: "product",
      entityId: extractId(segments[3]),
    };
  }

  if (path.startsWith("/api/assistant/chat") && method === "POST") {
    return {
      eventName: "assistant.chat",
      category: "assistant",
      action: "chat",
      metadata: {
        messageLength: trimOrNull(req.body?.message)?.length || null,
      },
    };
  }

  if (path.startsWith("/api/assistant/session/new") && method === "POST") {
    return {
      eventName: "assistant.session_new",
      category: "assistant",
      action: "session_new",
    };
  }

  if (path.startsWith("/api/assistant/session") && method === "GET") {
    return {
      eventName: "assistant.session_view",
      category: "assistant",
      action: "session_view",
    };
  }

  if (path.startsWith("/api/assistant/profile/home") && method === "POST") {
    return {
      eventName: "assistant.home_profile_update",
      category: "assistant",
      action: "profile_update",
      metadata: {
        audience: trimOrNull(req.body?.audience),
        priority: trimOrNull(req.body?.priority),
        interestsCount: countArray(req.body?.interests),
      },
    };
  }

  if (path.startsWith("/api/auth/account/addresses") && method === "GET") {
    return {
      eventName: "addresses.list",
      category: "account",
      action: "addresses_list",
    };
  }

  if (path.startsWith("/api/auth/account/addresses") && method === "POST") {
    return {
      eventName: "addresses.create",
      category: "account",
      action: "addresses_create",
    };
  }

  if (path.startsWith("/api/auth/account/addresses") && method === "PATCH") {
    return {
      eventName: "addresses.update",
      category: "account",
      action: "addresses_update",
      entityType: "address",
      entityId: extractId(segments[4]),
    };
  }

  if (path.startsWith("/api/auth/account/addresses") && method === "DELETE") {
    return {
      eventName: "addresses.remove",
      category: "account",
      action: "addresses_remove",
      entityType: "address",
      entityId: extractId(segments[4]),
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

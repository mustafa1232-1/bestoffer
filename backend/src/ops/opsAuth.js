import { q } from "../config/db.js";
import { requireAuth } from "../shared/middleware/auth.middleware.js";
import { AppError } from "../shared/utils/errors.js";
import { OPS_PERMISSION_KEYS } from "./types.js";

function normalizeRole(role) {
  return String(role || "").trim().toLowerCase();
}

async function hasRolePermission(role, capability) {
  const normalizedRole = normalizeRole(role);
  const capabilityKey = String(capability || "").trim();
  if (!normalizedRole || !capabilityKey) return false;

  const result = await q(
    `SELECT is_enabled
     FROM role_permission_override
     WHERE role_key = $1
       AND capability_key = $2
     LIMIT 1`,
    [normalizedRole, capabilityKey]
  );

  if (!result.rows[0]) return false;
  return result.rows[0].is_enabled === true;
}

export function buildRequireOpsAuth({
  lookupPermission = hasRolePermission,
  authMiddleware = requireAuth,
} = {}) {
  return function requireOpsAuth(requiredPermission = OPS_PERMISSION_KEYS.access) {
    const required = Array.isArray(requiredPermission)
      ? requiredPermission.filter(Boolean)
      : [requiredPermission].filter(Boolean);

    return async function opsAuthMiddleware(req, res, next) {
      try {
        await new Promise((resolve, reject) => {
          authMiddleware(req, res, (error) => (error ? reject(error) : resolve()));
        });

        if (req.userIsSuperAdmin === true) {
          return next();
        }

        const role = normalizeRole(req.userRole);
        if (!role) {
          return next(new AppError("FORBIDDEN_SUPER_ADMIN_ONLY", { status: 403 }));
        }

        for (const permission of required) {
          // eslint-disable-next-line no-await-in-loop
          const allowed = await lookupPermission(role, permission);
          if (allowed) return next();
        }

        return next(new AppError("FORBIDDEN_SUPER_ADMIN_ONLY", { status: 403 }));
      } catch (error) {
        return next(error);
      }
    };
  };
}

export const requireOpsAuth = buildRequireOpsAuth();

export function requireOpsWebhookApiKey(env) {
  const configured = String(env.opsApiKey || "").trim();

  return function opsWebhookApiKeyMiddleware(req, res, next) {
    if (!configured) {
      return res.status(503).json({ message: "OPS_WEBHOOK_KEY_NOT_CONFIGURED" });
    }

    const headerValue = String(
      req.headers["x-ops-api-key"] || req.headers["x-api-key"] || ""
    ).trim();

    const bearer = String(req.headers.authorization || "").trim();
    const bearerToken = bearer.toLowerCase().startsWith("bearer ")
      ? bearer.slice(7).trim()
      : "";

    const candidate = headerValue || bearerToken;
    if (!candidate || candidate !== configured) {
      return res.status(401).json({ message: "OPS_WEBHOOK_UNAUTHORIZED" });
    }

    return next();
  };
}

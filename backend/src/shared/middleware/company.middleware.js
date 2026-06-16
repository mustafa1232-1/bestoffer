import { AppError } from "../utils/errors.js";
import { q } from "../../config/db.js";

async function resolveActiveMemberships(userId) {
  const r = await q(
    `SELECT
       cu.id,
       cu.company_id,
       cu.user_id,
       cu.role,
       cu.permissions_json,
       cu.is_active,
       c.name AS company_name,
       c.status AS company_status
     FROM company_user cu
     JOIN company c ON c.id = cu.company_id
     WHERE cu.user_id = $1
       AND cu.is_active = TRUE
       AND c.status = 'active'
     ORDER BY cu.company_id ASC, cu.id ASC`,
    [Number(userId)]
  );
  return r.rows;
}

export async function requireCompanyAuth(req, res, next) {
  if (!req.userId) {
    return next(new AppError("UNAUTHORIZED", { status: 401 }));
  }
  if (String(req.userRole || "").trim().toLowerCase() !== "company_portal") {
    return next(new AppError("FORBIDDEN_COMPANY_PORTAL_ONLY", { status: 403 }));
  }

  try {
    const memberships = await resolveActiveMemberships(req.userId);
    if (!memberships.length) {
      return next(new AppError("COMPANY_MEMBERSHIP_REQUIRED", { status: 403 }));
    }
    req.companyMemberships = memberships;
    return next();
  } catch (error) {
    return next(error);
  }
}

export async function resolveCompanyContext(req, res, next) {
  try {
    const memberships = Array.isArray(req.companyMemberships)
      ? req.companyMemberships
      : await resolveActiveMemberships(req.userId);

    if (!memberships.length) {
      return next(new AppError("COMPANY_MEMBERSHIP_REQUIRED", { status: 403 }));
    }

    const rawCompanyId =
      req.headers["x-company-id"] ??
      req.query?.companyId ??
      req.body?.companyId ??
      req.params?.companyId ??
      null;
    const requestedCompanyId =
      rawCompanyId == null || rawCompanyId === ""
        ? null
        : Number(rawCompanyId);

    let membership = null;
    if (requestedCompanyId != null) {
      membership =
        memberships.find(
          (item) => Number(item.company_id) === Number(requestedCompanyId)
        ) || null;
      if (!membership) {
        return next(new AppError("FORBIDDEN_COMPANY_SCOPE", { status: 403 }));
      }
    } else if (memberships.length === 1) {
      membership = memberships[0];
    } else {
      return next(
        new AppError("COMPANY_SCOPE_REQUIRED", {
          status: 400,
          details: {
            message:
              "Multiple company memberships found. Send X-Company-Id or companyId.",
          },
        })
      );
    }

    req.companyMembership = membership;
    req.companyId = Number(membership.company_id);
    req.companyRole = String(membership.role || "").trim().toLowerCase();
    req.companyPermissions =
      membership.permissions_json &&
      typeof membership.permissions_json === "object"
        ? membership.permissions_json
        : {};
    return next();
  } catch (error) {
    return next(error);
  }
}

export function requireCompanyRoles(allowedRoles) {
  const allowed = new Set(
    Array.isArray(allowedRoles) ? allowedRoles : [allowedRoles]
  );

  return function companyRoleGuard(req, res, next) {
    const role = String(req.companyRole || "").trim().toLowerCase();
    if (!role || !allowed.has(role)) {
      return next(new AppError("FORBIDDEN_COMPANY_ROLE", { status: 403 }));
    }
    return next();
  };
}

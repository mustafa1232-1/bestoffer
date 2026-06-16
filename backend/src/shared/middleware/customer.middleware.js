import { AppError } from "../utils/errors.js";

export function requireCustomer(req, res, next) {
  const role = String(req.userRole || "").trim().toLowerCase();
  if (role === "user") {
    return next();
  }

  return next(new AppError("FORBIDDEN_CUSTOMER_ONLY", { status: 403 }));
}


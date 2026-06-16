import { AppError } from "../utils/errors.js";

export function requireTaxiCaptain(req, res, next) {
  const role = String(req.userRole || "").trim().toLowerCase();
  const isCaptainAlias = role === "delivery" && req.userIsTaxiCaptain === true;
  if (role !== "taxi_captain" && !isCaptainAlias) {
    return next(new AppError("FORBIDDEN_TAXI_CAPTAIN_ONLY", { status: 403 }));
  }
  return next();
}

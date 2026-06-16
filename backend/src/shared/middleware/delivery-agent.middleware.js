import { AppError } from "../utils/errors.js";

export function requireDeliveryAgent(req, res, next) {
  if (req.userRole !== "delivery") {
    return next(new AppError("FORBIDDEN_DELIVERY_ONLY", { status: 403 }));
  }
  return next();
}

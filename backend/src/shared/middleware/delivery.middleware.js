export function requireDelivery(req, res, next) {
  if (req.userRole !== "delivery") {
    return res.status(403).json({ message: "FORBIDDEN_DELIVERY_ONLY" });
  }
  next();
}

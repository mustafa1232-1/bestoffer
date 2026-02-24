export function requireCustomer(req, res, next) {
  if (req.userRole !== "user") {
    return res.status(403).json({ message: "FORBIDDEN_CUSTOMER_ONLY" });
  }
  next();
}

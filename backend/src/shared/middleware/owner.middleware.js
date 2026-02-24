export function requireOwner(req, res, next) {
  if (req.userRole !== "owner") {
    return res.status(403).json({ message: "FORBIDDEN_OWNER_ONLY" });
  }
  next();
}

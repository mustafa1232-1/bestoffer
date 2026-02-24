export function requireBackoffice(req, res, next) {
  if (req.userRole !== "admin" && req.userRole !== "deputy_admin") {
    return res.status(403).json({ message: "FORBIDDEN_BACKOFFICE_ONLY" });
  }
  next();
}

export function requireAdminOrOwner(req, res, next) {
  if (req.userRole !== "admin" && req.userRole !== "owner") {
    return res.status(403).json({ message: "FORBIDDEN_ADMIN_OR_OWNER_ONLY" });
  }
  next();
}

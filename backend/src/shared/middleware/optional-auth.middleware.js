import { verifyAccessToken } from "../utils/jwt.js";

export function attachOptionalAuth(req, res, next) {
  const h = req.headers.authorization || "";
  const token = h.startsWith("Bearer ") ? h.slice(7) : null;

  if (!token) return next();

  try {
    const payload = verifyAccessToken(token);
    req.authUserId = payload?.sub || null;
    req.authUserRole = payload?.role || null;
    req.authUserIsSuperAdmin = payload?.sa === true;
  } catch (_) {
    req.authUserId = null;
    req.authUserRole = null;
    req.authUserIsSuperAdmin = false;
  }

  return next();
}

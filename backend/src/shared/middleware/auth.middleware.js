import { verifyAccessToken } from "../utils/jwt.js";
import { AppError } from "../utils/errors.js";

export function requireAuth(req, res, next) {
  if (req.authUserId) {
    req.userId = req.authUserId;
    req.userRole = req.authUserRole;
    req.userIsSuperAdmin = req.authUserIsSuperAdmin === true;
    return next();
  }

  const h = req.headers.authorization || "";
  const token = h.startsWith("Bearer ") ? h.slice(7) : null;

  if (!token) {
    return next(new AppError("NO_TOKEN", { status: 401 }));
  }

  try {
    const payload = verifyAccessToken(token);
    req.userId = payload.sub;
    req.userRole = payload.role;
    req.userIsSuperAdmin = payload.sa === true;
    return next();
  } catch (error) {
    return next(new AppError("INVALID_TOKEN", { status: 401 }));
  }
}

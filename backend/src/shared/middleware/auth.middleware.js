import { AppError } from "../utils/errors.js";
import { resolveAccessAuth } from "./access-auth.js";

export async function requireAuth(req, res, next) {
  if (req.authUserId) {
    req.userId = req.authUserId;
    req.userRole = req.authUserRole;
    req.userIsSuperAdmin = req.authUserIsSuperAdmin === true;
    req.authSessionId = req.authSessionId || null;
    req.authDeviceContext = req.authDeviceContext || null;
    return next();
  }

  try {
    const auth = await resolveAccessAuth(req, { strict: true });
    req.userId = auth.userId;
    req.userRole = auth.role;
    req.userIsSuperAdmin = auth.isSuperAdmin === true;
    req.authSessionId = auth.sessionId;
    req.authDeviceContext = auth.deviceContext || null;
    return next();
  } catch (error) {
    if (error instanceof AppError) return next(error);
    return next(new AppError("INVALID_TOKEN", { status: 401 }));
  }
}

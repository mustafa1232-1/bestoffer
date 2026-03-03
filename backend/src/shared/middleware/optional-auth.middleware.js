import { resolveAccessAuth } from "./access-auth.js";

export async function attachOptionalAuth(req, res, next) {
  try {
    const auth = await resolveAccessAuth(req, { strict: false });
    req.authUserId = auth?.userId || null;
    req.authUserRole = auth?.role || null;
    req.authUserIsSuperAdmin = auth?.isSuperAdmin === true;
    req.authSessionId = auth?.sessionId || null;
    req.authDeviceContext = auth?.deviceContext || null;
  } catch (_) {
    req.authUserId = null;
    req.authUserRole = null;
    req.authUserIsSuperAdmin = false;
    req.authSessionId = null;
    req.authDeviceContext = null;
  }

  return next();
}

import { AppError } from "../utils/errors.js";
import { resolveAccessAuth } from "./access-auth.js";

/**
 * Purpose:
 * middleware المصادقة الأساسي الذي يحول access token إلى user context موحد
 * على `req` لبقية الطبقات.
 *
 * Critical notes:
 * - هذا الملف بوابة الثقة الأساسية لمعظم API المحمية.
 * - أي تغيير خاطئ هنا قد يفتح privilege escalation أو يكسر كل routes المحمية.
 *
 * Maintenance notes:
 * - عند ظهور `INVALID_TOKEN` أو `permission denied` افحص هذا الملف مع
 *   `access-auth.js` وطبقة session/token قبل فحص business routes.
 */
/**
 * يضمن وجود مستخدم مصادق ويملأ حقول السياق الموحدة على request.
 *
 * Side effects:
 * - يكتب `userId`, `userRole`, `userIsSuperAdmin`, `authSessionId`
 *   و`authDeviceContext` على `req`.
 */
export async function requireAuth(req, res, next) {
  if (Number(req.userId) > 0) {
    req.userIsSuperAdmin = req.userIsSuperAdmin === true;
    req.userIsTaxiCaptain = req.userIsTaxiCaptain === true;
    req.authSessionId = req.authSessionId || null;
    req.authDeviceContext = req.authDeviceContext || null;
    return next();
  }

  if (req.authUserId) {
    req.userId = req.authUserId;
    req.userRole = req.authUserRole;
    req.userIsSuperAdmin = req.authUserIsSuperAdmin === true;
    req.userIsTaxiCaptain = req.authUserIsTaxiCaptain === true;
    req.authSessionId = req.authSessionId || null;
    req.authDeviceContext = req.authDeviceContext || null;
    return next();
  }

  try {
    const auth = await resolveAccessAuth(req, { strict: true });
    req.userId = auth.userId;
    req.userRole = auth.role;
    req.userIsSuperAdmin = auth.isSuperAdmin === true;
    req.userIsTaxiCaptain = auth.isTaxiCaptain === true;
    req.authSessionId = auth.sessionId;
    req.authDeviceContext = auth.deviceContext || null;
    return next();
  } catch (error) {
    if (error instanceof AppError) return next(error);
    return next(new AppError("INVALID_TOKEN", { status: 401 }));
  }
}

export async function optionalAuth(req, res, next) {
  if (Number(req.userId) > 0) {
    req.userIsSuperAdmin = req.userIsSuperAdmin === true;
    req.userIsTaxiCaptain = req.userIsTaxiCaptain === true;
    req.authSessionId = req.authSessionId || null;
    req.authDeviceContext = req.authDeviceContext || null;
    return next();
  }

  try {
    const auth = await resolveAccessAuth(req, { strict: false });
    if (auth) {
      req.userId = auth.userId;
      req.userRole = auth.role;
      req.userIsSuperAdmin = auth.isSuperAdmin === true;
      req.userIsTaxiCaptain = auth.isTaxiCaptain === true;
      req.authSessionId = auth.sessionId;
      req.authDeviceContext = auth.deviceContext || null;
    }
    return next();
  } catch (_) {
    return next();
  }
}

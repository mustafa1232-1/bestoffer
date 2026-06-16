import { toAppError } from "../utils/errors.js";

let sentryCapturePromise = null;

async function captureErrorToSentry(error, req) {
  if (!String(process.env.SENTRY_DSN || "").trim()) return;
  try {
    if (!sentryCapturePromise) {
      sentryCapturePromise = import("@sentry/node")
        .then((mod) => mod.default || mod)
        .catch(() => null);
    }
    const sentry = await sentryCapturePromise;
    if (!sentry || typeof sentry.captureException !== "function") return;
    sentry.captureException(error, {
      tags: {
        module: "express_error_handler",
      },
      extra: {
        requestId: req?.requestId || null,
        method: req?.method || null,
        path: req?.originalUrl || null,
      },
    });
  } catch (_) {
    // best effort only
  }
}

/**
 * Purpose:
 * contract الخطأ الموحد على مستوى HTTP. يحول الاستثناءات الداخلية إلى body
 * ثابت يسهل على الواجهة وفريق الدعم تتبعه عبر `requestId`.
 *
 * Used by:
 * - آخر middleware في `app.js`
 *
 * Critical notes:
 * - لا يجب تسريب تفاصيل أخطاء داخلية للمستخدم النهائي إلا إذا كانت
 *   `expose=true` من AppError موثوق.
 */
function sanitizeMessage(message) {
  if (!message || typeof message !== "string") return "SERVER_ERROR";
  if (message.length > 180) return message.slice(0, 180);
  return message;
}

/**
 * يلتقط أخطاء JSON parser قبل وصولها إلى controllers.
 */
export function jsonSyntaxErrorHandler(err, req, res, next) {
  if (err?.type === "entity.parse.failed") {
    return res.status(400).json({
      message: "INVALID_JSON_BODY",
      requestId: req.requestId,
    });
  }
  return next(err);
}

/**
 * fallback موحد للمسارات غير المعرفة.
 */
export function notFoundHandler(req, res) {
  return res.status(404).json({
    message: "ROUTE_NOT_FOUND",
    path: req.originalUrl,
    requestId: req.requestId,
  });
}

/**
 * المعالج النهائي لكل الأخطاء التطبيقية وغير التطبيقية.
 *
 * Maintenance notes:
 * - أخطاء 5xx تطبع كـ `console.error` مع request id.
 * - أخطاء 4xx تطبع كتحذير لتسهيل دعم misuse/validation بدون إغراق logs.
 */
export function errorHandler(err, req, res, next) {
  const normalized = toAppError(err);
  const status = normalized.status >= 400 ? normalized.status : 500;

  if (status >= 500) {
    void captureErrorToSentry(normalized, req);
  }

  const body = {
    message: normalized.expose ? sanitizeMessage(normalized.message) : "SERVER_ERROR",
    requestId: req.requestId,
  };

  if (normalized.details && normalized.expose) {
    body.details = normalized.details;
  }

  if (
    normalized.expose &&
    normalized.details &&
    typeof normalized.details === "object" &&
    normalized.details.fields
  ) {
    body.fields = normalized.details.fields;
  }

  if (status >= 500) {
    console.error(
      `[error] id=${req.requestId || "n/a"} ${req.method} ${req.originalUrl}`,
      normalized
    );
  } else {
    console.warn(
      `[warn] id=${req.requestId || "n/a"} ${req.method} ${req.originalUrl} -> ${status} ${normalized.message}`
    );
  }

  return res.status(status).json(body);
}

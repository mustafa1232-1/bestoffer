import { toAppError } from "../utils/errors.js";

function sanitizeMessage(message) {
  if (!message || typeof message !== "string") return "SERVER_ERROR";
  if (message.length > 180) return message.slice(0, 180);
  return message;
}

export function jsonSyntaxErrorHandler(err, req, res, next) {
  if (err?.type === "entity.parse.failed") {
    return res.status(400).json({
      message: "INVALID_JSON_BODY",
      requestId: req.requestId,
    });
  }
  return next(err);
}

export function notFoundHandler(req, res) {
  return res.status(404).json({
    message: "ROUTE_NOT_FOUND",
    path: req.originalUrl,
    requestId: req.requestId,
  });
}

export function errorHandler(err, req, res, next) {
  const normalized = toAppError(err);
  const status = normalized.status >= 400 ? normalized.status : 500;

  const body = {
    message: normalized.expose ? sanitizeMessage(normalized.message) : "SERVER_ERROR",
    requestId: req.requestId,
  };

  if (normalized.details && normalized.expose) {
    body.details = normalized.details;
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

import crypto from "crypto";

export function withRequestContext(req, res, next) {
  const externalRequestId = req.headers["x-request-id"];
  const requestId =
    (Array.isArray(externalRequestId)
      ? externalRequestId[0]
      : externalRequestId) ||
    crypto.randomUUID();

  req.requestId = String(requestId);
  req.requestStartAt = Date.now();
  res.setHeader("x-request-id", req.requestId);

  next();
}

export function requestLogger({ enabled = true } = {}) {
  return function logRequest(req, res, next) {
    if (!enabled) return next();

    const startedAt = req.requestStartAt || Date.now();
    res.on("finish", () => {
      const ms = Date.now() - startedAt;
      const requestId = req.requestId || "n/a";
      console.log(
        `[http] ${req.method} ${req.originalUrl} -> ${res.statusCode} ${ms}ms id=${requestId}`
      );
    });

    next();
  };
}

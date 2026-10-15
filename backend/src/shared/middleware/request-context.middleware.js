import crypto from "crypto";

const REQUEST_ID_MAX_LENGTH = 128;
const SAFE_REQUEST_ID_PATTERN = /^[A-Za-z0-9._:-]+$/;

function normalizeRequestId(value) {
  const raw = String(value || "").trim();
  if (!raw) return crypto.randomUUID();
  if (raw.length > REQUEST_ID_MAX_LENGTH) return crypto.randomUUID();
  if (!SAFE_REQUEST_ID_PATTERN.test(raw)) return crypto.randomUUID();
  return raw;
}

export function withRequestContext(req, res, next) {
  const externalRequestId = req.headers["x-request-id"];
  const requestedId = Array.isArray(externalRequestId)
    ? externalRequestId[0]
    : externalRequestId;
  const requestId = normalizeRequestId(requestedId);

  req.requestId = requestId;
  req.requestStartAt = Date.now();
  res.setHeader("x-request-id", req.requestId);
  const runtimeRegion = String(
    process.env.RAILWAY_REPLICA_REGION || process.env.RAILWAY_REGION || ""
  ).trim();
  if (runtimeRegion) res.setHeader("x-app-region", runtimeRegion);

  const originalWriteHead = res.writeHead;
  res.writeHead = function writeHeadWithTiming(...args) {
    if (!res.headersSent) {
      const durationMs = Math.max(0, Date.now() - req.requestStartAt);
      res.setHeader("server-timing", `app;dur=${durationMs}`);
      res.setHeader("x-app-response-ms", String(durationMs));
    }
    return originalWriteHead.apply(this, args);
  };

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

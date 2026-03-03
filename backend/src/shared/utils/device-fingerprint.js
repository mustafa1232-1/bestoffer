import crypto from "crypto";

function firstHeaderValue(value) {
  if (Array.isArray(value)) return String(value[0] || "").trim();
  return String(value || "").trim();
}

export function extractClientIp(req) {
  const forwardedFor = req.headers["x-forwarded-for"];
  const firstForwarded = Array.isArray(forwardedFor)
    ? String(forwardedFor[0] || "").split(",")[0].trim()
    : String(forwardedFor || "").split(",")[0].trim();
  return firstForwarded || req.ip || req.socket?.remoteAddress || "unknown";
}

export function buildDeviceFingerprint(input) {
  const raw = [
    String(input.deviceId || "").trim(),
    String(input.userAgent || "").trim(),
    String(input.platform || "").trim(),
    String(input.appVersion || "").trim(),
    String(input.model || "").trim(),
  ].join("|");

  return crypto.createHash("sha256").update(raw || "unknown").digest("hex");
}

export function extractDeviceContext(req) {
  const deviceId =
    firstHeaderValue(req.headers["x-device-id"]) ||
    firstHeaderValue(req.headers["x-installation-id"]);
  const userAgent = firstHeaderValue(req.headers["user-agent"]);
  const platform = firstHeaderValue(req.headers["x-client-platform"]);
  const appVersion = firstHeaderValue(req.headers["x-app-version"]);
  const model = firstHeaderValue(req.headers["x-device-model"]);
  const ipAddress = extractClientIp(req);

  return {
    deviceId,
    userAgent,
    platform,
    appVersion,
    model,
    ipAddress,
    deviceFingerprint: buildDeviceFingerprint({
      deviceId,
      userAgent,
      platform,
      appVersion,
      model,
    }),
  };
}


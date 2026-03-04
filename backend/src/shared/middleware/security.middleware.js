import { env } from "../../config/env.js";

const frameAncestorsNone = "frame-ancestors 'none'";
const defaultSrcSelf = "default-src 'self'";
const objectNone = "object-src 'none'";
const baseUriSelf = "base-uri 'self'";
const formActionSelf = "form-action 'self'";

function normalizeOriginFromUrl(raw) {
  const value = String(raw || "").trim();
  if (!value) return "";
  try {
    const u = new URL(value);
    return `${u.protocol}//${u.host}`;
  } catch (_) {
    return "";
  }
}

function buildCspDirectives() {
  const r2Origin = normalizeOriginFromUrl(env.cfR2PublicBaseUrl);
  const extraOrigins = [r2Origin].filter(Boolean).join(" ");
  const imgSrc = [
    "img-src 'self' data: blob:",
    "https://*.googleapis.com",
    "https://*.gstatic.com",
    extraOrigins,
  ]
    .filter(Boolean)
    .join(" ");
  const mediaSrc = ["media-src 'self' data: blob:", extraOrigins]
    .filter(Boolean)
    .join(" ");
  const connectSrc = [
    "connect-src 'self'",
    "https://*.googleapis.com",
    "https://fcm.googleapis.com",
    extraOrigins,
  ]
    .filter(Boolean)
    .join(" ");

  return `${defaultSrcSelf}; ${objectNone}; ${baseUriSelf}; ${formActionSelf}; ${frameAncestorsNone}; ${imgSrc}; ${mediaSrc}; ${connectSrc}`;
}

export function securityHeaders(req, res, next) {
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("X-Frame-Options", "DENY");
  res.setHeader("Referrer-Policy", "strict-origin-when-cross-origin");
  res.setHeader("X-DNS-Prefetch-Control", "off");
  res.setHeader("Permissions-Policy", "camera=(), microphone=(), geolocation=()");

  const isHttps =
    req.secure ||
    req.headers["x-forwarded-proto"] === "https" ||
    req.headers["x-forwarded-ssl"] === "on";
  if (isHttps) {
    res.setHeader(
      "Strict-Transport-Security",
      "max-age=15552000; includeSubDomains"
    );
  }

  res.setHeader("Content-Security-Policy", buildCspDirectives());

  next();
}

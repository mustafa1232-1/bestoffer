const frameAncestorsNone = "frame-ancestors 'none'";
const defaultSrcSelf = "default-src 'self'";
const objectNone = "object-src 'none'";
const baseUriSelf = "base-uri 'self'";
const formActionSelf = "form-action 'self'";
const imgSrc =
  "img-src 'self' data: blob: https://*.googleapis.com https://*.gstatic.com";
const connectSrc = "connect-src 'self' https://*.googleapis.com https://fcm.googleapis.com";

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

  res.setHeader(
    "Content-Security-Policy",
    `${defaultSrcSelf}; ${objectNone}; ${baseUriSelf}; ${formActionSelf}; ${frameAncestorsNone}; ${imgSrc}; ${connectSrc}`
  );

  next();
}

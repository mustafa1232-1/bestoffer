const blockedKeys = new Set(["__proto__", "prototype", "constructor"]);
const MAX_DEPTH = 18;

function sanitizeValue(value, depth = 0) {
  if (depth > MAX_DEPTH) return null;

  if (Array.isArray(value)) {
    return value.map((entry) => sanitizeValue(entry, depth + 1));
  }

  if (value && typeof value === "object") {
    const cleaned = {};
    for (const [key, entry] of Object.entries(value)) {
      if (blockedKeys.has(key)) continue;
      cleaned[key] = sanitizeValue(entry, depth + 1);
    }
    return cleaned;
  }

  return value;
}

export function sanitizeInputMiddleware(req, res, next) {
  try {
    if (req.body && typeof req.body === "object") {
      req.body = sanitizeValue(req.body);
    }

    if (req.query && typeof req.query === "object") {
      req.query = sanitizeValue(req.query);
    }
  } catch (_) {
    // Keep request flow resilient even for malformed payloads.
  }

  next();
}

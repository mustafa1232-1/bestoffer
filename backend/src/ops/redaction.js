const SENSITIVE_KEY_PATTERNS = [
  /token/i,
  /password/i,
  /secret/i,
  /authorization/i,
  /api[_-]?key/i,
  /phone/i,
  /address/i,
  /payment/i,
  /wallet/i,
  /settlement/i,
  /commission/i,
  /refund/i,
  /card/i,
  /iban/i,
  /swift/i,
  /cookie/i,
];

const EMAIL_PATTERN = /([A-Z0-9._%+-]{2})[A-Z0-9._%+-]*(@[A-Z0-9.-]+\.[A-Z]{2,})/gi;
const PHONE_PATTERN = /\b(?:\+?\d[\d\s\-]{6,}\d)\b/g;
const BEARER_PATTERN = /bearer\s+[a-z0-9\-._~+/]+=*/gi;
const LONG_TOKEN_PATTERN = /\b[a-z0-9_\-]{24,}\b/gi;

function maskString(value) {
  const input = String(value || "");
  let out = input;
  out = out.replace(EMAIL_PATTERN, (_, start, domain) => `${start}***${domain}`);
  out = out.replace(PHONE_PATTERN, (match) => {
    const digits = match.replace(/\D/g, "");
    if (digits.length < 7) return match;
    const head = digits.slice(0, 3);
    const tail = digits.slice(-2);
    return `${head}***${tail}`;
  });
  out = out.replace(BEARER_PATTERN, "bearer [redacted]");
  out = out.replace(LONG_TOKEN_PATTERN, (match) => {
    if (/^[0-9]+$/.test(match)) return match;
    return `${match.slice(0, 4)}***${match.slice(-2)}`;
  });
  return out;
}

function isSensitiveKey(key) {
  const normalized = String(key || "").trim();
  if (!normalized) return false;
  return SENSITIVE_KEY_PATTERNS.some((pattern) => pattern.test(normalized));
}

function redactPrimitive(value) {
  if (value === null || value === undefined) return value;
  if (typeof value === "string") return maskString(value);
  return value;
}

function redactValue(value, stats, parentKey = "") {
  if (value === null || value === undefined) return value;

  if (Array.isArray(value)) {
    return value.map((item) => redactValue(item, stats, parentKey));
  }

  if (typeof value === "object") {
    const out = {};
    for (const [key, raw] of Object.entries(value)) {
      if (isSensitiveKey(key)) {
        out[key] = "[redacted]";
        stats.redactedFields += 1;
        continue;
      }
      out[key] = redactValue(raw, stats, key);
    }
    return out;
  }

  const redacted = redactPrimitive(value);
  if (typeof value === "string" && redacted !== value && isSensitiveKey(parentKey)) {
    stats.redactedFields += 1;
  }
  return redacted;
}

export function redactSensitiveData(payload) {
  const stats = {
    redactedFields: 0,
    redactedAt: new Date().toISOString(),
  };

  if (payload === null || payload === undefined) {
    return {
      payload: null,
      meta: stats,
    };
  }

  const redacted = redactValue(payload, stats);
  return {
    payload: redacted,
    meta: stats,
  };
}

export function sanitizeOpsText(value) {
  if (value === null || value === undefined) return "";
  return maskString(String(value)).slice(0, 10_000);
}

export function sanitizeOpsLogs(logs) {
  if (!Array.isArray(logs)) return [];
  return logs.slice(0, 200).map((entry) => {
    if (entry == null) return entry;
    if (typeof entry === "string") return sanitizeOpsText(entry);
    const { payload } = redactSensitiveData(entry);
    return payload;
  });
}

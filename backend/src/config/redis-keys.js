export const redisPrefixes = Object.freeze({
  rateLimit: "rl",
  firewall: "fw",
  cache: "cache",
  otp: "otp",
  queue: "queue",
  lock: "lock",
  session: "session",
});

export const redisTtls = Object.freeze({
  feedDiscoverySeconds: 90,
});

function normalizeKeyPart(value) {
  return String(value ?? "")
    .trim()
    .replace(/\s+/g, "-")
    .replace(/[:]+/g, "-")
    .replace(/[^a-zA-Z0-9._-]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-+|-+$/g, "");
}

export function buildRedisKey(prefix, ...parts) {
  return [prefix, ...parts.map(normalizeKeyPart)]
    .filter(Boolean)
    .join(":");
}

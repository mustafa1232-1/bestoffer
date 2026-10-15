export function classifyServiceConnection(value) {
  const raw = String(value || "").trim();
  if (!raw) return "unconfigured";

  try {
    const hostname = new URL(raw).hostname.toLowerCase();
    if (["localhost", "127.0.0.1", "::1"].includes(hostname)) return "local";
    if (/(^|\.)railway\.internal$/.test(hostname)) return "railway_private";
    if (
      /(^|\.)proxy\.rlwy\.net$/.test(hostname) ||
      /(^|\.)railway\.app$/.test(hostname)
    ) {
      return "railway_public_proxy";
    }
    return "external";
  } catch {
    return "invalid";
  }
}

import crypto from "crypto";

import { env } from "../../config/env.js";

function uniqueUrls(values) {
  return [...new Set((values || []).map((item) => String(item || "").trim()).filter(Boolean))];
}

function buildTurnCredential(username, secret) {
  return crypto.createHmac("sha1", secret).update(username).digest("base64");
}

async function buildTwilioRtcConfig() {
  if (!env.twilioAccountSid || !env.twilioAuthToken) {
    return null;
  }

  const auth = Buffer.from(
    `${env.twilioAccountSid}:${env.twilioAuthToken}`,
    "utf8"
  ).toString("base64");

  const endpoint = `https://api.twilio.com/2010-04-01/Accounts/${encodeURIComponent(
    env.twilioAccountSid
  )}/Tokens.json`;
  const payload = new URLSearchParams({
    Ttl: String(Math.max(300, Number(env.twilioNtsTtlSec) || 3600)),
  });

  const response = await fetch(endpoint, {
    method: "POST",
    headers: {
      Authorization: `Basic ${auth}`,
      "Content-Type": "application/x-www-form-urlencoded",
      Accept: "application/json",
    },
    body: payload.toString(),
  });

  if (!response.ok) {
    const details = await response.text().catch(() => "");
    throw new Error(`TWILIO_TURN_REQUEST_FAILED:${response.status}:${details}`);
  }

  const data = await response.json();
  const rawServers = Array.isArray(data?.ice_servers) ? data.ice_servers : [];
  const urls = rawServers
    .map((row) => {
      if (!row || typeof row !== "object") return null;
      const urlsValue = row.urls;
      const normalizedUrls = Array.isArray(urlsValue)
        ? urlsValue.map((item) => String(item || "").trim()).filter(Boolean)
        : [String(urlsValue || "").trim()].filter(Boolean);
      if (normalizedUrls.length <= 0) return null;
      return {
        urls: normalizedUrls.length === 1 ? normalizedUrls[0] : normalizedUrls,
        username: String(row.username || "").trim() || undefined,
        credential: String(row.credential || "").trim() || undefined,
      };
    })
    .filter(Boolean);

  const expiresAt = new Date(
    Date.now() + Math.max(300, Number(env.twilioNtsTtlSec) || 3600) * 1000
  );

  return {
    enabled: urls.length > 0,
    transport: "twilio-nts",
    provider: "twilio",
    generatedAt: new Date().toISOString(),
    expiresAt: expiresAt.toISOString(),
    ttlSeconds: Math.max(300, Number(env.twilioNtsTtlSec) || 3600),
    iceServers: urls,
  };
}

function buildSelfHostedTurnRtcConfig(userId) {
  const urls = uniqueUrls(env.rtcTurnUrls);
  const enabled = env.rtcTurnEnabled && urls.length > 0 && env.rtcTurnSecret.length > 0;
  if (!enabled) {
    return null;
  }

  const ttlSeconds = Math.max(300, Number(env.rtcTurnCredentialTtlSec) || 21600);
  const expiresAt = new Date(Date.now() + ttlSeconds * 1000);
  const username = `${Math.floor(expiresAt.getTime() / 1000)}:${Number(userId) || 0}`;
  const credential = buildTurnCredential(username, env.rtcTurnSecret);

  return {
    enabled: true,
    transport: "turn-tcp",
    provider: "self-hosted",
    generatedAt: new Date().toISOString(),
    expiresAt: expiresAt.toISOString(),
    ttlSeconds,
    iceServers: [
      {
        urls,
        username,
        credential,
      },
    ],
  };
}

function buildDisabledRtcConfig() {
  return {
    enabled: false,
    provider: "none",
    transport: "direct",
    generatedAt: new Date().toISOString(),
    expiresAt: null,
    iceServers: [],
  };
}

export async function buildRtcConfigForUser(userId) {
  try {
    if (env.rtcTurnProvider === "twilio") {
      const twilio = await buildTwilioRtcConfig();
      if (twilio) return twilio;
    }

    const selfHosted = buildSelfHostedTurnRtcConfig(userId);
    if (selfHosted) return selfHosted;

    if (!env.rtcTurnProvider && env.twilioAccountSid && env.twilioAuthToken) {
      const twilio = await buildTwilioRtcConfig();
      if (twilio) return twilio;
    }
  } catch (error) {
    console.warn("[rtc] failed to build managed RTC config", error?.message || error);
  }

  return buildDisabledRtcConfig();
}

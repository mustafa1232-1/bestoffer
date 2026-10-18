import crypto from "node:crypto";
import http2 from "node:http2";

/**
 * iOS VoIP (PushKit) sender for incoming in-app calls.
 *
 * FCM cannot deliver PushKit pushes, so iOS call invites go straight to APNs
 * with token-based auth (.p8 key). Apple requires every VoIP push to report a
 * call to CallKit immediately, so this sender is used ONLY for live call
 * invites — never for "call ended" or any other event.
 *
 * Env (all optional; when missing, iOS falls back to the FCM alert push):
 * - APNS_KEY_ID          10-char key id of the .p8 key (Apple Developer → Keys)
 * - APNS_TEAM_ID         10-char Apple team id
 * - APNS_PRIVATE_KEY     contents of AuthKey_XXXX.p8 (or APNS_PRIVATE_KEY_BASE64)
 * - APNS_BUNDLE_ID       app bundle id, default com.maslaki.user (topic gets ".voip")
 * - APNS_USE_SANDBOX     "true" for development builds signed with a dev profile
 */

const APNS_HOST_PRODUCTION = "https://api.push.apple.com";
const APNS_HOST_SANDBOX = "https://api.sandbox.push.apple.com";
const JWT_TTL_MS = 45 * 60 * 1000; // Apple rejects provider tokens older than 1h.

let cachedJwt = null;
let cachedJwtAt = 0;
let testTransport = null;

function readPrivateKey() {
  const raw = String(process.env.APNS_PRIVATE_KEY || "").trim();
  if (raw) return raw.replace(/\\n/g, "\n");
  const b64 = String(process.env.APNS_PRIVATE_KEY_BASE64 || "").trim();
  if (!b64) return "";
  try {
    return Buffer.from(b64, "base64").toString("utf8");
  } catch {
    return "";
  }
}

export function getApnsVoipConfig() {
  const keyId = String(process.env.APNS_KEY_ID || "").trim();
  const teamId = String(process.env.APNS_TEAM_ID || "").trim();
  const privateKey = readPrivateKey();
  const bundleId = String(process.env.APNS_BUNDLE_ID || "com.maslaki.user").trim();
  const sandbox = ["1", "true", "yes"].includes(
    String(process.env.APNS_USE_SANDBOX || "").trim().toLowerCase()
  );
  return {
    configured: Boolean(keyId && teamId && privateKey && bundleId),
    keyId,
    teamId,
    privateKey,
    bundleId,
    host: sandbox ? APNS_HOST_SANDBOX : APNS_HOST_PRODUCTION,
  };
}

function base64Url(input) {
  return Buffer.from(input).toString("base64url");
}

function providerToken(config, now = Date.now()) {
  if (cachedJwt && now - cachedJwtAt < JWT_TTL_MS) return cachedJwt;
  const header = base64Url(JSON.stringify({ alg: "ES256", kid: config.keyId }));
  const claims = base64Url(
    JSON.stringify({ iss: config.teamId, iat: Math.floor(now / 1000) })
  );
  const signature = crypto
    .sign("sha256", Buffer.from(`${header}.${claims}`), {
      key: config.privateKey,
      dsaEncoding: "ieee-p1363",
    })
    .toString("base64url");
  cachedJwt = `${header}.${claims}.${signature}`;
  cachedJwtAt = now;
  return cachedJwt;
}

function postToApns({ host, path, headers, body }) {
  if (testTransport) return testTransport({ host, path, headers, body });
  return new Promise((resolve) => {
    let client;
    let settled = false;
    const finish = (result) => {
      if (settled) return;
      settled = true;
      try {
        client?.close();
      } catch {}
      resolve(result);
    };
    try {
      client = http2.connect(host);
    } catch (error) {
      finish({ status: 0, reason: error?.message || "connect_failed" });
      return;
    }
    client.on("error", (error) => {
      finish({ status: 0, reason: error?.message || "connection_error" });
    });
    const req = client.request({ ":method": "POST", ":path": path, ...headers });
    let status = 0;
    let raw = "";
    req.setEncoding("utf8");
    req.on("response", (h) => {
      status = Number(h[":status"] || 0);
    });
    req.on("data", (chunk) => {
      raw += chunk;
    });
    req.on("end", () => {
      let reason = null;
      try {
        reason = raw ? JSON.parse(raw)?.reason || null : null;
      } catch {
        reason = null;
      }
      finish({ status, reason });
    });
    req.on("error", (error) => {
      finish({ status: 0, reason: error?.message || "request_error" });
    });
    req.setTimeout(8000, () => {
      req.close();
      finish({ status: 0, reason: "timeout" });
    });
    req.end(JSON.stringify(body));
  });
}

const DEAD_TOKEN_REASONS = new Set(["BadDeviceToken", "Unregistered", "DeviceTokenNotForTopic"]);

/**
 * Sends one VoIP push per token. Returns { accepted, deadTokens, failures }.
 * `callPayload` is delivered verbatim to PushKit (see ios/Runner/AppDelegate.swift).
 */
export async function sendVoipCallPush({ tokens = [], callPayload, expiresInSec = 40 }) {
  const config = getApnsVoipConfig();
  const result = { configured: config.configured, accepted: 0, deadTokens: [], failures: [] };
  if (!config.configured || !tokens.length) return result;
  let jwt;
  try {
    jwt = providerToken(config);
  } catch (error) {
    result.failures.push({ token: null, reason: `jwt:${error?.message || "sign_failed"}` });
    return result;
  }
  const headers = {
    authorization: `bearer ${jwt}`,
    "apns-topic": `${config.bundleId}.voip`,
    "apns-push-type": "voip",
    "apns-priority": "10",
    "apns-expiration": String(Math.floor(Date.now() / 1000) + Math.max(5, expiresInSec)),
    ...(callPayload?.id ? { "apns-collapse-id": String(callPayload.id).slice(0, 64) } : {}),
  };
  for (const token of tokens) {
    const response = await postToApns({
      host: config.host,
      path: `/3/device/${encodeURIComponent(token)}`,
      headers,
      body: { aps: {}, ...callPayload },
    });
    if (response.status === 200) {
      result.accepted += 1;
    } else if (response.status === 410 || DEAD_TOKEN_REASONS.has(response.reason)) {
      result.deadTokens.push(token);
    } else {
      result.failures.push({ token, status: response.status, reason: response.reason });
    }
  }
  return result;
}

export const __apnsVoipTestables = {
  setTransport(fn) {
    testTransport = fn;
    cachedJwt = null;
    cachedJwtAt = 0;
  },
  providerToken,
};

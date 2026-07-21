import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import https from "node:https";
import { Readable } from "node:stream";

import FormData from "form-data";

import { env } from "../../config/env.js";

function trimSlashes(value) {
  return String(value || "")
    .replace(/^\/+/, "")
    .replace(/\/+$/, "");
}

function normalizeBaseUrl(value) {
  const raw = String(value || "").trim();
  if (!raw) return "";
  return raw.replace(/\/+$/, "");
}

export function isCloudflareStreamConfigured() {
  return Boolean(
    env.cfStreamAccountId &&
      env.cfStreamApiToken &&
      (env.cfStreamCustomerCode || env.cfStreamPlaybackBaseUrl)
  );
}

export function isCloudflareStreamWebhookConfigured() {
  return Boolean(
    isCloudflareStreamConfigured() && String(env.cfStreamWebhookSecret || "").trim()
  );
}

function resolveStreamCustomerBaseUrl() {
  const explicit = normalizeBaseUrl(env.cfStreamPlaybackBaseUrl);
  if (explicit) return explicit;
  const customerCode = String(env.cfStreamCustomerCode || "").trim();
  if (!customerCode) return "";
  return `https://customer-${customerCode}.cloudflarestream.com`;
}

export function buildStreamPlaybackUrl(uid) {
  const base = resolveStreamCustomerBaseUrl();
  const safeUid = String(uid || "").trim();
  if (!base || !safeUid) return "";
  return `${base}/${safeUid}/manifest/video.m3u8`;
}

export function buildStreamThumbnailUrl(uid, time = "1s") {
  const base = normalizeBaseUrl(env.cfStreamThumbnailBaseUrl) || resolveStreamCustomerBaseUrl();
  const safeUid = String(uid || "").trim();
  if (!base || !safeUid) return "";
  const safeTime = String(time || "1s").trim() || "1s";
  return `${base}/${safeUid}/thumbnails/thumbnail.jpg?time=${encodeURIComponent(safeTime)}`;
}

function guessExtension(originalName = "", mimeType = "") {
  const ext = path.extname(String(originalName || "").trim()).toLowerCase();
  if (ext) return ext;
  const normalized = String(mimeType || "").trim().toLowerCase();
  switch (normalized) {
    case "video/mp4":
      return ".mp4";
    case "video/quicktime":
      return ".mov";
    case "video/webm":
      return ".webm";
    case "video/x-matroska":
      return ".mkv";
    case "video/3gpp":
      return ".3gp";
    default:
      return "";
  }
}

async function openStreamSource({
  sourceUrl = null,
  sourcePath = null,
}) {
  const filePath = String(sourcePath || "").trim();
  if (filePath && fs.existsSync(filePath)) {
    return {
      stream: fs.createReadStream(filePath),
      sourceName: path.basename(filePath),
      cleanup: async () => {},
    };
  }

  const url = String(sourceUrl || "").trim();
  if (!url) {
    throw new Error("STREAM_SOURCE_REQUIRED");
  }

  const response = await fetch(url);
  if (!response.ok || !response.body) {
    throw new Error(`STREAM_SOURCE_FETCH_FAILED:${response.status}`);
  }

  const webBody = response.body;
  const stream = Readable.fromWeb(webBody);
  const cleanup = async () => {
    try {
      if (!stream.destroyed) {
        stream.destroy();
      }
    } catch (_) {
      // ignore node stream cleanup failures
    }
    try {
      if (webBody?.locked !== true) {
        await webBody?.cancel?.();
      }
    } catch (_) {
      // ignore fetch cleanup failures
    }
  };
  return {
    stream,
    sourceName: path.basename(new URL(url).pathname) || "stream-media",
    cleanup,
  };
}

function readResponseBody(response) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    response.on("data", (chunk) => chunks.push(Buffer.from(chunk)));
    response.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    response.on("error", reject);
  });
}

function encodeUploadMetadataValue(value) {
  return Buffer.from(String(value || ""), "utf8").toString("base64");
}

function parseStreamUidFromLocation(location = "") {
  const raw = String(location || "").trim();
  if (!raw) return "";
  try {
    const parsed = new URL(raw, "https://api.cloudflare.com");
    const segments = parsed.pathname.split("/").filter(Boolean);
    if (segments.length <= 0) return "";
    if (segments.at(-1) === "upload" && segments.length >= 2) {
      return String(segments.at(-2) || "").trim();
    }
    return String(segments.at(-1) || "").trim();
  } catch {
    return raw.split("/").filter(Boolean).at(-1) || "";
  }
}

function parseCloudflareWebhookSignature(signatureHeader) {
  const raw = String(signatureHeader || "").trim();
  if (!raw) return null;
  const parts = raw
    .split(",")
    .map((part) => part.trim())
    .filter(Boolean);
  const result = {};
  for (const part of parts) {
    const index = part.indexOf("=");
    if (index <= 0) continue;
    const key = part.slice(0, index).trim().toLowerCase();
    const value = part.slice(index + 1).trim();
    if (key && value) result[key] = value;
  }
  if (!result.time || !result.sig1) return null;
  return result;
}

export function verifyCloudflareStreamWebhookSignature({
  rawBody,
  signatureHeader,
  secret = env.cfStreamWebhookSecret,
  maxSkewSeconds = 300,
}) {
  const parsed = parseCloudflareWebhookSignature(signatureHeader);
  const secretValue = String(secret || "").trim();
  const body =
    Buffer.isBuffer(rawBody)
      ? rawBody.toString("utf8")
      : String(rawBody || "");

  if (!parsed || !secretValue || !body) {
    return { ok: false, reason: "WEBHOOK_SIGNATURE_MISSING" };
  }

  const timestamp = Number(parsed.time);
  if (!Number.isFinite(timestamp) || timestamp <= 0) {
    return { ok: false, reason: "WEBHOOK_SIGNATURE_INVALID_TIME" };
  }
  const ageSeconds = Math.abs(Math.floor(Date.now() / 1000) - Math.floor(timestamp));
  if (Number.isFinite(maxSkewSeconds) && ageSeconds > maxSkewSeconds) {
    return { ok: false, reason: "WEBHOOK_SIGNATURE_EXPIRED" };
  }

  const expected = crypto
    .createHmac("sha256", secretValue)
    .update(`${parsed.time}.${body}`)
    .digest("hex");
  const expectedBuffer = Buffer.from(expected, "hex");
  const signatureBuffer = Buffer.from(parsed.sig1, "hex");
  if (
    expectedBuffer.length <= 0 ||
    signatureBuffer.length <= 0 ||
    expectedBuffer.length !== signatureBuffer.length
  ) {
    return { ok: false, reason: "WEBHOOK_SIGNATURE_MISMATCH" };
  }

  if (!crypto.timingSafeEqual(expectedBuffer, signatureBuffer)) {
    return { ok: false, reason: "WEBHOOK_SIGNATURE_MISMATCH" };
  }

  return { ok: true, reason: null };
}

export async function createCloudflareStreamUploadSession({
  title = null,
  sizeBytes,
  filename = null,
  mimeType = null,
  sourceType = null,
} = {}) {
  if (!isCloudflareStreamConfigured()) {
    const error = new Error("STREAM_NOT_CONFIGURED");
    error.status = 503;
    throw error;
  }

  const normalizedSize = Number(sizeBytes);
  if (!Number.isFinite(normalizedSize) || normalizedSize <= 0) {
    const error = new Error("STREAM_UPLOAD_SIZE_REQUIRED");
    error.status = 400;
    throw error;
  }

  const endpoint = `https://api.cloudflare.com/client/v4/accounts/${encodeURIComponent(
    env.cfStreamAccountId
  )}/stream?direct_user=true`;
  const headers = {
    Authorization: `Bearer ${env.cfStreamApiToken}`,
    "Tus-Resumable": "1.0.0",
    "Upload-Length": String(Math.max(1, Math.floor(normalizedSize))),
  };
  const metadata = [];
  const safeTitle = String(title || "").trim().slice(0, 180);
  const safeFileName = String(filename || "").trim().slice(0, 180);
  const safeMimeType = String(mimeType || "").trim().slice(0, 120);
  const safeSourceType = String(sourceType || "").trim().slice(0, 40);
  // Cloudflare's direct-user tus flow expects the reserved maximum duration to
  // be present in metadata. Without it, the generated upload URL can remain
  // authenticated/unsupported for browser-side uploads.
  const safeMaxDurationSeconds = 3600;
  if (safeTitle) metadata.push(`title ${encodeUploadMetadataValue(safeTitle)}`);
  if (safeFileName) metadata.push(`name ${encodeUploadMetadataValue(safeFileName)}`);
  if (safeMimeType) metadata.push(`mimeType ${encodeUploadMetadataValue(safeMimeType)}`);
  if (safeSourceType) metadata.push(`sourceType ${encodeUploadMetadataValue(safeSourceType)}`);
  metadata.push(
    `maxDurationSeconds ${encodeUploadMetadataValue(String(safeMaxDurationSeconds))}`
  );
  if (metadata.length > 0) {
    headers["Upload-Metadata"] = metadata.join(",");
  }

  const response = await fetch(endpoint, {
    method: "POST",
    headers,
  });

  const text = await response.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch (_) {
    json = null;
  }

  if (!response.ok) {
    const message =
      json?.errors?.[0]?.message ||
      json?.messages?.[0]?.message ||
      text ||
      `STREAM_UPLOAD_SESSION_FAILED_${response.status}`;
    const error = new Error(message);
    error.status = response.status || 502;
    error.details = json || null;
    throw error;
  }

  const uploadUrl =
    response.headers.get("location") ||
    json?.result?.location ||
    json?.result?.uploadURL ||
    "";
  const streamUid =
    response.headers.get("stream-media-id") ||
    response.headers.get("stream-media-id".toUpperCase()) ||
    json?.result?.uid ||
    parseStreamUidFromLocation(uploadUrl);

  return {
    uploadUrl: String(uploadUrl || "").trim() || null,
    streamUid: String(streamUid || "").trim() || null,
    readyToStream: Boolean(
      json?.result?.readyToStream ??
        json?.result?.ready_to_stream ??
        json?.result?.status === "ready"
    ),
    raw: json?.result || json || null,
    responseHeaders: Object.fromEntries(response.headers.entries()),
  };
}

export async function fetchCloudflareStreamVideoDetails(streamUid) {
  if (!isCloudflareStreamConfigured()) {
    const error = new Error("STREAM_NOT_CONFIGURED");
    error.status = 503;
    throw error;
  }
  const uid = String(streamUid || "").trim();
  if (!uid) {
    const error = new Error("STREAM_UID_REQUIRED");
    error.status = 400;
    throw error;
  }

  const endpoint = `https://api.cloudflare.com/client/v4/accounts/${encodeURIComponent(
    env.cfStreamAccountId
  )}/stream/${encodeURIComponent(uid)}`;
  const response = await fetch(endpoint, {
    method: "GET",
    headers: {
      Authorization: `Bearer ${env.cfStreamApiToken}`,
      Accept: "application/json",
    },
  });
  const text = await response.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch (_) {
    json = null;
  }

  if (!response.ok || json?.success === false) {
    const message =
      json?.errors?.[0]?.message ||
      json?.messages?.[0]?.message ||
      text ||
      `STREAM_VIDEO_DETAILS_FAILED_${response.status}`;
    const error = new Error(message);
    error.status = response.status || 502;
    error.details = json || null;
    throw error;
  }

  return json?.result || null;
}

async function requestStreamUpload({
  form,
  title,
}) {
  const endpoint = `https://api.cloudflare.com/client/v4/accounts/${encodeURIComponent(
    env.cfStreamAccountId
  )}/stream`;
  const headers = {
    Authorization: `Bearer ${env.cfStreamApiToken}`,
    ...form.getHeaders(),
  };
  if (title) headers["X-Title"] = String(title).trim().slice(0, 180);

  const contentLength = await new Promise((resolve) => {
    form.getLength((error, length) => {
      if (error || !Number.isFinite(length) || length <= 0) {
        resolve(null);
        return;
      }
      resolve(length);
    });
  });
  if (contentLength) {
    headers["Content-Length"] = String(contentLength);
  }

  const response = await new Promise((resolve, reject) => {
    const req = https.request(
      endpoint,
      {
        method: "POST",
        headers,
      },
      resolve
    );
    req.on("error", reject);
    form.pipe(req);
  });

  const body = await readResponseBody(response);
  let json = null;
  try {
    json = JSON.parse(body);
  } catch (_) {
    json = null;
  }

  if (response.statusCode < 200 || response.statusCode >= 300 || !json?.success) {
    const message =
      json?.errors?.[0]?.message ||
      json?.messages?.[0]?.message ||
      body ||
      `STREAM_UPLOAD_FAILED_${response.statusCode}`;
    const error = new Error(message);
    error.status = response.statusCode || 502;
    error.details = json || null;
    throw error;
  }

  return json.result || {};
}

export async function uploadVideoToCloudflareStream({
  sourceUrl = null,
  sourcePath = null,
  originalName = null,
  mimeType = null,
  title = null,
}) {
  if (!isCloudflareStreamConfigured()) {
    const error = new Error("STREAM_NOT_CONFIGURED");
    error.status = 503;
    throw error;
  }

  const source = await openStreamSource({ sourceUrl, sourcePath });
  const form = new FormData();
  const fileName =
    String(originalName || "").trim() ||
    source.sourceName ||
    `social_video${guessExtension(originalName || source.sourceName, mimeType)}`;

  form.append("file", source.stream, {
    filename: fileName,
    contentType: mimeType || "video/mp4",
  });

  if (title) {
    form.append("title", String(title).trim().slice(0, 180));
  }

  try {
    const result = await requestStreamUpload({ form, title });
    const uid = String(result.uid || "").trim();
    const playbackUrl =
      String(result.playback?.hls || result.playbackUrl || result.thumbnail || "").trim() ||
      buildStreamPlaybackUrl(uid);
    const thumbnailUrl =
      String(
        result.thumbnail ||
          result.thumbnailUrl ||
          result.preview ||
          buildStreamThumbnailUrl(uid)
      ).trim() || null;
    return {
      uid: uid || null,
      playbackUrl: playbackUrl || null,
      thumbnailUrl,
      readyToStream: Boolean(
        result.readyToStream ??
          result.ready_to_stream ??
          result.status === "ready"
      ),
      size: result.size == null ? null : Number(result.size),
      raw: result,
    };
  } finally {
    await source.cleanup();
  }
}

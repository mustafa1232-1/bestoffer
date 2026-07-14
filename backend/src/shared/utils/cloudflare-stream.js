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

  const stream = Readable.fromWeb(response.body);
  const cleanup = async () => {
    try {
      response.body?.cancel?.();
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

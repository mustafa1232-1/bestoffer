import path from "path";
import { randomUUID } from "crypto";
import { PassThrough } from "stream";

import { DeleteObjectCommand, PutObjectCommand, S3Client } from "@aws-sdk/client-s3";

import { env } from "../../config/env.js";

const extByMime = new Map([
  ["image/jpeg", ".jpg"],
  ["image/png", ".png"],
  ["image/webp", ".webp"],
  ["image/gif", ".gif"],
  ["video/mp4", ".mp4"],
  ["video/quicktime", ".mov"],
  ["video/webm", ".webm"],
  ["video/x-matroska", ".mkv"],
  ["video/3gpp", ".3gp"],
]);

function trimSlashes(value) {
  return String(value || "")
    .replace(/^\/+/, "")
    .replace(/\/+$/, "");
}

function guessExtension(originalName, mimeType) {
  const ext = String(path.extname(originalName || "") || "").toLowerCase();
  if (ext) return ext;
  return extByMime.get(String(mimeType || "").toLowerCase()) || "";
}

function sanitizeName(value) {
  const clean = String(value || "")
    .replace(/[^\w.-]/g, "_")
    .replace(/_+/g, "_")
    .slice(0, 40);
  return clean || "file";
}

function normalizePublicBaseUrl(value) {
  const raw = String(value || "").trim();
  if (!raw) return "";
  return raw.replace(/\/+$/, "");
}

function isR2Configured() {
  return Boolean(
    env.cfR2Bucket &&
      env.cfR2Endpoint &&
      env.cfR2AccessKeyId &&
      env.cfR2SecretAccessKey &&
      env.cfR2PublicBaseUrl
  );
}

let warnedPartialR2Config = false;
let cachedClient = null;

function getR2Client() {
  if (!isR2Configured()) {
    if (
      !warnedPartialR2Config &&
      (env.cfR2Bucket ||
        env.cfR2Endpoint ||
        env.cfR2AccessKeyId ||
        env.cfR2SecretAccessKey ||
        env.cfR2PublicBaseUrl)
    ) {
      warnedPartialR2Config = true;
      console.warn(
        "[r2] Incomplete R2 configuration detected. Falling back to local uploads."
      );
    }
    return null;
  }
  if (cachedClient) return cachedClient;
  cachedClient = new S3Client({
    region: "auto",
    endpoint: env.cfR2Endpoint,
    forcePathStyle: true,
    credentials: {
      accessKeyId: env.cfR2AccessKeyId,
      secretAccessKey: env.cfR2SecretAccessKey,
    },
  });
  return cachedClient;
}

export function isR2UploadsEnabled() {
  return Boolean(getR2Client());
}

export function buildR2ObjectKey({ originalName, mimeType, prefix = null }) {
  const ext = guessExtension(originalName, mimeType);
  const baseName = sanitizeName(path.basename(originalName || "", ext));
  const datePart = new Date().toISOString().slice(0, 10).replace(/-/g, "/");
  const keyPrefix = trimSlashes(prefix || env.cfR2UploadPrefix || "uploads");
  const uniq = `${Date.now()}_${randomUUID().slice(0, 8)}`;
  return `${keyPrefix}/${datePart}/${baseName}_${uniq}${ext}`;
}

export function buildR2PublicUrl(key) {
  const base = normalizePublicBaseUrl(env.cfR2PublicBaseUrl);
  const safeKey = trimSlashes(key);
  return `${base}/${safeKey}`;
}

export async function uploadStreamToR2({
  inputStream,
  originalName,
  mimeType,
  cacheControl = "public, max-age=31536000, immutable",
  contentLength = null,
  prefix = null,
}) {
  const client = getR2Client();
  if (!client) {
    const error = new Error("R2_NOT_CONFIGURED");
    error.status = 500;
    throw error;
  }

  const key = buildR2ObjectKey({
    originalName,
    mimeType,
    prefix,
  });

  const pass = new PassThrough();
  let size = 0;
  pass.on("data", (chunk) => {
    size += chunk.length;
  });
  inputStream.pipe(pass);

  await client.send(
    new PutObjectCommand({
      Bucket: env.cfR2Bucket,
      Key: key,
      Body: pass,
      ContentType: mimeType || "application/octet-stream",
      CacheControl: cacheControl,
      ...(Number.isFinite(Number(contentLength)) && Number(contentLength) > 0
        ? { ContentLength: Number(contentLength) }
        : {}),
    })
  );

  return {
    key,
    size,
    publicUrl: buildR2PublicUrl(key),
  };
}

export async function deleteR2Object(key) {
  const client = getR2Client();
  if (!client || !key) return;
  try {
    await client.send(
      new DeleteObjectCommand({
        Bucket: env.cfR2Bucket,
        Key: String(key),
      })
    );
  } catch (_) {
    // Best-effort cleanup only.
  }
}

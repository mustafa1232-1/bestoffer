import path from "path";
import fs from "fs";

import multer from "multer";
import { env } from "../../config/env.js";
import {
  deleteR2Object,
  isR2UploadsEnabled,
  uploadStreamToR2,
} from "./cloudflare-r2.js";
import { ensureUploadsDir, uploadsDir } from "./uploads.js";

const useR2Storage = isR2UploadsEnabled();
const r2MinFileSizeBytes = Number(env.cfR2MinFileSizeBytes || 0);
ensureUploadsDir();
let lastR2UploadError = null;
let lastR2UploadAt = null;

const allowedMimeTypes = new Set([
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/gif",
]);

const allowedMediaMimeTypes = new Set([
  ...allowedMimeTypes,
  "video/mp4",
  "video/quicktime",
  "video/webm",
  "video/x-matroska",
  "video/3gpp",
]);

function sanitizeBaseName(originalName = "image", ext = "") {
  return path
    .basename(originalName || "image", ext)
    .replace(/[^\w.-]/g, "_")
    .slice(0, 40);
}

function buildSafeFileName(originalName = "image") {
  const ext = path.extname(originalName || "").toLowerCase();
  const base = sanitizeBaseName(originalName || "image", ext);
  const uniq = `${Date.now()}_${Math.round(Math.random() * 1e9)}`;
  return `${base || "image"}_${uniq}${ext || ".jpg"}`;
}

function safeUnlink(filePath) {
  if (!filePath) return;
  try {
    if (fs.existsSync(filePath)) fs.unlinkSync(filePath);
  } catch (_) {
    // ignore cleanup errors
  }
}

const r2Storage = {
  _handleFile(req, file, cb) {
    const filename = buildSafeFileName(file.originalname || "image");
    const localPath = path.resolve(uploadsDir, filename);
    const out = fs.createWriteStream(localPath);
    let size = 0;
    let settled = false;

    const done = (error, info) => {
      if (settled) return;
      settled = true;
      if (error) {
        safeUnlink(localPath);
        cb(error);
        return;
      }
      cb(null, info);
    };

    out.on("error", (error) => done(error));
    file.stream.on("error", (error) => done(error));
    file.stream.on("data", (chunk) => {
      size += chunk.length;
    });

    out.on("finish", async () => {
      if (useR2Storage) {
        try {
          const readStream = fs.createReadStream(localPath);
          const uploaded = await uploadStreamToR2({
            inputStream: readStream,
            originalName: file.originalname,
            mimeType: file.mimetype,
            contentLength: size,
            prefix: "uploads",
          });
          safeUnlink(localPath);

          done(null, {
            filename: path.basename(uploaded.key),
            key: uploaded.key,
            r2Key: uploaded.key,
            location: uploaded.publicUrl,
            size,
            mimetype: file.mimetype,
            storageProvider: "r2",
          });
          lastR2UploadError = null;
          lastR2UploadAt = new Date().toISOString();
          return;
        } catch (error) {
          lastR2UploadError = String(error?.message || "R2_UPLOAD_FAILED");
          lastR2UploadAt = new Date().toISOString();
          console.warn(
            `[upload] R2 upload failed, falling back to local storage: ${
              error?.message || "unknown error"
            }`
          );
        }
      }

      done(null, {
        destination: uploadsDir,
        filename,
        path: localPath,
        size,
        mimetype: file.mimetype,
        storageProvider: "local",
      });
    });

    file.stream.pipe(out);
  },
  _removeFile(req, file, cb) {
    if (file?.r2Key || file?.storageProvider === "r2") {
      deleteR2Object(file?.r2Key || file?.key)
        .then(() => cb(null))
        .catch(() => cb(null));
      return;
    }
    safeUnlink(file?.path);
    cb(null);
  },
};

const storage = r2Storage;

function imageFilter(req, file, cb) {
  if (allowedMimeTypes.has(file.mimetype)) {
    cb(null, true);
    return;
  }

  const err = new Error("INVALID_IMAGE_TYPE");
  err.status = 400;
  cb(err);
}

export const imageUpload = multer({
  storage,
  fileFilter: imageFilter,
  limits: {
    fileSize: 8 * 1024 * 1024,
  },
});

function mediaFilter(req, file, cb) {
  if (allowedMediaMimeTypes.has(file.mimetype)) {
    cb(null, true);
    return;
  }

  const err = new Error("INVALID_MEDIA_TYPE");
  err.status = 400;
  cb(err);
}

export const mediaUpload = multer({
  storage,
  fileFilter: mediaFilter,
  limits: {
    fileSize: 28 * 1024 * 1024,
  },
});

export function buildUploadedFileUrl(req, file) {
  if (!file) return null;
  if (typeof file.location === "string" && file.location.trim()) {
    return file.location.trim();
  }
  return `${req.protocol}://${req.get("host")}/uploads/${file.filename}`;
}

export function getUploadRuntimeStatus() {
  return {
    r2Enabled: useR2Storage,
    r2MinFileSizeBytes,
    lastR2UploadError,
    lastR2UploadAt,
  };
}

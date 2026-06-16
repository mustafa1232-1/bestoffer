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

/**
 * Purpose:
 * تعريف سياسات رفع الملفات في النظام كله: الصور العامة، وسائط السوشال،
 * مرفقات الشات، مرفقات الوظائف، وبطاقات السكن.
 *
 * Used by:
 * - auth/company/feed/jobs/taxi وأي route يستخدم multer
 *
 * Depends on:
 * - `cloudflare-r2.js` للتخزين الإنتاجي
 * - `uploads.js` للفولدر المحلي fallback
 * - `env.js` لتحديد ما إذا كان local fallback مسموحاً
 *
 * Critical notes:
 * - هذا الملف حساس أمنياً وتشغيلياً لأنه يحدد MIME policy وأحجام الملفات.
 * - في production يجب ألا يعتمد workflow على local disk إلا أثناء fallback
 *   التطويري غير الإنتاجي.
 *
 * Maintenance notes:
 * - عند فشل upload افحص: نوع الملف، الحجم، R2 health، ثم صلاحية البناء
 *   المحلي للفولدر المؤقت.
 */
const useR2Storage = isR2UploadsEnabled();
const allowLocalUploadFallback = !env.isProduction;
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

const allowedChatAttachmentMimeTypes = new Set([
  ...allowedMediaMimeTypes,
  "audio/mp4",
  "audio/x-m4a",
  "audio/aac",
  "audio/mpeg",
  "audio/wav",
  "audio/x-wav",
  "audio/ogg",
  "audio/webm",
  "audio/opus",
  "application/pdf",
  "text/plain",
  "application/msword",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  "application/vnd.ms-excel",
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  "application/zip",
  "application/x-rar-compressed",
  "application/vnd.rar",
  "application/octet-stream",
]);

const allowedResidenceCardMimeTypes = new Set([
  "image/jpeg",
  "image/png",
  "image/webp",
]);

const allowedJobApplicationAttachmentMimeTypes = new Set([
  ...allowedMimeTypes,
  "application/pdf",
]);

const allowedJobApplicationAttachmentExtensions = new Set([
  ".jpg",
  ".jpeg",
  ".png",
  ".webp",
  ".gif",
  ".pdf",
]);

const allowedChatAttachmentExtensions = new Set([
  ".jpg",
  ".jpeg",
  ".png",
  ".webp",
  ".gif",
  ".mp4",
  ".mov",
  ".webm",
  ".mkv",
  ".3gp",
  ".m4a",
  ".aac",
  ".mp3",
  ".wav",
  ".ogg",
  ".opus",
  ".pdf",
  ".txt",
  ".doc",
  ".docx",
  ".xls",
  ".xlsx",
  ".zip",
  ".rar",
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
          safeUnlink(localPath);
          const r2Error = new Error("R2_UPLOAD_FAILED");
          r2Error.status = 503;
          r2Error.details = {
            reason: String(error?.message || "unknown error"),
          };
          done(r2Error);
          return;
        }
      }

      if (!allowLocalUploadFallback) {
        const storageError = new Error("R2_UPLOADS_REQUIRED");
        storageError.status = 503;
        done(storageError);
        return;
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

function residenceCardFilter(req, file, cb) {
  if (allowedResidenceCardMimeTypes.has(file.mimetype)) {
    cb(null, true);
    return;
  }

  const err = new Error("INVALID_RESIDENCE_CARD_IMAGE_TYPE");
  err.status = 400;
  cb(err);
}

export const residenceCardUpload = multer({
  storage: multer.memoryStorage(),
  fileFilter: residenceCardFilter,
  limits: {
    fileSize: 10 * 1024 * 1024,
  },
});

function registerWithCardFilter(req, file, cb) {
  const field = String(file.fieldname || "").trim();
  if (field === "cardImageFile") {
    return residenceCardFilter(req, file, cb);
  }
  return imageFilter(req, file, cb);
}

export const registerWithCardUpload = multer({
  storage,
  fileFilter: registerWithCardFilter,
  limits: {
    fileSize: 10 * 1024 * 1024,
  },
});

function chatAttachmentFilter(req, file, cb) {
  const ext = path.extname(file.originalname || "").toLowerCase();
  const mime = String(file.mimetype || "").toLowerCase();

  const mimeAllowed = allowedChatAttachmentMimeTypes.has(mime);
  const extAllowed = allowedChatAttachmentExtensions.has(ext);

  if (mimeAllowed && (mime !== "application/octet-stream" || extAllowed)) {
    cb(null, true);
    return;
  }

  const err = new Error("INVALID_CHAT_ATTACHMENT_TYPE");
  err.status = 400;
  cb(err);
}

export const chatAttachmentUpload = multer({
  storage,
  fileFilter: chatAttachmentFilter,
  limits: {
    fileSize: 32 * 1024 * 1024,
  },
});

function jobApplicationAttachmentFilter(req, file, cb) {
  const ext = path.extname(file.originalname || "").toLowerCase();
  const mime = String(file.mimetype || "").toLowerCase();

  const mimeAllowed = allowedJobApplicationAttachmentMimeTypes.has(mime);
  const extAllowed = allowedJobApplicationAttachmentExtensions.has(ext);

  if (mimeAllowed && (mime !== "application/octet-stream" || extAllowed)) {
    cb(null, true);
    return;
  }

  const err = new Error("INVALID_JOB_APPLICATION_ATTACHMENT_TYPE");
  err.status = 400;
  cb(err);
}

export const jobApplicationAttachmentUpload = multer({
  storage,
  fileFilter: jobApplicationAttachmentFilter,
  limits: {
    fileSize: 20 * 1024 * 1024,
  },
});

/**
 * يحول ناتج multer إلى URL عام مستقر للواجهة.
 *
 * Return value:
 * - رابط R2 مباشر إن كان الرفع على R2
 * - رابط `/uploads/...` محلي في بيئات fallback المحلية
 */
export function buildUploadedFileUrl(req, file) {
  if (!file) return null;
  if (typeof file.location === "string" && file.location.trim()) {
    return file.location.trim();
  }
  return `${req.protocol}://${req.get("host")}/uploads/${file.filename}`;
}

/**
 * يعرض حالة runtime الحالية لطبقة الرفع لتظهر في `/health`.
 */
export function getUploadRuntimeStatus() {
  return {
    provider: useR2Storage ? "r2" : "local",
    r2Enabled: useR2Storage,
    localFallbackAllowed: allowLocalUploadFallback,
    lastR2UploadError,
    lastR2UploadAt,
  };
}

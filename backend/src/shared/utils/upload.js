import path from "path";

import multer from "multer";
import { ensureUploadsDir, uploadsDir } from "./uploads.js";

ensureUploadsDir();

const allowedMimeTypes = new Set([
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/gif",
  "image/heic",
  "image/heif",
]);

const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, uploadsDir),
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname || "").toLowerCase();
    const base = path
      .basename(file.originalname || "image", ext)
      .replace(/[^\w.-]/g, "_")
      .slice(0, 40);
    const uniq = `${Date.now()}_${Math.round(Math.random() * 1e9)}`;
    cb(null, `${base || "image"}_${uniq}${ext || ".jpg"}`);
  },
});

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

export function buildUploadedFileUrl(req, file) {
  if (!file) return null;
  return `${req.protocol}://${req.get("host")}/uploads/${file.filename}`;
}

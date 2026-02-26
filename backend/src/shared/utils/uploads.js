import fs from "fs";
import path from "path";

const uploadsDirFromEnv = String(process.env.UPLOADS_DIR || "uploads").trim();

export const uploadsDir = path.isAbsolute(uploadsDirFromEnv)
  ? uploadsDirFromEnv
  : path.resolve(process.cwd(), uploadsDirFromEnv || "uploads");

export const missingImagePng = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO0LxYQAAAAASUVORK5CYII=",
  "base64"
);

export function ensureUploadsDir() {
  if (!fs.existsSync(uploadsDir)) {
    fs.mkdirSync(uploadsDir, { recursive: true });
  }
}

export function resolveUploadFilePath(fileName) {
  return path.resolve(uploadsDir, path.basename(fileName || ""));
}

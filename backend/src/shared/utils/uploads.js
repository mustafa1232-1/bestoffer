import fs from "fs";
import path from "path";

export const uploadsDir = path.resolve(process.cwd(), "uploads");

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

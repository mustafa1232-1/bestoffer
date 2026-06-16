import { env } from "../../../config/env.js";
import { extractTextWithGoogleVision } from "./providers/google-vision.provider.js";
import { extractTextWithTesseract } from "./providers/tesseract.provider.js";

export async function extractResidenceCardText({
  imageBuffer,
  mimeType = null,
  fileName = "",
}) {
  const preferred = String(env.residenceCardOcrProvider || "tesseract").toLowerCase();

  const providers = preferred === "google_vision"
    ? ["google_vision", "tesseract"]
    : ["tesseract", "google_vision"];

  let lastError = null;
  for (const provider of providers) {
    try {
      if (provider === "google_vision") {
        return await extractTextWithGoogleVision({
          buffer: imageBuffer,
          mimeType,
          fileName,
        });
      }
      return await extractTextWithTesseract({
        buffer: imageBuffer,
      });
    } catch (error) {
      lastError = error;
    }
  }

  const err = new Error("OCR_PROVIDER_FAILED");
  err.status = 503;
  err.details = {
    reason: String(lastError?.message || "unknown"),
  };
  throw err;
}

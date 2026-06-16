import { env } from "../../../../config/env.js";

function inferMimeType(fileName = "", fallback = "image/jpeg") {
  const lower = String(fileName || "").toLowerCase();
  if (lower.endsWith(".png")) return "image/png";
  if (lower.endsWith(".webp")) return "image/webp";
  return fallback;
}

export async function extractTextWithGoogleVision({
  buffer,
  mimeType = null,
  fileName = "",
}) {
  if (!env.googleVisionApiKey) {
    throw new Error("GOOGLE_VISION_API_KEY_NOT_CONFIGURED");
  }
  if (!buffer || buffer.length === 0) {
    throw new Error("OCR_IMAGE_BUFFER_REQUIRED");
  }

  const content = Buffer.from(buffer).toString("base64");
  const detectedMime = mimeType || inferMimeType(fileName);
  const body = {
    requests: [
      {
        image: { content },
        features: [{ type: "DOCUMENT_TEXT_DETECTION", maxResults: 1 }],
        imageContext: {
          languageHints: ["ar", "en"],
        },
      },
    ],
  };

  const url = `${env.googleVisionApiUrl}?key=${encodeURIComponent(env.googleVisionApiKey)}`;
  const response = await fetch(url, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      accept: "application/json",
      "x-image-mime-type": detectedMime,
    },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    const errorText = await response.text().catch(() => "");
    const error = new Error("GOOGLE_VISION_REQUEST_FAILED");
    error.details = {
      status: response.status,
      body: errorText.slice(0, 500),
    };
    throw error;
  }

  const payload = await response.json();
  const first = payload?.responses?.[0] || {};
  const text = String(first?.fullTextAnnotation?.text || "").trim();
  if (!text) {
    return {
      provider: "google_vision",
      text: "",
      confidence: null,
    };
  }

  return {
    provider: "google_vision",
    text,
    confidence: null,
  };
}

import { createWorker } from "tesseract.js";

let workerPromise = null;

async function getWorker() {
  if (!workerPromise) {
    workerPromise = createWorker("ara+eng");
  }
  return workerPromise;
}

export async function extractTextWithTesseract({ buffer }) {
  if (!buffer || buffer.length === 0) {
    throw new Error("OCR_IMAGE_BUFFER_REQUIRED");
  }
  const worker = await getWorker();
  const result = await worker.recognize(buffer);
  const text = String(result?.data?.text || "").trim();
  const confidenceRaw = Number(result?.data?.confidence);
  const confidence = Number.isFinite(confidenceRaw)
    ? Math.max(0, Math.min(1, confidenceRaw / 100))
    : null;
  return {
    provider: "tesseract",
    text,
    confidence,
  };
}

export async function terminateTesseractWorker() {
  if (!workerPromise) return;
  try {
    const worker = await workerPromise;
    await worker.terminate();
  } finally {
    workerPromise = null;
  }
}

import crypto from "node:crypto";

import bcrypt from "bcryptjs";

const LEGACY_SHA256_HEX_RE = /^[a-f0-9]{64}$/i;

export function isBcryptHash(hash) {
  return /^\$2[aby]\$\d{2}\$/.test(String(hash || ""));
}

export function isLegacyPinHash(hash) {
  return LEGACY_SHA256_HEX_RE.test(String(hash || "").trim());
}

function hashLegacyPin(pin) {
  return crypto
    .createHash("sha256")
    .update(String(pin || ""))
    .digest("hex");
}

export async function hashPin(pin) {
  return bcrypt.hash(String(pin), 10);
}

export async function verifyPin(pin, hash) {
  const result = await verifyPinDetailed(pin, hash);
  return result.ok;
}

export async function verifyPinDetailed(pin, hash) {
  const normalizedPin = String(pin || "");
  const normalizedHash = String(hash || "").trim();
  if (!normalizedHash) {
    return {
      ok: false,
      algorithm: "unknown",
      needsUpgrade: false,
    };
  }

  if (isBcryptHash(normalizedHash)) {
    return {
      ok: await bcrypt.compare(normalizedPin, normalizedHash),
      algorithm: "bcrypt",
      needsUpgrade: false,
    };
  }

  if (isLegacyPinHash(normalizedHash)) {
    const expected = hashLegacyPin(normalizedPin);
    return {
      ok: expected === normalizedHash.toLowerCase(),
      algorithm: "legacy_sha256",
      needsUpgrade: true,
    };
  }

  return {
    ok: false,
    algorithm: "unknown",
    needsUpgrade: false,
  };
}

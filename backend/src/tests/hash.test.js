import assert from "node:assert/strict";
import crypto from "node:crypto";
import test from "node:test";

import {
  hashPin,
  isBcryptHash,
  isLegacyPinHash,
  verifyPinDetailed,
} from "../shared/utils/hash.js";

test("verifyPinDetailed accepts bcrypt pins without upgrade", async () => {
  const hashed = await hashPin("1234");
  const result = await verifyPinDetailed("1234", hashed);

  assert.equal(isBcryptHash(hashed), true);
  assert.equal(result.ok, true);
  assert.equal(result.algorithm, "bcrypt");
  assert.equal(result.needsUpgrade, false);
});

test("verifyPinDetailed accepts legacy sha256 pins and marks them for upgrade", async () => {
  const legacyHash = crypto.createHash("sha256").update("4321").digest("hex");
  const result = await verifyPinDetailed("4321", legacyHash);

  assert.equal(isLegacyPinHash(legacyHash), true);
  assert.equal(result.ok, true);
  assert.equal(result.algorithm, "legacy_sha256");
  assert.equal(result.needsUpgrade, true);
});

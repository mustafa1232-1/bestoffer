import assert from "node:assert/strict";
import test, { after } from "node:test";
import { randomUUID } from "node:crypto";
import { pool, q } from "../config/db.js";
import { closeRedisClient } from "../config/redis.js";
import { completeTemporaryPinChange } from "../modules/auth/auth.service.js";
import { hashPin, verifyPin } from "../shared/utils/hash.js";
import { assertSafeE2EDatabaseTarget } from "../scripts/e2eDbSafety.js";

after(async () => {
  await closeRedisClient();
  await pool.end();
});

test("temporary PIN change verifies the actual credential, including non-default PINs", async () => {
  assertSafeE2EDatabaseTarget({ scriptName: "auth.temporary-pin.db.test",
    databaseUrl: process.env.DATABASE_URL, allowProductionOverride: false, isProduction: false });
  for (const temporaryPin of ["639281", "1234"]) {
    const tag = randomUUID().replaceAll("-", "").slice(0, 8);
    const { rows } = await q(`INSERT INTO app_user
      (full_name, phone, username, pin_hash, role, block, building_number, apartment, must_change_pin)
      VALUES ($1, $2, $3, $4, 'owner', 'A', 'A203', '1', TRUE) RETURNING id`,
      [`PIN regression ${tag}`, `077pin${tag}`, `pin_${tag}`, await hashPin(temporaryPin)]);
    const id = Number(rows[0].id);
    try {
      await assert.rejects(completeTemporaryPinChange(id, "0000", "762815"),
        { message: "INVALID_TEMPORARY_PIN" });
      await assert.rejects(completeTemporaryPinChange(id, temporaryPin, temporaryPin),
        { message: "INVALID_NEW_PIN" });
      await assert.rejects(completeTemporaryPinChange(id, temporaryPin, "1234"),
        { message: "INVALID_NEW_PIN" });
      const unchanged = (await q("SELECT must_change_pin, pin_hash FROM app_user WHERE id=$1", [id])).rows[0];
      assert.equal(unchanged.must_change_pin, true);
      assert.equal(await verifyPin(temporaryPin, unchanged.pin_hash), true);
      await completeTemporaryPinChange(id, temporaryPin, "762815");
      const updated = (await q("SELECT must_change_pin, pin_hash FROM app_user WHERE id=$1", [id])).rows[0];
      assert.equal(updated.must_change_pin, false);
      assert.equal(await verifyPin("762815", updated.pin_hash), true);
      await assert.rejects(completeTemporaryPinChange(id, "762815", "938261"),
        { message: "PIN_CHANGE_NOT_REQUIRED" });
    } finally {
      await q("DELETE FROM app_user WHERE id=$1", [id]);
    }
  }
});

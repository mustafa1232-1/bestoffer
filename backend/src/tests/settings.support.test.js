import "dotenv/config";

import assert from "node:assert/strict";
import test from "node:test";

import { q } from "../config/db.js";
import * as settings from "../modules/settings/settings.service.js";

let savedRow = null;

test.before(async () => {
  const r = await q(
    `SELECT value_json FROM platform_setting WHERE key = $1`,
    [settings.SUPPORT_SETTING_KEY]
  );
  savedRow = r.rows[0] ? r.rows[0].value_json : null;
});

test.after(async () => {
  if (savedRow) {
    await q(
      `INSERT INTO platform_setting (key, value_json) VALUES ($1, $2::jsonb)
       ON CONFLICT (key) DO UPDATE SET value_json = EXCLUDED.value_json`,
      [settings.SUPPORT_SETTING_KEY, JSON.stringify(savedRow)]
    );
  } else {
    await q(`DELETE FROM platform_setting WHERE key = $1`, [
      settings.SUPPORT_SETTING_KEY,
    ]);
  }
});

test("update + read round-trips the support contact", async () => {
  await settings.updateSupportContact({
    actorUserId: null,
    dto: {
      supportPhoneE164: "+9647701234567",
      supportPhoneDisplay: "0770 123 4567",
      supportWorkingHours: "9-17",
      supportEmergencyPhone: "+9647809999999",
    },
  });
  const out = await settings.getSupportContact();
  assert.equal(out.supportPhoneE164, "+9647701234567");
  assert.equal(out.supportEmergencyPhone, "+9647809999999");
  assert.equal(out.supportWorkingHours, "9-17");

  const pub = await settings.getPublicSettings();
  assert.equal(pub.support.supportPhoneE164, "+9647701234567");
});

test("invalid E164 is rejected", async () => {
  await assert.rejects(
    settings.updateSupportContact({
      actorUserId: null,
      dto: { supportPhoneE164: "12345" },
    })
  );
});

test("injection in display text is stripped, not stored raw", async () => {
  await settings.updateSupportContact({
    actorUserId: null,
    dto: {
      supportPhoneE164: "+9647701234567",
      supportPhoneDisplay: "call <script>alert(1)</script> us",
    },
  });
  const out = await settings.getSupportContact();
  assert.ok(!out.supportPhoneDisplay.includes("<"));
  assert.ok(!out.supportPhoneDisplay.includes(">"));
  assert.ok(out.supportPhoneDisplay.includes("call"));
});

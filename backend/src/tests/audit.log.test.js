import "dotenv/config";

import assert from "node:assert/strict";
import test from "node:test";

import { q } from "../config/db.js";
import { recordAudit, searchAuditEvents } from "../modules/security/audit.service.js";

const ACTION = `test.audit.${Date.now()}.${Math.random().toString(36).slice(2, 8)}`;

test.after(async () => {
  await q(`DELETE FROM admin_audit_event WHERE action_key = $1`, [ACTION]);
});

test("recordAudit writes an event and searchAuditEvents finds it by action", async () => {
  const res = await recordAudit({
    actorUserId: null,
    actorRole: "admin",
    actionKey: ACTION,
    summary: "unit test event",
    targetType: "app_user",
    targetId: 12345,
    reason: "testing",
    permissionKey: "audit.read",
  });
  assert.equal(res.ok, true);

  const found = await searchAuditEvents({ actionKey: ACTION, limit: 10 });
  assert.ok(found.total >= 1);
  const row = found.items[0];
  assert.equal(row.action_key, ACTION);
  assert.equal(row.target_type, "app_user");
  assert.equal(Number(row.target_id), 12345);
  assert.equal(row.reason, "testing");
  assert.equal(row.result, "ok");
});

test("sensitive fields in before/after are masked", async () => {
  await recordAudit({
    actionKey: ACTION,
    summary: "masking test",
    before: {
      full_name: "Ali",
      pin_hash: "supersecret",
      nested: { token: "abc123", ok: "keep" },
    },
    after: { password: "np", visible: 42 },
  });

  const found = await searchAuditEvents({ actionKey: ACTION, limit: 10 });
  const masked = found.items.find(
    (r) => r.before_json && r.before_json.full_name === "Ali"
  );
  assert.ok(masked, "expected the masking-test row");
  assert.equal(masked.before_json.pin_hash, "***");
  assert.equal(masked.before_json.nested.token, "***");
  assert.equal(masked.before_json.nested.ok, "keep");
  assert.equal(masked.after_json.password, "***");
  assert.equal(masked.after_json.visible, 42);
});

test("recordAudit never throws on bad input (best-effort)", async () => {
  const res = await recordAudit({ actionKey: ACTION, summary: null });
  assert.equal(typeof res.ok, "boolean");
});

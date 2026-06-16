import assert from "node:assert/strict";
import test from "node:test";

import { redactSensitiveData, sanitizeOpsText } from "../ops/redaction.js";

test("redactSensitiveData hides sensitive keys recursively", () => {
  const input = {
    token: "abc123",
    user: {
      phone: "07701234567",
      nested: {
        authorization: "Bearer very-secret-token",
      },
    },
    safe: "hello",
  };

  const out = redactSensitiveData(input);
  assert.equal(out.payload.token, "[redacted]");
  assert.equal(out.payload.user.phone, "[redacted]");
  assert.equal(out.payload.user.nested.authorization, "[redacted]");
  assert.equal(out.payload.safe, "hello");
  assert.ok(out.meta.redactedFields >= 3);
});

test("sanitizeOpsText masks bearer and phone patterns", () => {
  const raw = "Bearer abcdefghijklmnopqrstuvwxyz 07701234567";
  const masked = sanitizeOpsText(raw);
  assert.match(masked.toLowerCase(), /bearer \[redacted\]/);
  assert.match(masked, /077\*\*\*67/);
});

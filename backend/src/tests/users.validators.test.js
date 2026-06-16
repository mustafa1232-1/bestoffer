import assert from "node:assert/strict";
import test from "node:test";

import {
  validateDeleteMyAccount,
  validateSessionId,
} from "../modules/users/users.validators.js";

test("validateDeleteMyAccount accepts empty body", () => {
  const result = validateDeleteMyAccount({});
  assert.equal(result.ok, true);
  assert.equal(result.value.note, null);
});

test("validateDeleteMyAccount rejects long note", () => {
  const result = validateDeleteMyAccount({
    note: "x".repeat(501),
  });
  assert.equal(result.ok, false);
  assert.deepEqual(result.errors, ["note"]);
});

test("validateSessionId accepts positive integer", () => {
  const result = validateSessionId("33");
  assert.equal(result.ok, true);
  assert.equal(result.value, 33);
});

test("validateSessionId rejects invalid values", () => {
  const result = validateSessionId("abc");
  assert.equal(result.ok, false);
  assert.deepEqual(result.errors, ["sessionId"]);
});

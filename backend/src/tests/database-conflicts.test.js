import assert from "node:assert/strict";
import test from "node:test";

import {
  AppError,
  isDatabaseTemporarilyUnavailable,
  isDatabaseUniqueViolation,
  toAppError,
} from "../shared/utils/errors.js";

test("recognizes only the requested PostgreSQL unique constraint", () => {
  const error = {
    code: "23505",
    constraint: "uq_service_offerings_provider_name_per_sub",
  };

  assert.equal(isDatabaseUniqueViolation(error), true);
  assert.equal(
    isDatabaseUniqueViolation(
      error,
      "uq_service_offerings_provider_name_per_sub",
    ),
    true,
  );
  assert.equal(
    isDatabaseUniqueViolation(error, "app_user_phone_key"),
    false,
  );
});

test("maps an otherwise unhandled unique violation to an exposed 409", () => {
  const mapped = toAppError({
    code: "23505",
    constraint: "some_future_unique_constraint",
  });

  assert.ok(mapped instanceof AppError);
  assert.equal(mapped.status, 409);
  assert.equal(mapped.code, "RESOURCE_ALREADY_EXISTS");
  assert.equal(mapped.message, "RESOURCE_ALREADY_EXISTS");
  assert.equal(mapped.expose, true);
});

test("maps PostgreSQL startup to retryable service unavailable", () => {
  const source = {
    code: "57P03",
    message: "the database system is starting up",
  };

  assert.equal(isDatabaseTemporarilyUnavailable(source), true);
  const mapped = toAppError(source);
  assert.equal(mapped.status, 503);
  assert.equal(mapped.code, "DATABASE_TEMPORARILY_UNAVAILABLE");
  assert.equal(mapped.message, "DATABASE_TEMPORARILY_UNAVAILABLE");
  assert.equal(mapped.expose, true);
});

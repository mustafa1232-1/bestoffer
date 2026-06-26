import assert from "node:assert/strict";
import test from "node:test";

import {
  CircuitBreaker,
  computeBackoffDelay,
  createRealtimeError,
  extractStatusCode,
  isRetryableError,
  redactSecrets,
  runWithCircuit,
  sanitizeErrorForLog,
  stripHtml,
  withRetry,
  withTimeout,
} from "../shared/realtime/realtime-resilience.js";

test("stripHtml removes a full Cloudflare 520 HTML error page", () => {
  const html =
    "<!DOCTYPE html><html><head><title>520</title><style>body{}</style></head>" +
    "<body><h1>Error 520</h1><p>Web server is returning an unknown error</p></body></html>";
  const out = stripHtml(html);
  assert.equal(out.includes("<"), false);
  assert.equal(out.includes(">"), false);
  assert.match(out, /Web server is returning an unknown error/);
});

test("redactSecrets removes JWTs, bearer tokens, api keys and service role", () => {
  const jwt =
    "eyJhbGciOiJIUzI1Ni1.eyJzdWIiOiIxMjM0NTY3ODkw.SflKxwRJSMeKKF2QT4fwpMeJf";
  const raw = `Authorization: Bearer ${jwt} apikey=${jwt} service_role_key=abc123def456`;
  const out = redactSecrets(raw);
  assert.equal(out.includes(jwt), false);
  assert.match(out, /\[redacted\]/);
});

test("sanitizeErrorForLog never returns HTML, secrets, or > maxLen chars", () => {
  const error = new Error(
    "<html><body>520 " + "x".repeat(1000) + " Bearer eyJabc.def.ghi</body></html>"
  );
  error.status = 520;
  const safe = sanitizeErrorForLog(error, 300);
  assert.equal(safe.message.length <= 300, true);
  assert.equal(safe.message.includes("<"), false);
  assert.equal(safe.message.includes("Bearer eyJabc"), false);
  assert.equal(safe.statusCode, 520);
  assert.equal(safe.retryable, true);
});

test("extractStatusCode reads status, statusCode, details.status and message", () => {
  assert.equal(extractStatusCode({ status: 503 }), 503);
  assert.equal(extractStatusCode({ statusCode: 429 }), 429);
  assert.equal(extractStatusCode({ details: { status: 520 } }), 520);
  assert.equal(
    extractStatusCode(new Error("supabase.co | 520 Web server error")),
    520
  );
  assert.equal(extractStatusCode(null), null);
});

test("isRetryableError treats 5xx/429/timeouts/network as retryable, 4xx as not", () => {
  assert.equal(isRetryableError({ status: 520 }), true);
  assert.equal(isRetryableError({ status: 503 }), true);
  assert.equal(isRetryableError({ status: 429 }), true);
  assert.equal(isRetryableError({ status: 404 }), false);
  assert.equal(isRetryableError({ status: 403 }), false);
  assert.equal(isRetryableError({ code: "ETIMEDOUT" }), true);
  assert.equal(isRetryableError(new Error("fetch failed")), true);
  assert.equal(isRetryableError(createRealtimeError("X", { retryable: false })), false);
});

test("computeBackoffDelay grows exponentially and respects the ceiling", () => {
  const noJitter = (attempt) =>
    computeBackoffDelay(attempt, { baseDelayMs: 100, maxDelayMs: 1000, jitter: false });
  assert.equal(noJitter(1), 100);
  assert.equal(noJitter(2), 200);
  assert.equal(noJitter(3), 400);
  assert.equal(noJitter(50), 1000); // capped
});

test("withRetry retries retryable errors then succeeds, counting attempts", async () => {
  let attempts = 0;
  const result = await withRetry(
    async () => {
      attempts += 1;
      if (attempts < 3) throw createRealtimeError("E", { status: 520 });
      return "ok";
    },
    { retries: 3, sleep: async () => {} }
  );
  assert.equal(result, "ok");
  assert.equal(attempts, 3);
});

test("withRetry does not retry non-retryable errors", async () => {
  let attempts = 0;
  await assert.rejects(
    withRetry(
      async () => {
        attempts += 1;
        throw createRealtimeError("E", { status: 403 });
      },
      { retries: 3, sleep: async () => {} }
    )
  );
  assert.equal(attempts, 1);
});

test("withTimeout rejects with a retryable timeout error", async () => {
  await assert.rejects(
    withTimeout(new Promise(() => {}), 10, "probe"),
    (error) => {
      assert.equal(error.code, "REALTIME_TIMEOUT");
      assert.equal(isRetryableError(error), true);
      return true;
    }
  );
});

test("CircuitBreaker opens after threshold and half-opens after cooldown", () => {
  let nowMs = 1000;
  const breaker = new CircuitBreaker({
    failureThreshold: 3,
    cooldownMs: 5000,
    now: () => nowMs,
  });
  assert.equal(breaker.canRequest(), true);
  breaker.recordFailure();
  breaker.recordFailure();
  assert.equal(breaker.snapshot().state, "closed");
  breaker.recordFailure();
  assert.equal(breaker.snapshot().state, "open");
  assert.equal(breaker.canRequest(), false); // still within cooldown
  nowMs += 5000;
  assert.equal(breaker.canRequest(), true); // half-open trial allowed
  breaker.recordSuccess();
  assert.equal(breaker.snapshot().state, "closed");
});

test("runWithCircuit fails fast when the circuit is open", async () => {
  const breaker = new CircuitBreaker({ failureThreshold: 1, cooldownMs: 60000 });
  await assert.rejects(
    runWithCircuit(breaker, async () => {
      throw createRealtimeError("BOOM", { status: 520 });
    })
  );
  // Circuit now open: next call should fail fast without invoking fn.
  let invoked = false;
  await assert.rejects(
    runWithCircuit(breaker, async () => {
      invoked = true;
      return "should-not-run";
    }),
    (error) => {
      assert.equal(error.code, "REALTIME_CIRCUIT_OPEN");
      return true;
    }
  );
  assert.equal(invoked, false);
});

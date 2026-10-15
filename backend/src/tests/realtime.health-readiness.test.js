import assert from "node:assert/strict";
import test from "node:test";

import { buildTransientRealtimeProbeFailure } from "../shared/utils/realtime-readiness.js";

test("transient realtime probe failures do not take the core API out of readiness", () => {
  const readiness = buildTransientRealtimeProbeFailure({
    reason: "realtime_probe_timeout",
    status: {
      enabled: true,
      configured: true,
      requestedMode: "dual",
      missingKeys: [],
    },
  });

  assert.equal(readiness.ok, false);
  assert.equal(readiness.transientFailure, true);
  assert.equal(readiness.releaseBlocking, false);
  assert.equal(readiness.checks.dualModeRequested, true);
});

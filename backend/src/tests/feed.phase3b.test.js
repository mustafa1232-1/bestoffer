import assert from "node:assert/strict";
import test from "node:test";

import {
  validateCommunityChatMessageBody,
  validateSendMessage,
} from "../modules/feed/feed.validators.js";

test("phase 3b thread messages accept clientMessageId and preserve it", () => {
  const result = validateSendMessage({
    body: "Phase 3B hello",
    clientMessageId: "msg_phase3b_001",
  });

  assert.equal(result.ok, true);
  assert.equal(result.value.body, "Phase 3B hello");
  assert.equal(result.value.clientMessageId, "msg_phase3b_001");
});

test("phase 3b community messages accept clientMessageId and preserve it", () => {
  const result = validateCommunityChatMessageBody({
    body: "Community Phase 3B",
    clientMessageId: "community_phase3b_001",
  });

  assert.equal(result.ok, true);
  assert.equal(result.value.body, "Community Phase 3B");
  assert.equal(result.value.clientMessageId, "community_phase3b_001");
});

test("phase 3b rejects overlong clientMessageId values", () => {
  const overlong = "x".repeat(121);
  const threadResult = validateSendMessage({
    body: "Phase 3B hello",
    clientMessageId: overlong,
  });
  const communityResult = validateCommunityChatMessageBody({
    body: "Community Phase 3B",
    clientMessageId: overlong,
  });

  assert.equal(threadResult.ok, false);
  assert.ok(threadResult.errors.includes("clientMessageId"));
  assert.equal(communityResult.ok, false);
  assert.ok(communityResult.errors.includes("clientMessageId"));
});

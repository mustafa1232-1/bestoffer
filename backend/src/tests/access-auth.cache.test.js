import test from "node:test";
import assert from "node:assert/strict";

import {
  __sessionAccessCacheTestApi,
  invalidateSessionAccessCacheForSession,
  invalidateSessionAccessCacheForUser,
} from "../shared/middleware/access-auth.js";

test("invalidateSessionAccessCacheForSession evicts matching cached session only", () => {
  __sessionAccessCacheTestApi.clear();
  __sessionAccessCacheTestApi.write("11:7:jti-a:fp-a", { id: 11, user_id: 7 });
  __sessionAccessCacheTestApi.write("12:7:jti-b:fp-b", { id: 12, user_id: 7 });
  __sessionAccessCacheTestApi.write("13:9:jti-c:fp-c", { id: 13, user_id: 9 });

  const removed = invalidateSessionAccessCacheForSession({
    sessionId: 11,
    userId: 7,
  });

  assert.equal(removed, 1);
  assert.equal(__sessionAccessCacheTestApi.read("11:7:jti-a:fp-a"), null);
  assert.ok(__sessionAccessCacheTestApi.read("12:7:jti-b:fp-b"));
  assert.ok(__sessionAccessCacheTestApi.read("13:9:jti-c:fp-c"));
  __sessionAccessCacheTestApi.clear();
});

test("invalidateSessionAccessCacheForUser evicts all user sessions except the allowed one", () => {
  __sessionAccessCacheTestApi.clear();
  __sessionAccessCacheTestApi.write("21:15:jti-a:fp-a", { id: 21, user_id: 15 });
  __sessionAccessCacheTestApi.write("22:15:jti-b:fp-b", { id: 22, user_id: 15 });
  __sessionAccessCacheTestApi.write("23:16:jti-c:fp-c", { id: 23, user_id: 16 });

  const removed = invalidateSessionAccessCacheForUser({
    userId: 15,
    exceptSessionId: 22,
  });

  assert.equal(removed, 1);
  assert.equal(__sessionAccessCacheTestApi.read("21:15:jti-a:fp-a"), null);
  assert.ok(__sessionAccessCacheTestApi.read("22:15:jti-b:fp-b"));
  assert.ok(__sessionAccessCacheTestApi.read("23:16:jti-c:fp-c"));
  __sessionAccessCacheTestApi.clear();
});

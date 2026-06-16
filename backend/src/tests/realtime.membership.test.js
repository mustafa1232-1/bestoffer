import assert from "node:assert/strict";
import test from "node:test";

import {
  __realtimeMembershipTestApi,
  allowUsersOnChannel,
} from "../shared/realtime/realtime-membership.js";

test.afterEach(() => {
  __realtimeMembershipTestApi.reset();
});

test("allowUsersOnChannel deduplicates ids and remains idempotent", async () => {
  const store = new Map();

  const fakeClient = {
    from() {
      return {
        async upsert(rows) {
          for (const row of rows) {
            store.set(`${row.channel}:${row.user_id}`, row);
          }
          return { error: null };
        },
      };
    },
  };

  __realtimeMembershipTestApi.setStatusResolver(() => ({ canUseSupabase: true }));
  __realtimeMembershipTestApi.setAdminClientFactory(() => fakeClient);

  const first = await allowUsersOnChannel([5, "5", 7, 0, null], "chat:thread:11");
  const second = await allowUsersOnChannel([5, 7], "chat:thread:11");

  assert.equal(first.ok, true);
  assert.equal(first.count, 2);
  assert.equal(second.ok, true);
  assert.equal(store.size, 2);
});

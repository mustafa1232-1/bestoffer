import assert from "node:assert/strict";
import test from "node:test";
import pg from "pg";

import {
  assertStoryAudienceScopeAllowed,
  createStory,
} from "../modules/feed/feed.service.js";

// §1/§2: authoritative fail-closed backend gate. Even if the client (old,
// modified, or a direct API caller) requests a scoped story and input
// validation succeeds, the service must reject it before any DB side-effect
// while STORY_AUDIENCE_SCOPE_ENABLED is false.

test("global story requests are allowed by the gate", () => {
  assert.doesNotThrow(() => assertStoryAudienceScopeAllowed({}));
  assert.doesNotThrow(() =>
    assertStoryAudienceScopeAllowed({ audienceScopeType: "global" })
  );
  assert.doesNotThrow(() =>
    assertStoryAudienceScopeAllowed({ audienceScopeType: "GLOBAL", audienceScopeCode: "" })
  );
});

test("every non-global request is rejected with the right code/status", () => {
  const cases = [
    { audienceScopeType: "building", audienceScopeCode: "A101" },
    { audienceScopeType: "block", audienceScopeCode: "A" },
    { audienceScopeType: "compound", audienceScopeCode: "A1" },
    { scopeType: "building", scopeCode: "A101" }, // raw key aliases
    { audience_scope_type: "building", audience_scope_code: "A101" }, // snake_case
    { audienceScopeCode: "A101" }, // code without type
    { isOfficial: true },
    { isOfficial: "true" },
    { is_official: true },
    { isOfficialRequested: true },
    { audienceScopeType: "BUILDING", audienceScopeCode: "a101" }, // casing
  ];
  for (const dto of cases) {
    let threw = null;
    try {
      assertStoryAudienceScopeAllowed(dto);
    } catch (e) {
      threw = e;
    }
    assert.ok(threw, `expected rejection for ${JSON.stringify(dto)}`);
    assert.equal(threw.code, "STORY_AUDIENCE_SCOPE_NOT_AVAILABLE");
    assert.equal(threw.status, 409);
    assert.ok(threw.details?.messages?.ar);
    assert.ok(threw.details?.messages?.en);
  }
});

test("DB: a rejected scoped story creates NO social_story row (fail-closed)", async () => {
  const client = new pg.Client({ connectionString: process.env.DATABASE_URL });
  await client.connect();
  try {
    const count = async () =>
      Number((await client.query("SELECT COUNT(*)::int n FROM social_story")).rows[0].n);
    const before = await count();

    // Attempt a building-scoped story through the real service. Whether the
    // gate or the write-permission check fires first, NO story row must be
    // created — the request never reaches an insert.
    await assert.rejects(
      createStory(
        9,
        { caption: "scoped attempt", audienceScopeType: "building", audienceScopeCode: "A101" },
        null
      )
    );
    const after = await count();
    assert.equal(after, before, "no social_story row may be created for a rejected scoped request");

    // Retrying must also not create a global story.
    await assert.rejects(
      createStory(
        9,
        { caption: "scoped retry", audienceScopeType: "block", audienceScopeCode: "A" },
        null
      )
    );
    assert.equal(await count(), before, "retry must not create a story either");
  } finally {
    await client.end();
  }
});

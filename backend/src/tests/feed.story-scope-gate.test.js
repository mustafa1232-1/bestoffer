import assert from "node:assert/strict";
import test from "node:test";
import { randomUUID } from "node:crypto";
import pg from "pg";

import {
  assertStoryAudienceScopeAllowed,
  createStory,
} from "../modules/feed/feed.service.js";
import { getStoryAudienceScopeFeatureState } from "../modules/feed/feed.capabilities.js";
import * as controller from "../modules/feed/feed.controller.js";

const SCOPED = { audienceScopeType: "building", audienceScopeCode: "A101" };

// State helpers for injection.
const disabled = getStoryAudienceScopeFeatureState({ storyAudienceScopeEnabled: false });
const envForcedTrue = getStoryAudienceScopeFeatureState({ storyAudienceScopeEnabled: true }); // implementationReady const=false → effective false
const fullyEnabled = getStoryAudienceScopeFeatureState({ storyAudienceScopeEnabled: true }, true); // both true → effective true

test("global requests allowed in every state", () => {
  for (const st of [disabled, envForcedTrue, fullyEnabled]) {
    assert.doesNotThrow(() => assertStoryAudienceScopeAllowed({}, st));
    assert.doesNotThrow(() => assertStoryAudienceScopeAllowed({ audienceScopeType: "global" }, st));
  }
});

test("§3: env requested=true but implementationReady=false STILL rejects scoped", () => {
  assert.equal(envForcedTrue.requestedEnabled, true);
  assert.equal(envForcedTrue.implementationReady, false);
  assert.equal(envForcedTrue.effectiveEnabled, false);
  assert.throws(
    () => assertStoryAudienceScopeAllowed(SCOPED, envForcedTrue),
    (e) => e.code === "STORY_AUDIENCE_SCOPE_NOT_AVAILABLE" && e.status === 409
  );
  // Official also rejected under a forced env flag.
  assert.throws(() => assertStoryAudienceScopeAllowed({ isOfficial: true }, envForcedTrue));
});

test("effective enabled (both true) allows scoped — proves the AND, not OR", () => {
  assert.equal(fullyEnabled.effectiveEnabled, true);
  assert.doesNotThrow(() => assertStoryAudienceScopeAllowed(SCOPED, fullyEnabled));
});

test("hardened boolean parsing rejects all truthy official representations", () => {
  for (const v of [true, "true", "TRUE", 1, "1", "yes", "on"]) {
    assert.throws(
      () => assertStoryAudienceScopeAllowed({ isOfficial: v }, disabled),
      (e) => e.code === "STORY_AUDIENCE_SCOPE_NOT_AVAILABLE",
      `official=${JSON.stringify(v)} should reject`
    );
  }
});

test("§4 DB: rejected scoped story creates NO row with the unique marker", async () => {
  const client = new pg.Client({ connectionString: process.env.DATABASE_URL });
  await client.connect();
  const marker = `gate-${randomUUID()}`;
  try {
    // Gate fires FIRST in createStory, so any user id triggers it deterministically.
    let err = null;
    try {
      await createStory(9, { caption: marker, ...SCOPED }, null);
    } catch (e) {
      err = e;
    }
    assert.ok(err, "scoped story must be rejected");
    assert.equal(err.code, "STORY_AUDIENCE_SCOPE_NOT_AVAILABLE");
    assert.equal(err.status, 409);

    // Targeted query (not a whole-table COUNT) — parallel tests can't interfere.
    const row = await client.query("SELECT id FROM social_story WHERE caption = $1", [marker]);
    assert.equal(row.rowCount, 0, "no social_story row may exist for a rejected scoped request");

    // Retry with a different scope also creates nothing.
    const marker2 = `gate-${randomUUID()}`;
    await assert.rejects(
      createStory(9, { caption: marker2, audienceScopeType: "block", audienceScopeCode: "A" }, null),
      (e) => e.code === "STORY_AUDIENCE_SCOPE_NOT_AVAILABLE"
    );
    const row2 = await client.query("SELECT id FROM social_story WHERE caption = $1", [marker2]);
    assert.equal(row2.rowCount, 0);
  } finally {
    await client.end();
  }
});

test("§5 controller: POST-equivalent scoped request → next(AppError 409)", async () => {
  const req = {
    body: { caption: `ctrl-${randomUUID()}`, audienceScopeType: "building", audienceScopeCode: "A101" },
    file: null,
    userId: 9,
  };
  const res = { status() { return this; }, json() { return this; } };
  let captured = null;
  await controller.createStory(req, res, (e) => { captured = e; });
  assert.ok(captured, "controller must forward the error to next()");
  assert.equal(captured.code, "STORY_AUDIENCE_SCOPE_NOT_AVAILABLE");
  assert.equal(captured.status, 409);
  assert.ok(captured.details?.messages?.ar && captured.details?.messages?.en);
});

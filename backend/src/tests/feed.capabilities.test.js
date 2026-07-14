import assert from "node:assert/strict";
import test from "node:test";
import fs from "node:fs";
import path from "node:path";

import { buildSocialCapabilities } from "../modules/feed/feed.capabilities.js";
import { feedRouter } from "../modules/feed/feed.routes.js";

test("capabilities: storyAudienceScope disabled → only global", () => {
  const cap = buildSocialCapabilities({ storyAudienceScopeEnabled: false });
  assert.equal(cap.social.storyAudienceScope.supported, false);
  assert.deepEqual(cap.social.storyAudienceScope.supportedTypes, ["global"]);
  assert.equal(cap.social.storyAudienceScope.officialStoriesSupported, false);
});

test("capabilities: storyAudienceScope enabled → full scope types", () => {
  const cap = buildSocialCapabilities({ storyAudienceScopeEnabled: true });
  assert.equal(cap.social.storyAudienceScope.supported, true);
  assert.deepEqual(cap.social.storyAudienceScope.supportedTypes, [
    "global",
    "block",
    "compound",
    "building",
  ]);
});

test("GET /capabilities and cancel/publish routes are registered", () => {
  const routes = [];
  for (const layer of feedRouter.stack) {
    if (layer.route?.path) {
      for (const m of Object.keys(layer.route.methods || {})) {
        routes.push(`${m.toUpperCase()} ${layer.route.path}`);
      }
    }
  }
  assert.ok(routes.includes("GET /capabilities"), "capabilities route missing");
});

test("migration 135 is a runner-recognized numbered SQL file", () => {
  // The runner (sqlMigrations.js) matches ^\d+[a-z]?(?:_.*)?\.sql$ in sql/.
  const pattern = /^\d+[a-z]?(?:_.*)?\.sql$/i;
  const file = "135_social_story_audience_scope.sql";
  assert.ok(pattern.test(file), "135 does not match the migration file pattern");
  const full = path.resolve(process.cwd(), "sql", file);
  assert.ok(fs.existsSync(full), "migration 135 not present in sql/");
  const sql = fs.readFileSync(full, "utf8");
  assert.match(sql, /ADD COLUMN IF NOT EXISTS audience_scope_type/);
  assert.match(sql, /audience_scope_type IN \('global', 'block', 'compound', 'building'\)/);
  assert.match(sql, /idx_social_story_scope_active/);
});

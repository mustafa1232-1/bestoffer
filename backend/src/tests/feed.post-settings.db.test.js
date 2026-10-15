import assert from "node:assert/strict";
import test, { after } from "node:test";
import { randomUUID } from "node:crypto";
import { q, pool } from "../config/db.js";
import { validateCreatePost } from "../modules/feed/feed.validators.js";
import { createPost, addComment, resolveSharedEntityForSender, createStory } from "../modules/feed/feed.service.js";
import { listVisiblePostCandidates } from "../modules/feed/feed.discovery.repo.js";
import { assertSafeE2EDatabaseTarget } from "../scripts/e2eDbSafety.js";

after(() => pool.end());

test("persisted settings block comments, reposts and story attachments without losing discovery metadata", async () => {
  assertSafeE2EDatabaseTarget({ scriptName: "feed.post-settings.db.test",
    databaseUrl: process.env.DATABASE_URL, allowProductionOverride: false, isProduction: false });
  const tag = randomUUID().replaceAll("-", "").slice(0, 8);
  const { rows } = await q(`INSERT INTO app_user
    (full_name, phone, username, pin_hash, role, block, building_number, apartment, social_posts_public)
    VALUES ($1, $2, $3, 'test', 'user', 'A', 'A203', '1', TRUE) RETURNING id`,
    [`Post settings ${tag}`, `077settings${tag}`, `settings_${tag}`]);
  const userId = Number(rows[0].id);
  const validation = validateCreatePost({ caption: "Settings regression", commentsEnabled: false,
    sharingEnabled: false, storyStyle: { layers: [{ type: "text", text: "Visible overlay", x: 0.5, y: 0.5 }] } });
  assert.equal(validation.ok, true);
  const post = await createPost(userId, validation.value, null);
  await assert.rejects(addComment({ postId: post.id, userId, body: "Not permitted" }),
    { code: "POST_COMMENTS_DISABLED" });
  await assert.rejects(resolveSharedEntityForSender({ senderUserId: userId,
    sharedEntity: { type: "post", id: post.id } }), { code: "POST_SHARING_DISABLED" });
  for (const storyStyle of [
    { sharedPostId: post.id },
    { attachment: { type: "post_share", postId: post.id } },
    { attachment: { type: "reel_share", reelId: post.id } },
  ]) {
    await assert.rejects(createStory(userId, { caption: "Blocked share", storyStyle }, null),
      { code: "POST_SHARING_DISABLED" });
  }
  const candidates = await listVisiblePostCandidates({ viewerUserId: userId });
  const found = candidates.find((candidate) => Number(candidate.id) === post.id);
  assert.ok(found);
  assert.equal(found.story_style.postSettings.sharingEnabled, false);
  assert.equal(found.story_style.layers[0].text, "Visible overlay");
  const legacy = await createPost(userId, validateCreatePost({ caption: "Legacy settings" }).value, null);
  assert.ok(await addComment({ postId: legacy.id, userId, body: "Still allowed" }));
  assert.ok(await resolveSharedEntityForSender({ senderUserId: userId,
    sharedEntity: { type: "post", id: legacy.id } }));
});

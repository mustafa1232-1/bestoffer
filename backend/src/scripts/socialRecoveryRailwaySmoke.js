/* eslint-disable no-console */
import assert from "node:assert/strict";

import { pool, q } from "../config/db.js";
import {
  assertStatus,
  buildPhone,
  buildRunTag,
  createActor,
  readId,
  request,
} from "./e2eTestUtils.js";
import {
  buildMultipartForm,
  cleanupSocialArtifacts,
  DEFAULT_BASE_URL,
  registerActor,
  requestMultipartForm,
} from "./socialE2EHelpers.js";

const STORY_SETTING_KEYS = [
  "allowLikes",
  "allowPrivateReplies",
  "allowComments",
  "allowSharing",
  "allowReshare",
];

const DEFAULT_STORY_SETTINGS = Object.freeze({
  allowLikes: true,
  allowPrivateReplies: true,
  allowComments: true,
  allowSharing: true,
  allowReshare: true,
});

const DISABLED_STORY_SETTINGS = Object.freeze({
  allowLikes: false,
  allowPrivateReplies: false,
  allowComments: false,
  allowSharing: false,
  allowReshare: false,
});

function resolveBaseUrl() {
  const raw = String(
    process.env.SOCIAL_RECOVERY_BASE_URL ||
      process.env.BASE_URL ||
      DEFAULT_BASE_URL
  )
    .trim()
    .replace(/\/+$/, "");
  const parsed = new URL(raw);
  assert.equal(parsed.protocol, "https:", "Railway smoke BASE_URL must use HTTPS");
  assert.equal(
    ["localhost", "127.0.0.1", "::1"].includes(parsed.hostname.toLowerCase()),
    false,
    "Railway smoke BASE_URL must be remote"
  );
  return parsed.toString().replace(/\/$/, "");
}

function expectedGitSha() {
  const value = String(
    process.env.SOCIAL_RECOVERY_EXPECTED_SHA || process.env.GIT_COMMIT_SHA || ""
  )
    .trim()
    .toLowerCase();
  assert.match(
    value,
    /^[0-9a-f]{40}$/,
    "SOCIAL_RECOVERY_EXPECTED_SHA or GIT_COMMIT_SHA must be the full deployed commit SHA"
  );
  return value;
}

function readStorySettings(story) {
  return Object.fromEntries(
    STORY_SETTING_KEYS.map((key) => [key, story?.[key] === true])
  );
}

function assertStorySettings(story, expected, label) {
  assert.deepEqual(readStorySettings(story), expected, `${label} top-level settings`);
  assert.deepEqual(
    readStorySettings(story?.storyInteractionSettings),
    expected,
    `${label} nested settings`
  );
}

function assertApplicationError(response, status, message, label) {
  assertStatus(response, status, label);
  assert.equal(
    String(response.data?.message || ""),
    message,
    `${label} error message`
  );
}

function findStoryInViewerList(data, storyId) {
  const groups = Array.isArray(data?.stories) ? data.stories : [];
  return groups
    .flatMap((group) => (Array.isArray(group?.stories) ? group.stories : []))
    .find((story) => Number(story?.id || 0) === Number(storyId));
}

function buildNativeCardSnapshot(type, item) {
  const author = {
    id: Number(item?.author?.id || item?.userId || 0),
    fullName: String(item?.author?.fullName || ""),
    username: item?.author?.username || null,
    imageUrl: item?.author?.imageUrl || null,
  };
  return Object.fromEntries(
    Object.entries({
      id: Number(item?.id || 0),
      type,
      title: author.fullName,
      caption: String(item?.caption || ""),
      postKind: item?.postKind || type,
      mediaKind: item?.mediaKind || null,
      mediaUrl: item?.mediaUrl || null,
      posterUrl: item?.asset?.posterUrl || item?.asset?.thumbnailUrl || null,
      playbackUrl: item?.asset?.playbackUrl || item?.mediaUrl || null,
      createdAt: item?.createdAt || null,
      author,
      authorName: author.fullName,
      authorUsername: author.username,
      authorImageUrl: author.imageUrl,
    }).filter(([, value]) => value !== null && value !== undefined)
  );
}

async function countRows(sql, params = []) {
  const result = await q(sql, params);
  return Number(result.rows[0]?.count || 0);
}

async function assertRemoteAndDatabasePreflight(baseUrl, probeActor) {
  assert.ok(String(process.env.DATABASE_URL || "").trim(), "DATABASE_URL is required");

  const health = await request(baseUrl, probeActor, "GET", "/health");
  assertStatus(health, 200, "remote health preflight");
  const ready = await request(baseUrl, probeActor, "GET", "/ready");
  assertStatus(ready, 200, "remote readiness preflight");

  const version = await request(baseUrl, probeActor, "GET", "/version");
  assertStatus(version, 200, "remote version preflight");
  assert.equal(
    String(version.data?.gitCommitSha || "").trim().toLowerCase(),
    expectedGitSha(),
    "remote /version commit must exactly match the expected deployed commit"
  );

  const migrations = await q(
    `SELECT name
     FROM schema_migration
     WHERE name = ANY($1::text[])`,
    [[
      "136_social_story_interaction_settings.sql",
      "140_social_story_interaction_settings.sql",
    ]]
  );
  const migrationNames = new Set(migrations.rows.map((row) => String(row.name)));
  assert.equal(
    migrationNames.has("136_social_story_interaction_settings.sql"),
    true,
    "original production migration ledger row 136 must be retained"
  );
  assert.equal(
    migrationNames.has("140_social_story_interaction_settings.sql"),
    true,
    "reconciliation migration 140 must be applied"
  );

  const columns = await q(
    `SELECT column_name, is_nullable, column_default
     FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name = 'social_story'
       AND column_name = ANY($1::text[])`,
    [[
      "allow_likes",
      "allow_private_replies",
      "allow_comments",
      "allow_sharing",
      "allow_reshare",
    ]]
  );
  assert.equal(columns.rowCount, 5, "all five Story interaction columns must exist");
  for (const column of columns.rows) {
    assert.equal(column.is_nullable, "NO", `${column.column_name} must be NOT NULL`);
    assert.match(
      String(column.column_default || "").toLowerCase(),
      /true/,
      `${column.column_name} must default to true`
    );
  }

  const chatConstraint = await q(
    `SELECT pg_get_constraintdef(c.oid) AS definition
     FROM pg_constraint c
     WHERE c.conname = 'social_chat_message_shared_entity_type_chk'
       AND c.conrelid = 'social_chat_message'::regclass
     LIMIT 1`
  );
  assert.equal(chatConstraint.rowCount, 1, "chat shared-entity constraint must exist");
  assert.match(
    String(chatConstraint.rows[0]?.definition || "").toLowerCase(),
    /'story'/,
    "chat shared-entity constraint must allow native Story cards"
  );

  console.log("[social-recovery-smoke] PASS remote/DB preflight");
}

async function registerFixtureActor(baseUrl, actor, payload, artifacts, label) {
  await registerActor(baseUrl, actor, payload, `${label} register`);
  assert.ok(actor.token, `${label} registration token missing`);
  assert.ok(Number(actor.userId) > 0, `${label} registration user id missing`);
  artifacts.userIds.push(Number(actor.userId));
  if (actor.sessionId) artifacts.sessionIds.push(Number(actor.sessionId));

  const persisted = await q(
    `SELECT id, full_name, phone
     FROM app_user
     WHERE id = $1
     LIMIT 1`,
    [Number(actor.userId)]
  );
  assert.equal(persisted.rowCount, 1, `${label} user must persist in Railway DB`);
  assert.equal(persisted.rows[0].full_name, payload.fullName, `${label} full name`);
  assert.equal(persisted.rows[0].phone, payload.phone, `${label} phone`);
  assert.equal(
    await countRows(`SELECT COUNT(*)::int AS count FROM user_session WHERE user_id = $1`, [
      Number(actor.userId),
    ]),
    1,
    `${label} authenticated session must persist`
  );
}

async function updateAndVerifyPublicProfile(baseUrl, actor, runTag) {
  const bio = `Social recovery profile ${runTag}`;
  const response = await request(baseUrl, actor, "PATCH", "/api/feed/profile/me", {
    bio,
    accountPrivate: false,
    postsPublic: true,
    storiesPublic: true,
    relationsPublic: true,
  });
  assertStatus(response, 200, "owner public profile update");

  const persisted = await q(
    `SELECT
       bio,
       social_account_private,
       social_posts_public,
       social_stories_public,
       social_relations_public
     FROM app_user
     WHERE id = $1`,
    [Number(actor.userId)]
  );
  assert.equal(persisted.rows[0]?.bio, bio, "profile bio must persist");
  assert.equal(persisted.rows[0]?.social_account_private, false);
  assert.equal(persisted.rows[0]?.social_posts_public, true);
  assert.equal(persisted.rows[0]?.social_stories_public, true);
  assert.equal(persisted.rows[0]?.social_relations_public, true);
  console.log("[social-recovery-smoke] PASS authenticated profile mutation");
}

async function connectActorsAndCreateDm(baseUrl, owner, peer, artifacts) {
  const relationRequest = await request(
    baseUrl,
    owner,
    "POST",
    `/api/feed/users/${peer.userId}/relation/request`
  );
  assertStatus(relationRequest, 201, "owner relation request");

  const pair = [Number(owner.userId), Number(peer.userId)].sort((a, b) => a - b);
  let relation = await q(
    `SELECT status, initiator_user_id
     FROM social_user_relation
     WHERE user_a_id = $1 AND user_b_id = $2`,
    pair
  );
  assert.equal(relation.rows[0]?.status, "pending", "relation request must persist");
  assert.equal(Number(relation.rows[0]?.initiator_user_id), Number(owner.userId));

  const relationAccept = await request(
    baseUrl,
    peer,
    "POST",
    `/api/feed/users/${owner.userId}/relation/accept`
  );
  assertStatus(relationAccept, 200, "peer relation acceptance");
  relation = await q(
    `SELECT status
     FROM social_user_relation
     WHERE user_a_id = $1 AND user_b_id = $2`,
    pair
  );
  assert.equal(relation.rows[0]?.status, "accepted", "accepted relation must persist");

  const threadResponse = await request(
    baseUrl,
    owner,
    "POST",
    "/api/feed/chats/threads",
    { kind: "private", userId: Number(peer.userId) }
  );
  assertStatus(threadResponse, 201, "native DM thread create/get");
  const threadId = readId(threadResponse.data?.thread);
  assert.ok(threadId, "native DM thread id missing");
  artifacts.threadIds.push(threadId);

  const persistedThread = await q(
    `SELECT id, thread_kind, user_a_id, user_b_id
     FROM social_chat_thread
     WHERE id = $1`,
    [threadId]
  );
  assert.equal(persistedThread.rowCount, 1, "native DM thread must persist");
  assert.equal(persistedThread.rows[0].thread_kind, "private");
  assert.deepEqual(
    [
      Number(persistedThread.rows[0].user_a_id),
      Number(persistedThread.rows[0].user_b_id),
    ],
    pair
  );
  console.log("[social-recovery-smoke] PASS authenticated relation/native DM setup");
  return threadId;
}

async function createAndVerifyStory({
  baseUrl,
  owner,
  caption,
  settings,
  artifacts,
  label,
  useNestedSettings = false,
}) {
  const body = { caption };
  if (useNestedSettings) body.storyInteractionSettings = settings;
  const response = await request(baseUrl, owner, "POST", "/api/feed/stories", body);
  assertStatus(response, 201, label);
  const story = response.data?.story;
  const storyId = readId(story);
  assert.ok(storyId, `${label} story id missing`);
  artifacts.storyIds.push(storyId);
  assertStorySettings(story, settings, label);

  const persisted = await q(
    `SELECT
       user_id,
       caption,
       allow_likes,
       allow_private_replies,
       allow_comments,
       allow_sharing,
       allow_reshare
     FROM social_story
     WHERE id = $1`,
    [storyId]
  );
  assert.equal(persisted.rowCount, 1, `${label} DB row missing`);
  assert.equal(Number(persisted.rows[0].user_id), Number(owner.userId));
  assert.equal(persisted.rows[0].caption, caption);
  assert.deepEqual(
    {
      allowLikes: persisted.rows[0].allow_likes,
      allowPrivateReplies: persisted.rows[0].allow_private_replies,
      allowComments: persisted.rows[0].allow_comments,
      allowSharing: persisted.rows[0].allow_sharing,
      allowReshare: persisted.rows[0].allow_reshare,
    },
    settings,
    `${label} persisted settings`
  );
  return story;
}

async function assertDisabledStoryMutations({
  baseUrl,
  peer,
  threadId,
  storyId,
  runTag,
}) {
  const like = await request(
    baseUrl,
    peer,
    "POST",
    `/api/feed/stories/${storyId}/like`,
    {}
  );
  assertApplicationError(like, 403, "STORY_LIKES_DISABLED", "disabled Story like");
  assert.equal(
    await countRows(
      `SELECT COUNT(*)::int AS count
       FROM social_story_like
       WHERE story_id = $1 AND user_id = $2`,
      [storyId, Number(peer.userId)]
    ),
    0,
    "disabled Story like must not persist"
  );

  const rejectedCommentBody = `Rejected Story comment ${runTag}`;
  const comment = await request(
    baseUrl,
    peer,
    "POST",
    `/api/feed/stories/${storyId}/comments`,
    { body: rejectedCommentBody }
  );
  assertApplicationError(
    comment,
    403,
    "STORY_COMMENTS_DISABLED",
    "disabled Story comment"
  );
  assert.equal(
    await countRows(
      `SELECT COUNT(*)::int AS count
       FROM social_story_comment
       WHERE story_id = $1 AND body = $2`,
      [storyId, rejectedCommentBody]
    ),
    0,
    "disabled Story comment must not persist"
  );

  const share = await request(
    baseUrl,
    peer,
    "POST",
    `/api/feed/chats/threads/${threadId}/messages`,
    {
      body: "",
      clientMessageId: `${runTag}-disabled-story-share`,
      sharedEntity: {
        type: "story",
        id: storyId,
        snapshot: { forged: true, caption: `Forged ${runTag}` },
      },
    }
  );
  assertApplicationError(
    share,
    403,
    "STORY_SHARING_DISABLED",
    "disabled native Story share"
  );
  assert.equal(
    await countRows(
      `SELECT COUNT(*)::int AS count
       FROM social_chat_message
       WHERE thread_id = $1
         AND shared_entity_type = 'story'
         AND shared_entity_id = $2`,
      [threadId, storyId]
    ),
    0,
    "disabled native Story share must not persist"
  );

  console.log(
    "[social-recovery-smoke] CONTRACT privateReplyMutation=unsupported storyReshareMutation=unsupported nativeShareMutation=supported"
  );
  console.log("[social-recovery-smoke] PASS disabled Story operation enforcement");
}

async function findStoryNotification({ userId, type, storyId, actorUserId }) {
  const result = await q(
    `SELECT id, type, payload
     FROM app_notification
     WHERE user_id = $1
       AND type = $2
       AND payload ->> 'storyId' = $3
       AND payload ->> 'actorUserId' = $4
     ORDER BY id DESC
     LIMIT 1`,
    [
      Number(userId),
      type,
      String(storyId),
      String(actorUserId),
    ]
  );
  return result.rows[0] || null;
}

async function exerciseEnabledStory({
  baseUrl,
  owner,
  peer,
  story,
  threadId,
  runTag,
  artifacts,
}) {
  const storyId = Number(story.id);
  const like = await request(
    baseUrl,
    peer,
    "POST",
    `/api/feed/stories/${storyId}/like`,
    {}
  );
  assertStatus(like, 200, "enabled Story like");
  assert.equal(like.data?.liked, true);
  assert.equal(Number(like.data?.likesCount || 0), 1);
  assert.equal(
    await countRows(
      `SELECT COUNT(*)::int AS count
       FROM social_story_like
       WHERE story_id = $1 AND user_id = $2`,
      [storyId, Number(peer.userId)]
    ),
    1,
    "enabled Story like must persist"
  );

  const commentBody = `Enabled Story comment ${runTag}`;
  const comment = await request(
    baseUrl,
    peer,
    "POST",
    `/api/feed/stories/${storyId}/comments`,
    { body: commentBody }
  );
  assertStatus(comment, 201, "enabled Story comment");
  assert.equal(Number(comment.data?.commentsCount || 0), 1);
  const commentId = readId(comment.data?.comment);
  assert.ok(commentId, "enabled Story comment id missing");
  const persistedComment = await q(
    `SELECT story_id, user_id, body
     FROM social_story_comment
     WHERE id = $1`,
    [commentId]
  );
  assert.equal(persistedComment.rowCount, 1, "enabled Story comment must persist");
  assert.equal(Number(persistedComment.rows[0].story_id), storyId);
  assert.equal(Number(persistedComment.rows[0].user_id), Number(peer.userId));
  assert.equal(persistedComment.rows[0].body, commentBody);

  const likeNotification = await findStoryNotification({
    userId: owner.userId,
    type: "social.story.like",
    storyId,
    actorUserId: peer.userId,
  });
  assert.ok(likeNotification, "Story like notification must persist");
  assert.equal(likeNotification.payload?.target, "social_story");
  const commentNotification = await findStoryNotification({
    userId: owner.userId,
    type: "social.story.comment",
    storyId,
    actorUserId: peer.userId,
  });
  assert.ok(commentNotification, "Story comment notification must persist");
  assert.equal(commentNotification.payload?.target, "social_story");

  const exact = await request(
    baseUrl,
    peer,
    "GET",
    `/api/feed/stories/${storyId}`
  );
  assertStatus(exact, 200, "exact Story viewer read");
  assert.equal(Number(exact.data?.story?.id || 0), storyId);
  assert.equal(exact.data?.story?.caption, story.caption);
  assert.equal(Number(exact.data?.story?.likesCount || 0), 1);
  assert.equal(Number(exact.data?.story?.commentsCount || 0), 1);
  assert.equal(exact.data?.story?.isLiked, true);
  assertStorySettings(exact.data?.story, DEFAULT_STORY_SETTINGS, "exact Story read");

  const list = await request(
    baseUrl,
    peer,
    "GET",
    "/api/feed/stories?limitUsers=40&maxPerUser=20"
  );
  assertStatus(list, 200, "Story list viewer read");
  const listed = findStoryInViewerList(list.data, storyId);
  assert.ok(listed, "enabled Story must be present in viewer list");
  assert.equal(Number(listed.likesCount || 0), 1);
  assert.equal(Number(listed.commentsCount || 0), 1);
  assert.equal(listed.isLiked, true);
  assertStorySettings(listed, DEFAULT_STORY_SETTINGS, "Story list read");

  const forgedSnapshot = {
    title: `Forged ${runTag}`,
    caption: `Forged caption ${runTag}`,
    mediaUrl: "https://attacker.invalid/forged.jpg",
    authorName: "Forged author",
    forged: true,
  };
  const share = await request(
    baseUrl,
    owner,
    "POST",
    `/api/feed/chats/threads/${threadId}/messages`,
    {
      body: "",
      clientMessageId: `${runTag}-story-share`,
      sharedEntity: { type: "story", id: storyId, snapshot: forgedSnapshot },
    }
  );
  assertStatus(share, 201, "enabled native Story DM card");
  const messageId = readId(share.data?.message);
  assert.ok(messageId, "native Story DM message id missing");
  artifacts.messageIds.push(messageId);
  const shared = share.data?.message?.sharedEntity;
  assert.equal(shared?.type, "story");
  assert.equal(Number(shared?.id || 0), storyId);
  assert.equal(shared?.snapshot?.id, storyId);
  assert.equal(shared?.snapshot?.type, "story");
  assert.equal(shared?.snapshot?.caption, story.caption);
  assert.equal(Number(shared?.snapshot?.author?.id || 0), Number(owner.userId));
  assert.equal("forged" in (shared?.snapshot || {}), false);
  assert.notEqual(shared?.snapshot?.title, forgedSnapshot.title);
  assert.notEqual(shared?.snapshot?.mediaUrl, forgedSnapshot.mediaUrl);

  const persistedMessage = await q(
    `SELECT
       sender_user_id,
       shared_entity_type,
       shared_entity_id,
       shared_snapshot_json
     FROM social_chat_message
     WHERE id = $1`,
    [messageId]
  );
  assert.equal(persistedMessage.rowCount, 1, "native Story DM card must persist");
  assert.equal(Number(persistedMessage.rows[0].sender_user_id), Number(owner.userId));
  assert.equal(persistedMessage.rows[0].shared_entity_type, "story");
  assert.equal(Number(persistedMessage.rows[0].shared_entity_id), storyId);
  assert.deepEqual(persistedMessage.rows[0].shared_snapshot_json, shared.snapshot);

  const chatNotification = await q(
    `SELECT payload
     FROM app_notification
     WHERE user_id = $1
       AND type = 'social.chat.message'
       AND payload ->> 'threadId' = $2
       AND payload ->> 'senderUserId' = $3
     ORDER BY id DESC
     LIMIT 1`,
    [Number(peer.userId), String(threadId), String(owner.userId)]
  );
  assert.equal(chatNotification.rowCount, 1, "native Story DM notification must persist");
  assert.equal(chatNotification.rows[0].payload?.target, "social_chat");

  console.log(
    "[social-recovery-smoke] PASS enabled Story like/comment/share, exact/list reads, notification targets"
  );
}

async function sendAndVerifyNativeCard({
  baseUrl,
  sender,
  threadId,
  type,
  item,
  runTag,
  artifacts,
}) {
  const snapshot = buildNativeCardSnapshot(type, item);
  assert.ok(snapshot.id > 0, `${type} card snapshot id missing`);
  assert.ok(snapshot.author.id > 0, `${type} card author missing`);
  const response = await request(
    baseUrl,
    sender,
    "POST",
    `/api/feed/chats/threads/${threadId}/messages`,
    {
      body: "",
      clientMessageId: `${runTag}-${type}-share`,
      sharedEntity: { type, id: snapshot.id, snapshot },
    }
  );
  assertStatus(response, 201, `native ${type} DM card`);
  const messageId = readId(response.data?.message);
  assert.ok(messageId, `native ${type} DM message id missing`);
  artifacts.messageIds.push(messageId);
  assert.deepEqual(response.data?.message?.sharedEntity?.snapshot, snapshot);

  const persisted = await q(
    `SELECT shared_entity_type, shared_entity_id, shared_snapshot_json
     FROM social_chat_message
     WHERE id = $1`,
    [messageId]
  );
  assert.equal(persisted.rowCount, 1, `native ${type} DM row missing`);
  assert.equal(persisted.rows[0].shared_entity_type, type);
  assert.equal(Number(persisted.rows[0].shared_entity_id), snapshot.id);
  assert.deepEqual(persisted.rows[0].shared_snapshot_json, snapshot);
}

async function createPostAndReelCards({
  baseUrl,
  owner,
  peer,
  threadId,
  runTag,
  artifacts,
}) {
  const postCaption = `Social recovery Post ${runTag}`;
  const postResponse = await request(baseUrl, owner, "POST", "/api/feed/posts", {
    caption: postCaption,
    postKind: "text",
  });
  assertStatus(postResponse, 201, "Social recovery Post create");
  const post = postResponse.data?.post;
  const postId = readId(post);
  assert.ok(postId, "Social recovery Post id missing");
  artifacts.postIds.push(postId);
  const persistedPost = await q(
    `SELECT user_id, post_kind, caption, media_asset_id
     FROM social_post
     WHERE id = $1`,
    [postId]
  );
  assert.equal(persistedPost.rowCount, 1, "Post DB row missing");
  assert.equal(Number(persistedPost.rows[0].user_id), Number(owner.userId));
  assert.equal(persistedPost.rows[0].post_kind, "text");
  assert.equal(persistedPost.rows[0].caption, postCaption);

  await sendAndVerifyNativeCard({
    baseUrl,
    sender: owner,
    threadId,
    type: "post",
    item: post,
    runTag,
    artifacts,
  });

  const reelCaption = `Social recovery Reel ${runTag}`;
  const reelForm = buildMultipartForm({
    fields: { caption: reelCaption },
    fileFieldName: "mediaFile",
    fileName: `social-recovery-${runTag}.mp4`,
    mimeType: "video/mp4",
  });
  const reelResponse = await requestMultipartForm(
    baseUrl,
    owner,
    "POST",
    "/api/feed/reels",
    reelForm
  );
  assertStatus(reelResponse, 201, "Social recovery Reel create");
  const reel = reelResponse.data?.reel;
  const reelId = readId(reel);
  assert.ok(reelId, "Social recovery Reel id missing");
  artifacts.postIds.push(reelId);
  const persistedReel = await q(
    `SELECT user_id, post_kind, caption, media_asset_id
     FROM social_post
     WHERE id = $1`,
    [reelId]
  );
  assert.equal(persistedReel.rowCount, 1, "Reel DB row missing");
  assert.equal(Number(persistedReel.rows[0].user_id), Number(owner.userId));
  assert.equal(persistedReel.rows[0].post_kind, "reel");
  assert.equal(persistedReel.rows[0].caption, reelCaption);
  if (persistedReel.rows[0].media_asset_id != null) {
    artifacts.mediaAssetIds.push(Number(persistedReel.rows[0].media_asset_id));
  }

  const exactReel = await request(baseUrl, peer, "GET", `/api/feed/reels/${reelId}`);
  assertStatus(exactReel, 200, "exact Reel read");
  assert.equal(Number(exactReel.data?.reel?.id || 0), reelId);
  await sendAndVerifyNativeCard({
    baseUrl,
    sender: owner,
    threadId,
    type: "reel",
    item: reel,
    runTag,
    artifacts,
  });

  console.log("[social-recovery-smoke] PASS native Post and Reel DM cards");
  return { postId, reelId, postCaption };
}

async function verifyMerchantReviewValidation(baseUrl, owner, runTag) {
  const before = await countRows(
    `SELECT COUNT(*)::int AS count
     FROM social_post
     WHERE user_id = $1 AND post_kind = 'merchant_review'`,
    [Number(owner.userId)]
  );

  const missingMerchant = await request(baseUrl, owner, "POST", "/api/feed/posts", {
    caption: `Invalid merchant review missing merchant ${runTag}`,
    postKind: "merchant_review",
    reviewRating: 5,
  });
  assertApplicationError(
    missingMerchant,
    400,
    "VALIDATION_ERROR",
    "merchant review missing merchant"
  );
  assert.equal(
    Array.isArray(missingMerchant.data?.fields) &&
      missingMerchant.data.fields.includes("merchantId_required"),
    true,
    "missing merchant validation field"
  );

  const invalidRating = await request(baseUrl, owner, "POST", "/api/feed/posts", {
    caption: `Invalid merchant review rating ${runTag}`,
    postKind: "merchant_review",
    merchantId: 1,
    reviewRating: 6,
  });
  assertApplicationError(
    invalidRating,
    400,
    "VALIDATION_ERROR",
    "merchant review invalid rating"
  );
  assert.equal(
    Array.isArray(invalidRating.data?.fields) &&
      invalidRating.data.fields.includes("reviewRating"),
    true,
    "invalid review rating validation field"
  );

  const after = await countRows(
    `SELECT COUNT(*)::int AS count
     FROM social_post
     WHERE user_id = $1 AND post_kind = 'merchant_review'`,
    [Number(owner.userId)]
  );
  assert.equal(after, before, "invalid merchant reviews must not persist");
  console.log(
    "[social-recovery-smoke] PASS merchant_review invalid validation (no merchant fixture created)"
  );
}

async function verifyProfileAndFeedReads({
  baseUrl,
  owner,
  peer,
  postId,
  reelId,
}) {
  const profile = await request(
    baseUrl,
    peer,
    "GET",
    `/api/feed/users/${owner.userId}/profile`
  );
  assertStatus(profile, 200, "Social recovery profile retrieval");
  assert.equal(Number(profile.data?.profile?.id || 0), Number(owner.userId));

  const feed = await request(baseUrl, peer, "GET", "/api/feed/posts?limit=40");
  assertStatus(feed, 200, "Social recovery feed retrieval");
  const feedPosts = Array.isArray(feed.data?.posts) ? feed.data.posts : [];
  assert.equal(
    feedPosts.some((item) => Number(item?.id || 0) === Number(postId)),
    true,
    "public Post must be present in peer feed"
  );

  const profilePosts = await request(
    baseUrl,
    peer,
    "GET",
    `/api/feed/users/${owner.userId}/posts?limit=40`
  );
  assertStatus(profilePosts, 200, "Social recovery profile feed retrieval");
  const items = Array.isArray(profilePosts.data?.posts) ? profilePosts.data.posts : [];
  assert.equal(items.some((item) => Number(item?.id || 0) === Number(postId)), true);
  assert.equal(items.some((item) => Number(item?.id || 0) === Number(reelId)), true);
  console.log("[social-recovery-smoke] PASS profile/feed retrieval");
}

async function verifyNoArtifactsRemain(runTag, artifacts) {
  const pattern = `%${runTag}%`;
  const result = await q(
    `SELECT
       (SELECT COUNT(*)::int
          FROM app_user
         WHERE id = ANY($1::bigint[]) OR full_name ILIKE $7) AS users,
       (SELECT COUNT(*)::int
          FROM user_session
         WHERE id = ANY($2::bigint[]) OR user_id = ANY($1::bigint[])) AS sessions,
       (SELECT COUNT(*)::int
          FROM social_story
         WHERE id = ANY($3::bigint[]) OR caption ILIKE $7) AS stories,
       (SELECT COUNT(*)::int
          FROM social_post
         WHERE id = ANY($4::bigint[]) OR caption ILIKE $7) AS posts,
       (SELECT COUNT(*)::int
          FROM social_chat_thread
         WHERE id = ANY($5::bigint[])
            OR user_a_id = ANY($1::bigint[])
            OR user_b_id = ANY($1::bigint[])) AS threads,
       (SELECT COUNT(*)::int
          FROM social_chat_message
         WHERE id = ANY($6::bigint[])
            OR sender_user_id = ANY($1::bigint[])
            OR COALESCE(body, '') ILIKE $7
            OR COALESCE(shared_snapshot_json::text, '') ILIKE $7) AS messages,
       (SELECT COUNT(*)::int
          FROM social_media_asset
         WHERE id = ANY($8::bigint[]) OR owner_user_id = ANY($1::bigint[])) AS media_assets,
       (SELECT COUNT(*)::int
          FROM app_notification
         WHERE user_id = ANY($1::bigint[])
            OR COALESCE(body, '') ILIKE $7
            OR COALESCE(payload::text, '') ILIKE $7) AS notifications`,
    [
      artifacts.userIds,
      artifacts.sessionIds,
      artifacts.storyIds,
      artifacts.postIds,
      artifacts.threadIds,
      artifacts.messageIds,
      pattern,
      artifacts.mediaAssetIds,
    ]
  );
  const leftovers = Object.entries(result.rows[0] || {}).filter(
    ([, value]) => Number(value || 0) !== 0
  );
  assert.deepEqual(leftovers, [], `cleanup left artifacts: ${JSON.stringify(leftovers)}`);
  console.log("[social-recovery-smoke] PASS cleanup verified: no orphan users/content");
}

async function runSmoke({ baseUrl, runTag, artifacts }) {
  const probe = createActor("preflight", runTag, "social-recovery-smoke/1");
  await assertRemoteAndDatabasePreflight(baseUrl, probe);

  const seed = Number(String(Date.now()).slice(-8));
  const owner = createActor("owner", runTag, "social-recovery-smoke/1");
  const peer = createActor("peer", runTag, "social-recovery-smoke/1");
  const ownerPayload = {
    fullName: `Social Recovery Owner ${runTag}`,
    phone: buildPhone("079", seed),
    pin: "1234",
    block: "A1",
    buildingNumber: "A101",
    apartment: "101",
  };
  const peerPayload = {
    fullName: `Social Recovery Peer ${runTag}`,
    phone: buildPhone("078", seed + 1),
    pin: "1234",
    block: "A1",
    buildingNumber: "A101",
    apartment: "102",
  };

  await registerFixtureActor(
    baseUrl,
    owner,
    ownerPayload,
    artifacts,
    "owner"
  );
  await registerFixtureActor(baseUrl, peer, peerPayload, artifacts, "peer");
  console.log("[social-recovery-smoke] PASS authenticated temporary users");

  await updateAndVerifyPublicProfile(baseUrl, owner, runTag);
  const threadId = await connectActorsAndCreateDm(baseUrl, owner, peer, artifacts);

  const defaultStory = await createAndVerifyStory({
    baseUrl,
    owner,
    caption: `Social recovery default Story ${runTag}`,
    settings: DEFAULT_STORY_SETTINGS,
    artifacts,
    label: "default Story create",
  });
  const disabledStory = await createAndVerifyStory({
    baseUrl,
    owner,
    caption: `Social recovery disabled Story ${runTag}`,
    settings: DISABLED_STORY_SETTINGS,
    artifacts,
    label: "disabled Story create",
    useNestedSettings: true,
  });
  console.log("[social-recovery-smoke] PASS default/disabled Story response and DB settings");

  await assertDisabledStoryMutations({
    baseUrl,
    peer,
    threadId,
    storyId: Number(disabledStory.id),
    runTag,
  });
  await exerciseEnabledStory({
    baseUrl,
    owner,
    peer,
    story: defaultStory,
    threadId,
    runTag,
    artifacts,
  });

  const content = await createPostAndReelCards({
    baseUrl,
    owner,
    peer,
    threadId,
    runTag,
    artifacts,
  });
  await verifyMerchantReviewValidation(baseUrl, owner, runTag);
  await verifyProfileAndFeedReads({
    baseUrl,
    owner,
    peer,
    postId: content.postId,
    reelId: content.reelId,
  });
}

async function main() {
  const baseUrl = resolveBaseUrl();
  const runTag = buildRunTag("social-recovery-railway");
  const artifacts = {
    userIds: [],
    sessionIds: [],
    storyIds: [],
    postIds: [],
    threadIds: [],
    messageIds: [],
    mediaAssetIds: [],
  };
  let failure = null;

  try {
    await runSmoke({ baseUrl, runTag, artifacts });
    console.log(`[social-recovery-smoke] PASS runTag=${runTag}`);
  } catch (error) {
    failure = error;
  }

  try {
    await cleanupSocialArtifacts({
      runTag,
      adminSessionIds: artifacts.sessionIds,
    });
    await verifyNoArtifactsRemain(runTag, artifacts);
  } catch (cleanupError) {
    failure = failure
      ? new AggregateError(
          [failure, cleanupError],
          "Social recovery smoke failed and cleanup verification also failed"
        )
      : cleanupError;
  }

  try {
    await pool.end();
  } catch (poolError) {
    failure = failure
      ? new AggregateError([failure, poolError], "Smoke failure plus pool shutdown failure")
      : poolError;
  }

  if (failure) throw failure;
}

main().catch((error) => {
  console.error("[social-recovery-smoke] FAILED");
  console.error(error?.stack || error?.message || error);
  process.exit(1);
});

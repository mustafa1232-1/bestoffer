import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import pg from "pg";

import { feedRouter } from "../modules/feed/feed.routes.js";
import {
  addStoryComment,
  createStory,
  createThread,
  getStoryById,
  highlightStory,
  listMyReportedStories,
  listMyStoryArchive,
  listStories,
  listMessages,
  listUserHighlights,
  resolveSharedEntityForSender,
  scheduleMessage,
  sendCommunityChatMessage,
  sendMessage,
  setStoryArchivedState,
  searchThreadMessages,
  toggleStoryLike,
} from "../modules/feed/feed.service.js";
import { assertSafeE2EDatabaseTarget } from "../scripts/e2eDbSafety.js";

async function pickTwoUsers(client) {
  const result = await client.query(
    `SELECT
       id,
       role,
       block,
       building_number,
       apartment,
       social_stories_public
     FROM app_user
     WHERE COALESCE(is_account_disabled, FALSE) = FALSE
       AND COALESCE(is_super_admin, FALSE) = FALSE
       AND role = 'user'
       AND building_number ~ '^[AB][1-9][0-9]{2}$'
     ORDER BY id ASC
     LIMIT 2`
  );
  assert.ok(result.rowCount >= 2, "expected two active resident users in the test DB");
  return result.rows;
}

function registeredRoutes(router) {
  const routes = [];
  for (const layer of router.stack) {
    if (!layer.route?.path) continue;
    for (const method of Object.keys(layer.route.methods || {})) {
      if (layer.route.methods[method]) {
        routes.push(`${method.toUpperCase()} ${layer.route.path}`);
      }
    }
  }
  return routes;
}

test("story HTTP contract exposes exact retrieval but no invented reply/reshare mutations", () => {
  const routes = registeredRoutes(feedRouter);
  assert.ok(routes.includes("GET /stories/:storyId"));
  assert.equal(routes.includes("POST /stories/:storyId/reply"), false);
  assert.equal(routes.includes("POST /stories/:storyId/reshare"), false);
});

test("story interactions, exact reads, and native sharing enforce the persisted contract", async () => {
  const databaseUrl = process.env.DATABASE_URL || "";
  assertSafeE2EDatabaseTarget({
    scriptName: "feed.story-interactions.test",
    databaseUrl,
    allowProductionOverride: false,
    isProduction: false,
  });

  const client = new pg.Client({ connectionString: databaseUrl });
  await client.connect();

  const createdStoryIds = [];
  let threadId = null;
  let communityMessageId = null;
  let owner = null;
  try {
    const users = await pickTwoUsers(client);
    [owner] = users;
    const peer = users[1];

    // Avoid background new-story fanout; owner access remains valid and all
    // interaction/share checks below are still authoritative.
    await client.query(
      `UPDATE app_user SET social_stories_public = FALSE WHERE id = $1`,
      [owner.id]
    );

    const disabledCaption = `story-disabled-${randomUUID()}`;
    const disabled = await createStory(
      Number(owner.id),
      {
        caption: disabledCaption,
        allowLikes: false,
        allowPrivateReplies: false,
        allowComments: false,
        allowSharing: false,
        allowReshare: false,
      },
      null
    );
    createdStoryIds.push(Number(disabled.id));

    assert.deepEqual(
      {
        allowLikes: disabled.allowLikes,
        allowPrivateReplies: disabled.allowPrivateReplies,
        allowComments: disabled.allowComments,
        allowSharing: disabled.allowSharing,
        allowReshare: disabled.allowReshare,
      },
      {
        allowLikes: false,
        allowPrivateReplies: false,
        allowComments: false,
        allowSharing: false,
        allowReshare: false,
      }
    );

    const persistedDisabled = await client.query(
      `SELECT
         allow_likes,
         allow_private_replies,
         allow_comments,
         allow_sharing,
         allow_reshare
       FROM social_story
       WHERE id = $1`,
      [disabled.id]
    );
    assert.deepEqual(persistedDisabled.rows[0], {
      allow_likes: false,
      allow_private_replies: false,
      allow_comments: false,
      allow_sharing: false,
      allow_reshare: false,
    });

    await assert.rejects(
      toggleStoryLike({ storyId: disabled.id, userId: Number(owner.id) }),
      (error) => error.code === "STORY_LIKES_DISABLED" && error.status === 403
    );
    await assert.rejects(
      addStoryComment({
        storyId: disabled.id,
        userId: Number(owner.id),
        body: "must stay rejected",
      }),
      (error) => error.code === "STORY_COMMENTS_DISABLED" && error.status === 403
    );

    const defaultCaption = `story-default-${randomUUID()}`;
    const enabled = await createStory(
      Number(owner.id),
      { caption: defaultCaption },
      null
    );
    createdStoryIds.push(Number(enabled.id));
    assert.deepEqual(
      [
        enabled.allowLikes,
        enabled.allowPrivateReplies,
        enabled.allowComments,
        enabled.allowSharing,
        enabled.allowReshare,
      ],
      [true, true, true, true, true]
    );

    const liked = await toggleStoryLike({
      storyId: enabled.id,
      userId: Number(owner.id),
    });
    assert.equal(liked.liked, true);
    assert.equal(liked.likesCount, 1);
    const commented = await addStoryComment({
      storyId: enabled.id,
      userId: Number(owner.id),
      body: `comment-${randomUUID()}`,
    });
    assert.equal(commented.commentsCount, 1);

    const exact = await getStoryById(Number(owner.id), Number(enabled.id));
    assert.equal(exact.story.id, Number(enabled.id));
    assert.equal(exact.story.caption, defaultCaption);
    assert.equal(exact.story.likesCount, 1);
    assert.equal(exact.story.commentsCount, 1);
    assert.equal(exact.story.isLiked, true);
    assert.equal(exact.story.allowSharing, true);

    const active = await listStories(Number(owner.id), {
      limitUsers: 20,
      maxPerUser: 20,
    });
    const activeStory = active.stories
      .flatMap((group) => group.stories)
      .find((story) => story.id === Number(enabled.id));
    assert.ok(activeStory, "enabled Story must appear in the active Story read path");
    assert.equal(activeStory.likesCount, 1);
    assert.equal(activeStory.commentsCount, 1);
    assert.equal(activeStory.isLiked, true);
    assert.equal(activeStory.allowSharing, true);

    const thread = await createThread({
      userId: Number(owner.id),
      otherUserId: Number(peer.id),
      kind: "group",
      title: `story-share-${randomUUID()}`,
      memberIds: [Number(peer.id)],
    });
    threadId = Number(thread.id);

    const forgedSnapshot = {
      title: "forged title",
      caption: "forged caption",
      authorName: "forged author",
      mediaUrl: "https://attacker.invalid/forged.jpg",
      forged: true,
    };

    await assert.rejects(
      sendMessage({
        userId: Number(owner.id),
        threadId,
        body: "",
        sharedEntity: {
          type: "story",
          id: Number(disabled.id),
          snapshot: forgedSnapshot,
        },
      }),
      (error) => error.code === "STORY_SHARING_DISABLED" && error.status === 403
    );

    await assert.rejects(
      scheduleMessage({
        userId: Number(owner.id),
        threadId,
        body: "",
        scheduledFor: new Date(Date.now() + 90_000).toISOString(),
        sharedEntity: {
          type: "story",
          id: Number(disabled.id),
          snapshot: forgedSnapshot,
        },
      }),
      (error) => error.code === "STORY_SHARING_DISABLED" && error.status === 403
    );

    const sent = await sendMessage({
      userId: Number(owner.id),
      threadId,
      body: "",
      sharedEntity: {
        type: "story",
        id: Number(enabled.id),
        snapshot: forgedSnapshot,
      },
    });
    const sentSnapshot = sent.message.sharedEntity.snapshot;
    assert.equal(sent.message.sharedEntity.type, "story");
    assert.equal(sent.message.sharedEntity.id, Number(enabled.id));
    assert.equal(sentSnapshot.id, Number(enabled.id));
    assert.equal(sentSnapshot.caption, defaultCaption);
    assert.equal(sentSnapshot.author.id, Number(owner.id));
    assert.equal(sentSnapshot.authorName, sentSnapshot.author.fullName);
    assert.equal("forged" in sentSnapshot, false);
    assert.notEqual(sentSnapshot.title, forgedSnapshot.title);
    assert.notEqual(sentSnapshot.mediaUrl, forgedSnapshot.mediaUrl);

    const storedMessage = await client.query(
      `SELECT shared_snapshot_json
       FROM social_chat_message
       WHERE id = $1`,
      [sent.message.id]
    );
    assert.deepEqual(storedMessage.rows[0].shared_snapshot_json, sentSnapshot);

    const scheduled = await scheduleMessage({
      userId: Number(owner.id),
      threadId,
      body: "",
      scheduledFor: new Date(Date.now() + 90_000).toISOString(),
      sharedEntity: {
        type: "story",
        id: Number(enabled.id),
        snapshot: forgedSnapshot,
      },
    });
    assert.equal(scheduled.item.sharedEntity.snapshot.caption, defaultCaption);
    assert.equal("forged" in scheduled.item.sharedEntity.snapshot, false);

    const community = await sendCommunityChatMessage({
      userId: Number(owner.id),
      userRole: owner.role,
      scopeType: "building",
      scopeCode: owner.building_number,
      dto: {
        body: "",
        replyToMessageId: null,
        attachmentDurationMs: null,
        sharedEntity: {
          type: "story",
          id: Number(enabled.id),
          snapshot: forgedSnapshot,
        },
      },
    });
    communityMessageId = Number(community.message.id);
    assert.equal(community.message.sharedEntity.snapshot.caption, defaultCaption);
    assert.equal("forged" in community.message.sharedEntity.snapshot, false);

    const highlighted = await highlightStory({
      userId: Number(owner.id),
      storyId: Number(enabled.id),
      title: "Contract highlight",
    });
    assert.equal(highlighted.highlight.story.allowSharing, true);
    assert.equal(highlighted.highlight.story.likesCount, 1);
    const highlights = await listUserHighlights(Number(owner.id), Number(owner.id));
    const highlight = highlights.highlights.find(
      (item) => item.story.id === Number(enabled.id)
    );
    assert.ok(highlight);
    assert.equal(highlight.story.commentsCount, 1);
    assert.equal(highlight.story.isLiked, true);

    await setStoryArchivedState({
      userId: Number(owner.id),
      storyId: Number(enabled.id),
      archived: true,
    });
    const archive = await listMyStoryArchive(Number(owner.id), { limit: 40 });
    const archived = archive.stories.find((story) => story.id === Number(enabled.id));
    assert.ok(archived);
    assert.equal(archived.allowSharing, true);
    assert.equal(archived.likesCount, 1);
    assert.equal(archived.commentsCount, 1);

    await client.query(
      `UPDATE social_story
       SET moderation_status = 'pending',
           moderation_note = 'contract-test'
       WHERE id = $1`,
      [disabled.id]
    );
    const reported = await listMyReportedStories({
      userId: Number(owner.id),
      query: { limit: 40 },
    });
    const reportedStory = reported.stories.find(
      (story) => story.id === Number(disabled.id)
    );
    assert.ok(reportedStory);
    assert.equal(reportedStory.allowLikes, false);
    assert.equal(reportedStory.allowSharing, false);

    await assert.rejects(
      resolveSharedEntityForSender({
        senderUserId: Number(owner.id),
        sharedEntity: { type: "story", id: 9_223_372_036_854_000 },
      }),
      (error) => error.code === "STORY_NOT_FOUND" && error.status === 404
    );
  } finally {
    if (communityMessageId != null) {
      await client.query(
        `DELETE FROM app_notification
         WHERE type = 'social.community.chat.message'
           AND payload ->> 'messageId' = $1`,
        [String(communityMessageId)]
      );
      await client.query(`DELETE FROM social_scope_chat_message WHERE id = $1`, [
        communityMessageId,
      ]);
    }
    if (threadId != null) {
      await client.query(
        `DELETE FROM app_notification
         WHERE type = 'social.chat.message'
           AND payload ->> 'threadId' = $1`,
        [String(threadId)]
      );
      await client.query(`DELETE FROM social_chat_thread WHERE id = $1`, [threadId]);
    }
    if (createdStoryIds.length > 0) {
      await client.query(`DELETE FROM social_story WHERE id = ANY($1::bigint[])`, [
        createdStoryIds,
      ]);
    }
    if (owner) {
      await client.query(
        `UPDATE app_user SET social_stories_public = $2 WHERE id = $1`,
        [owner.id, owner.social_stories_public === true]
      );
    }
    await client.end();
  }
});

test("private thread messages remain readable after relation row is removed", async () => {
  const databaseUrl = process.env.DATABASE_URL || "";
  assertSafeE2EDatabaseTarget({
    scriptName: "feed.story-interactions.test",
    databaseUrl,
    allowProductionOverride: false,
    isProduction: false,
  });

  const client = new pg.Client({ connectionString: databaseUrl });
  await client.connect();

  try {
    const users = await pickTwoUsers(client);
    const owner = users[0];
    const peer = users[1];
    const userA = Math.min(Number(owner.id), Number(peer.id));
    const userB = Math.max(Number(owner.id), Number(peer.id));

    await client.query(
      `INSERT INTO social_user_relation (
         user_a_id,
         user_b_id,
         initiator_user_id,
         status,
         requested_at,
         responded_at,
         created_at,
         updated_at
       )
       VALUES ($1, $2, $3, 'accepted', NOW(), NOW(), NOW(), NOW())
       ON CONFLICT (user_a_id, user_b_id)
       DO UPDATE SET
         initiator_user_id = EXCLUDED.initiator_user_id,
         status = 'accepted',
         responded_at = NOW(),
         updated_at = NOW()`,
      [userA, userB, userA]
    );

    const thread = await createThread({
      userId: Number(owner.id),
      otherUserId: Number(peer.id),
      kind: "private",
    });
    const threadId = Number(thread.id);
    const body = `private-thread-${randomUUID()}`;
    const sent = await sendMessage({
      userId: Number(owner.id),
      threadId,
      body,
    });
    assert.equal(sent.message?.body, body);

    await client.query(
      `DELETE FROM social_user_relation
       WHERE user_a_id = $1
         AND user_b_id = $2`,
      [userA, userB]
    );

    const listed = await listMessages({
      userId: Number(owner.id),
      threadId,
      query: { limit: 40, beforeId: null },
    });
    assert.ok(
      listed.messages.some((message) => message.body === body),
      "private thread messages should remain readable after relation row removal"
    );

    const searched = await searchThreadMessages({
      userId: Number(owner.id),
      threadId,
      query: { search: body, limit: 40, beforeId: null },
    });
    assert.ok(
      searched.messages.some((message) => message.body === body),
      "search should remain readable after relation row removal"
    );
  } finally {
    await client.end().catch(() => {});
  }
});

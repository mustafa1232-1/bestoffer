/* eslint-disable no-console */
import assert from "node:assert/strict";

import { app } from "../app.js";
import { ensureSchema, pool, q } from "../config/db.js";
import { validateRuntimeEnv } from "../config/env.js";
import { runSqlMigrations } from "../config/sqlMigrations.js";
import { listUnreadCountsForThreads } from "../modules/feed/feed.repo.js";
import {
  assertStatus,
  buildPhone,
  buildRunTag,
  createActor,
  expectNotification,
  readId,
  readList,
  request,
  startLocalServer,
  stopLocalServer,
} from "./e2eTestUtils.js";
import {
  buildMultipartForm,
  cleanupSocialArtifacts,
  loginActor,
  registerActor,
  requestMultipartForm,
  shouldSkipEnsureSchema,
  shouldSkipMigrations,
} from "./socialE2EHelpers.js";

function normalizeTagKey(runTag) {
  return `phase3a${String(runTag || "")
    .replace(/[^a-z0-9]/gi, "")
    .toLowerCase()
    .slice(-10)}`;
}

function findStoryGroupByAuthorId(stories, authorId) {
    return readList(stories, "stories").find(
      (group) => Number(group?.userId || group?.author?.id || 0) === Number(authorId)
    );
  }

async function registerAndLogin(baseUrl, actor, { phone, fullName, label, apartment }) {
  await registerActor(
    baseUrl,
    actor,
    {
      fullName,
      phone,
      pin: "1234",
      block: "A1",
      buildingNumber: "A101",
      apartment,
      analyticsConsentAccepted: true,
    },
    `${label} register`
  );
  await loginActor(baseUrl, actor, phone, "1234", `${label} login`);
}

async function createBootstrapContext(prefix) {
  validateRuntimeEnv();
  if (!shouldSkipMigrations()) {
    await runSqlMigrations({ force: true });
  }
  if (!shouldSkipEnsureSchema()) {
    await ensureSchema();
  }

  const started = await startLocalServer(app);
  const runTag = buildRunTag(prefix);
  const seed = Number(String(Date.now()).slice(-8));
  const baseUrl = started.baseUrl;
  const alice = createActor("alice", runTag, `${prefix}/1`);
  const bob = createActor("bob", runTag, `${prefix}/1`);

  try {
    await registerAndLogin(baseUrl, alice, {
      phone: buildPhone("079", seed),
      fullName: `Phase3A Alice ${runTag}`,
      label: "alice",
      apartment: "101",
    });
    await registerAndLogin(baseUrl, bob, {
      phone: buildPhone("078", seed + 1),
      fullName: `Phase3A Bob ${runTag}`,
      label: "bob",
      apartment: "102",
    });

    return {
      baseUrl,
      runTag,
      alice,
      bob,
      server: started.server,
    };
  } catch (error) {
    await stopLocalServer(started.server);
    await pool.end();
    throw error;
  }
}

async function finalizeContext({ runTag, server }, { closePool = true } = {}) {
  try {
    if (runTag) {
      await cleanupSocialArtifacts({ runTag });
    }
  } finally {
    await stopLocalServer(server);
    if (closePool) {
      await pool.end();
    }
  }
}

export async function runSocialDiscoveryProfileMessagingFlow({
  closePool = true,
} = {}) {
  let ctx = null;
  try {
    ctx = await createBootstrapContext("social-phase3a");
    const { baseUrl, runTag, alice, bob } = ctx;
    const tagKey = normalizeTagKey(runTag);
    const messageBody = `Phase 3A message ${runTag}`;

    const profileForm = buildMultipartForm({
      fields: {
        bio: `Phase 3A bio ${runTag}`,
        workTitle: `Creator ${runTag}`,
        workCompany: "Maslaki Social",
        showPhone: false,
        postsPublic: true,
        storiesPublic: true,
        relationsPublic: true,
        preferredLocale: "ar",
      },
      fileFieldName: "imageFile",
      fileName: `profile-${runTag}.png`,
      mimeType: "image/png",
    });
    const profileUpdate = await requestMultipartForm(
      baseUrl,
      alice,
      "PATCH",
      "/api/feed/profile/me",
      profileForm
    );
    assertStatus(profileUpdate, 200, "alice profile update");
    assert.equal(
      String(profileUpdate.data?.profile?.bio || ""),
      `Phase 3A bio ${runTag}`,
      "profile bio should persist"
    );

    const relationRequest = await request(
      baseUrl,
      alice,
      "POST",
      `/api/feed/users/${bob.userId}/relation/request`
    );
    assertStatus(relationRequest, 201, "alice sends relation request");
    await expectNotification(
      {
        userId: bob.userId,
        type: "social.relation.request",
        payloadChecks: {
          actorUserId: alice.userId,
          target: "social_profile",
        },
      },
      "relation request notification"
    );

    const relationAccept = await request(
      baseUrl,
      bob,
      "POST",
      `/api/feed/users/${alice.userId}/relation/accept`
    );
    assertStatus(relationAccept, 200, "bob accepts relation request");
    await expectNotification(
      {
        userId: alice.userId,
        type: "social.relation.accepted",
        payloadChecks: {
          actorUserId: bob.userId,
          target: "social_profile",
        },
      },
      "relation accepted notification"
    );

    const relationState = await request(
      baseUrl,
      alice,
      "GET",
      `/api/feed/users/${bob.userId}/relation`
    );
    assertStatus(relationState, 200, "relation state");
    assert.equal(
      String(relationState.data?.relation?.state || ""),
      "accepted",
      "relation should be accepted"
    );

    const postCreate = await request(baseUrl, alice, "POST", "/api/feed/posts", {
      caption: `Phase 3A post ${runTag} #${tagKey} @Phase3A Bob ${runTag}`,
      postKind: "text",
      taggedUserIds: String(bob.userId),
    });
    assertStatus(postCreate, 201, "alice create post");
    const postId = readId(postCreate.data?.post);
    assert.ok(postId, "post id missing");

    const postLike = await request(
      baseUrl,
      bob,
      "POST",
      `/api/feed/posts/${postId}/like`
    );
    assertStatus(postLike, 200, "bob likes post");
    await expectNotification(
      {
        userId: alice.userId,
        type: "social.post.like",
        payloadChecks: {
          postId,
          actorUserId: bob.userId,
        },
      },
      "post like notification"
    );

    const postComment = await request(
      baseUrl,
      bob,
      "POST",
      `/api/feed/posts/${postId}/comments`,
      {
        body: `Great ${runTag}`,
      }
    );
    assertStatus(postComment, 201, "bob comments on post");
    assert.ok(Number(postComment.data?.commentsCount || 0) >= 1);
    await expectNotification(
      {
        userId: alice.userId,
        type: "social.post.comment",
        payloadChecks: {
          postId,
        },
      },
      "post comment notification"
    );

    const postComments = await request(
      baseUrl,
      alice,
      "GET",
      `/api/feed/posts/${postId}/comments`
    );
    assertStatus(postComments, 200, "list post comments");
    assert.ok(
      readList(postComments.data, "comments").some((comment) =>
        String(comment?.body || "").includes(runTag)
      ),
      "comment should be visible on the post"
    );

    const bobTaggedPosts = await request(
      baseUrl,
      bob,
      "GET",
      `/api/feed/profiles/${bob.userId}/tagged?limit=20`
    );
    assertStatus(bobTaggedPosts, 200, "bob tagged posts");
    assert.ok(
      readList(bobTaggedPosts.data, "posts").some((item) => Number(item?.id || 0) === postId),
      "tagged post should be visible on bob profile"
    );

    const savedToggle = await request(baseUrl, bob, "POST", "/api/feed/saved/toggle", {
      entityType: "post",
      entityId: postId,
    });
    assertStatus(savedToggle, 200, "bob saves post");
    assert.equal(Boolean(savedToggle.data?.saved), true);

    const savedList = await request(baseUrl, bob, "GET", "/api/feed/saved?entityType=post");
    assertStatus(savedList, 200, "bob saved content");
    assert.ok(
      readList(savedList.data, "items").some((item) => Number(item?.entityId || 0) === postId),
      "saved post should be present in saved list"
    );

    let searchAll = null;
    let searchMatched = false;
    for (let attempt = 0; attempt < 10; attempt += 1) {
      searchAll = await request(
        baseUrl,
        bob,
        "GET",
        `/api/feed/search?search=${encodeURIComponent(runTag)}&tab=all&limit=12`
      );
      assertStatus(searchAll, 200, "social search all");
      const users = readList(searchAll.data?.results || {}, "users");
      const posts = readList(searchAll.data?.results || {}, "posts");
      searchMatched =
        users.some((item) => Number(item?.id || 0) === alice.userId) &&
        posts.some((item) => Number(item?.id || 0) === postId);
      if (searchMatched) break;
      await new Promise((resolve) => setTimeout(resolve, 500));
    }
    assert.ok(searchMatched, "search should find alice and the post");
    assert.ok(Array.isArray(searchAll.data?.recentSearches), "recent searches should exist");

    const hashtagPosts = await request(
      baseUrl,
      bob,
      "GET",
      `/api/feed/hashtags/${tagKey}?limit=12`
    );
    assertStatus(hashtagPosts, 200, "hashtag posts");
    assert.ok(
      readList(hashtagPosts.data, "posts").some((item) => Number(item?.id || 0) === postId),
      "hashtag feed should include the post"
    );

    const mentionUsers = await request(
      baseUrl,
      bob,
      "GET",
      `/api/feed/mentions/users?search=${encodeURIComponent("Phase3A Bob")}&limit=12`
    );
    assertStatus(mentionUsers, 200, "mention suggestions");
    assert.ok(Array.isArray(mentionUsers.data?.users), "mention user list should exist");

    const suggestedPeople = await request(
      baseUrl,
      bob,
      "GET",
      "/api/feed/users/suggested?limit=12"
    );
    assertStatus(suggestedPeople, 200, "suggested people");
    assert.ok(Array.isArray(suggestedPeople.data?.users), "suggested users should exist");

    const shareRecipients = await request(
      baseUrl,
      bob,
      "GET",
      `/api/feed/share/recipients?search=${encodeURIComponent(runTag)}&limit=12`
    );
    assertStatus(shareRecipients, 200, "share recipients");
    assert.ok(Array.isArray(shareRecipients.data?.recipients), "share recipients should exist");

    const friends = await request(
      baseUrl,
      alice,
      "GET",
      `/api/feed/users/${alice.userId}/friends?limit=12`
    );
    assertStatus(friends, 200, "friends list");
    assert.ok(Array.isArray(readList(friends.data, "users")), "friends list should expose users");

    const aliceProfile = await request(
      baseUrl,
      bob,
      "GET",
      `/api/feed/users/${alice.userId}/profile`
    );
    assertStatus(aliceProfile, 200, "alice profile");
    assert.equal(
      String(aliceProfile.data?.profile?.bio || ""),
      `Phase 3A bio ${runTag}`,
      "alice profile bio should be visible"
    );
    assert.ok(
      Number(aliceProfile.data?.profile?.stats?.totalPosts || 0) >= 1,
      "profile stats should include at least one post"
    );
    assert.ok(
      Number(aliceProfile.data?.profile?.stats?.connectionsCount || 0) >= 1,
      "profile stats should reflect accepted relation"
    );

    const aliceInsights = await request(
      baseUrl,
      alice,
      "GET",
      `/api/feed/profiles/${alice.userId}/insights`
    );
    assertStatus(aliceInsights, 200, "alice insights");
    assert.ok(
      Number(aliceInsights.data?.summary?.contentCount || 0) >= 1,
      "insights should report content"
    );

    const groupThread = await request(baseUrl, alice, "POST", "/api/feed/chats/threads", {
      kind: "group",
      title: `Phase3A Group ${runTag}`,
      memberIds: [bob.userId],
    });
    assertStatus(groupThread, 201, "group thread create");
    const threadId = readId(groupThread.data?.thread);
    assert.ok(threadId, "group thread id missing");

    const bobThreads = await request(baseUrl, bob, "GET", "/api/feed/chats/threads?limit=20");
    assertStatus(bobThreads, 200, "bob threads list");
    assert.ok(Array.isArray(readList(bobThreads.data, "threads")), "thread list should exist");

    const threadMessage = await request(
      baseUrl,
      alice,
      "POST",
      `/api/feed/chats/threads/${threadId}/messages`,
      {
        body: messageBody,
      }
    );
    assertStatus(threadMessage, 201, "group thread message");
    await expectNotification(
      {
        userId: bob.userId,
        type: "social.chat.message",
        payloadChecks: {
          threadId,
        },
      },
      "group chat notification"
    );

    const threadMessages = await request(
      baseUrl,
      bob,
      "GET",
      `/api/feed/chats/threads/${threadId}/messages?limit=20`
    );
    assertStatus(threadMessages, 200, "thread messages");
    assert.ok(
      readList(threadMessages.data, "messages").some((item) =>
        String(item?.body || "").includes(runTag)
      ),
      "group message should be readable"
    );

    console.log(
      `[social-phase3a] passed runTag=${runTag} alice=${alice.userId} bob=${bob.userId} post=${postId} thread=${threadId}`
    );
  } finally {
    if (ctx) {
      await finalizeContext(ctx, { closePool });
    }
  }
}

export async function runStoriesPhase3AFlow() {
  let ctx = null;
  try {
    ctx = await createBootstrapContext("stories-phase3a");
    const { baseUrl, runTag, alice, bob } = ctx;
    const profileForm = buildMultipartForm({
      fields: {
        bio: `Phase 3A story bio ${runTag}`,
        workTitle: `Story Creator ${runTag}`,
        workCompany: "Maslaki Stories",
        showPhone: false,
        accountPrivate: false,
        postsPublic: true,
        storiesPublic: true,
        relationsPublic: true,
        preferredLocale: "ar",
      },
      fileFieldName: "imageFile",
      fileName: `story-profile-${runTag}.png`,
      mimeType: "image/png",
    });
    const profileUpdate = await requestMultipartForm(
      baseUrl,
      alice,
      "PATCH",
      "/api/feed/profile/me",
      profileForm
    );
    assertStatus(profileUpdate, 200, "alice story profile update");

    const relationRequest = await request(
      baseUrl,
      alice,
      "POST",
      `/api/feed/users/${bob.userId}/relation/request`
    );
    assertStatus(relationRequest, 201, "alice story relation request");
    const relationAccept = await request(
      baseUrl,
      bob,
      "POST",
      `/api/feed/users/${alice.userId}/relation/accept`
    );
    assertStatus(relationAccept, 200, "bob accepts story relation");

    const storyStyle = {
      version: 1,
      mode: "text",
      background: {
        type: "solid",
        primaryColor: "#112233",
      },
    };
    const storyForm = buildMultipartForm({
      fields: {
        caption: `Story ${runTag}`,
        storyStyle,
      },
      fileFieldName: "mediaFile",
      fileName: `story-${runTag}.png`,
      mimeType: "image/png",
    });
    const createdStory = await requestMultipartForm(
      baseUrl,
      alice,
      "POST",
      "/api/feed/stories",
      storyForm
    );
    assertStatus(createdStory, 201, "alice creates story");
    const storyId = readId(createdStory.data?.story);
    assert.ok(storyId, "story id missing");

    const storiesBefore = await request(
      baseUrl,
      bob,
      "GET",
      "/api/feed/stories?limitUsers=20&maxPerUser=8"
    );
    assertStatus(storiesBefore, 200, "stories list before view");
    const aliceStoryGroup = findStoryGroupByAuthorId(storiesBefore.data, alice.userId);
    assert.ok(aliceStoryGroup, "alice story group should be present");
    assert.ok(
      readList(aliceStoryGroup, "stories").some((item) => Number(item?.id || 0) === storyId),
      "story should be in the viewer list"
    );

    const storyView = await request(
      baseUrl,
      bob,
      "POST",
      `/api/feed/stories/${storyId}/view`,
      {}
    );
    assertStatus(storyView, 200, "story viewed");

    const storiesAfterView = await request(
      baseUrl,
      bob,
      "GET",
      "/api/feed/stories?limitUsers=20&maxPerUser=8"
    );
    assertStatus(storiesAfterView, 200, "stories list after view");
    const storyGroupAfterView = findStoryGroupByAuthorId(storiesAfterView.data, alice.userId);
    assert.ok(storyGroupAfterView, "story group after view should still exist");
    assert.ok(
      readList(storyGroupAfterView, "stories").some(
        (item) => Number(item?.id || 0) === storyId && item?.isViewed === true
      ),
      "story should be marked viewed"
    );

    const storyLike = await request(
      baseUrl,
      bob,
      "POST",
      `/api/feed/stories/${storyId}/like`,
      {}
    );
    assertStatus(storyLike, 200, "story like");
    await expectNotification(
      {
        userId: alice.userId,
        type: "social.story.like",
        payloadChecks: {
          storyId,
        },
      },
      "story like notification"
    );

    const storyComment = await request(
      baseUrl,
      bob,
      "POST",
      `/api/feed/stories/${storyId}/comments`,
      {
        body: `Story comment ${runTag}`,
      }
    );
    assertStatus(storyComment, 201, "story comment");
    await expectNotification(
      {
        userId: alice.userId,
        type: "social.story.comment",
        payloadChecks: {
          storyId,
        },
      },
      "story comment notification"
    );

    const storyComments = await request(
      baseUrl,
      alice,
      "GET",
      `/api/feed/stories/${storyId}/comments?limit=20`
    );
    assertStatus(storyComments, 200, "story comments");
    assert.ok(
      readList(storyComments.data, "comments").some((item) =>
        String(item?.body || "").includes(runTag)
      ),
      "story comment should be visible"
    );

    const highlight = await request(
      baseUrl,
      alice,
      "POST",
      `/api/feed/stories/${storyId}/highlight`,
      {
        title: `Featured ${runTag}`,
      }
    );
    assertStatus(highlight, 201, "story highlight");
    const highlightId = readId(highlight.data?.highlight);
    assert.ok(highlightId, "highlight id missing");

    const removeHighlight = await request(
      baseUrl,
      alice,
      "DELETE",
      `/api/feed/highlights/${highlightId}`
    );
    assertStatus(removeHighlight, 204, "remove highlight");

    const archiveStory = await request(
      baseUrl,
      alice,
      "POST",
      `/api/feed/stories/${storyId}/archive`,
      {}
    );
    assertStatus(archiveStory, 200, "archive story");

    const storyArchive = await request(
      baseUrl,
      alice,
      "GET",
      "/api/feed/stories/archive/me?limit=20"
    );
    assertStatus(storyArchive, 200, "story archive");
    assert.ok(
      readList(storyArchive.data, "stories").some((item) => Number(item?.id || 0) === storyId),
      "archived story should be visible in archive"
    );

    const restoreStory = await request(
      baseUrl,
      alice,
      "POST",
      `/api/feed/stories/${storyId}/restore`,
      {}
    );
    assertStatus(restoreStory, 200, "restore story");

    const storiesAfterRestore = await request(
      baseUrl,
      bob,
      "GET",
      "/api/feed/stories?limitUsers=20&maxPerUser=8"
    );
    assertStatus(storiesAfterRestore, 200, "stories list after restore");
    assert.ok(
      findStoryGroupByAuthorId(storiesAfterRestore.data, alice.userId),
      "restored story should be back in the viewer list"
    );

    console.log(`[stories-phase3a] passed runTag=${runTag} story=${storyId}`);
  } finally {
    if (ctx) {
      await finalizeContext(ctx);
    }
  }
}

export async function runReelsPhase3AFlow() {
  let ctx = null;
  try {
    ctx = await createBootstrapContext("reels-phase3a");
    const { baseUrl, runTag, alice, bob } = ctx;
    const tagKey = normalizeTagKey(runTag);
    const reelForm = buildMultipartForm({
      fields: {
        caption: `Reel ${runTag} #${tagKey}`,
      },
      fileFieldName: "mediaFile",
      fileName: `reel-${runTag}.mp4`,
      mimeType: "video/mp4",
    });
    const createdReel = await requestMultipartForm(
      baseUrl,
      alice,
      "POST",
      "/api/feed/reels",
      reelForm
    );
    assertStatus(createdReel, 201, "alice creates reel");
    const reelId = readId(createdReel.data?.reel);
    assert.ok(reelId, "reel id missing");

    const reelDetails = await request(baseUrl, bob, "GET", `/api/feed/reels/${reelId}`);
    assertStatus(reelDetails, 200, "reel details");
    assert.equal(Number(reelDetails.data?.reel?.id || 0), reelId, "reel detail id mismatch");

    const profileReels = await request(
      baseUrl,
      bob,
      "GET",
      `/api/feed/profiles/${alice.userId}/reels?limit=20`
    );
    assertStatus(profileReels, 200, "profile reels");
    assert.ok(
      readList(profileReels.data, "posts").some((item) => Number(item?.id || 0) === reelId),
      "profile reels should include the reel"
    );

    const searchReels = await request(
      baseUrl,
      bob,
      "GET",
      `/api/feed/search?search=${encodeURIComponent(runTag)}&tab=reels&limit=12`
    );
    assertStatus(searchReels, 200, "reel search");
    assert.ok(
      Array.isArray(searchReels.data?.results?.reels) &&
        searchReels.data.results.reels.some((item) => Number(item?.id || 0) === reelId),
      "reel search should include the reel"
    );

    const reelView = await request(
      baseUrl,
      bob,
      "POST",
      `/api/feed/reels/${reelId}/view`,
      {
        watchDurationMs: 4200,
        completionRate: 100,
        replayCount: 1,
        completed: true,
        context: "phase3a_reels",
      }
    );
    assertStatus(reelView, 200, "reel view");
    assert.ok(Number(reelView.data?.eventId || 0) > 0, "reel view event should be recorded");

    const reelLike = await request(
      baseUrl,
      bob,
      "POST",
      `/api/feed/posts/${reelId}/like`,
      {}
    );
    assertStatus(reelLike, 200, "reel like");
    await expectNotification(
      {
        userId: alice.userId,
        type: "social.reel.like",
        payloadChecks: {
          postId: reelId,
        },
      },
      "reel like notification"
    );

    const reelComment = await request(
      baseUrl,
      bob,
      "POST",
      `/api/feed/posts/${reelId}/comments`,
      {
        body: `Reel comment ${runTag}`,
      }
    );
    assertStatus(reelComment, 201, "reel comment");
    await expectNotification(
      {
        userId: alice.userId,
        type: "social.reel.comment",
        payloadChecks: {
          postId: reelId,
        },
      },
      "reel comment notification"
    );

    const reelComments = await request(
      baseUrl,
      alice,
      "GET",
      `/api/feed/posts/${reelId}/comments?limit=20`
    );
    assertStatus(reelComments, 200, "reel comments");
    assert.ok(
      readList(reelComments.data, "comments").some((item) =>
        String(item?.body || "").includes(runTag)
      ),
      "reel comment should be visible"
    );

    const saveReel = await request(baseUrl, alice, "POST", "/api/feed/saved/toggle", {
      entityType: "reel",
      entityId: reelId,
    });
    assertStatus(saveReel, 200, "save reel");
    assert.equal(Boolean(saveReel.data?.saved), true);

    const savedReels = await request(
      baseUrl,
      alice,
      "GET",
      "/api/feed/saved?entityType=reel&limit=20"
    );
    assertStatus(savedReels, 200, "saved reels");
    assert.ok(
      readList(savedReels.data, "items").some((item) => Number(item?.entityId || 0) === reelId),
      "saved reels should include the reel"
    );

    const reelsExplore = await request(baseUrl, bob, "GET", "/api/feed/reels/explore?limit=12");
    assertStatus(reelsExplore, 200, "reels explore");
    assert.ok(Array.isArray(reelsExplore.data?.reels), "reels explore should expose reels");

    const shareRecipients = await request(
      baseUrl,
      bob,
      "GET",
      `/api/feed/share/recipients?search=${encodeURIComponent(runTag)}&limit=12`
    );
    assertStatus(shareRecipients, 200, "share recipients");
    assert.ok(Array.isArray(shareRecipients.data?.recipients), "share recipients should exist");

    console.log(`[reels-phase3a] passed runTag=${runTag} reel=${reelId}`);
  } finally {
    if (ctx) {
      await finalizeContext(ctx);
    }
  }
}

export async function runSocialMessagingPhase3BFlow({
  closePool = true,
} = {}) {
  let ctx = null;
  try {
    ctx = await createBootstrapContext("social-phase3b");
    const { baseUrl, runTag, alice, bob } = ctx;
    const charlie = createActor("charlie", runTag, "social-phase3b/1");
    await registerAndLogin(baseUrl, charlie, {
      phone: buildPhone("077", Number(String(Date.now()).slice(-8)) + 77),
      fullName: `Phase3B Charlie ${runTag}`,
      label: "charlie",
      apartment: "103",
    });

    const groupThread = await request(baseUrl, alice, "POST", "/api/feed/chats/threads", {
      kind: "group",
      title: `Phase3B Group ${runTag}`,
      memberIds: [bob.userId, charlie.userId],
    });
    assertStatus(groupThread, 201, "phase3b group thread create");
    const threadId = readId(groupThread.data?.thread);
    assert.ok(threadId, "phase3b group thread id missing");

    const voiceForm = buildMultipartForm({
      fields: {
        body: "",
        clientMessageId: `phase3b-${runTag}-voice`,
      },
      fileFieldName: "attachmentFile",
      fileName: `voice-${runTag}.ogg`,
      mimeType: "audio/ogg",
    });
    const firstSend = await requestMultipartForm(
      baseUrl,
      alice,
      "POST",
      `/api/feed/chats/threads/${threadId}/messages`,
      voiceForm
    );
    assertStatus(firstSend, 201, "phase3b first voice send");
    const firstMessageId = readId(firstSend.data?.message);
    assert.ok(firstMessageId, "phase3b first message id missing");

    const duplicateForm = buildMultipartForm({
      fields: {
        body: "",
        clientMessageId: `phase3b-${runTag}-voice`,
      },
      fileFieldName: "attachmentFile",
      fileName: `voice-${runTag}.ogg`,
      mimeType: "audio/ogg",
    });
    const secondSend = await requestMultipartForm(
      baseUrl,
      alice,
      "POST",
      `/api/feed/chats/threads/${threadId}/messages`,
      duplicateForm
    );
    assertStatus(secondSend, 201, "phase3b duplicate voice send");
    const secondMessageId = readId(secondSend.data?.message);
    assert.equal(
      secondMessageId,
      firstMessageId,
      "duplicate clientMessageId should resolve to the same message"
    );

    const threadMessageCount = await q(
      `SELECT COUNT(*)::int AS count
       FROM social_chat_message
       WHERE thread_id = $1
         AND client_message_id = $2`,
      [threadId, `phase3b-${runTag}-voice`]
    );
    assert.equal(
      Number(threadMessageCount.rows[0]?.count || 0),
      1,
      "duplicate thread send should store only one row"
    );

    const bobUnreadRows = await listUnreadCountsForThreads({
      userId: bob.userId,
      threadIds: [threadId],
    });
    const charlieUnreadRows = await listUnreadCountsForThreads({
      userId: charlie.userId,
      threadIds: [threadId],
    });
    assert.equal(
      Number(bobUnreadRows[0]?.unread_count || 0),
      1,
      "bob unread count should remain 1 after a duplicate retry"
    );
    assert.equal(
      Number(charlieUnreadRows[0]?.unread_count || 0),
      1,
      "charlie unread count should remain 1 after a duplicate retry"
    );
    for (const row of [...bobUnreadRows, ...charlieUnreadRows]) {
      assert.equal(
        Number(row.unread_count || 0),
        1,
        `recipient ${row.user_id || row.thread_id} unread count should remain 1 after a duplicate retry`
      );
    }

    const notificationCount = await q(
      `SELECT COUNT(*)::int AS count
       FROM app_notification
       WHERE type = 'social.chat.message'
         AND COALESCE(payload->>'threadId', '') = $1`,
      [String(threadId)]
    );
    assert.equal(
      Number(notificationCount.rows[0]?.count || 0),
      2,
      "group notifications should only be emitted once per recipient"
    );

    const bobMessages = await request(
      baseUrl,
      bob,
      "GET",
      `/api/feed/chats/threads/${threadId}/messages?limit=20`
    );
    assertStatus(bobMessages, 200, "phase3b bob messages");
    assert.equal(
      readList(bobMessages.data, "messages").filter(
        (item) =>
          Number(item?.id || 0) === firstMessageId ||
          String(item?.clientMessageId || item?.client_message_id || "") ===
            `phase3b-${runTag}-voice`
      ).length,
      1,
      "bob should see a single voice message row"
    );

    console.log(
      `[social-phase3b] passed runTag=${runTag} alice=${alice.userId} bob=${bob.userId} charlie=${charlie.userId} thread=${threadId}`
    );
  } finally {
    if (ctx) {
      await finalizeContext(ctx, { closePool });
    }
  }
}

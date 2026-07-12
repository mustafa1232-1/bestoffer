/* eslint-disable no-console */
import "dotenv/config";

import assert from "node:assert/strict";

import { app } from "../app.js";
import { ensureSchema, pool } from "../config/db.js";
import { env, validateRuntimeEnv } from "../config/env.js";
import { runSqlMigrations } from "../config/sqlMigrations.js";
import {
  assertStatus,
  buildPhone,
  buildRunTag,
  cleanupAdminArtifacts,
  createActor,
  ensureSuperAdminAccount,
  expectNotification,
  readId,
  request,
  startLocalServer,
  stopLocalServer,
} from "./e2eTestUtils.js";

function buildCandidateBuildings() {
  const items = [];
  for (const area of ["A", "B"]) {
    for (let compound = 1; compound <= 8; compound += 1) {
      const limit = area === "A" ? 12 : 22;
      for (let building = 1; building <= limit; building += 1) {
        items.push({
          block: area,
          compound: `${area}${compound}`,
          building: `${area}${compound}${String(building).padStart(2, "0")}`,
        });
      }
    }
  }
  return items;
}

function shouldSkipMigrations() {
  const raw = String(process.env.E2E_SKIP_SQL_MIGRATIONS || "").trim().toLowerCase();
  return ["1", "true", "yes", "on"].includes(raw);
}

function shouldSkipEnsureSchema() {
  const raw = String(process.env.E2E_SKIP_ENSURE_SCHEMA || "").trim().toLowerCase();
  return ["1", "true", "yes", "on"].includes(raw);
}

async function pickUnusedBuildingScope() {
  const result = await pool.query(
    `WITH used_codes AS (
       SELECT building_number AS code
       FROM app_user
       WHERE building_number IS NOT NULL
       UNION
       SELECT scope_code AS code FROM social_scope_manager WHERE scope_type = 'building'
       UNION
       SELECT scope_code AS code FROM social_scope_announcement WHERE scope_type = 'building'
       UNION
       SELECT scope_code AS code FROM social_scope_chat_settings WHERE scope_type = 'building'
       UNION
       SELECT scope_code AS code FROM social_scope_chat_ban WHERE scope_type = 'building'
       UNION
       SELECT scope_code AS code FROM social_scope_chat_message WHERE scope_type = 'building'
       UNION
       SELECT scope_code AS code FROM social_scope_bill WHERE scope_type = 'building'
     )
     SELECT DISTINCT code
     FROM used_codes
     WHERE code IS NOT NULL`
  );

  const used = new Set(
    result.rows
      .map((row) => String(row.code || "").trim().toUpperCase())
      .filter(Boolean)
  );

  const candidate = buildCandidateBuildings().find(
    (item) => !used.has(item.building)
  );
  if (!candidate) {
    throw new Error("NO_EMPTY_BUILDING_SCOPE_AVAILABLE");
  }
  return candidate;
}

function findPost(rows, postId) {
  if (!Array.isArray(rows)) return null;
  return rows.find((row) => Number(row?.id || 0) === Number(postId)) || null;
}

function findMonitoredThread(rows, matcher) {
  if (!Array.isArray(rows)) return null;
  return rows.find((row) => matcher(row)) || null;
}

async function cleanup(state) {
  const userIds = [state.userOneId, state.userTwoId, state.outsiderUserId].filter(
    (value) => Number.isFinite(Number(value)) && Number(value) > 0
  );

  await cleanupAdminArtifacts({
    adminSessionIds: state.adminSessionIds,
    superAdminId: state.superAdminId,
    runTag: state.runTag,
    approvalPaths: [],
  });

  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    if (state.userPostId || state.adminPostId) {
      const postIds = [state.userPostId, state.adminPostId].filter(
        (value) => Number.isFinite(Number(value)) && Number(value) > 0
      );
      if (postIds.length > 0) {
        await client.query(
          `DELETE FROM app_notification
           WHERE COALESCE(payload->>'postId', '') = ANY($1::text[])`,
          [postIds.map((id) => String(id))]
        );
        await client.query(
          `DELETE FROM social_post_comment
           WHERE post_id = ANY($1::bigint[])`,
          [postIds]
        );
        await client.query(
          `DELETE FROM social_post_like
           WHERE post_id = ANY($1::bigint[])`,
          [postIds]
        );
        await client.query(`DELETE FROM social_post WHERE id = ANY($1::bigint[])`, [
          postIds,
        ]);
      }
    }

    if (state.scope?.building) {
      await client.query(
        `DELETE FROM app_notification
         WHERE COALESCE(payload->>'scopeCode', '') = $1`,
        [state.scope.building]
      );
      await client.query(
        `DELETE FROM social_scope_bill
         WHERE scope_type = 'building'
           AND scope_code = $1`,
        [state.scope.building]
      );
      await client.query(
        `DELETE FROM social_scope_chat_ban
         WHERE scope_type = 'building'
           AND scope_code = $1`,
        [state.scope.building]
      );
      await client.query(
        `DELETE FROM social_scope_chat_settings
         WHERE scope_type = 'building'
           AND scope_code = $1`,
        [state.scope.building]
      );
      await client.query(
        `DELETE FROM social_scope_chat_message
         WHERE scope_type = 'building'
           AND scope_code = $1`,
        [state.scope.building]
      );
      await client.query(
        `DELETE FROM social_scope_announcement
         WHERE scope_type = 'building'
           AND scope_code = $1`,
        [state.scope.building]
      );
      await client.query(
        `DELETE FROM social_scope_manager
         WHERE scope_type = 'building'
           AND scope_code = $1`,
        [state.scope.building]
      );
    }

    if (userIds.length > 0) {
      await client.query(
        `DELETE FROM user_activity_event
         WHERE user_id = ANY($1::bigint[])`,
        [userIds]
      );
      await client.query(
        `DELETE FROM app_notification
         WHERE user_id = ANY($1::bigint[])`,
        [userIds]
      );
      await client.query(
        `DELETE FROM social_scope_manager
         WHERE manager_user_id = ANY($1::bigint[])`,
        [userIds]
      );
      await client.query(
        `DELETE FROM social_post_comment
         WHERE user_id = ANY($1::bigint[])`,
        [userIds]
      );
      await client.query(
        `DELETE FROM customer_address
         WHERE customer_user_id = ANY($1::bigint[])`,
        [userIds]
      );
      await client.query(
        `DELETE FROM user_push_token
         WHERE user_id = ANY($1::bigint[])`,
        [userIds]
      );
      await client.query(
        `DELETE FROM user_session
         WHERE user_id = ANY($1::bigint[])`,
        [userIds]
      );
      await client.query(`DELETE FROM app_user WHERE id = ANY($1::bigint[])`, [
        userIds,
      ]);
    }

    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

async function registerUser(baseUrl, actor, payload, label) {
  const response = await request(baseUrl, actor, "POST", "/api/auth/register", {
    ...payload,
    analyticsConsentAccepted: true,
    analyticsConsentVersion: "analytics_v1",
  });
  assertStatus(response, 201, label);
  actor.token = String(response.data?.token || "");
  actor.sessionId = Number(response.data?.sessionId || 0) || null;
  return readId(response.data?.user);
}

async function makeProfilePublic(baseUrl, actor, label) {
  const response = await request(baseUrl, actor, "PATCH", "/api/feed/profile/me", {
    accountPrivate: false,
    postsPublic: true,
    storiesPublic: true,
    relationsPublic: true,
  });
  assertStatus(response, 200, label);
  if (actor.userId) {
    await pool.query(
      `UPDATE app_user
       SET social_account_private = FALSE,
           social_posts_public = TRUE,
           social_stories_public = TRUE,
           social_relations_public = TRUE,
           social_visibility_tier = 'normal'
       WHERE id = $1`,
      [Number(actor.userId)]
    );
  }
}

async function main() {
  validateRuntimeEnv();
  if (!shouldSkipMigrations()) {
    await runSqlMigrations({ force: true });
  }
  if (!shouldSkipEnsureSchema()) {
    await ensureSchema();
  }

  const runTag = buildRunTag("community-e2e");
  const timestampSeed = Number(String(Date.now()).slice(-8));
  const scope = await pickUnusedBuildingScope();
  const state = {
    runTag,
    scope,
    userOnePhone: buildPhone("079", timestampSeed),
    userTwoPhone: buildPhone("078", timestampSeed + 1),
    outsiderPhone: buildPhone("077", timestampSeed + 2),
    superAdminId: await ensureSuperAdminAccount(),
    userOneId: null,
    userTwoId: null,
    outsiderUserId: null,
    userPostId: null,
    adminPostId: null,
    adminSessionIds: [],
  };

  let server = null;

  try {
    const started = await startLocalServer(app);
    server = started.server;
    const baseUrl = started.baseUrl;
    console.log(
      `[community-e2e] baseUrl=${baseUrl} runTag=${runTag} scope=${scope.building}`
    );

    const admin = createActor("admin", runTag, "e2e-community-check/1");
    const userOne = createActor("user-one", runTag, "e2e-community-check/1");
    const userTwo = createActor("user-two", runTag, "e2e-community-check/1");
    const outsider = createActor("outsider", runTag, "e2e-community-check/1");

    state.userOneId = await registerUser(
      baseUrl,
      userOne,
      {
        fullName: `Resident One ${runTag}`,
        phone: state.userOnePhone,
        pin: "1234",
        block: scope.compound,
        buildingNumber: scope.building,
        apartment: "101",
      },
      "resident one register"
    );
    await makeProfilePublic(baseUrl, userOne, "resident one profile public");

    state.userTwoId = await registerUser(
      baseUrl,
      userTwo,
      {
        fullName: `Resident Two ${runTag}`,
        phone: state.userTwoPhone,
        pin: "1234",
        block: scope.compound,
        buildingNumber: scope.building,
        apartment: "102",
      },
      "resident two register"
    );
    await makeProfilePublic(baseUrl, userTwo, "resident two profile public");

    state.outsiderUserId = await registerUser(
      baseUrl,
      outsider,
      {
        fullName: `Resident Outside ${runTag}`,
        phone: state.outsiderPhone,
        pin: "1234",
        block: "B1",
        buildingNumber: "B101",
        apartment: "103",
      },
      "outsider register"
    );

    const adminLogin = await request(baseUrl, admin, "POST", "/api/auth/login", {
      phone: env.superAdminPhone,
      pin: env.superAdminPin,
    });
    assertStatus(adminLogin, 200, "admin login");
    admin.token = String(adminLogin.data?.token || "");
    admin.sessionId = Number(adminLogin.data?.sessionId || 0) || null;
    admin.userId = readId(adminLogin.data?.user) || state.superAdminId;
    if (admin.sessionId) {
      state.adminSessionIds.push(admin.sessionId);
    }
    await makeProfilePublic(baseUrl, admin, "admin profile public");

    const userScopes = await request(
      baseUrl,
      userOne,
      "GET",
      "/api/feed/communities/scopes/me"
    );
    assertStatus(userScopes, 200, "resident scopes");
    const scopeKeys = Array.isArray(userScopes.data?.scopes)
      ? userScopes.data.scopes.map((item) => `${item.scopeType}:${item.scopeCode}`)
      : [];
    assert.ok(scopeKeys.includes(`block:${scope.block}`));
    assert.ok(scopeKeys.includes(`compound:${scope.compound}`));
    assert.ok(scopeKeys.includes(`building:${scope.building}`));

    const adminScopes = await request(
      baseUrl,
      admin,
      "GET",
      "/api/feed/communities/scopes/me"
    );
    assertStatus(adminScopes, 200, "admin scopes");
    assert.ok(
      Array.isArray(adminScopes.data?.scopes) &&
        adminScopes.data.scopes.some(
          (item) =>
            item?.scopeType === "building" && String(item?.scopeCode || "") === scope.building
        ),
      "admin should see target building scope"
    );

    const userPostCreate = await request(baseUrl, userOne, "POST", "/api/feed/posts", {
      caption: `Resident post ${runTag}`,
      postKind: "text",
    });
    assertStatus(userPostCreate, 201, "resident create post");
    state.userPostId = readId(userPostCreate.data?.post);

    const adminPostCreate = await request(baseUrl, admin, "POST", "/api/feed/posts", {
      caption: `Admin post ${runTag}`,
      postKind: "text",
    });
    assertStatus(adminPostCreate, 201, "admin create post");
    state.adminPostId = readId(adminPostCreate.data?.post);

    const generalFeed = await request(baseUrl, userTwo, "GET", "/api/feed/posts?limit=40");
    assertStatus(generalFeed, 200, "resident general feed");
    assert.ok(findPost(generalFeed.data?.posts, state.userPostId));

    const adminGeneralFeed = await request(baseUrl, admin, "GET", "/api/feed/posts?limit=40");
    assertStatus(adminGeneralFeed, 200, "admin general feed");
    assert.ok(findPost(adminGeneralFeed.data?.posts, state.userPostId));

    for (const scopePath of [
      `/api/feed/communities/block/${scope.block}/feed?limit=40`,
      `/api/feed/communities/compound/${scope.compound}/feed?limit=40`,
      `/api/feed/communities/building/${scope.building}/feed?limit=40`,
    ]) {
      const response = await request(baseUrl, userTwo, "GET", scopePath);
      assertStatus(response, 200, `community feed ${scopePath}`);
      assert.ok(findPost(response.data?.posts, state.userPostId));
    }

    const outsiderBuildingFeed = await request(
      baseUrl,
      outsider,
      "GET",
      `/api/feed/communities/building/${scope.building}/feed?limit=40`
    );
    assertStatus(outsiderBuildingFeed, 403, "outsider building feed");

    const addComment = await request(
      baseUrl,
      userTwo,
      "POST",
      `/api/feed/posts/${state.userPostId}/comments`,
      {
        body: `comment-${runTag}`,
      }
    );
    assertStatus(addComment, 201, "add comment");
    assert.equal(Number(addComment.data?.commentsCount || 0), 1);

    await expectNotification(
      {
        userId: state.userOneId,
        type: "social.post.comment",
        payloadChecks: { postId: state.userPostId },
      },
      "resident comment notification"
    );

    const postDetails = await request(
      baseUrl,
      userOne,
      "GET",
      `/api/feed/posts/${state.userPostId}`
    );
    assertStatus(postDetails, 200, "post details");
    assert.equal(Number(postDetails.data?.post?.commentsCount || 0), 1);

    const searchManagers = await request(
      baseUrl,
      admin,
      "GET",
      `/api/feed/communities/building/${scope.building}/users/search?search=&limit=100`
    );
    assertStatus(searchManagers, 200, "search community users");
    assert.ok(
      Array.isArray(searchManagers.data?.users) &&
        searchManagers.data.users.some(
          (item) => Number(item?.id || 0) === state.userTwoId
        ),
      "manager search should include resident two"
    );

    const assignManager = await request(
      baseUrl,
      admin,
      "POST",
      `/api/feed/communities/building/${scope.building}/managers`,
      {
        managerUserId: state.userTwoId,
      }
    );
    assertStatus(assignManager, 200, "assign manager");
    assert.ok(
      Array.isArray(assignManager.data?.managers) &&
        assignManager.data.managers.some(
          (item) => Number(item?.managerUserId || 0) === state.userTwoId
        )
    );

    await expectNotification(
      {
        userId: state.userTwoId,
        type: "social.community.manager.assigned",
        payloadChecks: { scopeCode: scope.building, managerUserId: state.userTwoId },
      },
      "manager assigned notification"
    );

    const managerCannotAssign = await request(
      baseUrl,
      userTwo,
      "POST",
      `/api/feed/communities/building/${scope.building}/managers`,
      {
        managerUserId: state.userOneId,
      }
    );
    assertStatus(managerCannotAssign, 403, "manager cannot assign");

    const announcementCreate = await request(
      baseUrl,
      userTwo,
      "POST",
      `/api/feed/communities/building/${scope.building}/announcements`,
      {
        title: `announcement-${runTag}`,
        body: `announcement-body-${runTag}`,
      }
    );
    assertStatus(announcementCreate, 201, "announcement create");

    await expectNotification(
      {
        userId: state.userOneId,
        type: "social.community.announcement.created",
        payloadChecks: { scopeCode: scope.building },
      },
      "announcement notification"
    );

    const chatMessage = await request(
      baseUrl,
      userTwo,
      "POST",
      `/api/feed/communities/building/${scope.building}/chat/messages`,
      {
        body: `chat-message-${runTag}`,
      }
    );
    assertStatus(chatMessage, 201, "chat message");

    await expectNotification(
      {
        userId: state.userOneId,
        type: "social.community.chat.message",
        payloadChecks: { scopeCode: scope.building },
      },
      "chat notification"
    );

    const lockChat = await request(
      baseUrl,
      userTwo,
      "PATCH",
      `/api/feed/communities/building/${scope.building}/chat/lock`,
      {
        locked: true,
      }
    );
    assertStatus(lockChat, 200, "lock chat");
    assert.equal(lockChat.data?.chatLocked, true);

    await expectNotification(
      {
        userId: state.userOneId,
        type: "social.community.chat.lock_updated",
        payloadChecks: { scopeCode: scope.building },
      },
      "chat lock notification"
    );

    const lockedSend = await request(
      baseUrl,
      userOne,
      "POST",
      `/api/feed/communities/building/${scope.building}/chat/messages`,
      {
        body: `locked-should-fail-${runTag}`,
      }
    );
    assertStatus(lockedSend, 403, "locked chat send");

    const unlockChat = await request(
      baseUrl,
      userTwo,
      "PATCH",
      `/api/feed/communities/building/${scope.building}/chat/lock`,
      {
        locked: false,
      }
    );
    assertStatus(unlockChat, 200, "unlock chat");
    assert.equal(unlockChat.data?.chatLocked, false);

    const moderationSearch = await request(
      baseUrl,
      userTwo,
      "GET",
      `/api/feed/communities/building/${scope.building}/chat/users?search=&limit=100`
    );
    assertStatus(moderationSearch, 200, "moderation search");
    assert.ok(
      Array.isArray(moderationSearch.data?.users) &&
        moderationSearch.data.users.some(
          (item) => Number(item?.id || 0) === state.userOneId
        )
    );

    const banUser = await request(
      baseUrl,
      userTwo,
      "POST",
      `/api/feed/communities/building/${scope.building}/chat/ban`,
      {
        userId: state.userOneId,
        reason: `ban-reason-${runTag}`,
      }
    );
    assertStatus(banUser, 200, "ban user");

    await expectNotification(
      {
        userId: state.userOneId,
        type: "social.community.chat.restricted",
        payloadChecks: { scopeCode: scope.building, restrictedUserId: state.userOneId },
      },
      "restricted notification"
    );

    const bannedSend = await request(
      baseUrl,
      userOne,
      "POST",
      `/api/feed/communities/building/${scope.building}/chat/messages`,
      {
        body: `banned-message-${runTag}`,
      }
    );
    assertStatus(bannedSend, 403, "banned chat send");

    const unbanUser = await request(
      baseUrl,
      userTwo,
      "DELETE",
      `/api/feed/communities/building/${scope.building}/chat/ban/${state.userOneId}`
    );
    assertStatus(unbanUser, 200, "unban user");

    await expectNotification(
      {
        userId: state.userOneId,
        type: "social.community.chat.restored",
        payloadChecks: { scopeCode: scope.building, restoredUserId: state.userOneId },
      },
      "restored notification"
    );

    const restoredSend = await request(
      baseUrl,
      userOne,
      "POST",
      `/api/feed/communities/building/${scope.building}/chat/messages`,
      {
        body: `restored-message-${runTag}`,
      }
    );
    assertStatus(restoredSend, 201, "restored chat send");

    const relationRequest = await request(
      baseUrl,
      userOne,
      "POST",
      `/api/feed/users/${state.userTwoId}/relation/request`
    );
    assertStatus(relationRequest, 201, "send relation request");

    const relationAccept = await request(
      baseUrl,
      userTwo,
      "POST",
      `/api/feed/users/${state.userOneId}/relation/accept`
    );
    assertStatus(relationAccept, 200, "accept relation request");

    const directThreadCreate = await request(
      baseUrl,
      userOne,
      "POST",
      "/api/feed/chats/threads",
      {
        userId: state.userTwoId,
      }
    );
    assertStatus(directThreadCreate, 201, "create direct thread");
    const directThreadId = readId(directThreadCreate.data?.thread);
    assert.ok(directThreadId, "direct thread id missing");

    const directMessage = await request(
      baseUrl,
      userOne,
      "POST",
      `/api/feed/chats/threads/${directThreadId}/messages`,
      {
        body: `direct-chat-${runTag}`,
      }
    );
    assertStatus(directMessage, 201, "send direct thread message");

    await expectNotification(
      {
        userId: state.userTwoId,
        type: "social.chat.message",
        payloadChecks: { threadId: directThreadId },
      },
      "direct chat notification"
    );

    const adminMonitorAll = await request(
      baseUrl,
      admin,
      "GET",
      "/api/feed/admin/chats/threads?kind=all&limit=100"
    );
    assertStatus(adminMonitorAll, 200, "admin monitor all chats");
    const allThreads = adminMonitorAll.data?.threads || [];
    const directMonitor = findMonitoredThread(
      allThreads,
      (item) => item?.kind === "direct" && Number(item?.threadId || 0) === directThreadId
    );
    const communityMonitor = findMonitoredThread(
      allThreads,
      (item) =>
        item?.kind === "community" &&
        String(item?.scopeType || "") === "building" &&
        String(item?.scopeCode || "") === scope.building
    );
    assert.ok(directMonitor, "admin monitor all should include direct chat");
    assert.ok(communityMonitor, "admin monitor all should include community chat");

    const adminMonitorDirect = await request(
      baseUrl,
      admin,
      "GET",
      "/api/feed/admin/chats/threads?kind=direct&limit=100"
    );
    assertStatus(adminMonitorDirect, 200, "admin monitor direct chats");
    assert.ok(
      Array.isArray(adminMonitorDirect.data?.threads) &&
        adminMonitorDirect.data.threads.some(
          (item) => item?.kind === "direct" && Number(item?.threadId || 0) === directThreadId
        ),
      "direct filter should include direct thread"
    );
    assert.ok(
      adminMonitorDirect.data.threads.every((item) => item?.kind === "direct"),
      "direct filter should only return direct chats"
    );

    const adminMonitorCommunity = await request(
      baseUrl,
      admin,
      "GET",
      "/api/feed/admin/chats/threads?kind=community&limit=100"
    );
    assertStatus(adminMonitorCommunity, 200, "admin monitor community chats");
    assert.ok(
      Array.isArray(adminMonitorCommunity.data?.threads) &&
        adminMonitorCommunity.data.threads.some(
          (item) =>
            item?.kind === "community" &&
            String(item?.scopeType || "") === "building" &&
            String(item?.scopeCode || "") === scope.building
        ),
      "community filter should include building chat"
    );
    assert.ok(
      adminMonitorCommunity.data.threads.every((item) => item?.kind === "community"),
      "community filter should only return community chats"
    );

    const adminDirectMessages = await request(
      baseUrl,
      admin,
      "GET",
      `/api/feed/admin/chats/threads/${directThreadId}/messages?limit=40`
    );
    assertStatus(adminDirectMessages, 200, "admin direct thread messages");
    assert.ok(
      Array.isArray(adminDirectMessages.data?.messages) &&
        adminDirectMessages.data.messages.some(
          (item) => String(item?.body || "") === `direct-chat-${runTag}`
        ),
      "admin direct monitor should expose direct message body"
    );

    const adminCommunityMessages = await request(
      baseUrl,
      admin,
      "GET",
      `/api/feed/admin/chats/community/building/${scope.building}/messages?limit=60`
    );
    assertStatus(adminCommunityMessages, 200, "admin community messages");
    assert.ok(
      Array.isArray(adminCommunityMessages.data?.messages) &&
        adminCommunityMessages.data.messages.some(
          (item) => String(item?.body || "") === `chat-message-${runTag}`
        ),
      "admin community monitor should expose community message body"
    );

    const createBill = await request(
      baseUrl,
      userTwo,
      "POST",
      `/api/feed/communities/building/${scope.building}/bills`,
      {
        category: "water",
        title: `bill-${runTag}`,
        amount: 25000,
        dueDate: "2026-12-31",
        apartment: "101",
        details: `bill-details-${runTag}`,
      }
    );
    assertStatus(createBill, 201, "create bill");

    await expectNotification(
      {
        userId: state.userOneId,
        type: "social.community.bill.created",
        payloadChecks: { scopeCode: scope.building },
      },
      "bill notification"
    );

    let revokeManager = await request(
      baseUrl,
      admin,
      "DELETE",
      `/api/feed/communities/building/${scope.building}/managers/${state.userTwoId}`
    );
    if (revokeManager.status === 401) {
      const adminRelogin = await request(baseUrl, admin, "POST", "/api/auth/login", {
        phone: env.superAdminPhone,
        pin: env.superAdminPin,
      });
      assertStatus(adminRelogin, 200, "admin re-login");
      admin.token = String(adminRelogin.data?.token || "");
      admin.sessionId = Number(adminRelogin.data?.sessionId || 0) || null;
      if (admin.sessionId) {
        state.adminSessionIds.push(admin.sessionId);
      }

      revokeManager = await request(
        baseUrl,
        admin,
        "DELETE",
        `/api/feed/communities/building/${scope.building}/managers/${state.userTwoId}`
      );
    }
    assertStatus(revokeManager, 200, "revoke manager");
    assert.ok(
      Array.isArray(revokeManager.data?.managers) &&
        !revokeManager.data.managers.some(
          (item) => Number(item?.managerUserId || 0) === state.userTwoId
        )
    );

    await expectNotification(
      {
        userId: state.userTwoId,
        type: "social.community.manager.revoked",
        payloadChecks: { scopeCode: scope.building, managerUserId: state.userTwoId },
      },
      "manager revoked notification"
    );

    const announcementAfterRevoke = await request(
      baseUrl,
      userTwo,
      "POST",
      `/api/feed/communities/building/${scope.building}/announcements`,
      {
        title: `after-revoke-${runTag}`,
        body: `after-revoke-body-${runTag}`,
      }
    );
    assertStatus(announcementAfterRevoke, 403, "revoked manager cannot announce");

    console.log(
      `[community-e2e] passed building=${scope.building} residentPostId=${state.userPostId}`
    );
  } finally {
    try {
      await cleanup(state);
    } finally {
      await stopLocalServer(server);
      await pool.end();
    }
  }
}

main()
  .then(() => {
    process.exit(0);
  })
  .catch((error) => {
    console.error("[community-e2e] failed", error);
    process.exit(1);
  });

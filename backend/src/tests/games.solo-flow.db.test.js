import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import { q } from "../config/db.js";
import {
  claimReward,
  createGame,
  getRoomSnapshot,
  requestSoloHint,
  submitSoloCode,
} from "../modules/games/games.service.js";

test("team code solo journey completes three server-owned rounds and claims once", async (t) => {
  const marker = randomUUID().replaceAll("-", "").slice(0, 12);
  const user = await q(
    `INSERT INTO app_user
       (full_name,phone,pin_hash,block,building_number,apartment,username,role)
     VALUES ($1,$2,'x','A','1','1',$3,'user') RETURNING id`,
    [`game ${marker}`, `077${marker.replace(/\D/g, "").padEnd(8, "7").slice(0, 8)}`, `game_${marker}`],
  );
  const userId = Number(user.rows[0].id);
  let roomId = null;
  let claimed = false;
  t.after(async () => {
    if (claimed) {
      await q(
        `UPDATE game_campaign SET claimed_count=GREATEST(0,claimed_count-1)
         WHERE campaign_key='team_code_test'`,
      ).catch(() => null);
    }
    await q(`DELETE FROM app_user WHERE id=$1`, [userId]).catch(() => null);
  });

  let snapshot = await createGame(userId, "solo");
  roomId = snapshot.room.id;
  assert.equal(snapshot.room.mode, "solo");
  assert.equal(snapshot.session.currentRoundIndex, 1);
  assert.equal(snapshot.round.clues.length >= 5, true);
  assert.equal(JSON.stringify(snapshot).includes("solution_code"), false);
  assert.equal(JSON.stringify(snapshot).includes("solutionCode"), false);

  const hintCommand = `solo-hint-${marker}`;
  snapshot = await requestSoloHint(userId, roomId, hintCommand);
  snapshot = await requestSoloHint(userId, roomId, hintCommand);
  assert.equal(snapshot.round.hintsUsed, 1);

  for (let index = 1; index <= 3; index += 1) {
    const solution = await q(
      `SELECT pv.solution_code
       FROM game_session gs JOIN game_round gr ON gr.session_id=gs.id
       JOIN game_puzzle_version pv ON pv.id=gr.puzzle_version_id
       WHERE gs.room_id=$1 AND gr.round_index=$2`,
      [roomId, index],
    );
    snapshot = await submitSoloCode(userId, roomId, {
      code: solution.rows[0].solution_code,
      commandId: `solo-test-${index}-${marker}`,
    });
    if (index === 1) {
      assert.equal(snapshot.me.rewardEligible, true);
      const reward = await claimReward(userId, snapshot.session.id);
      claimed = true;
      assert.equal(reward.payload.mock, true);
      assert.equal(reward.payload.label, "غير قابلة للاستخدام");
    }
  }

  assert.equal(snapshot.room.status, "completed");
  assert.equal(snapshot.session.status, "completed");
  assert.equal(snapshot.results.length, 3);
  assert.equal(snapshot.results.every((item) => item.solutionCode), true);
  assert.equal(snapshot.me.rewardEligible, true);

  await assert.rejects(() => claimReward(userId, snapshot.session.id), /GAME_REWARD_ALREADY_CLAIMED/);

  const restored = await getRoomSnapshot(roomId, userId);
  assert.equal(restored.results.length, 3);
});

test("server expires a round after its authoritative countdown", async (t) => {
  const marker = randomUUID().replaceAll("-", "").slice(0, 12);
  const user = await q(
    `INSERT INTO app_user
       (full_name,phone,pin_hash,block,building_number,apartment,username,role)
     VALUES ($1,$2,'x','A','1','1',$3,'user') RETURNING id`,
    [`timer ${marker}`, `076${marker.replace(/\D/g, "").padEnd(8, "5").slice(0, 8)}`, `timer_${marker}`],
  );
  const userId = Number(user.rows[0].id);
  t.after(async () => {
    await q(`DELETE FROM app_user WHERE id=$1`, [userId]).catch(() => null);
  });

  let snapshot = await createGame(userId, "solo");
  assert.equal(snapshot.round.timeLimitSeconds, 150);
  assert.equal(snapshot.round.remainingSeconds > 0, true);
  await q(
    `UPDATE game_round SET started_at=NOW()-INTERVAL '151 seconds'
     WHERE id=$1`,
    [snapshot.round.id],
  );

  await assert.rejects(
    () => submitSoloCode(userId, snapshot.room.id, {
      code: "123",
      commandId: `expired-${marker}`,
    }),
    /GAME_ROUND_TIMED_OUT/,
  );
  snapshot = await getRoomSnapshot(snapshot.room.id, userId);
  assert.equal(snapshot.room.status, "failed");
  assert.equal(snapshot.session.status, "failed");
  assert.equal(snapshot.round.status, "failed");
  assert.equal(snapshot.round.failureReason, "timeout");
  assert.equal(snapshot.round.remainingSeconds, 0);
});

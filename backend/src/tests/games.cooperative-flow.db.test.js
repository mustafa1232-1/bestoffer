import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import { q } from "../config/db.js";
import {
  createGame,
  createProposal,
  getRoomSnapshot,
  joinRoom,
  leaveRoom,
  listMyGameHistory,
  sendMessage,
  setReady,
  startRoom,
  voteProposal,
} from "../modules/games/games.service.js";

async function createUser(prefix) {
  const marker = randomUUID().replaceAll("-", "").slice(0, 12);
  const result = await q(
    `INSERT INTO app_user
       (full_name,phone,pin_hash,block,building_number,apartment,username,role)
     VALUES ($1,$2,'x','A','1','1',$3,'user') RETURNING id`,
    [
      `${prefix} ${marker}`,
      `078${marker.replace(/\D/g, "").padEnd(8, "6").slice(0, 8)}`,
      `game_${marker}`,
    ],
  );
  return Number(result.rows[0].id);
}

function wrongCode(solution) {
  const digits = solution.split("");
  const available = "0123456789".split("").find((digit) => !digits.includes(digit));
  return `${available}${digits.slice(1).join("")}`;
}

async function solutionFor(roomId, roundIndex) {
  const result = await q(
    `SELECT pv.solution_code
     FROM game_session gs
     JOIN game_round gr ON gr.session_id=gs.id
     JOIN game_puzzle_version pv ON pv.id=gr.puzzle_version_id
     WHERE gs.room_id=$1 AND gr.round_index=$2`,
    [roomId, roundIndex],
  );
  return result.rows[0].solution_code;
}

test("cooperative team code keeps clues private and resolves only unanimous proposals", async (t) => {
  const hostId = await createUser("game_host");
  const guestId = await createUser("game_guest");
  t.after(async () => {
    await q(`DELETE FROM app_user WHERE id=ANY($1::bigint[])`, [[hostId, guestId]]).catch(
      () => null,
    );
  });

  let host = await createGame(hostId, "cooperative");
  const roomId = host.room.id;
  const guestLobby = await joinRoom(guestId, host.room.inviteCode);
  assert.equal(guestLobby.room.id, roomId);

  await setReady(hostId, roomId, true);
  await setReady(guestId, roomId, true);
  host = await startRoom(hostId, roomId);
  const guest = await getRoomSnapshot(roomId, guestId);

  const hostIndexes = new Set(host.round.clues.map((clue) => clue.index));
  const guestIndexes = new Set(guest.round.clues.map((clue) => clue.index));
  assert.equal(hostIndexes.size > 0, true);
  assert.equal(guestIndexes.size > 0, true);
  assert.equal([...hostIndexes].some((index) => guestIndexes.has(index)), false);
  assert.equal(JSON.stringify(host).includes("solutionCode"), false);
  assert.equal(JSON.stringify(guest).includes("solutionCode"), false);

  await sendMessage(hostId, roomId, "جرّبوا ترتيب الأدلة");
  const withMessage = await getRoomSnapshot(roomId, guestId);
  assert.equal(withMessage.messages.at(-1).body, "جرّبوا ترتيب الأدلة");

  const firstSolution = await solutionFor(roomId, 1);
  const beforeReject = host.round.attemptsRemaining;
  host = await createProposal(hostId, roomId, {
    kind: "code",
    code: wrongCode(firstSolution),
    commandId: `reject-${randomUUID()}`,
  });
  await voteProposal(guestId, roomId, host.proposal.id, "reject");
  host = await getRoomSnapshot(roomId, hostId);
  assert.equal(host.round.attemptsRemaining, beforeReject);
  assert.equal(host.proposal, null);

  host = await createProposal(hostId, roomId, {
    kind: "code",
    code: wrongCode(firstSolution),
    commandId: `wrong-${randomUUID()}`,
  });
  await voteProposal(guestId, roomId, host.proposal.id, "approve");
  host = await getRoomSnapshot(roomId, hostId);
  assert.equal(host.round.attemptsRemaining, beforeReject - 1);

  for (let roundIndex = 1; roundIndex <= 3; roundIndex += 1) {
    const solution = await solutionFor(roomId, roundIndex);
    host = await createProposal(hostId, roomId, {
      kind: "code",
      code: solution,
      commandId: `solve-${roundIndex}-${randomUUID()}`,
    });
    host = await voteProposal(guestId, roomId, host.proposal.id, "approve");
  }

  assert.equal(host.room.status, "completed");
  assert.equal(host.session.status, "completed");
  assert.equal(host.results.length, 3);
  assert.equal(host.results.every((result) => result.solutionCode), true);
  const guestResult = await getRoomSnapshot(roomId, guestId);
  assert.equal(guestResult.me.rewardEligible, true);
});

test("host departure transfers ownership and preserves every clue for the remaining player", async (t) => {
  const hostId = await createUser("departing_host");
  const guestId = await createUser("remaining_guest");
  t.after(async () => {
    await q(`DELETE FROM app_user WHERE id=ANY($1::bigint[])`, [[hostId, guestId]]).catch(
      () => null,
    );
  });

  let snapshot = await createGame(hostId, "cooperative");
  const roomId = snapshot.room.id;
  await joinRoom(guestId, snapshot.room.inviteCode);
  await setReady(hostId, roomId, true);
  await setReady(guestId, roomId, true);
  await startRoom(hostId, roomId);

  await leaveRoom(hostId, roomId);
  const hostHistory = await listMyGameHistory(hostId);
  assert.equal(
    hostHistory.find((item) => item.roomId === roomId)?.canOpen,
    false,
  );
  snapshot = await getRoomSnapshot(roomId, guestId);
  const clueCount = await q(
    `SELECT jsonb_array_length(pv.clues_json)::int count
     FROM game_session gs
     JOIN game_round gr ON gr.session_id=gs.id AND gr.round_index=gs.current_round_index
     JOIN game_puzzle_version pv ON pv.id=gr.puzzle_version_id
     WHERE gs.room_id=$1`,
    [roomId],
  );
  assert.equal(snapshot.room.hostUserId, guestId);
  assert.equal(snapshot.members.length, 1);
  assert.equal(snapshot.round.clues.length, Number(clueCount.rows[0].count));
});

test("empty cooperative room resumes inside grace window and expires after ten minutes", async (t) => {
  const hostId = await createUser("resume_host");
  const guestId = await createUser("resume_guest");
  t.after(async () => {
    await q(`DELETE FROM app_user WHERE id=ANY($1::bigint[])`, [[hostId, guestId]]).catch(
      () => null,
    );
  });

  let snapshot = await createGame(hostId, "cooperative");
  const roomId = snapshot.room.id;
  await joinRoom(guestId, snapshot.room.inviteCode);
  await setReady(hostId, roomId, true);
  await setReady(guestId, roomId, true);
  await startRoom(hostId, roomId);

  await q(
    `UPDATE game_membership SET
       last_seen_at=NOW()-INTERVAL '4 minutes',
       disconnected_at=NOW()-INTERVAL '121 seconds'
     WHERE room_id=$1`,
    [roomId],
  );
  snapshot = await getRoomSnapshot(roomId, hostId);
  assert.equal(snapshot.room.status, "active");
  assert.equal(
    snapshot.members.find((member) => member.userId === guestId).isActive,
    false,
  );

  await q(
    `UPDATE game_room SET status='paused',paused_at=NOW()-INTERVAL '11 minutes'
     WHERE id=$1`,
    [roomId],
  );
  await q(
    `UPDATE game_session SET status='paused' WHERE room_id=$1`,
    [roomId],
  );
  snapshot = await getRoomSnapshot(roomId, hostId);
  assert.equal(snapshot.room.status, "abandoned");
  assert.equal(snapshot.session.status, "abandoned");
});

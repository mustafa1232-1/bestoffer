import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import { q } from "../config/db.js";
import {
  advanceMafiaRoom,
  closeMafiaRoom,
  createMafiaRoom,
  getMafiaSnapshot,
  getMafiaVoiceAccess,
  joinMafiaRoom,
  kickMafiaPlayer,
  reactivateMafiaRoom,
  reportMafiaPlayer,
  sendMafiaInteraction,
  setMafiaReady,
  startMafiaRoom,
  submitMafiaAction,
} from "../modules/games/mafia.service.js";

async function createUser(index) {
  const marker = randomUUID().replaceAll("-", "").slice(0, 10);
  const result = await q(
    `INSERT INTO app_user
       (full_name,phone,pin_hash,block,building_number,apartment,username,role)
     VALUES ($1,$2,'x','A','1','1',$3,'user') RETURNING id`,
    [`Mafia QA ${index}`, `075${String(Date.now() + index).slice(-8)}`, `mafia_${marker}`],
  );
  return Number(result.rows[0].id);
}

test("mafia room runs reveal, first night, nomination, defense and elimination", async (t) => {
  const users = [];
  for (let index = 0; index < 7; index += 1) users.push(await createUser(index));
  t.after(async () => {
    await q(`DELETE FROM app_user WHERE id=ANY($1::bigint[])`, [users]).catch(() => null);
  });

  let host = await createMafiaRoom(users[0], { ruleset: "standard", maxPlayers: 14 });
  const roomId = host.room.id;
  for (const userId of users.slice(1)) await joinMafiaRoom(userId, host.room.inviteCode);
  for (const userId of users) await setMafiaReady(userId, roomId, true);

  host = await startMafiaRoom(users[0], roomId);
  assert.equal(host.room.status, "role_reveal");
  assert.equal(host.players.length, 7);
  assert.equal(host.players.filter((player) => player.role != null).length, 1);
  assert.ok(host.mission?.title);
  assert.equal(host.mission?.completed, false);
  assert.equal(host.narrator?.tone, "guide");
  assert.equal(host.profile?.gamesPlayed, 0);

  await advanceMafiaRoom(roomId, { force: true });
  let snapshot = await getMafiaSnapshot(roomId, users[0]);
  assert.equal(snapshot.room.status, "night");
  assert.equal(snapshot.room.dayNumber, 0);

  await advanceMafiaRoom(roomId, { force: true });
  snapshot = await getMafiaSnapshot(roomId, users[0]);
  assert.equal(snapshot.room.status, "day_discussion");
  assert.equal(snapshot.room.dayNumber, 1);

  await advanceMafiaRoom(roomId, { force: true });
  const target = await q(
    `SELECT id FROM mafia_player WHERE room_id=$1 AND user_id<>$2 ORDER BY seat_number LIMIT 1`,
    [roomId, users[0]],
  );
  const targetId = Number(target.rows[0].id);
  for (const [index, userId] of users.entries()) {
    const me = await getMafiaSnapshot(roomId, userId);
    if (me.me.playerId === targetId) continue;
    await submitMafiaAction(userId, roomId, {
      type: "nominate",
      targetPlayerId: targetId,
      commandId: `nominate-${index}-${randomUUID()}`,
    });
  }
  await advanceMafiaRoom(roomId, { force: true });
  snapshot = await getMafiaSnapshot(roomId, users[0]);
  assert.equal(snapshot.room.status, "day_defense");
  assert.deepEqual(snapshot.phase.candidateIds, [targetId]);

  await advanceMafiaRoom(roomId, { force: true });
  for (const [index, userId] of users.entries()) {
    const me = await getMafiaSnapshot(roomId, userId);
    if (me.me.lifeStatus !== "alive" || me.me.playerId === targetId) continue;
    await submitMafiaAction(userId, roomId, {
      type: "vote",
      targetPlayerId: targetId,
      commandId: `vote-${index}-${randomUUID()}`,
    });
  }
  await advanceMafiaRoom(roomId, { force: true });
  snapshot = await getMafiaSnapshot(roomId, users[0]);
  const eliminated = snapshot.players.find((player) => player.playerId === targetId);
  assert.equal(eliminated.lifeStatus, "dead");
  assert.equal(["night", "completed"].includes(snapshot.room.status), true);
});

test("completed rooms accept one MVP honor per player and expose the summary", async (t) => {
  const users = [await createUser(170), await createUser(171)];
  t.after(async () => {
    await q(`DELETE FROM mafia_room WHERE host_user_id=$1`, [users[0]]).catch(() => null);
    await q(`DELETE FROM app_user WHERE id=ANY($1::bigint[])`, [users]).catch(() => null);
  });

  const created = await createMafiaRoom(users[0], {
    ruleset: "standard",
    pace: "quick",
    maxPlayers: 14,
  });
  const joined = await joinMafiaRoom(users[1], created.room.inviteCode);
  const target = joined.players.find((player) => player.userId === users[1]);
  await q(
    `UPDATE mafia_room SET status='completed',winner='town',completed_at=NOW(),phase_ends_at=NULL
     WHERE id=$1`,
    [created.room.id],
  );
  await sendMafiaInteraction(users[0], created.room.id, {
    kind: "mvp",
    interactionType: "honor",
    targetPlayerId: target.playerId,
    commandId: `honor-${randomUUID()}`,
  });
  await assert.rejects(
    () => sendMafiaInteraction(users[0], created.room.id, {
      kind: "mvp",
      interactionType: "honor",
      targetPlayerId: target.playerId,
      commandId: `honor-${randomUUID()}`,
    }),
    (error) => error?.code === "MAFIA_HONOR_ALREADY_CAST",
  );
  const snapshot = await getMafiaSnapshot(created.room.id, users[0]);
  assert.equal(snapshot.summary.myHonorPlayerId, target.playerId);
  assert.equal(snapshot.summary.honors[0].playerId, target.playerId);
  assert.equal(snapshot.profile.gamesPlayed, 1);
  assert.equal(snapshot.room.settings.pace, "quick");
});

test("advanced night applies bodyguard sacrifice and framer deception", async (t) => {
  const users = [];
  for (let index = 0; index < 14; index += 1) users.push(await createUser(index + 20));
  t.after(async () => {
    await q(`DELETE FROM app_user WHERE id=ANY($1::bigint[])`, [users]).catch(() => null);
  });

  const created = await createMafiaRoom(users[0], {
    ruleset: "advanced",
    maxPlayers: 14,
  });
  const roomId = created.room.id;
  for (const userId of users.slice(1)) await joinMafiaRoom(userId, created.room.inviteCode);
  for (const userId of users) await setMafiaReady(userId, roomId, true);
  await startMafiaRoom(users[0], roomId);

  // Reveal -> coordination night -> first day -> empty nomination -> actionable night.
  await advanceMafiaRoom(roomId, { force: true });
  await advanceMafiaRoom(roomId, { force: true });
  await advanceMafiaRoom(roomId, { force: true });
  await advanceMafiaRoom(roomId, { force: true });

  const rows = (await q(
    `SELECT id,user_id,role,team,life_status FROM mafia_player WHERE room_id=$1`,
    [roomId],
  )).rows;
  const bodyguard = rows.find((player) => player.role === "bodyguard");
  const detective = rows.find((player) => player.role === "detective");
  const framer = rows.find((player) => player.role === "framer");
  const citizens = rows.filter((player) => player.role === "citizen");
  const protectedCitizen = citizens[0];
  const framedCitizen = citizens[1];
  assert.ok(bodyguard && detective && framer && protectedCitizen && framedCitizen);
  const mafiaPlayer = rows.find((player) => player.team === "mafia");
  const mafiaView = await getMafiaSnapshot(roomId, Number(mafiaPlayer.user_id));
  assert.equal(mafiaView.me.mafiaTeammateIds.length, 4);
  assert.equal(mafiaView.me.mafiaTeammateIds.includes(Number(mafiaPlayer.id)), true);

  for (const killer of rows.filter((player) => player.team === "mafia")) {
    await submitMafiaAction(Number(killer.user_id), roomId, {
      type: "mafia_kill",
      targetPlayerId: Number(protectedCitizen.id),
      commandId: `kill-${killer.id}-${randomUUID()}`,
    });
  }
  await submitMafiaAction(Number(bodyguard.user_id), roomId, {
    type: "bodyguard_protect",
    targetPlayerId: Number(protectedCitizen.id),
    commandId: `guard-${randomUUID()}`,
  });
  await submitMafiaAction(Number(framer.user_id), roomId, {
    type: "framer_frame",
    targetPlayerId: Number(framedCitizen.id),
    commandId: `frame-${randomUUID()}`,
  });
  await submitMafiaAction(Number(detective.user_id), roomId, {
    type: "detective_inspect",
    targetPlayerId: Number(framedCitizen.id),
    commandId: `inspect-${randomUUID()}`,
  });

  await advanceMafiaRoom(roomId, { force: true });
  const protectedState = await q(`SELECT life_status FROM mafia_player WHERE id=$1`, [protectedCitizen.id]);
  const guardState = await q(`SELECT life_status,eliminated_reason FROM mafia_player WHERE id=$1`, [bodyguard.id]);
  assert.equal(protectedState.rows[0].life_status, "alive");
  assert.equal(guardState.rows[0].life_status, "dead");
  assert.equal(guardState.rows[0].eliminated_reason, "bodyguard_sacrifice");

  const detectiveView = await getMafiaSnapshot(roomId, Number(detective.user_id));
  const result = detectiveView.events.find((event) => event.type === "investigation_result");
  assert.equal(result?.payload?.targetPlayerId, Number(framedCitizen.id));
  assert.equal(result?.payload?.isMafia, true);
});

test("only the host can kick lobby players and close the room", async (t) => {
  const users = [];
  for (let index = 0; index < 3; index += 1) users.push(await createUser(index + 80));
  t.after(async () => {
    await q(`DELETE FROM mafia_room WHERE host_user_id=ANY($1::bigint[])`, [users]).catch(() => null);
    await q(`DELETE FROM app_user WHERE id=ANY($1::bigint[])`, [users]).catch(() => null);
  });

  const created = await createMafiaRoom(users[0], { ruleset: "standard", maxPlayers: 14 });
  const roomId = created.room.id;
  await joinMafiaRoom(users[1], created.room.inviteCode);
  const joined = await joinMafiaRoom(users[2], created.room.inviteCode);
  const hostPlayer = joined.players.find((player) => player.userId === users[0]);
  const kickedPlayer = joined.players.find((player) => player.userId === users[2]);

  await assert.rejects(
    () => kickMafiaPlayer(users[1], roomId, kickedPlayer.playerId),
    (error) => error?.code === "MAFIA_HOST_REQUIRED",
  );
  await assert.rejects(
    () => kickMafiaPlayer(users[0], roomId, hostPlayer.playerId),
    (error) => error?.code === "MAFIA_HOST_CANNOT_KICK_SELF",
  );

  const afterKick = await kickMafiaPlayer(users[0], roomId, kickedPlayer.playerId);
  assert.equal(afterKick.players.some((player) => player.userId === users[2]), false);
  await assert.rejects(
    () => joinMafiaRoom(users[2], created.room.inviteCode),
    (error) => error?.code === "MAFIA_PLAYER_KICKED",
  );

  const reaction = await sendMafiaInteraction(users[0], roomId, {
    kind: "laugh",
    interactionType: "reaction",
    targetPlayerId: null,
    commandId: `reaction-${randomUUID()}`,
  });
  assert.equal(reaction.event.payload.kind, "laugh");
  const gift = await sendMafiaInteraction(users[1], roomId, {
    kind: "rose",
    interactionType: "gift",
    targetPlayerId: hostPlayer.playerId,
    commandId: `gift-${randomUUID()}`,
  });
  assert.equal(gift.event.payload.targetPlayerId, hostPlayer.playerId);
  const report = await reportMafiaPlayer(users[1], roomId, {
    targetPlayerId: hostPlayer.playerId,
    reason: "inappropriate_audio",
    details: "QA report",
    commandId: `report-${randomUUID()}`,
  });
  assert.equal(report.duplicate, false);
  const duplicateReport = await reportMafiaPlayer(users[1], roomId, {
    targetPlayerId: hostPlayer.playerId,
    reason: "spam",
    details: null,
    commandId: `report-${randomUUID()}`,
  });
  assert.equal(duplicateReport.duplicate, true);
  await assert.rejects(
    () => closeMafiaRoom(users[1], roomId),
    (error) => error?.code === "MAFIA_HOST_REQUIRED",
  );

  const closed = await closeMafiaRoom(users[0], roomId);
  assert.equal(closed.room.status, "cancelled");
  assert.equal(closed.players.every((player) => player.lifeStatus === "left"), true);

  const reactivated = await reactivateMafiaRoom(users[0], roomId, {
    ruleset: "advanced",
    maxPlayers: 14,
    revealRolesOnDeath: true,
  });
  assert.notEqual(reactivated.room.id, roomId);
  assert.equal(reactivated.room.ruleset, "advanced");
  assert.equal(reactivated.room.status, "lobby");

  const replacement = await createMafiaRoom(users[2], { ruleset: "standard", maxPlayers: 14 });
  assert.notEqual(replacement.room.id, roomId);
  assert.equal(replacement.room.status, "lobby");
});

test("host kick during a live round removes gameplay and voice access", async (t) => {
  const users = [];
  for (let index = 0; index < 7; index += 1) users.push(await createUser(index + 100));
  t.after(async () => {
    await q(`DELETE FROM mafia_room WHERE host_user_id=ANY($1::bigint[])`, [users]).catch(() => null);
    await q(`DELETE FROM app_user WHERE id=ANY($1::bigint[])`, [users]).catch(() => null);
  });

  const created = await createMafiaRoom(users[0], { ruleset: "standard", maxPlayers: 14 });
  const roomId = created.room.id;
  for (const userId of users.slice(1)) await joinMafiaRoom(userId, created.room.inviteCode);
  for (const userId of users) await setMafiaReady(userId, roomId, true);
  await startMafiaRoom(users[0], roomId);

  const targetResult = await q(
    `SELECT id,user_id FROM mafia_player
     WHERE room_id=$1 AND user_id<>$2 AND team='town'
     ORDER BY seat_number LIMIT 1`,
    [roomId, users[0]],
  );
  const target = targetResult.rows[0];
  assert.ok(target);

  // A connected player cannot be removed once the game runs (outcome abuse).
  await assert.rejects(
    () => kickMafiaPlayer(users[0], roomId, Number(target.id)),
    (error) => error?.code === "MAFIA_KICK_ACTIVE_PLAYER_FORBIDDEN",
  );
  // Once they stop responding, the host may free the seat.
  await q(`UPDATE mafia_player SET last_seen_at=NOW()-INTERVAL '2 minutes' WHERE id=$1`, [target.id]);
  const snapshot = await kickMafiaPlayer(users[0], roomId, Number(target.id));
  const kicked = snapshot.players.find((player) => player.playerId === Number(target.id));
  assert.equal(kicked.lifeStatus, "left");
  assert.equal(snapshot.room.settings.kickedUserIds.includes(Number(target.user_id)), true);
  await assert.rejects(
    () => getMafiaSnapshot(roomId, Number(target.user_id)),
    (error) => error?.code === "MAFIA_ROOM_FORBIDDEN",
  );
  await assert.rejects(
    () => getMafiaVoiceAccess(Number(target.user_id), roomId),
    (error) => error?.code === "MAFIA_ROOM_FORBIDDEN",
  );
});

test("fair play: votes settle early, the eliminated cannot signal, a running game cannot be cancelled", async (t) => {
  const users = [];
  for (let index = 0; index < 7; index += 1) users.push(await createUser(index + 300));
  t.after(async () => {
    await q(`DELETE FROM mafia_room WHERE host_user_id=ANY($1::bigint[])`, [users]).catch(() => null);
    await q(`DELETE FROM app_user WHERE id=ANY($1::bigint[])`, [users]).catch(() => null);
  });
  const created = await createMafiaRoom(users[0], { ruleset: "standard", maxPlayers: 14 });
  const roomId = created.room.id;
  for (const userId of users.slice(1)) await joinMafiaRoom(userId, created.room.inviteCode);
  for (const userId of users) await setMafiaReady(userId, roomId, true);
  await startMafiaRoom(users[0], roomId);
  await assert.rejects(() => closeMafiaRoom(users[0], roomId), (error) => error?.code === "MAFIA_GAME_IN_PROGRESS");

  await advanceMafiaRoom(roomId, { force: true }); // night 0
  await advanceMafiaRoom(roomId, { force: true }); // day 1 discussion
  await advanceMafiaRoom(roomId, { force: true }); // nomination
  const players = (await q(`SELECT id,user_id FROM mafia_player WHERE room_id=$1 ORDER BY seat_number`, [roomId])).rows;
  const target = players[1];
  const before = (await q(`SELECT phase_ends_at FROM mafia_room WHERE id=$1`, [roomId])).rows[0].phase_ends_at;
  for (const [index, player] of players.entries()) {
    await submitMafiaAction(Number(player.user_id), roomId, {
      type: "nominate",
      targetPlayerId: Number(player.id === target.id ? players[2].id : target.id),
      commandId: `settle-${index}-${randomUUID()}`,
    });
  }
  const after = (await q(
    `SELECT phase_ends_at,EXTRACT(EPOCH FROM phase_ends_at-clock_timestamp()) AS left_s FROM mafia_room WHERE id=$1`,
    [roomId],
  )).rows[0];
  // Everyone decided: the remaining nomination time collapses to a short settle.
  assert.ok(new Date(after.phase_ends_at) < new Date(before));
  assert.ok(Number(after.left_s) <= 1.2, `left ${after.left_s}s`);

  await q(`UPDATE mafia_player SET life_status='dead' WHERE id=$1`, [target.id]);
  await assert.rejects(
    () => sendMafiaInteraction(Number(target.user_id), roomId, {
      interactionType: "gift", kind: "rose", commandId: `ghost-${randomUUID()}`, targetPlayerId: Number(players[2].id),
    }),
    (error) => error?.code === "MAFIA_ELIMINATED_CANNOT_INTERACT",
  );
});

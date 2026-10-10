import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import { q } from "../config/db.js";
import {
  closeKnowledgeRoom,
  createDuel,
  getKnowledgeRoom,
  joinKnowledgeRoomSeat,
  lookupKnowledgeRoom,
  reactivateKnowledgeRoom,
} from "../modules/games/knowledge.service.js";

async function makeUser(marker, slot) {
  const result = await q(
    `INSERT INTO app_user
       (full_name,phone,pin_hash,block,building_number,apartment,username,role)
     VALUES ($1,$2,'x','A','1','1',$3,'user') RETURNING id`,
    [`knowledge_room_${marker}_${slot}`, `078${marker.slice(0, 8)}${slot}`, `kroom_${marker}_${slot}`],
  );
  return Number(result.rows[0].id);
}

test("knowledge duel room seats players by side and starts only at even capacity", async (t) => {
  const marker = randomUUID().replaceAll("-", "").slice(0, 8);
  const users = await Promise.all([0, 1, 2, 3].map((slot) => makeUser(marker, slot)));
  const created = await createDuel(users[0], { teamSize: 2, isPrivate: false });
  const eventId = created.eventId;
  t.after(async () => {
    await q("DELETE FROM maslaki_quiz_event WHERE id=$1", [eventId]).catch(() => null);
    await q("DELETE FROM app_user WHERE id=ANY($1::bigint[])", [users]).catch(() => null);
  });

  const lobby = await getKnowledgeRoom(users[0], eventId);
  assert.equal(lobby.totalSeats, 4);
  assert.equal(lobby.occupiedSeats, 0);
  assert.equal(lobby.status, "registration");

  await joinKnowledgeRoomSeat(users[0], eventId, "a");
  await joinKnowledgeRoomSeat(users[1], eventId, "a");
  await joinKnowledgeRoomSeat(users[2], eventId, "b");
  const oddLobby = await getKnowledgeRoom(users[2], eventId);
  assert.equal(oddLobby.occupiedSeats, 3);
  assert.equal(oddLobby.status, "registration");

  const fullLobby = await joinKnowledgeRoomSeat(users[3], eventId, "b");
  assert.equal(fullLobby.occupiedSeats, 4);
  assert.equal(fullLobby.status, "active");
  const match = await q("SELECT status FROM maslaki_quiz_match WHERE event_id=$1", [eventId]);
  assert.equal(match.rows[0]?.status, "pending");
});

test("private rooms require their code, and closed rooms are owner-only until reactivated", async (t) => {
  const marker = randomUUID().replaceAll("-", "").slice(0, 8);
  const ownerId = await makeUser(marker, 0);
  const guestId = await makeUser(marker, 1);
  const created = await createDuel(ownerId, { teamSize: 1, isPrivate: true });
  const eventId = created.eventId;
  t.after(async () => {
    await q("DELETE FROM maslaki_quiz_event WHERE id=$1", [eventId]).catch(() => null);
    await q("DELETE FROM app_user WHERE id=ANY($1::bigint[])", [[ownerId, guestId]]).catch(() => null);
  });

  await assert.rejects(getKnowledgeRoom(guestId, eventId), /ROOM_NOT_FOUND/);
  await assert.rejects(joinKnowledgeRoomSeat(guestId, eventId, "b"), /ROOM_NOT_FOUND/);
  const invitation = await lookupKnowledgeRoom(guestId, created.joinCode);
  assert.equal(invitation.id, eventId);

  await closeKnowledgeRoom(ownerId, eventId);
  await assert.rejects(getKnowledgeRoom(guestId, eventId, created.joinCode), /ROOM_NOT_FOUND/);
  assert.equal((await getKnowledgeRoom(ownerId, eventId)).status, "closed");
  await reactivateKnowledgeRoom(ownerId, eventId);
  assert.equal((await getKnowledgeRoom(ownerId, eventId)).status, "registration");
});

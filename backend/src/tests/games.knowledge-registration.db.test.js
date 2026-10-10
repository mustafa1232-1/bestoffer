import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import { q } from "../config/db.js";
import { registerTeam } from "../modules/games/knowledge.service.js";

test("repeated tournament registration returns the player's original team", async (t) => {
  const marker = randomUUID().replaceAll("-", "").slice(0, 12);
  const userResult = await q(
    `INSERT INTO app_user
       (full_name,phone,pin_hash,block,building_number,apartment,username,role)
     VALUES ($1,$2,'x','A','1','1',$3,'user') RETURNING id`,
    [`knowledge_retry_${marker}`, `078${marker.slice(0, 8)}`, `knowledge_${marker}`],
  );
  const userId = Number(userResult.rows[0].id);
  const eventResult = await q(
    `INSERT INTO maslaki_quiz_event
       (event_type,title,team_size,max_teams,created_by_user_id)
     VALUES ('tournament',$1,2,8,$2) RETURNING id`,
    [`registration retry ${marker}`, userId],
  );
  const eventId = Number(eventResult.rows[0].id);

  t.after(async () => {
    await q("DELETE FROM maslaki_quiz_event WHERE id=$1", [eventId]).catch(() => null);
    await q("DELETE FROM app_user WHERE id=$1", [userId]).catch(() => null);
  });

  const first = await registerTeam(userId, eventId, "Original team");
  const retry = await registerTeam(userId, eventId, "Retry team");

  assert.equal(retry.id, first.id);
  assert.equal(retry.joinCode, first.joinCode);
  assert.equal(retry.name, "Original team");
  assert.equal(retry.alreadyRegistered, true);
  const members = await q(
    "SELECT COUNT(*)::int AS count FROM maslaki_quiz_team_member WHERE event_id=$1 AND user_id=$2",
    [eventId, userId],
  );
  assert.equal(Number(members.rows[0].count), 1);
});

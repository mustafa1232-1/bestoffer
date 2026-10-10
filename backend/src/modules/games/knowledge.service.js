import crypto from "node:crypto";
import { AccessToken, RoomServiceClient, TrackSource } from "livekit-server-sdk";

import { env } from "../../config/env.js";
import { pool, q } from "../../config/db.js";
import { AppError } from "../../shared/utils/errors.js";
import { emitRealtimeToUsers } from "../../shared/realtime/realtime-gateway.js";
import { KNOWLEDGE_DIFFICULTY_SECONDS, MASLAKI_KNOWLEDGE_QUESTION_BANK, validateKnowledgeQuestionBank } from "./knowledge.question-bank.js";
import { buildTournamentBracket, knowledgeDuelCanStart, knowledgePublicChatIsConsented, knowledgeTeamJoinAction } from "./knowledge-game.logic.js";
import { resolveKnowledgeVotes } from './knowledge-game.logic.js';

const CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
const QUESTIONS_PER_MATCH = 5;
let seedTask;

function id(value) {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < 1) throw new AppError("INVALID_ID", { status: 400 });
  return parsed;
}

function roomCode(length = 6) {
  return [...crypto.randomBytes(length)].map((byte) => CODE_ALPHABET[byte % CODE_ALPHABET.length]).join("");
}

function questionKey(question) {
  return crypto.createHash("sha256").update(`${question.category}:${question.questionAr}`).digest("hex");
}

export async function seedKnowledgeQuestionBank() {
  const validation = validateKnowledgeQuestionBank();
  if (!validation.valid || validation.count < 1000) {
    throw new AppError("KNOWLEDGE_QUESTION_BANK_INVALID", { status: 500, details: validation });
  }
  if (!seedTask) {
    seedTask = (async () => {
      const client = await pool.connect();
      try {
        await client.query("BEGIN");
        const batchSize = 250;
        for (let offset = 0; offset < MASLAKI_KNOWLEDGE_QUESTION_BANK.length; offset += batchSize) {
          const batch = MASLAKI_KNOWLEDGE_QUESTION_BANK.slice(offset, offset + batchSize);
          const values = [];
          const rows = batch.map((question, rowIndex) => {
            const first = rowIndex * 9 + 1;
            values.push(questionKey(question), question.category, question.difficulty,
              question.questionAr, JSON.stringify(question.options), question.answerIndex,
              question.explanationAr, KNOWLEDGE_DIFFICULTY_SECONDS[question.difficulty] || 20,
              questionKey({...question,questionAr:question.factQuestionAr || question.questionAr}));
            return `($${first},$${first + 1},$${first + 2},$${first + 3},$${first + 4}::jsonb,` +
              `$${first + 5},$${first + 6},$${first + 7},$${first + 8})`;
          });
          await client.query(
            `INSERT INTO maslaki_quiz_question
               (question_key,category,difficulty,question_ar,options_json,answer_index,explanation_ar,time_limit_seconds,fact_key)
             VALUES ${rows.join(",")}
             ON CONFLICT(question_key) DO UPDATE SET fact_key=EXCLUDED.fact_key
               WHERE maslaki_quiz_question.question_ar=EXCLUDED.question_ar
                 AND maslaki_quiz_question.fact_key IS DISTINCT FROM EXCLUDED.fact_key`,
            values,
          );
        }
        await client.query("COMMIT");
      } catch (error) {
        await client.query("ROLLBACK");
        throw error;
      } finally {
        client.release();
      }
    })().catch((error) => {
      seedTask = null;
      throw error;
    });
  }
  await seedTask;
  return validation.count;
}

async function ensureQuestions() {
  if (!seedTask) await seedKnowledgeQuestionBank();
}

export async function listKnowledgeEvents(userId) {
  await ensureQuestions();
  const safeUserId = id(userId);
  const result = await q(
    `SELECT e.id,e.event_type,e.title,e.status,e.team_size,e.max_teams,e.best_of,
       e.prize_title,e.prize_description,e.prize_is_mock,e.starts_at,e.ends_at,
       e.is_private,e.created_by_user_id,
       COUNT(DISTINCT t.id)::int AS registered_teams,
       COUNT(DISTINCT tm.user_id)::int AS occupied_seats,
       COUNT(DISTINCT CASE WHEN m.status='active' THEN m.id END)::int AS active_matches
     FROM maslaki_quiz_event e
     LEFT JOIN maslaki_quiz_team t ON t.event_id=e.id
     LEFT JOIN maslaki_quiz_team_member tm ON tm.event_id=e.id
     LEFT JOIN maslaki_quiz_match m ON m.event_id=e.id
     WHERE (e.ends_at IS NULL OR e.ends_at>NOW() OR (e.event_type='tournament' AND e.status='completed')) AND (
       (e.event_type='duel' AND (
         (e.status='registration' AND (e.is_private=FALSE OR e.created_by_user_id=$1)) OR
         (e.created_by_user_id=$1 AND e.status IN ('closed','active'))
       )) OR
       (e.event_type='tournament' AND e.status IN ('registration','active','completed'))
     )
     GROUP BY e.id ORDER BY CASE WHEN e.status='active' THEN 0 WHEN e.status='registration' THEN 1 ELSE 2 END,e.created_at DESC LIMIT 100`,
    [safeUserId],
  );
  return result.rows.map((row) => ({
    id: Number(row.id), type: row.event_type, title: row.title, status: row.status,
    teamSize: Number(row.team_size), bestOf: Number(row.best_of), maxTeams: Number(row.max_teams),
    isPrivate: row.is_private === true, isMine: Number(row.created_by_user_id) === safeUserId,
    occupiedSeats: Number(row.occupied_seats), totalSeats: Number(row.team_size) * 2,
    registeredTeams: Number(row.registered_teams), activeMatches: Number(row.active_matches),
    prize: row.prize_title ? { title: row.prize_title, description: row.prize_description, mock: row.prize_is_mock } : null,
    startsAt: row.starts_at, endsAt: row.ends_at,
  }));
}

export async function createDuel(userId, { title, teamSize = 1, isPrivate = false, bestOf = 1 }) {
  const safeUserId = id(userId);
  if (![1,3,5,9].includes(Number(bestOf))) throw new AppError('SERIES_LENGTH_INVALID', { status: 400 });
  if (![1, 2, 3, 4].includes(Number(teamSize))) throw new AppError("TEAM_SIZE_INVALID", { status: 400 });
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const event = await client.query(
      `INSERT INTO maslaki_quiz_event(event_type,title,team_size,max_teams,created_by_user_id,prize_is_mock,is_private,best_of)
       VALUES('duel',$1,$2,2,$3,TRUE,$4,$5) RETURNING id`,
      [String(title || "تحدي خريطة المعرفة").trim().slice(0, 160), Number(teamSize), safeUserId, isPrivate === true, Number(bestOf)],
    );
    const code = roomCode(7);
    const teamResult = await client.query(
      `INSERT INTO maslaki_quiz_team(event_id,team_name,join_code,captain_user_id)
       VALUES($1,$2,$3,$4) RETURNING id,team_name,join_code`,
      [Number(event.rows[0].id), "فريق مسلكي", code, safeUserId],
    );
    const team = {
      id: Number(teamResult.rows[0].id),
      name: teamResult.rows[0].team_name,
      joinCode: teamResult.rows[0].join_code,
    };
    await client.query("COMMIT");
    return { eventId: Number(event.rows[0].id), team, joinCode: team.joinCode };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function getKnowledgeRoom(userId, eventId, accessCode = null) {
  const safeUserId = id(userId);
  const safeEventId = id(eventId);
  const code = accessCode == null ? null : String(accessCode).trim().toUpperCase();
  const roomResult = await q(
    `SELECT e.id,e.title,e.status,e.team_size,e.is_private,e.created_by_user_id,e.best_of,
       EXISTS(SELECT 1 FROM maslaki_quiz_team_member mine
         JOIN maslaki_quiz_team mt ON mt.id=mine.team_id
         WHERE mine.event_id=e.id AND mine.user_id=$2) AS is_member,
       (SELECT mine.team_id FROM maslaki_quiz_team_member mine
         WHERE mine.event_id=e.id AND mine.user_id=$2 LIMIT 1) AS my_team_id,
       EXISTS(SELECT 1 FROM maslaki_quiz_team owner_team
         WHERE owner_team.event_id=e.id AND owner_team.join_code=$3) AS valid_code
     FROM maslaki_quiz_event e WHERE e.id=$1 AND e.event_type='duel'`,
    [safeEventId, safeUserId, code],
  );
  const room = roomResult.rows[0];
  if (!room) throw new AppError("ROOM_NOT_FOUND", { status: 404 });
  const isOwner = Number(room.created_by_user_id) === safeUserId;
  const allowed = !room.is_private || isOwner || room.is_member || room.valid_code;
  if (!allowed || (room.status === "closed" && !isOwner)) {
    throw new AppError("ROOM_NOT_FOUND", { status: 404 });
  }
  const sides = await q(
    `SELECT t.id,t.team_name,COUNT(tm.user_id)::int AS occupied,
       COALESCE(json_agg(json_build_object('id',u.id,'name',COALESCE(NULLIF(u.full_name,''),'لاعب'))
         ORDER BY tm.joined_at) FILTER(WHERE tm.user_id IS NOT NULL),'[]'::json) AS players
     FROM maslaki_quiz_team t
     LEFT JOIN maslaki_quiz_team_member tm ON tm.team_id=t.id
     LEFT JOIN app_user u ON u.id=tm.user_id
     WHERE t.event_id=$1 GROUP BY t.id ORDER BY t.created_at,t.id`,
    [safeEventId],
  );
  const teams = sides.rows;
  const occupied = teams.reduce((sum, team) => sum + Number(team.occupied), 0);
  return {
    id: Number(room.id), title: room.title, status: room.status,
    teamSize: Number(room.team_size), bestOf: Number(room.best_of), isPrivate: room.is_private === true,
    isMine: isOwner, isMember: room.is_member === true, occupiedSeats: occupied,
    totalSeats: Number(room.team_size) * 2,
    teams: teams.map((team, index) => ({
      side: index === 0 ? "a" : "b", id: Number(team.id), name: team.team_name,
      occupied: Number(team.occupied), players: team.players,
    })),
    mySide: room.my_team_id == null ? null :
      (Number(room.my_team_id) === Number(teams[0]?.id) ? "a" : "b"),
  };
}

export async function lookupKnowledgeRoom(userId, joinCode) {
  id(userId);
  const code = String(joinCode || "").trim().toUpperCase();
  const result = await q(
    `SELECT e.id,e.event_type,e.title,e.team_size,e.status,e.is_private,
       e.created_by_user_id,t.join_code
     FROM maslaki_quiz_team t JOIN maslaki_quiz_event e ON e.id=t.event_id
     WHERE t.join_code=$1 AND e.event_type IN ('duel','tournament')
       AND e.status IN ('registration','active')`,
    [code],
  );
  const room = result.rows[0];
  if (!room || room.event_type === "duel" && room.status !== "registration") {
    throw new AppError("ROOM_NOT_JOINABLE", { status: 404 });
  }
  return {
    id: Number(room.id), eventType: room.event_type, title: room.title,
    teamSize: Number(room.team_size), isPrivate: room.is_private === true,
    accessCode: code,
  };
}

export async function joinKnowledgeRoomSeat(userId, eventId, side, accessCode = null) {
  const safeUserId = id(userId);
  const safeEventId = id(eventId);
  if (!["a", "b"].includes(side)) throw new AppError("ROOM_SIDE_INVALID", { status: 400 });
  const code = accessCode == null ? null : String(accessCode).trim().toUpperCase();
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const eventResult = await client.query(
      `SELECT * FROM maslaki_quiz_event WHERE id=$1 AND event_type='duel' FOR UPDATE`,
      [safeEventId],
    );
    const event = eventResult.rows[0];
    if (!event || event.status !== "registration") throw new AppError("ROOM_NOT_JOINABLE", { status: 409 });
    if (event.is_private) {
      const access = await client.query(
        `SELECT 1 FROM maslaki_quiz_team t WHERE t.event_id=$1 AND t.join_code=$2`,
        [safeEventId, code],
      );
      const owner = Number(event.created_by_user_id) === safeUserId;
      if (!owner && access.rowCount === 0) throw new AppError("ROOM_NOT_FOUND", { status: 404 });
    }
    const existing = await client.query(
      `SELECT team_id FROM maslaki_quiz_team_member WHERE event_id=$1 AND user_id=$2`,
      [safeEventId, safeUserId],
    );
    if (existing.rowCount > 0) {
      const teams = await client.query(
        "SELECT id FROM maslaki_quiz_team WHERE event_id=$1 ORDER BY created_at,id",
        [safeEventId],
      );
      const currentSide = Number(existing.rows[0].team_id) === Number(teams.rows[0]?.id) ? "a" : "b";
      if (currentSide !== side) throw new AppError("ROOM_ALREADY_SEATED", { status: 409 });
      await client.query("COMMIT");
      return getKnowledgeRoom(safeUserId, safeEventId, code);
    }
    const teams = await client.query(
      `SELECT t.id,t.team_name,COUNT(tm.user_id)::int AS occupied
       FROM maslaki_quiz_team t LEFT JOIN maslaki_quiz_team_member tm ON tm.team_id=t.id
       WHERE t.event_id=$1 GROUP BY t.id ORDER BY t.created_at,t.id`,
      [safeEventId],
    );
    let team = teams.rows[side === "a" ? 0 : 1];
    if (!team && side === "b") {
      const created = await createTeamTx(client, safeEventId, safeUserId, "الفريق الثاني");
      await client.query("COMMIT");
      return getKnowledgeRoom(safeUserId, safeEventId, code);
    }
    if (!team) throw new AppError("ROOM_SEAT_UNAVAILABLE", { status: 409 });
    if (Number(team.occupied) >= Number(event.team_size)) throw new AppError("ROOM_SEAT_UNAVAILABLE", { status: 409 });
    await client.query(
      "INSERT INTO maslaki_quiz_team_member(team_id,event_id,user_id) VALUES($1,$2,$3)",
      [team.id, safeEventId, safeUserId],
    );
    await maybeStartDuelTx(client, event);
    await client.query("COMMIT");
    return getKnowledgeRoom(safeUserId, safeEventId, code);
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function closeKnowledgeRoom(userId, eventId) {
  const result = await q(
    `UPDATE maslaki_quiz_event SET status='closed',updated_at=NOW()
     WHERE id=$1 AND event_type='duel' AND created_by_user_id=$2 AND status='registration'
     RETURNING id`, [id(eventId), id(userId)],
  );
  if (!result.rowCount) throw new AppError("ROOM_NOT_CLOSABLE", { status: 409 });
  return { id: Number(result.rows[0].id), status: "closed" };
}

export async function reactivateKnowledgeRoom(userId, eventId) {
  const result = await q(
    `UPDATE maslaki_quiz_event SET status='registration',updated_at=NOW()
     WHERE id=$1 AND event_type='duel' AND created_by_user_id=$2 AND status='closed'
     RETURNING id`, [id(eventId), id(userId)],
  );
  if (!result.rowCount) throw new AppError("ROOM_NOT_REACTIVATABLE", { status: 409 });
  return { id: Number(result.rows[0].id), status: "registration" };
}

async function createTeamTx(client, eventId, userId, name) {
  const eventResult = await client.query(
    `SELECT * FROM maslaki_quiz_event WHERE id=$1
     AND (ends_at IS NULL OR ends_at > NOW()) FOR UPDATE`, [eventId],
  );
  const event = eventResult.rows[0];
  if (!event || event.status !== "registration") throw new AppError("EVENT_CLOSED", { status: 409 });
  const count = await client.query("SELECT COUNT(*)::int AS count FROM maslaki_quiz_team WHERE event_id=$1", [eventId]);
  if (Number(count.rows[0].count) >= Number(event.max_teams)) throw new AppError("EVENT_FULL", { status: 409 });
  const code = roomCode(7);
  const teamName = String(name || "فريق المعرفة").trim().slice(0, 48) || "فريق المعرفة";
  const inserted = await client.query(
    `INSERT INTO maslaki_quiz_team(event_id,team_name,join_code,captain_user_id)
     VALUES($1,$2,$3,$4) RETURNING id,team_name,join_code`,
    [eventId, teamName, code, userId],
  );
  const team = inserted.rows[0];
  await client.query("INSERT INTO maslaki_quiz_team_member(team_id,event_id,user_id) VALUES($1,$2,$3)", [team.id, eventId, userId]);
  await maybeStartDuelTx(client, event);
  return { id: Number(team.id), name: team.team_name, joinCode: team.join_code };
}

async function maybeStartDuelTx(client, event) {
  if (event.event_type !== "duel") return;
  const teams = await client.query(
    `SELECT t.id,COUNT(tm.user_id)::int AS member_count FROM maslaki_quiz_team t
     LEFT JOIN maslaki_quiz_team_member tm ON tm.team_id=t.id
     WHERE t.event_id=$1 GROUP BY t.id ORDER BY t.created_at,t.id`, [event.id],
  );
  if (!knowledgeDuelCanStart(teams.rows.map((team) => ({ memberCount: team.member_count })), event.team_size)) return;
  await client.query(
    `INSERT INTO maslaki_quiz_match(event_id,round_number,match_number,team_a_id,team_b_id,status)
     VALUES($1,1,1,$2,$3,'pending') ON CONFLICT(event_id,round_number,match_number) DO NOTHING`,
    [event.id, teams.rows[0].id, teams.rows[1].id],
  );
  await client.query("UPDATE maslaki_quiz_event SET status='active',updated_at=NOW() WHERE id=$1", [event.id]);
}

export async function leaveKnowledgeRoomSeat(userId, eventId) {
  const client=await pool.connect();
  try {
    await client.query('BEGIN');
    const event=(await client.query("SELECT status FROM maslaki_quiz_event WHERE id=$1 AND event_type='duel' FOR UPDATE",[id(eventId)])).rows[0];
    if(!event || event.status!=='registration') throw new AppError('ROOM_ALREADY_STARTED',{status:409});
    await client.query('DELETE FROM maslaki_quiz_team_member WHERE event_id=$1 AND user_id=$2',[id(eventId),id(userId)]);
    await client.query('COMMIT');return {left:true};
  } catch(error){await client.query('ROLLBACK');throw error;}finally{client.release();}
}

export async function registerTeam(userId, eventId, teamName) {
  const safeUserId = id(userId);
  const safeEventId = id(eventId);
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    // Serialize registrations per event so retries (including concurrent taps)
    // return the player's existing team instead of hitting UNIQUE(event_id,user_id).
    await client.query(
      "SELECT id FROM maslaki_quiz_event WHERE id=$1 FOR UPDATE",
      [safeEventId],
    );
    const existing = await client.query(
      `SELECT t.id,t.team_name,t.join_code
       FROM maslaki_quiz_team_member m
       JOIN maslaki_quiz_team t ON t.id=m.team_id
       WHERE m.event_id=$1 AND m.user_id=$2
       LIMIT 1`,
      [safeEventId, safeUserId],
    );
    if (existing.rowCount > 0) {
      await client.query("COMMIT");
      const team = existing.rows[0];
      return {
        id: Number(team.id),
        name: team.team_name,
        joinCode: team.join_code,
        alreadyRegistered: true,
      };
    }
    const team = await createTeamTx(client, safeEventId, safeUserId, teamName);
    await client.query("COMMIT");
    return team;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function joinKnowledgeTeam(userId, joinCode) {
  const safeUserId = id(userId);
  const code = String(joinCode || "").trim().toUpperCase();
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const result = await client.query(
      `SELECT t.*,e.team_size,e.status AS event_status,e.event_type,e.title AS event_title
       FROM maslaki_quiz_team t JOIN maslaki_quiz_event e ON e.id=t.event_id
       WHERE t.join_code=$1 FOR UPDATE OF t,e`, [code],
    );
    const team = result.rows[0];
    if (!team) throw new AppError("TEAM_NOT_JOINABLE", { status: 404 });
    const existingMembership = await client.query(
      `SELECT t.id,t.team_name,t.join_code
       FROM maslaki_quiz_team_member m
       JOIN maslaki_quiz_team t ON t.id=m.team_id
       WHERE m.event_id=$1 AND m.user_id=$2 LIMIT 1`,
      [team.event_id, safeUserId],
    );
    if (existingMembership.rowCount > 0) {
      await client.query("COMMIT");
      const ownTeam = existingMembership.rows[0];
      return {
        teamId: Number(ownTeam.id), eventId: Number(team.event_id),
        name: ownTeam.team_name, joinCode: ownTeam.join_code,
        eventType: team.event_type, eventTitle: team.event_title,
        teamSize: Number(team.team_size), alreadyMember: true,
      };
    }
    const count = await client.query("SELECT COUNT(*)::int AS count FROM maslaki_quiz_team_member WHERE team_id=$1", [team.id]);
    const action = knowledgeTeamJoinAction({
      eventStatus: team.event_status,
      eventType: team.event_type,
      teamSize: team.team_size,
      memberCount: count.rows[0].count,
      alreadyMember: false,
    });
    if (action === "not-joinable") throw new AppError("TEAM_NOT_JOINABLE", { status: 404 });
    if (action === "team-full") throw new AppError("TEAM_FULL", { status: 409 });
    if (action === "join-opponent") {
      const opponents = await client.query(
        `SELECT t.id,t.team_name,t.join_code,COUNT(m.user_id)::int AS member_count
         FROM maslaki_quiz_team t
         LEFT JOIN maslaki_quiz_team_member m ON m.team_id=t.id
         WHERE t.event_id=$1 AND t.id<>$2
         GROUP BY t.id
         HAVING COUNT(m.user_id)<$3
         ORDER BY COUNT(m.user_id) DESC,t.created_at,t.id
         LIMIT 1`,
        [team.event_id, team.id, Number(team.team_size)],
      );
      if (opponents.rowCount > 0) {
        const opponent = opponents.rows[0];
        await client.query(
          "INSERT INTO maslaki_quiz_team_member(team_id,event_id,user_id) VALUES($1,$2,$3)",
          [opponent.id, team.event_id, safeUserId],
        );
        await maybeStartDuelTx(client, {
          id: team.event_id, event_type: team.event_type, team_size: team.team_size,
        });
        await client.query("COMMIT");
        return {
          teamId: Number(opponent.id), eventId: Number(team.event_id),
          name: opponent.team_name, joinCode: opponent.join_code,
          eventType: team.event_type, eventTitle: team.event_title,
          teamSize: Number(team.team_size), opponentTeam: true,
        };
      }
      const teamCount = await client.query(
        "SELECT COUNT(*)::int AS count FROM maslaki_quiz_team WHERE event_id=$1",
        [team.event_id],
      );
      if (Number(teamCount.rows[0].count) >= 2) {
        throw new AppError("TEAM_FULL", { status: 409 });
      }
      const opponent = await createTeamTx(client, team.event_id, safeUserId, "Duel opponent");
      await client.query("COMMIT");
      return {
        teamId: opponent.id, eventId: Number(team.event_id),
        name: opponent.name, joinCode: opponent.joinCode,
        eventType: team.event_type, eventTitle: team.event_title,
        teamSize: Number(team.team_size), opponentTeam: true,
      };
    }
    await client.query("INSERT INTO maslaki_quiz_team_member(team_id,event_id,user_id) VALUES($1,$2,$3)", [team.id, team.event_id, safeUserId]);
    await maybeStartDuelTx(client, { id: team.event_id, event_type: team.event_type, team_size: team.team_size });
    await client.query("COMMIT");
    return {
      teamId: Number(team.id), eventId: Number(team.event_id),
      name: team.team_name, joinCode: team.join_code,
      eventType: team.event_type, eventTitle: team.event_title,
      teamSize: Number(team.team_size),
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function createKnowledgeTournament(actor, input) {
  if (!actor.canManageGames) throw new AppError('FORBIDDEN', { status: 403 });
  const creatorId = id(actor.userId);
  const bestOf = Number(input.bestOf ?? 1);
  if (![1,3,5,9].includes(bestOf)) throw new AppError('SERIES_LENGTH_INVALID', { status: 400 });
  const teamSize = Number(input.teamSize);
  const maxTeams = Number(input.maxTeams);
  if (teamSize < 1 || teamSize > 4 || maxTeams < 2 || maxTeams > 64) throw new AppError("TOURNAMENT_SETTINGS_INVALID", { status: 400 });
  const result = await q(
    `INSERT INTO maslaki_quiz_event
       (event_type,title,team_size,max_teams,prize_title,prize_description,prize_is_mock,starts_at,ends_at,created_by_user_id,best_of)
     VALUES('tournament',$1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
     RETURNING id,title,status,team_size,max_teams,prize_title,prize_description,prize_is_mock,starts_at,ends_at`,
    [input.title, teamSize, maxTeams, input.prizeTitle || null, input.prizeDescription || null,
      input.prizeIsMock !== false, input.startsAt || null, input.endsAt || null, creatorId, bestOf],
  );
  const event = result.rows[0];
  return { id: Number(event.id), title: event.title, status: event.status, teamSize: Number(event.team_size),
    bestOf, maxTeams: Number(event.max_teams), prize: event.prize_title ? { title: event.prize_title,
      description: event.prize_description, mock: event.prize_is_mock } : null,
    startsAt: event.starts_at, endsAt: event.ends_at };
}


export async function advanceTournamentTx(client, eventId, roundNumber) {
  // Serialize the bracket handoff, not individual answer requests.
  await client.query('SELECT id FROM maslaki_quiz_event WHERE id=$1 FOR UPDATE', [eventId]);
  const open = await client.query(
    `SELECT COUNT(*)::int AS count FROM maslaki_quiz_match
     WHERE event_id=$1 AND round_number=$2 AND status NOT IN ('completed','bye')`, [eventId, roundNumber],
  );
  if (Number(open.rows[0].count) > 0) return;
  const matches = await client.query(
    `SELECT team_a_id,team_b_id,winner_team_id,status FROM maslaki_quiz_match
     WHERE event_id=$1 AND round_number=$2 ORDER BY match_number`, [eventId, roundNumber],
  );
  const winners = matches.rows.map((match) => Number(match.winner_team_id)).filter(Boolean);
  if (winners.length <= 1) {
    await client.query(
      `UPDATE maslaki_quiz_event SET status='completed',champion_team_id=$2,updated_at=NOW() WHERE id=$1`,
      [eventId, winners[0] || null],
    );
    return;
  }
  let matchNumber = 1;
  for (let index = 0; index < winners.length; index += 2) {
    const teamA = winners[index];
    const teamB = winners[index + 1] || null;
    await client.query(
      `INSERT INTO maslaki_quiz_match(event_id,round_number,match_number,team_a_id,team_b_id,winner_team_id,status)
       VALUES($1,$2,$3,$4,$5,$6,$7) ON CONFLICT(event_id,round_number,match_number) DO NOTHING`,
      [eventId, roundNumber + 1, matchNumber++, teamA, teamB, teamB ? null : teamA, teamB ? "pending" : "bye"],
    );
  }
}

export async function knowledgeTieBreakTx(client, match) {
  const answers = await client.query(
      `SELECT team_id,COUNT(DISTINCT question_id)::int AS correct_rounds,AVG(response_ms)::int AS avg_ms
       FROM maslaki_quiz_answer a WHERE match_id=$1 AND is_correct=TRUE AND is_timeout=FALSE
       AND ($2=0 OR EXISTS(SELECT 1 FROM maslaki_quiz_round r WHERE r.match_id=a.match_id
         AND r.question_id=a.question_id AND r.round_number>=$2)) GROUP BY team_id`,
      [match.id, Number(match.game_start_question || 0)],
    );
  const territories = await client.query(
      `SELECT team_id,COUNT(*)::int AS count FROM maslaki_quiz_territory
       WHERE match_id=$1 GROUP BY team_id`, [match.id],
    );
  const a = answers.rows.find((row) => Number(row.team_id) === Number(match.team_a_id));
  const b = answers.rows.find((row) => Number(row.team_id) === Number(match.team_b_id));
  const correctA = Number(a?.correct_rounds || 0);
  const correctB = Number(b?.correct_rounds || 0);
  if (correctA !== correctB) return correctA > correctB ? match.team_a_id : match.team_b_id;
  const timeA = Number(a?.avg_ms ?? Infinity);
  const timeB = Number(b?.avg_ms ?? Infinity);
  if (timeA !== timeB) return timeA < timeB ? match.team_a_id : match.team_b_id;
  const districtsA = Number(territories.rows.find((row) => Number(row.team_id) === Number(match.team_a_id))?.count || 0);
  const districtsB = Number(territories.rows.find((row) => Number(row.team_id) === Number(match.team_b_id))?.count || 0);
  if (districtsA !== districtsB) return districtsA > districtsB ? match.team_a_id : match.team_b_id;
  if (Number(match.question_number) - Number(match.game_start_question || 0) >= QUESTIONS_PER_MATCH + 2) {
    return crypto.randomInt(2) === 0 ? match.team_a_id : match.team_b_id;
  }
  return null;
}

export async function finalizeKnowledgeQuestionTx(client, match) {
  const input = (await client.query(`SELECT q.*,
    (SELECT jsonb_agg(to_jsonb(a)) FROM maslaki_quiz_answer a WHERE a.match_id=$1 AND a.question_id=q.id) AS answers,
    (SELECT jsonb_agg(to_jsonb(t)) FROM maslaki_quiz_territory t WHERE t.match_id=$1) AS territories,
    (SELECT COUNT(*)::int FROM maslaki_quiz_team_member WHERE team_id IN($3,$4)) AS expected
    FROM maslaki_quiz_question q WHERE q.id=$2`, [match.id,match.current_question_id,match.team_a_id,match.team_b_id])).rows[0];
  if (!input || (input.answers || []).length !== input.expected) return null;
  const resolved = resolveKnowledgeVotes({ teamIds:[match.team_a_id,match.team_b_id],
    answers:input.answers,territories:input.territories || [],question:input,startedAt:match.question_started_at });
  await client.query(`UPDATE maslaki_quiz_answer a SET is_correct=r.correct,
      points=CASE WHEN a.id=r."scoreAnswerId" THEN r.points ELSE 0 END
    FROM jsonb_to_recordset($3::jsonb) AS r("teamId" BIGINT,correct BOOLEAN,points INT,"scoreAnswerId" BIGINT)
    WHERE a.match_id=$1 AND a.question_id=$2 AND a.team_id=r."teamId"`,
    [match.id,match.current_question_id,JSON.stringify(resolved.outcomes)]);
  await client.query('UPDATE maslaki_quiz_match SET score_a=score_a+$2,score_b=score_b+$3 WHERE id=$1',
    [match.id,resolved.outcomes[0].points,resolved.outcomes[1].points]);
  if (resolved.grants.length) await client.query(`INSERT INTO maslaki_quiz_territory(match_id,district_id,team_id)
    SELECT $1,r."districtId",r."teamId" FROM jsonb_to_recordset($2::jsonb) AS r("districtId" TEXT,"teamId" BIGINT)`,
    [match.id,JSON.stringify(resolved.grants)]);
  return { explanation:input.explanation_ar,outcomes:resolved.outcomes.map(({scoreAnswerId,...result})=>result) };
}


export async function startKnowledgeTournament(actor, eventId) {
  if (!actor.canManageGames) throw new AppError("FORBIDDEN", { status: 403 });
  const safeEventId = id(eventId);
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const eventResult = await client.query("SELECT * FROM maslaki_quiz_event WHERE id=$1 FOR UPDATE", [safeEventId]);
    const event = eventResult.rows[0];
    if (!event || event.event_type !== "tournament" || event.status !== "registration" ||
        (event.starts_at && new Date(event.starts_at).getTime() > Date.now())) {
      throw new AppError("TOURNAMENT_NOT_STARTABLE", { status: 409 });
    }
    const teams = await client.query(
      `SELECT t.id,COUNT(m.user_id)::int AS members FROM maslaki_quiz_team t
       LEFT JOIN maslaki_quiz_team_member m ON m.team_id=t.id WHERE t.event_id=$1
       GROUP BY t.id ORDER BY t.created_at,t.id`, [safeEventId],
    );
    const eligible = teams.rows.filter((team) => Number(team.members) === Number(event.team_size));
    if (eligible.length < 2) throw new AppError("TOURNAMENT_NEEDS_TWO_FULL_TEAMS", { status: 409 });
    const drawnTeams = [...eligible];
    for (let index = drawnTeams.length - 1; index > 0; index -= 1) {
      const swapIndex = crypto.randomInt(index + 1);
      [drawnTeams[index], drawnTeams[swapIndex]] = [drawnTeams[swapIndex], drawnTeams[index]];
    }
    const bracket = buildTournamentBracket(drawnTeams.map((team) => team.id));
    for (const match of bracket.matches) {
      await client.query(
        `INSERT INTO maslaki_quiz_match(event_id,round_number,match_number,team_a_id,team_b_id,winner_team_id,status)
         VALUES($1,1,$2,$3,$4,$5,$6)`,
        [safeEventId, match.matchNumber, match.teamAId, match.teamBId, match.winnerTeamId, match.status],
      );
    }
    await client.query("UPDATE maslaki_quiz_event SET status='active',updated_at=NOW() WHERE id=$1", [safeEventId]);
    await advanceTournamentTx(client, safeEventId, 1);
    await client.query("COMMIT");
    return { eventId: safeEventId, teams: eligible.length, bracketSize: bracket.bracketSize, rounds: bracket.roundCount, drawn: true };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export { readKnowledgeSnapshot as knowledgeMatchSnapshot, acceptKnowledgeAnswer as answerKnowledgeQuestion,
  knowledgeAttemptStatus } from './knowledge-rounds.service.js';
export { readKnowledgeBracket } from './knowledge-bracket.service.js';

export async function listKnowledgeMatches(userId, eventId) {
  const result = await q(
    `SELECT m.id,m.round_number,m.match_number,m.status,m.score_a,m.score_b,m.wins_a,m.wins_b,
       ta.team_name AS team_a,tb.team_name AS team_b,m.winner_team_id,
       CASE WHEN ma.team_id IS NOT NULL THEN TRUE ELSE FALSE END AS is_member
     FROM maslaki_quiz_match m
     LEFT JOIN maslaki_quiz_team ta ON ta.id=m.team_a_id
     LEFT JOIN maslaki_quiz_team tb ON tb.id=m.team_b_id
     LEFT JOIN maslaki_quiz_team_member ma ON ma.team_id IN (m.team_a_id,m.team_b_id) AND ma.user_id=$2
     WHERE m.event_id=$1 AND ma.user_id IS NOT NULL
     ORDER BY m.round_number,m.match_number`, [id(eventId), id(userId)],
  );
  return result.rows.map((row) => ({ id: Number(row.id), round: Number(row.round_number), matchNumber: Number(row.match_number),
    status: row.status, scoreA: Number(row.score_a), scoreB: Number(row.score_b), winsA: Number(row.wins_a), winsB: Number(row.wins_b), teamA: row.team_a, teamB: row.team_b,
    winnerTeamId: row.winner_team_id == null ? null : Number(row.winner_team_id) }));
}

export async function getKnowledgeAdminOverview() {
  await ensureQuestions();
  const [events, stats, questions] = await Promise.all([
    q(`SELECT e.id,e.title,e.status,e.team_size,e.max_teams,e.best_of,e.prize_title,e.prize_description,e.prize_is_mock,e.starts_at,e.ends_at,
        COUNT(DISTINCT t.id)::int AS teams FROM maslaki_quiz_event e LEFT JOIN maslaki_quiz_team t ON t.event_id=e.id
        WHERE e.event_type='tournament' GROUP BY e.id ORDER BY e.created_at DESC LIMIT 50`),
    q(`SELECT COUNT(*)::int AS events,
        COUNT(*) FILTER(WHERE status='active')::int AS active_events,
        (SELECT COUNT(*)::int FROM maslaki_quiz_team) AS teams,
        (SELECT COUNT(*)::int FROM maslaki_quiz_question WHERE is_active=TRUE) AS questions
       FROM maslaki_quiz_event WHERE event_type='tournament'`),
    q(`SELECT category,COUNT(*)::int AS count FROM maslaki_quiz_question WHERE is_active=TRUE GROUP BY category ORDER BY category`),
  ]);
  return { stats: stats.rows[0], events: events.rows, questionsByCategory: questions.rows,
    bankSize: MASLAKI_KNOWLEDGE_QUESTION_BANK.length };
}

export async function listKnowledgeQuestionsForAdmin({ category, difficulty, query, limit = 100, offset = 0 } = {}) {
  await ensureQuestions();
  const result = await q(
    `SELECT id,category,difficulty,question_ar,options_json,answer_index,explanation_ar,
        time_limit_seconds,is_active,created_at
     FROM maslaki_quiz_question
     WHERE ($1::text IS NULL OR category=$1) AND ($2::text IS NULL OR difficulty=$2)
       AND ($3::text IS NULL OR question_ar ILIKE '%' || $3 || '%')
     ORDER BY created_at DESC,id DESC LIMIT $4 OFFSET $5`,
    [category || null, difficulty || null, query || null, Math.min(200, Math.max(1, Number(limit) || 100)),
      Math.min(10_000, Math.max(0, Number(offset) || 0))],
  );
  return result.rows.map((row) => ({ id: Number(row.id), category: row.category,
    difficulty: row.difficulty, question: row.question_ar, options: row.options_json,
    answerIndex: Number(row.answer_index), explanation: row.explanation_ar,
    timeLimitSeconds: Number(row.time_limit_seconds), active: row.is_active, createdAt: row.created_at }));
}

export async function saveKnowledgeQuestion(actor, input, questionId = null) {
  if (!actor.canManageGames) throw new AppError("FORBIDDEN", { status: 403 });
  if (questionId != null && typeof input.active === "boolean") {
    const result = await q("UPDATE maslaki_quiz_question SET is_active=$2 WHERE id=$1 RETURNING id",
      [id(questionId), input.active]);
    if (!result.rowCount) throw new AppError("QUESTION_NOT_FOUND", { status: 404 });
    return { id: Number(result.rows[0].id), active: input.active };
  }
  const question = { ...input, timeLimitSeconds: KNOWLEDGE_DIFFICULTY_SECONDS[input.difficulty] };
  if (questionId != null) {
    const result = await q(
      `UPDATE maslaki_quiz_question SET category=$2,difficulty=$3,question_ar=$4,
         options_json=$5::jsonb,answer_index=$6,explanation_ar=$7,time_limit_seconds=$8,
         is_active=COALESCE($9,is_active),fact_key=$10
       WHERE id=$1 AND NOT EXISTS(
         SELECT 1 FROM maslaki_quiz_match WHERE current_question_id=$1 AND status='active'
       ) RETURNING id`,
      [id(questionId), question.category, question.difficulty, question.question,
        JSON.stringify(question.options), question.answerIndex, question.explanation || "",
        question.timeLimitSeconds, typeof input.active === "boolean" ? input.active : null,
        questionKey({category:question.category,questionAr:question.question})],
    );
    if (!result.rowCount) {
      const exists = await q("SELECT 1 FROM maslaki_quiz_question WHERE id=$1", [id(questionId)]);
      if (!exists.rowCount) throw new AppError("QUESTION_NOT_FOUND", { status: 404 });
      throw new AppError("QUESTION_IN_ACTIVE_MATCH", { status: 409 });
    }
    return { id: Number(result.rows[0].id), updated: true };
  }
  const key = crypto.createHash("sha256")
    .update(`admin:${question.category}:${question.question.trim().toLocaleLowerCase()}`).digest("hex");
  const result = await q(
    `INSERT INTO maslaki_quiz_question
       (question_key,category,difficulty,question_ar,options_json,answer_index,explanation_ar,time_limit_seconds,fact_key)
     VALUES($1,$2,$3,$4,$5::jsonb,$6,$7,$8,$9)
     ON CONFLICT(question_key) DO UPDATE SET category=EXCLUDED.category,difficulty=EXCLUDED.difficulty,
       question_ar=EXCLUDED.question_ar,options_json=EXCLUDED.options_json,
       answer_index=EXCLUDED.answer_index,explanation_ar=EXCLUDED.explanation_ar,
       time_limit_seconds=EXCLUDED.time_limit_seconds,is_active=TRUE,fact_key=EXCLUDED.fact_key
     WHERE NOT EXISTS(
       SELECT 1 FROM maslaki_quiz_match m
       WHERE m.current_question_id=maslaki_quiz_question.id AND m.status='active'
     )
     RETURNING id`,
    [key, question.category, question.difficulty, question.question, JSON.stringify(question.options),
      question.answerIndex, question.explanation || "", question.timeLimitSeconds,
      questionKey({category:question.category,questionAr:question.question})],
  );
  if (!result.rowCount) throw new AppError("QUESTION_IN_ACTIVE_MATCH", { status: 409 });
  return { id: Number(result.rows[0].id), created: true };
}

async function matchMember(userId, matchId) {
  const result = await q(
    `SELECT m.id,m.status,m.team_a_id,m.team_b_id,tm.team_id,tm.user_id,
       COALESCE(u.full_name,u.phone,'لاعب') AS display_name
     FROM maslaki_quiz_match m JOIN maslaki_quiz_team_member tm
       ON tm.team_id IN (m.team_a_id,m.team_b_id) AND tm.user_id=$2
     LEFT JOIN app_user u ON u.id=tm.user_id WHERE m.id=$1`, [id(matchId), id(userId)],
  );
  if (!result.rowCount) throw new AppError("MATCH_NOT_FOUND_OR_FORBIDDEN", { status: 404 });
  return result.rows[0];
}

async function publicKnowledgeChatEnabled(match) {
  const result = await q(
    `SELECT t.id,COUNT(tm.user_id)::int AS total,
       COUNT(c.user_id) FILTER(WHERE c.enabled)::int AS opted_in
     FROM maslaki_quiz_team t JOIN maslaki_quiz_team_member tm ON tm.team_id=t.id
     LEFT JOIN maslaki_quiz_chat_consent c ON c.match_id=$1 AND c.team_id=t.id AND c.user_id=tm.user_id
     WHERE t.id IN ($2,$3) GROUP BY t.id`, [match.id, match.team_a_id, match.team_b_id],
  );
  return knowledgePublicChatIsConsented(result.rows.map((team) => ({
    total: team.total, optedIn: team.opted_in,
  })));
}

async function notifyKnowledgeMatch(matchId, event, payload = {}) {
  const members = await q(
    `SELECT DISTINCT tm.user_id FROM maslaki_quiz_match m
     JOIN maslaki_quiz_team_member tm ON tm.team_id IN (m.team_a_id,m.team_b_id) WHERE m.id=$1`, [id(matchId)],
  );
  emitRealtimeToUsers(members.rows.map((row) => Number(row.user_id)), event, { matchId: Number(matchId), ...payload }).catch(() => {});
}

export async function setKnowledgePublicChatConsent(userId, matchId, enabled) {
  const match = await matchMember(userId, matchId);
  if (match.status !== "active") throw new AppError("MATCH_NOT_ACTIVE", { status: 409 });
  await q(
    `INSERT INTO maslaki_quiz_chat_consent(match_id,team_id,user_id,enabled,updated_at)
     VALUES($1,$2,$3,$4,NOW()) ON CONFLICT(match_id,user_id)
     DO UPDATE SET team_id=EXCLUDED.team_id,enabled=EXCLUDED.enabled,updated_at=NOW()`,
    [match.id, match.team_id, id(userId), enabled],
  );
  const publicEnabled = await publicKnowledgeChatEnabled(match);
  await notifyKnowledgeMatch(matchId, "knowledge_match_updated", { publicChatEnabled: publicEnabled });
  return { enabled, publicChatEnabled: publicEnabled };
}

export async function sendKnowledgeChatMessage(userId, matchId, { channel, body }) {
  const match = await matchMember(userId, matchId);
  if (match.status !== "active") throw new AppError("MATCH_NOT_ACTIVE", { status: 409 });
  if (channel === "public" && !(await publicKnowledgeChatEnabled(match))) {
    throw new AppError("PUBLIC_CHAT_NEEDS_BOTH_TEAMS", { status: 409 });
  }
  const result = await q(
    `INSERT INTO maslaki_quiz_chat_message(match_id,team_id,channel,user_id,body)
     VALUES($1,$2,$3,$4,$5) RETURNING id,created_at`,
    [match.id, channel === "team" ? match.team_id : null, channel, id(userId), body],
  );
  await notifyKnowledgeMatch(matchId, "knowledge_chat_message", { channel });
  return { id: Number(result.rows[0].id), channel, body, createdAt: result.rows[0].created_at };
}

export async function sendKnowledgeReaction(userId, matchId, kind) {
  const match = await matchMember(userId, matchId);
  if (match.status !== "active") throw new AppError("MATCH_NOT_ACTIVE", { status: 409 });
  const result = await q(
    `INSERT INTO maslaki_quiz_reaction(match_id,team_id,user_id,kind)
     VALUES($1,$2,$3,$4) RETURNING id`, [match.id, match.team_id, id(userId), kind],
  );
  await q("DELETE FROM maslaki_quiz_reaction WHERE match_id=$1 AND created_at<NOW()-INTERVAL '1 minute'", [match.id]);
  await notifyKnowledgeMatch(matchId, "knowledge_reaction", { kind, userId: id(userId) });
  return { id: Number(result.rows[0].id), kind };
}

export async function getKnowledgeVoiceAccess(userId, matchId, channel) {
  const match = await matchMember(userId, matchId);
  if (match.status !== "active") throw new AppError("MATCH_NOT_ACTIVE", { status: 409 });
  if (!env.livekitUrl || !env.livekitApiKey || !env.livekitApiSecret) {
    return { enabled: false, reason: "LIVEKIT_NOT_CONFIGURED" };
  }
  if (channel === "public" && !(await publicKnowledgeChatEnabled(match))) {
    throw new AppError("PUBLIC_CHAT_NEEDS_BOTH_TEAMS", { status: 409 });
  }
  const roomName = channel === "public"
    ? `maslaki-knowledge-${match.id}-public`
    : `maslaki-knowledge-${match.id}-team-${match.team_id}`;
  const serviceUrl = String(env.livekitUrl).replace(/^wss:/i, "https:").replace(/^ws:/i, "http:");
  const rooms = new RoomServiceClient(serviceUrl, env.livekitApiKey, env.livekitApiSecret);
  try {
    await rooms.createRoom({ name: roomName, maxParticipants: channel === "public" ? 8 : 4,
      emptyTimeout: 10 * 60, departureTimeout: 3 * 60,
      metadata: JSON.stringify({ kind: "maslaki_knowledge", matchId: Number(match.id), channel }) });
  } catch (error) {
    if (!/exist|already/i.test(String(error?.message || error))) throw error;
  }
  const identity = `knowledge:${match.id}:user:${id(userId)}`;
  const grant = { roomJoin: true, room: roomName, canPublish: true, canSubscribe: true,
    canPublishData: true, canPublishSources: [TrackSource.MICROPHONE] };
  const token = new AccessToken(env.livekitApiKey, env.livekitApiSecret, {
    identity, name: match.display_name, ttl: Number(env.livekitTokenTtlSec || 900),
  });
  token.addGrant(grant);
  return { enabled: true, url: env.livekitUrl, roomName, identity,
    token: await token.toJwt(), permissions: { canPublish: true, canSubscribe: true },
    microphoneStartsMuted: true, expiresInSeconds: Number(env.livekitTokenTtlSec || 900) };
}

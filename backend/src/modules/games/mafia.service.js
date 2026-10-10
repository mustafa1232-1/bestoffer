import crypto from "node:crypto";

import { pool, q } from "../../config/db.js";
import { AppError } from "../../shared/utils/errors.js";
import { readMafiaState } from './mafia.snapshot.js';
import {
  issueMafiaVoiceToken,
  mafiaVoiceConfigured,
  mafiaVoiceRoomName,
} from "./mafia.voice.js";

const INVITE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
const ACTIVE_STATUSES = new Set([
  "role_reveal", "night", "day_discussion", "day_nomination",
  "day_defense", "day_vote", "day_revote",
]);
const PHASE_SECONDS = Object.freeze({
  role_reveal: 25,
  night: 45,
  day_discussion: 180,
  day_nomination: 45,
  day_defense: 60,
  day_vote: 35,
  day_revote: 30,
});
const QUICK_PHASE_SECONDS = Object.freeze({
  role_reveal: 18,
  night: 30,
  day_discussion: 90,
  day_nomination: 30,
  day_defense: 35,
  day_vote: 25,
  day_revote: 20,
});
const SECRET_MISSIONS = Object.freeze([
  {
    type: "survive",
    title: "الناجي الهادئ",
    description: "ابقَ داخل الجولة حتى إعلان النتيجة.",
  },
  {
    type: "cast_vote",
    title: "صوت المدينة",
    description: "شارك في تصويت نهاري واحد على الأقل.",
  },
  {
    type: "use_reaction",
    title: "روح المجلس",
    description: "أرسل تفاعلًا واحدًا أثناء النقاش.",
  },
  {
    type: "send_gift",
    title: "صاحب الذوق",
    description: "أرسل هدية إلى لاعب آخر.",
  },
  {
    type: "perform_role",
    title: "أدّ دورك",
    description: "نفّذ فعل دورك الليلي عندما تصبح قادرًا عليه.",
  },
]);

function id(value, code = "MAFIA_INVALID_ID") {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) throw new AppError(code, { status: 400 });
  return parsed;
}

function commandId(value) {
  const out = String(value || "").trim();
  if (!/^[A-Za-z0-9._:-]{8,80}$/.test(out)) {
    throw new AppError("MAFIA_COMMAND_ID_INVALID", { status: 400 });
  }
  return out;
}

function inviteCode() {
  const bytes = crypto.randomBytes(6);
  return [...bytes].map((byte) => INVITE_ALPHABET[byte % INVITE_ALPHABET.length]).join("");
}

function shuffle(values) {
  const out = [...values];
  for (let i = out.length - 1; i > 0; i -= 1) {
    const j = crypto.randomInt(i + 1);
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

export function buildMafiaRoleDeck(playerCount, ruleset = "standard") {
  const count = Number(playerCount);
  if (!Number.isInteger(count) || count < 7 || count > 14) {
    throw new AppError("MAFIA_PLAYER_COUNT_INVALID", { status: 400 });
  }
  const mafiaCount = count <= 9 ? 2 : count <= 13 ? 3 : 4;
  const mafiaRoles = [];
  if (count >= 10) mafiaRoles.push("don");
  if (ruleset === "advanced" && count === 14) mafiaRoles.push("framer");
  while (mafiaRoles.length < mafiaCount) mafiaRoles.push("mafia");

  const townRoles = ["detective", "doctor"];
  if (ruleset === "advanced" && count >= 11) townRoles.push("bodyguard");
  while (mafiaRoles.length + townRoles.length < count) townRoles.push("citizen");
  return [...mafiaRoles, ...townRoles];
}

export function teamForMafiaRole(role) {
  return ["mafia", "don", "framer"].includes(role) ? "mafia" : "town";
}

export function mafiaActionsForRole(role) {
  return {
    mafia: ["mafia_kill"],
    framer: ["mafia_kill", "framer_frame"],
    don: ["mafia_kill", "don_inspect"],
    doctor: ["doctor_protect"],
    bodyguard: ["bodyguard_protect"],
    detective: ["detective_inspect"],
  }[role] || [];
}

export function tallyMafiaBallots(ballots, allowedTargets = null) {
  const allowed = allowedTargets ? new Set(allowedTargets.map(Number)) : null;
  const counts = new Map();
  for (const ballot of ballots || []) {
    const target = Number(ballot.target_player_id ?? ballot.targetPlayerId);
    if (!target || (allowed && !allowed.has(target))) continue;
    counts.set(target, (counts.get(target) || 0) + 1);
  }
  const sorted = [...counts.entries()]
    .map(([playerId, votes]) => ({ playerId, votes }))
    .sort((a, b) => b.votes - a.votes || a.playerId - b.playerId);
  const topVotes = sorted[0]?.votes || 0;
  return {
    counts: sorted,
    winners: topVotes > 0 ? sorted.filter((item) => item.votes === topVotes).map((item) => item.playerId) : [],
    topVotes,
  };
}

export function mafiaPhaseSeconds(room, status) {
  const pace = settings(room).pace === "quick" ? "quick" : "classic";
  if (pace === 'quick' && settings(room).flowVersion === 2) {
    if (status === 'night' && Number(room.day_number) === 0) return 8;
    return {role_reveal:15,night:30,day_discussion:90,day_nomination:20,
      day_defense:30,day_vote:20,day_revote:15}[status] || null;
  }
  return (pace === "quick" ? QUICK_PHASE_SECONDS : PHASE_SECONDS)[status] || null;
}

function phaseDeadline(room, status) {
  const seconds = mafiaPhaseSeconds(room, status);
  return seconds ? new Date(Date.now() + seconds * 1000) : null;
}

export function mafiaNarratorCue(room, latestEvent = null) {
  const status = String(room?.status || "lobby");
  if (latestEvent?.event_type === "player_eliminated") {
    return {
      id: `elimination-${latestEvent.id}`,
      tone: "danger",
      title: "سقط قناع في المدينة",
      body: "غادر لاعب الجولة. راقبوا ما تغيّر قبل القرار التالي.",
    };
  }
  const copy = {
    lobby: ["المجلس يكتمل", "شارك الرمز، استعدوا، ثم ابدأوا عندما يجهز الجميع."],
    role_reveal: ["الأسرار بين أيديكم", "احفظ دورك ولا تكشف شاشتك لأي لاعب."],
    night: ["حلّ الليل", "المدينة صامتة الآن، وأصحاب الأدوار يتخذون قراراتهم."],
    day_discussion: ["استيقظت المدينة", "تكلموا، راقبوا التناقضات، ولا تمنحوا ثقتكم سريعًا."],
    day_nomination: ["حان وقت الاتهام", "رشّحوا من تشكون به، فالقرار سيقود إلى منصة الدفاع."],
    day_defense: ["منصة الدفاع", "استمعوا إلى المرشحين قبل أن تحسموا أصواتكم."],
    day_vote: ["قرار المدينة", "صوت واحد قد يكشف الحقيقة أو يمنح المافيا ليلة أخرى."],
    day_revote: ["كسر التعادل", "الأصوات متقاربة، وهذه الفرصة الأخيرة لحسم القرار."],
    completed: ["كُشفت كل الأسرار", "راجعوا خط الأحداث واختاروا نجم هذه الجولة."],
    cancelled: ["أُغلقت الغرفة", "تم حفظ الجولة في السجل ويمكن إنشاء ليلة جديدة."],
  }[status] || ["ليلة مسلكي", "تابعوا المرحلة الحالية واتخذوا قراركم في الوقت المناسب."];
  return {
    id: `phase-${room?.phase_version || 0}-${status}`,
    tone: status === "night" ? "mystery" : status === "completed" ? "victory" : "guide",
    title: copy[0],
    body: copy[1],
  };
}

function publicRoom(row) {
  return {
    id: Number(row.id),
    inviteCode: row.invite_code,
    hostUserId: Number(row.host_user_id),
    ruleset: row.ruleset,
    status: row.status,
    minPlayers: Number(row.min_players),
    maxPlayers: Number(row.max_players),
    dayNumber: Number(row.day_number),
    phaseVersion: Number(row.phase_version),
    phaseStartedAt: row.phase_started_at,
    phaseEndsAt: row.phase_ends_at,
    winner: row.winner,
    startedAt: row.started_at,
    completedAt: row.completed_at,
  };
}

async function loadRoom(client, roomId, lock = false) {
  const result = await client.query(
    `SELECT * FROM mafia_room WHERE id=$1${lock ? " FOR UPDATE" : ""}`,
    [roomId],
  );
  if (!result.rows[0]) throw new AppError("MAFIA_ROOM_NOT_FOUND", { status: 404 });
  return result.rows[0];
}

async function loadPlayer(client, roomId, userId, lock = false) {
  const result = await client.query(
    `SELECT p.*,u.full_name,u.image_url
     FROM mafia_player p JOIN app_user u ON u.id=p.user_id
     WHERE p.room_id=$1 AND p.user_id=$2${lock ? " FOR UPDATE OF p" : ""}`,
    [roomId, userId],
  );
  if (!result.rows[0]) throw new AppError("MAFIA_ROOM_FORBIDDEN", { status: 403 });
  return result.rows[0];
}

async function roomPlayers(client, roomId) {
  const result = await client.query(
    `SELECT p.*,u.full_name,u.image_url
     FROM mafia_player p JOIN app_user u ON u.id=p.user_id
     WHERE p.room_id=$1 ORDER BY p.seat_number`,
    [roomId],
  );
  return result.rows;
}

function settings(room) {
  return room.settings && typeof room.settings === "object" ? room.settings : {};
}

async function setPhase(client, room, status, patch = {}) {
  const nextSettings = { ...settings(room), ...(patch.settings || {}) };
  const deadline = phaseDeadline({ ...room, settings: nextSettings }, status);
  const result = await client.query(
    `UPDATE mafia_room SET status=$2,day_number=$3,phase_version=phase_version+1,
       phase_started_at=NOW(),phase_ends_at=$4,settings=$5::jsonb,updated_at=NOW()
     WHERE id=$1 RETURNING *`,
    [room.id, status, patch.dayNumber ?? room.day_number, deadline, JSON.stringify(nextSettings)],
  );
  await client.query(
    `INSERT INTO mafia_event (room_id,day_number,event_type,payload)
     VALUES ($1,$2,'phase_changed',$3::jsonb)`,
    [room.id, patch.dayNumber ?? room.day_number, JSON.stringify({ status, phaseEndsAt: deadline })],
  );
  return result.rows[0];
}

async function aliveCounts(client, roomId) {
  const result = await client.query(
    `SELECT team,COUNT(*)::int count FROM mafia_player
     WHERE room_id=$1 AND life_status='alive' GROUP BY team`,
    [roomId],
  );
  const out = { town: 0, mafia: 0 };
  for (const row of result.rows) out[row.team] = Number(row.count);
  return out;
}

async function completeIfWon(client, room) {
  const counts = await aliveCounts(client, room.id);
  const winner = counts.mafia <= 0 ? "town" : counts.mafia >= counts.town ? "mafia" : null;
  if (!winner) return null;
  const result = await client.query(
    `UPDATE mafia_room SET status='completed',winner=$2,completed_at=NOW(),
       phase_started_at=NOW(),phase_ends_at=NULL,phase_version=phase_version+1,updated_at=NOW()
     WHERE id=$1 RETURNING *`,
    [room.id, winner],
  );
  await client.query(
    `INSERT INTO mafia_event (room_id,day_number,event_type,payload)
     VALUES ($1,$2,'game_completed',$3::jsonb)`,
    [room.id, room.day_number, JSON.stringify({ winner, counts })],
  );
  return result.rows[0];
}

async function eliminate(client, room, playerId, reason) {
  const result = await client.query(
    `UPDATE mafia_player SET life_status='dead',eliminated_at=NOW(),eliminated_reason=$3
     WHERE room_id=$1 AND id=$2 AND life_status='alive' RETURNING id,seat_number,role,team`,
    [room.id, playerId, reason],
  );
  if (!result.rows[0]) return null;
  await client.query(
    `INSERT INTO mafia_event (room_id,day_number,event_type,payload)
     VALUES ($1,$2,'player_eliminated',$3::jsonb)`,
    [room.id, room.day_number, JSON.stringify({
      playerId: Number(playerId),
      seatNumber: Number(result.rows[0].seat_number),
      reason,
      role: settings(room).revealRolesOnDeath === false ? null : result.rows[0].role,
    })],
  );
  return result.rows[0];
}

async function nominationCandidates(client, room) {
  const result = await client.query(
    `SELECT target_player_id,COUNT(*)::int votes FROM mafia_ballot
     WHERE room_id=$1 AND day_number=$2 AND ballot_type='nomination'
       AND target_player_id IS NOT NULL
       AND EXISTS(SELECT 1 FROM mafia_player p WHERE p.id=mafia_ballot.voter_player_id AND p.life_status='alive')
       AND EXISTS(SELECT 1 FROM mafia_player p WHERE p.id=mafia_ballot.target_player_id AND p.life_status='alive')
     GROUP BY target_player_id ORDER BY votes DESC,target_player_id LIMIT 5`,
    [room.id, room.day_number],
  );
  return result.rows.map((row) => Number(row.target_player_id));
}

async function resolveVote(client, room, ballotType) {
  const candidates = (settings(room).candidateIds || []).map(Number);
  const ballots = await client.query(
    `SELECT target_player_id FROM mafia_ballot
     WHERE room_id=$1 AND day_number=$2 AND ballot_type=$3
       AND EXISTS(SELECT 1 FROM mafia_player p WHERE p.id=mafia_ballot.voter_player_id AND p.life_status='alive')
       AND (target_player_id IS NULL OR EXISTS(SELECT 1 FROM mafia_player p WHERE p.id=mafia_ballot.target_player_id AND p.life_status='alive'))`,
    [room.id, room.day_number, ballotType],
  );
  const tally = tallyMafiaBallots(ballots.rows, candidates);
  if (tally.winners.length === 1) {
    await eliminate(client, room, tally.winners[0], "day_vote");
    const completed = await completeIfWon(client, room);
    if (completed) return completed;
    return setPhase(client, room, "night", { settings: { candidateIds: [], revoteCandidateIds: [] } });
  }
  if (ballotType === "vote" && tally.winners.length > 1) {
    return setPhase(client, room, "day_revote", {
      settings: { candidateIds: tally.winners, revoteCandidateIds: tally.winners },
    });
  }
  await client.query(
    `INSERT INTO mafia_event (room_id,day_number,event_type,payload)
     VALUES ($1,$2,'vote_tied',$3::jsonb)`,
    [room.id, room.day_number, JSON.stringify({ candidates: tally.winners })],
  );
  return setPhase(client, room, "night", { settings: { candidateIds: [], revoteCandidateIds: [] } });
}

async function resolveNight(client, room) {
  if (Number(room.day_number) === 0) {
    return setPhase(client, room, "day_discussion", { dayNumber: 1 });
  }
  const actions = await client.query(
    `SELECT a.*,p.role,p.team FROM mafia_action a
     JOIN mafia_player p ON p.id=a.actor_player_id
     WHERE a.room_id=$1 AND a.day_number=$2 AND p.life_status='alive'`,
    [room.id, room.day_number],
  );
  const kills = actions.rows.filter((item) => item.action_type === "mafia_kill");
  const killTally = tallyMafiaBallots(kills.map((item) => ({ target_player_id: item.target_player_id })));
  const killTarget = killTally.winners.length === 1 ? killTally.winners[0] : null;
  const doctorProtectedIds = new Set(
    actions.rows
      .filter((item) => item.action_type === "doctor_protect")
      .map((item) => Number(item.target_player_id)),
  );
  const bodyguardAction = actions.rows.find(
    (item) => item.action_type === "bodyguard_protect" && Number(item.target_player_id) === killTarget,
  );
  const framedIds = new Set(
    actions.rows
      .filter((item) => item.action_type === "framer_frame")
      .map((item) => Number(item.target_player_id)),
  );

  for (const action of actions.rows.filter((item) => item.action_type === "detective_inspect")) {
    const target = await client.query(`SELECT team FROM mafia_player WHERE id=$1`, [action.target_player_id]);
    await client.query(
      `INSERT INTO mafia_event
         (room_id,day_number,event_type,visibility,recipient_player_id,payload)
       VALUES ($1,$2,'investigation_result','private',$3,$4::jsonb)`,
      [room.id, room.day_number, action.actor_player_id, JSON.stringify({
        targetPlayerId: Number(action.target_player_id),
        isMafia: target.rows[0]?.team === "mafia" || framedIds.has(Number(action.target_player_id)),
      })],
    );
  }
  for (const action of actions.rows.filter((item) => item.action_type === "don_inspect")) {
    const target = await client.query(`SELECT role FROM mafia_player WHERE id=$1`, [action.target_player_id]);
    await client.query(
      `INSERT INTO mafia_event
         (room_id,day_number,event_type,visibility,recipient_player_id,payload)
       VALUES ($1,$2,'don_result','private',$3,$4::jsonb)`,
      [room.id, room.day_number, action.actor_player_id, JSON.stringify({
        targetPlayerId: Number(action.target_player_id),
        isDetective: target.rows[0]?.role === "detective",
      })],
    );
  }

  if (killTarget && doctorProtectedIds.has(killTarget)) {
    await client.query(
      `INSERT INTO mafia_event (room_id,day_number,event_type,payload)
       VALUES ($1,$2,'quiet_night',$3::jsonb)`,
      [room.id, room.day_number, JSON.stringify({ protected: true })],
    );
  } else if (killTarget && bodyguardAction) {
    await eliminate(client, room, Number(bodyguardAction.actor_player_id), "bodyguard_sacrifice");
    await client.query(
      `INSERT INTO mafia_event (room_id,day_number,event_type,payload)
       VALUES ($1,$2,'bodyguard_sacrifice',$3::jsonb)`,
      [room.id, room.day_number, JSON.stringify({ protectedPlayerId: killTarget })],
    );
  } else if (killTarget) {
    await eliminate(client, room, killTarget, "night_kill");
  } else {
    await client.query(
      `INSERT INTO mafia_event (room_id,day_number,event_type,payload)
       VALUES ($1,$2,'quiet_night',$3::jsonb)`,
      [room.id, room.day_number, JSON.stringify({ protected: Boolean(killTarget) })],
    );
  }
  const completed = await completeIfWon(client, room);
  if (completed) return completed;
  return setPhase(client, room, "day_discussion", { dayNumber: Number(room.day_number) + 1 });
}

async function advancePhaseTx(client, room) {
  switch (room.status) {
    case "role_reveal":
      return setPhase(client, room, "night", { dayNumber: 0 });
    case "night":
      return resolveNight(client, room);
    case "day_discussion":
      return setPhase(client, room, "day_nomination");
    case "day_nomination": {
      const candidateIds = await nominationCandidates(client, room);
      if (candidateIds.length === 0) return setPhase(client, room, "night");
      return setPhase(client, room, "day_defense", { settings: { candidateIds } });
    }
    case "day_defense":
      return setPhase(client, room, "day_vote");
    case "day_vote":
      return resolveVote(client, room, "vote");
    case "day_revote":
      return resolveVote(client, room, "revote");
    default:
      return room;
  }
}

export async function advanceMafiaRoom(roomId, { force = false } = {}) {
  const safeRoomId = id(roomId);
  const client = await pool.connect();
  let changed = false;
  let room;
  try {
    await client.query("BEGIN");
    room = (await client.query('SELECT * FROM mafia_room WHERE id=$1 FOR UPDATE SKIP LOCKED', [safeRoomId])).rows[0];
    if (!room) { await client.query('COMMIT'); return {changed:false}; }
    const expired = room.phase_ends_at && new Date(room.phase_ends_at).getTime() <= Date.now();
    const earlyReveal = room.status === 'role_reveal' && settings(room).flowVersion === 2 &&
      Date.now()-new Date(room.phase_started_at).getTime() >= 4000 &&
      !(await client.query("SELECT 1 FROM mafia_player WHERE room_id=$1 AND life_status='alive' AND NOT role_acknowledged LIMIT 1", [safeRoomId])).rowCount;
    if (ACTIVE_STATUSES.has(room.status) && (force || expired || earlyReveal)) {
      room = await advancePhaseTx(client, room);
      changed = true;
    }
    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
  // Triggers commit notification/voice work with the phase, never await providers.
  return { changed, room: publicRoom(room) };
}

export async function createMafiaRoom(userId, input = {}) {
  const safeUserId = id(userId);
  const ruleset = input.ruleset === "advanced" ? "advanced" : "standard";
  const maxPlayers = Math.min(14, Math.max(7, Number(input.maxPlayers) || 14));
  const client = await pool.connect();
  let room;
  try {
    await client.query("BEGIN");
    const existing = await client.query(
      `SELECT r.* FROM mafia_room r JOIN mafia_player p ON p.room_id=r.id
       WHERE p.user_id=$1 AND p.life_status<>'left'
         AND r.status NOT IN ('completed','cancelled')
       ORDER BY r.updated_at DESC LIMIT 1`,
      [safeUserId],
    );
    if (existing.rows[0]) {
      await client.query("COMMIT");
      return getMafiaSnapshot(existing.rows[0].id, safeUserId);
    }
    let code;
    for (let attempt = 0; attempt < 12; attempt += 1) {
      const candidate = inviteCode();
      const found = await client.query(`SELECT 1 FROM mafia_room WHERE invite_code=$1`, [candidate]);
      if (!found.rows[0]) { code = candidate; break; }
    }
    if (!code) throw new AppError("MAFIA_INVITE_CODE_UNAVAILABLE", { status: 503 });
    const inserted = await client.query(
      `INSERT INTO mafia_room
         (invite_code,host_user_id,ruleset,max_players,voice_room_name,settings)
       VALUES ($1,$2,$3,$4,$5,$6::jsonb) RETURNING *`,
      [code, safeUserId, ruleset, maxPlayers, `pending-${code}`, JSON.stringify({
        pace: input.pace === "quick" ? "quick" : "classic",
        flowVersion: 2,
        tableTheme: ["royal", "cinema"].includes(input.tableTheme)
          ? input.tableTheme
          : "emerald",
        revealRolesOnDeath: input.revealRolesOnDeath !== false,
        candidateIds: [],
        revoteCandidateIds: [],
      })],
    );
    room = inserted.rows[0];
    const voiceName = mafiaVoiceRoomName(room.id);
    const updated = await client.query(
      `UPDATE mafia_room SET voice_room_name=$2 WHERE id=$1 RETURNING *`,
      [room.id, voiceName],
    );
    room = updated.rows[0];
    await client.query(
      `INSERT INTO mafia_player (room_id,user_id,seat_number,is_ready)
       VALUES ($1,$2,1,FALSE)`,
      [room.id, safeUserId],
    );
    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
  return getMafiaSnapshot(room.id, safeUserId);
}

export async function reactivateMafiaRoom(userId, sourceRoomId, input = {}) {
  const safeUserId = id(userId);
  const safeSourceRoomId = id(sourceRoomId);
  const sourceResult = await q(
    `SELECT * FROM mafia_room WHERE id=$1 AND host_user_id=$2`,
    [safeSourceRoomId, safeUserId],
  );
  const source = sourceResult.rows[0];
  if (!source) throw new AppError("MAFIA_HOST_REQUIRED", { status: 403 });
  if (!["completed", "cancelled"].includes(source.status)) {
    throw new AppError("MAFIA_ROOM_STILL_ACTIVE", { status: 409 });
  }
  const created = await createMafiaRoom(safeUserId, {
    ruleset: input.ruleset || source.ruleset,
    pace: input.pace || settings(source).pace,
    tableTheme: input.tableTheme || settings(source).tableTheme,
    maxPlayers: input.maxPlayers || source.max_players,
    revealRolesOnDeath: input.revealRolesOnDeath ??
      settings(source).revealRolesOnDeath,
  });
  if (Number(created.room.id) !== safeSourceRoomId) {
    await q(
      `UPDATE mafia_room
       SET settings=settings || $2::jsonb,updated_at=NOW()
       WHERE id=$1`,
      [created.room.id, JSON.stringify({ reactivatedFromRoomId: safeSourceRoomId })],
    );
  }
  return getMafiaSnapshot(created.room.id, safeUserId);
}

export async function joinMafiaRoom(userId, rawCode) {
  const safeUserId = id(userId);
  const code = String(rawCode || "").trim().toUpperCase();
  const client = await pool.connect();
  let roomId;
  try {
    await client.query("BEGIN");
    const found = await client.query(`SELECT * FROM mafia_room WHERE invite_code=$1 FOR UPDATE`, [code]);
    const room = found.rows[0];
    if (!room) throw new AppError("MAFIA_ROOM_NOT_FOUND", { status: 404 });
    if (room.status !== "lobby") throw new AppError("MAFIA_ROOM_ALREADY_STARTED", { status: 409 });
    if ((settings(room).kickedUserIds || []).map(Number).includes(safeUserId)) {
      throw new AppError("MAFIA_PLAYER_KICKED", { status: 403 });
    }
    const existing = await client.query(
      `SELECT * FROM mafia_player WHERE room_id=$1 AND user_id=$2`,
      [room.id, safeUserId],
    );
    if (existing.rows[0]) {
      await client.query(
        `UPDATE mafia_player SET life_status='alive',last_seen_at=NOW(),disconnected_at=NULL
         WHERE id=$1`,
        [existing.rows[0].id],
      );
    } else {
      const count = await client.query(
        `SELECT COUNT(*)::int count FROM mafia_player WHERE room_id=$1 AND life_status<>'left'`,
        [room.id],
      );
      if (Number(count.rows[0].count) >= Number(room.max_players)) {
        throw new AppError("MAFIA_ROOM_FULL", { status: 409 });
      }
      const seat = await client.query(
        `SELECT n FROM generate_series(1,14) n WHERE NOT EXISTS (
           SELECT 1 FROM mafia_player WHERE room_id=$1 AND seat_number=n AND life_status<>'left'
         ) ORDER BY n LIMIT 1`,
        [room.id],
      );
      await client.query(
        `INSERT INTO mafia_player (room_id,user_id,seat_number) VALUES ($1,$2,$3)`,
        [room.id, safeUserId, seat.rows[0].n],
      );
    }
    roomId = room.id;
    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
  return getMafiaSnapshot(roomId, safeUserId);
}

export async function setMafiaReady(userId, roomId, ready) {
  const result = await q(
    `UPDATE mafia_player p SET is_ready=$3,last_seen_at=NOW()
     FROM mafia_room r WHERE p.room_id=r.id AND p.room_id=$1 AND p.user_id=$2
       AND r.status='lobby' RETURNING p.id`,
    [id(roomId), id(userId), ready === true],
  );
  if (!result.rows[0]) throw new AppError("MAFIA_READY_NOT_ALLOWED", { status: 409 });
  return getMafiaSnapshot(roomId, userId);
}

export async function startMafiaRoom(userId, roomId) {
  const safeRoomId = id(roomId);
  const safeUserId = id(userId);
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    let room = await loadRoom(client, safeRoomId, true);
    if (Number(room.host_user_id) !== safeUserId) throw new AppError("MAFIA_HOST_REQUIRED", { status: 403 });
    if (room.status !== "lobby") throw new AppError("MAFIA_ROOM_ALREADY_STARTED", { status: 409 });
    const players = await roomPlayers(client, safeRoomId);
    if (players.length < Number(room.min_players)) {
      throw new AppError("MAFIA_NOT_ENOUGH_PLAYERS", { status: 409, details: { required: room.min_players } });
    }
    if (players.some((player) => player.is_ready !== true)) {
      throw new AppError("MAFIA_PLAYERS_NOT_READY", { status: 409 });
    }
    const roles = shuffle(buildMafiaRoleDeck(players.length, room.ruleset));
    for (let index = 0; index < players.length; index += 1) {
      await client.query(
        `UPDATE mafia_player SET role=$2,team=$3,life_status='alive',role_acknowledged=FALSE
         WHERE id=$1`,
        [players[index].id, roles[index], teamForMafiaRole(roles[index])],
      );
    }
    const missionDeck = shuffle(
      players.map((_, index) => SECRET_MISSIONS[index % SECRET_MISSIONS.length]),
    );
    for (let index = 0; index < players.length; index += 1) {
      await client.query(
        `INSERT INTO mafia_event
           (room_id,day_number,event_type,visibility,recipient_player_id,payload)
         VALUES ($1,0,'secret_mission','private',$2,$3::jsonb)`,
        [safeRoomId, players[index].id, JSON.stringify(missionDeck[index])],
      );
    }
    room = await setPhase(client, room, "role_reveal", { dayNumber: 0 });
    await client.query(
      `UPDATE mafia_room SET started_at=NOW() WHERE id=$1`,
      [safeRoomId],
    );
    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
  return getMafiaSnapshot(safeRoomId, safeUserId);
}

export async function acknowledgeMafiaRole(userId, roomId) {
  const result = await q(
    `UPDATE mafia_player SET role_acknowledged=TRUE,last_seen_at=NOW()
     WHERE room_id=$1 AND user_id=$2 AND role IS NOT NULL RETURNING id`,
    [id(roomId), id(userId)],
  );
  if (!result.rows[0]) throw new AppError("MAFIA_ROLE_UNAVAILABLE", { status: 409 });
  return getMafiaSnapshot(roomId, userId);
}

function assertAlive(player) {
  if (player.life_status !== "alive") throw new AppError("MAFIA_PLAYER_NOT_ALIVE", { status: 409 });
}

export async function submitMafiaAction(userId, roomId, input) {
  const safeRoomId = id(roomId);
  const targetPlayerId = input.targetPlayerId == null ? null : id(input.targetPlayerId);
  const safeCommandId = commandId(input.commandId);
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const room = await loadRoom(client, safeRoomId, true);
    const player = await loadPlayer(client, safeRoomId, id(userId), true);
    if (player.life_status === 'left') throw new AppError('MAFIA_ROOM_FORBIDDEN', {status:403});
    const request = {type:String(input.type || ''),targetPlayerId,phaseVersion:input.phaseVersion ?? null};
    const previous = (await client.query('SELECT request FROM mafia_command_receipt WHERE room_id=$1 AND user_id=$2 AND command_id=$3',
      [safeRoomId,id(userId),safeCommandId])).rows[0];
    if (previous) {
      if (Object.keys(request).some(key=>previous.request[key] !== request[key])) throw new AppError('MAFIA_COMMAND_CONFLICT', {status:409});
      await client.query('COMMIT');
      return getMafiaSnapshot(safeRoomId,userId);
    }
    if (input.phaseVersion != null && Number(input.phaseVersion) !== Number(room.phase_version)) {
      throw new AppError('MAFIA_PHASE_CHANGED', {status:409});
    }
    if (room.phase_ends_at && new Date(room.phase_ends_at).getTime() <= Date.now()) {
      throw new AppError("MAFIA_PHASE_EXPIRED", { status: 409 });
    }
    assertAlive(player);
    const target = targetPlayerId
      ? (await client.query(
          `SELECT * FROM mafia_player WHERE room_id=$1 AND id=$2 AND life_status='alive'`,
          [safeRoomId, targetPlayerId],
        )).rows[0]
      : null;
    if (targetPlayerId && !target) throw new AppError("MAFIA_TARGET_INVALID", { status: 400 });

    const type = String(input.type || "");
    if (type === "nominate") {
      if (room.status !== "day_nomination" || !target || Number(target.id) === Number(player.id)) {
        throw new AppError("MAFIA_NOMINATION_NOT_ALLOWED", { status: 409 });
      }
      await client.query(
        `INSERT INTO mafia_ballot
           (room_id,day_number,phase_version,ballot_type,voter_player_id,target_player_id,command_id)
         VALUES ($1,$2,$3,'nomination',$4,$5,$6)
         ON CONFLICT (room_id,voter_player_id,day_number,ballot_type) DO UPDATE SET
           target_player_id=EXCLUDED.target_player_id,command_id=EXCLUDED.command_id,
           phase_version=EXCLUDED.phase_version,created_at=NOW()`,
        [safeRoomId, room.day_number, room.phase_version, player.id, target.id, safeCommandId],
      );
    } else if (type === "vote") {
      if (!["day_vote", "day_revote"].includes(room.status)) {
        throw new AppError("MAFIA_VOTE_NOT_ALLOWED", { status: 409 });
      }
      const candidates = (settings(room).candidateIds || []).map(Number);
      if (target && !candidates.includes(Number(target.id))) {
        throw new AppError("MAFIA_VOTE_TARGET_INVALID", { status: 400 });
      }
      if (target && Number(target.id) === Number(player.id)) throw new AppError('MAFIA_SELF_TARGET_FORBIDDEN', {status:400});
      const ballotType = room.status === "day_revote" ? "revote" : "vote";
      await client.query(
        `INSERT INTO mafia_ballot
           (room_id,day_number,phase_version,ballot_type,voter_player_id,target_player_id,command_id)
         VALUES ($1,$2,$3,$4,$5,$6,$7)
         ON CONFLICT (room_id,voter_player_id,day_number,ballot_type) DO UPDATE SET
           target_player_id=EXCLUDED.target_player_id,command_id=EXCLUDED.command_id,
           phase_version=EXCLUDED.phase_version,created_at=NOW()`,
        [safeRoomId, room.day_number, room.phase_version, ballotType, player.id, target?.id || null, safeCommandId],
      );
    } else {
      if (room.status !== "night" || Number(room.day_number) < 1 || !target) {
        throw new AppError("MAFIA_NIGHT_ACTION_NOT_ALLOWED", { status: 409 });
      }
      if (!mafiaActionsForRole(player.role).includes(type)) {
        throw new AppError("MAFIA_ROLE_ACTION_FORBIDDEN", { status: 403 });
      }
      if (type !== "doctor_protect" && Number(target.id) === Number(player.id)) {
        throw new AppError("MAFIA_SELF_TARGET_FORBIDDEN", { status: 400 });
      }
      if (type === "mafia_kill" && target.team === "mafia") {
        throw new AppError("MAFIA_TEAM_TARGET_FORBIDDEN", { status: 400 });
      }
      if (type === "framer_frame" && target.team === "mafia") {
        throw new AppError("MAFIA_TEAM_TARGET_FORBIDDEN", { status: 400 });
      }
      if (type === "don_inspect" && target.team === "mafia") {
        throw new AppError("MAFIA_TEAM_TARGET_FORBIDDEN", { status: 400 });
      }
      if (type === "doctor_protect") {
        const previous = await client.query(
          `SELECT target_player_id FROM mafia_action
           WHERE room_id=$1 AND actor_player_id=$2 AND action_type='doctor_protect'
             AND day_number=$3`,
          [safeRoomId, player.id, Number(room.day_number) - 1],
        );
        if (Number(previous.rows[0]?.target_player_id) === Number(target.id)) {
          throw new AppError("MAFIA_DOCTOR_REPEAT_FORBIDDEN", { status: 409 });
        }
      }
      await client.query(
        `INSERT INTO mafia_action
           (room_id,day_number,phase_version,actor_player_id,action_type,target_player_id,command_id)
         VALUES ($1,$2,$3,$4,$5,$6,$7)
         ON CONFLICT (room_id,actor_player_id,day_number,action_type) DO UPDATE SET
           target_player_id=EXCLUDED.target_player_id,command_id=EXCLUDED.command_id,
           phase_version=EXCLUDED.phase_version,created_at=NOW()`,
        [safeRoomId, room.day_number, room.phase_version, player.id, type, target.id, safeCommandId],
      );
    }
    await client.query('INSERT INTO mafia_command_receipt(room_id,user_id,command_id,request) VALUES($1,$2,$3,$4::jsonb)',
      [safeRoomId,id(userId),safeCommandId,JSON.stringify(request)]);
    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
  return getMafiaSnapshot(safeRoomId, userId);
}

export async function sendMafiaMessage(userId, roomId, input) {
  const safeRoomId = id(roomId);
  const body = String(input.body || "").trim();
  if (!body || body.length > 300) throw new AppError("MAFIA_MESSAGE_INVALID", { status: 400 });
  const key = input.clientMessageId == null ? null : commandId(input.clientMessageId);
  const result = await q(`WITH member AS MATERIALIZED (
      SELECT p.id,p.user_id,p.seat_number,u.full_name FROM mafia_player p JOIN mafia_room r ON r.id=p.room_id
      JOIN app_user u ON u.id=p.user_id WHERE r.id=$1 AND p.user_id=$2 AND p.life_status<>'left' AND r.status<>'cancelled'
      AND (($3='public' AND (p.life_status='alive' OR r.status='completed') AND r.status IN
        ('lobby','day_discussion','day_nomination','day_defense','day_vote','day_revote','completed'))
       OR ($3='mafia' AND p.life_status='alive' AND p.team='mafia' AND r.status='night')
       OR ($3='dead' AND p.life_status='dead')) FOR SHARE OF r
    ), inserted AS (
      INSERT INTO mafia_message(room_id,sender_player_id,channel,body,client_message_id)
      SELECT $1,id,$3,$4,$5 FROM member
      ON CONFLICT(room_id,sender_player_id,client_message_id) WHERE client_message_id IS NOT NULL
        DO UPDATE SET client_message_id=EXCLUDED.client_message_id
        WHERE mafia_message.body=EXCLUDED.body AND mafia_message.channel=EXCLUDED.channel RETURNING *
    ) SELECT m.*,p.user_id,p.seat_number,p.full_name FROM inserted m JOIN member p ON p.id=m.sender_player_id`,
    [safeRoomId,id(userId),String(input.channel || 'public'),body,key]);
  const row = result.rows[0];
  if (!row) throw new AppError('MAFIA_MESSAGE_FORBIDDEN', {status:403});
  return {ok:true,message:{id:Number(row.id),body:row.body,channel:row.channel,userId:Number(row.user_id),
    seatNumber:Number(row.seat_number),senderName:row.full_name,createdAt:row.created_at,clientMessageId:row.client_message_id}};
}

export async function sendMafiaInteraction(userId, roomId, input) {
  const safeRoomId = id(roomId);
  const safeUserId = id(userId);
  const safeCommandId = commandId(input.commandId);
  const client = await pool.connect();
  let event;
  try {
    await client.query("BEGIN");
    const room = await loadRoom(client, safeRoomId, true);
    const isHonor = input.interactionType === "honor" && input.kind === "mvp";
    if (
      (isHonor && room.status !== "completed") ||
      (!isHonor && ["completed", "cancelled"].includes(room.status))
    ) {
      throw new AppError("MAFIA_INTERACTION_NOT_ALLOWED", { status: 409 });
    }
    const player = await loadPlayer(client, safeRoomId, safeUserId, true);
    if (player.life_status === "left") {
      throw new AppError("MAFIA_ROOM_FORBIDDEN", { status: 403 });
    }
    let target = null;
    if (input.targetPlayerId != null) {
      const targetResult = await client.query(
        `SELECT p.*,u.full_name FROM mafia_player p
         JOIN app_user u ON u.id=p.user_id
         WHERE p.room_id=$1 AND p.id=$2 AND p.life_status<>'left'`,
        [safeRoomId, id(input.targetPlayerId)],
      );
      target = targetResult.rows[0];
      if (!target || Number(target.id) === Number(player.id)) {
        throw new AppError("MAFIA_INTERACTION_TARGET_INVALID", { status: 400 });
      }
    }
    if (isHonor) {
      const existingHonor = await client.query(
        `SELECT 1 FROM mafia_event
         WHERE room_id=$1 AND event_type='player_interaction'
           AND payload->>'senderPlayerId'=$2 AND payload->>'kind'='mvp'
         LIMIT 1`,
        [safeRoomId, String(player.id)],
      );
      if (existingHonor.rows[0]) {
        throw new AppError("MAFIA_HONOR_ALREADY_CAST", { status: 409 });
      }
    } else {
      const recent = await client.query(
        `SELECT 1 FROM mafia_event
         WHERE room_id=$1 AND event_type='player_interaction'
           AND payload->>'senderPlayerId'=$2
           AND created_at > NOW() - INTERVAL '1200 milliseconds'
         LIMIT 1`,
        [safeRoomId, String(player.id)],
      );
      if (recent.rows[0]) {
        throw new AppError("MAFIA_INTERACTION_RATE_LIMIT", { status: 429 });
      }
    }
    const payload = {
      interactionType: input.interactionType,
      kind: input.kind,
      commandId: safeCommandId,
      senderPlayerId: Number(player.id),
      senderUserId: safeUserId,
      senderName: player.full_name,
      senderSeatNumber: Number(player.seat_number),
      targetPlayerId: target ? Number(target.id) : null,
      targetUserId: target ? Number(target.user_id) : null,
      targetName: target?.full_name || null,
      targetSeatNumber: target ? Number(target.seat_number) : null,
    };
    const inserted = await client.query(
      `INSERT INTO mafia_event (room_id,day_number,event_type,payload)
       VALUES ($1,$2,'player_interaction',$3::jsonb)
       RETURNING id,created_at`,
      [safeRoomId, room.day_number, JSON.stringify(payload)],
    );
    event = {
      id: Number(inserted.rows[0].id),
      type: "player_interaction",
      payload,
      createdAt: inserted.rows[0].created_at,
    };
    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
  return { ok: true, event };
}

export async function reportMafiaPlayer(userId, roomId, input) {
  const safeRoomId = id(roomId);
  const safeUserId = id(userId);
  const safeCommandId = commandId(input.commandId);
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const room = await loadRoom(client, safeRoomId, true);
    const reporter = await loadPlayer(client, safeRoomId, safeUserId, true);
    if (reporter.life_status === "left" || room.status === "cancelled") {
      throw new AppError("MAFIA_REPORT_NOT_ALLOWED", { status: 409 });
    }
    const targetResult = await client.query(
      `SELECT p.*,u.full_name FROM mafia_player p
       JOIN app_user u ON u.id=p.user_id
       WHERE p.room_id=$1 AND p.id=$2 AND p.life_status<>'left'`,
      [safeRoomId, id(input.targetPlayerId)],
    );
    const target = targetResult.rows[0];
    if (!target || Number(target.id) === Number(reporter.id)) {
      throw new AppError("MAFIA_REPORT_TARGET_INVALID", { status: 400 });
    }
    const existing = await client.query(
      `SELECT id FROM mafia_event
       WHERE room_id=$1 AND event_type='player_reported'
         AND payload->>'reporterPlayerId'=$2
         AND payload->>'targetPlayerId'=$3
       LIMIT 1`,
      [safeRoomId, String(reporter.id), String(target.id)],
    );
    if (existing.rows[0]) {
      await client.query("COMMIT");
      return { ok: true, duplicate: true, reportId: Number(existing.rows[0].id) };
    }
    const payload = {
      commandId: safeCommandId,
      status: "pending",
      reason: input.reason,
      details: input.details || null,
      reporterPlayerId: Number(reporter.id),
      reporterUserId: safeUserId,
      reporterName: reporter.full_name,
      targetPlayerId: Number(target.id),
      targetUserId: Number(target.user_id),
      targetName: target.full_name,
    };
    const inserted = await client.query(
      `INSERT INTO mafia_event
         (room_id,day_number,event_type,visibility,recipient_player_id,payload)
       VALUES ($1,$2,'player_reported','private',$3,$4::jsonb)
       RETURNING id,created_at`,
      [safeRoomId, room.day_number, reporter.id, JSON.stringify(payload)],
    );
    await client.query("COMMIT");
    return {
      ok: true,
      duplicate: false,
      reportId: Number(inserted.rows[0].id),
      createdAt: inserted.rows[0].created_at,
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function listMafiaReports(limit = 50) {
  const result = await q(
    `SELECT e.id,e.room_id,e.day_number,e.payload,e.created_at,
       reporter.full_name AS reporter_name,target.full_name AS target_name
     FROM mafia_event e
     LEFT JOIN app_user reporter
       ON reporter.id=(e.payload->>'reporterUserId')::bigint
     LEFT JOIN app_user target
       ON target.id=(e.payload->>'targetUserId')::bigint
     WHERE e.event_type='player_reported'
     ORDER BY (COALESCE(e.payload->>'status','pending')='pending') DESC,e.id DESC
     LIMIT $1`,
    [Math.min(200, Math.max(1, Number(limit) || 50))],
  );
  return result.rows.map((row) => ({
    reportId: Number(row.id),
    roomId: Number(row.room_id),
    dayNumber: Number(row.day_number),
    reporterName: row.reporter_name,
    targetName: row.target_name,
    ...row.payload,
    createdAt: row.created_at,
  }));
}

export async function reviewMafiaReport(reviewerUserId, reportId, note = null) {
  const result = await q(
    `UPDATE mafia_event
     SET payload=payload || jsonb_build_object(
       'status','reviewed',
       'reviewedBy',$2::bigint,
       'reviewedAt',NOW(),
       'reviewNote',$3::text
     )
     WHERE id=$1 AND event_type='player_reported'
     RETURNING id,payload`,
    [id(reportId, "MAFIA_REPORT_ID_INVALID"), id(reviewerUserId), note],
  );
  if (!result.rows[0]) {
    throw new AppError("MAFIA_REPORT_NOT_FOUND", { status: 404 });
  }
  return {
    ok: true,
    reportId: Number(result.rows[0].id),
    status: result.rows[0].payload.status,
  };
}

export async function mafiaHeartbeat(userId, roomId) {
  const safeRoomId = id(roomId);
  const result = await q(
    `UPDATE mafia_player SET last_seen_at=NOW(),disconnected_at=NULL
     WHERE room_id=$1 AND user_id=$2 RETURNING id`,
    [safeRoomId, id(userId)],
  );
  if (!result.rows[0]) throw new AppError("MAFIA_ROOM_FORBIDDEN", { status: 403 });
  return { ok: true };
}

export async function leaveMafiaRoom(userId, roomId) {
  const safeRoomId = id(roomId);
  const safeUserId = id(userId);
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const room = await loadRoom(client, safeRoomId, true);
    const player = await loadPlayer(client, safeRoomId, safeUserId, true);
    if (room.status === "lobby") {
      await client.query(`DELETE FROM mafia_player WHERE id=$1`, [player.id]);
    } else if (room.status !== "completed") {
      await client.query(
        `UPDATE mafia_player SET life_status='left',eliminated_at=NOW(),eliminated_reason='left'
         WHERE id=$1`,
        [player.id],
      );
      await completeIfWon(client, room);
    }
    if (Number(room.host_user_id) === safeUserId) {
      const replacement = await client.query(
        `SELECT user_id FROM mafia_player WHERE room_id=$1 AND life_status<>'left'
         ORDER BY seat_number LIMIT 1`,
        [safeRoomId],
      );
      if (replacement.rows[0]) {
        await client.query(`UPDATE mafia_room SET host_user_id=$2 WHERE id=$1`, [safeRoomId, replacement.rows[0].user_id]);
      } else {
        await client.query(
          `UPDATE mafia_room SET status='cancelled',completed_at=NOW(),phase_ends_at=NULL WHERE id=$1`,
          [safeRoomId],
        );
      }
    }
    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
  return { ok: true };
}

export async function kickMafiaPlayer(userId, roomId, playerId) {
  const safeUserId = id(userId);
  const safeRoomId = id(roomId);
  const safePlayerId = id(playerId, "MAFIA_PLAYER_ID_INVALID");
  const client = await pool.connect();
  let room;
  let target;
  try {
    await client.query("BEGIN");
    room = await loadRoom(client, safeRoomId, true);
    if (Number(room.host_user_id) !== safeUserId) {
      throw new AppError("MAFIA_HOST_REQUIRED", { status: 403 });
    }
    if (["completed", "cancelled"].includes(room.status)) {
      throw new AppError("MAFIA_KICK_ROOM_CLOSED", { status: 409 });
    }
    const targetResult = await client.query(
      `SELECT p.*,u.full_name FROM mafia_player p
       JOIN app_user u ON u.id=p.user_id
       WHERE p.room_id=$1 AND p.id=$2 FOR UPDATE OF p`,
      [safeRoomId, safePlayerId],
    );
    target = targetResult.rows[0];
    if (!target || target.life_status === "left") {
      throw new AppError("MAFIA_PLAYER_NOT_FOUND", { status: 404 });
    }
    if (Number(target.user_id) === safeUserId) {
      throw new AppError("MAFIA_HOST_CANNOT_KICK_SELF", { status: 409 });
    }

    const nextSettings = settings(room);
    const kickedUserIds = new Set(
      (nextSettings.kickedUserIds || []).map(Number).filter(Number.isInteger),
    );
    kickedUserIds.add(Number(target.user_id));
    if (room.status === "lobby") {
      await client.query(`DELETE FROM mafia_player WHERE id=$1`, [safePlayerId]);
    } else {
      // Keep the historical player row, while removing every unresolved action
      // that could make a kicked player affect the remainder of the round.
      await client.query(
        `DELETE FROM mafia_action
         WHERE room_id=$1 AND (actor_player_id=$2 OR target_player_id=$2)`,
        [safeRoomId, safePlayerId],
      );
      await client.query(
        `DELETE FROM mafia_ballot
         WHERE room_id=$1 AND (voter_player_id=$2 OR target_player_id=$2)`,
        [safeRoomId, safePlayerId],
      );
      await client.query(
        `UPDATE mafia_player SET life_status='left',disconnected_at=NOW(),
           eliminated_at=COALESCE(eliminated_at,NOW()),eliminated_reason='host_kick'
         WHERE id=$1`,
        [safePlayerId],
      );
    }
    const candidateIds = (nextSettings.candidateIds || [])
      .map(Number)
      .filter((candidateId) => candidateId !== safePlayerId);
    const revoteCandidateIds = (nextSettings.revoteCandidateIds || [])
      .map(Number)
      .filter((candidateId) => candidateId !== safePlayerId);
    const persistedSettings = {
      ...nextSettings,
      kickedUserIds: [...kickedUserIds],
      candidateIds,
      revoteCandidateIds,
    };
    const updated = await client.query(
      `UPDATE mafia_room SET settings=$2::jsonb,phase_version=phase_version+1,updated_at=NOW()
       WHERE id=$1 RETURNING *`,
      [safeRoomId, JSON.stringify(persistedSettings)],
    );
    room = updated.rows[0];
    if (room.status !== "lobby") {
      const completed = await completeIfWon(client, room);
      if (completed) {
        room = completed;
      } else if (
        ["day_defense", "day_vote", "day_revote"].includes(room.status) &&
        candidateIds.length === 0
      ) {
        room = await setPhase(client, room, "night", {
          settings: { candidateIds: [], revoteCandidateIds: [] },
        });
      }
    }
    await client.query(
      `INSERT INTO mafia_event (room_id,day_number,event_type,payload)
       VALUES ($1,$2,'player_kicked',$3::jsonb)`,
      [safeRoomId, room.day_number, JSON.stringify({
        playerId: safePlayerId,
        userId: Number(target.user_id),
        seatNumber: Number(target.seat_number),
        name: target.full_name,
      })],
    );
    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }

  return getMafiaSnapshot(safeRoomId, safeUserId);
}

export async function closeMafiaRoom(userId, roomId) {
  const safeUserId = id(userId);
  const safeRoomId = id(roomId);
  const client = await pool.connect();
  let room;
  try {
    await client.query("BEGIN");
    room = await loadRoom(client, safeRoomId, true);
    if (Number(room.host_user_id) !== safeUserId) {
      throw new AppError("MAFIA_HOST_REQUIRED", { status: 403 });
    }
    if (room.status === "completed") {
      throw new AppError("MAFIA_ROOM_ALREADY_COMPLETED", { status: 409 });
    }
    if (room.status !== "cancelled") {
      const updated = await client.query(
        `UPDATE mafia_room SET status='cancelled',completed_at=NOW(),phase_ends_at=NULL,
           phase_started_at=NOW(),phase_version=phase_version+1,updated_at=NOW()
         WHERE id=$1 RETURNING *`,
        [safeRoomId],
      );
      room = updated.rows[0];
      await client.query(
        `UPDATE mafia_player SET life_status='left',disconnected_at=COALESCE(disconnected_at,NOW()),
           eliminated_at=COALESCE(eliminated_at,NOW()),
           eliminated_reason=COALESCE(eliminated_reason,'room_closed')
         WHERE room_id=$1 AND life_status<>'left'`,
        [safeRoomId],
      );
      await client.query(
        `INSERT INTO mafia_event (room_id,day_number,event_type,payload)
         VALUES ($1,$2,'room_closed',$3::jsonb)`,
        [safeRoomId, room.day_number, JSON.stringify({ closedByUserId: safeUserId })],
      );
    }
    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }

  return getMafiaSnapshot(safeRoomId, safeUserId);
}

export async function getMafiaSnapshot(roomId, userId) {
  const safeRoomId = id(roomId);
  const safeUserId = id(userId);
    const state = await readMafiaState(safeRoomId, safeUserId);
    const {room,me} = state;
    const players = state.players || [];
    const roomSettings = settings(room);
    const candidateIds = (roomSettings.candidateIds || []).map(Number);
    const visibleRoles = room.status === "completed" || room.status === "cancelled";
    const events = {rows:state.events || []};
    const messages = {rows:state.messages || []};
    const myAction = {rows:state.actions || []};
    const myBallots = {rows:state.ballots || []};
    const remainingSeconds = room.phase_ends_at
      ? Math.max(0, Math.ceil((new Date(room.phase_ends_at).getTime() - Date.now()) / 1000))
      : null;
    const mafiaTeam = me.team === "mafia"
      ? players.filter((player) => player.team === "mafia").map((player) => Number(player.id))
      : [];
    let mission = state.mission && typeof state.mission === "object"
      ? { ...state.mission }
      : null;
    if (mission) {
      if (mission.type === "perform_role" && me.role === "citizen") {
        mission = {
          type: "cast_vote",
          title: "صوت المدينة",
          description: "شارك في تصويت نهاري واحد على الأقل.",
        };
      }
      const row = state.progress || {};
      const completed = {
        survive: room.status === "completed" && me.life_status === "alive",
        cast_vote: row.cast_vote === true,
        use_reaction: row.used_reaction === true,
        send_gift: row.sent_gift === true,
        perform_role: row.performed_role === true,
      }[mission.type] === true;
      mission = { ...mission, completed };
    }
    const profileRow = state.profile || {};
    const profile = {
      gamesPlayed: Number(profileRow.games_played || 0),
      wins: Number(profileRow.wins || 0),
      survivals: Number(profileRow.survivals || 0),
      detectiveGames: Number(profileRow.detective_games || 0),
    };
    profile.level = 1 + Math.floor((profile.gamesPlayed + profile.wins * 2) / 4);
    profile.points = profile.gamesPlayed * 20 + profile.wins * 35 + profile.survivals * 10;
    profile.season = "season_1";
    profile.achievements = [
      profile.gamesPlayed >= 1 ? { id: "first_night", title: "أول ليلة" } : null,
      profile.wins >= 3 ? { id: "city_guardian", title: "حارس المدينة" } : null,
      profile.survivals >= 3 ? { id: "last_light", title: "الضوء الأخير" } : null,
      profile.detectiveGames >= 3 ? { id: "sharp_eye", title: "عين المحقق" } : null,
    ].filter(Boolean);
    let summary = null;
    if (room.status === "completed") {
      const honorRows = {rows:state.honors || []};
      const myHonor = state.my_honor;
      summary = {
        winner: room.winner,
        days: Number(room.day_number),
        eliminations: events.rows
          .filter((event) => event.event_type === "player_eliminated")
          .map((event) => ({
            eventId: Number(event.id),
            dayNumber: Number(event.day_number),
            ...event.payload,
          })),
        honors: honorRows.rows.map((row) => ({
          playerId: Number(row.player_id),
          votes: Number(row.votes),
        })),
        myHonorPlayerId: myHonor ? Number(myHonor.targetPlayerId) : null,
      };
    }
    const latestEvent = events.rows[0];
    const latestNarrativeEvent = latestEvent?.event_type === "player_eliminated"
      ? latestEvent
      : null;
    return {
      serverTime: state.server_time,
      stateVersion: Number(state.revision),
      room: { ...publicRoom(room), settings: roomSettings },
      phase: {
        status: room.status,
        remainingSeconds,
        durationSeconds: mafiaPhaseSeconds(room, room.status),
        candidateIds,
      },
      narrator: mafiaNarratorCue(room, latestNarrativeEvent),
      mission,
      profile,
      summary,
      me: {
        playerId: Number(me.id),
        userId: Number(me.user_id),
        seatNumber: Number(me.seat_number),
        role: me.role,
        team: me.team,
        lifeStatus: me.life_status,
        isReady: me.is_ready === true,
        roleAcknowledged: me.role_acknowledged === true,
        mafiaTeammateIds: mafiaTeam,
        previousDoctorTargetId: me.role === 'doctor' && state.previous_doctor != null ? Number(state.previous_doctor) : null,
      },
      players: players.map((player) => ({
        playerId: Number(player.id),
        userId: Number(player.user_id),
        seatNumber: Number(player.seat_number),
        name: player.full_name,
        imageUrl: player.image_url,
        lifeStatus: player.life_status,
        isReady: player.is_ready === true,
        isConnected: player.disconnected_at == null &&
          Date.now() - new Date(player.last_seen_at).getTime() < 45_000,
        role: visibleRoles || Number(player.id) === Number(me.id) ||
          (roomSettings.revealRolesOnDeath !== false && player.life_status === "dead")
          ? player.role
          : null,
        isMafiaTeammate: mafiaTeam.includes(Number(player.id)),
      })),
      myAction: myAction.rows[0] ? {
        type: myAction.rows[0].action_type,
        targetPlayerId: Number(myAction.rows[0].target_player_id),
      } : null,
      myActions: Object.fromEntries(myAction.rows.map(a=>[a.action_type,Number(a.target_player_id)])),
      myBallots: Object.fromEntries(myBallots.rows.map((row) => [
        row.ballot_type,
        row.target_player_id == null ? null : Number(row.target_player_id),
      ])),
      events: events.rows.reverse().map((event) => ({
        id: Number(event.id),
        dayNumber: Number(event.day_number),
        type: event.event_type,
        payload: event.payload,
        createdAt: event.created_at,
      })),
      messages: messages.rows.reverse().map((message) => ({
        id: Number(message.id),
        channel: message.channel,
        body: message.body,
        userId: Number(message.user_id),
        seatNumber: Number(message.seat_number),
        senderName: message.full_name,
        createdAt: message.created_at,
        clientMessageId: message.client_message_id,
      })),
      voice: {
        enabled: mafiaVoiceConfigured(),
        canRequestToken: mafiaVoiceConfigured() && room.status !== "cancelled" && me.life_status !== 'left',
      },
    };
}

export async function getMafiaVoiceAccess(userId, roomId) {
  const safeRoomId = id(roomId);
  const client = await pool.connect();
  try {
    const room = await loadRoom(client, safeRoomId);
    if (room.status === "cancelled") {
      throw new AppError("MAFIA_ROOM_CLOSED", { status: 409 });
    }
    const safeUserId = id(userId);
    const player = await loadPlayer(client, safeRoomId, safeUserId);
    if (
      player.life_status === "left" ||
      (settings(room).kickedUserIds || []).map(Number).includes(safeUserId)
    ) {
      throw new AppError("MAFIA_ROOM_FORBIDDEN", { status: 403 });
    }
    if (mafiaVoiceConfigured()) {
      // A resumed SDK connection may still hold its previous token's grants.
      // Reconcile connected participants asynchronously, without a provider call.
      await client.query(`UPDATE mafia_room_delivery SET voice_pending=TRUE,voice_revision=voice_revision+1 WHERE room_id=$1`, [safeRoomId]);
    }
    return issueMafiaVoiceToken(
      room,
      player,
      player.full_name,
      settings(room).candidateIds || [],
    );
  } finally {
    client.release();
  }
}

export async function listMyMafiaRooms(userId, limit = 20) {
  const result = await q(
    `SELECT r.id,r.invite_code,r.host_user_id,r.status,r.ruleset,r.winner,r.settings,
       r.max_players,r.day_number,r.created_at,r.updated_at,r.completed_at,
       p.life_status,p.role,
       (SELECT COUNT(*)::int FROM mafia_player rp
        WHERE rp.room_id=r.id AND rp.life_status<>'left') AS player_count
     FROM mafia_room r JOIN mafia_player p ON p.room_id=r.id
     WHERE p.user_id=$1 ORDER BY r.updated_at DESC LIMIT $2`,
    [id(userId), Math.min(50, Math.max(1, Number(limit) || 20))],
  );
  return result.rows.map((row) => ({
    roomId: Number(row.id), inviteCode: row.invite_code, status: row.status,
    ruleset: row.ruleset, winner: row.winner, dayNumber: Number(row.day_number),
    pace: settings(row).pace === "quick" ? "quick" : "classic",
    tableTheme: ["royal", "cinema"].includes(settings(row).tableTheme)
      ? settings(row).tableTheme
      : "emerald",
    revealRolesOnDeath: settings(row).revealRolesOnDeath !== false,
    hostUserId: Number(row.host_user_id), isHost: Number(row.host_user_id) === id(userId),
    maxPlayers: Number(row.max_players), playerCount: Number(row.player_count),
    lifeStatus: row.life_status, role: row.status === "completed" ? row.role : null,
    createdAt: row.created_at, updatedAt: row.updated_at, completedAt: row.completed_at,
  }));
}

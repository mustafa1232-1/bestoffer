import crypto from "node:crypto";

import { pool, q } from "../../config/db.js";
import { AppError } from "../../shared/utils/errors.js";
import { emitRealtimeToUsers } from "../../shared/realtime/realtime-gateway.js";
import { TEAM_CODE_PUZZLES, validatePuzzleBank } from "./games.puzzle-bank.js";
import {
  issueTeamCodeVoiceToken,
  removeTeamCodeVoiceParticipant,
  teamCodeVoiceConfigured,
} from "./team-code.voice.js";

const ROOM_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
const RECONNECT_DETECT_SECONDS = 35;
const RECONNECT_GRACE_SECONDS = 120;
const EMPTY_ROOM_RETURN_MINUTES = 10;
const ROUND_LIMIT_SECONDS = Object.freeze({ easy: 150, medium: 120, hard: 90 });
const QUICK_MESSAGES = new Set([
  "عندي دليل",
  "راجعوا الترتيب",
  "شنو رأيكم؟",
  "نحتاج تلميح",
]);

let seedPromise = null;

function numericId(value, code = "INVALID_ID") {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) throw new AppError(code, { status: 400 });
  return parsed;
}

function assertCommandId(value) {
  const normalized = String(value || "").trim();
  if (!/^[A-Za-z0-9._:-]{8,80}$/.test(normalized)) {
    throw new AppError("GAME_COMMAND_ID_INVALID", { status: 400 });
  }
  return normalized;
}

function makeInviteCode() {
  const bytes = crypto.randomBytes(6);
  return [...bytes].map((byte) => ROOM_ALPHABET[byte % ROOM_ALPHABET.length]).join("");
}

function localeText(value) {
  if (!value || typeof value !== "object") return { ar: "", en: "" };
  return { ar: String(value.ar || ""), en: String(value.en || "") };
}

export function distributeClueIndexes(clueCount, membershipIds) {
  const members = [...new Set((membershipIds || []).map(Number).filter((id) => id > 0))];
  if (members.length < 1 || members.length > 4) return [];
  return Array.from({ length: Math.max(0, Number(clueCount) || 0) }, (_, clueIndex) => ({
    clueIndex,
    membershipId: members[clueIndex % members.length],
  }));
}

export function gameRoundLimitSeconds(difficulty, mode = "solo") {
  const base = ROUND_LIMIT_SECONDS[difficulty] || ROUND_LIMIT_SECONDS.medium;
  return base + (mode === "cooperative" ? 30 : 0);
}

function roundClock(round) {
  const limitSeconds = gameRoundLimitSeconds(round.difficulty, round.room_mode);
  const startedAt = new Date(round.started_at).getTime();
  const serverNow = new Date(round.server_now || Date.now()).getTime();
  const deadlineMs = startedAt + limitSeconds * 1000;
  return {
    limitSeconds,
    deadlineAt: new Date(deadlineMs),
    remainingSeconds: Math.max(0, Math.ceil((deadlineMs - serverNow) / 1000)),
  };
}

function assertRoundInTime(round) {
  if (round.status !== "active") {
    throw new AppError("GAME_ROUND_NOT_ACTIVE", { status: 409 });
  }
  if (roundClock(round).remainingSeconds <= 0) {
    throw new AppError("GAME_ROUND_TIMED_OUT", { status: 409 });
  }
}

export async function seedTeamCodePuzzles() {
  const validation = validatePuzzleBank();
  if (!validation.valid || validation.count !== 30) {
    throw new AppError("GAME_PUZZLE_BANK_INVALID", {
      status: 500,
      details: validation.results.filter((item) => !item.valid),
    });
  }

  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    for (const puzzle of TEAM_CODE_PUZZLES) {
      const definition = await client.query(
        `INSERT INTO game_puzzle_definition
           (slug, title_ar, title_en, difficulty, theme, is_active, updated_at)
         VALUES ($1,$2,$3,$4,$5,TRUE,NOW())
         ON CONFLICT (slug) DO UPDATE SET
           title_ar=EXCLUDED.title_ar,
           title_en=EXCLUDED.title_en,
           difficulty=EXCLUDED.difficulty,
           theme=EXCLUDED.theme,
           is_active=TRUE,
           updated_at=NOW()
         RETURNING id`,
        [puzzle.slug, puzzle.titleAr, puzzle.titleEn, puzzle.difficulty, puzzle.theme],
      );
      await client.query(
        `INSERT INTO game_puzzle_version
           (puzzle_id, version, code_length, solution_code, constraints_json,
            clues_json, hints_json, explanation_ar, explanation_en,
            is_verified, verified_solution_count)
         VALUES ($1,$2,$3,$4,$5::jsonb,$6::jsonb,$7::jsonb,$8,$9,TRUE,1)
         ON CONFLICT (puzzle_id, version) DO UPDATE SET
           code_length=EXCLUDED.code_length,
           solution_code=EXCLUDED.solution_code,
           constraints_json=EXCLUDED.constraints_json,
           clues_json=EXCLUDED.clues_json,
           hints_json=EXCLUDED.hints_json,
           explanation_ar=EXCLUDED.explanation_ar,
           explanation_en=EXCLUDED.explanation_en,
           is_verified=TRUE,
           verified_solution_count=1`,
        [
          definition.rows[0].id,
          puzzle.version,
          puzzle.codeLength,
          puzzle.solutionCode,
          JSON.stringify(puzzle.constraints),
          JSON.stringify(puzzle.clues),
          JSON.stringify(puzzle.hints),
          puzzle.explanationAr,
          puzzle.explanationEn,
        ],
      );
    }
    await client.query("COMMIT");
    return validation;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

async function ensureSeeded() {
  if (!seedPromise) {
    seedPromise = seedTeamCodePuzzles().catch((error) => {
      seedPromise = null;
      throw error;
    });
  }
  return seedPromise;
}

async function getCampaign(client = { query: q }, { lock = false } = {}) {
  const result = await client.query(
    `SELECT *,
       (is_enabled = TRUE
        AND (starts_at IS NULL OR starts_at <= NOW())
        AND (ends_at IS NULL OR ends_at >= NOW())) AS is_available
     FROM game_campaign
     WHERE campaign_key='team_code_test'
     LIMIT 1${lock ? " FOR UPDATE" : ""}`,
  );
  return result.rows[0] || null;
}

function publicCampaign(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    title: row.title,
    configuredEnabled: row.is_enabled === true,
    enabled: row.is_available === true,
    startsAt: row.starts_at,
    endsAt: row.ends_at,
    rewardType: row.reward_type,
    rewardValue: Number(row.reward_value || 0),
    rewardValidDays: Number(row.reward_valid_days || 0),
    claimLimit: row.claim_limit == null ? null : Number(row.claim_limit),
    claimedCount: Number(row.claimed_count || 0),
    remainingClaims:
      row.claim_limit == null
        ? null
        : Math.max(0, Number(row.claim_limit) - Number(row.claimed_count || 0)),
    isMock: row.is_mock === true,
  };
}

async function requireEnabled(client = { query: q }) {
  await ensureSeeded();
  const campaign = await getCampaign(client);
  if (!campaign?.is_available) throw new AppError("GAME_DISABLED", { status: 403 });
  return campaign;
}

async function abandonExpiredPausedRooms(client = { query: q }) {
  await client.query(
    `WITH abandoned AS (
       UPDATE game_room
       SET status='abandoned',abandoned_at=NOW(),completed_at=NOW(),
           updated_at=NOW(),state_version=state_version+1
       WHERE status='paused' AND paused_at IS NOT NULL
         AND paused_at < NOW() - ($1::int * INTERVAL '1 minute')
       RETURNING id
     )
     UPDATE game_session SET status='abandoned',completed_at=NOW(),updated_at=NOW()
     WHERE room_id IN (SELECT id FROM abandoned) AND status='paused'`,
    [EMPTY_ROOM_RETURN_MINUTES],
  );
}

export async function getGamesStatus(userId) {
  await ensureSeeded();
  await abandonExpiredPausedRooms();
  const campaign = await getCampaign();
  const active = await q(
    `SELECT r.id, r.invite_code, r.mode, r.status
     FROM game_membership m
     JOIN game_room r ON r.id=m.room_id
     WHERE m.user_id=$1 AND m.left_at IS NULL
       AND r.status IN ('lobby','active','paused')
     ORDER BY r.updated_at DESC LIMIT 1`,
    [numericId(userId)],
  );
  return {
    game: {
      key: "team_code",
      title: "شفرة الفريق",
      enabled: campaign?.is_available === true,
      puzzleCount: 30,
      supportsSolo: true,
      supportsCooperative: true,
      activeRoom: active.rows[0] || null,
    },
    campaign: publicCampaign(campaign),
  };
}

async function selectRoundPuzzlesTx(client, userId) {
  const picked = [];
  for (const difficulty of ["easy", "medium", "hard"]) {
    const result = await client.query(
      `SELECT pv.id
       FROM game_puzzle_version pv
       JOIN game_puzzle_definition pd ON pd.id=pv.puzzle_id
       WHERE pd.is_active=TRUE AND pv.is_verified=TRUE AND pd.difficulty=$1
         AND pv.version=(
           SELECT MAX(latest.version)
           FROM game_puzzle_version latest
           WHERE latest.puzzle_id=pv.puzzle_id AND latest.is_verified=TRUE
         )
       ORDER BY
         CASE WHEN pv.id IN (
           SELECT gr.puzzle_version_id
           FROM game_round gr
           JOIN game_session gs ON gs.id=gr.session_id
           JOIN game_membership gm ON gm.room_id=gs.room_id
           WHERE gm.user_id=$2
           ORDER BY gr.id DESC LIMIT 12
         ) THEN 1 ELSE 0 END,
         RANDOM()
       LIMIT 1`,
      [difficulty, Number(userId)],
    );
    if (!result.rows[0]) throw new AppError("GAME_PUZZLES_UNAVAILABLE", { status: 503 });
    picked.push(Number(result.rows[0].id));
  }
  return picked;
}

async function createSessionTx(client, room, memberships) {
  const puzzleIds = await selectRoundPuzzlesTx(client, room.host_user_id);
  const sessionResult = await client.query(
    `INSERT INTO game_session (room_id, status, current_round_index, started_at)
     VALUES ($1,'active',1,NOW()) RETURNING *`,
    [room.id],
  );
  const session = sessionResult.rows[0];
  for (let index = 0; index < puzzleIds.length; index += 1) {
    const roundResult = await client.query(
      `INSERT INTO game_round
         (session_id, puzzle_version_id, round_index, status, started_at)
       VALUES ($1,$2,$3,$4,$5) RETURNING id`,
      [session.id, puzzleIds[index], index + 1, index === 0 ? "active" : "pending", index === 0 ? new Date() : null],
    );
    const puzzleResult = await client.query(
      `SELECT clues_json FROM game_puzzle_version WHERE id=$1`,
      [puzzleIds[index]],
    );
    const clues = Array.isArray(puzzleResult.rows[0]?.clues_json)
      ? puzzleResult.rows[0].clues_json
      : [];
    const assignments = distributeClueIndexes(
      clues.length,
      memberships.map((membership) => membership.id),
    );
    for (const assignment of assignments) {
      await client.query(
        `INSERT INTO game_clue_assignment (round_id, membership_id, clue_index)
         VALUES ($1,$2,$3) ON CONFLICT (round_id, clue_index) DO NOTHING`,
        [roundResult.rows[0].id, assignment.membershipId, assignment.clueIndex],
      );
    }
  }
  await client.query(
    `UPDATE game_room SET status='active', started_at=NOW(), updated_at=NOW(), state_version=state_version+1
     WHERE id=$1`,
    [room.id],
  );
  return session;
}

async function emitRoomChanged(roomId, reason) {
  const users = await q(
    `SELECT user_id FROM game_membership WHERE room_id=$1 AND left_at IS NULL`,
    [roomId],
  );
  await emitRealtimeToUsers(
    users.rows.map((row) => Number(row.user_id)),
    "game_room_updated",
    { roomId: Number(roomId), reason },
    { module: "games" },
  ).catch(() => null);
}

async function expireMembershipsTx(client, roomId) {
  const abandoned = await client.query(
    `UPDATE game_room
     SET status='abandoned',abandoned_at=NOW(),completed_at=NOW(),
         updated_at=NOW(),state_version=state_version+1
     WHERE id=$1 AND status='paused' AND paused_at IS NOT NULL
       AND paused_at < NOW() - ($2::int * INTERVAL '1 minute')
     RETURNING id`,
    [roomId, EMPTY_ROOM_RETURN_MINUTES],
  );
  if (abandoned.rows[0]) {
    await client.query(
      `UPDATE game_session SET status='abandoned',completed_at=NOW(),updated_at=NOW()
       WHERE room_id=$1 AND status='paused'`,
      [roomId],
    );
    return;
  }

  await client.query(
    `UPDATE game_membership
     SET disconnected_at=COALESCE(disconnected_at, last_seen_at + ($2::int * INTERVAL '1 second'))
     WHERE room_id=$1 AND left_at IS NULL AND is_active=TRUE
       AND last_seen_at < NOW() - ($2::int * INTERVAL '1 second')`,
    [roomId, RECONNECT_DETECT_SECONDS],
  );
  const expired = await client.query(
    `UPDATE game_membership
     SET is_active=FALSE
     WHERE room_id=$1 AND left_at IS NULL AND is_active=TRUE
       AND disconnected_at IS NOT NULL
       AND disconnected_at < NOW() - ($2::int * INTERVAL '1 second')
     RETURNING id`,
    [roomId, RECONNECT_GRACE_SECONDS],
  );
  if (expired.rowCount > 0) {
    await client.query(
      `UPDATE game_clue_assignment
       SET membership_id=NULL, is_shared=TRUE
       WHERE membership_id=ANY($1::bigint[])`,
      [expired.rows.map((row) => Number(row.id))],
    );
    await client.query(
      `UPDATE game_proposal SET status='cancelled', resolved_at=NOW()
       WHERE status='active' AND round_id IN (
         SELECT gr.id FROM game_round gr
         JOIN game_session gs ON gs.id=gr.session_id WHERE gs.room_id=$1
       )`,
      [roomId],
    );
    const active = await client.query(
      `SELECT COUNT(*)::int count FROM game_membership
       WHERE room_id=$1 AND left_at IS NULL AND is_active=TRUE`,
      [roomId],
    );
    if (Number(active.rows[0].count) === 0) {
      await client.query(
        `UPDATE game_room SET status='paused',paused_at=NOW(),updated_at=NOW(),
           state_version=state_version+1 WHERE id=$1 AND status='active'`,
        [roomId],
      );
      await client.query(
        `UPDATE game_session SET status='paused',updated_at=NOW()
         WHERE room_id=$1 AND status='active'`,
        [roomId],
      );
    }
  }
}

async function loadMembershipTx(client, roomId, userId, { lock = false } = {}) {
  const result = await client.query(
    `SELECT * FROM game_membership
     WHERE room_id=$1 AND user_id=$2 AND left_at IS NULL
     LIMIT 1${lock ? " FOR UPDATE" : ""}`,
    [roomId, userId],
  );
  if (!result.rows[0]) throw new AppError("GAME_ROOM_FORBIDDEN", { status: 403 });
  return result.rows[0];
}

async function loadRoomTx(client, roomId, { lock = false } = {}) {
  const result = await client.query(
    `SELECT * FROM game_room WHERE id=$1 LIMIT 1${lock ? " FOR UPDATE" : ""}`,
    [roomId],
  );
  if (!result.rows[0]) throw new AppError("GAME_ROOM_NOT_FOUND", { status: 404 });
  return result.rows[0];
}

async function insertMembershipTx(client, roomId, userId) {
  const restored = await client.query(
    `UPDATE game_membership SET
       is_active=TRUE,left_at=NULL,disconnected_at=NULL,last_seen_at=NOW()
     WHERE room_id=$1 AND user_id=$2
     RETURNING *`,
    [roomId, userId],
  );
  if (restored.rows[0]) return restored.rows[0];

  const seat = await client.query(
    `SELECT candidate FROM generate_series(1,4) candidate
     WHERE NOT EXISTS (
       SELECT 1 FROM game_membership
       WHERE room_id=$1 AND seat_number=candidate AND left_at IS NULL
     ) ORDER BY candidate LIMIT 1`,
    [roomId],
  );
  if (!seat.rows[0]) throw new AppError("GAME_ROOM_FULL", { status: 409 });
  const result = await client.query(
    `INSERT INTO game_membership (room_id,user_id,seat_number)
     VALUES ($1,$2,$3) RETURNING *`,
    [roomId, userId, seat.rows[0].candidate],
  );
  return result.rows[0];
}

export async function createGame(userId, mode = "solo") {
  const safeUserId = numericId(userId);
  const normalizedMode = mode === "cooperative" ? "cooperative" : "solo";
  const client = await pool.connect();
  let room;
  try {
    await client.query("BEGIN");
    const campaign = await requireEnabled(client);
    if (normalizedMode === "solo") {
      const existing = await client.query(
        `SELECT r.id FROM game_room r
         JOIN game_membership m ON m.room_id=r.id
         WHERE m.user_id=$1 AND m.left_at IS NULL AND r.mode='solo'
           AND r.status IN ('active','paused')
         ORDER BY r.updated_at DESC LIMIT 1`,
        [safeUserId],
      );
      if (existing.rows[0]) {
        await client.query("COMMIT");
        return getRoomSnapshot(existing.rows[0].id, safeUserId);
      }
    }
    let inviteCode = null;
    if (normalizedMode === "cooperative") {
      for (let attempt = 0; attempt < 10; attempt += 1) {
        const candidate = makeInviteCode();
        const exists = await client.query(`SELECT 1 FROM game_room WHERE invite_code=$1`, [candidate]);
        if (!exists.rows[0]) { inviteCode = candidate; break; }
      }
      if (!inviteCode) throw new AppError("GAME_ROOM_CODE_UNAVAILABLE", { status: 503 });
    }
    const roomResult = await client.query(
      `INSERT INTO game_room
         (invite_code,mode,status,host_user_id,max_players,campaign_id)
       VALUES ($1,$2,$3,$4,$5,$6) RETURNING *`,
      [inviteCode, normalizedMode, normalizedMode === "solo" ? "active" : "lobby", safeUserId, normalizedMode === "solo" ? 1 : 4, campaign.id],
    );
    room = roomResult.rows[0];
    const membership = await insertMembershipTx(client, room.id, safeUserId);
    if (normalizedMode === "solo") await createSessionTx(client, room, [membership]);
    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
  await emitRoomChanged(room.id, "created");
  return getRoomSnapshot(room.id, safeUserId);
}

export async function joinRoom(userId, code) {
  const safeUserId = numericId(userId);
  const normalizedCode = String(code || "").trim().toUpperCase();
  if (!/^[A-HJ-NP-Z2-9]{6}$/.test(normalizedCode)) {
    throw new AppError("GAME_ROOM_CODE_INVALID", { status: 400 });
  }
  await abandonExpiredPausedRooms();
  const client = await pool.connect();
  let roomId;
  try {
    await client.query("BEGIN");
    await requireEnabled(client);
    const roomResult = await client.query(
      `SELECT * FROM game_room WHERE invite_code=$1 FOR UPDATE`,
      [normalizedCode],
    );
    const room = roomResult.rows[0];
    if (!room) throw new AppError("GAME_ROOM_NOT_FOUND", { status: 404 });
    if (["completed", "failed", "abandoned"].includes(room.status)) {
      throw new AppError("GAME_ROOM_FINISHED", { status: 409 });
    }
    roomId = Number(room.id);
    const previous = await client.query(
      `SELECT * FROM game_membership WHERE room_id=$1 AND user_id=$2`,
      [roomId, safeUserId],
    );
    if (room.status !== "lobby" && !previous.rows[0]) {
      throw new AppError("GAME_ROOM_ALREADY_STARTED", { status: 409 });
    }
    const count = await client.query(
      `SELECT COUNT(*)::int count FROM game_membership
       WHERE room_id=$1 AND left_at IS NULL`,
      [roomId],
    );
    if (!previous.rows[0] && Number(count.rows[0].count) >= Number(room.max_players)) {
      throw new AppError("GAME_ROOM_FULL", { status: 409 });
    }
    await insertMembershipTx(client, roomId, safeUserId);
    await client.query(
      `UPDATE game_room SET state_version=state_version+1, updated_at=NOW() WHERE id=$1`,
      [roomId],
    );
    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
  await emitRoomChanged(roomId, "member_joined");
  return getRoomSnapshot(roomId, safeUserId);
}

export async function setReady(userId, roomId, ready) {
  const safeRoomId = numericId(roomId, "GAME_ROOM_ID_INVALID");
  const membership = await q(
    `UPDATE game_membership m SET is_ready=$3, last_seen_at=NOW(), disconnected_at=NULL
     FROM game_room r
     WHERE m.room_id=$1 AND m.user_id=$2 AND m.left_at IS NULL
       AND r.id=m.room_id AND r.status='lobby'
     RETURNING m.id`,
    [safeRoomId, numericId(userId), ready === true],
  );
  if (!membership.rows[0]) throw new AppError("GAME_LOBBY_UNAVAILABLE", { status: 409 });
  await emitRoomChanged(safeRoomId, "ready_changed");
  return getRoomSnapshot(safeRoomId, userId);
}

export async function startRoom(userId, roomId) {
  const safeRoomId = numericId(roomId, "GAME_ROOM_ID_INVALID");
  const safeUserId = numericId(userId);
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const room = await loadRoomTx(client, safeRoomId, { lock: true });
    await requireEnabled(client);
    if (Number(room.host_user_id) !== safeUserId) throw new AppError("GAME_HOST_ONLY", { status: 403 });
    if (room.status !== "lobby") throw new AppError("GAME_ROOM_ALREADY_STARTED", { status: 409 });
    const membersResult = await client.query(
      `SELECT * FROM game_membership
       WHERE room_id=$1 AND left_at IS NULL AND is_active=TRUE
       ORDER BY joined_at,id FOR UPDATE`,
      [safeRoomId],
    );
    const members = membersResult.rows;
    if (members.length < 2 || members.length > 4) throw new AppError("GAME_PLAYER_COUNT_INVALID", { status: 409 });
    if (members.some((member) => member.is_ready !== true)) throw new AppError("GAME_PLAYERS_NOT_READY", { status: 409 });
    await createSessionTx(client, room, members);
    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
  await emitRoomChanged(safeRoomId, "started");
  return getRoomSnapshot(safeRoomId, safeUserId);
}

async function currentRoundTx(client, roomId, { lock = false } = {}) {
  const result = await client.query(
    `SELECT gr.*, gs.current_round_index, gs.score AS session_score,
       gs.id AS game_session_id, pv.solution_code, pv.code_length,
       pv.clues_json, pv.hints_json, pv.explanation_ar, pv.explanation_en,
       pd.title_ar, pd.title_en, pd.difficulty, pd.theme,
       room.mode AS room_mode, NOW() AS server_now
     FROM game_session gs
     JOIN game_room room ON room.id=gs.room_id
     JOIN game_round gr ON gr.session_id=gs.id AND gr.round_index=gs.current_round_index
     JOIN game_puzzle_version pv ON pv.id=gr.puzzle_version_id
     JOIN game_puzzle_definition pd ON pd.id=pv.puzzle_id
     WHERE gs.room_id=$1 LIMIT 1${lock ? " FOR UPDATE OF gr, gs" : ""}`,
    [roomId],
  );
  if (!result.rows[0]) throw new AppError("GAME_SESSION_NOT_FOUND", { status: 404 });
  return result.rows[0];
}

async function expireTimedRoundTx(client, roomId) {
  const result = await client.query(
    `SELECT gr.id,gr.started_at,pd.difficulty,room.mode AS room_mode,
       gs.id AS game_session_id,NOW() AS server_now
     FROM game_room room
     JOIN game_session gs ON gs.room_id=room.id
     JOIN game_round gr ON gr.session_id=gs.id AND gr.round_index=gs.current_round_index
     JOIN game_puzzle_version pv ON pv.id=gr.puzzle_version_id
     JOIN game_puzzle_definition pd ON pd.id=pv.puzzle_id
     WHERE room.id=$1 AND room.status='active' AND gs.status='active'
       AND gr.status='active'
     FOR UPDATE OF room,gs,gr`,
    [roomId],
  );
  const round = result.rows[0];
  if (!round || roundClock(round).remainingSeconds > 0) return false;
  await client.query(
    `UPDATE game_round SET status='failed',completed_at=NOW() WHERE id=$1`,
    [round.id],
  );
  await client.query(
    `UPDATE game_proposal SET status='expired',resolved_at=NOW()
     WHERE round_id=$1 AND status='active'`,
    [round.id],
  );
  await client.query(
    `UPDATE game_session SET status='failed',completed_at=NOW(),
       state_version=state_version+1,updated_at=NOW() WHERE id=$1`,
    [round.game_session_id],
  );
  await client.query(
    `UPDATE game_room SET status='failed',completed_at=NOW(),
       state_version=state_version+1,updated_at=NOW() WHERE id=$1`,
    [roomId],
  );
  return true;
}

async function persistRoundTimeout(roomId) {
  const client = await pool.connect();
  let expired = false;
  try {
    await client.query("BEGIN");
    expired = await expireTimedRoundTx(client, roomId);
    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
  if (expired) await emitRoomChanged(roomId, "round_timed_out");
}

async function persistTimeoutBeforeRethrow(error, roomId) {
  if (error?.code === "GAME_ROUND_TIMED_OUT") {
    await persistRoundTimeout(roomId);
  }
  throw error;
}

async function applyHintTx(client, round) {
  assertRoundInTime(round);
  if (Number(round.hints_used) >= 3) throw new AppError("GAME_HINTS_EXHAUSTED", { status: 409 });
  await client.query(
    `UPDATE game_round SET hints_used=hints_used+1 WHERE id=$1`,
    [round.id],
  );
  await client.query(
    `UPDATE game_session SET state_version=state_version+1, updated_at=NOW() WHERE id=$1`,
    [round.game_session_id],
  );
}

async function applyAttemptTx(client, round, membershipId, code, commandId) {
  assertRoundInTime(round);
  const normalizedCode = String(code || "").trim();
  if (!new RegExp(`^[0-9]{${round.code_length}}$`).test(normalizedCode)) {
    throw new AppError("GAME_CODE_INVALID", { status: 400 });
  }
  if (new Set(normalizedCode).size !== normalizedCode.length) {
    throw new AppError("GAME_CODE_DIGITS_MUST_BE_UNIQUE", { status: 400 });
  }
  const correct = normalizedCode === String(round.solution_code);
  const inserted = await client.query(
    `INSERT INTO game_attempt (round_id,membership_id,proposed_code,is_correct,command_id)
     VALUES ($1,$2,$3,$4,$5)
     ON CONFLICT (round_id,command_id) DO NOTHING RETURNING id`,
    [round.id, membershipId, normalizedCode, correct, commandId],
  );
  if (!inserted.rows[0]) return { duplicate: true, correct: null };

  if (correct) {
    const clock = roundClock(round);
    const timeBonus = Math.ceil(50 * clock.remainingSeconds / clock.limitSeconds);
    const score = Math.max(
      25,
      100 + timeBonus - Number(round.wrong_attempts) * 10 - Number(round.hints_used) * 15,
    );
    await client.query(
      `UPDATE game_round SET status='solved', score=$2, completed_at=NOW() WHERE id=$1`,
      [round.id, score],
    );
    // A successful vault is the campaign completion unit. Keep eligibility
    // server-owned so retries, clients, and later rounds cannot duplicate it.
    await client.query(
      `UPDATE game_membership gm
       SET reward_eligible=TRUE
       FROM game_session gs
       JOIN game_room room ON room.id=gs.room_id
       WHERE gs.id=$1
         AND gm.room_id=room.id
         AND room.campaign_id IS NOT NULL
         AND gm.is_active=TRUE
         AND gm.left_at IS NULL`,
      [round.game_session_id],
    );
    if (Number(round.round_index) < 3) {
      await client.query(
        `UPDATE game_round SET status='active', started_at=NOW()
         WHERE session_id=$1 AND round_index=$2`,
        [round.game_session_id, Number(round.round_index) + 1],
      );
      await client.query(
        `UPDATE game_session SET current_round_index=current_round_index+1,
           score=score+$2, state_version=state_version+1, updated_at=NOW()
         WHERE id=$1`,
        [round.game_session_id, score],
      );
    } else {
      await client.query(
        `UPDATE game_session SET status='completed', score=score+$2,
           completed_at=NOW(), state_version=state_version+1, updated_at=NOW()
         WHERE id=$1`,
        [round.game_session_id, score],
      );
      await client.query(
        `UPDATE game_room SET status='completed', completed_at=NOW(),
           state_version=state_version+1, updated_at=NOW()
         WHERE id=(SELECT room_id FROM game_session WHERE id=$1)`,
        [round.game_session_id],
      );
    }
  } else {
    const remaining = Math.max(0, Number(round.attempts_remaining) - 1);
    await client.query(
      `UPDATE game_round SET attempts_remaining=$2::smallint, wrong_attempts=wrong_attempts+1,
         status=CASE WHEN $2::smallint=0 THEN 'failed' ELSE status END,
         completed_at=CASE WHEN $2::smallint=0 THEN NOW() ELSE completed_at END
       WHERE id=$1`,
      [round.id, remaining],
    );
    if (remaining === 0) {
      await client.query(
        `UPDATE game_session SET status='failed', completed_at=NOW(),
           state_version=state_version+1, updated_at=NOW() WHERE id=$1`,
        [round.game_session_id],
      );
      await client.query(
        `UPDATE game_room SET status='failed', completed_at=NOW(),
           state_version=state_version+1, updated_at=NOW()
         WHERE id=(SELECT room_id FROM game_session WHERE id=$1)`,
        [round.game_session_id],
      );
    } else {
      await client.query(
        `UPDATE game_session SET state_version=state_version+1, updated_at=NOW() WHERE id=$1`,
        [round.game_session_id],
      );
    }
  }
  return { duplicate: false, correct };
}

export async function submitSoloCode(userId, roomId, { code, commandId }) {
  const safeRoomId = numericId(roomId, "GAME_ROOM_ID_INVALID");
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const room = await loadRoomTx(client, safeRoomId, { lock: true });
    if (room.mode !== "solo") throw new AppError("GAME_SOLO_ONLY", { status: 409 });
    const member = await loadMembershipTx(client, safeRoomId, numericId(userId), { lock: true });
    const round = await currentRoundTx(client, safeRoomId, { lock: true });
    await applyAttemptTx(client, round, member.id, code, assertCommandId(commandId));
    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    return persistTimeoutBeforeRethrow(error, safeRoomId);
  } finally {
    client.release();
  }
  await emitRoomChanged(safeRoomId, "attempt_resolved");
  return getRoomSnapshot(safeRoomId, userId);
}

export async function requestSoloHint(userId, roomId, commandId) {
  const safeRoomId = numericId(roomId, "GAME_ROOM_ID_INVALID");
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const room = await loadRoomTx(client, safeRoomId, { lock: true });
    if (room.mode !== "solo") throw new AppError("GAME_SOLO_ONLY", { status: 409 });
    const safeUserId = numericId(userId);
    await loadMembershipTx(client, safeRoomId, safeUserId);
    const round = await currentRoundTx(client, safeRoomId, { lock: true });
    const command = await client.query(
      `INSERT INTO game_command (room_id,user_id,command_id,command_type)
       VALUES ($1,$2,$3,'solo_hint')
       ON CONFLICT (room_id,user_id,command_id) DO NOTHING RETURNING id`,
      [safeRoomId, safeUserId, assertCommandId(commandId)],
    );
    if (command.rows[0]) await applyHintTx(client, round);
    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    return persistTimeoutBeforeRethrow(error, safeRoomId);
  } finally {
    client.release();
  }
  await emitRoomChanged(safeRoomId, "hint_revealed");
  return getRoomSnapshot(safeRoomId, userId);
}

async function assertVotingAvailableTx(client, roomId) {
  const waiting = await client.query(
    `SELECT 1 FROM game_membership
     WHERE room_id=$1 AND left_at IS NULL AND is_active=TRUE AND disconnected_at IS NOT NULL
     LIMIT 1`,
    [roomId],
  );
  if (waiting.rows[0]) throw new AppError("GAME_WAITING_FOR_RECONNECT", { status: 409 });
}

export async function createProposal(userId, roomId, { kind, code, commandId }) {
  const safeRoomId = numericId(roomId, "GAME_ROOM_ID_INVALID");
  const safeKind = kind === "hint" ? "hint" : "code";
  const client = await pool.connect();
  let proposalId;
  try {
    await client.query("BEGIN");
    const room = await loadRoomTx(client, safeRoomId, { lock: true });
    if (room.mode !== "cooperative" || room.status !== "active") {
      throw new AppError("GAME_COOP_NOT_ACTIVE", { status: 409 });
    }
    await expireMembershipsTx(client, safeRoomId);
    await assertVotingAvailableTx(client, safeRoomId);
    const member = await loadMembershipTx(client, safeRoomId, numericId(userId), { lock: true });
    if (!member.is_active) throw new AppError("GAME_MEMBER_INACTIVE", { status: 409 });
    const round = await currentRoundTx(client, safeRoomId, { lock: true });
    assertRoundInTime(round);
    if (safeKind === "code") {
      const normalized = String(code || "").trim();
      if (!new RegExp(`^[0-9]{${round.code_length}}$`).test(normalized) || new Set(normalized).size !== normalized.length) {
        throw new AppError("GAME_CODE_INVALID", { status: 400 });
      }
    }
    await client.query(
      `UPDATE game_proposal SET status='expired', resolved_at=NOW()
       WHERE round_id=$1 AND status='active' AND expires_at<=NOW()`,
      [round.id],
    );
    const inserted = await client.query(
      `INSERT INTO game_proposal
         (round_id,proposer_membership_id,kind,proposed_code,status,command_id,expires_at)
       VALUES ($1,$2,$3,$4,'active',$5,NOW()+INTERVAL '30 seconds')
       ON CONFLICT (round_id,command_id) DO UPDATE SET command_id=EXCLUDED.command_id
       RETURNING id,status`,
      [round.id, member.id, safeKind, safeKind === "code" ? String(code).trim() : null, assertCommandId(commandId)],
    );
    proposalId = Number(inserted.rows[0].id);
    if (inserted.rows[0].status === "active") {
      await client.query(
        `INSERT INTO game_vote (proposal_id,membership_id,vote)
         VALUES ($1,$2,'approve') ON CONFLICT (proposal_id,membership_id) DO NOTHING`,
        [proposalId, member.id],
      );
    }
    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    if (String(error?.code) === "23505") throw new AppError("GAME_PROPOSAL_ALREADY_ACTIVE", { status: 409 });
    return persistTimeoutBeforeRethrow(error, safeRoomId);
  } finally {
    client.release();
  }
  await emitRoomChanged(safeRoomId, "proposal_created");
  return getRoomSnapshot(safeRoomId, userId);
}

export async function voteProposal(userId, roomId, proposalId, vote) {
  const safeRoomId = numericId(roomId, "GAME_ROOM_ID_INVALID");
  const safeProposalId = numericId(proposalId, "GAME_PROPOSAL_ID_INVALID");
  const normalizedVote = vote === "reject" ? "reject" : "approve";
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await loadRoomTx(client, safeRoomId, { lock: true });
    await expireMembershipsTx(client, safeRoomId);
    await assertVotingAvailableTx(client, safeRoomId);
    const member = await loadMembershipTx(client, safeRoomId, numericId(userId), { lock: true });
    const activeRound = await currentRoundTx(client, safeRoomId, { lock: true });
    assertRoundInTime(activeRound);
    const proposalResult = await client.query(
      `SELECT gp.*, gr.session_id, gr.status AS round_status
       FROM game_proposal gp JOIN game_round gr ON gr.id=gp.round_id
       JOIN game_session gs ON gs.id=gr.session_id
       WHERE gp.id=$1 AND gs.room_id=$2 FOR UPDATE OF gp`,
      [safeProposalId, safeRoomId],
    );
    const proposal = proposalResult.rows[0];
    if (!proposal || proposal.status !== "active") throw new AppError("GAME_PROPOSAL_NOT_ACTIVE", { status: 409 });
    if (new Date(proposal.expires_at).getTime() <= Date.now()) {
      await client.query(`UPDATE game_proposal SET status='expired',resolved_at=NOW() WHERE id=$1`, [safeProposalId]);
      await client.query("COMMIT");
      await emitRoomChanged(safeRoomId, "proposal_expired");
      return getRoomSnapshot(safeRoomId, userId);
    }
    await client.query(
      `INSERT INTO game_vote (proposal_id,membership_id,vote)
       VALUES ($1,$2,$3)
       ON CONFLICT (proposal_id,membership_id) DO UPDATE SET vote=EXCLUDED.vote,created_at=NOW()`,
      [safeProposalId, member.id, normalizedVote],
    );
    if (normalizedVote === "reject") {
      await client.query(`UPDATE game_proposal SET status='rejected',resolved_at=NOW() WHERE id=$1`, [safeProposalId]);
    } else {
      const tally = await client.query(
        `SELECT
           COUNT(*) FILTER (WHERE gv.vote='approve')::int approvals,
           (SELECT COUNT(*)::int FROM game_membership
            WHERE room_id=$2 AND left_at IS NULL AND is_active=TRUE) required
         FROM game_vote gv WHERE gv.proposal_id=$1`,
        [safeProposalId, safeRoomId],
      );
      if (Number(tally.rows[0].approvals) >= Number(tally.rows[0].required)) {
        await client.query(`UPDATE game_proposal SET status='approved',resolved_at=NOW() WHERE id=$1`, [safeProposalId]);
        const round = await currentRoundTx(client, safeRoomId, { lock: true });
        if (proposal.kind === "hint") {
          await applyHintTx(client, round);
        } else {
          await applyAttemptTx(client, round, proposal.proposer_membership_id, proposal.proposed_code, `proposal:${safeProposalId}`);
        }
      }
    }
    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    return persistTimeoutBeforeRethrow(error, safeRoomId);
  } finally {
    client.release();
  }
  await emitRoomChanged(safeRoomId, "vote_changed");
  return getRoomSnapshot(safeRoomId, userId);
}

export async function sendMessage(userId, roomId, body) {
  const safeRoomId = numericId(roomId, "GAME_ROOM_ID_INVALID");
  const normalized = String(body || "").trim().replace(/\s+/g, " ");
  if (!normalized || normalized.length > 300) throw new AppError("GAME_MESSAGE_INVALID", { status: 400 });
  const member = await q(
    `SELECT id FROM game_membership WHERE room_id=$1 AND user_id=$2
       AND left_at IS NULL AND is_active=TRUE`,
    [safeRoomId, numericId(userId)],
  );
  if (!member.rows[0]) throw new AppError("GAME_ROOM_FORBIDDEN", { status: 403 });
  await q(
    `INSERT INTO game_message (room_id,membership_id,body) VALUES ($1,$2,$3)`,
    [safeRoomId, member.rows[0].id, normalized],
  );
  await emitRoomChanged(safeRoomId, QUICK_MESSAGES.has(normalized) ? "quick_message" : "message");
  return { ok: true };
}

export async function heartbeat(userId, roomId) {
  const safeRoomId = numericId(roomId, "GAME_ROOM_ID_INVALID");
  const updated = await q(
    `UPDATE game_membership SET last_seen_at=NOW(), disconnected_at=NULL, is_active=TRUE
     WHERE room_id=$1 AND user_id=$2 AND left_at IS NULL RETURNING id`,
    [safeRoomId, numericId(userId)],
  );
  if (!updated.rows[0]) throw new AppError("GAME_ROOM_FORBIDDEN", { status: 403 });
  return { ok: true, serverTime: new Date().toISOString() };
}

export async function leaveRoom(userId, roomId) {
  const safeRoomId = numericId(roomId, "GAME_ROOM_ID_INVALID");
  const safeUserId = numericId(userId);
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const room = await loadRoomTx(client, safeRoomId, { lock: true });
    const member = await loadMembershipTx(client, safeRoomId, safeUserId, { lock: true });
    await client.query(
      `UPDATE game_membership SET is_active=FALSE,left_at=NOW(),is_ready=FALSE WHERE id=$1`,
      [member.id],
    );
    await client.query(
      `UPDATE game_clue_assignment SET membership_id=NULL,is_shared=TRUE WHERE membership_id=$1`,
      [member.id],
    );
    await client.query(
      `UPDATE game_proposal SET status='cancelled',resolved_at=NOW()
       WHERE status='active' AND round_id IN (
         SELECT gr.id FROM game_round gr JOIN game_session gs ON gs.id=gr.session_id WHERE gs.room_id=$1
       )`,
      [safeRoomId],
    );
    const remaining = await client.query(
      `SELECT * FROM game_membership WHERE room_id=$1 AND left_at IS NULL AND is_active=TRUE
       ORDER BY joined_at,id`,
      [safeRoomId],
    );
    if (Number(room.host_user_id) === safeUserId && remaining.rows[0]) {
      await client.query(`UPDATE game_room SET host_user_id=$2 WHERE id=$1`, [safeRoomId, remaining.rows[0].user_id]);
    }
    if (remaining.rowCount === 0 && ["lobby", "active", "paused"].includes(room.status)) {
      if (room.status === "lobby") {
        await client.query(
          `UPDATE game_room SET status='abandoned',abandoned_at=NOW(),completed_at=NOW(),
             updated_at=NOW(),state_version=state_version+1 WHERE id=$1`,
          [safeRoomId],
        );
      } else {
        await client.query(
          `UPDATE game_room SET status='paused',paused_at=NOW(),updated_at=NOW(),state_version=state_version+1 WHERE id=$1`,
          [safeRoomId],
        );
        await client.query(`UPDATE game_session SET status='paused',updated_at=NOW() WHERE room_id=$1`, [safeRoomId]);
      }
    } else {
      await client.query(`UPDATE game_room SET state_version=state_version+1,updated_at=NOW() WHERE id=$1`, [safeRoomId]);
    }
    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
  removeTeamCodeVoiceParticipant(safeRoomId, safeUserId).catch((error) =>
    console.warn(
      "[team-code-voice] participant removal failed",
      error?.message || error,
    ),
  );
  await emitRoomChanged(safeRoomId, "member_left");
  return { ok: true };
}

export async function getTeamCodeVoiceAccess(userId, roomId) {
  const safeRoomId = numericId(roomId, "GAME_ROOM_ID_INVALID");
  const safeUserId = numericId(userId);
  const result = await q(
    `SELECT r.*,m.id AS membership_id,m.user_id,m.seat_number,u.full_name
     FROM game_room r
     JOIN game_membership m
       ON m.room_id=r.id
      AND m.user_id=$2
      AND m.left_at IS NULL
      AND m.is_active=TRUE
     JOIN app_user u ON u.id=m.user_id
     WHERE r.id=$1
     LIMIT 1`,
    [safeRoomId, safeUserId],
  );
  const row = result.rows[0];
  if (!row) throw new AppError("GAME_ROOM_FORBIDDEN", { status: 403 });
  if (row.mode !== "cooperative") {
    return { enabled: false, reason: "TEAM_CODE_VOICE_SOLO_ROOM" };
  }
  return issueTeamCodeVoiceToken({
    room: row,
    membership: {
      id: row.membership_id,
      user_id: row.user_id,
      seat_number: row.seat_number,
    },
    displayName: row.full_name,
  });
}

export async function continueAlone(userId, roomId) {
  const safeRoomId = numericId(roomId, "GAME_ROOM_ID_INVALID");
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const member = await loadMembershipTx(client, safeRoomId, numericId(userId), { lock: true });
    const active = await client.query(
      `SELECT COUNT(*)::int count FROM game_membership WHERE room_id=$1 AND left_at IS NULL AND is_active=TRUE`,
      [safeRoomId],
    );
    if (Number(active.rows[0].count) !== 1) throw new AppError("GAME_SOLO_CONTINUE_UNAVAILABLE", { status: 409 });
    await client.query(`UPDATE game_room SET mode='solo',status='active',paused_at=NULL,state_version=state_version+1 WHERE id=$1`, [safeRoomId]);
    await client.query(`UPDATE game_session SET status='active',state_version=state_version+1 WHERE room_id=$1`, [safeRoomId]);
    await client.query(
      `UPDATE game_clue_assignment SET membership_id=$2,is_shared=FALSE
       WHERE round_id IN (SELECT gr.id FROM game_round gr JOIN game_session gs ON gs.id=gr.session_id WHERE gs.room_id=$1)`,
      [safeRoomId, member.id],
    );
    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
  await emitRoomChanged(safeRoomId, "continued_solo");
  return getRoomSnapshot(safeRoomId, userId);
}

export async function getRoomSnapshot(roomId, userId) {
  const safeRoomId = numericId(roomId, "GAME_ROOM_ID_INVALID");
  const safeUserId = numericId(userId);
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await expireMembershipsTx(client, safeRoomId);
    const room = await loadRoomTx(client, safeRoomId);
    const me = await loadMembershipTx(client, safeRoomId, safeUserId);
    if (["lobby", "active", "paused"].includes(room.status)) {
      await client.query(
        `UPDATE game_membership SET last_seen_at=NOW(),disconnected_at=NULL,is_active=TRUE WHERE id=$1`,
        [me.id],
      );
      if (room.status === "paused") {
        await client.query(
          `UPDATE game_room SET status='active',paused_at=NULL,updated_at=NOW(),
             state_version=state_version+1 WHERE id=$1`,
          [safeRoomId],
        );
        await client.query(
          `UPDATE game_session SET status='active',updated_at=NOW()
           WHERE room_id=$1 AND status='paused'`,
          [safeRoomId],
        );
        room.status = "active";
        room.paused_at = null;
        room.state_version = Number(room.state_version) + 1;
      }
    }
    if (room.status === "active" && await expireTimedRoundTx(client, safeRoomId)) {
      room.status = "failed";
      room.completed_at = new Date();
      room.state_version = Number(room.state_version) + 1;
    }
    const membersResult = await client.query(
      `SELECT m.id,m.user_id,m.seat_number,m.is_ready,m.is_active,m.joined_at,
         m.last_seen_at,m.disconnected_at,m.reward_eligible,u.full_name,u.image_url
       FROM game_membership m JOIN app_user u ON u.id=m.user_id
       WHERE m.room_id=$1 AND m.left_at IS NULL ORDER BY m.seat_number`,
      [safeRoomId],
    );
    const sessionResult = await client.query(`SELECT * FROM game_session WHERE room_id=$1`, [safeRoomId]);
    const session = sessionResult.rows[0] || null;
    let round = null;
    let proposal = null;
    if (session) {
      const current = await currentRoundTx(client, safeRoomId);
      const clues = Array.isArray(current.clues_json) ? current.clues_json : [];
      const assignmentResult = await client.query(
        `SELECT clue_index,is_shared,membership_id FROM game_clue_assignment WHERE round_id=$1 ORDER BY clue_index`,
        [current.id],
      );
      const visibleIndexes = room.mode === "solo"
        ? clues.map((_, index) => index)
        : assignmentResult.rows
            .filter((item) => item.is_shared === true || Number(item.membership_id) === Number(me.id))
            .map((item) => Number(item.clue_index));
      const hints = Array.isArray(current.hints_json) ? current.hints_json : [];
      const clock = roundClock(current);
      round = {
        id: Number(current.id),
        index: Number(current.round_index),
        title: { ar: current.title_ar, en: current.title_en },
        difficulty: current.difficulty,
        theme: current.theme,
        status: current.status,
        codeLength: Number(current.code_length),
        attemptsRemaining: Number(current.attempts_remaining),
        hintsRemaining: Math.max(0, 3 - Number(current.hints_used)),
        hintsUsed: Number(current.hints_used),
        startedAt: current.started_at,
        timeLimitSeconds: clock.limitSeconds,
        remainingSeconds: clock.remainingSeconds,
        deadlineAt: clock.deadlineAt,
        failureReason:
          current.status === "failed" && Number(current.attempts_remaining) > 0
            ? "timeout"
            : current.status === "failed"
              ? "attempts"
              : null,
        clues: visibleIndexes.map((index) => ({ index, text: localeText(clues[index]?.text) })),
        revealedHints: hints.slice(0, Number(current.hints_used)).map((item, index) => ({ index, text: localeText(item.text) })),
      };
      const proposalResult = await client.query(
        `SELECT gp.*,u.full_name proposer_name,
          COALESCE(jsonb_agg(jsonb_build_object('membershipId',gv.membership_id,'vote',gv.vote))
            FILTER (WHERE gv.id IS NOT NULL),'[]'::jsonb) votes
         FROM game_proposal gp
         JOIN game_membership pm ON pm.id=gp.proposer_membership_id
         JOIN app_user u ON u.id=pm.user_id
         LEFT JOIN game_vote gv ON gv.proposal_id=gp.id
         WHERE gp.round_id=$1 AND gp.status='active' AND gp.expires_at>NOW()
         GROUP BY gp.id,u.full_name LIMIT 1`,
        [current.id],
      );
      if (proposalResult.rows[0]) {
        const item = proposalResult.rows[0];
        proposal = {
          id: Number(item.id),
          kind: item.kind,
          proposedCode: item.proposed_code,
          proposerName: item.proposer_name,
          proposerMembershipId: Number(item.proposer_membership_id),
          expiresAt: item.expires_at,
          votes: item.votes,
        };
      }
    }
    const messages = await client.query(
      `SELECT msg.id,msg.body,msg.created_at,m.user_id,u.full_name
       FROM game_message msg
       JOIN game_membership m ON m.id=msg.membership_id
       JOIN app_user u ON u.id=m.user_id
       WHERE msg.room_id=$1 ORDER BY msg.id DESC LIMIT 50`,
      [safeRoomId],
    );
    let results = [];
    if (session && ["completed", "failed", "abandoned"].includes(session.status)) {
      const solved = await client.query(
        `SELECT gr.round_index,gr.status,gr.score,pv.solution_code,pv.explanation_ar,pv.explanation_en,
          pd.title_ar,pd.title_en
         FROM game_round gr
         JOIN game_puzzle_version pv ON pv.id=gr.puzzle_version_id
         JOIN game_puzzle_definition pd ON pd.id=pv.puzzle_id
         WHERE gr.session_id=$1
           AND gr.started_at IS NOT NULL
         ORDER BY gr.round_index`,
        [session.id],
      );
      results = solved.rows.map((item) => ({
        index: Number(item.round_index), status: item.status, score: Number(item.score),
        solutionCode: item.solution_code,
        title: { ar: item.title_ar, en: item.title_en },
        explanation: { ar: item.explanation_ar, en: item.explanation_en },
      }));
    }
    await client.query("COMMIT");
    return {
      serverTime: new Date().toISOString(),
      room: {
        id: Number(room.id), inviteCode: room.invite_code, mode: room.mode,
        status: room.status, hostUserId: Number(room.host_user_id),
        stateVersion: Number(room.state_version), createdAt: room.created_at,
      },
      me: { membershipId: Number(me.id), userId: safeUserId, rewardEligible: me.reward_eligible === true },
      members: membersResult.rows.map((member) => ({
        membershipId: Number(member.id), userId: Number(member.user_id),
        seatNumber: Number(member.seat_number), name: member.full_name,
        imageUrl: member.image_url, isReady: member.is_ready === true,
        isActive: member.is_active === true, isConnected: member.disconnected_at == null,
        disconnectedAt: member.disconnected_at,
      })),
      session: session ? {
        id: Number(session.id), status: session.status,
        currentRoundIndex: Number(session.current_round_index), score: Number(session.score),
        startedAt: session.started_at, completedAt: session.completed_at,
      } : null,
      round,
      proposal,
      messages: messages.rows.reverse().map((message) => ({
        id: Number(message.id), body: message.body, userId: Number(message.user_id),
        senderName: message.full_name, createdAt: message.created_at,
      })),
      results,
      voice: {
        enabled: teamCodeVoiceConfigured() && room.mode === "cooperative",
        canRequestToken:
          teamCodeVoiceConfigured() &&
          room.mode === "cooperative" &&
          room.status !== "abandoned",
      },
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function listMyGameHistory(userId, limit = 30) {
  await ensureSeeded();
  const result = await q(
    `SELECT gs.id,gr.id room_id,gr.mode,gr.status,gs.score,gs.started_at,gs.completed_at,
       gm.reward_eligible,gm.is_active,gm.left_at,
       EXISTS (SELECT 1 FROM game_reward_claim c WHERE c.session_id=gs.id AND c.user_id=$1) reward_claimed
     FROM game_membership gm
     JOIN game_room gr ON gr.id=gm.room_id
     JOIN game_session gs ON gs.room_id=gr.id
     WHERE gm.user_id=$1
     ORDER BY gs.started_at DESC LIMIT $2`,
    [numericId(userId), Math.max(1, Math.min(100, Number(limit) || 30))],
  );
  return result.rows.map((row) => ({
    sessionId: Number(row.id), roomId: Number(row.room_id), mode: row.mode,
    status: row.status, score: Number(row.score), startedAt: row.started_at,
    completedAt: row.completed_at, rewardEligible: row.reward_eligible === true,
    rewardClaimed: row.reward_claimed === true,
    canOpen: row.is_active === true && row.left_at == null,
  }));
}

export async function claimReward(userId, sessionId) {
  const safeUserId = numericId(userId);
  const safeSessionId = numericId(sessionId, "GAME_SESSION_ID_INVALID");
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const sessionResult = await client.query(
      `SELECT gs.*,gm.reward_eligible,gr.campaign_id
       FROM game_session gs
       JOIN game_room gr ON gr.id=gs.room_id
       JOIN game_membership gm ON gm.room_id=gr.id AND gm.user_id=$2
       WHERE gs.id=$1 FOR UPDATE OF gs,gm`,
      [safeSessionId, safeUserId],
    );
    const session = sessionResult.rows[0];
    if (!session || session.reward_eligible !== true) {
      throw new AppError("GAME_REWARD_NOT_ELIGIBLE", { status: 409 });
    }
    const solvedRound = await client.query(
      `SELECT 1 FROM game_round
       WHERE session_id=$1 AND status='solved'
       LIMIT 1`,
      [safeSessionId],
    );
    if (!solvedRound.rows[0]) {
      throw new AppError("GAME_REWARD_NOT_ELIGIBLE", { status: 409 });
    }
    const campaign = await getCampaign(client, { lock: true });
    if (!campaign || Number(campaign.id) !== Number(session.campaign_id)) {
      throw new AppError("GAME_CAMPAIGN_UNAVAILABLE", { status: 409 });
    }
    if (campaign.claim_limit != null && Number(campaign.claimed_count) >= Number(campaign.claim_limit)) {
      throw new AppError("GAME_REWARDS_EXHAUSTED", { status: 409 });
    }
    const payload = campaign.is_mock
      ? { label: "غير قابلة للاستخدام", value: Number(campaign.reward_value), mock: true }
      : { value: Number(campaign.reward_value), validDays: Number(campaign.reward_valid_days) };
    const claim = await client.query(
      `INSERT INTO game_reward_claim
         (campaign_id,user_id,session_id,reward_type,reward_payload)
       VALUES ($1,$2,$3,$4,$5::jsonb)
       ON CONFLICT (campaign_id,user_id) DO NOTHING RETURNING *`,
      [campaign.id, safeUserId, safeSessionId, campaign.reward_type, JSON.stringify(payload)],
    );
    if (!claim.rows[0]) throw new AppError("GAME_REWARD_ALREADY_CLAIMED", { status: 409 });
    await client.query(`UPDATE game_campaign SET claimed_count=claimed_count+1,updated_at=NOW() WHERE id=$1`, [campaign.id]);
    await client.query("COMMIT");
    return { claimId: Number(claim.rows[0].id), rewardType: campaign.reward_type, payload };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

function assertAdmin(actor) {
  if (actor?.isSuperAdmin === true || actor?.canManageGames === true) return;
  throw new AppError("FORBIDDEN_GAME_ADMIN", { status: 403 });
}

export async function getAdminOverview(actor) {
  assertAdmin(actor);
  await abandonExpiredPausedRooms();
  const [campaign, stats, recentRooms, recentClaims] = await Promise.all([
    getCampaign(),
    q(`SELECT
      (SELECT COUNT(*) FROM game_room)::int rooms,
      (SELECT COUNT(*) FROM game_session WHERE status='completed')::int completed_sessions,
      (SELECT COUNT(*) FROM game_membership)::int memberships,
      (SELECT COUNT(*) FROM game_reward_claim)::int claims`),
    q(`SELECT r.id,r.invite_code,r.mode,r.status,r.created_at,r.completed_at,
         COUNT(m.id)::int member_count
       FROM game_room r
       LEFT JOIN game_membership m ON m.room_id=r.id
       GROUP BY r.id ORDER BY r.created_at DESC LIMIT 20`),
    q(`SELECT c.id,c.claimed_at,c.reward_type,c.reward_payload,u.full_name,gs.score
       FROM game_reward_claim c
       JOIN app_user u ON u.id=c.user_id
       JOIN game_session gs ON gs.id=c.session_id
       ORDER BY c.claimed_at DESC LIMIT 20`),
  ]);
  return {
    campaign: publicCampaign(campaign),
    stats: stats.rows[0],
    recentRooms: recentRooms.rows.map((row) => ({
      id: Number(row.id),
      inviteCode: row.invite_code,
      mode: row.mode,
      status: row.status,
      memberCount: Number(row.member_count),
      createdAt: row.created_at,
      completedAt: row.completed_at,
    })),
    recentClaims: recentClaims.rows.map((row) => ({
      id: Number(row.id),
      userName: row.full_name,
      rewardType: row.reward_type,
      reward: row.reward_payload,
      score: Number(row.score),
      claimedAt: row.claimed_at,
    })),
  };
}

export async function updateCampaign(actor, input) {
  assertAdmin(actor);
  const result = await q(
    `UPDATE game_campaign SET
       is_enabled=COALESCE($1,is_enabled),
       starts_at=COALESCE($2,starts_at),
       ends_at=COALESCE($3,ends_at),
       reward_type=COALESCE($4,reward_type),
       reward_value=COALESCE($5,reward_value),
       reward_valid_days=COALESCE($6,reward_valid_days),
       claim_limit=COALESCE($7,claim_limit),
       updated_at=NOW()
     WHERE campaign_key='team_code_test' RETURNING *`,
    [
      typeof input.enabled === "boolean" ? input.enabled : null,
      input.startsAt || null,
      input.endsAt || null,
      input.rewardType || null,
      input.rewardValue == null ? null : Number(input.rewardValue),
      input.rewardValidDays == null ? null : Number(input.rewardValidDays),
      input.claimLimit == null ? null : Number(input.claimLimit),
    ],
  );
  return publicCampaign(result.rows[0]);
}

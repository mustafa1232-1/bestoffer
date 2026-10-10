import { q } from '../../config/db.js';
import { emitRealtimeToUser } from '../../shared/realtime/realtime-gateway.js';
import { advanceMafiaRoom, MAFIA_ACTION_GRACE_MS } from './mafia.service.js';
import { createWorkerLoop } from './games.worker-loop.js';
import { closeMafiaVoiceRoom, removeMafiaVoiceParticipant, syncMafiaVoicePermissions } from './mafia.voice.js';

export async function runMafiaPhases() {
  // Deadlines close after a short grace so a tap made just before zero, still in
  // flight on a slow network, is counted instead of rejected.
  const rooms = await q(`SELECT id FROM mafia_room r WHERE
    (phase_ends_at+${MAFIA_ACTION_GRACE_MS}*INTERVAL '1 millisecond'<=NOW() AND status NOT IN('lobby','completed','cancelled')) OR
    (status='role_reveal' AND settings->>'flowVersion'='2' AND phase_started_at<=NOW()-INTERVAL '4 seconds'
      AND NOT EXISTS(SELECT 1 FROM mafia_player p WHERE p.room_id=r.id AND life_status='alive' AND NOT role_acknowledged))
    ORDER BY phase_ends_at LIMIT 32`);
  let changed = 0;
  for (const room of rooms.rows) {
    try { changed += Number((await advanceMafiaRoom(room.id)).changed); }
    catch (error) { console.warn(JSON.stringify({ event:'mafia_phase_retry',roomId:Number(room.id),code:error.code || 'FAILED' })); }
  }
  return changed;
}

async function nextMafiaDueMs() {
  const due = await q(`SELECT GREATEST(0,EXTRACT(EPOCH FROM MIN(t)-clock_timestamp())*1000)::int AS ms FROM (
      SELECT phase_ends_at+${MAFIA_ACTION_GRACE_MS}*INTERVAL '1 millisecond' AS t FROM mafia_room
      WHERE status NOT IN('lobby','completed','cancelled') AND phase_ends_at IS NOT NULL
      UNION ALL
      SELECT phase_started_at+INTERVAL '4 seconds' FROM mafia_room
      WHERE status='role_reveal' AND settings->>'flowVersion'='2') due`);
  const ms = due.rows[0]?.ms;
  return ms == null ? null : Number(ms);
}

async function syncVoice(room, players, isCurrent) {
  if (room.status === 'cancelled') return closeMafiaVoiceRoom(room);
  const removed = new Set([...(room.settings?.kickedUserIds || []), ...players.filter(p => p.life_status === 'left').map(p => p.user_id)]);
  for (const userId of removed) await removeMafiaVoiceParticipant(room, userId);
  return syncMafiaVoicePermissions(room, players.filter(p => p.life_status !== 'left'), room.settings?.candidateIds || [], undefined, { isCurrent });
}

export async function publishMafiaRoom(users, event, data, options, send = emitRealtimeToUser) {
  // All seats receive the SSE hint immediately; a slow external publish for one
  // user cannot hold every subsequent player behind it. A room has <=14 seats.
  const results = await Promise.allSettled([...new Set(users)].map(user => send(user,event,data,options)));
  const failure = results.find(r => r.status === 'rejected');
  if (failure) throw failure.reason;
}

// The lease is committed before external I/O. A newer revision keeps the job
// pending, including when another request commits while publication is running.
export async function deliverMafiaChanges(kind = 'notify', { publish = publishMafiaRoom, voice = syncVoice } = {}) {
  if (!['notify', 'voice'].includes(kind)) throw new Error('INVALID_MAFIA_DELIVERY_KIND');
  const pending = `${kind}_pending`, lease = `${kind}_lease_until`;
  const revision = kind === 'voice' ? 'voice_revision' : 'revision';
  const jobs = await q(`UPDATE mafia_room_delivery SET ${lease}=date_trunc('milliseconds',clock_timestamp())+INTERVAL '180 seconds'
    WHERE room_id IN(SELECT room_id FROM mafia_room_delivery WHERE ${pending} AND ${lease}<=NOW()
      ORDER BY ${lease},room_id LIMIT 4 FOR UPDATE SKIP LOCKED) RETURNING room_id,${revision} AS revision,${lease} AS lease`, []);
  const results = await Promise.allSettled(jobs.rows.map(async job => {
    try {
      const data = await q(`SELECT to_jsonb(r) AS room,
        COALESCE((SELECT jsonb_agg(to_jsonb(p)) FROM mafia_player p WHERE p.room_id=r.id),'[]') AS players
        FROM mafia_room r WHERE r.id=$1`, [job.room_id]);
      const state = data.rows[0];
      if (state) {
        if (kind === 'voice') await voice(state.room, state.players, async () =>
          (await q('SELECT 1 FROM mafia_room_delivery WHERE room_id=$1 AND voice_revision=$2',[job.room_id,job.revision])).rowCount > 0);
        else {
          const users = [...new Set([...state.players.map(p => Number(p.user_id)), ...(state.room.settings?.kickedUserIds || []).map(Number)])];
          await publish(users, 'mafia_room_updated', { roomId: Number(job.room_id), stateVersion: Number(job.revision), reason: 'state_changed' }, { requireDurable: true });
        }
      }
      await q(`UPDATE mafia_room_delivery SET ${pending}=${revision}<>$2,${lease}='-infinity'
        WHERE room_id=$1 AND ${lease}=$3`, [job.room_id, job.revision, job.lease]);
    } catch (error) {
      await q(`UPDATE mafia_room_delivery SET ${lease}=NOW()+$3*INTERVAL '1 second' WHERE room_id=$1 AND ${lease}=$2`,
        [job.room_id, job.lease, error.code === 'MAFIA_VOICE_SUPERSEDED' ? 0 : 2]);
      throw error;
    }
  }));
  return { processed: jobs.rowCount, failed: results.filter(r => r.status === 'rejected').length };
}

const phaseLoop = createWorkerLoop('mafia_phase', async () => {
  const changed = await runMafiaPhases();
  if (changed > 0) { notifyLoop.wake(); voiceLoop.wake(); return { busy: true }; }
  return { nextDueMs: await nextMafiaDueMs() };
});
const notifyLoop = createWorkerLoop('mafia_notify', async () => {
  const result = await deliverMafiaChanges('notify');
  return { busy: result.processed > 0, failed: result.failed };
}, { maxDelayMs: 750 });
const voiceLoop = createWorkerLoop('mafia_voice', async () => {
  const result = await deliverMafiaChanges('voice');
  return { busy: result.processed > 0, failed: result.failed };
}, { maxDelayMs: 1000 });

// Request handlers call this after committing a mafia write: the realtime hint
// and voice permission change go out now, not at the next poll.
export function wakeMafiaWorkers() {
  phaseLoop.wake();
  notifyLoop.wake();
  voiceLoop.wake();
}
export function startMafiaWorker() {
  phaseLoop.start();
  notifyLoop.start();
  voiceLoop.start();
}
export async function stopMafiaWorker() {
  await Promise.allSettled([phaseLoop.stop(), notifyLoop.stop(), voiceLoop.stop()]);
}

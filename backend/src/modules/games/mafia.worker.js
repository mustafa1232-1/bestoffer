import { q } from '../../config/db.js';
import { emitRealtimeToUser } from '../../shared/realtime/realtime-gateway.js';
import { advanceMafiaRoom } from './mafia.service.js';
import { closeMafiaVoiceRoom, removeMafiaVoiceParticipant, syncMafiaVoicePermissions } from './mafia.voice.js';

export async function runMafiaPhases() {
  const rooms = await q(`SELECT id FROM mafia_room r WHERE
    (phase_ends_at<=NOW() AND status NOT IN('lobby','completed','cancelled')) OR
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

let stopped = true;
const tasks = new Set(), timers = new Set();
export function startMafiaWorker() {
  if (!stopped) return;
  stopped = false;
  const loop = (work, delay, name) => {
    if (stopped) return;
    const running = work().then(result => {
      if (result?.failed) console.warn(JSON.stringify({ event: `mafia_${name}_retry`, failed: result.failed }));
    }).catch(error => console.warn(JSON.stringify({ event: `mafia_${name}_error`, code: error.code || 'FAILED' })))
      .finally(() => {
        tasks.delete(running);
        if (!stopped) {
          const timer = setTimeout(() => { timers.delete(timer); loop(work, delay, name); }, delay);
          timer.unref?.(); timers.add(timer);
        }
      });
    tasks.add(running);
  };
  loop(runMafiaPhases, 150, 'phase');
  loop(() => deliverMafiaChanges('notify'), 150, 'notify');
  loop(() => deliverMafiaChanges('voice'), 200, 'voice');
}
export async function stopMafiaWorker() {
  stopped = true;
  for (const timer of timers) clearTimeout(timer);
  timers.clear();
  await Promise.allSettled([...tasks]);
}

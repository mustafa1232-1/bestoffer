import { q } from '../../config/db.js';
import { AppError } from '../../shared/utils/errors.js';

// A single MVCC statement: no phase transitions, writes, row locks or provider
// calls in GET. The mapper in mafia.service remains the public privacy boundary.
export async function readMafiaState(roomId, userId) {
  const result = await q(`SELECT to_jsonb(r) AS room,to_jsonb(me)||jsonb_build_object('full_name',u.full_name) AS me,
    statement_timestamp() AS server_time,COALESCE(d.revision,0) AS revision,
    (SELECT jsonb_agg(to_jsonb(p)||jsonb_build_object('full_name',a.full_name,'image_url',a.image_url) ORDER BY p.seat_number)
      FROM mafia_player p JOIN app_user a ON a.id=p.user_id WHERE p.room_id=r.id) AS players,
    (SELECT jsonb_agg(to_jsonb(e) ORDER BY e.id DESC) FROM (SELECT * FROM mafia_event WHERE room_id=r.id AND
      (visibility='public' OR (visibility='mafia' AND me.team='mafia' AND me.life_status='alive')
       OR (visibility='dead' AND me.life_status='dead') OR (visibility='private' AND recipient_player_id=me.id))
      ORDER BY id DESC LIMIT 80) e) AS events,
    (SELECT payload FROM mafia_event WHERE room_id=r.id AND event_type='secret_mission'
      AND recipient_player_id=me.id ORDER BY id DESC LIMIT 1) AS mission,
    (SELECT jsonb_agg(to_jsonb(m) ORDER BY m.id DESC) FROM (
      SELECT m.id,m.channel,m.body,m.created_at,m.client_message_id,p.user_id,p.seat_number,a.full_name
      FROM mafia_message m JOIN mafia_player p ON p.id=m.sender_player_id JOIN app_user a ON a.id=p.user_id
      WHERE m.room_id=r.id AND (m.channel='public' OR (m.channel='mafia' AND me.team='mafia' AND me.life_status='alive')
        OR (m.channel='dead' AND me.life_status='dead')) ORDER BY m.id DESC LIMIT 80) m) AS messages,
    (SELECT jsonb_agg(to_jsonb(a) ORDER BY a.id DESC) FROM mafia_action a
      WHERE a.room_id=r.id AND a.actor_player_id=me.id AND a.day_number=r.day_number) AS actions,
    (SELECT target_player_id FROM mafia_action WHERE room_id=r.id AND actor_player_id=me.id
      AND action_type='doctor_protect' AND day_number=r.day_number-1 LIMIT 1) AS previous_doctor,
    (SELECT jsonb_agg(to_jsonb(b)) FROM mafia_ballot b WHERE b.room_id=r.id AND b.voter_player_id=me.id
      AND b.day_number=r.day_number) AS ballots,
    jsonb_build_object(
      'cast_vote',EXISTS(SELECT 1 FROM mafia_ballot WHERE room_id=r.id AND voter_player_id=me.id AND ballot_type IN('vote','revote')),
      'performed_role',EXISTS(SELECT 1 FROM mafia_action WHERE room_id=r.id AND actor_player_id=me.id),
      'used_reaction',EXISTS(SELECT 1 FROM mafia_event WHERE room_id=r.id AND event_type='player_interaction'
        AND payload->>'senderPlayerId'=me.id::text AND payload->>'interactionType'='reaction'),
      'sent_gift',EXISTS(SELECT 1 FROM mafia_event WHERE room_id=r.id AND event_type='player_interaction'
        AND payload->>'senderPlayerId'=me.id::text AND payload->>'interactionType'='gift')) AS progress,
    (SELECT jsonb_build_object('games_played',COUNT(*) FILTER(WHERE h.status='completed'),
      'wins',COUNT(*) FILTER(WHERE h.status='completed' AND h.winner=p.team),
      'survivals',COUNT(*) FILTER(WHERE h.status='completed' AND p.life_status='alive'),
      'detective_games',COUNT(*) FILTER(WHERE h.status='completed' AND p.role='detective'))
      FROM mafia_player p JOIN mafia_room h ON h.id=p.room_id WHERE p.user_id=$2) AS profile,
    CASE WHEN r.status='completed' THEN (SELECT jsonb_agg(to_jsonb(h)) FROM (
      SELECT (payload->>'targetPlayerId')::bigint AS player_id,COUNT(*)::int AS votes
      FROM mafia_event WHERE room_id=r.id AND event_type='player_interaction' AND payload->>'kind'='mvp'
      GROUP BY (payload->>'targetPlayerId')::bigint ORDER BY votes DESC,player_id LIMIT 3) h) END AS honors,
    CASE WHEN r.status='completed' THEN (SELECT payload FROM mafia_event WHERE room_id=r.id AND event_type='player_interaction'
      AND payload->>'kind'='mvp' AND payload->>'senderPlayerId'=me.id::text ORDER BY id DESC LIMIT 1) END AS my_honor
    FROM mafia_room r JOIN mafia_player me ON me.room_id=r.id AND me.user_id=$2
    JOIN app_user u ON u.id=me.user_id LEFT JOIN mafia_room_delivery d ON d.room_id=r.id
    WHERE r.id=$1 AND NOT(COALESCE(r.settings->'kickedUserIds','[]') @> to_jsonb(ARRAY[$2::bigint]))`, [roomId,userId]);
  const state = result.rows[0];
  if (!state) throw new AppError('MAFIA_ROOM_FORBIDDEN', {status:403});
  return state;
}

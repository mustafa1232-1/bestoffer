import { q } from '../../config/db.js';
import { AppError } from '../../shared/utils/errors.js';

// Public tournament results contain team names and scores, never private chat,
// invite codes, individual answers or a playable token for an opposing team.
export async function readKnowledgeBracket(userId, eventId) {
  const event = (await q(`SELECT e.id,e.title,e.status,e.team_size,e.best_of,e.prize_title,
      e.prize_description,e.prize_is_mock,e.champion_team_id
    FROM maslaki_quiz_event e WHERE e.id=$1 AND e.event_type='tournament'`, [eventId])).rows[0];
  if (!event) throw new AppError('TOURNAMENT_NOT_FOUND', { status: 404 });
  const teams = (await q(`SELECT t.id,t.team_name,COUNT(tm.user_id)::int AS members,
      COALESCE(BOOL_OR(tm.user_id=$2),FALSE) AS is_mine FROM maslaki_quiz_team t
    LEFT JOIN maslaki_quiz_team_member tm ON tm.team_id=t.id WHERE t.event_id=$1 GROUP BY t.id ORDER BY t.id`, [eventId,userId])).rows;
  const rows = (await q(`SELECT m.*,EXISTS(SELECT 1 FROM maslaki_quiz_team_member tm
    WHERE tm.user_id=$2 AND tm.team_id IN(m.team_a_id,m.team_b_id)) AS is_mine
    FROM maslaki_quiz_match m WHERE event_id=$1 ORDER BY round_number,match_number`, [eventId,userId])).rows;
  const team = (id) => id == null ? null : { id: Number(id), name: teams.find(t => Number(t.id)===Number(id))?.team_name || 'فريق' };
  const firstCount = rows.filter(m => Number(m.round_number)===1).length;
  const rounds = [];
  for (let count=firstCount,number=1;count>=1;count/=2,number++) {
    const matches = [];
    for (let slot=1;slot<=count;slot++) {
      const m = rows.find(r => Number(r.round_number)===number && Number(r.match_number)===slot);
      const prior = rounds.at(-1)?.matches;
      const advanced = (n) => prior?.[n]?.winnerTeamId ? team(prior[n].winnerTeamId) : null;
      matches.push({ id: m ? Number(m.id) : null, round: number, matchNumber: slot,
        status: m?.status || 'waiting', teamA: m ? team(m.team_a_id) : advanced((slot-1)*2),
        teamB: m ? team(m.team_b_id) : advanced((slot-1)*2+1),
        sourceA: number>1 ? { round:number-1,matchNumber:slot*2-1 } : null,
        sourceB: number>1 ? { round:number-1,matchNumber:slot*2 } : null,
        winsA: Number(m?.wins_a || 0), winsB: Number(m?.wins_b || 0),
        scoreA: Number(m?.score_a || 0), scoreB: Number(m?.score_b || 0),
        winnerTeamId: m && ['completed','bye'].includes(m.status) && m.winner_team_id ? Number(m.winner_team_id) : null,
        canPlay: m?.is_mine === true && ['pending','active','completed'].includes(m.status) });
    }
    rounds.push({ number, matches });
  }
  return { event: { id:Number(event.id),title:event.title,status:event.status,teamSize:Number(event.team_size),
    bestOf:Number(event.best_of),champion:team(event.champion_team_id),
    prize:event.prize_title ? {title:event.prize_title,description:event.prize_description,mock:event.prize_is_mock} : null },
    teams:teams.map(t => ({id:Number(t.id),name:t.team_name,members:Number(t.members),isMine:t.is_mine})),
    rounds };
}

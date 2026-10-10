export const KNOWLEDGE_DISTRICTS = Object.freeze([
  { id: "souk", nameAr: "سوق المعرفة", neighbors: ["river", "garden"] },
  { id: "river", nameAr: "درب دجلة", neighbors: ["souk", "old-city", "bridge"] },
  { id: "garden", nameAr: "حدائق مسلكي", neighbors: ["souk", "library", "market"] },
  { id: "old-city", nameAr: "المدينة القديمة", neighbors: ["river", "library", "crafts"] },
  { id: "bridge", nameAr: "جسر الأصدقاء", neighbors: ["river", "market", "science"] },
  { id: "library", nameAr: "دار الحكايات", neighbors: ["garden", "old-city", "science"] },
  { id: "market", nameAr: "ساحة التحدي", neighbors: ["garden", "bridge", "sports"] },
  { id: "crafts", nameAr: "خان الحرف", neighbors: ["old-city", "science", "arts"] },
  { id: "science", nameAr: "مرصد الرافدين", neighbors: ["bridge", "library", "crafts", "sports"] },
  { id: "sports", nameAr: "ملعب الأبطال", neighbors: ["market", "science", "arts"] },
  { id: "arts", nameAr: "مسرح النخيل", neighbors: ["crafts", "sports"] },
]);

const BASE_POINTS = Object.freeze({ easy: 100, medium: 150, hard: 200 });
const MAX_SPEED_BONUS = 50;

// Display the same rules used by scoring; territory ownership is not currency.
export function knowledgeScoringRules(difficulty) {
  return { basePoints: BASE_POINTS[difficulty] || BASE_POINTS.medium,
    maxSpeedBonus: MAX_SPEED_BONUS, territoryBonusPoints: 0 };
}

// Stable majority ties use the earliest server receipt, matching the original
// rules. A-first territory arbitration is intentionally retained, not silently
// replaced with a new competitive rule during this performance migration.
export function resolveKnowledgeVotes({ teamIds, answers, territories, question, startedAt }) {
  const claimed = new Set(territories.map(t => t.district_id));
  const grants = [];
  const outcomes = teamIds.map(teamId => {
    const submitted = answers.filter(a => Number(a.team_id) === Number(teamId) && !a.is_timeout)
      .sort((a,b) => new Date(a.answered_at)-new Date(b.answered_at) || Number(a.id)-Number(b.id));
    const counts = new Map();
    for (const answer of submitted) counts.set(Number(answer.answer_index), (counts.get(Number(answer.answer_index)) || 0)+1);
    const highest = Math.max(0,...counts.values());
    const choice = submitted.find(a => counts.get(Number(a.answer_index)) === highest);
    const correct = choice != null && Number(choice.answer_index) === Number(question.answer_index);
    const elapsedMs = submitted.length ? new Date(submitted.at(-1).answered_at)-new Date(startedAt) : question.time_limit_seconds*1000;
    const points = scoreKnowledgeAnswer({ isCorrect: correct, difficulty: question.difficulty, elapsedMs: Math.max(0,elapsedMs), timeLimitMs: question.time_limit_seconds*1000 });
    if (correct) {
      const owned = territories.filter(t => Number(t.team_id) === Number(teamId)).map(t => t.district_id);
      const candidates = nextDistricts(KNOWLEDGE_DISTRICTS,owned).filter(d => !claimed.has(d.id));
      const votes = new Map();
      for (const answer of submitted) votes.set(answer.district_id,(votes.get(answer.district_id)||0)+1);
      const preferred = [...votes.entries()].sort((a,b)=>b[1]-a[1])[0]?.[0];
      const district = candidates.find(d=>d.id===preferred) || candidates[0];
      if (district) { grants.push({ districtId: district.id,teamId:Number(teamId) }); claimed.add(district.id); }
    }
    return { teamId:Number(teamId),correct,points,scoreAnswerId: submitted.at(-1)?.id || null };
  });
  return { outcomes,grants };
}

export function knowledgePublicChatIsConsented(teams) {
  return Array.isArray(teams) && teams.length === 2 && teams.every((team) =>
    Number(team.total) > 0 && Number(team.optedIn) === Number(team.total));
}

export function knowledgeTeamJoinAction({ eventStatus, eventType, teamSize, memberCount, alreadyMember }) {
  if (alreadyMember) return "already-member";
  if (eventStatus !== "registration") return "not-joinable";
  if (Number(memberCount) < Number(teamSize)) return "join-team";
  if (eventType === "duel") return "join-opponent";
  return "team-full";
}

export function knowledgeDuelCanStart(teams, teamSize) {
  return Array.isArray(teams) && teams.length === 2 &&
    teams.every((team) => Number(team.memberCount) === Number(teamSize));
}

export function scoreKnowledgeAnswer({ isCorrect, difficulty, elapsedMs, timeLimitMs = 20_000 }) {
  if (!isCorrect) return 0;
  const base = knowledgeScoringRules(difficulty).basePoints;
  const remainingRatio = Math.max(0, Math.min(1, (timeLimitMs - elapsedMs) / timeLimitMs));
  return base + Math.round(MAX_SPEED_BONUS * remainingRatio);
}

export function nextDistricts(districts, ownedDistrictIds) {
  const owned = new Set(ownedDistrictIds || []);
  if (owned.size === 0) return districts.map(({ id, nameAr }) => ({ id, nameAr }));
  const frontier = new Set();
  for (const district of districts) {
    if (owned.has(district.id)) {
      for (const neighbor of district.neighbors) {
        if (!owned.has(neighbor)) frontier.add(neighbor);
      }
    }
  }
  return districts.filter(({ id }) => frontier.has(id)).map(({ id, nameAr }) => ({ id, nameAr }));
}

export function buildTournamentBracket(teamIds) {
  const unique = [...new Set((teamIds || []).map(Number).filter((id) => Number.isInteger(id) && id > 0))];
  if (unique.length < 2 || unique.length > 64) throw new RangeError("TOURNAMENT_TEAM_COUNT_INVALID");
  const bracketSize = 2 ** Math.ceil(Math.log2(unique.length));
  const matches = [];
  const byeCount = bracketSize - unique.length;
  const pairings = [
    ...unique.slice(0, byeCount).map((teamId) => [teamId, null]),
    ...Array.from({ length: (unique.length - byeCount) / 2 }, (_, index) => {
      const offset = byeCount + index * 2;
      return [unique[offset], unique[offset + 1]];
    }),
  ];
  pairings.forEach(([teamAId, teamBId], index) => {
    matches.push({
      roundNumber: 1,
      matchNumber: index + 1,
      teamAId,
      teamBId,
      status: teamAId && teamBId ? "pending" : "bye",
      winnerTeamId: teamAId && teamBId ? null : teamAId || teamBId,
    });
  });
  return { bracketSize, roundCount: Math.log2(bracketSize), matches };
}

export function decideMatchWinner({ scoreA, scoreB, tieBreakA = 0, tieBreakB = 0 }) {
  if (scoreA !== scoreB) return scoreA > scoreB ? "a" : "b";
  if (tieBreakA !== tieBreakB) return tieBreakA > tieBreakB ? "a" : "b";
  return "draw";
}

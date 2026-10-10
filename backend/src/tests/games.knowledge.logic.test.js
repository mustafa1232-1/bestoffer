import test from "node:test";
import assert from "node:assert/strict";

import { buildTournamentBracket, decideMatchWinner, KNOWLEDGE_DISTRICTS, knowledgeDuelCanStart, knowledgePublicChatIsConsented, knowledgeTeamJoinAction, nextDistricts, scoreKnowledgeAnswer } from "../modules/games/knowledge-game.logic.js";
import { KNOWLEDGE_CATEGORY_LABELS, KNOWLEDGE_DIFFICULTY_SECONDS, MASLAKI_KNOWLEDGE_QUESTIONS, MASLAKI_KNOWLEDGE_QUESTION_BANK, validateKnowledgeQuestionBank } from "../modules/games/knowledge.question-bank.js";
import { KNOWLEDGE_QUESTION_ADDITIONS } from "../modules/games/knowledge.question-expansion.js";

test('all 160 numeric additions have independently recomputed answers and distinct choices', () => {
  const numeric = KNOWLEDGE_QUESTION_ADDITIONS.slice(40);
  assert.equal(numeric.length, 160);
  for (const [index, question] of numeric.entries()) {
    const numbers = question.questionAr.match(/\d+/g).map(Number);
    const [a,b] = numbers;
    const expected = [
      () => a - a * b / 100,
      () => a + a + a + a,
      () => a * b,
      () => a / b,
      () => (a + b) / 2,
      () => numbers[3] + a,
      () => Array.from({length:a},(_,i)=>i).reduce((sum,n)=>sum+n,0),
      () => a * 4,
    ][index % 8]();
    assert.equal(Number(question.options[question.answerIndex]), expected, question.questionAr);
    assert.equal(new Set(question.options).size, 4, question.questionAr);
  }
});

test("knowledge question bank is large, valid, varied, and does not expose a fixed answer slot", () => {
  const validation = validateKnowledgeQuestionBank();
  assert.equal(validation.valid, true, JSON.stringify(validation.failures));
  assert.equal(validation.count, 1200);
  assert.equal(validation.uniqueCount, 1200);
  assert.ok(new Set(MASLAKI_KNOWLEDGE_QUESTIONS.map((question) => question.category)).size >= 7);
  assert.equal(new Set(MASLAKI_KNOWLEDGE_QUESTION_BANK.map((question) => question.questionAr)).size, validation.count);
  for (const category of Object.keys(KNOWLEDGE_CATEGORY_LABELS)) {
    assert.ok(MASLAKI_KNOWLEDGE_QUESTION_BANK.filter((question) => question.category === category).length >= 10);
  }
  assert.ok(MASLAKI_KNOWLEDGE_QUESTION_BANK.every((question) => question.options.length === 4 && question.options[question.answerIndex]));
  assert.deepEqual(new Set(MASLAKI_KNOWLEDGE_QUESTIONS.map((question) => question.answerIndex)), new Set([0, 1, 2, 3]));
  assert.equal(new Set(MASLAKI_KNOWLEDGE_QUESTION_BANK.map(q=>`${q.category}:${q.factQuestionAr}`)).size,316);
});

test("difficulty timers are fixed and public chat requires every player on both teams", () => {
  assert.deepEqual(KNOWLEDGE_DIFFICULTY_SECONDS, { easy: 30, medium: 20, hard: 15 });
  assert.equal(knowledgePublicChatIsConsented([
    { total: 4, optedIn: 4 }, { total: 3, optedIn: 3 },
  ]), true);
  assert.equal(knowledgePublicChatIsConsented([
    { total: 4, optedIn: 3 }, { total: 3, optedIn: 3 },
  ]), false);
});

test("knowledge team codes fill duel teams and route overflow players to opponents", () => {
  assert.equal(knowledgeTeamJoinAction({
    eventStatus: "registration", eventType: "duel", teamSize: 1,
    memberCount: 1, alreadyMember: false,
  }), "join-opponent");
  assert.equal(knowledgeTeamJoinAction({
    eventStatus: "registration", eventType: "duel", teamSize: 4,
    memberCount: 4, alreadyMember: false,
  }), "join-opponent");
  assert.equal(knowledgeTeamJoinAction({
    eventStatus: "registration", eventType: "duel", teamSize: 1,
    memberCount: 1, alreadyMember: true,
  }), "already-member");
  assert.equal(knowledgeTeamJoinAction({
    eventStatus: "registration", eventType: "tournament", teamSize: 1,
    memberCount: 1, alreadyMember: false,
  }), "team-full");
  assert.equal(knowledgeTeamJoinAction({
    eventStatus: "active", eventType: "duel", teamSize: 1,
    memberCount: 1, alreadyMember: false,
  }), "not-joinable");
});

test("knowledge duel rooms start only when both even-sized teams are full", () => {
  assert.equal(knowledgeDuelCanStart([{ memberCount: 1 }, { memberCount: 1 }], 1), true);
  assert.equal(knowledgeDuelCanStart([{ memberCount: 2 }, { memberCount: 2 }], 2), true);
  assert.equal(knowledgeDuelCanStart([{ memberCount: 2 }, { memberCount: 1 }], 2), false);
  assert.equal(knowledgeDuelCanStart([{ memberCount: 2 }], 2), false);
});

test("territory expansion exposes only adjacent unclaimed districts", () => {
  assert.deepEqual(nextDistricts(KNOWLEDGE_DISTRICTS, ["souk"]).map((district) => district.id).sort(), ["garden", "river"]);
  assert.equal(nextDistricts(KNOWLEDGE_DISTRICTS, []).length, KNOWLEDGE_DISTRICTS.length);
});

test("answer scoring rewards correct answers and speed without negative scores", () => {
  assert.equal(scoreKnowledgeAnswer({ isCorrect: false, difficulty: "hard", elapsedMs: 0 }), 0);
  assert.equal(scoreKnowledgeAnswer({ isCorrect: true, difficulty: "hard", elapsedMs: 0 }), 250);
  assert.equal(scoreKnowledgeAnswer({ isCorrect: true, difficulty: "hard", elapsedMs: 20_000 }), 200);
});

test("12-team tournament bracket creates only valid games and four fair byes", () => {
  const bracket = buildTournamentBracket(Array.from({ length: 12 }, (_, index) => index + 1));
  assert.equal(bracket.bracketSize, 16);
  assert.equal(bracket.roundCount, 4);
  assert.equal(bracket.matches.length, 8);
  assert.equal(bracket.matches.filter((match) => match.status === "bye").length, 4);
  assert.equal(bracket.matches.filter((match) => match.status === "pending").length, 4);
  assert.ok(bracket.matches.every((match) => match.teamAId || match.teamBId));
});

test("bracket rejects fewer than two teams and resolves ties using explicit tie breaks", () => {
  assert.throws(() => buildTournamentBracket([1]), /TOURNAMENT_TEAM_COUNT_INVALID/);
  assert.equal(decideMatchWinner({ scoreA: 10, scoreB: 10, tieBreakA: 4, tieBreakB: 3 }), "a");
  assert.equal(decideMatchWinner({ scoreA: 4, scoreB: 5 }), "b");
});

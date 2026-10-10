import assert from "node:assert/strict";
import test from "node:test";

import { maskOffensiveText } from "../modules/games/games.safety.js";
import { numericDistractors } from "../modules/games/knowledge.question-expansion.js";
import { MASLAKI_KNOWLEDGE_QUESTION_BANK } from "../modules/games/knowledge.question-bank.js";
import { teamCodeVotesRequired } from "../modules/games/games.service.js";

test("chat masking catches Arabic spelling tricks without touching normal game talk", () => {
  for (const text of ["انت كلب", "يا حمااااار", "وَالكَلْب", "fuck you"]) {
    assert.equal(maskOffensiveText(text).flagged, true, text);
  }
  for (const text of ["عندي دليل", "شنو رأيكم؟", "كسر التعادل", "عالم الحيوان", "راجعوا الترتيب"]) {
    const result = maskOffensiveText(text);
    assert.equal(result.flagged, false, text);
    assert.equal(result.text, text);
  }
});

test("numeric answers are not identifiable as the smallest or largest choice", () => {
  const ranks = [0, 0, 0, 0];
  for (const question of MASLAKI_KNOWLEDGE_QUESTION_BANK) {
    const values = question.options.map(Number);
    if (values.some(Number.isNaN)) continue;
    const sorted = [...values].sort((a, b) => a - b);
    ranks[sorted.indexOf(values[question.answerIndex])] += 1;
  }
  const total = ranks.reduce((a, b) => a + b, 0);
  for (const count of ranks) assert.ok(count / total < 0.35, `rank share ${ranks}`);
  for (let seed = 0; seed < 16; seed += 1) {
    const choices = numericDistractors(3, seed);
    assert.ok(choices.every((value) => value > 0 && value !== 3));
    assert.equal(new Set(choices).size, 3);
  }
});

test("team code needs a strict majority of active players", () => {
  assert.deepEqual([1, 2, 3, 4].map(teamCodeVotesRequired), [1, 2, 2, 3]);
});

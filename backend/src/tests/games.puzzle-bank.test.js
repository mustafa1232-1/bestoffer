import assert from "node:assert/strict";
import test from "node:test";

import {
  TEAM_CODE_PUZZLES,
  enumeratePuzzleSolutions,
  validatePuzzleBank,
} from "../modules/games/games.puzzle-bank.js";
import {
  distributeClueIndexes,
  gameRoundLimitSeconds,
} from "../modules/games/games.service.js";

test("team code bank has 30 uniquely solvable versioned puzzles", () => {
  const result = validatePuzzleBank();
  assert.equal(result.valid, true);
  assert.equal(result.count, 30);
  assert.deepEqual(
    TEAM_CODE_PUZZLES.reduce((counts, puzzle) => {
      counts[puzzle.difficulty] = (counts[puzzle.difficulty] || 0) + 1;
      return counts;
    }, {}),
    { easy: 10, medium: 10, hard: 10 },
  );
  for (const puzzle of TEAM_CODE_PUZZLES) {
    assert.deepEqual(enumeratePuzzleSolutions(puzzle), [puzzle.solutionCode]);
    assert.equal(new Set(puzzle.solutionCode).size, puzzle.codeLength);
    assert.equal(puzzle.hints.length, 3);
  }
});

test("round timer gets shorter as difficulty rises and gives teams voting time", () => {
  assert.equal(gameRoundLimitSeconds("easy", "solo"), 150);
  assert.equal(gameRoundLimitSeconds("medium", "solo"), 120);
  assert.equal(gameRoundLimitSeconds("hard", "solo"), 90);
  assert.equal(gameRoundLimitSeconds("hard", "cooperative"), 120);
});

for (const players of [2, 3, 4]) {
  test(`clue distribution gives every member clues with ${players} players`, () => {
    const memberIds = Array.from({ length: players }, (_, index) => index + 10);
    const assignments = distributeClueIndexes(8, memberIds);
    assert.equal(assignments.length, 8);
    for (const memberId of memberIds) {
      assert.ok(assignments.some((item) => item.membershipId === memberId));
    }
    assert.equal(new Set(assignments.map((item) => item.clueIndex)).size, 8);
  });
}

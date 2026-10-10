import assert from 'node:assert/strict';
import test from 'node:test';
import { knowledgeScoringRules, scoreKnowledgeAnswer } from '../modules/games/knowledge-game.logic.js';

test('displayed rewards match scoring without inventing territory points', () => {
  for (const [difficulty, expectedBase] of [['easy',100],['medium',150],['hard',200]]) {
    const rules = knowledgeScoringRules(difficulty);
    assert.equal(rules.basePoints, expectedBase);
    assert.equal(rules.territoryBonusPoints, 0);
    assert.equal(scoreKnowledgeAnswer({isCorrect:true,difficulty,elapsedMs:0}),
      rules.basePoints + rules.maxSpeedBonus);
    assert.equal(scoreKnowledgeAnswer({isCorrect:true,difficulty,elapsedMs:20_000}),
      rules.basePoints);
    assert.equal(scoreKnowledgeAnswer({isCorrect:false,difficulty,elapsedMs:0}), 0);
  }
});

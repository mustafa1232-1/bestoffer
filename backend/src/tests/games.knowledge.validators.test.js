import test from "node:test";
import assert from "node:assert/strict";

import {
  knowledgeChatBody,
  knowledgeConsentBody,
  knowledgeQuestionBody,
  knowledgeReactionBody,
  knowledgeDuelBody,
  knowledgeRoomCodeBody,
  knowledgeRoomSeatBody,
} from "../modules/games/games.validators.js";

test("knowledge questions require four distinct choices and a valid answer index", () => {
  const valid = {
    category: "science",
    difficulty: "hard",
    question: "Which answer is correct?",
    options: ["A", "B", "C", "D"],
    answerIndex: 2,
  };
  assert.equal(knowledgeQuestionBody(valid).answerIndex, 2);
  assert.equal(knowledgeQuestionBody({ ...valid, options: ["A", "A", "C", "D"] }), null);
  assert.equal(knowledgeQuestionBody({ ...valid, answerIndex: 5 }), null);
  assert.equal(knowledgeQuestionBody({ ...valid, category: "unknown" }), null);
});

test("knowledge chat, consent, and reaction payloads are constrained", () => {
  assert.deepEqual(knowledgeChatBody({ channel: "team", body: "  hello  " }), {
    channel: "team", body: "hello",
  });
  assert.equal(knowledgeChatBody({ channel: "public", body: "" }), null);
  assert.deepEqual(knowledgeConsentBody({ enabled: false }), { enabled: false });
  assert.equal(knowledgeConsentBody({ enabled: "yes" }), null);
  assert.deepEqual(knowledgeReactionBody({ kind: "request_public_chat" }), {
    kind: "request_public_chat",
  });
  assert.equal(knowledgeReactionBody({ kind: "free-form" }), null);
});

test("knowledge room creation and seat inputs reject malformed visibility and seat data", () => {
  assert.deepEqual(knowledgeDuelBody({ teamSize: 2, isPrivate: true }), {
    teamSize: 2,
    bestOf: 1,
    title: "تحدي خريطة المعرفة",
    isPrivate: true,
  });
  assert.equal(knowledgeDuelBody({ teamSize: 2, isPrivate: "yes" }), null);
  assert.deepEqual(knowledgeRoomCodeBody({ code: "kb9bay5" }), { code: "KB9BAY5" });
  assert.equal(knowledgeRoomCodeBody({ code: "bad" }), null);
  assert.deepEqual(knowledgeRoomSeatBody({ side: "b", code: "KB9BAY5" }), {
    side: "b",
    code: "KB9BAY5",
  });
  assert.equal(knowledgeRoomSeatBody({ side: "c" }), null);
});

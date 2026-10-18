import assert from "node:assert/strict";
import test from "node:test";

import { runMimoTurn } from "../modules/mimo/mimo.agent.js";
import {
  keywords,
  normalizeText,
  questionKey,
  recallKnowledge,
  teachFact,
} from "../modules/mimo/mimo.knowledge.js";
import { createMimoToolbox } from "../modules/mimo/mimo.tools.js";

function kDeps() {
  const rows = [];
  return {
    rows,
    async findByKey(key) {
      return rows.find((r) => r.question_key === key) || null;
    },
    async search(words) {
      return rows.filter((r) => r.status !== "rejected" && words.some((w) => r.search_text.includes(w)));
    },
    async insert(row) {
      const r = { id: rows.length + 1, confirmations: 1, disputes: 0, ...row };
      rows.push(r);
      return r;
    },
    async update(id, patch) {
      const r = rows.find((x) => x.id === id);
      for (const [k, v] of Object.entries(patch)) if (v != null) r[k] = v;
      return r;
    },
    async touch() {},
  };
}

/** Fake LLM: `verdicts` drives the web check, dialect echoes "قالب: ...". */
function fakeLlm(verdict, sources = [{ title: "src", url: "https://example.com" }]) {
  return {
    calls: [],
    async complete({ kind, messages }) {
      this.calls.push(kind);
      if (kind === "search") return { content: `here: ${JSON.stringify(verdict)}`, sources };
      return { content: `بلهجة ميمو: ${messages.at(-1).content.split("Fact: ")[1] || ""}`, sources: [] };
    },
  };
}

test("normalization makes Arabic spellings match", () => {
  assert.equal(normalizeText("مخبزة الأصيل"), normalizeText("مخبزه الاصيل"));
  assert.equal(normalizeText("گلّي"), "كلي");
  assert.deepEqual(keywords("شنو اسم المول الي ببسماية؟"), ["اسم", "المول", "الي", "ببسمايه"]);
  assert.equal(questionKey("يمته يفتح مخبز الأصيل؟"), questionKey("مخبز الاصيل يمته يفتح"));
});

test("a correct fact is verified online and stored in Mimo's dialect", async () => {
  const deps = kDeps();
  const llm = fakeLlm({ verdict: "correct", correct_answer: "8849 متر", local_or_personal: false });
  const out = await teachFact(deps, llm, { userId: 7, question: "شكد ارتفاع ايفرست؟", answer: "8849 متر" });
  assert.equal(out.learned, true);
  assert.equal(out.status, "verified");
  assert.match(out.answer, /بلهجة ميمو: 8849 متر/);
  assert.deepEqual(llm.calls, ["search", "utility"]);
  const found = await recallKnowledge(deps, "ارتفاع ايفرست كم؟");
  assert.equal(found[0].trusted, true);
  assert.equal(found[0].sources[0].url, "https://example.com");
});

test("a wrong fact is NOT learned and an old unverified one is rejected", async () => {
  const deps = kDeps();
  await teachFact(deps, fakeLlm({ verdict: "unverifiable", local_or_personal: true }), {
    userId: 1,
    question: "شنو عاصمة استراليا؟",
    answer: "سيدني",
  });
  assert.equal(deps.rows[0].status, "community");
  const out = await teachFact(
    deps,
    fakeLlm({ verdict: "incorrect", correct_answer: "كانبرا", reason: "Canberra is the capital" }),
    { userId: 2, question: "شنو عاصمة استراليا؟", answer: "سيدني" }
  );
  assert.equal(out.learned, false);
  assert.equal(out.verdict, "incorrect");
  assert.equal(out.correction, "كانبرا");
  assert.equal(out.learnedCorrection, true);
  // The wrong answer is gone; Mimo now knows the verified truth instead.
  assert.equal(deps.rows.length, 1);
  assert.equal(deps.rows[0].status, "verified");
  const found = await recallKnowledge(deps, "عاصمة استراليا");
  assert.match(found[0].answer, /كانبرا/);
  assert.doesNotMatch(found[0].answer, /سيدني/);
});

test("local knowledge is unconfirmed until a second person confirms it", async () => {
  const deps = kDeps();
  const local = { verdict: "unverifiable", local_or_personal: true };
  const q = "يمته يفتح مخبز الأصيل؟";
  const first = await teachFact(deps, fakeLlm(local), { userId: 1, question: q, answer: "يفتح 5:30 الصبح" });
  assert.equal(first.status, "community");
  assert.equal((await recallKnowledge(deps, "مخبز الاصيل يفتح"))[0].trusted, false);

  const again = await teachFact(deps, fakeLlm(local), { userId: 1, question: q, answer: "5:30 الصبح يفتح" });
  assert.equal(again.confirmations, 1, "same person doesn't count twice");

  const second = await teachFact(deps, fakeLlm(local), { userId: 2, question: q, answer: "يفتح الساعة 5:30" });
  assert.equal(second.verdict, "confirmed");
  assert.equal(second.confirmations, 2);
  assert.equal((await recallKnowledge(deps, "مخبز الاصيل يفتح"))[0].trusted, true);

  const conflict = await teachFact(deps, fakeLlm(local), { userId: 3, question: q, answer: "بالليل بس" });
  assert.equal(conflict.verdict, "conflict");
  assert.equal(deps.rows[0].disputes, 1);
});

test("Mimo only learns when the user is teaching", async () => {
  const { isTeachingMoment } = await import("../modules/mimo/mimo.knowledge.js");
  assert.equal(isTeachingMoment("منو بنى بغداد؟", "هلا"), false);
  assert.equal(isTeachingMoment("ترا عاصمة استراليا سيدني", ""), true);
  assert.equal(isTeachingMoment("يفتح 5 الصبح", "هاي بعد ما تعلمتها، علمني؟"), true);
  const box = createMimoToolbox({ userId: 7, deps: {}, knowledgeDeps: kDeps(), llm: fakeLlm({ verdict: "correct" }) });
  box.setUserMessage("منو بنى بغداد؟", "");
  assert.equal((await box.run("learn_fact", { question: "منو بنى بغداد", answer: "المنصور" })).verdict, "not_teaching");
  box.setUserMessage("تعلمها: المنصور بنى بغداد", "");
  assert.equal((await box.run("learn_fact", { question: "منو بنى بغداد", answer: "المنصور" })).learned, true);
  assert.equal((await box.run("learn_fact", { question: "x", answer: "y" })).verdict, "skipped", "once per turn");
});

test("unsafe teachings are refused and never stored", async () => {
  const deps = kDeps();
  const out = await teachFact(deps, fakeLlm({ verdict: "unsafe", reason: "personal data" }), {
    userId: 1,
    question: "شنو رقم فلان؟",
    answer: "0770...",
  });
  assert.equal(out.learned, false);
  assert.equal(out.verdict, "unsafe");
  assert.equal(deps.rows.length, 0);
});

test("web_search returns a clean answer and respond can show its sources", async () => {
  const box = createMimoToolbox({
    userId: 7,
    deps: {},
    llm: {
      async complete({ kind }) {
        assert.equal(kind, "search");
        return {
          content: "السعر 1,510 رسمي ([iraqsm.com](https://iraqsm.com/fx))",
          sources: [{ title: "iraqsm", url: "https://iraqsm.com/fx" }],
        };
      },
    },
  });
  const r = await box.run("web_search", { query: "سعر الدولار" });
  assert.equal(r.answer, "السعر 1,510 رسمي");
  const ui = await box.display("respond", { text: "x", mood: "thinking", sources: true });
  assert.equal(ui[0].type, "sources");
  assert.equal(ui[0].items[0].url, "https://iraqsm.com/fx");
});

test("long chats are folded into a running summary", async () => {
  const history = [];
  for (let i = 0; i < 20; i += 1) {
    history.push({ role: i % 2 ? "assistant" : "user", content: i === 0 ? "اسمي علي وامتحاني الخميس" : `m${i}` });
  }
  history.push({ role: "user", content: "شنو يوم امتحاني؟" });
  let seen = null;
  const llm = {
    async complete({ messages }) {
      assert.match(messages[1].content, /اسمي علي/);
      return { content: "علي، امتحانه يوم الخميس." };
    },
    async chat({ messages }) {
      seen = messages;
      return { content: "", toolCalls: [{ id: "r", name: "respond", arguments: '{"text":"الخميس","mood":"happy"}' }] };
    },
  };
  const events = [];
  const out = await runMimoTurn({
    llm,
    toolbox: createMimoToolbox({ userId: 7, deps: {} }),
    history,
    summary: "",
    emit: (e, d) => events.push([e, d]),
  });
  assert.equal(out.summarized, 21 - 12);
  assert.ok(seen.some((m) => m.role === "user" && /^\[Notes from earlier/.test(m.content) && /امتحانه يوم الخميس/.test(m.content)));
  // The app sends the summary back, so it must never get system authority.
  assert.ok(!seen.some((m) => m.role === "system" && /امتحانه يوم الخميس/.test(m.content)));
  // 12 kept chat messages + the notes and Mimo's ack of them.
  assert.equal(seen.filter((m) => m.role !== "system").length, 12 + 2);
  const done = events.find(([e]) => e === "done")[1];
  assert.equal(done.summary, "علي، امتحانه يوم الخميس.");
});

test("if the online check fails, nothing is learned", async () => {
  const deps = kDeps();
  const broken = {
    async complete({ kind }) {
      if (kind === "search") throw new Error("429");
      return { content: "x" };
    },
  };
  const out = await teachFact(deps, broken, { userId: 1, question: "عاصمة استراليا؟", answer: "سيدني" });
  assert.equal(out.learned, false);
  assert.equal(out.verdict, "verify_failed");
  assert.equal(deps.rows.length, 0);
  const notLocal = await teachFact(deps, fakeLlm({ verdict: "unverifiable", local_or_personal: false }), {
    userId: 1,
    question: "شنو اسرع حيوان بالكون؟",
    answer: "الحلزون",
  });
  assert.equal(notLocal.learned, false);
  assert.equal(deps.rows.length, 0);
});

test("an admin rejection can't be undone by a user re-teaching it", async () => {
  const deps = kDeps();
  const q = "يمته يفتح مخبز الأصيل؟";
  await deps.insert({ question: q, question_key: questionKey(q), answer: "الساعة 6", status: "rejected", search_text: "" });
  const llm = fakeLlm({ verdict: "unverifiable", local_or_personal: true });
  const out = await teachFact(deps, llm, { userId: 8, question: q, answer: "الساعة 6" });
  assert.equal(out.learned, false);
  assert.equal(out.verdict, "rejected_before");
  assert.equal(deps.rows[0].status, "rejected");
});

test("a verified fact is never replaced by an unverified answer", async () => {
  const deps = kDeps();
  const q = "شكد ارتفاع ايفرست؟";
  await deps.insert({ question: q, question_key: questionKey(q), answer: "8849 متر", status: "verified", search_text: "" });
  const llm = fakeLlm({ verdict: "unverifiable", local_or_personal: true });
  const out = await teachFact(deps, llm, { userId: 9, question: q, answer: "10 كيلو" });
  assert.equal(out.verdict, "already_verified");
  assert.equal(deps.rows[0].answer, "8849 متر");
  assert.equal(deps.rows[0].status, "verified");
});

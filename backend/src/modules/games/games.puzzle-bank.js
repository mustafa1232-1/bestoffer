const EASY_CODES = ["274", "508", "631", "920", "147", "386", "705", "819", "452", "963"];
const MEDIUM_CODES = ["4062", "7315", "2584", "9147", "6703", "3258", "8416", "5927", "1036", "7682"];
const HARD_CODES = ["2749", "5083", "6317", "9204", "1476", "3861", "7052", "8193", "4520", "9638"];

const candidateCache = new Map();

function localized(ar, en) {
  return { ar, en };
}

function uniqueCandidates(length) {
  if (candidateCache.has(length)) return candidateCache.get(length);
  const output = [];
  const visit = (prefix) => {
    if (prefix.length === length) {
      output.push(prefix);
      return;
    }
    for (let digit = 0; digit <= 9; digit += 1) {
      const value = String(digit);
      if (!prefix.includes(value)) visit(`${prefix}${value}`);
    }
  };
  visit("");
  candidateCache.set(length, output);
  return output;
}

function feedback(candidate, guess) {
  let exact = 0;
  let common = 0;
  for (let index = 0; index < guess.length; index += 1) {
    if (candidate[index] === guess[index]) exact += 1;
    if (candidate.includes(guess[index])) common += 1;
  }
  return { exact, misplaced: common - exact };
}

function clueText(constraint) {
  switch (constraint.type) {
    case "sum":
      return localized(
        `مجموع أرقام الشفرة يساوي ${constraint.value}.`,
        `The code digits add up to ${constraint.value}.`,
      );
    case "adjacent_sum":
      return localized(
        `مجموع الخانتين ${constraint.start + 1} و${constraint.start + 2} يساوي ${constraint.value}.`,
        `Positions ${constraint.start + 1} and ${constraint.start + 2} add up to ${constraint.value}.`,
      );
    case "weighted_sum":
      return localized(
        `بصمة الخزنة: الأول + ضعفي الثاني + ثلاثة أضعاف الثالث + أربعة أضعاف الأخير = ${constraint.value}.`,
        `Vault checksum: first + 2x second + 3x third + 4x last = ${constraint.value}.`,
      );
    case "parity_count":
      return localized(
        `تحتوي الشفرة على ${constraint.value} من الأرقام الزوجية.`,
        `The code contains ${constraint.value} even digits.`,
      );
    case "edge_difference":
      return localized(
        `الفرق بين الرقم الأول والأخير يساوي ${constraint.value}.`,
        `The difference between the first and last digits is ${constraint.value}.`,
      );
    case "feedback":
      return localized(
        `المحاولة ${constraint.guess}: ${constraint.exact} في مكانه الصحيح، و${constraint.misplaced} صحيح في مكان آخر.`,
        `Attempt ${constraint.guess}: ${constraint.exact} exact and ${constraint.misplaced} misplaced.`,
      );
    default:
      return localized("دليل غير معروف.", "Unknown clue.");
  }
}

function withText(constraint) {
  return { ...constraint, text: clueText(constraint) };
}

function arithmeticConstraints(code, difficulty) {
  const digits = code.split("").map(Number);
  const constraints = [];
  constraints.push({
    type: "sum",
    value: digits.reduce((total, digit) => total + digit, 0),
  });
  for (let start = 0; start < digits.length - 1; start += 1) {
    constraints.push({
      type: "adjacent_sum",
      start,
      value: digits[start] + digits[start + 1],
    });
  }
  constraints.push({
    type: "parity_count",
    value: digits.filter((digit) => digit % 2 === 0).length,
  });
  constraints.push({
    type: "edge_difference",
    value: Math.abs(digits[0] - digits.at(-1)),
  });
  if (difficulty !== "easy") {
    constraints.push({
      type: "weighted_sum",
      value: digits.reduce((total, digit, index) => total + digit * (index + 1), 0),
    });
  }
  return constraints;
}

function hardConstraints(code, index) {
  const digits = code.split("").map(Number);
  const constraints = [
    { type: "sum", value: digits.reduce((total, digit) => total + digit, 0) },
    { type: "parity_count", value: digits.filter((digit) => digit % 2 === 0).length },
  ];
  let possible = uniqueCandidates(code.length).filter((candidate) =>
    constraints.every((constraint) => candidateMatchesConstraint(candidate, constraint)),
  );
  const all = uniqueCandidates(code.length);
  const stride = 37 + index * 2;
  const pool = [];
  for (let cursor = index; cursor < all.length && pool.length < 140; cursor += stride) {
    if (all[cursor] !== code) pool.push(all[cursor]);
  }
  const rotations = [
    `${code.slice(1)}${code[0]}`,
    `${code.at(-1)}${code.slice(0, -1)}`,
    code.split("").reverse().join(""),
  ];
  for (const guess of rotations) {
    if (guess !== code && !pool.includes(guess)) pool.push(guess);
  }

  while (possible.length > 1) {
    let best = null;
    for (const guess of pool) {
      const expected = feedback(code, guess);
      const remaining = possible.filter((candidate) => {
        const result = feedback(candidate, guess);
        return result.exact === expected.exact && result.misplaced === expected.misplaced;
      });
      if (
        remaining.length > 0 &&
        remaining.length < possible.length &&
        (!best || remaining.length < best.remaining.length)
      ) {
        best = { guess, expected, remaining };
      }
    }
    if (!best) break;
    constraints.push({ type: "feedback", guess: best.guess, ...best.expected });
    possible = best.remaining;
    pool.splice(pool.indexOf(best.guess), 1);
  }

  const supplemental = [
    { type: "edge_difference", value: Math.abs(digits[0] - digits.at(-1)) },
    { type: "adjacent_sum", start: 1, value: digits[1] + digits[2] },
    {
      type: "weighted_sum",
      value: digits.reduce((total, digit, digitIndex) => total + digit * (digitIndex + 1), 0),
    },
  ];
  while (constraints.length < 6 && supplemental.length > 0) {
    const next = supplemental.shift();
    if (!constraints.some((item) => JSON.stringify(item) === JSON.stringify(next))) {
      constraints.push(next);
    }
  }
  return constraints;
}

function buildPuzzle(code, difficulty, index) {
  const digits = code.split("");
  const constraints = difficulty === "hard"
    ? hardConstraints(code, index)
    : arithmeticConstraints(code, difficulty);
  const hints = [
    {
      type: "position",
      digit: digits.at(-1),
      position: digits.length - 1,
      text: localized(
        `ثبّتوا النهاية: ${digits.at(-1)} هو الرقم الأخير.`,
        `${digits.at(-1)} is the final digit.`,
      ),
    },
    {
      type: "position",
      digit: digits[0],
      position: 0,
      text: localized(
        `بداية الشفرة هي الرقم ${digits[0]}.`,
        `The code starts with ${digits[0]}.`,
      ),
    },
    {
      type: "position",
      digit: digits[Math.floor(digits.length / 2)],
      position: Math.floor(digits.length / 2),
      text: localized(
        `الرقم ${digits[Math.floor(digits.length / 2)]} في الخانة ${Math.floor(digits.length / 2) + 1}.`,
        `${digits[Math.floor(digits.length / 2)]} is in position ${Math.floor(digits.length / 2) + 1}.`,
      ),
    },
  ];

  return {
    slug: `team-code-${difficulty}-${String(index + 1).padStart(2, "0")}`,
    titleAr: `ملف ${difficulty === "easy" ? "المدخل" : difficulty === "medium" ? "الربط" : "الحسم"} ${index + 1}`,
    titleEn: `${difficulty} file ${index + 1}`,
    difficulty,
    theme: difficulty === "hard" ? "forensics" : "arithmetic",
    version: 2,
    codeLength: digits.length,
    solutionCode: code,
    constraints,
    clues: constraints.map(withText),
    hints,
    explanationAr: `تُحل الشفرة ${code} بدمج الأدلة العددية ونتائج المحاولات، لا بكشف الأرقام مباشرة. كل دليل يقلّص الاحتمالات حتى يبقى ترتيب واحد صالح.`,
    explanationEn: `Code ${code} is derived by combining numeric constraints and attempt feedback until only one valid ordering remains.`,
  };
}

export const TEAM_CODE_PUZZLES = Object.freeze([
  ...EASY_CODES.map((code, index) => buildPuzzle(code, "easy", index)),
  ...MEDIUM_CODES.map((code, index) => buildPuzzle(code, "medium", index)),
  ...HARD_CODES.map((code, index) => buildPuzzle(code, "hard", index)),
]);

function candidateMatchesConstraint(candidate, constraint) {
  const digits = String(candidate).split("").map(Number);
  switch (constraint.type) {
    case "contains":
      return String(candidate).includes(String(constraint.digit));
    case "position":
      return String(candidate)[Number(constraint.position)] === String(constraint.digit);
    case "before":
      return String(candidate).indexOf(String(constraint.first)) < String(candidate).indexOf(String(constraint.second));
    case "sum":
      return digits.reduce((total, digit) => total + digit, 0) === Number(constraint.value);
    case "adjacent_sum": {
      const start = Number(constraint.start);
      return digits[start] + digits[start + 1] === Number(constraint.value);
    }
    case "weighted_sum":
      return digits.reduce((total, digit, index) => total + digit * (index + 1), 0) === Number(constraint.value);
    case "parity_count":
      return digits.filter((digit) => digit % 2 === 0).length === Number(constraint.value);
    case "edge_difference":
      return Math.abs(digits[0] - digits.at(-1)) === Number(constraint.value);
    case "feedback": {
      const result = feedback(String(candidate), String(constraint.guess));
      return result.exact === Number(constraint.exact) &&
        result.misplaced === Number(constraint.misplaced);
    }
    default:
      return false;
  }
}

export function candidateMatchesConstraints(candidate, constraints) {
  const normalized = String(candidate);
  if (new Set(normalized).size !== normalized.length) return false;
  return constraints.every((constraint) => candidateMatchesConstraint(normalized, constraint));
}

export function enumeratePuzzleSolutions(puzzle) {
  return uniqueCandidates(puzzle.codeLength).filter((candidate) =>
    candidateMatchesConstraints(candidate, puzzle.constraints),
  );
}

export function validatePuzzleBank(puzzles = TEAM_CODE_PUZZLES) {
  const slugs = new Set();
  const results = puzzles.map((puzzle) => {
    const solutions = enumeratePuzzleSolutions(puzzle);
    const valid =
      !slugs.has(puzzle.slug) &&
      puzzle.version === 2 &&
      solutions.length === 1 &&
      solutions[0] === puzzle.solutionCode &&
      new Set(puzzle.solutionCode).size === puzzle.codeLength &&
      puzzle.clues.length >= 4 &&
      puzzle.hints.length === 3;
    slugs.add(puzzle.slug);
    return { slug: puzzle.slug, valid, solutions };
  });
  return {
    valid: results.every((item) => item.valid),
    count: results.length,
    results,
  };
}

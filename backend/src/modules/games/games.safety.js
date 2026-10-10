import { AppError } from "../../shared/utils/errors.js";

// Shared safety helpers for the Maslaki games' rooms and chats.

// Normalizes Arabic so trivial evasions (diacritics, tatweel, letter variants,
// stretched letters, separators between letters) still match the word list.
export function normalizeForModeration(value) {
  return String(value || "")
    .toLowerCase()
    .replace(/[ً-ٰٟـ]/g, "") // tashkeel + tatweel
    .replace(/[أإآٱ]/g, "ا")
    .replace(/ة/g, "ه")
    .replace(/ى/g, "ي")
    .replace(/ؤ/g, "و")
    .replace(/ئ/g, "ي")
    .replace(/(.)\1{2,}/gu, "$1");
}

// Kept intentionally short and high-precision: masking ordinary words would be
// worse for players than missing a rare insult. Extend from moderation reports.
const BLOCKED_TERMS = [
  "كلب", "حمار", "خنزير", "زباله", "قذر", "وسخ", "منيوك", "منيك", "نيك",
  "كس", "كسمك", "كس امك", "عير", "زب", "شرموط", "شرموطه", "قحبه", "قحبة", "عاهره",
  "ديوث", "لوطي", "مخنث", "ابن الكلب", "ابن الحرام", "يلعن", "انعل", "كواد", "گواد",
  "fuck", "shit", "bitch", "bastard", "asshole", "dick", "pussy", "whore", "slut",
].map(normalizeForModeration);
const SINGLE_WORD = new Set(BLOCKED_TERMS.filter((term) => !term.includes(" ")));
const PHRASES = BLOCKED_TERMS.filter((term) => term.includes(" "));

function tokenKey(token) {
  // Strips the Arabic definite article and common attached prefixes.
  const bare = normalizeForModeration(token).replace(/[^\p{L}\p{N}]/gu, "");
  const withoutArticle = bare.replace(/^(وال|بال|فال|كال|لل|ال)/u, "");
  return [bare, withoutArticle, withoutArticle.replace(/^[وبفل]/u, "")];
}

/// Returns the text with offensive words masked, and whether anything changed.
export function maskOffensiveText(value) {
  const text = String(value || "");
  let flagged = false;
  let masked = text.replace(/\S+/gu, (token) => {
    if (tokenKey(token).some((key) => key && SINGLE_WORD.has(key))) {
      flagged = true;
      return "•".repeat(Math.min(6, Math.max(3, [...token].length)));
    }
    return token;
  });
  const normalized = normalizeForModeration(masked);
  if (PHRASES.some((phrase) => normalized.includes(phrase))) {
    flagged = true;
    for (const phrase of PHRASES) {
      const words = phrase.split(" ");
      masked = masked.replace(/\S+(\s+\S+)+/gu, (span) =>
        normalizeForModeration(span).includes(phrase)
          ? span.split(/\s+/).map((word) =>
              words.includes(normalizeForModeration(word)) ? "•••" : word).join(" ")
          : span);
    }
  }
  return { text: masked, flagged };
}

/// Rejects joining a room that contains someone who blocked the user (or whom
/// the user blocked), reusing the social graph's block relation.
export async function assertNoBlockedMembers(client, userId, memberUserIds, code = "GAME_ROOM_BLOCKED") {
  const others = [...new Set((memberUserIds || []).map(Number))].filter((id) => id > 0 && id !== Number(userId));
  if (!others.length) return;
  const rows = await client.query(
    `SELECT 1 FROM social_user_relation
     WHERE status='blocked'
       AND ((user_a_id=$1 AND user_b_id=ANY($2::bigint[]))
         OR (user_b_id=$1 AND user_a_id=ANY($2::bigint[])))
     LIMIT 1`,
    [Number(userId), others],
  );
  if (rows.rowCount > 0) throw new AppError(code, { status: 403 });
}

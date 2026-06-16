import { validateUpdateSocialProfile } from "../feed/feed.validators.js";

export function validateUpdateMyProfile(body = {}, opts = {}) {
  return validateUpdateSocialProfile(body, opts);
}

export function validateDeleteMyAccount(body = {}) {
  const errors = [];
  const note =
    body.note === undefined || body.note === null
      ? null
      : String(body.note).trim();
  if (note != null && note.length > 500) {
    errors.push("note");
  }
  return {
    ok: errors.length === 0,
    errors,
    value: {
      note,
    },
  };
}

export function validateSessionId(sessionId) {
  const parsed = Number(sessionId);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    return { ok: false, errors: ["sessionId"] };
  }
  return { ok: true, errors: [], value: parsed };
}

function text(value, max = 300) {
  const normalized = String(value ?? "").trim();
  return normalized && normalized.length <= max ? normalized : null;
}

export function roomId(value) {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : null;
}

export function createGameBody(body = {}) {
  const mode = body.mode === "cooperative" ? "cooperative" : body.mode === "solo" ? "solo" : null;
  return mode ? { mode } : null;
}

export function joinRoomBody(body = {}) {
  const code = text(body.code, 6)?.toUpperCase();
  return code && /^[A-HJ-NP-Z2-9]{6}$/.test(code) ? { code } : null;
}

export function readyBody(body = {}) {
  return typeof body.ready === "boolean" ? { ready: body.ready } : null;
}

export function attemptBody(body = {}) {
  const code = text(body.code, 4);
  const commandId = text(body.commandId, 80);
  return code && commandId ? { code, commandId } : null;
}

export function commandBody(body = {}) {
  const commandId = text(body.commandId, 80);
  return commandId ? { commandId } : null;
}

export function proposalBody(body = {}) {
  const kind = body.kind === "hint" ? "hint" : body.kind === "code" ? "code" : null;
  const code = kind === "code" ? text(body.code, 4) : null;
  const commandId = text(body.commandId, 80);
  if (!kind || !commandId || (kind === "code" && !code)) return null;
  return { kind, code, commandId };
}

export function voteBody(body = {}) {
  const vote = body.vote === "approve" ? "approve" : body.vote === "reject" ? "reject" : null;
  return vote ? { vote } : null;
}

export function messageBody(body = {}) {
  const value = text(body.body, 300);
  return value ? { body: value } : null;
}

export function campaignBody(body = {}) {
  const value = {};
  if (typeof body.enabled === "boolean") value.enabled = body.enabled;
  for (const key of ["startsAt", "endsAt"]) {
    if (body[key] != null) {
      const date = new Date(body[key]);
      if (Number.isNaN(date.getTime())) return null;
      value[key] = date.toISOString();
    }
  }
  if (body.rewardType != null) {
    const rewardType = text(body.rewardType, 30);
    if (!rewardType) return null;
    value.rewardType = rewardType;
  }
  for (const key of ["rewardValue", "rewardValidDays", "claimLimit"]) {
    if (body[key] != null) {
      const number = Number(body[key]);
      if (!Number.isFinite(number) || number < 0) return null;
      value[key] = number;
    }
  }
  return value;
}

export function createMafiaBody(body = {}) {
  const ruleset = body.ruleset === "advanced" ? "advanced" : "standard";
  const pace = body.pace === "quick" ? "quick" : "classic";
  const tableTheme = ["emerald", "royal", "cinema"].includes(body.tableTheme)
    ? body.tableTheme
    : "emerald";
  const maxPlayers = Number(body.maxPlayers ?? 14);
  if (!Number.isInteger(maxPlayers) || maxPlayers < 7 || maxPlayers > 14) return null;
  return {
    ruleset,
    pace,
    tableTheme,
    maxPlayers,
    revealRolesOnDeath: body.revealRolesOnDeath !== false,
  };
}

export function mafiaActionBody(body = {}) {
  const allowed = new Set([
    "nominate", "vote", "mafia_kill", "doctor_protect",
    "bodyguard_protect", "detective_inspect", "don_inspect", "framer_frame",
  ]);
  const type = text(body.type, 30);
  const commandId = text(body.commandId, 80);
  const targetPlayerId = body.targetPlayerId == null ? null : roomId(body.targetPlayerId);
  if (!type || !allowed.has(type) || !commandId) return null;
  if (type !== "vote" && !targetPlayerId) return null;
  const phaseVersion = body.phaseVersion == null ? null : Number(body.phaseVersion);
  if (phaseVersion != null && (!Number.isInteger(phaseVersion) || phaseVersion < 1)) return null;
  return { type, targetPlayerId, commandId, ...(phaseVersion == null ? {} : {phaseVersion}) };
}

export function mafiaMessageBody(body = {}) {
  const message = text(body.body, 300);
  const channel = ["public", "mafia", "dead"].includes(body.channel)
    ? body.channel
    : "public";
  const clientMessageId = body.clientMessageId == null ? null : text(body.clientMessageId,80);
  if (body.clientMessageId != null && !/^[A-Za-z0-9._:-]{8,80}$/.test(clientMessageId || '')) return null;
  return message ? { body: message, channel, ...(clientMessageId == null ? {} : {clientMessageId}) } : null;
}

export function mafiaInteractionBody(body = {}) {
  const kind = text(body.kind, 24);
  const commandId = text(body.commandId, 80);
  const reactions = new Set(["laugh", "happy", "angry", "surprised", "applause"]);
  const gifts = new Set(["rose", "tea", "egg"]);
  const honors = new Set(["mvp"]);
  if (
    !kind || !commandId ||
    (!reactions.has(kind) && !gifts.has(kind) && !honors.has(kind))
  ) {
    return null;
  }
  const targetPlayerId = body.targetPlayerId == null
    ? null
    : roomId(body.targetPlayerId);
  if ((gifts.has(kind) || honors.has(kind)) && !targetPlayerId) return null;
  return {
    kind,
    commandId,
    targetPlayerId,
    interactionType: honors.has(kind)
      ? "honor"
      : gifts.has(kind)
        ? "gift"
        : "reaction",
  };
}

export function mafiaReportBody(body = {}) {
  const targetPlayerId = roomId(body.targetPlayerId);
  const commandId = text(body.commandId, 80);
  const reason = [
    "harassment",
    "inappropriate_audio",
    "cheating",
    "spam",
    "other",
  ].includes(body.reason)
    ? body.reason
    : null;
  const details = body.details == null ? null : text(body.details, 300);
  if (!targetPlayerId || !commandId || !reason) return null;
  if (body.details != null && !details) return null;
  return { targetPlayerId, commandId, reason, details };
}

export function mafiaReportReviewBody(body = {}) {
  const note = body.note == null ? null : text(body.note, 300);
  if (body.note != null && !note) return null;
  return { note };
}

export function knowledgeDuelBody(body = {}) {
  const teamSize = Number(body.teamSize ?? 1);
  const bestOf = Number(body.bestOf ?? 1);
  const title = text(body.title ?? "تحدي خريطة المعرفة", 160);
  return Number.isInteger(teamSize) && teamSize >= 1 && teamSize <= 4 && title && [1,3,5,9].includes(bestOf) &&
    (body.isPrivate == null || typeof body.isPrivate === "boolean")
    ? { teamSize, bestOf, title, isPrivate: body.isPrivate === true }
    : null;
}

export function knowledgeRoomId(value) {
  return roomId(value);
}

export function knowledgeRoomCodeBody(body = {}) {
  const code = text(body.code, 8)?.toUpperCase();
  return code && /^[A-HJ-NP-Z2-9]{7}$/.test(code) ? { code } : null;
}

export function knowledgeRoomSeatBody(body = {}) {
  const side = ["a", "b"].includes(body.side) ? body.side : null;
  const code = body.code == null ? null : text(body.code, 8)?.toUpperCase();
  if (!side || (body.code != null && (!code || !/^[A-HJ-NP-Z2-9]{7}$/.test(code)))) return null;
  return { side, code };
}

export function knowledgeTeamBody(body = {}) {
  const eventId = roomId(body.eventId);
  const name = text(body.name ?? "فريق المعرفة", 48);
  return eventId && name ? { eventId, name } : null;
}

export function knowledgeJoinTeamBody(body = {}) {
  const code = text(body.code, 8)?.toUpperCase();
  return code && /^[A-HJ-NP-Z2-9]{7}$/.test(code) ? { code } : null;
}

export function knowledgeAnswerBody(body = {}) {
  const answerIndex = Number(body.answerIndex);
  const districtId = text(body.districtId, 40);
  const roundId = Number(body.roundId);
  const questionId = Number(body.questionId);
  const idempotencyKey = typeof body.idempotencyKey === 'string' ? body.idempotencyKey : '';
  return body.answerIndex != null && Number.isInteger(answerIndex) && answerIndex >= 0 && answerIndex <= 3 && districtId
    && Number.isSafeInteger(roundId) && roundId > 0 && Number.isSafeInteger(questionId) && questionId > 0
    && /^[a-zA-Z0-9_-]{16,80}$/.test(idempotencyKey)
    ? { answerIndex, districtId, roundId, questionId, idempotencyKey }
    : null;
}

const knowledgeCategories = new Set([
  "iraq", "science", "history", "geography", "culture", "sports", "technology", "nature", "space", "math", "logic",
]);

export function knowledgeChatBody(body = {}) {
  const channel = ["team", "public"].includes(body.channel) ? body.channel : null;
  const message = text(body.body, 500);
  return channel && message ? { channel, body: message } : null;
}

export function knowledgeConsentBody(body = {}) {
  return typeof body.enabled === "boolean" ? { enabled: body.enabled } : null;
}

export function knowledgeReactionBody(body = {}) {
  const kinds = new Set(["happy", "angry", "laugh", "surprised", "applause", "request_public_chat"]);
  return kinds.has(body.kind) ? { kind: body.kind } : null;
}

export function knowledgeQuestionBody(body = {}, { allowActiveOnly = false } = {}) {
  if (allowActiveOnly && Object.keys(body).every((key) => key === "active") && typeof body.active === "boolean") {
    return { active: body.active };
  }
  const category = knowledgeCategories.has(body.category) ? body.category : null;
  const difficulty = ["easy", "medium", "hard"].includes(body.difficulty) ? body.difficulty : null;
  const question = text(body.question, 1000);
  const options = Array.isArray(body.options) && body.options.length === 4
    ? body.options.map((option) => text(option, 200))
    : null;
  const answerIndex = Number(body.answerIndex);
  const explanation = body.explanation == null ? "" : text(body.explanation, 500);
  if (!category || !difficulty || !question || !options || options.some((option) => !option) ||
      new Set(options.map((option) => option.toLocaleLowerCase())).size !== 4 ||
      !Number.isInteger(answerIndex) || answerIndex < 0 || answerIndex > 3 || explanation == null) return null;
  return { category, difficulty, question, options, answerIndex, explanation };
}

export function knowledgeTournamentBody(body = {}) {
  const bestOf = Number(body.bestOf ?? 1);
  const title = text(body.title, 160);
  const teamSize = Number(body.teamSize);
  const maxTeams = Number(body.maxTeams);
  const prizeTitle = body.prizeTitle == null ? null : text(body.prizeTitle, 120);
  const prizeDescription = body.prizeDescription == null ? null : text(body.prizeDescription, 500);
  const date = (value) => {
    if (value == null) return null;
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? undefined : parsed.toISOString();
  };
  const startsAt = date(body.startsAt);
  const endsAt = date(body.endsAt);
  if (!title || ![1,3,5,9].includes(bestOf) || !Number.isInteger(teamSize) || teamSize < 1 || teamSize > 4 ||
      !Number.isInteger(maxTeams) || maxTeams < 2 || maxTeams > 64 ||
      (body.prizeTitle != null && !prizeTitle) ||
      (body.prizeDescription != null && !prizeDescription) ||
      startsAt === undefined || endsAt === undefined ||
      (startsAt && endsAt && new Date(endsAt) <= new Date(startsAt))) return null;
  return { title, teamSize, bestOf, maxTeams, prizeTitle, prizeDescription,
    prizeIsMock: body.prizeIsMock !== false, startsAt, endsAt };
}

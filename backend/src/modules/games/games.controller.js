import * as service from "./games.service.js";
import * as mafia from "./mafia.service.js";
import * as validators from "./games.validators.js";
import * as knowledge from "./knowledge.service.js";

function invalid(res) {
  return res.status(400).json({ message: "VALIDATION_ERROR" });
}

function actor(req) {
  return {
    userId: req.userId,
    role: req.userRole,
    isSuperAdmin: req.userIsSuperAdmin === true,
    canManageGames:
      req.permissionScopes?.["competitions.manage"] != null,
  };
}

export async function status(req, res, next) {
  try { return res.json(await service.getGamesStatus(req.userId)); } catch (error) { return next(error); }
}

export async function create(req, res, next) {
  try {
    const body = validators.createGameBody(req.body);
    if (!body) return invalid(res);
    return res.status(201).json(await service.createGame(req.userId, body.mode));
  } catch (error) { return next(error); }
}

export async function join(req, res, next) {
  try {
    const body = validators.joinRoomBody(req.body);
    if (!body) return invalid(res);
    return res.json(await service.joinRoom(req.userId, body.code));
  } catch (error) { return next(error); }
}

export async function snapshot(req, res, next) {
  try {
    const id = validators.roomId(req.params.roomId);
    if (!id) return invalid(res);
    return res.json(await service.getRoomSnapshot(id, req.userId));
  } catch (error) { return next(error); }
}

export async function ready(req, res, next) {
  try {
    const id = validators.roomId(req.params.roomId);
    const body = validators.readyBody(req.body);
    if (!id || !body) return invalid(res);
    return res.json(await service.setReady(req.userId, id, body.ready));
  } catch (error) { return next(error); }
}

export async function start(req, res, next) {
  try {
    const id = validators.roomId(req.params.roomId);
    if (!id) return invalid(res);
    return res.json(await service.startRoom(req.userId, id));
  } catch (error) { return next(error); }
}

export async function attempt(req, res, next) {
  try {
    const id = validators.roomId(req.params.roomId);
    const body = validators.attemptBody(req.body);
    if (!id || !body) return invalid(res);
    return res.json(await service.submitSoloCode(req.userId, id, body));
  } catch (error) { return next(error); }
}

export async function hint(req, res, next) {
  try {
    const id = validators.roomId(req.params.roomId);
    const body = validators.commandBody(req.body);
    if (!id || !body) return invalid(res);
    return res.json(
      await service.requestSoloHint(req.userId, id, body.commandId),
    );
  } catch (error) { return next(error); }
}

export async function propose(req, res, next) {
  try {
    const id = validators.roomId(req.params.roomId);
    const body = validators.proposalBody(req.body);
    if (!id || !body) return invalid(res);
    return res.status(201).json(await service.createProposal(req.userId, id, body));
  } catch (error) { return next(error); }
}

export async function vote(req, res, next) {
  try {
    const id = validators.roomId(req.params.roomId);
    const proposalId = validators.roomId(req.params.proposalId);
    const body = validators.voteBody(req.body);
    if (!id || !proposalId || !body) return invalid(res);
    return res.json(await service.voteProposal(req.userId, id, proposalId, body.vote));
  } catch (error) { return next(error); }
}

export async function message(req, res, next) {
  try {
    const id = validators.roomId(req.params.roomId);
    const body = validators.messageBody(req.body);
    if (!id || !body) return invalid(res);
    return res.status(201).json(await service.sendMessage(req.userId, id, body.body));
  } catch (error) { return next(error); }
}

export async function heartbeat(req, res, next) {
  try {
    const id = validators.roomId(req.params.roomId);
    if (!id) return invalid(res);
    return res.json(await service.heartbeat(req.userId, id));
  } catch (error) { return next(error); }
}

export async function teamCodeVoiceToken(req, res, next) {
  try {
    const id = validators.roomId(req.params.roomId);
    if (!id) return invalid(res);
    return res.json(await service.getTeamCodeVoiceAccess(req.userId, id));
  } catch (error) { return next(error); }
}

export async function leave(req, res, next) {
  try {
    const id = validators.roomId(req.params.roomId);
    if (!id) return invalid(res);
    return res.json(await service.leaveRoom(req.userId, id));
  } catch (error) { return next(error); }
}

export async function continueAlone(req, res, next) {
  try {
    const id = validators.roomId(req.params.roomId);
    if (!id) return invalid(res);
    return res.json(await service.continueAlone(req.userId, id));
  } catch (error) { return next(error); }
}

export async function history(req, res, next) {
  try { return res.json(await service.listMyGameHistory(req.userId, req.query.limit)); } catch (error) { return next(error); }
}

export async function claim(req, res, next) {
  try {
    const id = validators.roomId(req.params.sessionId);
    if (!id) return invalid(res);
    return res.status(201).json(await service.claimReward(req.userId, id));
  } catch (error) { return next(error); }
}

export async function adminOverview(req, res, next) {
  try { return res.json(await service.getAdminOverview(actor(req))); } catch (error) { return next(error); }
}

export async function adminUpdateCampaign(req, res, next) {
  try {
    const body = validators.campaignBody(req.body);
    if (!body) return invalid(res);
    return res.json(await service.updateCampaign(actor(req), body));
  } catch (error) { return next(error); }
}

export async function knowledgeEvents(_req, res, next) {
  try { return res.json(await knowledge.listKnowledgeEvents(_req.userId)); }
  catch (error) { return next(error); }
}

export async function knowledgeCreateDuel(req, res, next) {
  try {
    const body = validators.knowledgeDuelBody(req.body);
    if (!body) return invalid(res);
    return res.status(201).json(await knowledge.createDuel(req.userId, body));
  } catch (error) { return next(error); }
}

export async function knowledgeLookupRoom(req, res, next) {
  try {
    const body = validators.knowledgeRoomCodeBody(req.body);
    if (!body) return invalid(res);
    return res.json(await knowledge.lookupKnowledgeRoom(req.userId, body.code));
  } catch (error) { return next(error); }
}

export async function knowledgeRoom(req, res, next) {
  try {
    const eventId = validators.knowledgeRoomId(req.params.eventId);
    const code = req.query.code == null ? null : String(req.query.code);
    if (!eventId) return invalid(res);
    return res.json(await knowledge.getKnowledgeRoom(req.userId, eventId, code));
  } catch (error) { return next(error); }
}

export async function knowledgeJoinRoomSeat(req, res, next) {
  try {
    const eventId = validators.knowledgeRoomId(req.params.eventId);
    const body = validators.knowledgeRoomSeatBody(req.body);
    if (!eventId || !body) return invalid(res);
    return res.json(await knowledge.joinKnowledgeRoomSeat(req.userId, eventId, body.side, body.code));
  } catch (error) { return next(error); }
}

export async function knowledgeCloseRoom(req, res, next) {
  try {
    const eventId = validators.knowledgeRoomId(req.params.eventId);
    if (!eventId) return invalid(res);
    return res.json(await knowledge.closeKnowledgeRoom(req.userId, eventId));
  } catch (error) { return next(error); }
}

export async function knowledgeReactivateRoom(req, res, next) {
  try {
    const eventId = validators.knowledgeRoomId(req.params.eventId);
    if (!eventId) return invalid(res);
    return res.json(await knowledge.reactivateKnowledgeRoom(req.userId, eventId));
  } catch (error) { return next(error); }
}

export async function knowledgeRegisterTeam(req, res, next) {
  try {
    const body = validators.knowledgeTeamBody(req.body);
    if (!body) return invalid(res);
    return res.status(201).json(await knowledge.registerTeam(req.userId, body.eventId, body.name));
  } catch (error) { return next(error); }
}

export async function knowledgeJoinTeam(req, res, next) {
  try {
    const body = validators.knowledgeJoinTeamBody(req.body);
    if (!body) return invalid(res);
    return res.json(await knowledge.joinKnowledgeTeam(req.userId, body.code));
  } catch (error) { return next(error); }
}

export async function knowledgeMatches(req, res, next) {
  try {
    const eventId = validators.roomId(req.params.eventId);
    if (!eventId) return invalid(res);
    return res.json(await knowledge.listKnowledgeMatches(req.userId, eventId));
  } catch (error) { return next(error); }
}

export async function knowledgeBracket(req, res, next) {
  try {
    const eventId = validators.roomId(req.params.eventId);
    if (!eventId) return invalid(res);
    return res.json(await knowledge.readKnowledgeBracket(req.userId,eventId));
  } catch (error) { return next(error); }
}

export async function knowledgeMatch(req, res, next) {
  try {
    const matchId = validators.roomId(req.params.matchId);
    if (!matchId) return invalid(res);
    return res.json(await knowledge.knowledgeMatchSnapshot(req.userId, matchId));
  } catch (error) { return next(error); }
}

export async function knowledgeAnswer(req, res, next) {
  try {
    if (!req.body?.roundId || !req.body?.questionId || !req.body?.idempotencyKey) {
      return res.status(426).json({ code: 'GAME_UPDATE_REQUIRED', message: 'حدّث التطبيق لمتابعة اللعب', requestId: req.requestId });
    }
    const matchId = validators.roomId(req.params.matchId);
    const body = validators.knowledgeAnswerBody(req.body);
    if (!matchId || !body) return invalid(res);
    return res.json(await knowledge.answerKnowledgeQuestion(req.userId, matchId, body, { traceId: req.requestId }));
  } catch (error) { return next(error); }
}

export async function knowledgeAttempt(req, res, next) {
  try {
    const matchId = validators.roomId(req.params.matchId);
    const key = req.params.key || '';
    if (!matchId || !/^[a-zA-Z0-9_-]{16,80}$/.test(key)) return invalid(res);
    return res.json(await knowledge.knowledgeAttemptStatus(req.userId, matchId, key));
  } catch (error) { return next(error); }
}

export async function knowledgeLeaveSeat(req,res,next) {
  try {
    const eventId=validators.roomId(req.params.eventId);
    if(!eventId)return invalid(res);
    return res.json(await knowledge.leaveKnowledgeRoomSeat(req.userId,eventId));
  }catch(error){return next(error);}
}

export async function knowledgeChat(req, res, next) {
  try {
    const matchId = validators.roomId(req.params.matchId);
    const body = validators.knowledgeChatBody(req.body);
    if (!matchId || !body) return invalid(res);
    return res.status(201).json(await knowledge.sendKnowledgeChatMessage(req.userId, matchId, body));
  } catch (error) { return next(error); }
}

export async function knowledgeConsent(req, res, next) {
  try {
    const matchId = validators.roomId(req.params.matchId);
    const body = validators.knowledgeConsentBody(req.body);
    if (!matchId || !body) return invalid(res);
    return res.json(await knowledge.setKnowledgePublicChatConsent(req.userId, matchId, body.enabled));
  } catch (error) { return next(error); }
}

export async function knowledgeReaction(req, res, next) {
  try {
    const matchId = validators.roomId(req.params.matchId);
    const body = validators.knowledgeReactionBody(req.body);
    if (!matchId || !body) return invalid(res);
    return res.status(201).json(await knowledge.sendKnowledgeReaction(req.userId, matchId, body.kind));
  } catch (error) { return next(error); }
}

export async function knowledgeVoiceToken(req, res, next) {
  try {
    const matchId = validators.roomId(req.params.matchId);
    const channel = req.body?.channel === "public" ? "public" : req.body?.channel === "team" ? "team" : null;
    if (!matchId || !channel) return invalid(res);
    return res.json(await knowledge.getKnowledgeVoiceAccess(req.userId, matchId, channel));
  } catch (error) { return next(error); }
}

export async function knowledgeAdminOverview(_req, res, next) {
  try { return res.json(await knowledge.getKnowledgeAdminOverview()); }
  catch (error) { return next(error); }
}

export async function knowledgeAdminQuestions(req, res, next) {
  try {
    return res.json(await knowledge.listKnowledgeQuestionsForAdmin({
      category: req.query.category, difficulty: req.query.difficulty,
      query: typeof req.query.query === "string" ? req.query.query.trim().slice(0, 100) : null,
      limit: req.query.limit, offset: req.query.offset,
    }));
  } catch (error) { return next(error); }
}

export async function knowledgeAdminCreateQuestion(req, res, next) {
  try {
    const body = validators.knowledgeQuestionBody(req.body);
    if (!body) return invalid(res);
    return res.status(201).json(await knowledge.saveKnowledgeQuestion(actor(req), body));
  } catch (error) { return next(error); }
}

export async function knowledgeAdminUpdateQuestion(req, res, next) {
  try {
    const questionId = validators.roomId(req.params.questionId);
    const body = validators.knowledgeQuestionBody(req.body, { allowActiveOnly: true });
    if (!questionId || !body) return invalid(res);
    return res.json(await knowledge.saveKnowledgeQuestion(actor(req), body, questionId));
  } catch (error) { return next(error); }
}

export async function knowledgeAdminCreate(req, res, next) {
  try {
    const body = validators.knowledgeTournamentBody(req.body);
    if (!body) return invalid(res);
    return res.status(201).json(await knowledge.createKnowledgeTournament(actor(req), body));
  } catch (error) { return next(error); }
}

export async function knowledgeAdminStart(req, res, next) {
  try {
    const eventId = validators.roomId(req.params.eventId);
    if (!eventId) return invalid(res);
    return res.json(await knowledge.startKnowledgeTournament(actor(req), eventId));
  } catch (error) { return next(error); }
}

export async function mafiaCreate(req, res, next) {
  try {
    const body = validators.createMafiaBody(req.body);
    if (!body) return invalid(res);
    return res.status(201).json(await mafia.createMafiaRoom(req.userId, body));
  } catch (error) { return next(error); }
}

export async function mafiaJoin(req, res, next) {
  try {
    const body = validators.joinRoomBody(req.body);
    if (!body) return invalid(res);
    return res.json(await mafia.joinMafiaRoom(req.userId, body.code));
  } catch (error) { return next(error); }
}

export async function mafiaSnapshot(req, res, next) {
  try {
    const id = validators.roomId(req.params.roomId);
    if (!id) return invalid(res);
    return res.json(await mafia.getMafiaSnapshot(id, req.userId));
  } catch (error) { return next(error); }
}

export async function mafiaReady(req, res, next) {
  try {
    const id = validators.roomId(req.params.roomId);
    const body = validators.readyBody(req.body);
    if (!id || !body) return invalid(res);
    return res.json(await mafia.setMafiaReady(req.userId, id, body.ready));
  } catch (error) { return next(error); }
}

export async function mafiaStart(req, res, next) {
  try {
    const id = validators.roomId(req.params.roomId);
    if (!id) return invalid(res);
    return res.json(await mafia.startMafiaRoom(req.userId, id));
  } catch (error) { return next(error); }
}

export async function mafiaAcknowledgeRole(req, res, next) {
  try {
    const id = validators.roomId(req.params.roomId);
    if (!id) return invalid(res);
    return res.json(await mafia.acknowledgeMafiaRole(req.userId, id));
  } catch (error) { return next(error); }
}

export async function mafiaAction(req, res, next) {
  try {
    const id = validators.roomId(req.params.roomId);
    const body = validators.mafiaActionBody(req.body);
    if (!id || !body) return invalid(res);
    return res.json(await mafia.submitMafiaAction(req.userId, id, body));
  } catch (error) { return next(error); }
}

export async function mafiaAdvance(req, res, next) {
  try {
    const id = validators.roomId(req.params.roomId);
    if (!id) return invalid(res);
    await mafia.getMafiaSnapshot(id, req.userId);
    await mafia.advanceMafiaRoom(id);
    return res.json(await mafia.getMafiaSnapshot(id, req.userId));
  } catch (error) { return next(error); }
}

export async function mafiaMessage(req, res, next) {
  try {
    const id = validators.roomId(req.params.roomId);
    const body = validators.mafiaMessageBody(req.body);
    if (!id || !body) return invalid(res);
    return res.status(201).json(await mafia.sendMafiaMessage(req.userId, id, body));
  } catch (error) { return next(error); }
}

export async function mafiaInteraction(req, res, next) {
  try {
    const id = validators.roomId(req.params.roomId);
    const body = validators.mafiaInteractionBody(req.body);
    if (!id || !body) return invalid(res);
    return res.status(201).json(
      await mafia.sendMafiaInteraction(req.userId, id, body),
    );
  } catch (error) { return next(error); }
}

export async function mafiaReport(req, res, next) {
  try {
    const id = validators.roomId(req.params.roomId);
    const body = validators.mafiaReportBody(req.body);
    if (!id || !body) return invalid(res);
    return res.status(201).json(
      await mafia.reportMafiaPlayer(req.userId, id, body),
    );
  } catch (error) { return next(error); }
}

export async function mafiaReports(req, res, next) {
  try { return res.json(await mafia.listMafiaReports(req.query.limit)); }
  catch (error) { return next(error); }
}

export async function mafiaReviewReport(req, res, next) {
  try {
    const reportId = validators.roomId(req.params.reportId);
    const body = validators.mafiaReportReviewBody(req.body);
    if (!reportId || !body) return invalid(res);
    return res.json(
      await mafia.reviewMafiaReport(req.userId, reportId, body.note),
    );
  } catch (error) { return next(error); }
}

export async function mafiaHeartbeat(req, res, next) {
  try {
    const id = validators.roomId(req.params.roomId);
    if (!id) return invalid(res);
    return res.json(await mafia.mafiaHeartbeat(req.userId, id));
  } catch (error) { return next(error); }
}

export async function mafiaVoiceToken(req, res, next) {
  try {
    const id = validators.roomId(req.params.roomId);
    if (!id) return invalid(res);
    return res.json(await mafia.getMafiaVoiceAccess(req.userId, id));
  } catch (error) { return next(error); }
}

export async function mafiaKick(req, res, next) {
  try {
    const roomId = validators.roomId(req.params.roomId);
    const playerId = validators.roomId(req.params.playerId);
    if (!roomId || !playerId) return invalid(res);
    return res.json(await mafia.kickMafiaPlayer(req.userId, roomId, playerId));
  } catch (error) { return next(error); }
}

export async function mafiaClose(req, res, next) {
  try {
    const id = validators.roomId(req.params.roomId);
    if (!id) return invalid(res);
    return res.json(await mafia.closeMafiaRoom(req.userId, id));
  } catch (error) { return next(error); }
}

export async function mafiaReactivate(req, res, next) {
  try {
    const id = validators.roomId(req.params.roomId);
    const body = validators.createMafiaBody(req.body);
    if (!id || !body) return invalid(res);
    return res.status(201).json(
      await mafia.reactivateMafiaRoom(req.userId, id, body),
    );
  } catch (error) { return next(error); }
}

export async function mafiaLeave(req, res, next) {
  try {
    const id = validators.roomId(req.params.roomId);
    if (!id) return invalid(res);
    return res.json(await mafia.leaveMafiaRoom(req.userId, id));
  } catch (error) { return next(error); }
}

export async function mafiaHistory(req, res, next) {
  try { return res.json(await mafia.listMyMafiaRooms(req.userId, req.query.limit)); }
  catch (error) { return next(error); }
}

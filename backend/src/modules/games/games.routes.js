import { Router } from "express";

import { requireAuth } from "../../shared/middleware/auth.middleware.js";
import { createRateLimiter } from "../../shared/middleware/rate-limit.middleware.js";
import { requirePermission } from "../../shared/middleware/permission.middleware.js";
import * as controller from "./games.controller.js";
import { wakeMafiaWorkers } from "./mafia.worker.js";

export const gamesRouter = Router();

gamesRouter.use(requireAuth);
gamesRouter.use(
  createRateLimiter({ windowMs: 60_000, maxRequests: 240, keyPrefix: "games" }),
);

// A committed mafia write queues a delivery row (DB trigger). Wake the workers
// as the response finishes so other players see it now, not at the next poll.
gamesRouter.use("/mafia", (req, res, next) => {
  if (req.method !== "GET") {
    res.on("finish", () => {
      if (res.statusCode < 400) wakeMafiaWorkers();
    });
  }
  next();
});

gamesRouter.get("/status", controller.status);
gamesRouter.post("/rooms", controller.create);
gamesRouter.post("/rooms/join", controller.join);
gamesRouter.get("/rooms/:roomId", controller.snapshot);
gamesRouter.post("/rooms/:roomId/ready", controller.ready);
gamesRouter.post("/rooms/:roomId/start", controller.start);
gamesRouter.post("/rooms/:roomId/attempt", controller.attempt);
gamesRouter.post("/rooms/:roomId/hint", controller.hint);
gamesRouter.post("/rooms/:roomId/proposals", controller.propose);
gamesRouter.post("/rooms/:roomId/proposals/:proposalId/vote", controller.vote);
gamesRouter.post("/rooms/:roomId/messages", controller.message);
gamesRouter.post("/rooms/:roomId/heartbeat", controller.heartbeat);
gamesRouter.post("/rooms/:roomId/voice-token", controller.teamCodeVoiceToken);
gamesRouter.post("/rooms/:roomId/leave", controller.leave);
gamesRouter.post("/rooms/:roomId/continue-solo", controller.continueAlone);
gamesRouter.get("/history", controller.history);
gamesRouter.post("/sessions/:sessionId/reward", controller.claim);

// Maslaki Mafia is isolated from Team Code so its secret-role authorization
// cannot leak through the cooperative puzzle endpoints.
gamesRouter.post("/mafia/rooms", controller.mafiaCreate);
gamesRouter.post("/mafia/rooms/join", controller.mafiaJoin);
gamesRouter.get("/mafia/rooms/:roomId", controller.mafiaSnapshot);
gamesRouter.post("/mafia/rooms/:roomId/ready", controller.mafiaReady);
gamesRouter.post("/mafia/rooms/:roomId/start", controller.mafiaStart);
gamesRouter.post("/mafia/rooms/:roomId/acknowledge-role", controller.mafiaAcknowledgeRole);
gamesRouter.post("/mafia/rooms/:roomId/actions", controller.mafiaAction);
gamesRouter.post("/mafia/rooms/:roomId/advance", controller.mafiaAdvance);
gamesRouter.post("/mafia/rooms/:roomId/messages", controller.mafiaMessage);
gamesRouter.post("/mafia/rooms/:roomId/interactions", controller.mafiaInteraction);
gamesRouter.post("/mafia/rooms/:roomId/reports", controller.mafiaReport);
gamesRouter.post("/mafia/rooms/:roomId/heartbeat", controller.mafiaHeartbeat);
gamesRouter.post("/mafia/rooms/:roomId/voice-token", controller.mafiaVoiceToken);
gamesRouter.delete("/mafia/rooms/:roomId/players/:playerId", controller.mafiaKick);
gamesRouter.post("/mafia/rooms/:roomId/close", controller.mafiaClose);
gamesRouter.post("/mafia/rooms/:roomId/reactivate", controller.mafiaReactivate);
gamesRouter.post("/mafia/rooms/:roomId/leave", controller.mafiaLeave);
gamesRouter.get("/mafia/history", controller.mafiaHistory);
gamesRouter.get(
  "/admin/mafia-reports",
  requirePermission("competitions.manage"),
  controller.mafiaReports,
);
gamesRouter.patch(
  "/admin/mafia-reports/:reportId/review",
  requirePermission("competitions.manage"),
  controller.mafiaReviewReport,
);
gamesRouter.get(
  "/admin/overview",
  requirePermission("competitions.manage"),
  controller.adminOverview,
);
gamesRouter.patch(
  "/admin/campaign",
  requirePermission("competitions.manage"),
  controller.adminUpdateCampaign,
);

gamesRouter.get("/knowledge/events", controller.knowledgeEvents);
gamesRouter.post("/knowledge/duels", controller.knowledgeCreateDuel);
gamesRouter.post("/knowledge/rooms/lookup", controller.knowledgeLookupRoom);
gamesRouter.get("/knowledge/rooms/:eventId", controller.knowledgeRoom);
gamesRouter.post("/knowledge/rooms/:eventId/seats", controller.knowledgeJoinRoomSeat);
gamesRouter.post("/knowledge/rooms/:eventId/close", controller.knowledgeCloseRoom);
gamesRouter.post("/knowledge/rooms/:eventId/reactivate", controller.knowledgeReactivateRoom);
gamesRouter.post("/knowledge/teams", controller.knowledgeRegisterTeam);
gamesRouter.post("/knowledge/teams/join", controller.knowledgeJoinTeam);
gamesRouter.get("/knowledge/events/:eventId/matches", controller.knowledgeMatches);
gamesRouter.get("/knowledge/events/:eventId/bracket", controller.knowledgeBracket);
gamesRouter.post("/knowledge/events/:eventId/leave-seat", controller.knowledgeLeaveSeat);
gamesRouter.get("/knowledge/matches/:matchId", controller.knowledgeMatch);
gamesRouter.post("/knowledge/matches/:matchId/answers", controller.knowledgeAnswer);
gamesRouter.get("/knowledge/matches/:matchId/attempts/:key", controller.knowledgeAttempt);
gamesRouter.post("/knowledge/matches/:matchId/chat", controller.knowledgeChat);
gamesRouter.post("/knowledge/matches/:matchId/chat-consent", controller.knowledgeConsent);
gamesRouter.post("/knowledge/matches/:matchId/reactions", controller.knowledgeReaction);
gamesRouter.post("/knowledge/matches/:matchId/voice-token", controller.knowledgeVoiceToken);
gamesRouter.get(
  "/admin/knowledge/overview",
  requirePermission("competitions.manage"),
  controller.knowledgeAdminOverview,
);
gamesRouter.get(
  "/admin/knowledge/questions",
  requirePermission("competitions.manage"),
  controller.knowledgeAdminQuestions,
);
gamesRouter.post(
  "/admin/knowledge/questions",
  requirePermission("competitions.manage"),
  controller.knowledgeAdminCreateQuestion,
);
gamesRouter.patch(
  "/admin/knowledge/questions/:questionId",
  requirePermission("competitions.manage"),
  controller.knowledgeAdminUpdateQuestion,
);
gamesRouter.post(
  "/admin/knowledge/events",
  requirePermission("competitions.manage"),
  controller.knowledgeAdminCreate,
);
gamesRouter.post(
  "/admin/knowledge/events/:eventId/start",
  requirePermission("competitions.manage"),
  controller.knowledgeAdminStart,
);

import { Router } from "express";

import { requireAuth } from "../../shared/middleware/auth.middleware.js";
import { requireCustomer } from "../../shared/middleware/customer.middleware.js";
import * as c from "./assistant.controller.js";

export const assistantRouter = Router();

assistantRouter.use(requireAuth, requireCustomer);

assistantRouter.get("/session", c.getCurrentSession);
assistantRouter.post("/session/new", c.startNewSession);
assistantRouter.post("/chat", c.chat);
assistantRouter.post("/ai/chat", c.chat);
assistantRouter.post("/draft/:token/confirm", c.confirmDraft);
assistantRouter.get("/profile", c.getProfile);
assistantRouter.post("/profile/home", c.updateHomePreferences);
assistantRouter.post("/recommend/jobs", c.recommendJobs);
assistantRouter.post("/recommend/commerce", c.recommendCommerce);

assistantRouter.post("/ai/memory/consent", c.setAiMemoryConsent);
assistantRouter.get("/ai/profile", c.getAiUserProfile);
assistantRouter.patch("/ai/profile", c.updateAiUserProfile);

assistantRouter.get("/ai/conversations", c.listAiConversations);
assistantRouter.get("/ai/conversations/:conversationId", c.getAiConversation);

assistantRouter.get("/ai/memories", c.listAiMemories);
assistantRouter.post("/ai/memories", c.createAiMemory);
assistantRouter.delete("/ai/memories", c.clearAiMemories);
assistantRouter.patch("/ai/memories/:memoryId", c.updateAiMemory);
assistantRouter.delete("/ai/memories/:memoryId", c.deleteAiMemory);

assistantRouter.get("/ai/topics", c.listAiTopics);
assistantRouter.post("/ai/search/app", c.appSearch);
assistantRouter.post("/ai/search/web", c.webSearch);

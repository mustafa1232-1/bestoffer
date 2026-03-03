import { Router } from "express";

import { requireAuth } from "../../shared/middleware/auth.middleware.js";
import { mediaUpload } from "../../shared/utils/upload.js";
import * as c from "./feed.controller.js";

export const feedRouter = Router();

feedRouter.use(requireAuth);

feedRouter.get("/posts", c.listPosts);
feedRouter.get("/posts/:postId", c.getPostById);
feedRouter.post("/posts", mediaUpload.single("mediaFile"), c.createPost);
feedRouter.post("/posts/:postId/like", c.toggleLike);
feedRouter.get("/posts/:postId/comments", c.listPostComments);
feedRouter.post("/posts/:postId/comments", c.addComment);
feedRouter.get("/merchants", c.listMerchants);

feedRouter.get("/chats/threads", c.listThreads);
feedRouter.post("/chats/threads", c.createThread);
feedRouter.get("/chats/threads/:threadId/messages", c.listThreadMessages);
feedRouter.post("/chats/threads/:threadId/messages", c.sendThreadMessage);

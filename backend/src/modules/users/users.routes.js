import { Router } from "express";
import { requireAuth } from "../../shared/middleware/auth.middleware.js";
import { imageUpload } from "../../shared/utils/upload.js";
import * as c from "./users.controller.js";

export const usersRouter = Router();

usersRouter.use(requireAuth);

// Profile
usersRouter.get("/me", c.getMyProfile);
usersRouter.patch("/me", imageUpload.single("imageFile"), c.updateMyProfile);
usersRouter.delete("/me", c.deleteMyAccount);

// Sessions
usersRouter.get("/me/sessions", c.getMySessions);
usersRouter.delete("/me/sessions/:sessionId", c.revokeMySession);

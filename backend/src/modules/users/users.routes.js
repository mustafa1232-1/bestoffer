import { Router } from "express";
import { requireAuth } from "../../shared/middleware/auth.middleware.js";
import { imageUpload } from "../../shared/utils/upload.js";
import * as c from "./users.controller.js";

export const usersRouter = Router();
export const accountRouter = Router();

usersRouter.use(requireAuth);
accountRouter.use(requireAuth);

// Profile
usersRouter.get("/me", c.getMyProfile);
usersRouter.patch("/me", imageUpload.single("imageFile"), c.updateMyProfile);
usersRouter.delete("/me", c.deleteMyAccount);
accountRouter.delete("/", c.deleteMyAccount);

// Sessions
usersRouter.get("/me/sessions", c.getMySessions);
usersRouter.delete("/me/sessions/:sessionId", c.revokeMySession);

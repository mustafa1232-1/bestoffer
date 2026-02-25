import { Router } from "express";

import { requireAuth } from "../../shared/middleware/auth.middleware.js";
import * as c from "./notifications.controller.js";

export const notificationsRouter = Router();

notificationsRouter.use(requireAuth);

notificationsRouter.get("/", c.list);
notificationsRouter.get("/unread-count", c.unreadCount);
notificationsRouter.get("/stream", c.stream);
notificationsRouter.patch("/:notificationId/read", c.markRead);
notificationsRouter.patch("/read-all", c.markAllRead);

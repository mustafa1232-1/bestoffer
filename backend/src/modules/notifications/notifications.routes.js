import { Router } from "express";

import { requireAuth } from "../../shared/middleware/auth.middleware.js";
import * as c from "./notifications.controller.js";

/**
 * Purpose:
 * واجهة الإشعارات الموحدة: inbox، unread count، SSE stream، push token
 * registration، وتعليم الإشعارات كمقروءة.
 *
 * Used by:
 * - شاشة الإشعارات
 * - bell/unread badges
 * - مزامنة push token على Flutter
 *
 * Critical notes:
 * - هذا router محمي بالكامل بـ `requireAuth`.
 * - أي كسر هنا يظهر بسرعة على badges وrealtime وفتح الإشعارات من الواجهة.
 */
export const notificationsRouter = Router();

notificationsRouter.use(requireAuth);

// القائمة الأساسية المستخدمة في شاشة inbox مع فلاتر unread/limit.
notificationsRouter.get("/", c.list);
notificationsRouter.get("/unread-count", c.unreadCount);
// SSE stream للتحديثات الحية وقراءة الحالة اللحظية للاتصال.
notificationsRouter.get("/stream", c.stream);
notificationsRouter.get("/push-status", c.pushStatus);
notificationsRouter.post("/push-token", c.registerPushToken);
notificationsRouter.post("/actions/track", c.trackAction);
notificationsRouter.delete("/push-token", c.unregisterPushToken);
notificationsRouter.patch("/:notificationId/read", c.markRead);
notificationsRouter.patch("/read-all", c.markAllRead);

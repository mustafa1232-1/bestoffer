import * as service from "./notifications.service.js";
import {
  addUserStream,
  getLatestUserEventId,
  replayUserEvents,
  removeUserStream,
  writeSseEvent,
} from "../../shared/realtime/live-events.js";

/**
 * Purpose:
 * controllers صندوق الإشعارات والـ SSE stream الخاصة بها.
 *
 * Used by:
 * - `notifications.routes.js`
 *
 * Maintenance notes:
 * - عند مشاكل inbox أو stream handshakes ابدأ هنا ثم انزل إلى service/repo.
 */

/**
 * يعيد قائمة الإشعارات للمستخدم الحالي.
 */
export async function list(req, res, next) {
  try {
    const data = await service.listUserNotifications(req.userId, req.query);
    res.json(data);
  } catch (e) {
    next(e);
  }
}

/**
 * يعيد العداد الحالي للإشعارات غير المقروءة.
 */
export async function unreadCount(req, res, next) {
  try {
    const out = await service.unreadCount(req.userId);
    res.json(out);
  } catch (e) {
    next(e);
  }
}

/**
 * يعلّم إشعاراً واحداً كمقروء.
 */
export async function markRead(req, res, next) {
  try {
    await service.markRead(req.userId, req.params.notificationId);
    res.status(204).send();
  } catch (e) {
    next(e);
  }
}

/**
 * يعلّم كل إشعارات المستخدم كمقروءة دفعة واحدة.
 */
export async function markAllRead(req, res, next) {
  try {
    const out = await service.markAllRead(req.userId);
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function registerPushToken(req, res, next) {
  try {
    await service.registerPushToken(
      {
        userId: req.userId,
        sessionId: req.authSessionId || null,
        role: req.userRole,
        deviceContext: req.authDeviceContext || null,
      },
      req.body || {}
    );
    res.status(204).send();
  } catch (e) {
    next(e);
  }
}

export async function unregisterPushToken(req, res, next) {
  try {
    await service.unregisterPushToken(req.userId, req.body || {});
    res.status(204).send();
  } catch (e) {
    next(e);
  }
}

export async function pushStatus(req, res, next) {
  try {
    const out = await service.pushStatus(req.userId);
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function trackAction(req, res, next) {
  try {
    const out = await service.trackAction(req.userId, req.body || {});
    res.status(201).json({ item: out });
  } catch (e) {
    next(e);
  }
}

/**
 * يبدأ stream SSE للمستخدم الحالي مع replay اختياري وheartbeat دوري.
 *
 * Critical notes:
 * - هذا المسار حساس لتعدد الاتصالات والتزامن بين replay وlive events.
 */
export function stream(req, res, next) {
  try {
    res.status(200);
    res.setHeader("Content-Type", "text/event-stream; charset=utf-8");
    res.setHeader("Cache-Control", "no-cache, no-transform");
    res.setHeader("Connection", "keep-alive");
    res.setHeader("X-Accel-Buffering", "no");
    res.flushHeaders?.();

    const rawLastId = req.get("last-event-id") || req.query?.lastEventId;
    const lastEventId = Number(rawLastId || 0);
    const safeLastEventId =
      Number.isFinite(lastEventId) && lastEventId > 0
        ? Math.floor(lastEventId)
        : 0;

    const requestedChannel =
      String(req.query?.channel || "").trim().toLowerCase() === "social"
        ? "social"
        : "notifications";

    addUserStream(req.userId, res, { channel: requestedChannel });
    writeSseEvent(
      res,
      "connected",
      {
        at: new Date().toISOString(),
        channel: requestedChannel,
        lastEventId: safeLastEventId || null,
      },
      { retry: 3000 }
    );

    if (safeLastEventId > 0) {
      const replay = replayUserEvents(req.userId, res, {
        afterEventId: safeLastEventId,
        maxEvents: 1000,
        channel: requestedChannel,
      });

      if (replay.resyncRequired) {
        writeSseEvent(res, "resync_required", {
          channel: requestedChannel,
          reason: replay.reason,
          latestEventId: replay.latestEventId || null,
          oldestEventId: replay.oldestEventId || null,
        });
      } else if (replay.replayed > 0) {
        writeSseEvent(res, "replayed", {
          channel: requestedChannel,
          replayed: replay.replayed,
          lastEventId: replay.lastEventId,
        });
      }
    }

    const heartbeat = setInterval(() => {
      writeSseEvent(
        res,
        "heartbeat",
        {
          at: new Date().toISOString(),
          channel: requestedChannel,
          latestEventId: getLatestUserEventId(req.userId, {
            channel: requestedChannel,
          }),
        }
      );
    }, 20000);

    req.on("close", () => {
      clearInterval(heartbeat);
      removeUserStream(req.userId, res);
    });
  } catch (e) {
    next(e);
  }
}

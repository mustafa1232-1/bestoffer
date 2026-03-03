import * as service from "./notifications.service.js";
import {
  addUserStream,
  getLatestUserEventId,
  replayUserEvents,
  removeUserStream,
  writeSseEvent,
} from "../../shared/realtime/live-events.js";

export async function list(req, res, next) {
  try {
    const data = await service.listUserNotifications(req.userId, req.query);
    res.json(data);
  } catch (e) {
    next(e);
  }
}

export async function unreadCount(req, res, next) {
  try {
    const out = await service.unreadCount(req.userId);
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function markRead(req, res, next) {
  try {
    await service.markRead(req.userId, req.params.notificationId);
    res.status(204).send();
  } catch (e) {
    next(e);
  }
}

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
    await service.registerPushToken(req.userId, req.body || {});
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

    addUserStream(req.userId, res);
    writeSseEvent(
      res,
      "connected",
      {
        at: new Date().toISOString(),
        lastEventId: safeLastEventId || null,
      },
      { id: getLatestUserEventId(req.userId) }
    );

    if (safeLastEventId > 0) {
      const replay = replayUserEvents(req.userId, res, {
        afterEventId: safeLastEventId,
        maxEvents: 1000,
      });

      if (replay.replayed > 0) {
        writeSseEvent(res, "replayed", {
          replayed: replay.replayed,
          lastEventId: replay.lastEventId,
        });
      }
    }

    const heartbeat = setInterval(() => {
      writeSseEvent(
        res,
        "heartbeat",
        { at: new Date().toISOString() },
        { id: getLatestUserEventId(req.userId) }
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

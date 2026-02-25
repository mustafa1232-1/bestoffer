import * as service from "./notifications.service.js";
import {
  addUserStream,
  removeUserStream,
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

export function stream(req, res, next) {
  try {
    res.status(200);
    res.setHeader("Content-Type", "text/event-stream; charset=utf-8");
    res.setHeader("Cache-Control", "no-cache, no-transform");
    res.setHeader("Connection", "keep-alive");
    res.setHeader("X-Accel-Buffering", "no");
    res.flushHeaders?.();

    const writeEvent = (event, data) => {
      const payload = JSON.stringify(data || {});
      res.write(`event: ${event}\n`);
      res.write(`data: ${payload}\n\n`);
    };

    addUserStream(req.userId, res);
    writeEvent("connected", { at: new Date().toISOString() });

    const heartbeat = setInterval(() => {
      writeEvent("heartbeat", { at: new Date().toISOString() });
    }, 20000);

    req.on("close", () => {
      clearInterval(heartbeat);
      removeUserStream(req.userId, res);
    });
  } catch (e) {
    next(e);
  }
}

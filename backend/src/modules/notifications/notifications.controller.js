import * as service from "./notifications.service.js";

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

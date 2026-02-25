import * as service from "./assistant.service.js";
import {
  validateChatBody,
  validateConfirmDraft,
  validateSessionQuery,
} from "./assistant.validators.js";

export async function getCurrentSession(req, res, next) {
  try {
    const v = validateSessionQuery(req.query || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const data = await service.getCurrentConversation(req.userId, {
      sessionId:
        req.query?.sessionId == null ? null : Number(req.query.sessionId),
      limit: req.query?.limit == null ? null : Number(req.query.limit),
    });
    res.json(data);
  } catch (e) {
    next(e);
  }
}

export async function startNewSession(req, res, next) {
  try {
    const data = await service.startNewConversation(req.userId);
    res.json(data);
  } catch (e) {
    next(e);
  }
}

export async function chat(req, res, next) {
  try {
    const body = req.body || {};
    const v = validateChatBody(body);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const data = await service.chat(req.userId, {
      message: body.message,
      sessionId: body.sessionId == null ? null : Number(body.sessionId),
      addressId: body.addressId == null ? null : Number(body.addressId),
      draftToken: body.draftToken || null,
      confirmDraft: body.confirmDraft === true,
      createDraft: body.createDraft === true,
      note: body.note,
    });
    res.json(data);
  } catch (e) {
    next(e);
  }
}

export async function confirmDraft(req, res, next) {
  try {
    const v = validateConfirmDraft(req.body || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const data = await service.confirmDraft(req.userId, req.params.token, {
      sessionId: req.body?.sessionId == null ? null : Number(req.body.sessionId),
      addressId: req.body?.addressId == null ? null : Number(req.body.addressId),
      note: req.body?.note || null,
    });
    res.json(data);
  } catch (e) {
    next(e);
  }
}

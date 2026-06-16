import { buildUploadedFileUrl } from "../../shared/utils/upload.js";
import * as service from "./users.service.js";
import {
  validateDeleteMyAccount,
  validateSessionId,
  validateUpdateMyProfile,
} from "./users.validators.js";

function badRequest(res, fields) {
  return res.status(400).json({
    message: "VALIDATION_ERROR",
    fields,
  });
}

export async function getMyProfile(req, res, next) {
  try {
    const out = await service.getMyProfile(req.userId);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function updateMyProfile(req, res, next) {
  try {
    const body = {
      ...(req.body || {}),
      imageUrl: buildUploadedFileUrl(req, req.file) || req.body?.imageUrl,
    };
    const validation = validateUpdateMyProfile(body, {
      hasImageUpload: !!req.file,
    });
    if (!validation.ok) return badRequest(res, validation.errors);
    const out = await service.updateMyProfile(req.userId, validation.value);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function deleteMyAccount(req, res, next) {
  try {
    const validation = validateDeleteMyAccount(req.body || {});
    if (!validation.ok) return badRequest(res, validation.errors);
    const out = await service.deleteMyAccount(req.userId, validation.value);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function getMySessions(req, res, next) {
  try {
    const out = await service.getMySessions(req.userId, req.authSessionId || null);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function revokeMySession(req, res, next) {
  try {
    const validation = validateSessionId(req.params?.sessionId);
    if (!validation.ok) return badRequest(res, validation.errors);
    const out = await service.revokeMySession({
      userId: req.userId,
      sessionId: validation.value,
      currentSessionId: req.authSessionId || null,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

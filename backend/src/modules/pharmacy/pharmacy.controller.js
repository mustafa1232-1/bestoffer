import {
  validateAttachmentUpload,
  validateCartAction,
  validateConversationCreate,
  validateConversationListQuery,
  validateConvertToOrder,
  validateCreateProposedCart,
  validateIdParam,
  validateSendMessage,
} from "./pharmacy.validators.js";
import * as service from "./pharmacy.service.js";
import { buildUploadedFileUrl } from "../../shared/utils/upload.js";

function badRequest(res, fields) {
  return res.status(400).json({
    message: "VALIDATION_ERROR",
    fields,
  });
}

function parseMaybeJson(raw, fallback) {
  if (raw == null) return fallback;
  if (typeof raw !== "string") return raw;
  try {
    return JSON.parse(raw);
  } catch (_) {
    return fallback;
  }
}

function requestBaseUrl(req) {
  const proto = (req.headers["x-forwarded-proto"] || req.protocol || "http")
    .toString()
    .split(",")[0]
    .trim();
  const host = String(req.headers["x-forwarded-host"] || req.get("host") || "").trim();
  return `${proto}://${host}`;
}

export async function createConversation(req, res, next) {
  try {
    const body = {
      ...req.body,
      metadata: parseMaybeJson(req.body?.metadata, {}),
    };
    const v = validateConversationCreate(body);
    if (!v.ok) return badRequest(res, v.errors);
    const conversation = await service.createConversation({
      customerUserId: req.userId,
      customerRole: req.userRole,
      customerIsTaxiCaptain: req.userIsTaxiCaptain === true,
      merchantId: v.value.merchantId,
      initialMessage: v.value.initialMessage,
      metadata: v.value.metadata,
    });
    return res.status(201).json({ conversation });
  } catch (error) {
    return next(error);
  }
}

export async function listConversations(req, res, next) {
  try {
    const v = validateConversationListQuery(req.query || {});
    const items = await service.listConversations({
      actorUserId: req.userId,
      actorRole: req.userRole,
      actorIsTaxiCaptain: req.userIsTaxiCaptain === true,
      query: v.value,
    });
    return res.json({ items });
  } catch (error) {
    return next(error);
  }
}

export async function getConversationDetails(req, res, next) {
  try {
    const idV = validateIdParam(req.params?.id, "conversationId");
    if (!idV.ok) return badRequest(res, idV.errors);
    const limit = Math.max(1, Math.min(240, Number(req.query?.limit) || 120));
    const beforeId = Number(req.query?.beforeId);
    const out = await service.getConversationDetails({
      conversationId: idV.value,
      actorUserId: req.userId,
      actorRole: req.userRole,
      actorIsTaxiCaptain: req.userIsTaxiCaptain === true,
      messageLimit: limit,
      beforeId: Number.isInteger(beforeId) && beforeId > 0 ? beforeId : null,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function sendMessage(req, res, next) {
  try {
    const idV = validateIdParam(req.params?.id, "conversationId");
    if (!idV.ok) return badRequest(res, idV.errors);
    const body = {
      ...req.body,
      metadata: parseMaybeJson(req.body?.metadata, {}),
    };
    const v = validateSendMessage(body);
    if (!v.ok) return badRequest(res, v.errors);
    const item = await service.sendMessage({
      conversationId: idV.value,
      actorUserId: req.userId,
      actorRole: req.userRole,
      actorIsTaxiCaptain: req.userIsTaxiCaptain === true,
      message: v.value.message,
      metadata: v.value.metadata,
    });
    return res.status(201).json({ item });
  } catch (error) {
    return next(error);
  }
}

export async function uploadAttachment(req, res, next) {
  try {
    const idV = validateIdParam(req.params?.id, "conversationId");
    if (!idV.ok) return badRequest(res, idV.errors);
    const fileValidation = validateAttachmentUpload(req.file);
    if (!fileValidation.ok) return badRequest(res, fileValidation.errors);
    const metadata = parseMaybeJson(req.body?.metadata, {});
    const payload = {
      ...req.file,
      location: buildUploadedFileUrl(req, req.file),
    };
    const out = await service.addAttachment({
      conversationId: idV.value,
      actorUserId: req.userId,
      actorRole: req.userRole,
      actorIsTaxiCaptain: req.userIsTaxiCaptain === true,
      file: payload,
      metadata,
    });
    return res.status(201).json(out);
  } catch (error) {
    return next(error);
  }
}

export async function createProposedCart(req, res, next) {
  try {
    const idV = validateIdParam(req.params?.id, "conversationId");
    if (!idV.ok) return badRequest(res, idV.errors);
    const body = {
      ...req.body,
      items: parseMaybeJson(req.body?.items, []),
    };
    const v = validateCreateProposedCart(body);
    if (!v.ok) return badRequest(res, v.errors);
    const cart = await service.createProposedCart({
      conversationId: idV.value,
      actorUserId: req.userId,
      actorRole: req.userRole,
      items: v.value.items,
      deliveryFee: v.value.deliveryFee,
      expiresAt: v.value.expiresAt,
      notes: v.value.notes,
    });
    return res.status(201).json({ cart });
  } catch (error) {
    return next(error);
  }
}

export async function acceptProposedCart(req, res, next) {
  try {
    const idV = validateIdParam(req.params?.id, "proposedCartId");
    if (!idV.ok) return badRequest(res, idV.errors);
    const v = validateCartAction(req.body || {});
    const cart = await service.updateCartStatusByCustomer({
      cartId: idV.value,
      actorUserId: req.userId,
      actorRole: req.userRole,
      actorIsTaxiCaptain: req.userIsTaxiCaptain === true,
      action: "accept",
      note: v.value.note,
    });
    return res.json({ cart });
  } catch (error) {
    return next(error);
  }
}

export async function rejectProposedCart(req, res, next) {
  try {
    const idV = validateIdParam(req.params?.id, "proposedCartId");
    if (!idV.ok) return badRequest(res, idV.errors);
    const v = validateCartAction(req.body || {});
    const cart = await service.updateCartStatusByCustomer({
      cartId: idV.value,
      actorUserId: req.userId,
      actorRole: req.userRole,
      actorIsTaxiCaptain: req.userIsTaxiCaptain === true,
      action: "reject",
      note: v.value.note,
    });
    return res.json({ cart });
  } catch (error) {
    return next(error);
  }
}

export async function requestCartRevision(req, res, next) {
  try {
    const idV = validateIdParam(req.params?.id, "proposedCartId");
    if (!idV.ok) return badRequest(res, idV.errors);
    const v = validateCartAction(req.body || {});
    const cart = await service.updateCartStatusByCustomer({
      cartId: idV.value,
      actorUserId: req.userId,
      actorRole: req.userRole,
      actorIsTaxiCaptain: req.userIsTaxiCaptain === true,
      action: "request-revision",
      note: v.value.note,
    });
    return res.json({ cart });
  } catch (error) {
    return next(error);
  }
}

export async function convertProposedCartToOrder(req, res, next) {
  try {
    const idV = validateIdParam(req.params?.id, "proposedCartId");
    if (!idV.ok) return badRequest(res, idV.errors);
    const v = validateConvertToOrder(req.body || {});
    const out = await service.convertCartToOrder({
      cartId: idV.value,
      actorUserId: req.userId,
      actorRole: req.userRole,
      actorIsTaxiCaptain: req.userIsTaxiCaptain === true,
      note: v.value.note,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function attachmentAccessUrl(req, res, next) {
  try {
    const idV = validateIdParam(req.params?.id, "attachmentId");
    if (!idV.ok) return badRequest(res, idV.errors);
    const out = await service.buildAttachmentAccessUrl({
      attachmentId: idV.value,
      actorUserId: req.userId,
      actorRole: req.userRole,
      actorIsTaxiCaptain: req.userIsTaxiCaptain === true,
      baseUrl: requestBaseUrl(req),
      ipAddress: req.ip,
      userAgent: req.get("user-agent"),
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function attachmentContent(req, res, next) {
  try {
    const idV = validateIdParam(req.params?.id, "attachmentId");
    if (!idV.ok) return badRequest(res, idV.errors);
    const out = await service.resolveAttachmentContentByToken({
      attachmentId: idV.value,
      token: req.query?.token,
      ipAddress: req.ip,
      userAgent: req.get("user-agent"),
    });
    return res.redirect(out.fileUrl);
  } catch (error) {
    return next(error);
  }
}

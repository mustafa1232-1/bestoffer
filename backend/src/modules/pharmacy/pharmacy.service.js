import crypto from "crypto";

import { env } from "../../config/env.js";
import { AppError } from "../../shared/utils/errors.js";
import { createNotification } from "../notifications/notifications.repo.js";
import * as repo from "./pharmacy.repo.js";

const ATTACHMENT_URL_TTL_SEC = 5 * 60;

function normalizeRole(role) {
  return String(role || "").trim().toLowerCase();
}

function isCustomerRole(role, isTaxiCaptain = false) {
  const normalized = normalizeRole(role);
  if (normalized === "user") return true;
  return false;
}

function normalizeOrigin(raw) {
  const value = String(raw || "").trim();
  if (!value) return "";
  try {
    const url = new URL(value);
    return `${url.protocol}//${url.host}`;
  } catch (_) {
    return "";
  }
}

function isTrustedAttachmentFileUrl(raw) {
  const value = String(raw || "").trim();
  if (!value) return false;
  const r2Origin = normalizeOrigin(env.cfR2PublicBaseUrl);

  try {
    const url = new URL(value);
    const origin = `${url.protocol}//${url.host}`;
    if (r2Origin && origin === r2Origin) return true;
    return /^\/uploads\/[^/]+$/i.test(url.pathname || "");
  } catch (_) {
    return /^\/uploads\/[^/]+$/i.test(value);
  }
}

function computeConversationBucket(status) {
  const normalized = String(status || "").trim().toLowerCase();
  if (["completed"].includes(normalized)) return "completed";
  if (["closed_no_sale", "cancelled", "unavailable"].includes(normalized)) {
    return "closed";
  }
  return "active";
}

function signAttachmentToken({ attachmentId, userId, role, expiresAt }) {
  const normalizedRole = normalizeRole(role) || "user";
  const payload = `${Number(attachmentId)}.${Number(userId)}.${normalizedRole}.${Number(
    expiresAt
  )}`;
  const sig = crypto
    .createHmac("sha256", env.jwtSecret)
    .update(payload)
    .digest("hex");
  return `${payload}.${sig}`;
}

function parseAndVerifyAttachmentToken(token) {
  const raw = String(token || "").trim();
  if (!raw) return null;
  const parts = raw.split(".");
  if (parts.length !== 5) return null;
  const attachmentId = Number(parts[0]);
  const userId = Number(parts[1]);
  const role = normalizeRole(parts[2]);
  const expiresAt = Number(parts[3]);
  const signature = parts[4];
  if (!Number.isInteger(attachmentId) || attachmentId <= 0) return null;
  if (!Number.isInteger(userId) || userId <= 0) return null;
  if (!role) return null;
  if (!Number.isInteger(expiresAt) || expiresAt <= 0) return null;
  const expected = signAttachmentToken({ attachmentId, userId, role, expiresAt }).split(
    "."
  )[4];
  const safeEqual =
    expected.length === signature.length &&
    crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(signature));
  if (!safeEqual) return null;
  if (Date.now() > expiresAt) return null;
  return { attachmentId, userId, role, expiresAt };
}

function mapConversationRow(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    merchantId: Number(row.merchant_id),
    customerUserId: Number(row.customer_user_id),
    merchantName: row.merchant_name || null,
    merchantImageUrl: row.merchant_image_url || null,
    activityType: row.activity_type || "pharmacy",
    conversationType: row.conversation_type || "pharmacy_direct",
    status: row.status || "open",
    bucket: computeConversationBucket(row.status),
    linkedOrderId: row.linked_order_id == null ? null : Number(row.linked_order_id),
    lastMessageAt: row.last_message_at || null,
    closedReason: row.closed_reason || null,
    metadata:
      row.metadata_json && typeof row.metadata_json === "object"
        ? row.metadata_json
        : {},
    supportsChat: row.supports_chat === true,
    supportsAttachments: row.supports_attachments === true,
    supportsPharmacyWorkflow: row.supports_pharmacy_workflow === true,
    customer: {
      fullName: row.customer_full_name || null,
      phone: row.customer_phone || null,
    },
    messagesCount: Number(row.messages_count || 0),
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
  };
}

function mapMessageRow(row) {
  return {
    id: Number(row.id),
    conversationId: Number(row.conversation_id),
    senderUserId: row.sender_user_id == null ? null : Number(row.sender_user_id),
    senderType: row.sender_type || "system",
    senderFullName: row.sender_full_name || null,
    messageType: row.message_type || "text",
    text: row.text || null,
    attachmentId: row.attachment_id == null ? null : Number(row.attachment_id),
    attachmentUrl: row.attachment_url || null,
    attachmentMimeType: row.attachment_mime_type || null,
    attachmentName: row.attachment_name || null,
    proposedCartId: row.proposed_cart_id == null ? null : Number(row.proposed_cart_id),
    metadata: row.metadata_json && typeof row.metadata_json === "object" ? row.metadata_json : {},
    createdAt: row.created_at || null,
  };
}

function mapCartRow(row, items = []) {
  if (!row) return null;
  return {
    id: Number(row.id),
    conversationId: Number(row.conversation_id),
    version: Number(row.version || 0),
    status: row.status || "draft",
    subtotal: Number(row.subtotal || 0),
    deliveryFee: Number(row.delivery_fee || 0),
    total: Number(row.total || 0),
    notes: row.notes || null,
    expiresAt: row.expires_at || null,
    confirmedAt: row.confirmed_at || null,
    rejectedAt: row.rejected_at || null,
    revisionRequestedAt: row.revision_requested_at || null,
    createdByUserId: row.created_by_user_id == null ? null : Number(row.created_by_user_id),
    items: items.map((item) => ({
      id: Number(item.id),
      proposedCartId: Number(item.proposed_cart_id),
      productId: item.product_id == null ? null : Number(item.product_id),
      productName: item.product_name || "",
      quantity: Number(item.quantity || 0),
      unitPrice: Number(item.unit_price || 0),
      lineTotal: Number(item.line_total || 0),
      alternativeGroupId: item.alternative_group_id || null,
      note: item.note || null,
      requiresPrescription: item.requires_prescription === true,
      requiresReview: item.requires_review === true,
      metadata:
        item.metadata_json && typeof item.metadata_json === "object"
          ? item.metadata_json
          : {},
    })),
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
  };
}

async function ensureConversationAccess({
  conversationId,
  actorUserId,
  actorRole,
  actorIsTaxiCaptain = false,
}) {
  const conversation = await repo.findConversationById(conversationId);
  if (!conversation) {
    throw new AppError("PHARMACY_CONVERSATION_NOT_FOUND", { status: 404 });
  }
  const role = normalizeRole(actorRole);
  const hasAccess = repo.hasConversationAccess(conversation, {
    userId: actorUserId,
    role,
  });
  if (!hasAccess) {
    if (isCustomerRole(role, actorIsTaxiCaptain)) {
      throw new AppError("FORBIDDEN_CUSTOMER_ONLY", { status: 403 });
    }
    throw new AppError("FORBIDDEN", { status: 403 });
  }
  return conversation;
}

async function notifySafe(payload) {
  try {
    await createNotification(payload);
  } catch (_) {
    // Notification failures should never break pharmacy workflows.
  }
}

function queueSafeNotification(payload) {
  setImmediate(() => {
    notifySafe(payload).catch(() => {});
  });
}

export async function createConversation({
  customerUserId,
  customerRole,
  customerIsTaxiCaptain = false,
  merchantId,
  initialMessage = null,
  metadata = {},
}) {
  if (!isCustomerRole(customerRole, customerIsTaxiCaptain)) {
    throw new AppError("FORBIDDEN_CUSTOMER_ONLY", { status: 403 });
  }
  const merchant = await repo.getMerchantPharmacyConfig(merchantId);
  if (!merchant || merchant.is_approved !== true || merchant.is_disabled === true) {
    throw new AppError("MERCHANT_NOT_FOUND", { status: 404 });
  }
  if (merchant.supports_pharmacy_workflow !== true) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: { merchantId: "PHARMACY_WORKFLOW_NOT_SUPPORTED" } },
    });
  }

  const conversation = await repo.createConversation({
    merchantId: Number(merchantId),
    customerUserId: Number(customerUserId),
    metadata,
  });
  await repo.appendConversationEvent({
    conversationId: conversation.id,
    actorUserId: customerUserId,
    eventType: "conversation_created",
    fromStatus: null,
    toStatus: "open",
  });

  if (initialMessage) {
    await repo.appendConversationMessage({
      conversationId: conversation.id,
      senderUserId: customerUserId,
      senderType: "customer",
      messageType: "text",
      text: initialMessage,
    });
    await repo.updateConversationStatus(conversation.id, "awaiting_pharmacy");
  }

  queueSafeNotification({
    userId: Number(merchant.owner_user_id),
    type: "pharmacy.conversation.new",
    title: "محادثة صيدلية جديدة",
    body: "لديك محادثة جديدة من أحد العملاء.",
    merchantId: Number(merchant.id),
    payload: {
      target: "pharmacy_conversation",
      conversationId: Number(conversation.id),
      merchantId: Number(merchant.id),
    },
  });

  return mapConversationRow({
    ...conversation,
    owner_user_id: merchant.owner_user_id,
    merchant_name: merchant.name || null,
    merchant_image_url: merchant.image_url || null,
    activity_type: merchant.activity_type || "pharmacy",
    supports_attachments: merchant.supports_attachments === true,
    supports_chat: merchant.supports_chat === true,
    supports_pharmacy_workflow: merchant.supports_pharmacy_workflow === true,
    customer_full_name: null,
    customer_phone: null,
    messages_count: initialMessage ? 1 : 0,
    status: initialMessage ? "awaiting_pharmacy" : conversation.status,
  });
}

export async function listConversations({
  actorUserId,
  actorRole,
  actorIsTaxiCaptain = false,
  query,
}) {
  const role = normalizeRole(actorRole);
  if (isCustomerRole(role, actorIsTaxiCaptain)) {
    const rows = await repo.listCustomerConversations({
      customerUserId: actorUserId,
      status: query.status,
      q: query.q,
      limit: query.limit,
    });
    return rows.map(mapConversationRow);
  }
  if (role === "owner") {
    const statusBucket = query.bucket;
    let statuses = null;
    if (statusBucket === "active") {
      statuses = [
        "open",
        "awaiting_customer",
        "awaiting_pharmacy",
        "cart_proposed",
        "cart_revision_requested",
        "order_created",
        "in_preparation",
        "out_for_delivery",
      ];
    } else if (statusBucket === "completed") {
      statuses = ["completed"];
    } else if (statusBucket === "closed") {
      statuses = ["closed_no_sale", "cancelled", "unavailable"];
    }
    const rows = await repo.listOwnerConversations({
      ownerUserId: actorUserId,
      status: query.status,
      statuses,
      q: query.q,
      limit: query.limit,
    });
    return rows.map(mapConversationRow);
  }
  throw new AppError("FORBIDDEN", { status: 403 });
}

export async function getConversationDetails({
  conversationId,
  actorUserId,
  actorRole,
  actorIsTaxiCaptain = false,
  messageLimit = 120,
  beforeId = null,
}) {
  const conversation = await ensureConversationAccess({
    conversationId,
    actorUserId,
    actorRole,
    actorIsTaxiCaptain,
  });
  const [messages, latestCart] = await Promise.all([
    repo.listConversationMessages(conversationId, {
      limit: messageLimit,
      beforeId,
    }),
    repo.getLatestConversationCart(conversationId),
  ]);
  let cart = null;
  if (latestCart) {
    const cartItems = await repo.listProposedCartItems(latestCart.id);
    cart = mapCartRow(latestCart, cartItems);
  }
  return {
    conversation: mapConversationRow(conversation),
    messages: messages.map(mapMessageRow),
    latestProposedCart: cart,
  };
}

export async function sendMessage({
  conversationId,
  actorUserId,
  actorRole,
  actorIsTaxiCaptain = false,
  message,
  metadata = {},
}) {
  const conversation = await ensureConversationAccess({
    conversationId,
    actorUserId,
    actorRole,
    actorIsTaxiCaptain,
  });
  const role = normalizeRole(actorRole);
  const senderType = role === "owner" ? "pharmacy" : "customer";
  const inserted = await repo.appendConversationMessage({
    conversationId,
    senderUserId: actorUserId,
    senderType,
    messageType: "text",
    text: message,
    metadata,
  });
  const nextStatus = role === "owner" ? "awaiting_customer" : "awaiting_pharmacy";
  const updated = await repo.updateConversationStatus(conversationId, nextStatus);
  await repo.appendConversationEvent({
    conversationId,
    actorUserId,
    eventType: "message_sent",
    fromStatus: conversation.status,
    toStatus: updated?.status || nextStatus,
    metadata: { senderType },
  });

  const targetUserId =
    role === "owner" ? Number(conversation.customer_user_id) : Number(conversation.owner_user_id);
  queueSafeNotification({
    userId: targetUserId,
    type: role === "owner" ? "pharmacy.message.store" : "pharmacy.message.customer",
    title: role === "owner" ? "رسالة جديدة من الصيدلية" : "رسالة جديدة من العميل",
    body: "تم استلام رسالة جديدة في محادثة الصيدلية.",
    merchantId: Number(conversation.merchant_id),
    payload: {
      target: "pharmacy_conversation",
      conversationId: Number(conversationId),
      merchantId: Number(conversation.merchant_id),
    },
  });

  return mapMessageRow(inserted);
}

export async function addAttachment({
  conversationId,
  actorUserId,
  actorRole,
  actorIsTaxiCaptain = false,
  file,
  metadata = {},
}) {
  const conversation = await ensureConversationAccess({
    conversationId,
    actorUserId,
    actorRole,
    actorIsTaxiCaptain,
  });
  const role = normalizeRole(actorRole);
  const senderType = role === "owner" ? "pharmacy" : "customer";
  const attachment = await repo.createAttachment({
    conversationId,
    uploaderUserId: actorUserId,
    fileUrl: file.location || file.path || null,
    storageKey: file.r2Key || file.key || null,
    mimeType: file.mimetype || null,
    fileSizeBytes: file.size || null,
    originalFileName: file.originalname || null,
    isSensitive: true,
    retentionExpiresAt: null,
    metadata,
  });
  const inserted = await repo.appendConversationMessage({
    conversationId,
    senderUserId: actorUserId,
    senderType,
    messageType: "file",
    text: null,
    attachmentId: attachment.id,
    metadata: { mimeType: file.mimetype || null },
  });
  const nextStatus = role === "owner" ? "awaiting_customer" : "awaiting_pharmacy";
  await repo.updateConversationStatus(conversationId, nextStatus);

  const targetUserId =
    role === "owner" ? Number(conversation.customer_user_id) : Number(conversation.owner_user_id);
  queueSafeNotification({
    userId: targetUserId,
    type: role === "owner" ? "pharmacy.attachment.store" : "pharmacy.attachment.customer",
    title: role === "owner" ? "مرفق جديد من الصيدلية" : "مرفق جديد من العميل",
    body: "تمت إضافة مرفق جديد في المحادثة.",
    merchantId: Number(conversation.merchant_id),
    payload: {
      target: "pharmacy_conversation",
      conversationId: Number(conversationId),
      merchantId: Number(conversation.merchant_id),
      attachmentId: Number(attachment.id),
    },
  });

  return {
    attachmentId: Number(attachment.id),
    message: mapMessageRow({
      ...inserted,
      attachment_url: attachment.file_url,
      attachment_mime_type: attachment.attachment_mime_type,
      attachment_name: attachment.original_file_name,
    }),
  };
}

export async function createProposedCart({
  conversationId,
  actorUserId,
  actorRole,
  items,
  deliveryFee,
  expiresAt = null,
  notes = null,
}) {
  if (normalizeRole(actorRole) !== "owner") {
    throw new AppError("FORBIDDEN_OWNER_ONLY", { status: 403 });
  }
  const conversation = await ensureConversationAccess({
    conversationId,
    actorUserId,
    actorRole,
  });
  const cart = await repo.createProposedCartWithItems({
    conversationId,
    createdByUserId: actorUserId,
    items,
    deliveryFee,
    notes,
    expiresAt,
  });
  const cartItems = await repo.listProposedCartItems(cart.id);
  await repo.appendConversationMessage({
    conversationId,
    senderUserId: actorUserId,
    senderType: "pharmacy",
    messageType: "cart",
    proposedCartId: cart.id,
    text: null,
    metadata: { version: Number(cart.version) },
  });
  await repo.appendConversationEvent({
    conversationId,
    actorUserId,
    eventType: "cart_proposed",
    fromStatus: conversation.status,
    toStatus: "cart_proposed",
    metadata: { cartId: Number(cart.id), version: Number(cart.version) },
  });
  queueSafeNotification({
    userId: Number(conversation.customer_user_id),
    type: "pharmacy.cart.proposed",
    title: "تم إنشاء سلة صيدلية",
    body: "لديك سلة جديدة بانتظار الموافقة.",
    merchantId: Number(conversation.merchant_id),
    payload: {
      target: "pharmacy_conversation",
      conversationId: Number(conversationId),
      cartId: Number(cart.id),
    },
  });
  return mapCartRow(cart, cartItems);
}

export async function updateCartStatusByCustomer({
  cartId,
  actorUserId,
  actorRole,
  actorIsTaxiCaptain = false,
  action,
  note = null,
}) {
  if (!isCustomerRole(actorRole, actorIsTaxiCaptain)) {
    throw new AppError("FORBIDDEN_CUSTOMER_ONLY", { status: 403 });
  }
  const cart = await repo.getProposedCartById(cartId);
  if (!cart) throw new AppError("PHARMACY_PROPOSED_CART_NOT_FOUND", { status: 404 });
  if (Number(cart.customer_user_id) !== Number(actorUserId)) {
    throw new AppError("FORBIDDEN", { status: 403 });
  }

  const current = String(cart.status || "").toLowerCase();
  if (!["proposed", "revision_requested", "accepted"].includes(current)) {
    throw new AppError("PHARMACY_PROPOSED_CART_INVALID_STATE", {
      status: 409,
      details: { fields: { _form: "INVALID_STATE" } },
    });
  }

  let nextStatus = current;
  let nextConversationStatus = "awaiting_pharmacy";
  let eventType = "cart_status_updated";
  const timestamps = {};
  if (action === "accept") {
    nextStatus = "accepted";
    nextConversationStatus = "order_created";
    eventType = "cart_accepted";
    timestamps.confirmed_at = new Date().toISOString();
  } else if (action === "reject") {
    nextStatus = "rejected";
    nextConversationStatus = "closed_no_sale";
    eventType = "cart_rejected";
    timestamps.rejected_at = new Date().toISOString();
  } else if (action === "request-revision") {
    nextStatus = "revision_requested";
    nextConversationStatus = "cart_revision_requested";
    eventType = "cart_revision_requested";
    timestamps.revision_requested_at = new Date().toISOString();
  }

  const updatedCart = await repo.updateProposedCartStatus(cartId, nextStatus, timestamps);
  await repo.updateConversationStatus(cart.conversation_id, nextConversationStatus);
  await repo.appendConversationEvent({
    conversationId: cart.conversation_id,
    actorUserId,
    eventType,
    fromStatus: cart.status,
    toStatus: nextConversationStatus,
    metadata: { cartId: Number(cartId), note },
  });
  await repo.appendConversationMessage({
    conversationId: cart.conversation_id,
    senderUserId: actorUserId,
    senderType: "customer",
    messageType: "system",
    text:
      action === "accept"
        ? "تمت الموافقة على السلة."
        : action === "reject"
        ? "تم رفض السلة."
        : "تم طلب تعديل السلة.",
    metadata: { action, note: note || null, cartId: Number(cartId) },
  });

  queueSafeNotification({
    userId: Number(cart.owner_user_id),
    type: `pharmacy.cart.${action}`,
    title:
      action === "accept"
        ? "وافق العميل على السلة"
        : action === "reject"
        ? "رفض العميل السلة"
        : "طلب العميل تعديل السلة",
    body: "تم تحديث حالة السلة من جهة العميل.",
    merchantId: Number(cart.merchant_id),
    payload: {
      target: "pharmacy_conversation",
      conversationId: Number(cart.conversation_id),
      cartId: Number(cartId),
      action,
    },
  });

  const items = await repo.listProposedCartItems(updatedCart.id);
  return mapCartRow(updatedCart, items);
}

export async function convertCartToOrder({
  cartId,
  actorUserId,
  actorRole,
  actorIsTaxiCaptain = false,
  note = null,
}) {
  const cart = await repo.getProposedCartById(cartId);
  if (!cart) throw new AppError("PHARMACY_PROPOSED_CART_NOT_FOUND", { status: 404 });
  const role = normalizeRole(actorRole);
  const allowed =
    role === "owner"
      ? Number(cart.owner_user_id) === Number(actorUserId)
      : isCustomerRole(role, actorIsTaxiCaptain) &&
        Number(cart.customer_user_id) === Number(actorUserId);
  if (!allowed) throw new AppError("FORBIDDEN", { status: 403 });

  const out = await repo.convertAcceptedCartToOrder({ cartId, note });
  if (out.code === "CART_NOT_FOUND") {
    throw new AppError("PHARMACY_PROPOSED_CART_NOT_FOUND", { status: 404 });
  }
  if (out.code === "CART_NOT_ACCEPTED") {
    throw new AppError("PHARMACY_PROPOSED_CART_NOT_ACCEPTED", {
      status: 409,
      details: { fields: { _form: "CART_NOT_ACCEPTED" } },
    });
  }
  const orderId = Number(out.order?.id || 0);
  queueSafeNotification({
    userId: Number(cart.customer_user_id),
    type: "pharmacy.order.created",
    title: "تم إنشاء طلب الصيدلية",
    body: `تم تحويل السلة إلى طلب #${orderId}.`,
    merchantId: Number(cart.merchant_id),
    orderId,
    payload: {
      target: "order_details",
      orderId,
      sourceType: "pharmacy_chat_cart",
      conversationId: Number(cart.conversation_id),
    },
  });
  queueSafeNotification({
    userId: Number(cart.owner_user_id),
    type: "pharmacy.order.created.store",
    title: "تم إنشاء طلب من المحادثة",
    body: `تم إنشاء طلب جديد #${orderId} من سلة الصيدلية.`,
    merchantId: Number(cart.merchant_id),
    orderId,
    payload: {
      target: "owner_order_details",
      orderId,
      sourceType: "pharmacy_chat_cart",
      conversationId: Number(cart.conversation_id),
    },
  });
  return { orderId };
}

export async function buildAttachmentAccessUrl({
  attachmentId,
  actorUserId,
  actorRole,
  actorIsTaxiCaptain = false,
  baseUrl,
  ipAddress = null,
  userAgent = null,
}) {
  const attachment = await repo.findAttachmentById(attachmentId);
  if (!attachment) {
    await repo.appendAttachmentAccessAudit({
      attachmentId,
      actorUserId,
      actorRole,
      action: "request_url",
      accessGranted: false,
      ipAddress,
      userAgent,
    }).catch(() => {});
    throw new AppError("PHARMACY_ATTACHMENT_NOT_FOUND", { status: 404 });
  }

  const hasAccess = repo.hasConversationAccess(attachment, {
    userId: actorUserId,
    role: normalizeRole(actorRole),
  });
  if (!hasAccess) {
    await repo.appendAttachmentAccessAudit({
      attachmentId,
      actorUserId,
      actorRole,
      action: "request_url",
      accessGranted: false,
      ipAddress,
      userAgent,
    }).catch(() => {});
    throw new AppError("FORBIDDEN", { status: 403 });
  }

  await repo.appendAttachmentAccessAudit({
    attachmentId,
    actorUserId,
    actorRole,
    action: "request_url",
    accessGranted: true,
    ipAddress,
    userAgent,
  });

  const expiresAt = Date.now() + ATTACHMENT_URL_TTL_SEC * 1000;
  const token = signAttachmentToken({
    attachmentId: Number(attachmentId),
    userId: Number(actorUserId),
    role: actorRole,
    expiresAt,
  });
  const safeBase = String(baseUrl || "").replace(/\/+$/, "");
  return {
    url: `${safeBase}/api/pharmacy/attachments/${Number(
      attachmentId
    )}/content?token=${encodeURIComponent(token)}`,
    expiresAt: new Date(expiresAt).toISOString(),
  };
}

export async function resolveAttachmentContentByToken({
  attachmentId,
  token,
  ipAddress = null,
  userAgent = null,
}) {
  const parsed = parseAndVerifyAttachmentToken(token);
  if (!parsed || Number(parsed.attachmentId) !== Number(attachmentId)) {
    throw new AppError("INVALID_OR_EXPIRED_ATTACHMENT_TOKEN", { status: 401 });
  }
  const attachment = await repo.findAttachmentById(attachmentId);
  if (!attachment) {
    throw new AppError("PHARMACY_ATTACHMENT_NOT_FOUND", { status: 404 });
  }
  const hasAccess = repo.hasConversationAccess(attachment, {
    userId: parsed.userId,
    role: parsed.role,
  });
  if (!hasAccess) {
    throw new AppError("FORBIDDEN", { status: 403 });
  }
  await repo.appendAttachmentAccessAudit({
    attachmentId,
    actorUserId: parsed.userId,
    actorRole: "signed_url",
    action: "download",
    accessGranted: true,
    ipAddress,
    userAgent,
  });
  if (!isTrustedAttachmentFileUrl(attachment.file_url)) {
    await repo.appendAttachmentAccessAudit({
      attachmentId,
      actorUserId: parsed.userId,
      actorRole: "signed_url",
      action: "download_rejected",
      accessGranted: false,
      ipAddress,
      userAgent,
    }).catch(() => {});
    throw new AppError("PHARMACY_ATTACHMENT_UNTRUSTED_URL", { status: 409 });
  }
  return {
    fileUrl: attachment.file_url,
  };
}

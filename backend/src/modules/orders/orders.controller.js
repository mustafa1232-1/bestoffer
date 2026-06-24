import * as service from "./orders.service.js";
import * as commerceService from "../commerce/commerce.service.js";
import { writeSseEvent } from "../../shared/realtime/live-events.js";
import {
  validateCreateOrder,
  validatePreviewOrder,
  validateRating,
  validateReorder,
  validateOrderActionReason,
} from "./orders.validators.js";
import { buildUploadedFileUrl } from "../../shared/utils/upload.js";

/**
 * Purpose:
 * controllers الطلبات من منظور العميل: create/list/confirm/rate/reorder
 * وبعض endpoints المساندة للشات والمراجعات.
 *
 * Used by:
 * - `orders.routes.js`
 *
 * Maintenance notes:
 * - عند mismatch بين response shape والواجهة ابدأ هنا قبل service.
 */

/**
 * يطبع body إنشاء الطلب، ويفك JSON للعناصر عند قدومها من multipart.
 */
function normalizeCreateBody(req) {
  const body = { ...req.body };

  if (typeof body.items === "string") {
    try {
      body.items = JSON.parse(body.items);
    } catch (_) {
      body.items = [];
    }
  }

  if (typeof body.storeOrders === "string") {
    try {
      body.storeOrders = JSON.parse(body.storeOrders);
    } catch (_) {
      body.storeOrders = [];
    }
  }

  body.imageUrl = buildUploadedFileUrl(req, req.file) || body.imageUrl;

  return body;
}

function validatePublicTrackToken(rawToken) {
  const value = String(rawToken || "").trim();
  if (value.length < 8 || value.length > 200) {
    return { ok: false, errors: ["token"] };
  }
  return { ok: true, value };
}

export async function preview(req, res, next) {
  try {
    const body = normalizeCreateBody(req);
    const v = validatePreviewOrder(body);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const out = await service.previewOrder(req.userId, body);
    res.json(out);
  } catch (e) {
    next(e);
  }
}

/**
 * ينشئ طلباً جديداً بعد validation وربط الصورة المرفوعة إن وجدت.
 */
export async function create(req, res, next) {
  try {
    const body = normalizeCreateBody(req);
    const v = validateCreateOrder(body);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const order = await service.createOrder(req.userId, body);
    res.status(201).json(order);
  } catch (e) {
    next(e);
  }
}

/**
 * يعيد قائمة طلبات المستخدم الحالي.
 */
export async function listMyOrders(req, res, next) {
  try {
    const hasLimit = req.query?.limit !== undefined;
    const hasOffset = req.query?.offset !== undefined;
    const limitRaw = Number(req.query?.limit);
    const offsetRaw = Number(req.query?.offset);
    const limit =
      hasLimit && Number.isFinite(limitRaw)
        ? Math.max(1, Math.min(120, Math.trunc(limitRaw)))
        : null;
    const offset =
      hasOffset && Number.isFinite(offsetRaw)
        ? Math.max(0, Math.min(1_000_000, Math.trunc(offsetRaw)))
        : 0;
    const options = {
      paginate: hasLimit || hasOffset,
      limit,
      offset,
    };
    const data = await service.listMyOrders(req.userId, options);
    res.json(data);
  } catch (e) {
    next(e);
  }
}

export async function getTrackingSnapshot(req, res, next) {
  try {
    const out = await service.getOrderTrackingSnapshotForViewer({
      viewerUserId: req.userId,
      viewerRole: req.userRole,
      isSuperAdmin: req.userIsSuperAdmin === true,
      orderId: req.params.orderId,
    });
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function createShareToken(req, res, next) {
  try {
    const out = await service.createOrderShareToken(req.userId, req.params.orderId);
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function publicTrack(req, res, next) {
  try {
    const v = validatePublicTrackToken(req.params.token);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await service.getPublicOrderTracking(v.value);
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function publicTrackStream(req, res, next) {
  try {
    const v = validatePublicTrackToken(req.params.token);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    res.status(200);
    res.setHeader("Content-Type", "text/event-stream; charset=utf-8");
    res.setHeader("Cache-Control", "no-cache, no-transform");
    res.setHeader("Connection", "keep-alive");
    res.setHeader("X-Accel-Buffering", "no");
    res.flushHeaders?.();

    const token = v.value;
    let lastSerialized = "";

    const pushSnapshot = async () => {
      const snapshot = await service.getPublicOrderTracking(token);
      const serialized = JSON.stringify(snapshot || null);
      if (!snapshot) {
        writeSseEvent(res, "closed", {
          module: "orders",
          reason: "TRACKING_NOT_FOUND",
          token,
        });
        return false;
      }
      if (serialized !== lastSerialized) {
        lastSerialized = serialized;
        writeSseEvent(res, "order_tracking_update", snapshot);
      }
      return true;
    };

    const initialOk = await pushSnapshot();
    if (!initialOk) {
      res.end();
      return;
    }

    const heartbeat = setInterval(() => {
      writeSseEvent(res, "heartbeat", {
        at: new Date().toISOString(),
        module: "orders",
        token,
      });
    }, 20000);

    const poller = setInterval(async () => {
      try {
        const keepOpen = await pushSnapshot();
        if (!keepOpen) {
          clearInterval(heartbeat);
          clearInterval(poller);
          res.end();
        }
      } catch (_) {
        writeSseEvent(res, "resync_required", {
          module: "orders",
          token,
        });
      }
    }, 3000);

    req.on("close", () => {
      clearInterval(heartbeat);
      clearInterval(poller);
    });
  } catch (e) {
    next(e);
  }
}

export async function getOrderGroupDetails(req, res, next) {
  try {
    const out = await service.getOrderGroupDetails(req.userId, req.params.groupId);
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function listActionReasons(req, res, next) {
  try {
    const out = await service.listOrderActionReasons({
      actorScope: req.query?.actorScope ?? null,
      actionKind: req.query?.actionKind ?? null,
    });
    res.json({ items: out });
  } catch (e) {
    next(e);
  }
}

export async function cancelByCustomer(req, res, next) {
  try {
    const v = validateOrderActionReason(req.body || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await service.cancelOrderByCustomer(req.userId, req.params.orderId, {
      reasonCode: req.body.reasonCode,
      reasonText: req.body.reasonText,
    });
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function requestReturnByCustomer(req, res, next) {
  try {
    const v = validateOrderActionReason(req.body || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await service.requestReturnByCustomer(req.userId, req.params.orderId, {
      reasonCode: req.body.reasonCode,
      reasonText: req.body.reasonText,
    });
    res.json(out);
  } catch (e) {
    next(e);
  }
}

/**
 * يؤكد استلام الطلب من العميل.
 */
export async function confirmDelivered(req, res, next) {
  try {
    await service.confirmDelivered(req.userId, req.params.orderId);
    res.status(204).send();
  } catch (e) {
    next(e);
  }
}

export async function rateDelivery(req, res, next) {
  try {
    const v = validateRating(req.body);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    await service.rateDelivery(
      req.userId,
      req.params.orderId,
      req.body.rating,
      req.body.review
    );

    res.status(204).send();
  } catch (e) {
    next(e);
  }
}

export async function rateMerchant(req, res, next) {
  try {
    const v = validateRating(req.body);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    await service.rateMerchant(
      req.userId,
      req.params.orderId,
      req.body.rating,
      req.body.review
    );

    res.status(204).send();
  } catch (e) {
    next(e);
  }
}

export async function listFavoriteProductIds(req, res, next) {
  try {
    const ids = await service.listFavoriteProductIds(req.userId);
    res.json({ productIds: ids });
  } catch (e) {
    next(e);
  }
}

export async function listFavoriteProducts(req, res, next) {
  try {
    const merchantId =
      req.query?.merchantId == null ? null : Number(req.query.merchantId);
    const limitRaw = Number(req.query?.limit);
    const offsetRaw = Number(req.query?.offset);
    const limit = Number.isInteger(limitRaw)
      ? Math.max(1, Math.min(120, limitRaw))
      : 40;
    const offset = Number.isInteger(offsetRaw)
      ? Math.max(0, Math.min(100000, offsetRaw))
      : 0;

    const data = await service.listFavoriteProducts(req.userId, {
      merchantId: merchantId && merchantId > 0 ? merchantId : null,
      limit,
      offset,
    });
    res.json(data);
  } catch (e) {
    next(e);
  }
}

export async function addFavoriteProduct(req, res, next) {
  try {
    await service.addFavoriteProduct(req.userId, req.params.productId);
    res.status(204).send();
  } catch (e) {
    next(e);
  }
}

export async function removeFavoriteProduct(req, res, next) {
  try {
    await service.removeFavoriteProduct(req.userId, req.params.productId);
    res.status(204).send();
  } catch (e) {
    next(e);
  }
}

/**
 * يعيد استخدام طلب سابق لإنشاء طلب جديد.
 */
export async function reorder(req, res, next) {
  try {
    const v = validateReorder(req.body || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const order = await service.reorderOrder(
      req.userId,
      req.params.orderId,
      req.body?.note
    );
    res.status(201).json(order);
  } catch (e) {
    next(e);
  }
}

export async function confirmReceivedV2(req, res, next) {
  try {
    const out = await commerceService.customerConfirmReceived(
      req.userId,
      req.params.orderId
    );
    res.json(out);
  } catch (e) {
    next(e);
  }
}

/**
 * يعيد رسائل شات الطلب مع pagination بسيطة عبر beforeId.
 */
export async function listOrderChatMessages(req, res, next) {
  try {
    const limit = Math.max(1, Math.min(400, Number(req.query?.limit) || 120));
    const beforeRaw = Number(req.query?.beforeId);
    const beforeId = Number.isInteger(beforeRaw) && beforeRaw > 0 ? beforeRaw : null;
    const out = await commerceService.listOrderChatMessages({
      userId: req.userId,
      userRole: req.userRole,
      orderId: req.params.orderId,
      limit,
      beforeId,
    });
    res.json(out);
  } catch (e) {
    next(e);
  }
}

/**
 * يرسل رسالة داخل شات الطلب بعد التحقق من عدم فراغ النص.
 */
export async function sendOrderChatMessage(req, res, next) {
  try {
    const message = `${req.body?.message ?? ""}`.trim();
    if (!message) {
      return res.status(400).json({
        message: "VALIDATION_ERROR",
        fields: { message: "MESSAGE_REQUIRED" },
      });
    }

    const out = await commerceService.sendOrderChatMessage({
      userId: req.userId,
      userRole: req.userRole,
      orderId: req.params.orderId,
      message,
    });
    res.status(201).json(out);
  } catch (e) {
    next(e);
  }
}

// ─── Product reviews ──────────────────────────────────────────────────────────

export async function submitProductReview(req, res, next) {
  try {
    const { rating, body, orderId } = req.body || {};
    const out = await service.submitProductReview(
      req.userId,
      req.params.productId,
      { rating, body, orderId }
    );
    res.status(201).json(out);
  } catch (e) {
    next(e);
  }
}

export async function listProductReviews(req, res, next) {
  try {
    const limit = Math.max(1, Math.min(100, Number(req.query?.limit) || 20));
    const offset = Math.max(0, Number(req.query?.offset) || 0);
    const out = await service.listProductReviews(req.params.productId, { limit, offset });
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function deleteProductReview(req, res, next) {
  try {
    const out = await service.deleteProductReview(req.userId, req.params.productId);
    res.json(out);
  } catch (e) {
    next(e);
  }
}

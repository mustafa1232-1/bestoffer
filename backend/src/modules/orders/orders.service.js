import { getUserPublicById } from "../auth/auth.repo.js";
import { resolveOrderAddress } from "../auth/auth.service.js";
import * as repo from "./orders.repo.js";
import {
  getOrderActionReason,
  listOrderActionReasons as listOrderActionReasonsRepo,
  normalizeOrderActionKind,
  normalizeOrderActionScope,
} from "./order-action-reasons.repo.js";

const ORDER_LIST_CACHE_TTL_MS = 10000;
const orderListCache = new Map();

function buildOrderListCacheKey(customerUserId, { paginate = false, limit = null, offset = 0 } = {}) {
  return [
    Number(customerUserId),
    paginate === true ? "1" : "0",
    limit == null ? "null" : Number(limit),
    Number(offset || 0),
  ].join(":");
}

function readOrderListCache(key) {
  const cached = orderListCache.get(key);
  if (!cached) return null;
  if (cached.expiresAt <= Date.now()) {
    orderListCache.delete(key);
    return null;
  }
  return cached.value;
}

function writeOrderListCache(key, value) {
  orderListCache.set(key, {
    value,
    expiresAt: Date.now() + ORDER_LIST_CACHE_TTL_MS,
  });
  return value;
}

export function invalidateOrderListCacheForUser(customerUserId) {
  const prefix = `${Number(customerUserId)}:`;
  for (const key of orderListCache.keys()) {
    if (key.startsWith(prefix)) {
      orderListCache.delete(key);
    }
  }
}

/**
 * Purpose:
 * طبقة الخدمة الخاصة بالطلبات من منظور العميل. تجمع التحقق من أهلية
 * المستخدم والعنوان وتطبيع العناصر قبل تسليم التنفيذ الثقيل إلى repository.
 *
 * Used by:
 * - `orders.controller.js`
 * - تدفقات الطلبات وإعادة الطلب والتقييم والمفضلة
 *
 * Critical notes:
 * - هذا الملف لا ينفذ SQL مباشرة، لكنه يحدد شروط الدخول الصحيحة إلى
 *   `orders.repo.js` حيث تتم transaction الحقيقية.
 */

// ─── Product reviews ──────────────────────────────────────────────────────────

export async function submitProductReview(customerId, productId, { rating, body, orderId }) {
  const r = Number(rating);
  if (!Number.isInteger(r) || r < 1 || r > 5) {
    const err = new Error("INVALID_RATING");
    err.status = 400;
    throw err;
  }
  const eligibleOrder = await repo.findEligibleOrderForProductReview(
    customerId,
    Number(productId),
    {
      orderId: orderId ? Number(orderId) : null,
    }
  );
  if (!eligibleOrder?.order_id) {
    const err = new Error("PRODUCT_REVIEW_ORDER_REQUIRED");
    err.status = 403;
    throw err;
  }
  const review = await repo.upsertProductReview(customerId, Number(productId), {
    rating: r,
    body: body?.trim() || null,
    orderId: Number(eligibleOrder.order_id),
  });
  return { review };
}

export async function listProductReviews(productId, { limit = 20, offset = 0 } = {}) {
  const [reviews, summary] = await Promise.all([
    repo.listProductReviews(Number(productId), { limit: Number(limit), offset: Number(offset) }),
    repo.getProductRatingSummary(Number(productId)),
  ]);
  return { reviews, summary };
}

export async function deleteProductReview(customerId, productId) {
  await repo.deleteProductReview(customerId, Number(productId));
  return { ok: true };
}

// ─── End product reviews ──────────────────────────────────────────────────────


/**
 * يدمج العناصر المكررة في السلة في صف واحد لكل productId قبل إرسالها للـ repo.
 *
 * السبب:
 * - تقليل تضارب الخصومات والمخزون عند وجود نفس المنتج أكثر من مرة في الطلب.
 */
/**
 * يدمج العناصر المكررة في السلة في صف واحد لكل `productId` قبل إرسالها
 * إلى repo.
 *
 * السبب:
 * - تقليل تضارب الخصومات والمخزون عند وجود نفس المنتج أكثر من مرة.
 */
function normalizeItems(items) {
  const map = new Map();
  for (const raw of items) {
    const productId = Number(raw.productId);
    const quantity = Number(raw.quantity);
    const selectedModifiers = Array.isArray(raw.selectedModifiers)
      ? raw.selectedModifiers
      : [];
    const modifiersKey = JSON.stringify(selectedModifiers);
    const key = `${productId}:${modifiersKey}`;
    const prev = map.get(key) || {
      productId,
      quantity: 0,
      selectedModifiers,
    };
    prev.quantity += quantity;
    map.set(key, prev);
  }
  return Array.from(map.values());
}

function normalizeStoreOrders(dto) {
  const storeOrders = Array.isArray(dto?.storeOrders)
    ? dto.storeOrders
    : null;
  if (!storeOrders) return null;
  return storeOrders.map((storeOrder) => ({
    merchantId: Number(storeOrder.merchantId),
    note:
      typeof storeOrder.note === "string" && storeOrder.note.trim()
        ? storeOrder.note.trim()
        : null,
    imageUrl:
      typeof storeOrder.imageUrl === "string" && storeOrder.imageUrl.trim()
        ? storeOrder.imageUrl.trim()
        : null,
    couponId:
      storeOrder.couponId == null || storeOrder.couponId === ""
        ? null
        : Number(storeOrder.couponId),
    couponCode:
      typeof storeOrder.couponCode === "string" && storeOrder.couponCode.trim()
        ? storeOrder.couponCode.trim().toUpperCase()
        : null,
    normalizedItems: normalizeItems(storeOrder.items || []),
  }));
}

async function resolveCheckoutContext(customerUserId, dto) {
  const customer = await getUserPublicById(customerUserId);
  if (!customer) {
    const err = new Error("CUSTOMER_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  const deliveryAddress = await resolveOrderAddress(
    customerUserId,
    dto.addressId == null ? null : Number(dto.addressId)
  );
  return { customer, deliveryAddress };
}

/**
 * ينشئ طلب عميل جديد بعد حل هوية العميل وعنوان التوصيل وتطبيع السلة.
 *
 * Used by:
 * - شاشة checkout في Flutter
 *
 * Maintenance notes:
 * - إذا فشل الإنشاء افحص بالتسلسل:
 *   customer lookup -> resolveOrderAddress -> createOrderWithItems transaction
 *   -> مخزون المنتجات -> coupon/offer logic -> fan-out الإشعارات.
 */
/**
 * ينشئ طلب عميل جديد بعد حل هوية العميل وعنوان التوصيل وتطبيع السلة.
 *
 * Used by:
 * - شاشة checkout في Flutter
 *
 * Maintenance notes:
 * - إذا فشل الإنشاء افحص بالتسلسل:
 *   customer lookup -> resolveOrderAddress -> createOrderWithItems transaction
 *   -> مخزون المنتجات -> coupon/offer logic -> الإشعارات اللاحقة.
 */
export async function createOrder(customerUserId, dto) {
  const { customer, deliveryAddress } = await resolveCheckoutContext(
    customerUserId,
    dto
  );

  const normalizedStoreOrders = normalizeStoreOrders(dto);
  const created = normalizedStoreOrders
    ? await repo.createOrderGroupWithItems({
      customer,
      deliveryAddress,
      note:
        typeof dto.note === "string" && dto.note.trim()
          ? dto.note.trim()
          : null,
      paymentMethod:
        typeof dto.paymentMethod === "string" && dto.paymentMethod.trim()
          ? dto.paymentMethod.trim()
          : "cash_on_delivery",
      storeOrders: normalizedStoreOrders,
    })
    : await repo.createOrderWithItems({
        customer,
        deliveryAddress,
        merchantId: Number(dto.merchantId),
        note: dto.note?.trim(),
        imageUrl: dto.imageUrl || null,
        couponId:
          dto.couponId == null || dto.couponId === ""
            ? null
            : Number(dto.couponId),
        couponCode:
          typeof dto.couponCode === "string" && dto.couponCode.trim()
            ? dto.couponCode.trim().toUpperCase()
            : null,
        normalizedItems: normalizeItems(dto.items),
      });

  invalidateOrderListCacheForUser(customerUserId);
  return created;
}

export async function previewOrder(customerUserId, dto) {
  const { customer, deliveryAddress } = await resolveCheckoutContext(
    customerUserId,
    dto
  );
  const normalizedStoreOrders = normalizeStoreOrders(dto);
  if (normalizedStoreOrders) {
    return repo.previewOrderGroup({
      customer,
      deliveryAddress,
      note:
        typeof dto.note === "string" && dto.note.trim()
          ? dto.note.trim()
          : null,
      paymentMethod:
        typeof dto.paymentMethod === "string" && dto.paymentMethod.trim()
          ? dto.paymentMethod.trim()
          : "cash_on_delivery",
      storeOrders: normalizedStoreOrders,
    });
  }
  return repo.previewOrderGroup({
    customer,
    deliveryAddress,
    note:
      typeof dto.note === "string" && dto.note.trim()
        ? dto.note.trim()
        : null,
    paymentMethod:
      typeof dto.paymentMethod === "string" && dto.paymentMethod.trim()
        ? dto.paymentMethod.trim()
        : "cash_on_delivery",
    storeOrders: [
      {
        merchantId: Number(dto.merchantId),
        note: dto.note?.trim() || null,
        imageUrl: dto.imageUrl || null,
        couponId: dto.couponId == null || dto.couponId === "" ? null : Number(dto.couponId),
        couponCode:
          typeof dto.couponCode === "string" && dto.couponCode.trim()
            ? dto.couponCode.trim().toUpperCase()
            : null,
        normalizedItems: normalizeItems(dto.items),
      },
    ],
  });
}

export async function listMyOrders(
  customerUserId,
  { paginate = false, limit = null, offset = 0 } = {}
) {
  const cacheKey = buildOrderListCacheKey(customerUserId, {
    paginate,
    limit,
    offset,
  });
  const cached = readOrderListCache(cacheKey);
  if (cached) return cached;
  const out = await repo.listCustomerOrders(customerUserId, {
    paginate,
    limit,
    offset,
  });
  return writeOrderListCache(cacheKey, out);
}

export async function getOrderGroupDetails(customerUserId, groupId) {
  const out = await repo.getCustomerOrderGroupDetails(
    customerUserId,
    Number(groupId)
  );
  if (!out) {
    const err = new Error("ORDER_GROUP_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  return out;
}

export async function getOrderTrackingSnapshot(customerUserId, orderId) {
  const out = await repo.getCustomerOrderTrackingSnapshot(
    Number(customerUserId),
    Number(orderId)
  );
  if (!out) {
    const err = new Error("ORDER_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  return out;
}

/**
 * Role-aware order tracking. The customer owner, the assigned courier, the
 * merchant owner and admins may all view a tracking snapshot for the order;
 * anyone else is rejected with 403 (not 404), so the apps can show a clear
 * "not allowed" state instead of a generic failure.
 */
export async function getOrderTrackingSnapshotForViewer({
  viewerUserId,
  viewerRole,
  isSuperAdmin = false,
  orderId,
}) {
  const out = await repo.getOrderTrackingSnapshotForViewer({
    viewerUserId: Number(viewerUserId),
    viewerRole,
    isSuperAdmin: isSuperAdmin === true,
    orderId: Number(orderId),
  });
  if (out?.notFound) {
    const err = new Error("ORDER_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  if (out?.forbidden) {
    const err = new Error("FORBIDDEN_ORDER_TRACKING");
    err.status = 403;
    throw err;
  }
  return out.snapshot;
}

export async function createOrderShareToken(customerUserId, orderId) {
  const out = await repo.createCustomerOrderShareToken(
    Number(customerUserId),
    Number(orderId)
  );
  if (!out) {
    const err = new Error("ORDER_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  return out;
}

export async function getPublicOrderTracking(token) {
  const out = await repo.getPublicOrderTrackingByToken(String(token || "").trim());
  if (!out) {
    const err = new Error("ORDER_TRACKING_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  return out;
}

/**
 * يؤكد استلام العميل للطلب بعد أن تكون حالة الطلب وصلت إلى delivered فعلاً.
 */
/**
 * يؤكد استلام العميل للطلب بعد أن تكون حالته وصلت فعلاً إلى `delivered`.
 */
export async function confirmDelivered(customerUserId, orderId) {
  const ok = await repo.confirmOrderDelivered(customerUserId, Number(orderId));
  if (!ok) {
    const err = new Error("ORDER_NOT_FOUND_OR_NOT_DELIVERED");
    err.status = 404;
    throw err;
  }
  invalidateOrderListCacheForUser(customerUserId);
}

export async function rateDelivery(customerUserId, orderId, rating, review) {
  const ok = await repo.rateDelivery(
    customerUserId,
    Number(orderId),
    Number(rating),
    review?.trim()
  );
  if (!ok) {
    const err = new Error("ORDER_NOT_FOUND_OR_NOT_RATEABLE");
    err.status = 409;
    throw err;
  }
}

export async function rateMerchant(customerUserId, orderId, rating, review) {
  const ok = await repo.rateMerchant(
    customerUserId,
    Number(orderId),
    Number(rating),
    review?.trim()
  );
  if (!ok) {
    const err = new Error("ORDER_NOT_FOUND_OR_NOT_RATEABLE");
    err.status = 409;
    throw err;
  }
}

export async function listFavoriteProductIds(customerUserId) {
  return repo.listFavoriteProductIds(customerUserId);
}

export async function listFavoriteProducts(
  customerUserId,
  { merchantId = null, limit = 40, offset = 0 } = {}
) {
  return repo.listFavoriteProducts(customerUserId, {
    merchantId: merchantId || null,
    limit,
    offset,
  });
}

export async function addFavoriteProduct(customerUserId, productId) {
  return repo.addFavoriteProduct(customerUserId, Number(productId));
}

export async function removeFavoriteProduct(customerUserId, productId) {
  return repo.removeFavoriteProduct(customerUserId, Number(productId));
}

/**
 * يعيد استخدام عناصر طلب سابق لإنشاء طلب جديد بنفس المتجر والسياق قدر الإمكان.
 *
 * Critical notes:
 * - لا يعتمد blindly على الطلب القديم؛ يعيد المرور عبر createOrderWithItems
 *   حتى يعاد تقييم المخزون والعروض الحالية.
 */
/**
 * يعيد استخدام عناصر طلب سابق لإنشاء طلب جديد مع إعادة تقييم المخزون
 * والعروض الحالية بدلاً من نسخ الطلب القديم كما هو.
 */
export async function reorderOrder(customerUserId, orderId, note) {
  const source = await repo.getOrderForReorder(customerUserId, Number(orderId));
  if (!source) {
    const err = new Error("ORDER_NOT_FOUND");
    err.status = 404;
    throw err;
  }

  if (!source.items.length) {
    const err = new Error("ORDER_HAS_NO_REORDERABLE_ITEMS");
    err.status = 400;
    throw err;
  }

  const customer = await getUserPublicById(customerUserId);
  if (!customer) {
    const err = new Error("CUSTOMER_NOT_FOUND");
    err.status = 404;
    throw err;
  }

  return repo.createOrderWithItems({
    customer,
    deliveryAddress: {
      city: source.customerCity || "مدينة بسماية",
      block: source.customerBlock || customer.block,
      building_number: source.customerBuildingNumber || customer.building_number,
      apartment: source.customerApartment || customer.apartment,
    },
    merchantId: source.merchantId,
    note: note?.trim() || source.note || null,
    normalizedItems: source.items,
  });
}

export async function listOrderActionReasons({ actorScope, actionKind } = {}) {
  const scope = normalizeOrderActionScope(actorScope, { fallback: null });
  const kind = normalizeOrderActionKind(actionKind, { fallback: null });
  return listOrderActionReasonsRepo({
    actorScope: scope,
    actionKind: kind,
  });
}

async function resolveOrderActionReasonPayload({
  actorScope,
  actionKind,
  reasonCode,
  reasonText,
}) {
  const normalizedCode = String(reasonCode || "").trim().toLowerCase();
  const normalizedText =
    reasonText == null ? null : String(reasonText).trim() || null;
  const legacyAliases = {
    delay_too_long: "changed_mind",
    wrong_address: "address_issue",
    item_damaged: "damaged_item",
  };
  let reason = await getOrderActionReason({
    actorScope,
    actionKind,
    reasonCode: normalizedCode,
  });
  if (!reason && legacyAliases[normalizedCode]) {
    reason = await getOrderActionReason({
      actorScope,
      actionKind,
      reasonCode: legacyAliases[normalizedCode],
    });
  }
  if (!reason) {
    const err = new Error("ORDER_ACTION_REASON_INVALID");
    err.status = 400;
    throw err;
  }
  if (reason.allowsOtherText && !normalizedText) {
    const err = new Error("ORDER_ACTION_REASON_TEXT_REQUIRED");
    err.status = 400;
    throw err;
  }
  return {
    reasonCode: reason.reasonCode,
    reasonText:
      normalizedText ??
      (reason.allowsOtherText ? null : reason.reasonLabelAr || reason.reasonCode),
  };
}

export async function cancelOrderByCustomer(
  customerUserId,
  orderId,
  { reasonCode, reasonText }
) {
  const reasonPayload = await resolveOrderActionReasonPayload({
    actorScope: "customer",
    actionKind: "cancel",
    reasonCode,
    reasonText,
  });
  const out = await repo.cancelOrderByCustomer({
    customerUserId: Number(customerUserId),
    orderId: Number(orderId),
    reasonCode: reasonPayload.reasonCode,
    reasonText: reasonPayload.reasonText,
  });
  if (!out) {
    const err = new Error("ORDER_CANNOT_BE_CANCELLED");
    err.status = 409;
    throw err;
  }
  invalidateOrderListCacheForUser(customerUserId);
  return out;
}

export async function requestReturnByCustomer(
  customerUserId,
  orderId,
  { reasonCode, reasonText }
) {
  const reasonPayload = await resolveOrderActionReasonPayload({
    actorScope: "customer",
    actionKind: "return",
    reasonCode,
    reasonText,
  });
  const out = await repo.requestOrderReturnByCustomer({
    customerUserId: Number(customerUserId),
    orderId: Number(orderId),
    reasonCode: reasonPayload.reasonCode,
    reasonText: reasonPayload.reasonText,
  });
  if (!out) {
    const err = new Error("ORDER_RETURN_NOT_ALLOWED");
    err.status = 409;
    throw err;
  }
  invalidateOrderListCacheForUser(customerUserId);
  return out;
}

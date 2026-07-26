import { pool, q } from "../../config/db.js";
import { AppError } from "../../shared/utils/errors.js";
import { createNotification } from "../notifications/notifications.repo.js";
import { emitRealtimeToUser } from "../../shared/realtime/realtime-gateway.js";
import {
  computeOrderFinancialSnapshot,
  getMerchantBillingProfile,
  roundMoney,
} from "../commerce/merchant-financial.logic.js";
import { buildOrderItemDisplaySnapshot } from "./order-item-snapshot.logic.js";

const OPEN_REVISION_STATUSES = new Set([
  "DRAFT",
  "AWAITING_CUSTOMER",
  "AWAITING_MERCHANT",
  "AWAITING_BOTH",
  "APPROVED",
  "APPLYING",
]);

const FINAL_ORDER_STATUSES = new Set([
  "delivered",
  "delivered_by_courier",
  "received_by_customer",
  "completed",
  "cancelled",
  "cancelled_by_customer",
  "cancelled_by_store",
  "cancelled_by_admin",
  "failed_delivery",
  "returned_if_needed",
]);

const DELIVERY_LOCKED_STATUSES = new Set(["on_the_way", "arrived", "picked_up"]);

function json(value, fallback) {
  return JSON.stringify(value ?? fallback);
}

function toMoney(value) {
  return roundMoney(Number(value || 0));
}

function asArray(value) {
  return Array.isArray(value) ? value : [];
}

function normalizeRole(role) {
  return String(role || "agent").trim().toLowerCase() || "agent";
}

function queueNotification(payload) {
  createNotification(payload).catch((error) => {
    console.warn("[order-revisions] notification failed", error?.message || error);
  });
}

function queueRealtime(userId, event, payload) {
  if (!userId) return;
  emitRealtimeToUser(Number(userId), event, payload).catch((error) => {
    console.warn("[order-revisions] realtime failed", error?.message || error);
  });
}

function notificationSurfaceForRole(role) {
  const normalized = normalizeRole(role);
  if (normalized === "owner" || normalized === "merchant") return "store";
  if (normalized === "delivery" || normalized === "courier") return "delivery";
  if (normalized === "admin" || normalized === "agent" || normalized === "deputy_admin") return "admin";
  return "user";
}

function notifyUser({ userId, role, type, title, body, revision, order = null, extra = {} }) {
  if (!userId) return;
  const payload = {
    ...publicRevisionPayload(revision),
    target: "order_revision",
    targetModule: role === "delivery" || role === "courier" ? "courier" : "orders",
    roleScope: role,
    appSurface: notificationSurfaceForRole(role),
    merchantId: order?.merchant_id == null ? undefined : Number(order.merchant_id),
    ...extra,
  };
  queueNotification({
    userId: Number(userId),
    type,
    title,
    body,
    orderId: Number(revision.order_id),
    merchantId: order?.merchant_id == null ? undefined : Number(order.merchant_id),
    payload,
  });
  queueRealtime(Number(userId), "order_revision", payload);
}

function publicRevisionPayload(revision) {
  return {
    revisionId: Number(revision.id),
    orderId: Number(revision.order_id),
    supportTicketId: Number(revision.support_ticket_id),
    status: revision.status,
    priceDifference: toMoney(revision.price_difference),
    target: "order_revision",
    targetModule: "orders",
  };
}

function orderStatusIsEditable(status) {
  const normalized = String(status || "").trim().toLowerCase();
  return !FINAL_ORDER_STATUSES.has(normalized) && !DELIVERY_LOCKED_STATUSES.has(normalized);
}

async function ensureTicketLinkedToOrderTx(client, { ticketId, orderId }) {
  const ticket = await client.query(
    `SELECT id, user_id, status, entity_type, entity_id
     FROM support_ticket
     WHERE id = $1
     LIMIT 1`,
    [Number(ticketId)]
  );
  const row = ticket.rows[0] || null;
  if (!row) throw new AppError("TICKET_NOT_FOUND", { status: 404 });

  const directMatch =
    String(row.entity_type || "").toLowerCase() === "order" &&
    Number(row.entity_id) === Number(orderId);
  const link = await client.query(
    `SELECT id
     FROM support_ticket_link
     WHERE ticket_id = $1
       AND entity_type = 'order'
       AND entity_id = $2
     LIMIT 1`,
    [Number(ticketId), Number(orderId)]
  );
  if (!directMatch && !link.rows[0]) {
    throw new AppError("SUPPORT_TICKET_ORDER_LINK_REQUIRED", { status: 403 });
  }
  return row;
}

async function loadOrderForRevisionTx(client, orderId, { lock = false } = {}) {
  const result = await client.query(
    `SELECT
       o.*,
       o.status::text AS status_text,
       m.name AS merchant_name,
       m.owner_user_id
     FROM customer_order o
     JOIN merchant m ON m.id = o.merchant_id
     WHERE o.id = $1
     ${lock ? "FOR UPDATE OF o" : ""}
     LIMIT 1`,
    [Number(orderId)]
  );
  const order = result.rows[0] || null;
  if (!order) throw new AppError("ORDER_NOT_FOUND", { status: 404 });
  return order;
}

async function loadOrderItemsTx(client, orderId) {
  const result = await client.query(
    `SELECT
       id,
       order_id,
       product_id,
       product_name,
       base_unit_price,
       unit_price,
       quantity,
       selected_modifiers_json,
       selected_variant_json,
       selected_variant_options_json,
       display_snapshot_json,
       variant_price_delta_total,
       modifiers_unit_total,
       modifiers_line_total,
       line_discount_total,
       line_total,
       pricing_breakdown_json
     FROM order_item
     WHERE order_id = $1
     ORDER BY id ASC`,
    [Number(orderId)]
  );
  return result.rows;
}

function itemVariantId(row) {
  const snapshot = row?.selected_variant_json || {};
  return Number(snapshot.variantId ?? snapshot.variant_id ?? row?.variant_id ?? 0) || null;
}

function itemVariantSignature(row) {
  const snapshot = row?.selected_variant_json || {};
  return snapshot.signature || null;
}

function inventoryKey({ productId, variantId = null, variantSignature = null }) {
  return [
    Number(productId),
    variantId == null ? "" : Number(variantId),
    variantId == null ? String(variantSignature || "") : "",
  ].join(":");
}

function summarizeItems(rows) {
  return rows.map((row) => ({
    orderItemId: row.id == null ? null : Number(row.id),
    productId: Number(row.product_id ?? row.productId),
    variantId: itemVariantId(row),
    variantSignature: itemVariantSignature(row),
    productName: row.product_name ?? row.productName,
    quantity: Number(row.quantity || 0),
    unitPrice: toMoney(row.unit_price ?? row.unitPrice),
    lineTotal: toMoney(row.line_total ?? row.lineTotal),
    selectedVariant: row.selected_variant_json || row.selectedVariant || null,
    selectedVariantOptions:
      row.selected_variant_options_json || row.selectedVariantOptions || [],
    selectedModifiers: row.selected_modifiers_json || row.selectedModifiers || [],
    displaySnapshot: row.display_snapshot_json || row.displaySnapshot || null,
    pricingBreakdown: row.pricing_breakdown_json || row.pricingBreakdown || {},
  }));
}

function orderTotals(order) {
  return {
    grossSubtotal: toMoney(order.gross_subtotal ?? order.subtotal),
    productDiscountTotal: toMoney(order.product_discount_total),
    couponDiscountTotal: toMoney(order.coupon_discount_total),
    subtotal: toMoney(order.subtotal),
    serviceFee: toMoney(order.service_fee),
    deliveryFee: toMoney(order.delivery_fee),
    deliveryFeeRaw: toMoney(order.delivery_fee_raw ?? order.delivery_fee),
    totalAmount: toMoney(order.total_amount),
    pricingBreakdown: order.pricing_breakdown_json || {},
    financialSnapshot: order.financial_config_snapshot_json || {},
  };
}

async function loadCatalogTx(client, merchantId, proposedItems) {
  const productIds = [...new Set(proposedItems.map((item) => Number(item.productId)))];
  if (!productIds.length) throw new AppError("ORDER_REVISION_ITEMS_REQUIRED", { status: 400 });

  const products = await client.query(
    `SELECT
       p.id,
       p.merchant_id,
       p.name,
       p.image_url,
       p.price,
       p.discounted_price,
       p.is_available,
       si.quantity AS inventory_quantity,
       si.reorder_threshold AS inventory_reorder_threshold,
       si.manual_disabled AS inventory_manual_disabled
     FROM product p
     LEFT JOIN store_inventory_item si
       ON si.merchant_id = p.merchant_id
      AND si.product_id = p.id
     WHERE p.id = ANY($1::bigint[])`,
    [productIds]
  );
  const productMap = new Map(products.rows.map((row) => [Number(row.id), row]));

  const variants = await client.query(
    `SELECT id, product_id, signature, selections_json, sku, material,
            price_override, discounted_price_override, stock_quantity,
            image_url, is_available
     FROM product_variant
     WHERE product_id = ANY($1::bigint[])`,
    [productIds]
  );
  const variantMap = new Map(variants.rows.map((row) => [Number(row.id), row]));

  for (const item of proposedItems) {
    const product = productMap.get(Number(item.productId));
    if (!product) throw new AppError("PRODUCT_NOT_FOUND", { status: 404 });
    if (Number(product.merchant_id) !== Number(merchantId)) {
      throw new AppError("ORDER_REVISION_CROSS_MERCHANT_ITEM", { status: 400 });
    }
    if (product.is_available === false) {
      throw new AppError("PRODUCT_UNAVAILABLE", { status: 400 });
    }
    if (item.variantId != null) {
      const variant = variantMap.get(Number(item.variantId));
      if (!variant || Number(variant.product_id) !== Number(product.id)) {
        throw new AppError("PRODUCT_VARIANT_SELECTION_INVALID", { status: 400 });
      }
      if (variant.is_available === false) {
        throw new AppError("PRODUCT_VARIANT_UNAVAILABLE", { status: 400 });
      }
    }
  }

  return { productMap, variantMap };
}

function resolveVariantSnapshot(product, variant) {
  if (!variant) return null;
  return {
    signature: variant.signature || null,
    variantId: Number(variant.id),
    sku: variant.sku || null,
    material: variant.material || null,
    imageUrl: variant.image_url || null,
    stockQuantity: Number(variant.stock_quantity || 0),
    selections: asArray(variant.selections_json),
    productId: Number(product.id),
    productName: product.name,
  };
}

function calculateProposedItems({ order, existingItems, requestedItems, productMap, variantMap }) {
  const existingById = new Map(existingItems.map((row) => [Number(row.id), row]));
  const requested = [];
  for (const raw of requestedItems) {
    if (Number(raw.quantity) <= 0) continue;
    const existing = raw.orderItemId ? existingById.get(Number(raw.orderItemId)) : null;
    const productId = Number(raw.productId || existing?.product_id || 0);
    const product = productMap.get(productId);
    const variantId = raw.variantId ?? (existing ? itemVariantId(existing) : null);
    const variant = variantId == null ? null : variantMap.get(Number(variantId));
    const baseUnitPrice = toMoney(
      variant?.price_override ??
        product.discounted_price ??
        product.price
    );
    const unitPrice = toMoney(
      variant?.discounted_price_override ??
        variant?.price_override ??
        product.discounted_price ??
        product.price
    );
    const quantity = Math.max(1, Number(raw.quantity || 0));
    const lineTotal = toMoney(unitPrice * quantity);
    const variantSnapshot = resolveVariantSnapshot(product, variant);
    const displaySnapshot = buildOrderItemDisplaySnapshot({
      productId: product.id,
      productName: product.name,
      productImageUrl: product.image_url || null,
      thumbnailUrl: variant?.image_url || product.image_url || null,
      variantId: variant?.id || null,
      variantName: variant?.signature || null,
      variantSku: variant?.sku || null,
      quantity,
      unitPrice,
      lineTotal,
      currency: "IQD",
      specs: variantSnapshot?.selections || [],
      options: raw.selectedModifiers || [],
      userNote: raw.note || null,
      activityType: order.activity_type || null,
      storeId: order.merchant_id,
      storeName: order.merchant_name,
    });
    requested.push({
      orderItemId: existing ? Number(existing.id) : null,
      productId,
      variantId: variant?.id == null ? null : Number(variant.id),
      variantSignature: variant?.signature || null,
      productName: product.name,
      quantity,
      baseUnitPrice,
      unitPrice,
      lineTotal,
      selectedModifiers: raw.selectedModifiers || [],
      selectedVariantSnapshot: variantSnapshot,
      selectedVariantOptions: variantSnapshot?.selections || [],
      displaySnapshot,
      pricingBreakdown: {
        baseUnitPrice,
        finalUnitPrice: unitPrice,
        quantity,
        lineDiscountTotal: 0,
        grossLineTotal: lineTotal,
        lineTotal,
        selectedVariantSnapshot: variantSnapshot,
        displaySnapshot,
      },
    });
  }
  return requested;
}

function summarizeInventoryEffect(originalItems, proposedItems) {
  const original = new Map();
  const proposed = new Map();
  for (const item of originalItems) {
    const key = inventoryKey(item);
    original.set(key, {
      productId: Number(item.productId),
      variantId: item.variantId,
      variantSignature: item.variantSignature,
      quantity: (original.get(key)?.quantity || 0) + Number(item.quantity || 0),
    });
  }
  for (const item of proposedItems) {
    const key = inventoryKey(item);
    proposed.set(key, {
      productId: Number(item.productId),
      variantId: item.variantId,
      variantSignature: item.variantSignature,
      quantity: (proposed.get(key)?.quantity || 0) + Number(item.quantity || 0),
    });
  }
  const keys = new Set([...original.keys(), ...proposed.keys()]);
  const deltas = [];
  for (const key of keys) {
    const before = original.get(key) || { quantity: 0 };
    const after = proposed.get(key) || before;
    const delta = Number(after.quantity || 0) - Number(before.quantity || 0);
    if (delta !== 0) {
      deltas.push({
        productId: Number(after.productId || before.productId),
        variantId: after.variantId ?? before.variantId ?? null,
        variantSignature: after.variantSignature ?? before.variantSignature ?? null,
        quantityBefore: Number(before.quantity || 0),
        quantityAfter: Number(after.quantity || 0),
        delta,
      });
    }
  }
  return { deltas };
}

function assertProposedInventoryCapacity({ originalItems, proposedItems, productMap, variantMap }) {
  const originalByKey = new Map();
  for (const item of originalItems) {
    const key = inventoryKey(item);
    originalByKey.set(key, (originalByKey.get(key) || 0) + Number(item.quantity || 0));
  }
  const proposedByKey = new Map();
  for (const item of proposedItems) {
    const key = inventoryKey(item);
    const current = proposedByKey.get(key) || {
      productId: Number(item.productId),
      variantId: item.variantId,
      variantSignature: item.variantSignature,
      quantity: 0,
    };
    current.quantity += Number(item.quantity || 0);
    proposedByKey.set(key, current);
  }
  for (const [key, item] of proposedByKey) {
    const originalQty = Number(originalByKey.get(key) || 0);
    if (item.variantId != null) {
      const variant = variantMap.get(Number(item.variantId));
      const available = Number(variant?.stock_quantity || 0) + originalQty;
      if (Number(item.quantity || 0) > available) {
        throw new AppError("PRODUCT_OUT_OF_STOCK", {
          status: 409,
          details: {
            productId: item.productId,
            variantId: item.variantId,
            requestedQuantity: Number(item.quantity || 0),
            availableQuantity: available,
          },
        });
      }
      continue;
    }
    const product = productMap.get(Number(item.productId));
    if (product?.inventory_quantity == null) continue;
    if (product.inventory_manual_disabled === true) {
      throw new AppError("PRODUCT_UNAVAILABLE", { status: 409 });
    }
    const available = Number(product.inventory_quantity || 0) + originalQty;
    if (Number(item.quantity || 0) > available) {
      throw new AppError("PRODUCT_OUT_OF_STOCK", {
        status: 409,
        details: {
          productId: item.productId,
          requestedQuantity: Number(item.quantity || 0),
          availableQuantity: available,
        },
      });
    }
  }
}

function calculateTotals(order, proposedItems) {
  const grossSubtotal = toMoney(
    proposedItems.reduce((sum, item) => sum + Number(item.lineTotal || 0), 0)
  );
  const couponDiscountTotal = Math.min(
    toMoney(order.coupon_discount_total),
    grossSubtotal
  );
  const billingSnapshot = computeOrderFinancialSnapshot(
    {
      ...order,
      subtotal: grossSubtotal,
      coupon_discount_total: couponDiscountTotal,
      total_amount:
        couponDiscountTotal > 0
          ? grossSubtotal +
            toMoney(order.service_fee) +
            toMoney(order.delivery_fee) -
            couponDiscountTotal
          : Number.MAX_SAFE_INTEGER,
    },
    {}
  );
  const subtotalAfterAllDiscounts = toMoney(Math.max(0, grossSubtotal - couponDiscountTotal));
  const totalAmount = toMoney(
    subtotalAfterAllDiscounts +
      Number(billingSnapshot.serviceFeeAmount || 0) +
      Number(billingSnapshot.deliveryFee || 0)
  );
  const financialSnapshot = {
    ...billingSnapshot,
    subtotal: grossSubtotal,
    couponDiscountTotal,
    customerTotalAmount: totalAmount,
  };
  return {
    grossSubtotal,
    productDiscountTotal: 0,
    couponDiscountTotal,
    subtotal: grossSubtotal,
    serviceFee: toMoney(financialSnapshot.serviceFeeAmount),
    deliveryFee: toMoney(financialSnapshot.deliveryFee),
    deliveryFeeRaw: toMoney(order.delivery_fee_raw ?? financialSnapshot.deliveryFee),
    totalAmount,
    pricingBreakdown: {
      grossSubtotal,
      productDiscountTotal: 0,
      subtotalAfterProductDiscounts: grossSubtotal,
      couponDiscountTotal,
      subtotalAfterAllDiscounts,
      serviceFee: toMoney(financialSnapshot.serviceFeeAmount),
      deliveryFee: toMoney(financialSnapshot.deliveryFee),
      rawDeliveryFee: toMoney(order.delivery_fee_raw ?? financialSnapshot.deliveryFee),
      totalAmount,
      coupon: order.coupon_id
        ? {
            id: Number(order.coupon_id),
            code: order.coupon_code || null,
            discountAmount: couponDiscountTotal,
          }
        : null,
      items: proposedItems.map((item) => item.pricingBreakdown),
    },
    financialSnapshot,
  };
}

function approvalRequirements({ originalItems, proposedItems, priceDifference }) {
  const itemChanged = JSON.stringify(
    originalItems.map((item) => ({
      productId: item.productId,
      variantId: item.variantId,
      quantity: item.quantity,
    }))
  ) !== JSON.stringify(
    proposedItems.map((item) => ({
      productId: item.productId,
      variantId: item.variantId,
      quantity: item.quantity,
    }))
  );
  const required = [];
  if (itemChanged) required.push("MERCHANT");
  if (Math.abs(Number(priceDifference || 0)) > 0.009) required.push("CUSTOMER");
  return required.length ? required : ["MERCHANT"];
}

function nextAwaitingStatus(required) {
  const set = new Set(required);
  if (set.has("CUSTOMER") && set.has("MERCHANT")) return "AWAITING_BOTH";
  if (set.has("CUSTOMER")) return "AWAITING_CUSTOMER";
  if (set.has("MERCHANT")) return "AWAITING_MERCHANT";
  return "APPROVED";
}

function computeItemActions(originalItems, proposedItems) {
  const originalById = new Map(
    originalItems
      .filter((item) => item.orderItemId)
      .map((item) => [Number(item.orderItemId), item])
  );
  const seen = new Set();
  const rows = [];
  for (const after of proposedItems) {
    const before = after.orderItemId ? originalById.get(Number(after.orderItemId)) : null;
    if (before) seen.add(Number(before.orderItemId));
    let action = "added";
    if (before) {
      if (Number(before.productId) !== Number(after.productId)) action = "replaced";
      else if (Number(before.variantId || 0) !== Number(after.variantId || 0)) action = "variant_changed";
      else if (Number(before.quantity) !== Number(after.quantity)) action = "quantity_changed";
      else action = "unchanged";
    }
    rows.push({
      orderItemId: before?.orderItemId || null,
      action,
      productId: after.productId,
      variantId: after.variantId,
      productName: after.productName,
      quantityBefore: Number(before?.quantity || 0),
      quantityAfter: Number(after.quantity || 0),
      unitPriceBefore: toMoney(before?.unitPrice || 0),
      unitPriceAfter: toMoney(after.unitPrice || 0),
      lineTotalBefore: toMoney(before?.lineTotal || 0),
      lineTotalAfter: toMoney(after.lineTotal || 0),
      beforeSnapshot: before || null,
      afterSnapshot: after,
      inventoryDelta: Number(after.quantity || 0) - Number(before?.quantity || 0),
    });
  }
  for (const before of originalItems) {
    if (before.orderItemId && seen.has(Number(before.orderItemId))) continue;
    rows.push({
      orderItemId: before.orderItemId || null,
      action: "removed",
      productId: before.productId,
      variantId: before.variantId,
      productName: before.productName,
      quantityBefore: Number(before.quantity || 0),
      quantityAfter: 0,
      unitPriceBefore: toMoney(before.unitPrice || 0),
      unitPriceAfter: 0,
      lineTotalBefore: toMoney(before.lineTotal || 0),
      lineTotalAfter: 0,
      beforeSnapshot: before,
      afterSnapshot: null,
      inventoryDelta: -Number(before.quantity || 0),
    });
  }
  return rows;
}

async function buildRevisionDraftTx(client, { order, existingItems, requestedItems }) {
  const requestedWithFallbacks = requestedItems.map((item) => {
    if (item.orderItemId) {
      const existing = existingItems.find((row) => Number(row.id) === Number(item.orderItemId));
      return {
        ...item,
        productId: item.productId || Number(existing?.product_id || 0),
        variantId: item.variantId ?? itemVariantId(existing),
      };
    }
    return item;
  });
  const { productMap, variantMap } = await loadCatalogTx(
    client,
    Number(order.merchant_id),
    requestedWithFallbacks.filter((item) => Number(item.quantity) > 0)
  );
  const originalItems = summarizeItems(existingItems);
  const proposedItems = calculateProposedItems({
    order,
    existingItems,
    requestedItems: requestedWithFallbacks,
    productMap,
    variantMap,
  });
  assertProposedInventoryCapacity({
    originalItems,
    proposedItems,
    productMap,
    variantMap,
  });
  const proposedTotals = calculateTotals(order, proposedItems);
  const originalTotals = orderTotals(order);
  const priceDifference = toMoney(proposedTotals.totalAmount - originalTotals.totalAmount);
  const inventoryEffect = summarizeInventoryEffect(originalItems, proposedItems);
  const approvalsRequired = approvalRequirements({
    originalItems,
    proposedItems,
    priceDifference,
  });
  return {
    originalItems,
    proposedItems,
    originalTotals,
    proposedTotals,
    priceDifference,
    inventoryEffect,
    approvalsRequired,
    itemActions: computeItemActions(originalItems, proposedItems),
    paymentEffect: {
      priceDifference,
      adjustmentType:
        priceDifference > 0 ? "COLLECT_MORE" : priceDifference < 0 ? "REFUND" : "NO_CHANGE",
      direction:
        priceDifference > 0 ? "customer_owes" : priceDifference < 0 ? "customer_credit" : "none",
    },
  };
}

async function insertRevisionEventTx(
  client,
  { revisionId, orderId, ticketId, actorUserId, actorRole, eventType, fromStatus = null, toStatus = null, metadata = {} }
) {
  await client.query(
    `INSERT INTO order_revision_event
       (revision_id, order_id, support_ticket_id, actor_user_id, actor_role,
        event_type, from_status, to_status, metadata_json)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9::jsonb)`,
    [
      Number(revisionId),
      Number(orderId),
      ticketId == null ? null : Number(ticketId),
      actorUserId == null ? null : Number(actorUserId),
      actorRole || null,
      eventType,
      fromStatus,
      toStatus,
      json(metadata, {}),
    ]
  );
}

async function insertRevisionItemRowsTx(client, revisionId, itemActions) {
  for (const item of itemActions) {
    await client.query(
      `INSERT INTO order_revision_item
         (revision_id, order_item_id, action, product_id, variant_id, product_name,
          quantity_before, quantity_after, unit_price_before, unit_price_after,
          line_total_before, line_total_after, before_snapshot_json, after_snapshot_json,
          inventory_delta)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13::jsonb,$14::jsonb,$15)`,
      [
        Number(revisionId),
        item.orderItemId,
        item.action,
        Number(item.productId),
        item.variantId == null ? null : Number(item.variantId),
        item.productName,
        Number(item.quantityBefore || 0),
        Number(item.quantityAfter || 0),
        item.unitPriceBefore,
        item.unitPriceAfter,
        item.lineTotalBefore,
        item.lineTotalAfter,
        json(item.beforeSnapshot, {}),
        json(item.afterSnapshot, {}),
        Number(item.inventoryDelta || 0),
      ]
    );
  }
}

async function insertApprovalsTx(client, revisionId, required) {
  for (const approvalType of required) {
    await client.query(
      `INSERT INTO order_revision_approval (revision_id, approval_type)
       VALUES ($1,$2)
       ON CONFLICT (revision_id, approval_type) DO NOTHING`,
      [Number(revisionId), approvalType]
    );
  }
}

export async function createRevisionFromSupportTicket({
  ticketId,
  actorUserId,
  actorRole,
  orderId,
  reason,
  items,
  note,
  expiresInMinutes = 240,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const order = await loadOrderForRevisionTx(client, orderId, { lock: true });
    await ensureTicketLinkedToOrderTx(client, { ticketId, orderId: order.id });
    if (!orderStatusIsEditable(order.status_text)) {
      throw new AppError("ORDER_REVISION_ORDER_NOT_EDITABLE", { status: 409 });
    }
    const open = await client.query(
      `SELECT id, status
       FROM order_revision
       WHERE order_id = $1
         AND status = ANY($2::text[])
       LIMIT 1`,
      [Number(order.id), [...OPEN_REVISION_STATUSES]]
    );
    if (open.rows[0]) {
      throw new AppError("ORDER_REVISION_ALREADY_OPEN", {
        status: 409,
        details: { revisionId: Number(open.rows[0].id), status: open.rows[0].status },
      });
    }
    const existingItems = await loadOrderItemsTx(client, order.id);
    const draft = await buildRevisionDraftTx(client, {
      order,
      existingItems,
      requestedItems: items,
    });
    const versionRow = await client.query(
      `SELECT COALESCE(MAX(version_number), 0)::int + 1 AS next_version
       FROM order_revision
       WHERE order_id = $1`,
      [Number(order.id)]
    );
    const status = "DRAFT";
    const inserted = await client.query(
      `INSERT INTO order_revision
         (order_id, support_ticket_id, version_number, base_order_version,
          status, reason, created_by_user_id, created_by_employee_id,
          original_totals_json, proposed_totals_json,
          original_items_json, proposed_items_json,
          price_difference, inventory_effect_json,
          approvals_required_json, approval_state_json,
          payment_effect_json, metadata_json, expires_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9::jsonb,$10::jsonb,$11::jsonb,$12::jsonb,
               $13,$14::jsonb,$15::jsonb,$16::jsonb,$17::jsonb,$18::jsonb,
               NOW() + ($19 * interval '1 minute'))
       RETURNING *`,
      [
        Number(order.id),
        Number(ticketId),
        Number(versionRow.rows[0].next_version),
        Number(order.order_revision_version || 1),
        status,
        reason,
        Number(actorUserId),
        Number(actorUserId),
        json(draft.originalTotals, {}),
        json(draft.proposedTotals, {}),
        json(draft.originalItems, []),
        json(draft.proposedItems, []),
        draft.priceDifference,
        json(draft.inventoryEffect, {}),
        json(draft.approvalsRequired, []),
        json({}, {}),
        json(draft.paymentEffect, {}),
        json({ note: note ?? null }, {}),
        Number(expiresInMinutes),
      ]
    );
    const revision = inserted.rows[0];
    await insertRevisionItemRowsTx(client, revision.id, draft.itemActions);
    await insertApprovalsTx(client, revision.id, draft.approvalsRequired);
    await insertRevisionEventTx(client, {
      revisionId: revision.id,
      orderId: order.id,
      ticketId,
      actorUserId,
      actorRole: normalizeRole(actorRole),
      eventType: "created",
      toStatus: status,
      metadata: { approvalsRequired: draft.approvalsRequired },
    });
    await client.query("COMMIT");
    notifyRevisionCreated(revision);
    return getRevisionDetails({ orderId: order.id, revisionId: revision.id });
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function listRevisionsForTicket(ticketId) {
  const result = await q(
    `SELECT *
     FROM order_revision
     WHERE support_ticket_id = $1
     ORDER BY created_at DESC, id DESC`,
    [Number(ticketId)]
  );
  return { items: result.rows };
}

function revisionListStatusFilterForViewer(viewerRole) {
  const role = normalizeRole(viewerRole);
  if (role === "delivery" || role === "courier") {
    return ["APPLIED"];
  }
  return [
    "DRAFT",
    "AWAITING_CUSTOMER",
    "AWAITING_MERCHANT",
    "AWAITING_BOTH",
    "APPROVED",
    "APPLIED",
    "REJECTED",
    "FAILED",
    "EXPIRED",
  ];
}

async function assertOrderRevisionViewerTx(client, { orderId, viewerUserId, viewerRole }) {
  const order = await loadOrderForRevisionTx(client, orderId, { lock: false });
  const role = normalizeRole(viewerRole);
  const userId = Number(viewerUserId);
  if (role === "customer" || role === "user") {
    if (Number(order.customer_user_id) !== userId) {
      throw new AppError("ORDER_REVISION_FORBIDDEN", { status: 403 });
    }
    return order;
  }
  if (role === "owner" || role === "merchant") {
    if (Number(order.owner_user_id) !== userId) {
      throw new AppError("ORDER_REVISION_FORBIDDEN", { status: 403 });
    }
    return order;
  }
  if (role === "delivery" || role === "courier") {
    if (Number(order.delivery_user_id) !== userId) {
      throw new AppError("ORDER_REVISION_FORBIDDEN", { status: 403 });
    }
    return order;
  }
  throw new AppError("ORDER_REVISION_FORBIDDEN", { status: 403 });
}

export async function listRevisionsForOrderViewer({
  orderId,
  viewerUserId,
  viewerRole,
}) {
  const client = await pool.connect();
  try {
    const order = await assertOrderRevisionViewerTx(client, {
      orderId,
      viewerUserId,
      viewerRole,
    });
    const statuses = revisionListStatusFilterForViewer(viewerRole);
    const revisions = await client.query(
      `SELECT *
       FROM order_revision
       WHERE order_id = $1
         AND status = ANY($2::varchar[])
       ORDER BY created_at DESC, id DESC`,
      [Number(order.id), statuses]
    );
    return {
      orderId: Number(order.id),
      items: revisions.rows,
    };
  } finally {
    client.release();
  }
}

export async function getOrderRevisionContextForTicket(ticketId) {
  const result = await q(
    `WITH linked AS (
       SELECT entity_id::bigint AS order_id
       FROM support_ticket
       WHERE id = $1
         AND entity_type = 'order'
         AND entity_id IS NOT NULL
       UNION
       SELECT entity_id::bigint AS order_id
       FROM support_ticket_link
       WHERE ticket_id = $1
         AND entity_type = 'order'
     )
     SELECT
       o.*,
       o.status::text AS status_text,
       m.name AS merchant_name,
       m.owner_user_id,
       cu.full_name AS customer_name,
       cu.phone AS customer_phone,
       du.full_name AS delivery_name,
       du.phone AS delivery_phone
     FROM linked l
     JOIN customer_order o ON o.id = l.order_id
     JOIN merchant m ON m.id = o.merchant_id
     LEFT JOIN app_user cu ON cu.id = o.customer_user_id
     LEFT JOIN app_user du ON du.id = o.delivery_user_id
     ORDER BY o.id DESC
     LIMIT 1`,
    [Number(ticketId)]
  );
  const order = result.rows[0] || null;
  if (!order) {
    return {
      ticketId: Number(ticketId),
      order: null,
      items: [],
      invoice: null,
      revisions: [],
    };
  }
  const [items, invoice, revisions] = await Promise.all([
    q(`SELECT * FROM order_item WHERE order_id=$1 ORDER BY id ASC`, [Number(order.id)]),
    q(
      `SELECT *
       FROM merchant_receivable_invoice
       WHERE order_id=$1
       ORDER BY id DESC
       LIMIT 1`,
      [Number(order.id)]
    ),
    q(
      `SELECT *
       FROM order_revision
       WHERE order_id=$1
       ORDER BY created_at DESC, id DESC`,
      [Number(order.id)]
    ),
  ]);
  return {
    ticketId: Number(ticketId),
    order,
    items: items.rows,
    invoice: invoice.rows[0] || null,
    revisions: revisions.rows,
  };
}

export async function getRevisionDetails({ orderId, revisionId }) {
  const revision = await q(
    `SELECT *
     FROM order_revision
     WHERE id = $1 AND order_id = $2
     LIMIT 1`,
    [Number(revisionId), Number(orderId)]
  );
  const row = revision.rows[0] || null;
  if (!row) throw new AppError("ORDER_REVISION_NOT_FOUND", { status: 404 });
  const [items, approvals, events, adjustments] = await Promise.all([
    q(`SELECT * FROM order_revision_item WHERE revision_id = $1 ORDER BY id ASC`, [Number(revisionId)]),
    q(`SELECT * FROM order_revision_approval WHERE revision_id = $1 ORDER BY id ASC`, [Number(revisionId)]),
    q(`SELECT * FROM order_revision_event WHERE revision_id = $1 ORDER BY created_at ASC, id ASC`, [Number(revisionId)]),
    q(`SELECT * FROM order_revision_financial_adjustment WHERE revision_id = $1 ORDER BY created_at DESC`, [Number(revisionId)]),
  ]);
  return {
    revision: row,
    items: items.rows,
    approvals: approvals.rows,
    events: events.rows,
    adjustments: adjustments.rows,
  };
}

export async function patchRevision({ orderId, revisionId, actorUserId, actorRole, patch }) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const current = await client.query(
      `SELECT * FROM order_revision WHERE id=$1 AND order_id=$2 FOR UPDATE`,
      [Number(revisionId), Number(orderId)]
    );
    const revision = current.rows[0];
    if (!revision) throw new AppError("ORDER_REVISION_NOT_FOUND", { status: 404 });
    if (revision.status !== "DRAFT") {
      throw new AppError("ORDER_REVISION_NOT_EDITABLE", { status: 409 });
    }
    const order = await loadOrderForRevisionTx(client, orderId, { lock: true });
    const existingItems = await loadOrderItemsTx(client, order.id);
    const requestedItems = patch.items || asArray(revision.proposed_items_json).map((item) => ({
      orderItemId: item.orderItemId,
      productId: item.productId,
      variantId: item.variantId,
      quantity: item.quantity,
      selectedModifiers: item.selectedModifiers,
    }));
    const draft = await buildRevisionDraftTx(client, {
      order,
      existingItems,
      requestedItems,
    });
    const reason = patch.reason ?? revision.reason;
    const metadata = { ...(revision.metadata_json || {}) };
    if (Object.prototype.hasOwnProperty.call(patch, "note")) metadata.note = patch.note;
    const updated = await client.query(
      `UPDATE order_revision
       SET reason=$3,
           original_totals_json=$4::jsonb,
           proposed_totals_json=$5::jsonb,
           original_items_json=$6::jsonb,
           proposed_items_json=$7::jsonb,
           price_difference=$8,
           inventory_effect_json=$9::jsonb,
           approvals_required_json=$10::jsonb,
           payment_effect_json=$11::jsonb,
           metadata_json=$12::jsonb
       WHERE id=$1 AND order_id=$2
       RETURNING *`,
      [
        Number(revisionId),
        Number(orderId),
        reason,
        json(draft.originalTotals, {}),
        json(draft.proposedTotals, {}),
        json(draft.originalItems, []),
        json(draft.proposedItems, []),
        draft.priceDifference,
        json(draft.inventoryEffect, {}),
        json(draft.approvalsRequired, []),
        json(draft.paymentEffect, {}),
        json(metadata, {}),
      ]
    );
    await client.query(`DELETE FROM order_revision_item WHERE revision_id=$1`, [Number(revisionId)]);
    await client.query(`DELETE FROM order_revision_approval WHERE revision_id=$1`, [Number(revisionId)]);
    await insertRevisionItemRowsTx(client, revisionId, draft.itemActions);
    await insertApprovalsTx(client, revisionId, draft.approvalsRequired);
    await insertRevisionEventTx(client, {
      revisionId,
      orderId,
      ticketId: revision.support_ticket_id,
      actorUserId,
      actorRole: normalizeRole(actorRole),
      eventType: "updated",
      fromStatus: revision.status,
      toStatus: updated.rows[0].status,
      metadata: { approvalsRequired: draft.approvalsRequired },
    });
    await client.query("COMMIT");
    return getRevisionDetails({ orderId, revisionId });
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function submitRevision({ orderId, revisionId, actorUserId, actorRole }) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const result = await client.query(
      `SELECT * FROM order_revision WHERE id=$1 AND order_id=$2 FOR UPDATE`,
      [Number(revisionId), Number(orderId)]
    );
    const revision = result.rows[0];
    if (!revision) throw new AppError("ORDER_REVISION_NOT_FOUND", { status: 404 });
    if (revision.status !== "DRAFT") {
      throw new AppError("ORDER_REVISION_SUBMIT_INVALID_STATE", { status: 409 });
    }
    const required = asArray(revision.approvals_required_json);
    const nextStatus = nextAwaitingStatus(required);
    const updated = await client.query(
      `UPDATE order_revision
       SET status=$3::varchar,
           submitted_at=NOW(),
           approved_at=CASE WHEN $3::varchar='APPROVED' THEN NOW() ELSE approved_at END
       WHERE id=$1 AND order_id=$2
       RETURNING *`,
      [Number(revisionId), Number(orderId), nextStatus]
    );
    await insertRevisionEventTx(client, {
      revisionId,
      orderId,
      ticketId: revision.support_ticket_id,
      actorUserId,
      actorRole: normalizeRole(actorRole),
      eventType: "submitted",
      fromStatus: revision.status,
      toStatus: nextStatus,
      metadata: { approvalsRequired: required },
    });
    await client.query("COMMIT");
    const out = await getRevisionDetails({ orderId, revisionId });
    notifyRevisionSubmitted(updated.rows[0]);
    return out;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

function approvalsComplete(approvals) {
  return approvals.every((row) => row.status === "APPROVED");
}

function statusAfterApprovals(approvals) {
  if (approvalsComplete(approvals)) return "APPROVED";
  const pending = approvals.filter((row) => row.status === "PENDING").map((row) => row.approval_type);
  return nextAwaitingStatus(pending);
}

async function decideApproval({ orderId, revisionId, actorUserId, actorRole, approvalType, status, note }) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const revisionResult = await client.query(
      `SELECT * FROM order_revision WHERE id=$1 AND order_id=$2 FOR UPDATE`,
      [Number(revisionId), Number(orderId)]
    );
    const revision = revisionResult.rows[0];
    if (!revision) throw new AppError("ORDER_REVISION_NOT_FOUND", { status: 404 });
    if (!["AWAITING_CUSTOMER", "AWAITING_MERCHANT", "AWAITING_BOTH"].includes(revision.status)) {
      throw new AppError("ORDER_REVISION_APPROVAL_INVALID_STATE", { status: 409 });
    }
    const order = await loadOrderForRevisionTx(client, orderId, { lock: true });
    if (
      approvalType === "CUSTOMER" &&
      Number(order.customer_user_id) !== Number(actorUserId)
    ) {
      throw new AppError("ORDER_REVISION_APPROVAL_FORBIDDEN", { status: 403 });
    }
    if (
      approvalType === "MERCHANT" &&
      Number(order.owner_user_id) !== Number(actorUserId)
    ) {
      throw new AppError("ORDER_REVISION_APPROVAL_FORBIDDEN", { status: 403 });
    }
    const approval = await client.query(
      `UPDATE order_revision_approval
       SET status=$3,
           approver_user_id=$4,
           decision_note=$5,
           decided_at=NOW()
       WHERE revision_id=$1
         AND approval_type=$2
         AND status='PENDING'
       RETURNING *`,
      [Number(revisionId), approvalType, status, Number(actorUserId), note]
    );
    if (!approval.rows[0]) {
      throw new AppError("ORDER_REVISION_APPROVAL_NOT_PENDING", { status: 409 });
    }
    const approvals = await client.query(
      `SELECT * FROM order_revision_approval WHERE revision_id=$1 ORDER BY id ASC`,
      [Number(revisionId)]
    );
    const nextStatus = status === "REJECTED" ? "REJECTED" : statusAfterApprovals(approvals.rows);
    const updated = await client.query(
      `UPDATE order_revision
       SET status=$3::varchar,
           approved_at=CASE WHEN $3::varchar='APPROVED' THEN NOW() ELSE approved_at END,
           rejected_at=CASE WHEN $3::varchar='REJECTED' THEN NOW() ELSE rejected_at END,
           approval_state_json=$4::jsonb
       WHERE id=$1 AND order_id=$2
       RETURNING *`,
      [
        Number(revisionId),
        Number(orderId),
        nextStatus,
        json({ approvals: approvals.rows }, {}),
      ]
    );
    await insertRevisionEventTx(client, {
      revisionId,
      orderId,
      ticketId: revision.support_ticket_id,
      actorUserId,
      actorRole: normalizeRole(actorRole),
      eventType: status === "APPROVED" ? "approval_granted" : "approval_rejected",
      fromStatus: revision.status,
      toStatus: nextStatus,
      metadata: { approvalType, note },
    });
    await client.query("COMMIT");
    const out = await getRevisionDetails({ orderId, revisionId });
    notifyRevisionDecision(updated.rows[0], approvalType, status);
    return out;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export function customerApprove({ orderId, revisionId, userId, note }) {
  return decideApproval({
    orderId,
    revisionId,
    actorUserId: userId,
    actorRole: "customer",
    approvalType: "CUSTOMER",
    status: "APPROVED",
    note,
  });
}

export function merchantApprove({ orderId, revisionId, ownerUserId, note }) {
  return decideApproval({
    orderId,
    revisionId,
    actorUserId: ownerUserId,
    actorRole: "owner",
    approvalType: "MERCHANT",
    status: "APPROVED",
    note,
  });
}

export function rejectRevision({ orderId, revisionId, userId, role, note }) {
  const approvalType = normalizeRole(role) === "owner" ? "MERCHANT" : "CUSTOMER";
  return decideApproval({
    orderId,
    revisionId,
    actorUserId: userId,
    actorRole: role,
    approvalType,
    status: "REJECTED",
    note,
  });
}

async function applyStockDeltaTx(client, delta) {
  if (Number(delta.delta) === 0) return;
  if (Number(delta.delta) > 0) {
    if (delta.variantId != null) {
      const out = await client.query(
        `UPDATE product_variant
         SET stock_quantity = stock_quantity - $2, updated_at = NOW()
         WHERE id = $1
           AND is_available = TRUE
           AND stock_quantity >= $2
         RETURNING id`,
        [Number(delta.variantId), Number(delta.delta)]
      );
      if (!out.rows[0]) throw new AppError("PRODUCT_OUT_OF_STOCK", { status: 409 });
      return;
    }
    const out = await client.query(
      `UPDATE store_inventory_item
       SET quantity = quantity - $2,
           stock_status = CASE
             WHEN quantity - $2 <= 0 THEN 'out_of_stock'
             WHEN quantity - $2 <= COALESCE(reorder_threshold, 0) THEN 'low_stock'
             ELSE 'in_stock'
           END,
           last_quantity_update_at = NOW(),
           updated_at = NOW()
       WHERE merchant_id = (SELECT merchant_id FROM product WHERE id=$1)
         AND product_id = $1
         AND manual_disabled = FALSE
         AND quantity >= $2
       RETURNING id`,
      [Number(delta.productId), Number(delta.delta)]
    );
    if (!out.rows[0]) throw new AppError("PRODUCT_OUT_OF_STOCK", { status: 409 });
    return;
  }

  const releaseQty = Math.abs(Number(delta.delta));
  if (delta.variantId != null) {
    await client.query(
      `UPDATE product_variant
       SET stock_quantity = stock_quantity + $2, updated_at = NOW()
       WHERE id = $1`,
      [Number(delta.variantId), releaseQty]
    );
    return;
  }
  await client.query(
    `UPDATE store_inventory_item
     SET quantity = quantity + $2,
         stock_status = CASE
           WHEN quantity + $2 <= COALESCE(reorder_threshold, 0) THEN 'low_stock'
           ELSE 'in_stock'
         END,
         auto_disabled = FALSE,
         last_quantity_update_at = NOW(),
         updated_at = NOW()
     WHERE product_id = $1`,
    [Number(delta.productId), releaseQty]
  );
}

async function replaceOrderItemsTx(client, { order, proposedItems }) {
  await client.query(`DELETE FROM order_item WHERE order_id=$1`, [Number(order.id)]);
  const inserted = [];
  for (const item of proposedItems) {
    const row = await client.query(
      `INSERT INTO order_item
         (order_id, product_id, product_name, base_unit_price, unit_price,
          quantity, selected_modifiers_json, selected_variant_json,
          selected_variant_options_json, display_snapshot_json,
          variant_price_delta_total, modifiers_unit_total, modifiers_line_total,
          line_discount_total, line_total, pricing_breakdown_json)
       VALUES ($1,$2,$3,$4,$5,$6,$7::jsonb,$8::jsonb,$9::jsonb,$10::jsonb,$11,$12,$13,$14,$15,$16::jsonb)
       RETURNING *`,
      [
        Number(order.id),
        Number(item.productId),
        item.productName,
        item.baseUnitPrice,
        item.unitPrice,
        Number(item.quantity),
        json(item.selectedModifiers, []),
        json(item.selectedVariantSnapshot, {}),
        json(item.selectedVariantOptions, []),
        json(item.displaySnapshot, {}),
        0,
        0,
        0,
        0,
        item.lineTotal,
        json(item.pricingBreakdown, {}),
      ]
    );
    const insertedItem = row.rows[0];
    inserted.push(insertedItem);
    await client.query(
      `INSERT INTO inventory_reservation
         (order_id, order_item_id, merchant_id, product_id, variant_id, variant_signature,
          quantity, status, expires_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,'pending', NOW() + interval '30 minutes')
       ON CONFLICT (order_item_id) DO NOTHING`,
      [
        Number(order.id),
        Number(insertedItem.id),
        Number(order.merchant_id),
        Number(item.productId),
        item.variantId == null ? null : Number(item.variantId),
        item.variantSignature || null,
        Number(item.quantity),
      ]
    );
  }
  return inserted;
}

async function updateInvoiceTx(client, { order, totals, revision }) {
  const invoice = await client.query(
    `SELECT *
     FROM merchant_receivable_invoice
     WHERE order_id=$1
     FOR UPDATE`,
    [Number(order.id)]
  );
  if (!invoice.rows[0]) return null;
  const paidAmount = toMoney(invoice.rows[0].paid_amount);
  const outstandingAmount = toMoney(Math.max(0, totals.totalAmount - paidAmount));
  const status =
    outstandingAmount <= 0
      ? "paid"
      : paidAmount > 0
        ? "partially_paid"
        : "unpaid";
  const updated = await client.query(
    `UPDATE merchant_receivable_invoice
     SET order_status=$2,
         subtotal=$3,
         commission_amount=$4,
         service_fee_amount=$5,
         app_delivery_fee_amount=$6,
         store_delivery_fee_amount=$7,
         app_receivable_amount=$8,
         store_net_amount=$9,
         store_net_received_amount=$10,
         app_due_from_delivery=$11,
         difference_amount=$12,
         difference_reason=$13,
         outstanding_amount=$14,
         invoice_status=$15,
         updated_at=NOW()
     WHERE id=$1
     RETURNING *`,
    [
      Number(invoice.rows[0].id),
      order.status_text,
      totals.subtotal,
      totals.financialSnapshot.commissionAmount || 0,
      totals.financialSnapshot.serviceFeeAmount || 0,
      totals.financialSnapshot.appDeliveryFeeAmount || 0,
      totals.financialSnapshot.storeDeliveryFeeAmount || 0,
      totals.financialSnapshot.appReceivableAmount || 0,
      totals.financialSnapshot.storeNetAmount || 0,
      totals.financialSnapshot.storeNetReceivedAmount || 0,
      totals.financialSnapshot.appDueFromDelivery || 0,
      totals.financialSnapshot.differenceAmount || 0,
      `order revision ${revision.id}`,
      outstandingAmount,
      status,
    ]
  );
  return updated.rows[0] || null;
}

export async function applyRevision({ orderId, revisionId, actorUserId, actorRole }) {
  const client = await pool.connect();
  let appliedRevision = null;
  try {
    await client.query("BEGIN");
    const revisionResult = await client.query(
      `SELECT * FROM order_revision WHERE id=$1 AND order_id=$2 FOR UPDATE`,
      [Number(revisionId), Number(orderId)]
    );
    const revision = revisionResult.rows[0];
    if (!revision) throw new AppError("ORDER_REVISION_NOT_FOUND", { status: 404 });
    if (revision.status === "APPLIED") {
      await client.query("COMMIT");
      return getRevisionDetails({ orderId, revisionId });
    }
    if (revision.status !== "APPROVED") {
      throw new AppError("ORDER_REVISION_APPLY_INVALID_STATE", { status: 409 });
    }
    const order = await loadOrderForRevisionTx(client, orderId, { lock: true });
    if (!orderStatusIsEditable(order.status_text)) {
      throw new AppError("ORDER_REVISION_ORDER_NOT_EDITABLE", { status: 409 });
    }
    if (Number(order.order_revision_version || 1) !== Number(revision.base_order_version)) {
      throw new AppError("ORDER_REVISION_CONFLICT", { status: 409 });
    }
    await client.query(
      `UPDATE order_revision
       SET status='APPLYING'
       WHERE id=$1`,
      [Number(revisionId)]
    );
    for (const delta of asArray(revision.inventory_effect_json?.deltas)) {
      await applyStockDeltaTx(client, delta);
    }
    await replaceOrderItemsTx(client, {
      order,
      proposedItems: asArray(revision.proposed_items_json),
    });
    const totals = revision.proposed_totals_json || {};
    await client.query(
      `UPDATE customer_order
       SET gross_subtotal=$2,
           product_discount_total=$3,
           coupon_discount_total=$4,
           subtotal=$5,
           service_fee=$6,
           delivery_fee=$7,
           delivery_fee_raw=$8,
           total_amount=$9,
           pricing_breakdown_json=$10::jsonb,
           financial_config_snapshot_json=$11::jsonb,
           note=COALESCE($12, note),
           order_revision_version = order_revision_version + 1,
           last_order_revision_id=$13,
           last_order_revision_applied_at=NOW(),
           updated_at=NOW()
       WHERE id=$1`,
      [
        Number(order.id),
        totals.grossSubtotal || totals.subtotal || 0,
        totals.productDiscountTotal || 0,
        totals.couponDiscountTotal || 0,
        totals.subtotal || 0,
        totals.serviceFee || 0,
        totals.deliveryFee || 0,
        totals.deliveryFeeRaw || totals.deliveryFee || 0,
        totals.totalAmount || 0,
        json(totals.pricingBreakdown, {}),
        json(totals.financialSnapshot, {}),
        revision.metadata_json?.note ?? null,
        Number(revisionId),
      ]
    );
    const invoice = await updateInvoiceTx(client, { order, totals, revision });
    const adjustment = revision.payment_effect_json || {};
    await client.query(
      `INSERT INTO order_revision_financial_adjustment
         (revision_id, order_id, adjustment_type, amount, direction, payment_method,
          status, metadata_json)
       VALUES ($1,$2,$3,$4,$5,$6,'RECORDED',$7::jsonb)`,
      [
        Number(revisionId),
        Number(order.id),
        adjustment.adjustmentType || "NO_CHANGE",
        Math.abs(toMoney(revision.price_difference)),
        adjustment.direction || "none",
        order.payment_method || null,
        json({ invoiceId: invoice?.id || null }, {}),
      ]
    );
    const updated = await client.query(
      `UPDATE order_revision
       SET status='APPLIED',
           applied_at=NOW()
       WHERE id=$1
       RETURNING *`,
      [Number(revisionId)]
    );
    appliedRevision = updated.rows[0];
    await insertRevisionEventTx(client, {
      revisionId,
      orderId,
      ticketId: revision.support_ticket_id,
      actorUserId,
      actorRole: normalizeRole(actorRole),
      eventType: "applied",
      fromStatus: "APPROVED",
      toStatus: "APPLIED",
      metadata: {
        priceDifference: toMoney(revision.price_difference),
        invoiceId: invoice?.id || null,
      },
    });
    await client.query("COMMIT");
    const out = await getRevisionDetails({ orderId, revisionId });
    notifyRevisionApplied(appliedRevision, order);
    return out;
  } catch (error) {
    await client.query("ROLLBACK").catch(() => {});
    if (appliedRevision == null) {
      await q(
        `UPDATE order_revision
         SET status='FAILED',
             failed_at=NOW(),
             failure_reason=$2
         WHERE id=$1
           AND status='APPLYING'`,
        [Number(revisionId), String(error?.message || error).slice(0, 500)]
      ).catch(() => {});
      notifyRevisionFailed({ orderId, revisionId, actorUserId, error });
    }
    throw error;
  } finally {
    client.release();
  }
}

async function loadNotificationOrder(orderId) {
  const result = await q(
    `SELECT o.id, o.customer_user_id, o.delivery_user_id, o.merchant_id, m.owner_user_id
     FROM customer_order o
     JOIN merchant m ON m.id = o.merchant_id
     WHERE o.id=$1
     LIMIT 1`,
    [Number(orderId)]
  );
  return result.rows[0] || null;
}

function notifyRevisionCreated(revision) {
  notifyUser({
    userId: revision.created_by_user_id,
    role: "admin",
    type: "order.revision.created",
    title: "Order revision draft created",
    body: `Order #${revision.order_id} revision draft is ready.`,
    revision,
  });
}

function notifyRevisionSubmitted(revision) {
  loadNotificationOrder(revision.order_id)
    .then((order) => {
      const required = asArray(revision.approvals_required_json);
      notifyUser({
        userId: revision.created_by_user_id,
        role: "admin",
        type: "order.revision.submitted",
        title: "Order revision submitted",
        body: `Order #${revision.order_id} revision is awaiting approval.`,
        revision,
        order,
        extra: { approvalsRequired: required },
      });
      if (required.includes("CUSTOMER")) {
        notifyUser({
          userId: order?.customer_user_id,
          role: "customer",
          type: "order.revision.awaiting_customer",
          title: "Order update needs your approval",
          body: `Review the proposed change for order #${revision.order_id}.`,
          revision,
          order,
          extra: { approvalType: "CUSTOMER" },
        });
      }
      if (required.includes("MERCHANT")) {
        notifyUser({
          userId: order?.owner_user_id,
          role: "owner",
          type: "order.revision.awaiting_merchant",
          title: "Order update needs store approval",
          body: `Review the proposed change for order #${revision.order_id}.`,
          revision,
          order,
          extra: { approvalType: "MERCHANT" },
        });
      }
    })
    .catch((error) => {
      console.warn("[order-revisions] submitted notification failed", error?.message || error);
    });
}

function notifyRevisionDecision(revision, approvalType, decision) {
  loadNotificationOrder(revision.order_id)
    .then((order) => {
      const type = decision === "REJECTED"
        ? "order.revision.rejected"
        : `order.revision.${approvalType.toLowerCase()}_approved`;
      notifyUser({
        userId: revision.created_by_user_id,
        role: "admin",
        type,
        title: "Order revision decision",
        body: `Order #${revision.order_id}: ${approvalType} ${decision.toLowerCase()}.`,
        revision,
        order,
        extra: { approvalType, decision },
      });
      const otherUserId = approvalType === "CUSTOMER"
        ? order?.owner_user_id
        : order?.customer_user_id;
      const otherRole = approvalType === "CUSTOMER" ? "owner" : "customer";
      notifyUser({
        userId: otherUserId,
        role: otherRole,
        type,
        title: "Order revision decision",
        body: `Order #${revision.order_id}: ${approvalType} ${decision.toLowerCase()}.`,
        revision,
        order,
        extra: { approvalType, decision },
      });
    })
    .catch((error) => {
      console.warn("[order-revisions] decision notification failed", error?.message || error);
    });
}

function notifyRevisionApplied(revision, order) {
  for (const recipient of [
    { userId: order.customer_user_id, role: "customer" },
    { userId: order.owner_user_id, role: "owner" },
    { userId: order.delivery_user_id, role: "delivery" },
    { userId: revision.created_by_user_id, role: "admin" },
  ]) {
    notifyUser({
      userId: recipient.userId,
      role: recipient.role,
      type: "order.revision.applied",
      title: "Order updated",
      body: `Order #${revision.order_id} was updated by support.`,
      revision,
      order,
    });
  }
}

function notifyRevisionFailed({ orderId, revisionId, actorUserId, error }) {
  const revision = {
    id: Number(revisionId),
    order_id: Number(orderId),
    support_ticket_id: null,
    status: "FAILED",
    price_difference: 0,
    created_by_user_id: actorUserId,
  };
  notifyUser({
    userId: actorUserId,
    role: "admin",
    type: "order.revision.failed",
    title: "Order revision failed",
    body: `Order #${orderId} revision could not be applied.`,
    revision,
    extra: { failureReason: String(error?.message || error).slice(0, 160) },
  });
}

export const __orderRevisionTestables = Object.freeze({
  approvalRequirements,
  computeItemActions,
  summarizeInventoryEffect,
  calculateTotals,
  orderStatusIsEditable,
});

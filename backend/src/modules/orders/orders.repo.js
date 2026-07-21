import { pool, q } from "../../config/db.js";
import { env } from "../../config/env.js";
import {
  buildDeliveryCashSettlementSnapshot,
  computeOrderFinancialSnapshot,
  evaluateCourierEndDayReadiness,
  getMerchantBillingProfile,
} from "../commerce/merchant-financial.logic.js";
import { insertOpsAuditLog } from "../../ops/auditLog.js";
import {
  calcDiscount,
  validateCouponByIdOrCode,
} from "../coupons/coupons.repo.js";
import {
  applyMerchantOfferPricing,
} from "../owner/merchant-offers.logic.js";
import {
  listLatestEligibleOffersByProductIds,
  markOfferUsageByOrderTx,
} from "../owner/merchant-offers.repo.js";
import {
  listActiveMerchantNotificationRecipients,
} from "../owner/owner.repo.js";
import {
  extractRichCatalogFromMetadata,
  normalizeVariantSelectionInput,
} from "../products/product-catalog.logic.js";
import {
  buildOrderItemDisplaySnapshot,
  hydrateOrderItemDisplaySnapshot,
} from "./order-item-snapshot.logic.js";
import {
  buildDeliveryAssignmentPresentation,
  DELIVERY_ASSIGNMENT_STATUSES,
  deriveDeliveryAssignmentStatus,
  isDeliveryAssignmentAssigned,
  isDeliveryAssignmentOpen,
  normalizeDeliveryAssignmentStatus,
} from "./delivery-assignment.logic.js";
import { requestDeliveryAssignmentRecovery } from "./delivery-assignment.worker.js";
import {
  ensureDeliveryJobForGroup,
  recomputeGroupReadiness,
} from "../delivery/delivery-job.service.js";
import { directAssignDeliveryOrderTx } from "../commerce/commerce.repo.js";
import crypto from "crypto";
import {
  consumeCouponRedemptionByOrderTx,
  syncOrderIncentiveConsumptionForStatusTx,
} from "./order-incentives.repo.js";
import { invalidateMerchantCatalogCache } from "../merchants/merchants.repo.js";

/**
 * Purpose:
 * repository الرئيسي للطلبات. يحتوي SQL والـ transactions المتعلقة بإنشاء
 * الطلبات، transitions الخاصة بالمالك والدلفري، التقارير، والمفضلات.
 *
 * Depends on:
 * - PostgreSQL عبر `pool/q`
 * - incentive/coupon/offer logic
 * - notifications fan-out بعد اكتمال transitions الحساسة
 *
 * Critical notes:
 * - هذا الملف من أكثر الملفات حساسية في المنظومة لأن أي خلل فيه قد يسبب:
 *   خصم مخزون خاطئ، order status desync، أو إشعارات غير متوافقة مع الحالة.
 * - العمليات الحرجة يجب أن تبقى داخل transaction واحدة أو contract واضح.
 *
 * Maintenance notes:
 * - عند أعطال الطلبات ابدأ من هنا بعد service/controller، خصوصاً:
 *   `createOrderWithItems`, `updateOwnerOrderStatus`, `claimDeliveryOrder`.
 */

// Product reviews

export async function findEligibleOrderForProductReview(
  customerId,
  productId,
  { orderId = null } = {}
) {
  const params = [Number(customerId), Number(productId)];
  let orderFilter = "";
  if (orderId != null) {
    params.push(Number(orderId));
    orderFilter = `AND o.id = $${params.length}`;
  }
  const r = await q(
    `SELECT
       o.id AS order_id,
       o.merchant_id,
       o.created_at
     FROM customer_order o
     JOIN order_item oi ON oi.order_id = o.id
     WHERE o.customer_user_id = $1
       AND oi.product_id = $2
       AND o.status IN ('delivered', 'completed')
       ${orderFilter}
     ORDER BY o.created_at DESC, o.id DESC
     LIMIT 1`,
    params
  );
  return r.rows[0] || null;
}

export async function upsertProductReview(customerId, productId, { rating, body, orderId }) {
  const r = await q(
    `INSERT INTO product_review (customer_id, product_id, order_id, rating, body)
     VALUES ($1, $2, $3, $4, $5)
     ON CONFLICT (product_id, customer_id)
     DO UPDATE SET rating = EXCLUDED.rating,
                   body   = EXCLUDED.body,
                   order_id = COALESCE(EXCLUDED.order_id, product_review.order_id),
                   updated_at = NOW()
     RETURNING *`,
    [customerId, productId, orderId || null, rating, body || null]
  );
  return r.rows[0];
}

export async function listProductReviews(productId, { limit = 20, offset = 0 } = {}) {
  const r = await q(
    `SELECT
       pr.id,
       pr.rating,
       pr.body,
       pr.created_at,
       pr.updated_at,
       u.id          AS customer_id,
       u.full_name   AS customer_name,
       u.image_url   AS customer_image_url
     FROM product_review pr
     JOIN app_user u ON u.id = pr.customer_id
     WHERE pr.product_id = $1
     ORDER BY pr.created_at DESC
     LIMIT $2 OFFSET $3`,
    [productId, limit, offset]
  );
  return r.rows;
}

export async function getProductRatingSummary(productId) {
  const r = await q(
    `SELECT avg_rating, review_count
     FROM product_rating_summary
     WHERE product_id = $1`,
    [productId]
  );
  return r.rows[0] || { avg_rating: null, review_count: 0 };
}

export async function deleteProductReview(customerId, productId) {
  await q(
    `DELETE FROM product_review WHERE customer_id = $1 AND product_id = $2`,
    [customerId, productId]
  );
}

// End product reviews

import { createManyNotifications } from "../notifications/notifications.repo.js";
import { AppError } from "../../shared/utils/errors.js";
import {
  assertOwnerTransition,
  currentStatusRank,
  isDeliveryCurrentStatus,
  isOrderChatStatus,
  isOwnerCurrentStatus,
  statusText,
} from "./order-flow.logic.js";

const orderSelect = `
  SELECT
    o.*,
    m.name AS merchant_name,
    m.type AS merchant_type,
    m.activity_type AS merchant_activity_type,
    m.phone AS merchant_phone,
    m.owner_user_id AS owner_user_id,
    c.image_url AS customer_image_url,
    d.id AS delivery_id,
    d.full_name AS delivery_full_name,
    d.phone AS delivery_phone,
    d.image_url AS delivery_image_url,
    cp.driver_type AS delivery_driver_type,
    cp.rating AS delivery_rating,
    cp.availability_status AS delivery_availability_status,
    cp.coverage_block AS delivery_coverage_block,
    cp.vehicle_type AS delivery_vehicle_type,
    latest_ca.id AS delivery_assignment_id,
    latest_ca.status AS delivery_assignment_row_status,
    latest_ca.assigned_at AS delivery_assignment_assigned_at,
    latest_ca.ended_at AS delivery_assignment_ended_at,
    latest_ca.ended_reason AS delivery_assignment_ended_reason
  FROM customer_order o
  JOIN merchant m ON m.id = o.merchant_id
  LEFT JOIN app_user c ON c.id = o.customer_user_id
  LEFT JOIN app_user d ON d.id = o.delivery_user_id
  LEFT JOIN courier_profile cp ON cp.user_id = d.id
  LEFT JOIN LATERAL (
    SELECT
      ca.id,
      ca.status,
      ca.assigned_at,
      ca.ended_at,
      ca.ended_reason
    FROM courier_assignment ca
    WHERE ca.order_id = o.id
    ORDER BY ca.id DESC
    LIMIT 1
  ) latest_ca ON TRUE
`;

let merchantReviewNotificationOutboxWriter = defaultMerchantReviewNotificationOutboxWriter;

export function setMerchantReviewNotificationOutboxWriter(writer) {
  merchantReviewNotificationOutboxWriter =
    typeof writer === "function"
      ? writer
      : defaultMerchantReviewNotificationOutboxWriter;
}

async function insertMerchantReviewSocialPostTx(
  client,
  { customerUserId, merchantId, orderId, rating, review }
) {
  const result = await client.query(
    `INSERT INTO social_post
      (
        user_id,
        post_kind,
        caption,
        merchant_id,
        review_rating,
        verified_purchase,
        verified_purchase_order_id,
        verified_purchase_verified_at,
        audience_scope_type,
        audience_scope_code,
        moderation_status
      )
     VALUES ($1, 'merchant_review', $2, $3, $4, TRUE, $5, NOW(), 'global', NULL, 'approved')
     RETURNING id`,
    [
      Number(customerUserId),
      review || null,
      Number(merchantId),
      Number(rating),
      Number(orderId),
    ]
  );
  return result.rows[0] || null;
}

async function defaultMerchantReviewNotificationOutboxWriter(
  client,
  { orderId, merchantId, customerUserId, ownerUserId, rating, reviewPostId }
) {
  const owner = Number(ownerUserId);
  if (!Number.isFinite(owner) || owner <= 0) return null;
  const eventId = `merchant-review:${Number(merchantId)}:${Number(customerUserId)}`;
  await client.query(
    `INSERT INTO notification_outbox
       (event_id, event_type, recipient_user_id, target_surface,
        target_entity_type, target_entity_id, payload_json, priority)
     VALUES ($1,$2,$3,'store','merchant_review',$4,$5,'high')
     ON CONFLICT (event_id) DO NOTHING`,
    [
      eventId,
      "MERCHANT_REVIEW_CREATED",
      owner,
      Number(reviewPostId),
      JSON.stringify({
        orderId: Number(orderId),
        merchantId: Number(merchantId),
        customerUserId: Number(customerUserId),
        reviewPostId: Number(reviewPostId),
        rating: Number(rating),
        requiresAction: true,
      }),
    ]
  );
  return eventId;
}

function toNumberOrNull(value) {
  if (value == null || value === "") return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function roundMoney(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return 0;
  return Math.round((parsed + Number.EPSILON) * 100) / 100;
}

function normalizePositiveInteger(value) {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : null;
}

function resolveGroupedCheckoutSequence(storeOrder = {}, fallbackIndex = 0) {
  return (
    normalizePositiveInteger(storeOrder.store_sequence ?? storeOrder.storeSequence) ??
    fallbackIndex + 1
  );
}

function resolveGroupedFeeSequence(storeOrder = {}, checkoutSequence = null, fallbackIndex = 0) {
  return (
    normalizePositiveInteger(storeOrder.pickup_sequence ?? storeOrder.pickupSequence) ??
    normalizePositiveInteger(storeOrder.store_sequence ?? storeOrder.storeSequence) ??
    checkoutSequence ??
    fallbackIndex + 1
  );
}

function buildGroupedDeliveryFeePlan(entries) {
  if (!Array.isArray(entries) || entries.length === 0) {
    return {
      entries: [],
      orderedEntries: [],
      rawDeliveryFeeTotal: 0,
      allocatedDeliveryFeeTotal: 0,
    };
  }

  const normalized = entries.map((entry, originalIndex) => {
    const checkoutSequence = resolveGroupedCheckoutSequence(
      entry.storeOrder || {},
      originalIndex
    );
    const feeSequence = resolveGroupedFeeSequence(
      entry.storeOrder || {},
      checkoutSequence,
      originalIndex
    );
    const feeSequenceSource = normalizePositiveInteger(
      entry.storeOrder?.pickup_sequence ?? entry.storeOrder?.pickupSequence
    ) != null
      ? "pickup_sequence"
      : normalizePositiveInteger(
          entry.storeOrder?.store_sequence ?? entry.storeOrder?.storeSequence
        ) != null
        ? "store_sequence"
        : "creation_order";
    return {
      ...entry,
      originalIndex,
      checkoutSequence,
      feeSequence,
      feeSequenceSource,
    };
  });

  const orderedEntries = [...normalized].sort((a, b) => {
    const sourceRank = {
      pickup_sequence: 0,
      store_sequence: 1,
      creation_order: 2,
    };
    const rankDiff = (sourceRank[a.feeSequenceSource] ?? 2) - (sourceRank[b.feeSequenceSource] ?? 2);
    if (rankDiff !== 0) return rankDiff;
    const feeDiff = Number(a.feeSequence || 0) - Number(b.feeSequence || 0);
    if (feeDiff !== 0) return feeDiff;
    return Number(a.originalIndex || 0) - Number(b.originalIndex || 0);
  });

  const plansByOriginalIndex = new Array(normalized.length);
  let rawDeliveryFeeTotal = 0;
  let allocatedDeliveryFeeTotal = 0;

  for (let sortedIndex = 0; sortedIndex < orderedEntries.length; sortedIndex += 1) {
    const entry = orderedEntries[sortedIndex];
    const multiplier = sortedIndex === 0 ? 1 : sortedIndex === 1 ? 0.5 : 0.25;
    const rawDeliveryFee = roundMoney(entry.rawDeliveryFee || 0);
    const allocatedDeliveryFee = roundMoney(rawDeliveryFee * multiplier);
    const totalAmount = roundMoney(
      Number(entry.subtotalAfterAllDiscounts || 0) +
        Number(entry.serviceFee || 0) +
        allocatedDeliveryFee
    );
    const planned = {
      ...entry,
      deliveryFeeMultiplier: multiplier,
      rawDeliveryFee,
      allocatedDeliveryFee,
      deliveryFee: allocatedDeliveryFee,
      totalAmount,
      checkoutSequence: Number(entry.checkoutSequence || entry.originalIndex + 1),
      feeSequence: Number(entry.feeSequence || entry.originalIndex + 1),
    };
    rawDeliveryFeeTotal = roundMoney(rawDeliveryFeeTotal + rawDeliveryFee);
    allocatedDeliveryFeeTotal = roundMoney(
      allocatedDeliveryFeeTotal + allocatedDeliveryFee
    );
    plansByOriginalIndex[entry.originalIndex] = planned;
  }

  return {
    entries: plansByOriginalIndex,
    orderedEntries: orderedEntries.map((entry, sortedIndex) => {
      const planned = plansByOriginalIndex[entry.originalIndex];
      return {
        ...planned,
        allocationOrder: sortedIndex + 1,
      };
    }),
    rawDeliveryFeeTotal,
    allocatedDeliveryFeeTotal,
  };
}

function mapCourierPresence(row) {
  if (!row || row.latitude == null || row.longitude == null) return null;
  return {
    courierUserId: Number(row.courier_user_id),
    currentOrderId: row.current_order_id == null ? null : Number(row.current_order_id),
    latitude: Number(row.latitude),
    longitude: Number(row.longitude),
    headingDeg: toNumberOrNull(row.heading_deg),
    speedKmh: toNumberOrNull(row.speed_kmh),
    accuracyM: toNumberOrNull(row.accuracy_m),
    isOnline: row.is_online !== false,
    recordedAt: row.recorded_at || null,
    updatedAt: row.updated_at || null,
  };
}

function buildOrderTrackingStage(order) {
  const status = String(order?.status || "").trim().toLowerCase();
  const customerConfirmedAt = order?.customer_confirmed_at || order?.customerConfirmedAt;
  switch (status) {
    case "pending":
      return "order_placed";
    case "approved":
      return "order_accepted";
    case "preparing":
    case "courier_requested":
    case "courier_assigned":
      return "being_prepared";
    case "ready_for_delivery":
    case "ready_for_pickup":
      return "ready_for_pickup";
    case "on_the_way":
    case "picked_up":
      return "heading_to_customer";
    case "arrived":
      return "near_customer";
    case "delivered":
    case "delivered_by_courier":
    case "received_by_customer":
    case "completed":
      return "delivered";
    case "cancelled":
    case "cancelled_by_customer":
    case "cancelled_by_store":
    case "cancelled_by_admin":
      return "cancelled";
    default:
      return "order_placed";
  }
}

function createPublicOrderShareToken() {
  return `ord_${crypto.randomBytes(24).toString("hex")}`;
}

function periodStartExpression(period) {
  switch (period) {
    case "day":
      return "DATE_TRUNC('day', NOW())";
    case "week":
      return "DATE_TRUNC('week', NOW())";
    case "month":
      return "DATE_TRUNC('month', NOW())";
    case "year":
      return "DATE_TRUNC('year', NOW())";
    case "all":
      return null;
    default:
      return null;
  }
}

function normalizeReportPeriod(period) {
  const normalized = String(period || "day").trim().toLowerCase();
  switch (normalized) {
    // Canonical values.
    case "day":
    case "week":
    case "month":
    case "year":
    case "all":
      return normalized;
    // Accepted aliases so the dashboard/report surfaces can send friendlier
    // labels without tripping INVALID_PERIOD. All map to a canonical bucket.
    case "today":
      return "day";
    case "total":
    case "lifetime":
    case "all_time":
    case "alltime":
      return "all";
    default:
      return null;
  }
}

function buildReportTimeFilter(period, column = "o.created_at") {
  const since = periodStartExpression(normalizeReportPeriod(period));
  return since ? `${column} >= ${since}` : null;
}

function normalizeAdminOrderOverviewStatus(status) {
  const normalized = String(status || "all").trim().toLowerCase();
  switch (normalized) {
    case "completed":
    case "cancelled":
    case "in_progress":
    case "all":
      return normalized;
    default:
      return "all";
  }
}

function normalizeAdminOverviewPeriod(period) {
  const normalized = String(period || "all").trim().toLowerCase();
  switch (normalized) {
    case "all":
    case "day":
    case "week":
    case "month":
    case "year":
    case "custom":
      return normalized;
    default:
      return "all";
  }
}

function appendAdminOrderDateWindow({
  clauses,
  params,
  alias = "o",
  period,
  from,
  to,
}) {
  const normalizedPeriod = normalizeAdminOverviewPeriod(period);
  if (normalizedPeriod === "all") return;

  if (normalizedPeriod === "custom") {
    const fromDate = from ? new Date(from) : null;
    const toDate = to ? new Date(to) : null;
    if (from && (!fromDate || Number.isNaN(fromDate.getTime()))) {
      throw new AppError("INVALID_FROM_DATE", 400);
    }
    if (to && (!toDate || Number.isNaN(toDate.getTime()))) {
      throw new AppError("INVALID_TO_DATE", 400);
    }
    if (fromDate) {
      params.push(fromDate.toISOString());
      clauses.push(`${alias}.created_at >= $${params.length}`);
    }
    if (toDate) {
      params.push(toDate.toISOString());
      clauses.push(`${alias}.created_at <= $${params.length}`);
    }
    return;
  }

  const since = periodStartExpression(normalizedPeriod);
  if (!since) return;
  clauses.push(`${alias}.created_at >= ${since}`);
}

function adminOrderStatusFilterSql(status, alias = "o") {
  const normalized = normalizeAdminOrderOverviewStatus(status);
  switch (normalized) {
    case "completed":
      return `${alias}.status IN ('delivered', 'delivered_by_courier', 'received_by_customer', 'completed')`;
    case "cancelled":
      return `${alias}.status IN ('cancelled', 'cancelled_by_store', 'cancelled_by_admin', 'cancelled_by_customer')`;
    case "in_progress":
      return `${alias}.status NOT IN ('delivered', 'delivered_by_courier', 'received_by_customer', 'completed', 'cancelled', 'cancelled_by_store', 'cancelled_by_admin', 'cancelled_by_customer')`;
    case "all":
    default:
      return "1=1";
  }
}

async function attachItems(orderRows) {
  if (!orderRows.length) return [];

  const ids = orderRows.map((o) => o.id);
  const columns = await getTableColumns("order_item");
  const displaySnapshotSql = columns.has("display_snapshot_json")
    ? "display_snapshot_json"
    : "NULL::jsonb AS display_snapshot_json";
  const itemsResult = await q(
    `SELECT
       id,
       order_id,
       product_id,
       product_name,
       ${displaySnapshotSql},
       base_unit_price,
       unit_price,
       quantity,
       selected_modifiers_json,
       selected_variant_json,
       selected_variant_options_json,
       variant_price_delta_total,
       line_discount_total,
       line_total,
       pricing_breakdown_json
     FROM order_item
     WHERE order_id = ANY($1::bigint[])
     ORDER BY id ASC`,
    [ids]
  );

  const map = new Map();
  for (const item of itemsResult.rows) {
    const key = String(item.order_id);
    const list = map.get(key) || [];
    list.push(item);
    map.set(key, list);
  }

  const orderMap = new Map(orderRows.map((row) => [String(row.id), row]));

  return orderRows.map((row) => {
    const items = (map.get(String(row.id)) || []).map((item) =>
      hydrateOrderItemDisplaySnapshot(item, orderMap.get(String(row.id)))
    );
    return {
      ...row,
      items,
    };
  });
}

const tableColumnsCache = new Map();

async function getTableColumns(tableName) {
  const key = String(tableName || "").trim().toLowerCase();
  if (!key) return new Set();
  if (tableColumnsCache.has(key)) {
    return tableColumnsCache.get(key);
  }
  const result = await q(
    `SELECT column_name
     FROM information_schema.columns
     WHERE table_name = $1
       AND table_schema = ANY(current_schemas(false))`,
    [key]
  );
  const out = new Set(
    result.rows
      .map((row) => String(row.column_name || "").trim().toLowerCase())
      .filter(Boolean)
  );
  tableColumnsCache.set(key, out);
  return out;
}

async function getTableColumnsTx(client, tableName) {
  const key = String(tableName || "").trim().toLowerCase();
  if (!key) return new Set();
  if (tableColumnsCache.has(key)) {
    return tableColumnsCache.get(key);
  }
  const result = await client.query(
    `SELECT column_name
     FROM information_schema.columns
     WHERE table_name = $1
       AND table_schema = ANY(current_schemas(false))`,
    [key]
  );
  const out = new Set(
    result.rows
      .map((row) => String(row.column_name || "").trim().toLowerCase())
      .filter(Boolean)
  );
  tableColumnsCache.set(key, out);
  return out;
}

function assertRequiredColumns(tableName, availableColumns, requiredColumns) {
  const missing = (requiredColumns || []).filter(
    (column) => !availableColumns.has(String(column || "").toLowerCase())
  );
  if (missing.length <= 0) return;
  throw new AppError("ORDER_SCHEMA_INCOMPATIBLE", {
    status: 500,
    expose: false,
    details: {
      table: tableName,
      missingColumns: missing,
    },
  });
}

function buildDynamicInsertParts({ availableColumns, candidates }) {
  const insertColumns = [];
  const insertValues = [];
  for (const [column, value] of candidates || []) {
    if (!availableColumns.has(column)) continue;
    insertColumns.push(column);
    insertValues.push(value);
  }
  const placeholders = insertValues.map((_, index) => `$${index + 1}`).join(",");
  return {
    insertColumns,
    insertValues,
    placeholders,
  };
}

async function loadProductVariantCatalogTx(client, productIds) {
  const normalizedIds = Array.from(
    new Set(
      (productIds || [])
        .map((value) => Number(value))
        .filter((value) => Number.isInteger(value) && value > 0)
    )
  );
  if (!normalizedIds.length) return new Map();

  const result = await client.query(
    `SELECT
       g.id AS group_id,
       g.product_id,
       g.group_code,
       g.label_ar AS group_label_ar,
       g.label_en AS group_label_en,
       g.display_mode,
       g.selection_mode,
       g.required,
       g.sort_order AS group_sort_order,
       g.metadata_json AS group_metadata_json,
       o.id AS option_id,
       o.option_code,
       o.label_ar AS option_label_ar,
       o.label_en AS option_label_en,
       o.swatch_hex,
       o.price_delta,
       o.image_url,
       o.is_available,
       o.sort_order AS option_sort_order,
       o.metadata_json AS option_metadata_json
     FROM product_variant_group g
     LEFT JOIN product_variant_option o
       ON o.group_id = g.id
     WHERE g.product_id = ANY($1::bigint[])
     ORDER BY g.product_id ASC, g.sort_order ASC, g.id ASC, o.sort_order ASC, o.id ASC`,
    [normalizedIds]
  );

  const byProductId = new Map();
  for (const row of result.rows) {
    const productId = Number(row.product_id);
    let catalog = byProductId.get(productId);
    if (!catalog) {
      catalog = {
        groups: [],
        groupByCode: new Map(),
        variants: [],
        variantBySignature: new Map(),
        hasVariants: false,
      };
      byProductId.set(productId, catalog);
    }

    const groupId = Number(row.group_id);
    let group = catalog.groups.find((entry) => Number(entry.groupId) === groupId);
    if (!group) {
      group = {
        groupId,
        groupCode: row.group_code,
        labelAr: row.group_label_ar || null,
        labelEn: row.group_label_en || null,
        displayMode: row.display_mode || "chips",
        selectionMode: row.selection_mode || "single",
        required: row.required === true,
        sortOrder: Number(row.group_sort_order || 0),
        metadata: row.group_metadata_json || {},
        options: [],
        optionByCode: new Map(),
        optionById: new Map(),
      };
      catalog.groups.push(group);
      catalog.groupByCode.set(String(group.groupCode || "").toLowerCase(), group);
      catalog.hasVariants = true;
    }

    if (row.option_id == null) continue;
    const option = {
      optionId: Number(row.option_id),
      optionCode: row.option_code,
      labelAr: row.option_label_ar || null,
      labelEn: row.option_label_en || null,
      swatchHex: row.swatch_hex || null,
      priceDelta: Number(row.price_delta || 0),
      imageUrl: row.image_url || null,
      isAvailable: row.is_available !== false,
      sortOrder: Number(row.option_sort_order || 0),
      metadata: row.option_metadata_json || {},
    };
    group.options.push(option);
    group.optionByCode.set(String(option.optionCode || "").toLowerCase(), option);
    group.optionById.set(Number(option.optionId), option);
  }

  const variantsResult = await client.query(
    `SELECT id, product_id, signature, selections_json, sku, barcode, material,
            price_override, discounted_price_override, stock_quantity, image_url,
            is_available, sort_order
     FROM product_variant
     WHERE product_id = ANY($1::bigint[])
     ORDER BY sort_order ASC, id ASC`,
    [normalizedIds]
  );
  for (const row of variantsResult.rows) {
    const productId = Number(row.product_id);
    let catalog = byProductId.get(productId);
    if (!catalog) {
      catalog = {
        groups: [], groupByCode: new Map(), variants: [],
        variantBySignature: new Map(), hasVariants: true,
      };
      byProductId.set(productId, catalog);
    }
    const variant = {
      variantId: Number(row.id), signature: String(row.signature || ""),
      selections: Array.isArray(row.selections_json) ? row.selections_json : [],
      sku: row.sku || null, barcode: row.barcode || null, material: row.material || null,
      priceOverride: row.price_override == null ? null : Number(row.price_override),
      discountedPriceOverride: row.discounted_price_override == null ? null : Number(row.discounted_price_override),
      stockQuantity: Math.max(0, Number(row.stock_quantity || 0)),
      imageUrl: row.image_url || null, isAvailable: row.is_available !== false,
    };
    catalog.variants.push(variant);
    catalog.variantBySignature.set(variant.signature, variant);
    catalog.hasVariants = true;
  }

  const fallbackResult = await client.query(
    `SELECT id, metadata_json
     FROM product
     WHERE id = ANY($1::bigint[])`,
    [normalizedIds]
  );
  for (const row of fallbackResult.rows) {
    const productId = Number(row.id);
    const existing = byProductId.get(productId);
    if (existing && existing.hasVariants) continue;
    const fallback = extractRichCatalogFromMetadata(row.metadata_json);
    if (!fallback.variantGroups.length) continue;
    const catalog = {
      groups: [],
      groupByCode: new Map(),
      variants: [],
      variantBySignature: new Map(),
      hasVariants: true,
    };
    for (const groupEntry of fallback.variantGroups) {
      const group = {
        groupId: Number(groupEntry.groupId || catalog.groups.length + 1),
        productId,
        groupCode: groupEntry.code,
        labelAr: groupEntry.labelAr || null,
        labelEn: groupEntry.labelEn || null,
        displayMode: groupEntry.displayMode || "chips",
        selectionMode: groupEntry.selectionMode || "single",
        required: groupEntry.required === true,
        sortOrder: Number(groupEntry.sortOrder || 0),
        metadata: groupEntry.metadata || {},
        options: [],
        optionByCode: new Map(),
        optionById: new Map(),
      };
      for (const optionEntry of groupEntry.options || []) {
        const option = {
          optionId: Number(optionEntry.optionId || group.optionByCode.size + 1),
          optionCode: optionEntry.code,
          labelAr: optionEntry.labelAr || null,
          labelEn: optionEntry.labelEn || null,
          swatchHex: optionEntry.swatchHex || null,
          priceDelta: Number(optionEntry.priceDelta || 0),
          imageUrl: optionEntry.imageUrl || null,
          isAvailable: optionEntry.isAvailable !== false,
          sortOrder: Number(optionEntry.sortOrder || 0),
          metadata: optionEntry.metadata || {},
        };
        group.options.push(option);
        group.optionByCode.set(String(option.optionCode || "").toLowerCase(), option);
        group.optionById.set(Number(option.optionId), option);
      }
      catalog.groups.push(group);
      catalog.groupByCode.set(String(group.groupCode || "").toLowerCase(), group);
    }
    byProductId.set(productId, catalog);
  }

  return byProductId;
}

/**
 * PRODUCT_OUT_OF_STOCK مع تفاصيل منظمة تكفي الواجهة لعرض رسالة مفهومة
 * (اسم المنتج واللون والمقاس والكمية المتاحة) بدل رسالة عامة.
 */
function productOutOfStockError({
  product,
  variantId = null,
  colorName = null,
  size = null,
  requestedQuantity = 0,
  availableQuantity = 0,
}) {
  const err = new Error("PRODUCT_OUT_OF_STOCK");
  err.status = 400;
  err.details = {
    reason: "OUT_OF_STOCK",
    productId: Number(product?.id) || null,
    productName: product?.name || null,
    variantId: variantId == null ? null : Number(variantId),
    colorName: colorName || null,
    size: size || null,
    requestedQuantity: Math.max(0, Number(requestedQuantity || 0)),
    availableQuantity: Math.max(0, Number(availableQuantity ?? 0)),
  };
  return err;
}

function productUnavailableError({
  product,
  variantId = null,
  colorName = null,
  size = null,
  reason = "UNAVAILABLE",
}) {
  const productName = product?.name || null;
  const userMessageAr = `${productName ? `المنتج "${productName}"` : "هذا المنتج"} غير متاح حالياً.`;
  const userMessageEn = `${productName ? `Product "${productName}"` : "This product"} is currently unavailable.`;
  const err = new Error("PRODUCT_UNAVAILABLE");
  err.status = 400;
  err.details = {
    reason,
    productId: Number(product?.id) || null,
    productName,
    variantId: variantId == null ? null : Number(variantId),
    colorName: colorName || null,
    size: size || null,
    requestedQuantity: 0,
    availableQuantity: 0,
    userMessageAr,
    userMessageEn,
  };
  return err;
}

/**
 * مخزون المنتج العام (store_inventory_item) يحكم المنتج البسيط فقط.
 * عندما يُحلّ العنصر إلى variant ملموس فإن مخزون الـ variant هو المرجع،
 * وصف المنتج العام (غالباً 0 لمنتجات الـ variants) يجب ألا يمنع البيع.
 */
function shouldApplyProductInventoryGate({
  variantResolution,
  inventoryEnabled,
  inventoryQuantity,
}) {
  if (variantResolution?.variantId) return false;
  return inventoryEnabled === true && inventoryQuantity != null;
}

function buildVariantSelectionSignature(selections) {
  return (selections || [])
    .map((entry) =>
      `${String(entry.groupCode || "").toLowerCase()}:${String(entry.optionCode || "").toLowerCase()}`
    )
    .sort()
    .join("|");
}

function buildSelectionsFromVariantCatalog(variantCatalog, variant) {
  const selections = [];
  for (const selection of Array.isArray(variant?.selections) ? variant.selections : []) {
    const groupCode = String(selection.groupCode || selection.group_code || "").toLowerCase();
    const optionCode = String(selection.optionCode || selection.option_code || "").toLowerCase();
    if (!groupCode || !optionCode) continue;
    const group = variantCatalog?.groupByCode?.get(groupCode);
    if (!group) continue;
    const option = group.optionByCode.get(optionCode);
    if (!option) continue;
    selections.push({
      groupCode: group.groupCode,
      groupLabel: group.labelAr || group.labelEn || group.groupCode,
      optionCode: option.optionCode,
      optionLabel: option.labelAr || option.labelEn || option.optionCode,
      optionId: Number(option.optionId),
      swatchHex: option.swatchHex || null,
      imageUrl: option.imageUrl || null,
      priceDelta: Number(option.priceDelta || 0),
    });
  }
  const normalized = normalizeVariantSelectionInput({ selections });
  const colorSelection =
    normalized.selections.find((entry) => String(entry.groupCode || "").toLowerCase() === "color") ||
    null;
  const sizeSelection =
    normalized.selections.find((entry) => String(entry.groupCode || "").toLowerCase() === "size") ||
    null;
  return {
    ...normalized,
    selectionSignature: buildVariantSelectionSignature(normalized.selections),
    colorSelection,
    sizeSelection,
  };
}

function resolveVariantSelectionForItem(product, item, variantCatalog) {
  const selected = normalizeVariantSelectionInput(
    item.selectedVariant ?? item.selectedVariantSelections ?? {}
  );
  const requestedVariantId = Number(
    selected.variantId ??
      item.selectedVariantId ??
      item.selected_variant_id ??
      item.variantId ??
      0
  ) || null;
  const groups = variantCatalog?.groups || [];
  const hasVariants = groups.length > 0;

  if (!hasVariants) {
    if (selected.hasSelections) {
      const err = new Error("PRODUCT_VARIANT_SELECTION_INVALID");
      err.status = 400;
      throw err;
    }
    return {
      hasVariants: false,
      selectedVariantSnapshot: null,
      variantPriceDeltaTotal: 0,
    };
  }

  if (requestedVariantId != null) {
    const exactVariant = (variantCatalog?.variants || []).find(
      (variant) => Number(variant.variantId) === Number(requestedVariantId)
    );
    if (!exactVariant) {
      const err = new Error("PRODUCT_VARIANT_SELECTION_INVALID");
      err.status = 400;
      throw err;
    }
    if (exactVariant.isAvailable === false) {
      throw productUnavailableError({
        product,
        variantId: exactVariant.variantId,
        colorName: null,
        size: null,
        reason: "VARIANT_UNAVAILABLE",
      });
    }

    const exactSelections = buildSelectionsFromVariantCatalog(
      variantCatalog,
      exactVariant
    );
    if (selected.hasSelections) {
      const requestedSignature = buildVariantSelectionSignature(selected.selections);
      if (requestedSignature !== exactSelections.selectionSignature) {
        const err = new Error("PRODUCT_VARIANT_SELECTION_INVALID");
        err.status = 400;
        throw err;
      }
    }

    for (const group of groups) {
      if (
        group.required === true &&
        !exactSelections.selections.some(
          (entry) => String(entry.groupCode || "").toLowerCase() === String(group.groupCode || "").toLowerCase()
        )
      ) {
        const err = new Error("PRODUCT_VARIANT_SELECTION_REQUIRED");
        err.status = 400;
        throw err;
      }
    }

    if (exactVariant.stockQuantity < Number(item.quantity || 0)) {
      throw productOutOfStockError({
        product,
        variantId: exactVariant.variantId,
        colorName: exactSelections.colorSelection?.optionLabel || null,
        size: exactSelections.sizeSelection?.optionLabel || null,
        requestedQuantity: item.quantity,
        availableQuantity: exactVariant.stockQuantity,
      });
    }

    const combinationSignature = exactSelections.selectionSignature;
    const selectedVariantSnapshot = {
      signature: combinationSignature,
      variantId: exactVariant?.variantId || null,
      sku: exactVariant?.sku || null,
      barcode: exactVariant?.barcode || null,
      material: exactVariant?.material || null,
      imageUrl:
        exactVariant?.imageUrl ||
        exactSelections.colorSelection?.imageUrl ||
        exactSelections.selections.find((entry) => entry.imageUrl)?.imageUrl ||
        null,
      colorCode: exactSelections.colorSelection?.optionCode || null,
      colorLabel: exactSelections.colorSelection?.optionLabel || null,
      colorHex: exactSelections.colorSelection?.swatchHex || null,
      colorImageUrl: exactSelections.colorSelection?.imageUrl || null,
      sizeCode: exactSelections.sizeSelection?.optionCode || null,
      sizeLabel: exactSelections.sizeSelection?.optionLabel || null,
      stockQuantity: exactVariant?.stockQuantity ?? null,
      selections: exactSelections.selections,
      groupCodes: exactSelections.selections.map((entry) => entry.groupCode),
      optionCodes: exactSelections.selections.map((entry) => entry.optionCode),
      optionIds: exactSelections.selections.map((entry) => entry.optionId),
      priceDeltaTotal: Number(exactSelections.priceDeltaTotal || 0),
      productId: Number(product.id),
    };

    return {
      hasVariants: true,
      selectedVariantSnapshot,
      variantPriceDeltaTotal: Number(exactSelections.priceDeltaTotal || 0),
      variantId: exactVariant?.variantId || null,
      priceOverride: exactVariant?.priceOverride ?? null,
      discountedPriceOverride: exactVariant?.discountedPriceOverride ?? null,
    };
  }

  if (!selected.hasSelections) {
    const err = new Error("PRODUCT_VARIANT_SELECTION_REQUIRED");
    err.status = 400;
    throw err;
  }

  const seenGroups = new Set();
  const seenSelections = new Set();
  const resolvedSelections = [];
  let variantPriceDeltaTotal = 0;

  for (const selection of selected.selections) {
    const groupKey = String(selection.groupCode || "").toLowerCase();
    if (!groupKey) {
      const err = new Error("PRODUCT_VARIANT_SELECTION_INVALID");
      err.status = 400;
      throw err;
    }
    const group = variantCatalog.groupByCode.get(groupKey);
    if (!group) {
      const err = new Error("PRODUCT_VARIANT_SELECTION_INVALID");
      err.status = 400;
      throw err;
    }
    const optionKey = String(selection.optionCode || "").toLowerCase();
    const selectionKey = `${groupKey}:${optionKey}`;
    if (seenSelections.has(selectionKey) || (seenGroups.has(groupKey) && group.selectionMode !== "multiple")) {
      const err = new Error("PRODUCT_VARIANT_SELECTION_INVALID");
      err.status = 400;
      throw err;
    }
    const option = group.optionByCode.get(optionKey);
    if (!option || option.isAvailable === false) {
      const err = new Error("PRODUCT_VARIANT_SELECTION_INVALID");
      err.status = 400;
      throw err;
    }
    seenGroups.add(groupKey);
    seenSelections.add(selectionKey);
    variantPriceDeltaTotal += Number(option.priceDelta || 0);
    resolvedSelections.push({
      groupCode: group.groupCode,
      groupLabel: group.labelAr || group.labelEn || group.groupCode,
      optionCode: option.optionCode,
      optionLabel: option.labelAr || option.labelEn || option.optionCode,
      optionId: Number(option.optionId),
      swatchHex: option.swatchHex || null,
      imageUrl: option.imageUrl || null,
      priceDelta: Number(option.priceDelta || 0),
    });
  }

  for (const group of groups) {
    if (group.required === true && !seenGroups.has(String(group.groupCode || "").toLowerCase())) {
      const err = new Error("PRODUCT_VARIANT_SELECTION_REQUIRED");
      err.status = 400;
      throw err;
    }
  }

  const managedGroupCodes = new Set(
    (variantCatalog?.variants || []).flatMap((variant) =>
      (variant.selections || []).map((entry) => String(entry.groupCode || entry.group_code || "").toLowerCase())
    )
  );
  const combinationSignature = resolvedSelections
    .filter((entry) => managedGroupCodes.size === 0 || managedGroupCodes.has(String(entry.groupCode).toLowerCase()))
    .map((entry) => `${String(entry.groupCode).toLowerCase()}:${String(entry.optionCode).toLowerCase()}`)
    .sort()
    .join("|");
  const exactVariant = variantCatalog?.variants?.length
    ? variantCatalog.variantBySignature?.get(combinationSignature) ||
      variantCatalog.variants.find(
        (variant) => String(variant.signature || "").toLowerCase() === combinationSignature
      ) ||
      null
    : null;
  if (variantCatalog?.variants?.length && (!exactVariant || exactVariant.isAvailable === false)) {
    if (exactVariant && exactVariant.isAvailable === false) {
      throw productUnavailableError({
        product,
        variantId: exactVariant.variantId,
        colorName:
          resolvedSelections.find(
            (entry) => String(entry.groupCode || "").toLowerCase() === "color"
          )?.optionLabel || null,
        size:
          resolvedSelections.find(
            (entry) => String(entry.groupCode || "").toLowerCase() === "size"
          )?.optionLabel || null,
        reason: "VARIANT_UNAVAILABLE",
      });
    }
    const err = new Error("PRODUCT_VARIANT_SELECTION_INVALID");
    err.status = 400;
    throw err;
  }
  if (exactVariant && exactVariant.stockQuantity < Number(item.quantity || 0)) {
    throw productOutOfStockError({
      product,
      variantId: exactVariant.variantId,
      colorName:
        resolvedSelections.find(
          (entry) => String(entry.groupCode || "").toLowerCase() === "color"
        )?.optionLabel || null,
      size:
        resolvedSelections.find(
          (entry) => String(entry.groupCode || "").toLowerCase() === "size"
        )?.optionLabel || null,
      requestedQuantity: item.quantity,
      availableQuantity: exactVariant.stockQuantity,
    });
  }

  const selectedVariantSnapshot = {
    signature: combinationSignature,
    variantId: exactVariant?.variantId || null,
    sku: exactVariant?.sku || null,
    barcode: exactVariant?.barcode || null,
    material: exactVariant?.material || null,
    imageUrl:
      exactVariant?.imageUrl ||
      resolvedSelections.find((entry) => entry.imageUrl)?.imageUrl ||
      null,
    colorCode:
      resolvedSelections.find(
        (entry) => String(entry.groupCode || "").toLowerCase() === "color"
      )?.optionCode || null,
    colorLabel:
      resolvedSelections.find(
        (entry) => String(entry.groupCode || "").toLowerCase() === "color"
      )?.optionLabel || null,
    colorHex:
      resolvedSelections.find(
        (entry) => String(entry.groupCode || "").toLowerCase() === "color"
      )?.swatchHex || null,
    colorImageUrl:
      resolvedSelections.find(
        (entry) => String(entry.groupCode || "").toLowerCase() === "color"
      )?.imageUrl || null,
    sizeCode:
      resolvedSelections.find(
        (entry) => String(entry.groupCode || "").toLowerCase() === "size"
      )?.optionCode || null,
    sizeLabel:
      resolvedSelections.find(
        (entry) => String(entry.groupCode || "").toLowerCase() === "size"
      )?.optionLabel || null,
    stockQuantity: exactVariant?.stockQuantity ?? null,
    selections: resolvedSelections,
    groupCodes: resolvedSelections.map((item) => item.groupCode),
    optionCodes: resolvedSelections.map((item) => item.optionCode),
    optionIds: resolvedSelections.map((item) => item.optionId),
    priceDeltaTotal: Number(variantPriceDeltaTotal || 0),
    productId: Number(product.id),
  };

  return {
    hasVariants: true,
    selectedVariantSnapshot,
    variantPriceDeltaTotal: Number(variantPriceDeltaTotal || 0),
    variantId: exactVariant?.variantId || null,
    priceOverride: exactVariant?.priceOverride ?? null,
    discountedPriceOverride: exactVariant?.discountedPriceOverride ?? null,
  };
}

function queueOrderSideEffect(task) {
  setImmediate(() => {
    Promise.resolve()
      .then(task)
      .catch((error) => {
        console.warn("[orders] deferred side effect failed", error?.message || error);
      });
  });
}

async function insertCustomerOrderTx(
  client,
  {
    merchantId,
    customer,
    city,
    block,
    buildingNumber,
    apartment,
    note,
    imageUrl,
    orderGroupId,
    subOrderId,
    orderScope,
    storeSequence,
    grossSubtotal,
    productDiscountTotal,
    coupon,
    couponDiscountTotal,
    subtotal,
    serviceFee,
    deliveryFee,
    deliveryFeeRaw = null,
    totalAmount,
    pricingBreakdown,
    financialSnapshot,
  }
) {
  const columns = await getTableColumnsTx(client, "customer_order");
  assertRequiredColumns("customer_order", columns, [
    "merchant_id",
    "customer_user_id",
    "status",
    "customer_full_name",
    "customer_phone",
    "customer_block",
    "customer_building_number",
    "customer_apartment",
    "subtotal",
    "delivery_fee",
    "total_amount",
  ]);

  const candidates = [
    ["merchant_id", Number(merchantId)],
    ["customer_user_id", Number(customer.id)],
    ["status", "pending"],
    ["customer_full_name", customer.full_name],
    ["customer_phone", customer.phone],
    ["customer_city", city],
    ["customer_block", block],
    ["customer_building_number", buildingNumber],
    ["customer_apartment", apartment],
    ["note", note || null],
    ["image_url", imageUrl || null],
    [
      "order_group_id",
      orderGroupId == null ? null : Number(orderGroupId),
    ],
    ["sub_order_id", subOrderId || null],
    ["order_scope", orderScope === "group_child" ? "group_child" : "single"],
    ["store_sequence", Number(storeSequence || 1)],
    ["gross_subtotal", grossSubtotal],
    ["product_discount_total", productDiscountTotal],
    ["coupon_id", coupon ? Number(coupon.id) : null],
    ["coupon_code", coupon?.code || null],
    ["coupon_discount_total", couponDiscountTotal],
    ["subtotal", subtotal],
    ["service_fee", serviceFee],
    ["delivery_fee", deliveryFee],
    ["delivery_fee_raw", deliveryFeeRaw == null ? deliveryFee : deliveryFeeRaw],
    ["total_amount", totalAmount],
    ["store_net_received_amount", financialSnapshot.storeNetReceivedAmount],
    ["app_due_from_delivery", financialSnapshot.appDueFromDelivery],
    ["store_cash_confirmed", financialSnapshot.storeCashConfirmed === true],
    [
      "store_cash_confirmed_at",
      financialSnapshot.storeCashConfirmedAt || null,
    ],
    [
      "store_cash_confirmed_by_user_id",
      financialSnapshot.storeCashConfirmedByUserId ?? null,
    ],
    ["amount_received_actual", financialSnapshot.amountReceivedActual || 0],
    ["difference_amount", financialSnapshot.differenceAmount || 0],
    ["difference_reason", financialSnapshot.differenceReason || null],
    ["settlement_status", financialSnapshot.settlementStatus || "pending_store_confirmation"],
    ["pricing_breakdown_json", JSON.stringify(pricingBreakdown)],
    ["financial_profile_version", financialSnapshot.profileVersion],
    ["financial_config_snapshot_json", JSON.stringify(financialSnapshot)],
  ];

  const { insertColumns, insertValues, placeholders } = buildDynamicInsertParts({
    availableColumns: columns,
    candidates,
  });
  const sql = `INSERT INTO customer_order (${insertColumns.join(",")}) VALUES (${placeholders}) RETURNING *`;
  const result = await client.query(sql, insertValues);
  return result.rows[0] || null;
}

async function insertOrderItemTx(client, orderId, item) {
  const columns = await getTableColumnsTx(client, "order_item");
  assertRequiredColumns("order_item", columns, [
    "order_id",
    "product_id",
    "product_name",
    "unit_price",
    "quantity",
    "line_total",
  ]);

  const candidates = [
    ["order_id", Number(orderId)],
    ["product_id", Number(item.productId)],
    ["product_name", item.productName],
    ["base_unit_price", Number(item.baseUnitPrice || 0)],
    ["unit_price", Number(item.unitPrice || 0)],
    ["quantity", Number(item.quantity || 0)],
    ["selected_modifiers_json", JSON.stringify(item.selectedModifiers || [])],
    [
      "selected_variant_json",
      JSON.stringify(item.selectedVariantSnapshot || null),
    ],
    [
      "selected_variant_options_json",
      JSON.stringify(item.selectedVariantSnapshot?.selections || []),
    ],
    [
      "display_snapshot_json",
      JSON.stringify(
        item.displaySnapshot ||
          item.display_snapshot_json ||
          item.displaySnapshotJson ||
          null
      ),
    ],
    [
      "variant_price_delta_total",
      Number(item.variantPriceDeltaTotal || 0),
    ],
    ["modifiers_unit_total", Number(item.modifiersUnitTotal || 0)],
    ["modifiers_line_total", Number(item.modifiersLineTotal || 0)],
    ["line_discount_total", Number(item.lineDiscountTotal || 0)],
    ["line_total", Number(item.lineTotal || 0)],
    ["pricing_breakdown_json", JSON.stringify(item.pricingBreakdown || {})],
  ];

  const { insertColumns, insertValues, placeholders } = buildDynamicInsertParts({
    availableColumns: columns,
    candidates,
  });
  const sql = `INSERT INTO order_item (${insertColumns.join(",")}) VALUES (${placeholders}) RETURNING *`;
  const result = await client.query(sql, insertValues);
  return result.rows[0] || null;
}

async function transitionInventoryReservationsTx(client, orderId, nextStatus) {
  const nextStatusValue = String(nextStatus || "").trim().toLowerCase();
  const release = nextStatusValue === "released" || nextStatusValue === "expired";
  const eligible = release ? ["pending", "consumed"] :
    nextStatusValue === "completed" ? ["pending", "consumed"] : ["pending"];
  const rows = await client.query(
    `SELECT * FROM inventory_reservation
     WHERE order_id = $1 AND status = ANY($2::varchar[])
     ORDER BY id ASC FOR UPDATE`,
    [Number(orderId), eligible]
  );
  for (const reservation of rows.rows) {
    if (release) {
      if (reservation.variant_id != null) {
        await client.query(
          `UPDATE product_variant
           SET stock_quantity = stock_quantity + $2, updated_at = NOW()
           WHERE id = $1`,
          [Number(reservation.variant_id), Number(reservation.quantity)]
        );
      } else if (reservation.variant_signature) {
        await client.query(
          `UPDATE product_variant
           SET stock_quantity = stock_quantity + $3, updated_at = NOW()
           WHERE product_id = $1 AND signature = $2`,
          [Number(reservation.product_id), reservation.variant_signature, Number(reservation.quantity)]
        );
      } else {
        await client.query(
          `UPDATE store_inventory_item
           SET quantity = quantity + $3,
               stock_status = CASE
                 WHEN quantity + $3 <= COALESCE(reorder_threshold, 0) THEN 'low_stock'
                 ELSE 'in_stock'
               END,
               auto_disabled = FALSE, last_quantity_update_at = NOW(), updated_at = NOW()
           WHERE merchant_id = $1 AND product_id = $2`,
          [Number(reservation.merchant_id), Number(reservation.product_id), Number(reservation.quantity)]
        );
      }
    }
    await client.query(
      `UPDATE inventory_reservation
       SET status = $2::varchar(16),
           consumed_at = CASE WHEN $2::varchar(16) = 'consumed' THEN NOW() ELSE consumed_at END,
           completed_at = CASE WHEN $2::varchar(16) = 'completed' THEN NOW() ELSE completed_at END,
           released_at = CASE WHEN $2::varchar(16) IN ('released','expired') THEN NOW() ELSE released_at END,
           updated_at = NOW()
        WHERE id = $1`,
      [Number(reservation.id), nextStatusValue]
    );
  }
  return rows.rows.length;
}

export async function expireInventoryReservationsBatch({ limit = 100 } = {}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const due = await client.query(
      `SELECT id, order_id
       FROM inventory_reservation
       WHERE status = 'pending' AND expires_at <= NOW()
       ORDER BY expires_at ASC, id ASC
       LIMIT $1 FOR UPDATE SKIP LOCKED`,
      [Math.max(1, Number(limit || 100))]
    );
    let expired = 0;
    const orderIds = [...new Set(due.rows.map((row) => Number(row.order_id)))];
    for (const orderId of orderIds) {
      const orderResult = await client.query(
        `UPDATE customer_order
         SET status = 'expired'::order_status, updated_at = NOW()
         WHERE id = $1 AND status = 'pending'
         RETURNING id, order_group_id`,
        [orderId]
      );
      if (!orderResult.rows[0]) continue;
      expired += await transitionInventoryReservationsTx(client, orderId, "expired");
      await syncOrderGroupStatusTx(client, orderResult.rows[0].order_group_id);
    }
    await client.query("COMMIT");
    return expired;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export const __ordersRepoTestables = Object.freeze({
  buildDynamicInsertParts,
  buildVariantSelectionSignature,
  buildSelectionsFromVariantCatalog,
  buildOrderTrackingEnvelope,
  hydrateOrderItemDisplaySnapshot,
  buildOrderItemDisplaySnapshot,
  buildGroupedDeliveryFeePlan,
  resolveGroupedCheckoutSequence,
  resolveGroupedFeeSequence,
  normalizeReportPeriod,
  periodStartExpression,
  buildReportTimeFilter,
  toDeliveryDetailResponse,
  resolveTrackingViewerMode,
  buildDeliveryEarnings,
  buildDeliveryRatings,
  resolveVariantSelectionForItem,
  shouldApplyProductInventoryGate,
  productOutOfStockError,
  productUnavailableError,
  transitionInventoryReservationsTx,
});

/**
 * Lightweight snapshot used to distinguish "already claimed by another courier"
 * from "not available" after an atomic claim loses the race.
 */
export async function getOrderAssignmentSnapshot(orderId) {
  const r = await q(
    `SELECT
       id,
       status::text AS status,
       delivery_user_id,
       delivery_assignment_status,
       delivery_assignment_status::text AS delivery_assignment_status_text
     FROM customer_order
     WHERE id = $1
     LIMIT 1`,
    [Number(orderId)]
  );
  return r.rows[0] || null;
}

export async function listDeliveryAgents() {
  const r = await q(
    `SELECT u.id, u.full_name, u.phone
     FROM app_user u
     LEFT JOIN courier_profile cp ON cp.user_id = u.id
     WHERE u.role='delivery'
       AND u.delivery_account_approved = TRUE
       AND u.is_account_disabled = FALSE
       AND COALESCE(cp.driver_type, 'app_driver') = 'app_driver'
       AND COALESCE(LOWER(cp.availability_status), 'online') = 'online'
       AND EXISTS (
         SELECT 1
         FROM courier_presence presence
         WHERE presence.courier_user_id = u.id
           AND presence.is_online = TRUE
           AND presence.updated_at >= NOW() - INTERVAL '90 seconds'
       )
       AND NOT EXISTS (
         SELECT 1
         FROM customer_order active_order
         WHERE active_order.delivery_user_id = u.id
           AND active_order.delivery_assignment_status = 'ASSIGNED'
       )
       AND NOT EXISTS (
         SELECT 1
         FROM taxi_captain_profile tcp
         WHERE tcp.user_id = u.id
       )
     ORDER BY u.id DESC`
  );
  return r.rows;
}

async function listNearbyDeliveryAgentsByBlock(block) {
  const normalizedBlock = String(block || "").trim();
  if (!normalizedBlock) return [];

  const r = await q(
    `SELECT u.id, u.full_name, u.phone
     FROM app_user u
     LEFT JOIN courier_profile cp ON cp.user_id = u.id
     WHERE u.role='delivery'
       AND u.delivery_account_approved = TRUE
       AND u.is_account_disabled = FALSE
       AND COALESCE(cp.driver_type, 'app_driver') = 'app_driver'
       AND COALESCE(LOWER(cp.availability_status), 'online') = 'online'
       AND EXISTS (
         SELECT 1
         FROM courier_presence presence
         WHERE presence.courier_user_id = u.id
           AND presence.is_online = TRUE
           AND presence.updated_at >= NOW() - INTERVAL '90 seconds'
       )
       AND NOT EXISTS (
         SELECT 1
         FROM customer_order active_order
         WHERE active_order.delivery_user_id = u.id
           AND active_order.delivery_assignment_status = 'ASSIGNED'
       )
       AND u.block IS NOT NULL
       AND UPPER(TRIM(u.block)) = UPPER(TRIM($1))
       AND NOT EXISTS (
         SELECT 1
         FROM taxi_captain_profile tcp
         WHERE tcp.user_id = u.id
       )
     ORDER BY u.id DESC`,
    [normalizedBlock]
  );
  return r.rows;
}

async function notifyDeliveryPoolForOrder({
  orderId,
  merchantId,
  merchantName,
  customerBlock,
  stage = "new",
}) {
  // Delivery auto-assignment v2 disables broadcast fan-out entirely.
  // Keep this function as a compatibility no-op so older call sites do not
  // re-introduce pool semantics by accident.
  return {
    orderId: Number(orderId),
    merchantId: Number(merchantId),
    merchantName: merchantName || null,
    customerBlock: customerBlock || null,
    stage,
    broadcastDisabled: true,
  };
}

async function buildMerchantOrderNotifications({
  merchantId,
  merchantName,
  orderId,
  status,
}) {
  const recipients = await listActiveMerchantNotificationRecipients({
    merchantId,
    requiredPermissions: ["view_orders", "accept_orders", "prepare_orders"],
  });
  if (!recipients.length) return [];

  return recipients.map((recipient) => ({
    userId: Number(recipient.userId),
    type: "owner_new_order",
    title: "طلب جديد",
    body: `طلب جديد رقم #${orderId} لدى ${merchantName}`,
    orderId: Number(orderId),
    merchantId: Number(merchantId),
    payload: {
      orderId: Number(orderId),
      status,
      requiresAction: true,
      target: "merchant_order_details",
    },
  }));
}

export async function ensureDeliveryAccountApproved(deliveryUserId) {
  await q(
    `UPDATE app_user
     SET delivery_account_approved = TRUE,
         delivery_approved_by_user_id = NULL,
         delivery_approved_at = COALESCE(delivery_approved_at, NOW())
     WHERE id = $1
       AND role = 'delivery'`,
    [Number(deliveryUserId)]
  );
}

function buildOrderGroupPublicId() {
  const stamp = Date.now().toString(36).toUpperCase();
  const randomPart = Math.random().toString(36).slice(2, 8).toUpperCase();
  return `OG-${stamp}-${randomPart}`;
}

function summarizeOrderGroupStatus(statuses) {
  const normalized = (statuses || []).map((value) =>
    String(value || "").trim().toLowerCase()
  );
  if (!normalized.length) return "pending";
  const allCompleted = normalized.every((status) =>
    ["completed", "delivered", "delivered_by_courier", "received_by_customer"].includes(
      status
    )
  );
  if (allCompleted) return "completed";
  const allCancelled = normalized.every((status) =>
    [
      "cancelled",
      "cancelled_by_store",
      "cancelled_by_customer",
      "cancelled_by_admin",
    ].includes(status)
  );
  if (allCancelled) return "cancelled";
  const anyCancelled = normalized.some((status) =>
    [
      "cancelled",
      "cancelled_by_store",
      "cancelled_by_customer",
      "cancelled_by_admin",
    ].includes(status)
  );
  if (anyCancelled) return "partially_completed";
  if (normalized.some((status) => status === "ready_for_delivery")) {
    return "ready_for_delivery";
  }
  if (normalized.some((status) => status === "preparing")) {
    return "preparing";
  }
  if (normalized.some((status) => status === "approved")) {
    return "approved";
  }
  return "pending";
}

async function syncOrderGroupStatusTx(client, orderGroupId) {
  if (!orderGroupId) return null;
  const statusRows = await client.query(
    `SELECT id, status, merchant_id, subtotal, delivery_fee, delivery_fee_raw, total_amount
     FROM customer_order
     WHERE order_group_id = $1
     ORDER BY store_sequence ASC, id ASC`,
    [Number(orderGroupId)]
  );
  if (!statusRows.rows.length) return null;
  const nextStatus = summarizeOrderGroupStatus(
    statusRows.rows.map((row) => row.status)
  );
  await client.query(
    `UPDATE order_group
     SET status = $2,
         updated_at = NOW()
     WHERE id = $1`,
    [Number(orderGroupId), nextStatus]
  );
  for (const row of statusRows.rows) {
    await client.query(
      `UPDATE order_group_item_summary
       SET status = $3,
           subtotal = $4,
           delivery_fee = $5,
           raw_delivery_fee = $6,
           total_amount = $7,
           updated_at = NOW()
       WHERE order_group_id = $1
         AND child_order_id = $2`,
      [
        Number(orderGroupId),
        Number(row.id),
        String(row.status || ""),
        Number(row.subtotal || 0),
        Number(row.delivery_fee || 0),
        Number(row.delivery_fee_raw || row.delivery_fee || 0),
        Number(row.total_amount || 0),
      ]
    );
  }
  return nextStatus;
}

async function calculateStoreOrderDraft({
  client,
  customer,
  merchantId,
  normalizedItems,
  couponId = null,
  couponCode = null,
}) {
  const merchantResult = await client.query(
    `SELECT id, name, activity_type, is_open, is_disabled, owner_user_id
     FROM merchant
     WHERE id=$1`,
    [Number(merchantId)]
  );
  const merchant = merchantResult.rows[0];
  if (!merchant) {
    const err = new Error("MERCHANT_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  if (!merchant.is_open) {
    const err = new Error("MERCHANT_CLOSED");
    err.status = 400;
    throw err;
  }
  if (merchant.is_disabled) {
    const err = new Error("MERCHANT_DISABLED");
    err.status = 400;
    throw err;
  }

  const inventorySettingsResult = await client.query(
    `SELECT *
     FROM inventory_settings
     WHERE merchant_id = $1
     LIMIT 1`,
    [Number(merchantId)]
  );
  const inventorySettings = inventorySettingsResult.rows[0] || null;
  const inventoryEnabled = inventorySettings?.inventory_enabled === true;

  const productIds = normalizedItems.map((x) => Number(x.productId));
  const productsResult = await client.query(
    `SELECT
       p.id,
       p.merchant_id,
       p.name,
       p.image_url,
       p.price,
       p.discounted_price,
       p.free_delivery,
       p.is_available,
       si.quantity AS inventory_quantity,
       si.reorder_threshold AS inventory_reorder_threshold,
       si.manual_disabled AS inventory_manual_disabled,
       si.auto_disabled AS inventory_auto_disabled,
       si.stock_status AS inventory_stock_status
     FROM product p
     LEFT JOIN store_inventory_item si
       ON si.merchant_id = p.merchant_id
      AND si.product_id = p.id
     WHERE p.id = ANY($1::bigint[])`,
    [productIds]
  );

  const productMap = new Map(productsResult.rows.map((p) => [String(p.id), p]));
  const variantCatalogMap = await loadProductVariantCatalogTx(
    client,
    productIds
  );
  const activeOffers = await listLatestEligibleOffersByProductIds({
    client,
    merchantId: Number(merchantId),
    productIds,
  });
  const activeOfferMap = new Map(
    activeOffers.map((offer) => [String(offer.product_id), offer])
  );

  const calculatedItems = [];
  let grossSubtotal = 0;
  let subtotal = 0;
  let productDiscountTotal = 0;
  let hasFreeDeliveryOffer = false;

  for (const item of normalizedItems) {
    const product = productMap.get(String(item.productId));
    if (!product) {
      const err = new Error("PRODUCT_NOT_FOUND");
      err.status = 404;
      throw err;
    }
    if (String(product.merchant_id) !== String(merchantId)) {
      const err = new Error("PRODUCT_MERCHANT_MISMATCH");
      err.status = 400;
      throw err;
    }
    if (!product.is_available) {
      throw productUnavailableError({ product });
    }

    const variantResolution = resolveVariantSelectionForItem(
      product,
      item,
      variantCatalogMap.get(Number(product.id)) || null
    );

    if (
      shouldApplyProductInventoryGate({
        variantResolution,
        inventoryEnabled,
        inventoryQuantity: product.inventory_quantity,
      })
    ) {
      if (product.inventory_manual_disabled === true) {
        throw productUnavailableError({ product, reason: "MANUAL_DISABLED" });
      }
      const currentQuantity = Math.max(0, Number(product.inventory_quantity || 0));
      if (currentQuantity < Number(item.quantity || 0)) {
        throw productOutOfStockError({
          product,
          requestedQuantity: item.quantity,
          availableQuantity: currentQuantity,
        });
      }
    }

    if (product.free_delivery) hasFreeDeliveryOffer = true;

    const activeOffer = activeOfferMap.get(String(item.productId)) || null;
    const baseUnitPrice = variantResolution.priceOverride ??
      (Number(product.price) + Number(variantResolution.variantPriceDeltaTotal || 0));
    const fallbackDiscountedPrice = variantResolution.discountedPriceOverride ??
      (product.discounted_price == null
        ? null
        : Number(product.discounted_price) + Number(variantResolution.variantPriceDeltaTotal || 0));
    const pricing = applyMerchantOfferPricing({
      baseUnitPrice,
      quantity: Number(item.quantity || 0),
      offer: activeOffer,
      fallbackDiscountedPrice,
    });

    const selectedModifiers = Array.isArray(item.selectedModifiers)
      ? item.selectedModifiers
      : [];
    const modifiersUnitTotal = selectedModifiers.reduce(
      (sum, modifier) => sum + Number(modifier?.priceDelta ?? modifier?.price ?? 0),
      0
    );
    const modifiersLineTotal = modifiersUnitTotal * Number(item.quantity || 0);

    const unitPrice = Number(pricing.unitPrice) + modifiersUnitTotal;
    const lineDiscountTotal = Number(pricing.lineDiscountTotal);
    const grossLineTotal = Number(pricing.grossLineTotal) + modifiersLineTotal;
    const lineTotal = Number(pricing.lineTotal) + modifiersLineTotal;
    const displaySnapshot = buildOrderItemDisplaySnapshot({
      productId: product.id,
      productName: product.name,
      productImageUrl: product.image_url || null,
      thumbnailUrl:
        variantResolution.selectedVariantSnapshot?.imageUrl ||
        product.image_url ||
        null,
      sku: variantResolution.selectedVariantSnapshot?.sku || null,
      variantId: variantResolution.variantId || null,
      variantName: variantResolution.selectedVariantSnapshot?.signature || null,
      variantSku: variantResolution.selectedVariantSnapshot?.sku || null,
      quantity: item.quantity,
      unitPrice,
      lineTotal,
      currency: "IQD",
      selectedColor: variantResolution.selectedVariantSnapshot
        ? {
            label: variantResolution.selectedVariantSnapshot.colorLabel || null,
            value: variantResolution.selectedVariantSnapshot.colorLabel || null,
            hex: variantResolution.selectedVariantSnapshot.colorHex || null,
          }
        : null,
      selectedSize: variantResolution.selectedVariantSnapshot
        ? {
            label: variantResolution.selectedVariantSnapshot.sizeLabel || null,
            value: variantResolution.selectedVariantSnapshot.sizeLabel || null,
          }
        : null,
      specs: variantResolution.selectedVariantSnapshot?.selections || [],
      options: selectedModifiers,
      addons: [],
      removals: [],
      userNote: item.userNote || item.note || null,
      activityType: merchant.activity_type || null,
      storeId: merchant.id,
      storeName: merchant.name,
    });

    grossSubtotal += grossLineTotal;
    subtotal += lineTotal;
    productDiscountTotal += lineDiscountTotal;

    calculatedItems.push({
      productId: Number(product.id),
      productName: product.name,
      offerId: pricing.offerId,
      offerType: pricing.offerType,
      offerLabel: pricing.offerLabel,
      freeUnits: pricing.freeUnits,
      baseUnitPrice,
      unitPrice,
      quantity: Number(item.quantity || 0),
      lineDiscountTotal,
      lineTotal,
      modifiersUnitTotal,
      modifiersLineTotal,
      selectedModifiers,
      selectedVariantSnapshot: variantResolution.selectedVariantSnapshot == null ? null : {
        ...variantResolution.selectedVariantSnapshot,
        productName: product.name,
        finalPrice: unitPrice,
        quantity: Number(item.quantity || 0),
      },
      displaySnapshot,
      variantPriceDeltaTotal: Number(variantResolution.variantPriceDeltaTotal || 0),
      pricingBreakdown: {
        ...pricing.pricingBreakdown,
        selectedModifiers,
        modifiersUnitTotal,
        modifiersLineTotal,
        selectedVariantSnapshot: variantResolution.selectedVariantSnapshot == null ? null : {
          ...variantResolution.selectedVariantSnapshot,
          productName: product.name,
          finalPrice: unitPrice,
          quantity: Number(item.quantity || 0),
        },
        displaySnapshot,
        variantPriceDeltaTotal: Number(variantResolution.variantPriceDeltaTotal || 0),
      },
    });
  }

  const couponResult = await validateCouponByIdOrCode(
    { couponId, code: couponCode },
    {
      customerId: Number(customer.id),
      merchantId: Number(merchantId),
      orderTotal: subtotal,
    }
  );
  if ((couponId || couponCode) && !couponResult?.coupon) {
    const err = new Error(couponResult?.reasonCode || "COUPON_INVALID_OR_EXPIRED");
    err.status = 400;
    throw err;
  }
  const coupon = couponResult?.coupon || null;

  const couponDiscountTotal = coupon ? calcDiscount(coupon, subtotal) : 0;
  const billingProfile = await getMerchantBillingProfile(Number(merchantId));
  const financialSnapshot = computeOrderFinancialSnapshot(
    {
      subtotal,
      service_fee: 0,
      delivery_fee: hasFreeDeliveryOffer ? 0 : null,
      delivery_type: "delivery",
      courier_source: "app",
      has_free_delivery: hasFreeDeliveryOffer,
      created_at: new Date().toISOString(),
    },
    billingProfile
  );
  const serviceFee = Number(financialSnapshot.serviceFeeAmount || 0);
  const deliveryFee = Number(financialSnapshot.deliveryFee || 0);
  const subtotalAfterAllDiscounts = Math.max(0, subtotal - couponDiscountTotal);
  const totalAmount = subtotalAfterAllDiscounts + serviceFee + deliveryFee;

  return {
    merchant,
    calculatedItems,
    pricing: {
      grossSubtotal,
      productDiscountTotal,
      subtotalAfterProductDiscounts: subtotal,
      couponDiscountTotal,
      subtotalAfterAllDiscounts,
      serviceFee,
      deliveryFee,
      totalAmount,
      coupon: coupon
        ? {
            id: Number(coupon.id),
            code: coupon.code,
            discountType: coupon.discount_type,
            discountValue: Number(coupon.discount_value),
            discountAmount: couponDiscountTotal,
            description: coupon.description || null,
          }
        : null,
    },
    financialSnapshot,
  };
}

/**
 * ينشئ الطلب وكل عناصره والخصومات وحجوزات المخزون داخل transaction واحدة.
 *
 * Side effects:
 * - يقرأ merchant/products/offers/coupons/inventory
 * - يكتب customer_order وorder_item
 * - يحدّث المخزون ويستهلك coupon/offer usage
 * - قد يطلق إشعارات لاحقة خارج transaction
 *
 * Critical notes:
 * - هذا هو root transaction لإنشاء الطلب. أي تعديل يجب أن يحافظ على ترتيب:
 *   validate merchant -> validate inventory -> calculate pricing -> insert order
 *   -> insert items -> adjust inventory -> consume incentives -> commit.
 */
export async function createOrderWithItems({
  customer,
  deliveryAddress,
  merchantId,
  note,
  imageUrl,
  couponId = null,
  couponCode = null,
  normalizedItems,
  orderGroupId = null,
  subOrderId = null,
  orderScope = "single",
  storeSequence = 1,
  deliveryFeeOverride = null,
  deliveryFeeRaw = null,
  txClient = null,
  suppressNotifications = false,
}) {
  const ownsClient = !txClient;
  const client = txClient || (await pool.connect());
  const shouldManageTransaction = ownsClient;
  try {
    if (shouldManageTransaction) {
      await client.query("BEGIN");
    }

    const merchantResult = await client.query(
      `SELECT id, name, type, activity_type, is_open, is_disabled, owner_user_id
       FROM merchant
       WHERE id=$1`,
      [merchantId]
    );
    const merchant = merchantResult.rows[0];
    if (!merchant) {
      const err = new Error("MERCHANT_NOT_FOUND");
      err.status = 404;
      throw err;
    }
    if (!merchant.is_open) {
      const err = new Error("MERCHANT_CLOSED");
      err.status = 400;
      throw err;
    }
    if (merchant.is_disabled) {
      const err = new Error("MERCHANT_DISABLED");
      err.status = 400;
      throw err;
    }

    const inventorySettingsResult = await client.query(
      `SELECT *
       FROM inventory_settings
       WHERE merchant_id = $1
       LIMIT 1`,
      [Number(merchantId)]
    );
    const inventorySettings = inventorySettingsResult.rows[0] || null;
    const inventoryEnabled = inventorySettings?.inventory_enabled === true;

    const productIds = normalizedItems.map((x) => x.productId);
    const productsResult = await client.query(
      `SELECT
         p.id,
         p.merchant_id,
         p.name,
         p.image_url,
         p.price,
         p.discounted_price,
         p.free_delivery,
         p.is_available,
         si.quantity AS inventory_quantity,
         si.reorder_threshold AS inventory_reorder_threshold,
         si.manual_disabled AS inventory_manual_disabled,
         si.auto_disabled AS inventory_auto_disabled,
         si.stock_status AS inventory_stock_status
       FROM product
       p
       LEFT JOIN store_inventory_item si
         ON si.merchant_id = p.merchant_id
        AND si.product_id = p.id
       WHERE p.id = ANY($1::bigint[])`,
      [productIds]
    );

  const productMap = new Map(productsResult.rows.map((p) => [String(p.id), p]));
  const variantCatalogMap = await loadProductVariantCatalogTx(
    client,
    productIds
  );
  const activeOffers = await listLatestEligibleOffersByProductIds({
    client,
    merchantId: Number(merchantId),
      productIds,
    });
    const activeOfferMap = new Map(
      activeOffers.map((offer) => [String(offer.product_id), offer])
    );
    const calculatedItems = [];
    let grossSubtotal = 0;
    let subtotal = 0;
    let productDiscountTotal = 0;
    let hasFreeDeliveryOffer = false;
    const inventoryAdjustments = [];

    for (const item of normalizedItems) {
      const product = productMap.get(String(item.productId));
      if (!product) {
        const err = new Error("PRODUCT_NOT_FOUND");
        err.status = 404;
        throw err;
      }
      if (String(product.merchant_id) !== String(merchantId)) {
        const err = new Error("PRODUCT_MERCHANT_MISMATCH");
        err.status = 400;
        throw err;
      }
      if (!product.is_available) {
        throw productUnavailableError({ product });
      }

      const variantResolution = resolveVariantSelectionForItem(
        product,
        item,
        variantCatalogMap.get(Number(product.id)) || null
      );

      if (
        shouldApplyProductInventoryGate({
          variantResolution,
          inventoryEnabled,
          inventoryQuantity: product.inventory_quantity,
        })
      ) {
        if (product.inventory_manual_disabled === true) {
          throw productUnavailableError({ product, reason: "MANUAL_DISABLED" });
        }
        const currentQuantity = Math.max(0, Number(product.inventory_quantity || 0));
        if (currentQuantity < Number(item.quantity || 0)) {
          throw productOutOfStockError({
            product,
            requestedQuantity: item.quantity,
            availableQuantity: currentQuantity,
          });
        }
      }

      if (product.free_delivery) {
        hasFreeDeliveryOffer = true;
      }

      const activeOffer = activeOfferMap.get(String(item.productId)) || null;
      const baseUnitPrice = variantResolution.priceOverride ??
        (Number(product.price) + Number(variantResolution.variantPriceDeltaTotal || 0));
      const fallbackDiscountedPrice = variantResolution.discountedPriceOverride ??
        (product.discounted_price == null
          ? null
          : Number(product.discounted_price) +
            Number(variantResolution.variantPriceDeltaTotal || 0));
      const pricing = applyMerchantOfferPricing({
        baseUnitPrice,
        quantity: item.quantity,
        offer: activeOffer,
        fallbackDiscountedPrice,
      });
      const selectedModifiers = Array.isArray(item.selectedModifiers)
        ? item.selectedModifiers
        : [];
      const modifiersUnitTotal = selectedModifiers.reduce(
        (sum, modifier) => sum + Number(modifier?.priceDelta ?? modifier?.price ?? 0),
        0
      );
      const modifiersLineTotal = modifiersUnitTotal * Number(item.quantity || 0);

      const unitPrice = Number(pricing.unitPrice) + modifiersUnitTotal;
      const lineDiscountTotal = Number(pricing.lineDiscountTotal);
      const grossLineTotal = Number(pricing.grossLineTotal) + modifiersLineTotal;
      const lineTotal = Number(pricing.lineTotal) + modifiersLineTotal;
      const displaySnapshot = buildOrderItemDisplaySnapshot({
        productId: product.id,
        productName: product.name,
        productImageUrl: product.image_url || null,
        thumbnailUrl:
          variantResolution.selectedVariantSnapshot?.imageUrl ||
          product.image_url ||
          null,
        sku: variantResolution.selectedVariantSnapshot?.sku || null,
        variantId: variantResolution.variantId || null,
        variantName: variantResolution.selectedVariantSnapshot?.signature || null,
        variantSku: variantResolution.selectedVariantSnapshot?.sku || null,
        quantity: item.quantity,
        unitPrice,
        lineTotal,
        currency: "IQD",
        selectedColor: variantResolution.selectedVariantSnapshot
          ? {
              label: variantResolution.selectedVariantSnapshot.colorLabel || null,
              value: variantResolution.selectedVariantSnapshot.colorLabel || null,
              hex: variantResolution.selectedVariantSnapshot.colorHex || null,
            }
          : null,
        selectedSize: variantResolution.selectedVariantSnapshot
          ? {
              label: variantResolution.selectedVariantSnapshot.sizeLabel || null,
              value: variantResolution.selectedVariantSnapshot.sizeLabel || null,
            }
          : null,
        specs: variantResolution.selectedVariantSnapshot?.selections || [],
        options: selectedModifiers,
        addons: [],
        removals: [],
        userNote: item.userNote || item.note || null,
        activityType: merchant.activity_type || null,
        storeId: merchant.id,
        storeName: merchant.name,
      });
      grossSubtotal += grossLineTotal;
      subtotal += lineTotal;
      productDiscountTotal += lineDiscountTotal;

      calculatedItems.push({
        productId: product.id,
        productName: product.name,
        offerId: pricing.offerId,
        offerType: pricing.offerType,
        offerLabel: pricing.offerLabel,
        freeUnits: pricing.freeUnits,
        baseUnitPrice,
        unitPrice,
        quantity: item.quantity,
        lineDiscountTotal,
        lineTotal,
        modifiersUnitTotal,
        modifiersLineTotal,
        selectedModifiers,
        selectedVariantSnapshot: variantResolution.selectedVariantSnapshot == null ? null : {
          ...variantResolution.selectedVariantSnapshot,
          productName: product.name,
          finalPrice: unitPrice,
          quantity: Number(item.quantity || 0),
        },
        displaySnapshot,
        variantPriceDeltaTotal: Number(variantResolution.variantPriceDeltaTotal || 0),
        pricingBreakdown: {
          ...pricing.pricingBreakdown,
          selectedModifiers,
          modifiersUnitTotal,
          modifiersLineTotal,
          selectedVariantSnapshot: variantResolution.selectedVariantSnapshot == null ? null : {
            ...variantResolution.selectedVariantSnapshot,
            productName: product.name,
            finalPrice: unitPrice,
            quantity: Number(item.quantity || 0),
          },
          displaySnapshot,
          variantPriceDeltaTotal: Number(variantResolution.variantPriceDeltaTotal || 0),
        },
      });

      if (variantResolution.variantId) {
        inventoryAdjustments.push({
          itemIndex: calculatedItems.length - 1,
          productId: Number(product.id),
          variantId: Number(variantResolution.variantId),
          orderedQuantity: Number(item.quantity || 0),
          currentQuantity: null,
          reorderThreshold: 0,
          manualDisabled: false,
        });
      } else if (inventoryEnabled && product.inventory_quantity != null) {
        inventoryAdjustments.push({
          itemIndex: calculatedItems.length - 1,
          productId: Number(product.id),
          orderedQuantity: Number(item.quantity || 0),
          currentQuantity: Math.max(0, Number(product.inventory_quantity || 0)),
          reorderThreshold:
            product.inventory_reorder_threshold == null
              ? Math.max(0, Number(inventorySettings?.low_stock_threshold || 0))
              : Math.max(0, Number(product.inventory_reorder_threshold || 0)),
          manualDisabled: product.inventory_manual_disabled === true,
        });
      }
    }

    const couponResult = await validateCouponByIdOrCode(
      { couponId, code: couponCode },
      {
        customerId: Number(customer.id),
        merchantId: Number(merchantId),
        orderTotal: subtotal,
      }
    );
    if ((couponId || couponCode) && !couponResult?.coupon) {
      const err = new Error(couponResult?.reasonCode || "COUPON_INVALID_OR_EXPIRED");
      err.status = 400;
      throw err;
    }
    const coupon = couponResult?.coupon || null;
    const couponDiscountTotal = coupon
      ? calcDiscount(coupon, subtotal)
      : 0;

    const billingProfile = await getMerchantBillingProfile(Number(merchantId));
    const effectiveDeliveryFee =
      deliveryFeeOverride == null ? null : roundMoney(deliveryFeeOverride);
    const effectiveRawDeliveryFee =
      deliveryFeeRaw == null
        ? effectiveDeliveryFee == null
          ? null
          : effectiveDeliveryFee
        : roundMoney(deliveryFeeRaw);
    const financialSnapshot = computeOrderFinancialSnapshot(
      {
        subtotal,
        service_fee: 0,
        delivery_fee:
          hasFreeDeliveryOffer
            ? 0
            : effectiveDeliveryFee == null
              ? null
              : effectiveDeliveryFee,
        delivery_type: "delivery",
        courier_source: "app",
        has_free_delivery: hasFreeDeliveryOffer,
        created_at: new Date().toISOString(),
      },
      billingProfile
    );
    const serviceFee = financialSnapshot.serviceFeeAmount;
    const deliveryFee = financialSnapshot.deliveryFee;
    const subtotalAfterAllDiscounts = Math.max(0, subtotal - couponDiscountTotal);
    const totalAmount =
      subtotalAfterAllDiscounts + serviceFee + deliveryFee;
    const rawDeliveryFee =
      effectiveRawDeliveryFee == null ? deliveryFee : effectiveRawDeliveryFee;
    const pricingBreakdown = {
      grossSubtotal,
      productDiscountTotal,
      subtotalAfterProductDiscounts: subtotal,
      couponDiscountTotal,
      subtotalAfterAllDiscounts,
      serviceFee,
      deliveryFee,
      rawDeliveryFee,
      allocatedDeliveryFee: deliveryFee,
      totalAmount,
      coupon: coupon
        ? {
            id: Number(coupon.id),
            code: coupon.code,
            discountType: coupon.discount_type,
            discountValue: Number(coupon.discount_value),
            discountAmount: couponDiscountTotal,
            description: coupon.description || null,
          }
        : null,
      items: calculatedItems.map((item) => ({
        productId: item.productId,
        productName: item.productName,
        offerId: item.offerId,
        offerType: item.offerType,
        offerLabel: item.offerLabel,
        freeUnits: item.freeUnits,
        ...item.pricingBreakdown,
      })),
    };

    const city = deliveryAddress?.city?.trim() || "مدينة بسماية";
    const block = deliveryAddress?.block?.trim() || customer.block;
    const buildingNumber =
      deliveryAddress?.building_number?.trim() ||
      customer.building_number;
    const apartment =
      deliveryAddress?.apartment?.trim() ||
      customer.apartment;

    const order = await insertCustomerOrderTx(client, {
      merchantId,
      customer,
      city,
      block,
      buildingNumber,
      apartment,
      note,
      imageUrl,
      orderGroupId,
      subOrderId,
      orderScope,
      storeSequence,
      grossSubtotal,
      productDiscountTotal,
      coupon,
      couponDiscountTotal,
      subtotal,
      serviceFee,
      deliveryFee,
      deliveryFeeRaw: rawDeliveryFee,
      totalAmount,
      pricingBreakdown,
      financialSnapshot,
    });

    const persistedItems = [];
    for (const item of calculatedItems) {
      const persisted = await insertOrderItemTx(client, order.id, item);
      if (persisted) persistedItems.push(persisted);
    }

    const catalogMutated = inventoryAdjustments.length > 0;
    if (catalogMutated) {
      for (const item of inventoryAdjustments) {
        let reserved;
        if (item.variantId) {
          reserved = await client.query(
            `UPDATE product_variant
             SET stock_quantity = stock_quantity - $2, updated_at = NOW()
             WHERE id = $1 AND is_available = TRUE AND stock_quantity >= $2
             RETURNING id, stock_quantity`,
            [Number(item.variantId), Number(item.orderedQuantity)]
          );
        } else {
          reserved = await client.query(
            `UPDATE store_inventory_item
             SET quantity = quantity - $3,
                 stock_status = CASE
                   WHEN quantity - $3 <= 0 THEN 'out_of_stock'
                   WHEN quantity - $3 <= COALESCE(reorder_threshold, $4) THEN 'low_stock'
                   ELSE 'in_stock'
                 END,
                 last_quantity_update_at = NOW(), updated_at = NOW()
             WHERE merchant_id = $1 AND product_id = $2
               AND manual_disabled = FALSE AND quantity >= $3
             RETURNING id, quantity`,
            [Number(merchantId), Number(item.productId), Number(item.orderedQuantity), Number(item.reorderThreshold || 0)]
          );
        }
        if (!reserved.rows[0]) {
          let availableQuantity = 0;
          if (item.variantId) {
            const stockRow = await client.query(
              `SELECT stock_quantity FROM product_variant WHERE id = $1`,
              [Number(item.variantId)]
            );
            availableQuantity = Number(stockRow.rows[0]?.stock_quantity || 0);
          } else {
            const stockRow = await client.query(
              `SELECT quantity FROM store_inventory_item
               WHERE merchant_id = $1 AND product_id = $2`,
              [Number(merchantId), Number(item.productId)]
            );
            availableQuantity = Number(stockRow.rows[0]?.quantity || 0);
          }
          const calculated = calculatedItems[item.itemIndex] || {};
          throw productOutOfStockError({
            product: { id: item.productId, name: calculated.productName },
            variantId: item.variantId || null,
            colorName: calculated.selectedVariantSnapshot?.colorLabel || null,
            size: calculated.selectedVariantSnapshot?.sizeLabel || null,
            requestedQuantity: item.orderedQuantity,
            availableQuantity,
          });
        }
        const persistedItem = persistedItems[item.itemIndex];
        await client.query(
          `INSERT INTO inventory_reservation
             (order_id, order_item_id, merchant_id, product_id, variant_id, variant_signature, quantity, status, expires_at)
           VALUES ($1,$2,$3,$4,$5,$6,$7,'pending', NOW() + ($8 * interval '1 minute'))
           ON CONFLICT (order_item_id) DO NOTHING`,
          [Number(order.id), Number(persistedItem.id), Number(merchantId), Number(item.productId),
           item.variantId ? Number(item.variantId) : null,
           item.variantId ? calculatedItems[item.itemIndex]?.selectedVariantSnapshot?.signature || null : null,
           Number(item.orderedQuantity), Number(env.orderStockReservationTtlMinutes || 30)]
        );
      }

      if (inventoryEnabled) await client.query(
        `UPDATE inventory_settings
         SET last_stock_update_at = NOW(),
             updated_at = NOW()
         WHERE merchant_id = $1`,
        [Number(merchantId)]
      );
    }

    const offerUsages = [];
    const offerUsageMap = new Map();
    for (const item of calculatedItems) {
      if (!item.offerId || item.lineDiscountTotal <= 0) continue;
      const current = offerUsageMap.get(String(item.offerId)) || {
        offerId: Number(item.offerId),
        discountTotal: 0,
      };
      current.discountTotal += Number(item.lineDiscountTotal || 0);
      offerUsageMap.set(String(item.offerId), current);
    }
    for (const usage of offerUsageMap.values()) {
      offerUsages.push({
        offerId: usage.offerId,
        orderId: Number(order.id),
        merchantId: Number(merchant.id),
        customerUserId: Number(customer.id),
        discountTotal: usage.discountTotal,
      });
    }
    if (offerUsages.length) {
      await markOfferUsageByOrderTx(client, offerUsages);
    }

    if (coupon && couponDiscountTotal > 0) {
      await consumeCouponRedemptionByOrderTx(client, {
        couponId: Number(coupon.id),
        customerId: Number(customer.id),
        orderId: Number(order.id),
        discountAmount: Number(couponDiscountTotal),
      });
    }

    if (shouldManageTransaction) {
      await client.query("COMMIT");
    }
    if (catalogMutated) {
      await invalidateMerchantCatalogCache(merchantId);
    }

    const hydrated = {
      ...order,
      merchant_name: merchant.name || null,
      merchant_type: merchant.type || null,
      owner_user_id:
        merchant.owner_user_id == null ? null : Number(merchant.owner_user_id),
      customer_image_url: customer.image_url || null,
      delivery_id: null,
      delivery_full_name: null,
      delivery_phone: null,
      delivery_driver_type: null,
      items: persistedItems,
    };

    if (!suppressNotifications) {
      queueOrderSideEffect(async () => {
        const employeeNotifications = await buildMerchantOrderNotifications({
          merchantId: Number(merchant.id),
          merchantName: merchant.name,
          orderId: order.id,
          status: order.status,
        });
        await createManyNotifications([
          {
            userId: customer.id,
            type: "order_created",
            title: "تم إنشاء الطلب",
            body: `تم إنشاء طلبك لدى ${merchant.name} بنجاح`,
            orderId: order.id,
            merchantId: merchant.id,
            payload: {
              orderId: order.id,
              status: order.status,
            },
          },
          merchant.owner_user_id
            ? {
                userId: merchant.owner_user_id,
                type: "owner_new_order",
                title: "طلب جديد",
                body: `طلب جديد رقم #${order.id} لدى ${merchant.name}`,
                orderId: order.id,
                merchantId: merchant.id,
                payload: {
                  orderId: order.id,
                  status: order.status,
                  requiresAction: true,
                  target: "merchant_order_details",
                },
              }
            : null,
          ...employeeNotifications,
        ].filter(Boolean));

      });
    }

    return hydrated;
  } catch (e) {
    if (shouldManageTransaction) {
      await client.query("ROLLBACK");
    }
    throw e;
  } finally {
    if (ownsClient) {
      client.release();
    }
  }
}

export async function previewOrderGroup({
  customer,
  deliveryAddress,
  note = null,
  paymentMethod = "cash_on_delivery",
  storeOrders,
}) {
  if (!Array.isArray(storeOrders) || storeOrders.length === 0) {
    throw new AppError("ORDER_ITEMS_REQUIRED", { status: 400 });
  }
  if (storeOrders.length > 3) {
    throw new AppError("MAX_STORES_PER_ORDER_EXCEEDED", { status: 400 });
  }

  const client = await pool.connect();
  try {
    const draftedStores = [];
    for (let index = 0; index < storeOrders.length; index += 1) {
      const storeOrder = storeOrders[index];
      const draft = await calculateStoreOrderDraft({
        client,
        customer,
        merchantId: Number(storeOrder.merchantId),
        normalizedItems: storeOrder.normalizedItems,
        couponId: storeOrder.couponId ?? null,
        couponCode: storeOrder.couponCode ?? null,
      });
      draftedStores.push({
        storeOrder,
        draft,
        originalIndex: index,
        checkoutSequence: resolveGroupedCheckoutSequence(storeOrder, index),
        rawDeliveryFee: Number(draft.pricing.deliveryFee || 0),
        subtotalAfterAllDiscounts: Number(
          draft.pricing.subtotalAfterAllDiscounts || 0
        ),
        serviceFee: Number(draft.pricing.serviceFee || 0),
        grossSubtotal: Number(draft.pricing.grossSubtotal || 0),
        productDiscountTotal: Number(
          draft.pricing.productDiscountTotal || 0
        ),
        couponDiscountTotal: Number(draft.pricing.couponDiscountTotal || 0),
      });
    }
    const deliveryPlan = buildGroupedDeliveryFeePlan(draftedStores);
    const stores = draftedStores.map((entry, index) => {
      const feePlan = deliveryPlan.entries[index];
      return {
        merchantId: Number(entry.draft.merchant.id),
        merchantName: entry.draft.merchant.name,
        note: entry.storeOrder.note || null,
        items: entry.draft.calculatedItems,
        pricing: {
          ...entry.draft.pricing,
          rawDeliveryFee: feePlan.rawDeliveryFee,
          allocatedDeliveryFee: feePlan.allocatedDeliveryFee,
          deliveryFee: feePlan.allocatedDeliveryFee,
          totalAmount: feePlan.totalAmount,
        },
        sequence: feePlan.checkoutSequence,
        deliveryFeeMultiplier: feePlan.deliveryFeeMultiplier,
      };
    });
    const totals = {
      grossSubtotal: 0,
      productDiscountTotal: 0,
      couponDiscountTotal: 0,
      serviceFeeTotal: 0,
      deliveryFeeTotal: 0,
      rawDeliveryFeeTotal: deliveryPlan.rawDeliveryFeeTotal,
      allocatedDeliveryFeeTotal: deliveryPlan.allocatedDeliveryFeeTotal,
      totalAmount: 0,
    };
    for (const entry of deliveryPlan.entries) {
      totals.grossSubtotal += Number(entry.grossSubtotal || 0);
      totals.productDiscountTotal += Number(entry.productDiscountTotal || 0);
      totals.couponDiscountTotal += Number(entry.couponDiscountTotal || 0);
      totals.serviceFeeTotal += Number(entry.serviceFee || 0);
      totals.deliveryFeeTotal += Number(entry.allocatedDeliveryFee || 0);
      totals.totalAmount += Number(entry.totalAmount || 0);
    }

    return {
      mode: stores.length > 1 ? "multi_store" : "single_store",
      storesCount: stores.length,
      maxStoresAllowed: 3,
      note: note || null,
      paymentMethod: paymentMethod || "cash_on_delivery",
      customerAddress: {
        city: deliveryAddress?.city?.trim() || "مدينة بسماية",
        block: deliveryAddress?.block?.trim() || customer.block,
        buildingNumber:
          deliveryAddress?.building_number?.trim() || customer.building_number,
        apartment: deliveryAddress?.apartment?.trim() || customer.apartment,
      },
      totals,
      multiStoreDelayNotice:
        stores.length > 1
          ? "الطلب يحتوي على أكثر من متجر، وقد يستغرق وقتًا أطول قليلًا."
          : null,
      stores,
    };
  } finally {
    client.release();
  }
}

export async function createOrderGroupWithItems({
  customer,
  deliveryAddress,
  note = null,
  paymentMethod = "cash_on_delivery",
  storeOrders,
}) {
  if (!Array.isArray(storeOrders) || storeOrders.length === 0) {
    throw new AppError("ORDER_ITEMS_REQUIRED", { status: 400 });
  }
  if (storeOrders.length > 3) {
    throw new AppError("MAX_STORES_PER_ORDER_EXCEEDED", { status: 400 });
  }

  const client = await pool.connect();
  const customerBlock =
    deliveryAddress?.block?.trim() || customer.block || null;
  try {
    await client.query("BEGIN");
    const draftedStores = [];
    for (let index = 0; index < storeOrders.length; index += 1) {
      const storeOrder = storeOrders[index];
      const draft = await calculateStoreOrderDraft({
        client,
        customer,
        merchantId: Number(storeOrder.merchantId),
        normalizedItems: storeOrder.normalizedItems,
        couponId: storeOrder.couponId ?? null,
        couponCode: storeOrder.couponCode ?? null,
      });
      draftedStores.push({
        storeOrder,
        draft,
        originalIndex: index,
        checkoutSequence: resolveGroupedCheckoutSequence(storeOrder, index),
        rawDeliveryFee: Number(draft.pricing.deliveryFee || 0),
        subtotalAfterAllDiscounts: Number(
          draft.pricing.subtotalAfterAllDiscounts || 0
        ),
        serviceFee: Number(draft.pricing.serviceFee || 0),
        grossSubtotal: Number(draft.pricing.grossSubtotal || 0),
        productDiscountTotal: Number(
          draft.pricing.productDiscountTotal || 0
        ),
        couponDiscountTotal: Number(draft.pricing.couponDiscountTotal || 0),
      });
    }
    const deliveryPlan = buildGroupedDeliveryFeePlan(draftedStores);
    const groupTotals = {
      grossSubtotal: 0,
      productDiscountTotal: 0,
      couponDiscountTotal: 0,
      serviceFeeTotal: 0,
      deliveryFeeTotal: 0,
      rawDeliveryFeeTotal: deliveryPlan.rawDeliveryFeeTotal,
      allocatedDeliveryFeeTotal: deliveryPlan.allocatedDeliveryFeeTotal,
      totalAmount: 0,
    };
    for (const entry of deliveryPlan.entries) {
      groupTotals.grossSubtotal += Number(entry.grossSubtotal || 0);
      groupTotals.productDiscountTotal += Number(
        entry.productDiscountTotal || 0
      );
      groupTotals.couponDiscountTotal += Number(
        entry.couponDiscountTotal || 0
      );
      groupTotals.serviceFeeTotal += Number(entry.serviceFee || 0);
      groupTotals.deliveryFeeTotal += Number(entry.allocatedDeliveryFee || 0);
      groupTotals.totalAmount += Number(entry.totalAmount || 0);
    }
    const storesCount = storeOrders.length;
    const preview = {
      storesCount,
      totals: groupTotals,
      multiStoreDelayNotice:
        storesCount > 1
          ? "الطلب يحتوي على أكثر من متجر، وقد يستغرق وقتًا أطول قليلًا."
          : null,
    };

    const groupInsert = await client.query(
      `INSERT INTO order_group
        (
          public_id,
          customer_user_id,
          status,
          is_multi_store,
          stores_count,
          gross_subtotal,
          product_discount_total,
          coupon_discount_total,
          service_fee_total,
          delivery_fee_total,
          raw_delivery_fee_total,
          total_amount,
          payment_method,
          payment_status,
          notes
        )
       VALUES
        ($1,$2,'pending',$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,'pending_acceptance',$13)
       RETURNING *`,
      [
        buildOrderGroupPublicId(),
        Number(customer.id),
        storesCount > 1,
        storesCount,
        Number(preview.totals.grossSubtotal || 0),
        Number(preview.totals.productDiscountTotal || 0),
        Number(preview.totals.couponDiscountTotal || 0),
        Number(preview.totals.serviceFeeTotal || 0),
        Number(preview.totals.deliveryFeeTotal || 0),
        Number(preview.totals.rawDeliveryFeeTotal || 0),
        Number(preview.totals.totalAmount || 0),
        paymentMethod || "cash_on_delivery",
        note || null,
      ]
    );
    const orderGroup = groupInsert.rows[0];

    const childOrders = [];
    for (let index = 0; index < draftedStores.length; index += 1) {
      const entry = draftedStores[index];
      const feePlan = deliveryPlan.entries[index];
      const child = await createOrderWithItems({
        customer,
        deliveryAddress,
        merchantId: Number(entry.storeOrder.merchantId),
        note: entry.storeOrder.note || note || null,
        imageUrl: entry.storeOrder.imageUrl || null,
        couponId: entry.storeOrder.couponId ?? null,
        couponCode: entry.storeOrder.couponCode ?? null,
        normalizedItems: entry.storeOrder.normalizedItems,
        orderGroupId: Number(orderGroup.id),
        subOrderId: `${orderGroup.public_id}-${Number(feePlan.checkoutSequence || index + 1)}`,
        orderScope: "group_child",
        storeSequence: Number(feePlan.checkoutSequence || index + 1),
        deliveryFeeOverride: Number(feePlan.allocatedDeliveryFee || 0),
        deliveryFeeRaw: Number(feePlan.rawDeliveryFee || 0),
        txClient: client,
        suppressNotifications: true,
      });
      childOrders.push(child);

      await client.query(
        `INSERT INTO order_group_item_summary
          (
            order_group_id,
            child_order_id,
            merchant_id,
            merchant_name,
            status,
            subtotal,
            delivery_fee,
            raw_delivery_fee,
            total_amount
          )
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
         ON CONFLICT (order_group_id, child_order_id)
         DO UPDATE SET
           status = EXCLUDED.status,
           subtotal = EXCLUDED.subtotal,
           delivery_fee = EXCLUDED.delivery_fee,
           raw_delivery_fee = EXCLUDED.raw_delivery_fee,
           total_amount = EXCLUDED.total_amount,
           updated_at = NOW()`,
        [
          Number(orderGroup.id),
          Number(child.id),
          Number(child.merchant_id || child.merchantId || 0),
          String(child.merchant_name || child.merchantName || ""),
          String(child.status || "pending"),
          Number(child.subtotal || 0),
          Number(child.delivery_fee || child.deliveryFee || 0),
          Number(child.delivery_fee_raw || child.deliveryFeeRaw || child.deliveryFee || 0),
          Number(child.total_amount || child.totalAmount || 0),
        ]
      );
    }

    const status = summarizeOrderGroupStatus(childOrders.map((row) => row.status));
    await client.query(
      `UPDATE order_group
       SET status = $2,
           updated_at = NOW()
       WHERE id = $1`,
      [Number(orderGroup.id), status]
    );

    // Delivery closure §2: create the authoritative grouped delivery job + one
    // pickup stop per child order in the SAME checkout transaction. Idempotent
    // on retries. The job stays PENDING_STORES until stores accept — no courier
    // is assigned here.
    await ensureDeliveryJobForGroup(client, Number(orderGroup.id));

    await client.query("COMMIT");

    queueOrderSideEffect(async () => {
      const employeeNotifications = (
        await Promise.all(
          childOrders.map((child) =>
            buildMerchantOrderNotifications({
              merchantId: Number(child.merchant_id || 0),
              merchantName: String(child.merchant_name || ""),
              orderId: Number(child.id),
              status: String(child.status || "pending"),
            })
          )
        )
      ).flat();
      await createManyNotifications(
        [
          {
            userId: Number(customer.id),
            type: "order_group_created",
            title: "تم إنشاء الطلب",
            body:
              preview.storesCount > 1
                ? `تم إنشاء طلبك من ${preview.storesCount} متاجر بنجاح`
                : "تم إنشاء طلبك بنجاح",
            orderId: Number(childOrders[0]?.id || 0) || undefined,
            payload: {
              orderGroupId: Number(orderGroup.id),
              orderGroupPublicId: String(orderGroup.public_id || ""),
              status,
              storesCount: preview.storesCount,
            },
          },
          ...childOrders.flatMap((child) => [
            Number(child.owner_user_id || 0) > 0
              ? {
                  userId: Number(child.owner_user_id),
                  type: "owner_new_order",
                  title: "طلب جديد",
                  body: `طلب جديد رقم #${child.id} لدى ${child.merchant_name || ""}`,
                  orderId: Number(child.id),
                  merchantId: Number(child.merchant_id || 0),
                  payload: {
                    orderId: Number(child.id),
                    status: String(child.status || "pending"),
                    orderGroupId: Number(orderGroup.id),
                    requiresAction: true,
                    target: "merchant_order_details",
                  },
                }
              : null,
          ]),
          ...employeeNotifications,
        ].filter(Boolean)
      );

    });

    return {
      mode: preview.storesCount > 1 ? "multi_store" : "single_store",
      orderGroup: {
        ...orderGroup,
        status,
        rawDeliveryFeeTotal: Number(
          orderGroup.raw_delivery_fee_total || preview.totals.rawDeliveryFeeTotal || 0
        ),
        allocatedDeliveryFeeTotal: Number(
          orderGroup.delivery_fee_total || preview.totals.deliveryFeeTotal || 0
        ),
      },
      storesCount: preview.storesCount,
      multiStoreDelayNotice: preview.multiStoreDelayNotice,
      children: childOrders,
      totals: preview.totals,
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function getCustomerOrderGroupDetails(customerUserId, groupId) {
  const numericGroupId = Number(groupId);
  if (!Number.isInteger(numericGroupId) || numericGroupId <= 0) return null;

  const groupResult = await q(
    `SELECT *
     FROM order_group
     WHERE id = $1
       AND customer_user_id = $2
     LIMIT 1`,
    [numericGroupId, Number(customerUserId)]
  );
  const group = groupResult.rows[0];
  if (!group) return null;

  const ordersResult = await q(
    `${orderSelect}
     WHERE o.customer_user_id = $1
       AND o.order_group_id = $2
     ORDER BY o.store_sequence ASC, o.id ASC`,
    [Number(customerUserId), Number(group.id)]
  );
  const children = await attachItems(ordersResult.rows);

  const summariesResult = await q(
    `SELECT *
     FROM order_group_item_summary
     WHERE order_group_id = $1
     ORDER BY id ASC`,
    [Number(group.id)]
  );

  const status = summarizeOrderGroupStatus(children.map((row) => row.status));

  return {
    ...group,
    status,
    children,
    storeSummaries: summariesResult.rows,
    totals: {
      grossSubtotal: Number(group.gross_subtotal || 0),
      productDiscountTotal: Number(group.product_discount_total || 0),
      couponDiscountTotal: Number(group.coupon_discount_total || 0),
      serviceFeeTotal: Number(group.service_fee_total || 0),
      deliveryFeeTotal: Number(group.delivery_fee_total || 0),
      rawDeliveryFeeTotal: Number(
        group.raw_delivery_fee_total || group.delivery_fee_total || 0
      ),
      allocatedDeliveryFeeTotal: Number(group.delivery_fee_total || 0),
      totalAmount: Number(group.total_amount || 0),
    },
  };
}

export async function listCustomerOrders(
  customerUserId,
  { paginate = false, limit = null, offset = 0 } = {}
) {
  const usePagination = paginate === true;
  const safeLimit =
    usePagination
      ? Math.max(1, Math.min(120, Number(limit) || 40))
      : null;
  const safeOffset = usePagination ? Math.max(0, Number(offset) || 0) : 0;
  const sql = usePagination
    ? `${orderSelect}
       WHERE o.customer_user_id=$1
       ORDER BY o.id DESC
       LIMIT $2 OFFSET $3`
    : `${orderSelect}
       WHERE o.customer_user_id=$1
       ORDER BY o.id DESC`;
  const params = usePagination
    ? [customerUserId, safeLimit, safeOffset]
    : [customerUserId];
  const r = await q(sql, params);
  return attachItems(r.rows);
}

export async function findCustomerOrder(customerUserId, orderId) {
  const r = await q(
    `${orderSelect}
     WHERE o.customer_user_id=$1
       AND o.id=$2`,
    [customerUserId, orderId]
  );
  const rows = await attachItems(r.rows);
  return rows[0] || null;
}

export async function getLatestCourierPresence(courierUserId) {
  const r = await q(
    `SELECT
       courier_user_id,
       current_order_id,
       latitude,
       longitude,
       heading_deg,
       speed_kmh,
       accuracy_m,
       is_online,
       recorded_at,
       updated_at
     FROM courier_presence
     WHERE courier_user_id = $1
     LIMIT 1`,
    [Number(courierUserId)]
  );
  return mapCourierPresence(r.rows[0]);
}

export async function getOrderLatestCourierPresence(orderId) {
  const r = await q(
    `SELECT
       cp.courier_user_id,
       cp.current_order_id,
       cp.latitude,
       cp.longitude,
       cp.heading_deg,
       cp.speed_kmh,
       cp.accuracy_m,
       cp.is_online,
       cp.recorded_at,
       cp.updated_at
     FROM courier_presence cp
     JOIN customer_order o ON o.delivery_user_id = cp.courier_user_id
     WHERE o.id = $1
       AND cp.latitude IS NOT NULL
       AND cp.longitude IS NOT NULL
     LIMIT 1`,
    [Number(orderId)]
  );
  return mapCourierPresence(r.rows[0]);
}

export async function upsertCourierPresence({
  courierUserId,
  orderId = null,
  latitude,
  longitude,
  headingDeg = null,
  speedKmh = null,
  accuracyM = null,
  isOnline = true,
}) {
  const r = await q(
    `INSERT INTO courier_presence
       (
         courier_user_id,
         current_order_id,
         latitude,
         longitude,
         heading_deg,
         speed_kmh,
         accuracy_m,
         is_online,
         recorded_at,
         updated_at
       )
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,NOW(),NOW())
     ON CONFLICT (courier_user_id)
     DO UPDATE SET
       current_order_id = EXCLUDED.current_order_id,
       latitude = EXCLUDED.latitude,
       longitude = EXCLUDED.longitude,
       heading_deg = EXCLUDED.heading_deg,
       speed_kmh = EXCLUDED.speed_kmh,
       accuracy_m = EXCLUDED.accuracy_m,
       is_online = EXCLUDED.is_online,
       recorded_at = NOW(),
       updated_at = NOW()
     RETURNING
       courier_user_id,
       current_order_id,
       latitude,
       longitude,
       heading_deg,
       speed_kmh,
       accuracy_m,
       is_online,
       recorded_at,
       updated_at`,
    [
      Number(courierUserId),
      orderId == null ? null : Number(orderId),
      latitude,
      longitude,
      headingDeg,
      speedKmh,
      accuracyM,
      isOnline === false ? false : true,
    ]
  );
  return mapCourierPresence(r.rows[0]);
}

export async function findCourierTrackableOrder(courierUserId, orderId) {
  const r = await q(
    `${orderSelect}
     WHERE o.id = $1
       AND o.delivery_user_id = $2
       AND o.delivery_assignment_status = 'ASSIGNED'
       AND o.status IN ('ready_for_delivery','on_the_way','arrived')
     LIMIT 1`,
    [Number(orderId), Number(courierUserId)]
  );
  const rows = await attachItems(r.rows);
  return rows[0] || null;
}

export function isCourierTrackableOrderStatus(status) {
  return ["ready_for_delivery", "on_the_way", "arrived"].includes(
    String(status || "").trim().toLowerCase()
  );
}

export async function getCustomerOrderTrackingSnapshot(customerUserId, orderId) {
  const order = await findCustomerOrder(Number(customerUserId), Number(orderId));
  if (!order) return null;
  const latestLocation = order.delivery_user_id
    ? await getLatestCourierPresence(order.delivery_user_id)
    : null;
  const activeShareRes = await q(
    `SELECT share_token, expires_at, revoked_at
     FROM customer_order_share_token
     WHERE order_id = $1
     LIMIT 1`,
    [Number(orderId)]
  );
  const share = activeShareRes.rows[0]
    ? {
        token: activeShareRes.rows[0].share_token,
        expiresAt: activeShareRes.rows[0].expires_at || null,
        revokedAt: activeShareRes.rows[0].revoked_at || null,
      }
    : null;

  return buildOrderTrackingEnvelope(order, {
    viewerMode: "owner",
    latestLocation,
    share,
  });
}

/**
 * Pure permission resolver for order tracking. Returns the viewer mode
 * ('admin' | 'customer' | 'delivery' | 'merchant') the user is entitled to,
 * or null when they have no access. Side-effect free so it can be unit tested
 * without a database (exposed via __ordersRepoTestables).
 */
function resolveTrackingViewerMode({ role, isSuperAdmin = false, viewerId, order }) {
  const normalizedRole = String(role || "").trim().toLowerCase();
  const isAdmin =
    isSuperAdmin === true ||
    normalizedRole === "admin" ||
    normalizedRole === "deputy_admin" ||
    normalizedRole === "company";
  const id = Number(viewerId || 0);
  if (isAdmin) return "admin";
  if (id > 0 && Number(order?.customer_user_id || 0) === id) return "customer";
  if (
    normalizedRole === "delivery" &&
    Number(order?.delivery_user_id || 0) > 0 &&
    Number(order?.delivery_user_id) === id &&
    normalizeDeliveryAssignmentStatus(order?.delivery_assignment_status) ===
      DELIVERY_ASSIGNMENT_STATUSES.ASSIGNED
  ) {
    return "delivery";
  }
  if (
    (normalizedRole === "owner" || normalizedRole === "merchant") &&
    id > 0 &&
    Number(order?.owner_user_id || 0) === id
  ) {
    return "merchant";
  }
  return null;
}

/**
 * Role-aware tracking snapshot. Resolves the viewer mode for the order and
 * returns the same payload shape the customer tracking screen consumes, so
 * every role (customer/delivery/merchant/admin) renders the live map without
 * a 403. Returns `{ notFound }` / `{ forbidden }` markers for the service to
 * translate into HTTP errors.
 */
export async function getOrderTrackingSnapshotForViewer({
  viewerUserId,
  viewerRole,
  isSuperAdmin = false,
  orderId,
}) {
  const res = await q(
    `${orderSelect}
     WHERE o.id = $1
     LIMIT 1`,
    [Number(orderId)]
  );
  const attached = await attachItems(res.rows);
  const order = attached[0] || null;
  if (!order) return { notFound: true };

  const viewerMode = resolveTrackingViewerMode({
    role: viewerRole,
    isSuperAdmin,
    viewerId: viewerUserId,
    order,
  });
  if (!viewerMode) return { forbidden: true };

  const latestLocation = order.delivery_user_id
    ? await getLatestCourierPresence(order.delivery_user_id)
    : null;

  let share = null;
  if (viewerMode === "customer" || viewerMode === "admin") {
    const activeShareRes = await q(
      `SELECT share_token, expires_at, revoked_at
       FROM customer_order_share_token
       WHERE order_id = $1
       LIMIT 1`,
      [Number(orderId)]
    );
    share = activeShareRes.rows[0]
      ? {
          token: activeShareRes.rows[0].share_token,
          expiresAt: activeShareRes.rows[0].expires_at || null,
          revokedAt: activeShareRes.rows[0].revoked_at || null,
        }
      : null;
  }

  return {
    snapshot: buildOrderTrackingEnvelope(order, {
      viewerMode,
      latestLocation,
      share,
    }),
  };
}

export async function createCustomerOrderShareToken(customerUserId, orderId) {
  const order = await findCustomerOrder(Number(customerUserId), Number(orderId));
  if (!order) return null;
  const token = createPublicOrderShareToken();
  const r = await q(
    `INSERT INTO customer_order_share_token
       (order_id, customer_user_id, share_token, revoked_at, updated_at)
     VALUES ($1,$2,$3,NULL,NOW())
     ON CONFLICT (order_id)
     DO UPDATE SET
       customer_user_id = EXCLUDED.customer_user_id,
       share_token = EXCLUDED.share_token,
       revoked_at = NULL,
       updated_at = NOW()
     RETURNING share_token, expires_at, revoked_at`,
    [Number(orderId), Number(customerUserId), token]
  );
  const row = r.rows[0];
  return row
    ? {
        orderId: Number(orderId),
        token: row.share_token,
        expiresAt: row.expires_at || null,
        revokedAt: row.revoked_at || null,
      }
    : null;
}

export async function getPublicOrderTrackingByToken(token) {
  const shareRes = await q(
    `SELECT order_id
     FROM customer_order_share_token
     WHERE share_token = $1
       AND revoked_at IS NULL
       AND (expires_at IS NULL OR expires_at > NOW())
     LIMIT 1`,
    [String(token)]
  );
  const orderId = shareRes.rows[0]?.order_id;
  if (!orderId) return null;

  const r = await q(
    `${orderSelect}
     WHERE o.id = $1
     LIMIT 1`,
    [Number(orderId)]
  );
  const rows = await attachItems(r.rows);
  const order = rows[0];
  if (!order) return null;
  const latestLocation = order.delivery_user_id
    ? await getLatestCourierPresence(order.delivery_user_id)
    : null;
  return buildOrderTrackingEnvelope(order, {
    viewerMode: "publicReadonly",
    latestLocation,
  });
}

export async function cancelOrderByCustomer({
  customerUserId,
  orderId,
  reasonCode,
  reasonText = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const updated = await client.query(
      `UPDATE customer_order
       SET status = 'cancelled_by_customer'::order_status,
           cancelled_by_role = 'customer',
           cancellation_reason_code = $3,
           cancellation_reason_text = $4,
           updated_at = NOW()
       WHERE id = $1
         AND customer_user_id = $2
         AND status IN ('pending','approved','preparing','courier_requested')
       RETURNING id, merchant_id, order_group_id, status`,
      [Number(orderId), Number(customerUserId), String(reasonCode), reasonText]
    );
    const row = updated.rows[0];
    if (!row) {
      await client.query("ROLLBACK");
      return null;
    }

    await client.query(
      `INSERT INTO order_action_event
        (order_id, actor_user_id, actor_scope, action_kind, reason_code, reason_text)
       VALUES ($1,$2,'customer','cancel',$3,$4)`,
      [Number(row.id), Number(customerUserId), String(reasonCode), reasonText]
    );

    await syncOrderIncentiveConsumptionForStatusTx(client, {
      orderId: Number(row.id),
      status: "cancelled_by_customer",
    });

    await transitionInventoryReservationsTx(client, row.id, "released");

    await syncOrderGroupStatusTx(client, row.order_group_id);

    await client.query("COMMIT");
    return {
      ok: true,
      orderId: Number(row.id),
      status: String(row.status || "cancelled_by_customer"),
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function requestOrderReturnByCustomer({
  customerUserId,
  orderId,
  reasonCode,
  reasonText = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const updated = await client.query(
      `UPDATE customer_order
       SET return_requested_at = NOW(),
           returned_by_role = 'customer',
           return_reason_code = $3,
           return_reason_text = $4,
           return_window_expires_at = COALESCE(return_window_expires_at, delivered_at + interval '24 hour'),
           updated_at = NOW()
       WHERE id = $1
         AND customer_user_id = $2
         AND status IN ('delivered','completed','received_by_customer')
         AND COALESCE(delivered_at, created_at) >= NOW() - interval '24 hour'
       RETURNING id, merchant_id, order_group_id, status, return_requested_at`,
      [Number(orderId), Number(customerUserId), String(reasonCode), reasonText]
    );
    const row = updated.rows[0];
    if (!row) {
      await client.query("ROLLBACK");
      return null;
    }

    await client.query(
      `INSERT INTO order_action_event
        (order_id, actor_user_id, actor_scope, action_kind, reason_code, reason_text)
       VALUES ($1,$2,'customer','return',$3,$4)`,
      [Number(row.id), Number(customerUserId), String(reasonCode), reasonText]
    );

    await client.query("COMMIT");
    return {
      ok: true,
      orderId: Number(row.id),
      status: String(row.status || ""),
      returnRequestedAt: row.return_requested_at,
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function confirmOrderDelivered(customerUserId, orderId) {
  const r = await q(
    `UPDATE customer_order
     SET customer_confirmed_at = COALESCE(customer_confirmed_at, NOW())
     WHERE id=$1
       AND customer_user_id=$2
       AND status='delivered'
     RETURNING
       id,
       merchant_id,
       delivery_user_id,
       (SELECT owner_user_id FROM merchant WHERE id = customer_order.merchant_id) AS owner_user_id`,
    [orderId, customerUserId]
  );
  const row = r.rows[0];
  if (!row) return false;

  await createManyNotifications(
    [
      row.delivery_user_id
        ? {
            userId: row.delivery_user_id,
            type: "delivery_customer_confirmed",
            title: "تأكيد استلام",
            body: `الزبون أكد استلام الطلب #${row.id}`,
            orderId: row.id,
            merchantId: row.merchant_id,
            payload: {
              orderId: row.id,
            },
          }
        : null,
      row.owner_user_id
        ? {
            userId: row.owner_user_id,
            type: "owner_customer_confirmed",
            title: "تم تأكيد الاستلام",
            body: `الزبون أكد استلام الطلب #${row.id}`,
            orderId: row.id,
            merchantId: row.merchant_id,
            payload: {
              orderId: row.id,
            },
          }
        : null,
    ].filter(Boolean)
  );

  return true;
}

export async function rateDelivery(customerUserId, orderId, rating, review) {
  const r = await q(
    `UPDATE customer_order
     SET delivery_rating=$1,
         delivery_review=$2,
         rated_at=NOW()
     WHERE id=$3
       AND customer_user_id=$4
       AND status IN ('delivered','completed')
       AND delivery_user_id IS NOT NULL
     RETURNING
       id,
       merchant_id,
       delivery_user_id,
       (SELECT owner_user_id FROM merchant WHERE id = customer_order.merchant_id) AS owner_user_id`,
    [rating, review || null, orderId, customerUserId]
  );
  const row = r.rows[0];
  if (!row) return false;

  await createManyNotifications(
    [
      row.delivery_user_id
        ? {
            userId: row.delivery_user_id,
            type: "delivery_rated",
            title: "تقييم جديد",
            body: `تم تقييمك على الطلب #${row.id} بـ ${rating}/5`,
            orderId: row.id,
            merchantId: row.merchant_id,
            payload: {
              orderId: row.id,
              rating,
            },
          }
        : null,
      row.owner_user_id
        ? {
            userId: row.owner_user_id,
            type: "owner_delivery_rated",
            title: "تقييم توصيل",
            body: `تم تقييم الدلفري في الطلب #${row.id} بـ ${rating}/5`,
            orderId: row.id,
            merchantId: row.merchant_id,
            payload: {
              orderId: row.id,
              rating,
            },
          }
        : null,
    ].filter(Boolean)
  );

  return true;
}

export async function rateMerchant(customerUserId, orderId, rating, review) {
  const client = await pool.connect();
  let orderRow = null;
  try {
    await client.query("BEGIN");

    const orderRowResult = await client.query(
      `SELECT
         o.id,
         o.merchant_id,
         m.owner_user_id
       FROM customer_order o
       JOIN merchant m ON m.id = o.merchant_id
       WHERE o.id = $1
         AND o.customer_user_id = $2
         AND o.status IN ('delivered','completed')
       FOR UPDATE`,
      [Number(orderId), Number(customerUserId)]
    );
    orderRow = orderRowResult.rows[0];
    if (!orderRow) {
      await client.query("ROLLBACK");
      return false;
    }

    await client.query(
      `SELECT pg_advisory_xact_lock(hashtext($1))`,
      [`merchant-review:${Number(customerUserId)}:${Number(orderRow.merchant_id)}`]
    );

    const existingReviewResult = await client.query(
      `SELECT id, merchant_id, social_post_id
       FROM merchant_verified_review
       WHERE customer_user_id = $1
         AND merchant_id = $2
         AND review_state IN ('active', 'restored')
       ORDER BY updated_at DESC, id DESC
       LIMIT 1`,
      [Number(customerUserId), Number(orderRow.merchant_id)]
    );
    const existingReview = existingReviewResult.rows[0];
    if (existingReview) {
      await client.query("ROLLBACK");
      return {
        ok: false,
        conflict: {
          existingReviewId: Number(existingReview.id),
          existingPostId:
            existingReview.social_post_id == null
              ? null
              : Number(existingReview.social_post_id),
          merchantId: Number(existingReview.merchant_id),
        },
      };
    }

    await client.query(
      `UPDATE customer_order
       SET merchant_rating=$1,
           merchant_review=$2,
           merchant_rated_at=NOW()
       WHERE id=$3`,
      [rating, review || null, Number(orderRow.id)]
    );

    const socialPost = await insertMerchantReviewSocialPostTx(client, {
      customerUserId,
      merchantId: orderRow.merchant_id,
      orderId: orderRow.id,
      rating,
      review,
    });
    if (!socialPost?.id) {
      throw new AppError("MERCHANT_REVIEW_POST_CREATE_FAILED", { status: 500 });
    }

    await client.query(
      `INSERT INTO merchant_verified_review
        (
          order_id,
          merchant_id,
          customer_user_id,
          social_post_id,
          rating,
          review_text,
          is_verified,
          review_state,
          review_deleted_at,
          review_deleted_by_user_id,
          review_moderated_at,
          review_moderated_by_user_id,
          review_moderation_note,
          metadata_json
        )
       VALUES ($1,$2,$3,$4,$5,$6,TRUE,'active',NULL,NULL,NULL,NULL,NULL,$7::jsonb)`,
      [
        Number(orderRow.id),
        Number(orderRow.merchant_id),
        Number(customerUserId),
        Number(socialPost.id),
        Number(rating),
        review || null,
        JSON.stringify({
          source: "customer_order_rate_merchant",
          orderId: Number(orderRow.id),
          socialPostId: Number(socialPost.id),
        }),
      ]
    );

    await merchantReviewNotificationOutboxWriter(client, {
      orderId: orderRow.id,
      merchantId: orderRow.merchant_id,
      customerUserId,
      ownerUserId: orderRow.owner_user_id,
      rating,
      reviewPostId: socialPost.id,
    });

    await client.query("COMMIT");

    return true;
  } catch (error) {
    try {
      await client.query("ROLLBACK");
    } catch {
      // noop
    }

    if (Number(error?.code || 0) === 23505) {
      const conflictReview = await q(
        `SELECT id, merchant_id, social_post_id
         FROM merchant_verified_review
         WHERE customer_user_id = $1
           AND merchant_id = $2
           AND review_state IN ('active', 'restored')
         ORDER BY updated_at DESC, id DESC
         LIMIT 1`,
        [Number(customerUserId), Number(orderRow?.merchant_id || 0)]
      );
      const row = conflictReview.rows[0];
      if (row) {
        return {
          ok: false,
          conflict: {
            existingReviewId: Number(row.id),
            existingPostId:
              row.social_post_id == null ? null : Number(row.social_post_id),
            merchantId: Number(row.merchant_id),
          },
        };
      }
    }

    throw error;
  } finally {
    client.release();
  }
}

export async function listOwnerCurrentOrders(ownerUserId) {
  const r = await q(
    `${orderSelect}
     JOIN merchant mo ON mo.id = o.merchant_id
     WHERE mo.owner_user_id=$1
       AND o.status NOT IN ('cancelled','cancelled_by_customer','cancelled_by_store','cancelled_by_admin')
     ORDER BY o.id DESC`,
    [ownerUserId]
  );
  const rows = await attachItems(r.rows);
  return rows
    .filter((row) => isOwnerCurrentStatus(row.status, row.customer_confirmed_at))
    .sort((a, b) => {
      const rank = currentStatusRank(a.status) - currentStatusRank(b.status);
      if (rank !== 0) return rank;
      return Number(b.id) - Number(a.id);
    });
}

export async function listOwnerOrderHistory(ownerUserId, archiveDate) {
  const params = [ownerUserId];
  let dateSql = "";
  if (archiveDate) {
    params.push(archiveDate);
    dateSql = "AND DATE(o.delivered_at) = $2";
  }

  const r = await q(
    `${orderSelect}
     JOIN merchant mo ON mo.id = o.merchant_id
     WHERE mo.owner_user_id=$1
       AND o.archived_by_delivery = TRUE
       ${dateSql}
     ORDER BY o.id DESC`,
    params
  );
  return attachItems(r.rows);
}

export async function listAdminOrdersForReport(period) {
  const normalizedPeriod = normalizeReportPeriod(period);
  if (!normalizedPeriod) {
    const err = new Error("INVALID_PERIOD");
    err.status = 400;
    throw err;
  }
  const timeFilter = buildReportTimeFilter(normalizedPeriod);

  const r = await q(
    `${orderSelect}
     ${timeFilter ? `WHERE ${timeFilter}` : ""}
     ORDER BY o.created_at DESC`,
    []
  );
  return attachItems(r.rows);
}

export async function listAdminMerchantOrderOverview({
  status = "all",
  period = "all",
  from = null,
  to = null,
  search = null,
  limit = 60,
  offset = 0,
} = {}) {
  const normalizedStatus = normalizeAdminOrderOverviewStatus(status);
  const normalizedPeriod = normalizeAdminOverviewPeriod(period);
  const safeLimit = Math.max(1, Math.min(200, Number(limit) || 60));
  const safeOffset = Math.max(0, Number(offset) || 0);

  const summaryParams = [];
  const summaryClauses = ["1=1"];
  appendAdminOrderDateWindow({
    clauses: summaryClauses,
    params: summaryParams,
    alias: "o",
    period: normalizedPeriod,
    from,
    to,
  });

  const summaryResult = await q(
    `SELECT
       COUNT(*)::int AS total_orders,
       COUNT(*) FILTER (
         WHERE o.status IN ('delivered', 'delivered_by_courier', 'received_by_customer', 'completed')
       )::int AS completed_orders,
       COUNT(*) FILTER (WHERE o.status IN ('cancelled', 'cancelled_by_store', 'cancelled_by_admin', 'cancelled_by_customer'))::int AS cancelled_orders,
       COUNT(*) FILTER (
         WHERE o.status NOT IN ('delivered', 'delivered_by_courier', 'received_by_customer', 'completed', 'cancelled', 'cancelled_by_store', 'cancelled_by_admin', 'cancelled_by_customer')
       )::int AS in_progress_orders
     FROM customer_order o
     WHERE ${summaryClauses.join(" AND ")}`,
    summaryParams
  );

  const merchantParams = [];
  const merchantClauses = [adminOrderStatusFilterSql(normalizedStatus, "o")];
  appendAdminOrderDateWindow({
    clauses: merchantClauses,
    params: merchantParams,
    alias: "o",
    period: normalizedPeriod,
    from,
    to,
  });

  const safeSearch = String(search || "").trim();
  let merchantSearchSql = "";
  if (safeSearch) {
    merchantParams.push(`%${safeSearch}%`);
    const placeholder = `$${merchantParams.length}`;
    merchantSearchSql = ` AND (
      m.name ILIKE ${placeholder}
      OR COALESCE(m.phone, '') ILIKE ${placeholder}
      OR COALESCE(u.full_name, '') ILIKE ${placeholder}
      OR COALESCE(u.phone, '') ILIKE ${placeholder}
    )`;
  }

  const merchantRows = await q(
    `SELECT
       m.id AS merchant_id,
       m.name AS merchant_name,
       m.type AS merchant_type,
       m.phone AS merchant_phone,
       u.id AS owner_user_id,
       u.full_name AS owner_full_name,
       u.phone AS owner_phone,
       COUNT(o.id)::int AS orders_count,
       MAX(o.created_at) AS last_order_at
     FROM merchant m
     LEFT JOIN app_user u ON u.id = m.owner_user_id
     JOIN customer_order o ON o.merchant_id = m.id
     WHERE ${merchantClauses.join(" AND ")}${merchantSearchSql}
     GROUP BY m.id, u.id
     ORDER BY orders_count DESC, last_order_at DESC NULLS LAST, m.id DESC
     LIMIT ${safeLimit} OFFSET ${safeOffset}`,
    merchantParams
  );

  const countRows = await q(
    `SELECT COUNT(*)::int AS total
     FROM (
       SELECT m.id
       FROM merchant m
       LEFT JOIN app_user u ON u.id = m.owner_user_id
       JOIN customer_order o ON o.merchant_id = m.id
       WHERE ${merchantClauses.join(" AND ")}${merchantSearchSql}
       GROUP BY m.id
     ) overview`,
    merchantParams
  );

  return {
    summary: summaryResult.rows[0] || {
      total_orders: 0,
      completed_orders: 0,
      cancelled_orders: 0,
      in_progress_orders: 0,
    },
    items: merchantRows.rows,
    total: Number(countRows.rows[0]?.total || 0),
    filters: {
      status: normalizedStatus,
      period: normalizedPeriod,
      from,
      to,
      search: safeSearch || null,
      limit: safeLimit,
      offset: safeOffset,
    },
  };
}

export async function listAdminMerchantOrdersOverview({
  merchantId,
  status = "all",
  period = "all",
  from = null,
  to = null,
  limit = 80,
  offset = 0,
} = {}) {
  const safeMerchantId = Number(merchantId);
  if (!Number.isInteger(safeMerchantId) || safeMerchantId <= 0) {
    throw new AppError("INVALID_MERCHANT_ID", 400);
  }

  const normalizedStatus = normalizeAdminOrderOverviewStatus(status);
  const normalizedPeriod = normalizeAdminOverviewPeriod(period);
  const safeLimit = Math.max(1, Math.min(200, Number(limit) || 80));
  const safeOffset = Math.max(0, Number(offset) || 0);

  const params = [safeMerchantId];
  const clauses = [
    "o.merchant_id = $1",
    adminOrderStatusFilterSql(normalizedStatus, "o"),
  ];
  appendAdminOrderDateWindow({
    clauses,
    params,
    alias: "o",
    period: normalizedPeriod,
    from,
    to,
  });

  const merchantResult = await q(
    `SELECT
       m.id,
       m.name,
       m.type,
       m.phone,
       u.id AS owner_user_id,
       u.full_name AS owner_full_name,
       u.phone AS owner_phone
     FROM merchant m
     LEFT JOIN app_user u ON u.id = m.owner_user_id
     WHERE m.id = $1
     LIMIT 1`,
    [safeMerchantId]
  );
  const merchant = merchantResult.rows[0];
  if (!merchant) {
    throw new AppError("MERCHANT_NOT_FOUND", 404);
  }

  const rowsResult = await q(
    `${orderSelect}
     WHERE ${clauses.join(" AND ")}
     ORDER BY o.created_at DESC, o.id DESC
     LIMIT ${safeLimit} OFFSET ${safeOffset}`,
    params
  );

  const countResult = await q(
    `SELECT COUNT(*)::int AS total
     FROM customer_order o
     WHERE ${clauses.join(" AND ")}`,
    params
  );

  return {
    merchant,
    items: await attachItems(rowsResult.rows),
    total: Number(countResult.rows[0]?.total || 0),
    filters: {
      status: normalizedStatus,
      period: normalizedPeriod,
      from,
      to,
      limit: safeLimit,
      offset: safeOffset,
    },
  };
}

export async function listOwnerOrdersForReport(ownerUserId, period) {
  const normalizedPeriod = normalizeReportPeriod(period);
  if (!normalizedPeriod) {
    const err = new Error("INVALID_PERIOD");
    err.status = 400;
    throw err;
  }
  const timeFilter = buildReportTimeFilter(normalizedPeriod);

  const r = await q(
    `${orderSelect}
     WHERE m.owner_user_id = $1
       ${timeFilter ? `AND ${timeFilter}` : ""}
     ORDER BY o.created_at DESC`,
    [ownerUserId]
  );
  return attachItems(r.rows);
}

/**
 * يطبق transition يدوية من المتجر/المالك على حالة الطلب مع timestamps
 * والإشعارات ومزامنة incentive state.
 *
 * Maintenance notes:
 * - إذا ظهرت حالة طلب عالقة أو إشعار غير مطابق، ابدأ من:
 *   `assertOwnerTransition` ثم UPDATE statement ثم createManyNotifications.
 */
/**
 * يحدث حالة الطلب من منظور مالك المتجر مع فرض ownership check واضح.
 *
 * Side effects:
 * - يكتب status timestamps مختلفة بحسب الانتقال
 * - قد يطلق إشعارات للعميل أو الدليفري حسب الحالة الناتجة
 *
 * Critical notes:
 * - هذه الدالة تفصل بين صلاحية owner وصلاحية delivery؛ لا تخلطها مع
 *   transitions الخاصة بالمندوب.
 */
export async function updateOwnerOrderStatus(
  ownerUserId,
  orderId,
  status,
  estimatedPrepMinutes,
  estimatedDeliveryMinutes
) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const currentResult = await client.query(
       `SELECT
          o.id,
          o.merchant_id,
          o.order_group_id,
          o.status,
          o.customer_user_id,
          o.customer_block,
          o.delivery_user_id,
          o.is_merchant_delivery,
          o.assigned_by_store,
          m.owner_user_id,
          m.name AS merchant_name
        FROM customer_order o
        JOIN merchant m ON m.id = o.merchant_id
        WHERE o.id=$1
         AND m.owner_user_id=$2
       FOR UPDATE`,
      [Number(orderId), Number(ownerUserId)]
    );

    const current = currentResult.rows[0];
    if (!current) {
      await client.query("ROLLBACK");
      return false;
    }

    const deliveryUserId = current.delivery_user_id
      ? Number(current.delivery_user_id)
      : null;
    const isMerchantDelivery = current.is_merchant_delivery === true;
    const hasAppDeliveryAssignment = current.assigned_by_store === true;

    assertOwnerTransition({
      currentStatus: current.status,
      nextStatus: status,
      deliveryUserId,
      isMerchantDelivery,
      hasAppDeliveryAssignment,
    });

    const updateResult = await client.query(
      `UPDATE customer_order o
       SET status=$1::order_status,
           delivery_assignment_status = CASE
             WHEN $1::text = 'cancelled' THEN 'CANCELLED'
             WHEN $1::text IN ('delivered', 'completed') THEN 'COMPLETED'
             WHEN $1::text IN ('approved', 'preparing', 'ready_for_delivery', 'ready_for_pickup')
               AND o.delivery_user_id IS NULL
             THEN 'PENDING_NO_DRIVER'
             WHEN o.delivery_user_id IS NOT NULL THEN 'ASSIGNED'
             ELSE COALESCE(o.delivery_assignment_status, 'NOT_REQUIRED')
           END,
           estimated_prep_minutes=COALESCE($2::int, o.estimated_prep_minutes),
           estimated_delivery_minutes=COALESCE($3::int, o.estimated_delivery_minutes),
           approved_at = CASE
             WHEN $4::boolean THEN COALESCE(o.approved_at, NOW())
             ELSE o.approved_at
           END,
           preparing_started_at = CASE
             WHEN $5::boolean THEN COALESCE(o.preparing_started_at, NOW())
             ELSE o.preparing_started_at
           END,
           prepared_at = CASE
             WHEN $6::boolean THEN COALESCE(o.prepared_at, NOW())
             ELSE o.prepared_at
           END,
           picked_up_at = CASE
             WHEN $7::boolean THEN COALESCE(o.picked_up_at, NOW())
             ELSE o.picked_up_at
           END,
           arrived_at = CASE
             WHEN $8::boolean THEN COALESCE(o.arrived_at, NOW())
             ELSE o.arrived_at
           END,
           delivered_at = CASE
             WHEN $9::boolean THEN COALESCE(o.delivered_at, NOW())
             ELSE o.delivered_at
           END
       WHERE o.id=$10
       RETURNING
         o.id,
         o.merchant_id,
         o.order_group_id,
         o.status,
         o.customer_user_id,
         o.delivery_user_id,
         o.is_merchant_delivery`,
      [
        status,
        estimatedPrepMinutes,
        estimatedDeliveryMinutes,
        ["approved", "preparing", "ready_for_delivery"].includes(status),
        status === "preparing",
        status === "ready_for_delivery",
        status === "on_the_way",
        status === "arrived",
        status === "delivered",
        Number(orderId),
      ]
    );

    const updated = updateResult.rows[0];
    if (status === "approved") {
      await transitionInventoryReservationsTx(client, orderId, "consumed");
    } else if (status === "delivered") {
      await transitionInventoryReservationsTx(client, orderId, "completed");
    } else if (status === "cancelled") {
      await transitionInventoryReservationsTx(client, orderId, "released");
    }

    if (["cancelled", "delivered"].includes(String(status))) {
      await client.query(
        `UPDATE courier_assignment
         SET ended_at = COALESCE(ended_at, NOW()),
             ended_reason = COALESCE(
               ended_reason,
               CASE
                 WHEN $2::text = 'cancelled' THEN 'ORDER_CANCELLED'
                 WHEN $2::text = 'delivered' THEN 'COMPLETED'
                 ELSE 'RELEASED'
               END
             ),
             status = CASE
               WHEN status IN ('assigned', 'accepted') AND $2::text = 'cancelled' THEN 'cancelled'
               WHEN status IN ('assigned', 'accepted') AND $2::text = 'delivered' THEN 'completed'
               ELSE status
             END
         WHERE order_id = $1
           AND ended_at IS NULL`,
        [Number(orderId), String(status)]
      );
    }

    await syncOrderGroupStatusTx(client, updated.order_group_id);
    await syncOrderIncentiveConsumptionForStatusTx(client, {
      orderId: Number(orderId),
      nextStatus: String(status),
      reason: `owner_status_transition:${String(status || "").trim() || "updated"}`,
    });

    // Delivery closure §3: for a multi-store group child, keep the grouped
    // delivery job in sync with this store's acceptance/cancellation and
    // recompute grouped readiness inside the SAME transaction. When every active
    // child is accepted the job flips to READY_FOR_ASSIGNMENT; when the last
    // active child is cancelled it flips to CANCELLED. The grouped worker (not
    // the per-child worker) then assigns exactly one courier.
    const orderGroupId = updated.order_group_id
      ? Number(updated.order_group_id)
      : null;
    if (orderGroupId) {
      await ensureDeliveryJobForGroup(client, orderGroupId);
      await recomputeGroupReadiness(client, orderGroupId);
    }

    await client.query("COMMIT");

    const shouldTriggerRecovery =
      ["cancelled", "delivered", "ready_for_delivery"].includes(String(status)) ||
      (orderGroupId != null &&
        ["approved", "preparing"].includes(String(status)));
    if (shouldTriggerRecovery) {
      void requestDeliveryAssignmentRecovery({ limit: 25 }).catch((error) => {
        console.error("[delivery-assignment] recovery trigger failed", {
          orderId: Number(orderId),
          status,
          error: error?.message || String(error),
        });
      });
    }

    await createManyNotifications(
      [
        {
          userId: current.customer_user_id,
          type: "customer_order_status",
          title: "تحديث حالة الطلب",
          body: `حالة الطلب #${updated.id}: ${statusText(status)}`,
          orderId: updated.id,
          merchantId: updated.merchant_id,
          payload: {
            orderId: updated.id,
            status,
          },
        },
        status === "preparing" && deliveryUserId
          ? {
              userId: deliveryUserId,
              type: "delivery_order_preparing",
              title: "بدأ تجهيز الطلب",
              body: `المتجر بدأ تجهيز الطلب #${updated.id}`,
              orderId: updated.id,
              merchantId: updated.merchant_id,
              payload: {
                orderId: updated.id,
                status,
              },
            }
          : null,
        status === "ready_for_delivery" && deliveryUserId
          ? {
              userId: deliveryUserId,
              type: "delivery_order_ready",
              title: "الطلب جاهز للاستلام",
              body: `الطلب #${updated.id} من ${current.merchant_name} جاهز للاستلام الآن.`,
              orderId: updated.id,
              merchantId: updated.merchant_id,
              payload: {
                orderId: updated.id,
                status,
                requiresAction: true,
              },
            }
          : null,
        status === "cancelled" && deliveryUserId
          ? {
              userId: deliveryUserId,
              type: "delivery_order_cancelled",
              title: "تم إلغاء الطلب",
              body: `تم إلغاء الطلب #${updated.id}`,
              orderId: updated.id,
              merchantId: updated.merchant_id,
              payload: {
                orderId: updated.id,
                status,
              },
            }
          : null,
      ].filter(Boolean)
    );

    return updated;
  } catch (e) {
    await client.query("ROLLBACK");
    throw e;
  } finally {
    client.release();
  }
}

export async function assignDeliveryToOwnerOrder(
  ownerUserId,
  orderId,
  deliveryUserId,
  { assignmentMode = "platform_delivery" } = {}
) {
  const normalizedMode =
    assignmentMode === "merchant_delivery"
      ? "merchant_delivery"
      : "platform_delivery";
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const currentResult = await client.query(
      `SELECT
         o.id,
         o.merchant_id,
         o.status,
         o.customer_user_id,
         o.customer_block,
         o.delivery_user_id,
         m.name AS merchant_name
       FROM customer_order o
       JOIN merchant m ON m.id = o.merchant_id
       WHERE o.id=$1
         AND m.id=$2
       FOR UPDATE`,
      [Number(orderId), Number(ownerUserId)]
    );

    const current = currentResult.rows[0];
    if (!current) {
      await client.query("ROLLBACK");
      return false;
    }

    if (!["approved", "preparing", "ready_for_delivery"].includes(current.status)) {
      throw new AppError(
        "Delivery can be assigned only after approval and before completion.",
        { status: 400 }
      );
    }

    if (deliveryUserId == null) {
      await client.query(
        `UPDATE courier_assignment
         SET ended_at = COALESCE(ended_at, NOW()),
             ended_reason = COALESCE(ended_reason, 'MANUAL_REASSIGNMENT'),
             status = CASE
               WHEN status IN ('assigned', 'accepted') THEN 'released'
               ELSE status
             END
         WHERE order_id = $1
           AND ended_at IS NULL
         RETURNING id`,
        [Number(orderId)]
      );

      const pendingResult = await client.query(
        `UPDATE customer_order
         SET delivery_user_id = NULL,
             delivery_assignment_status = 'PENDING_NO_DRIVER',
             assigned_by_store = FALSE,
             courier_source = 'app',
             updated_at = NOW()
         WHERE id = $1
         RETURNING *`,
        [Number(orderId)]
      );
      const pendingOrder = pendingResult.rows[0] || current;
      await client.query("COMMIT");

      await createManyNotifications([
        {
          userId: pendingOrder.customer_user_id,
          type: "customer_delivery_pending",
          title: "بانتظار دلفري متاح",
          body: `الطلب #${pendingOrder.id} بانتظار دلفري متاح حالياً.`,
          orderId: pendingOrder.id,
          merchantId: pendingOrder.merchant_id,
          payload: {
            orderId: pendingOrder.id,
            assignmentStatus: "PENDING_NO_DRIVER",
            releaseReason: "MANUAL_REASSIGNMENT",
          },
        },
        current.delivery_user_id
          ? {
              userId: Number(current.delivery_user_id),
              type: "delivery_order_removed",
              title: "تم تحرير الطلب",
              body: `تم تحرير الطلب #${current.id} من جدولك.`,
              orderId: current.id,
              merchantId: current.merchant_id,
              payload: {
                orderId: current.id,
                releaseReason: "MANUAL_REASSIGNMENT",
              },
            }
          : null,
      ].filter(Boolean));

      void requestDeliveryAssignmentRecovery({ limit: 25 }).catch((error) => {
        console.error("[delivery-assignment] recovery trigger failed", {
          orderId: Number(orderId),
          error: error?.message || String(error),
        });
      });

      return {
        ...current,
        ...pendingOrder,
        deliveryAssignment: buildDeliveryAssignmentPresentation({
          order: pendingOrder,
        }),
        driver: null,
      };
    }

    const assignmentResult = await directAssignDeliveryOrderTx(client, {
      orderId: Number(orderId),
      merchantId: Number(current.merchant_id),
      requestedByUserId: Number(ownerUserId),
      customerBlock: current.customer_block || null,
      assignmentType: normalizedMode === "merchant_delivery" ? "merchant_manual" : "owner_manual",
      explicitCourierUserId:
        deliveryUserId == null ? null : Number(deliveryUserId),
      allowPending: deliveryUserId == null,
      forceMerchantCourier: normalizedMode === "merchant_delivery" ? true : false,
    });

    await client.query("COMMIT");

    const deliveryNotifications = [];
    if (assignmentResult.assignmentCreated) {
      if (assignmentResult.driver?.id != null) {
        deliveryNotifications.push({
          userId: Number(assignmentResult.driver.id),
          type: "delivery_assigned_by_owner",
          title: "تم إسناد طلب جديد إليك",
          body: `تم إسناد الطلب #${current.id} من ${current.merchant_name} إليك.`,
          orderId: current.id,
          merchantId: current.merchant_id,
          payload: {
            orderId: current.id,
            assignedBy: "owner",
            assignmentMode: normalizedMode,
            assignmentStatus: assignmentResult.assignmentStatus,
            requiresAction: false,
          },
        });
      }

      if (assignmentResult.assignmentStatus === DELIVERY_ASSIGNMENT_STATUSES.PENDING_NO_DRIVER) {
        deliveryNotifications.push({
          userId: current.customer_user_id,
          type: "customer_delivery_pending",
          title: "بانتظار دلفري متاح",
          body: `لا يوجد دلفري متاح حالياً للطلب #${current.id}.`,
          orderId: current.id,
          merchantId: current.merchant_id,
          payload: {
            orderId: current.id,
            assignmentStatus: assignmentResult.assignmentStatus,
            assignmentId: null,
            driver: null,
          },
        });
      }
    }

    const customerNotification =
      assignmentResult.assignmentCreated &&
      assignmentResult.assignmentStatus === DELIVERY_ASSIGNMENT_STATUSES.ASSIGNED
        ? {
            userId: current.customer_user_id,
            type: "customer_delivery_assigned",
            title: "تم تعيين التوصيل",
            body: `تم تعيين دلفري للطلب #${current.id}.`,
            orderId: current.id,
            merchantId: current.merchant_id,
            payload: {
              orderId: current.id,
              assignmentMode: normalizedMode,
              assignmentStatus: assignmentResult.assignmentStatus,
              assignmentId: assignmentResult.deliveryAssignment?.assignmentId || null,
              driver: assignmentResult.driver || null,
            },
          }
        : assignmentResult.assignmentCreated &&
          assignmentResult.assignmentStatus === DELIVERY_ASSIGNMENT_STATUSES.PENDING_NO_DRIVER
        ? {
            userId: current.customer_user_id,
            type: "customer_delivery_pending",
            title: "بانتظار دلفري متاح",
            body: `الطلب #${current.id} بانتظار دلفري متاح.`,
            orderId: current.id,
            merchantId: current.merchant_id,
            payload: {
              orderId: current.id,
              assignmentMode: normalizedMode,
              assignmentStatus: assignmentResult.assignmentStatus,
              assignmentId: null,
              driver: null,
            },
          }
        : null;

    await createManyNotifications(
      [...deliveryNotifications, customerNotification].filter(Boolean)
    );

    return {
      ...current,
      ...assignmentResult.order,
      deliveryAssignment: assignmentResult.deliveryAssignment,
      driver: assignmentResult.driver,
    };
  } catch (e) {
    await client.query("ROLLBACK");
    throw e;
  } finally {
    client.release();
  }
}

export async function listDeliveryCurrentOrders(deliveryUserId) {
  const r = await q(
    `${orderSelect}
     JOIN app_user du ON du.id = $1
     LEFT JOIN courier_profile ducp ON ducp.user_id = du.id
     WHERE o.delivery_user_id = $1
       AND o.delivery_assignment_status = 'ASSIGNED'
       AND o.status NOT IN ('cancelled','cancelled_by_customer','cancelled_by_store','cancelled_by_admin')
     ORDER BY o.id DESC`,
    [Number(deliveryUserId)]
  );
  const rows = await attachItems(r.rows);
  return rows
    .map((row) => ({
      ...row,
      deliveryAssignment: buildDeliveryAssignmentSnapshot(row),
    }))
    .filter((row) => isDeliveryCurrentStatus(row.status, row.customer_confirmed_at))
    .sort((a, b) => {
      const rank = currentStatusRank(a.status) - currentStatusRank(b.status);
      if (rank !== 0) return rank;
      return Number(b.id) - Number(a.id);
    });
}

export async function listDeliveryHistory(deliveryUserId, archiveDate) {
  const params = [deliveryUserId];
  let dateSql = "";
  if (archiveDate) {
    params.push(archiveDate);
    dateSql = "AND DATE(o.delivered_at) = $2";
  }

  const r = await q(
    `${orderSelect}
     WHERE o.delivery_user_id=$1
       AND o.archived_by_delivery = TRUE
       ${dateSql}
     ORDER BY o.id DESC`,
    params
  );
  const rows = await attachItems(r.rows);
  return rows.map((row) => ({
    ...row,
    deliveryAssignment: buildDeliveryAssignmentSnapshot(row),
  }));
}

function normalizeDeliveryDetailOrderState(status) {
  switch (String(status || "").trim().toLowerCase()) {
    case "approved":
      return "accepted";
    case "preparing":
    case "courier_requested":
    case "courier_assigned":
      return "preparing";
    case "ready_for_delivery":
    case "ready_for_pickup":
      return "ready";
    case "cancelled":
    case "cancelled_by_customer":
    case "cancelled_by_store":
    case "cancelled_by_admin":
      return "cancelled";
    case "failed_delivery":
    case "returned_if_needed":
      return "returned";
    default:
      return String(status || "").trim().toLowerCase() || "pending";
  }
}

function normalizeDeliveryDetailCourierState(order, { isAssignedToDelivery }) {
  const status = String(order?.status || "").trim().toLowerCase();
  if (!isAssignedToDelivery) return null;
  switch (status) {
    case "approved":
    case "preparing":
    case "ready_for_delivery":
    case "ready_for_pickup":
      return "accepted";
    case "picked_up":
      return "picked_up";
    case "on_the_way":
      return "on_the_way";
    case "arrived":
      return "arrived";
    case "delivered":
    case "completed":
      return "completed";
    default:
      return null;
  }
}

function buildDeliveryAllowedActions({
  order,
  isAssignedToDelivery,
  isEligibleDelivery,
  canModerate,
}) {
  const status = String(order?.status || "").trim().toLowerCase();
  const actions = new Set();

  if (isAssignedToDelivery || canModerate) {
    if (["approved", "preparing", "ready_for_delivery"].includes(status)) {
      actions.add("picked_up");
    }
    if (status === "on_the_way") {
      actions.add("arrived");
    }
    if (status === "arrived") {
      actions.add("delivered");
    }
    if (["ready_for_delivery", "on_the_way", "arrived"].includes(status)) {
      actions.add("request_cancel");
    }
  }

  if (isAssignedToDelivery || canModerate) {
    actions.add("open_chat");
    actions.add("open_tracking");
  }
  return Array.from(actions);
}

function buildDeliveryTimeline(order) {
  return [
    {
      key: "created",
      status: "done",
      labelAr: "تم إنشاء الطلب",
      labelEn: "Order placed",
      time: order.created_at || null,
    },
    {
      key: "approved",
      status: order.approved_at ? "done" : "pending",
      labelAr: "تم قبول الطلب",
      labelEn: "Order accepted",
      time: order.approved_at || null,
    },
    {
      key: "preparing",
      status:
        order.preparing_started_at || order.prepared_at ? "done" : "pending",
      labelAr: "قيد التحضير",
      labelEn: "Preparing",
      time: order.preparing_started_at || order.prepared_at || null,
    },
    {
      key: "picked_up",
      status: order.picked_up_at ? "done" : "pending",
      labelAr: "تم الاستلام من المتجر",
      labelEn: "Picked up",
      time: order.picked_up_at || null,
    },
    {
      key: "arrived",
      status: order.arrived_at ? "done" : "pending",
      labelAr: "وصل السائق",
      labelEn: "Courier arrived",
      time: order.arrived_at || null,
    },
    {
      key: "delivered",
      status: order.delivered_at ? "done" : "pending",
      labelAr: "تم التسليم",
      labelEn: "Delivered",
      time: order.delivered_at || null,
    },
  ];
}

function buildDeliveryAssignmentSnapshot(order) {
  if (!order || typeof order !== "object") return null;
  const openAssignmentRow =
    order.delivery_assignment_ended_at == null && order.delivery_assignment_id != null
      ? {
          id: order.delivery_assignment_id,
          status: order.delivery_assignment_row_status,
          assigned_at: order.delivery_assignment_assigned_at,
          ended_at: order.delivery_assignment_ended_at,
          ended_reason: order.delivery_assignment_ended_reason,
        }
      : null;
  const latestAssignmentRow =
    order.delivery_assignment_id == null
      ? null
      : {
          id: order.delivery_assignment_id,
          status: order.delivery_assignment_row_status,
          assigned_at: order.delivery_assignment_assigned_at,
          ended_at: order.delivery_assignment_ended_at,
          ended_reason: order.delivery_assignment_ended_reason,
        };

  return buildDeliveryAssignmentPresentation({
    order,
    openAssignmentRow,
    latestAssignmentRow,
  });
}

function buildOrderTrackingEnvelope(order, { viewerMode, latestLocation = null, share = null }) {
  const items = Array.isArray(order?.items) ? order.items : [];
  const deliveryAssignment = buildDeliveryAssignmentSnapshot(order);
  const hydratedOrder = {
    ...order,
    id: Number(order.id),
    merchantId: Number(order.merchant_id),
    merchantName: order.merchant_name || null,
    merchantType: order.merchant_type || null,
    merchantActivityType: order.merchant_activity_type || null,
    totalAmount: Number(order.total_amount || 0),
    deliveryFee: Number(order.delivery_fee || 0),
    deliveryFeeRaw: Number(order.delivery_fee_raw || order.delivery_fee || 0),
    customerCity: order.customer_city || null,
    customerBlock: order.customer_block || null,
    customerBuildingNumber: order.customer_building_number || null,
    customerApartment: order.customer_apartment || null,
    estimatedPrepMinutes:
      order.estimated_prep_minutes == null
        ? null
        : Number(order.estimated_prep_minutes),
    estimatedDeliveryMinutes:
      order.estimated_delivery_minutes == null
        ? null
        : Number(order.estimated_delivery_minutes),
    createdAt: order.created_at || null,
    approvedAt: order.approved_at || null,
    preparingStartedAt: order.preparing_started_at || null,
    preparedAt: order.prepared_at || null,
    pickedUpAt: order.picked_up_at || null,
    arrivedAt: order.arrived_at || null,
    deliveredAt: order.delivered_at || null,
    customerConfirmedAt: order.customer_confirmed_at || null,
    items,
    deliveryAssignment,
  };
  return {
    kind: "delivery",
    viewerMode,
    order: hydratedOrder,
    items,
    stage: buildOrderTrackingStage(order),
    latestLocation,
    deliveryAssignment,
    courier: deliveryAssignment?.driver
      ? {
          userId: Number(deliveryAssignment.driver.id || 0),
          fullName: deliveryAssignment.driver.name || null,
          phone: deliveryAssignment.driver.phone || null,
          driverType: order.delivery_driver_type || null,
          courierSource: order.courier_source || null,
          isMerchantCourier: order.is_merchant_delivery === true,
        }
      : null,
    destination: {
      city: order.customer_city,
      block: order.customer_block,
      buildingNumber: order.customer_building_number,
      apartment: order.customer_apartment,
      label: `${order.customer_city} - ${order.customer_block} - ${order.customer_building_number}`,
    },
    merchant: {
      id: Number(order.merchant_id),
      name: order.merchant_name,
      type: order.merchant_type || null,
      activityType: order.merchant_activity_type || null,
    },
    share,
    lastUpdatedAt:
      latestLocation?.updatedAt ||
      order.arrived_at?.toISOString?.() ||
      order.picked_up_at?.toISOString?.() ||
      order.prepared_at?.toISOString?.() ||
      order.preparing_started_at?.toISOString?.() ||
      order.approved_at?.toISOString?.() ||
      order.created_at?.toISOString?.() ||
      null,
  };
}

function toDeliveryDetailResponse(order, context) {
  const deliveryAssignment = buildDeliveryAssignmentSnapshot(order);
  const isAssignedToDelivery =
    Number(order.delivery_user_id || 0) > 0 &&
    Number(order.delivery_user_id || 0) === Number(context.requestUserId || 0) &&
    normalizeDeliveryAssignmentStatus(order.delivery_assignment_status) ===
      DELIVERY_ASSIGNMENT_STATUSES.ASSIGNED;
  const isEligibleDelivery =
    context.requestUserRole === "delivery" && isAssignedToDelivery;
  const canModerate = context.isBackoffice === true;
  const orderState = normalizeDeliveryDetailOrderState(order.status);
  const courierState = normalizeDeliveryDetailCourierState(order, {
    isAssignedToDelivery,
  });
  const invoice = {
    grossSubtotal: Number(order.gross_subtotal || order.subtotal || 0),
    productDiscountTotal: Number(order.product_discount_total || 0),
    subtotal: Number(order.subtotal || 0),
    serviceFee: Number(order.service_fee || 0),
    deliveryFee: Number(order.delivery_fee || 0),
    rawDeliveryFee: Number(order.delivery_fee_raw || order.delivery_fee || 0),
    couponDiscountTotal: Number(order.coupon_discount_total || 0),
    totalAmount: Number(order.total_amount || 0),
    paymentMethod: order.payment_method || null,
    paymentMethodOther: order.payment_method_other || null,
    cashCollectionResponsible:
      Number(order.delivery_user_id || 0) > 0 ? "courier" : null,
  };
  const canonicalOrder = {
    ...order,
    items: Array.isArray(order.items) ? order.items : [],
    normalizedStatus: String(order.status || "").trim().toLowerCase(),
    orderState,
    courierState,
  };

  return {
    order: canonicalOrder,
    items: canonicalOrder.items,
    merchant: {
      id: Number(order.merchant_id),
      name: order.merchant_name || null,
      type: order.merchant_type || null,
      phone: order.merchant_phone || null,
      ownerUserId: order.owner_user_id == null ? null : Number(order.owner_user_id),
    },
    customer: {
      userId: Number(order.customer_user_id),
      fullName: order.customer_full_name || null,
      phone: order.customer_phone || null,
      city: order.customer_city || null,
      block: order.customer_block || null,
      buildingNumber: order.customer_building_number || null,
      apartment: order.customer_apartment || null,
      imageUrl: order.customer_image_url || null,
      note: order.note || null,
    },
    delivery: {
      userId: order.delivery_user_id == null ? null : Number(order.delivery_user_id),
      fullName: order.delivery_full_name || null,
      phone: order.delivery_phone || null,
      imageUrl: order.delivery_image_url || null,
      driverType: order.delivery_driver_type || null,
      courierSource: order.courier_source || null,
      rating: order.delivery_rating == null ? null : Number(order.delivery_rating),
      availabilityStatus: order.delivery_availability_status || null,
      coverageBlock: order.delivery_coverage_block || null,
      vehicleType: order.delivery_vehicle_type || null,
      isMerchantDelivery: order.is_merchant_delivery === true,
      isAssignedToRequester: isAssignedToDelivery,
      isEligibleForRequester: isEligibleDelivery,
      deliveryAssignment,
      courierState,
    },
    deliveryAssignment,
    invoice,
    timeline: buildDeliveryTimeline(order),
    allowedActions: buildDeliveryAllowedActions({
      order,
      isAssignedToDelivery,
      isEligibleDelivery,
      canModerate,
    }),
  };
}

export async function getDeliveryOrderDetail({
  requestUserId,
  requestUserRole,
  userIsSuperAdmin = false,
  orderId,
}) {
  const normalizedRole = String(requestUserRole || "").trim().toLowerCase();
  const isBackoffice =
    userIsSuperAdmin === true ||
    normalizedRole === "admin" ||
    normalizedRole === "deputy_admin";

  if (!isBackoffice && normalizedRole !== "delivery") {
    throw new AppError("FORBIDDEN_DELIVERY_DETAIL_ONLY", { status: 403 });
  }

  let row = null;
  if (isBackoffice) {
    const result = await q(
      `${orderSelect}
       WHERE o.id = $1
       LIMIT 1`,
      [Number(orderId)]
    );
    row = result.rows[0] || null;
  } else {
    const result = await q(
      `${orderSelect}
       JOIN app_user du ON du.id = $2
       LEFT JOIN courier_profile ducp ON ducp.user_id = du.id
       WHERE o.id = $1
         AND o.delivery_user_id = $2
         AND o.delivery_assignment_status = 'ASSIGNED'
       LIMIT 1`,
      [Number(orderId), Number(requestUserId)]
    );
    row = result.rows[0] || null;
  }

  if (!row) {
    throw new AppError("ORDER_NOT_FOUND", { status: 404 });
  }

  const withItems = await attachItems([row]);
  return toDeliveryDetailResponse(withItems[0], {
    requestUserId,
    requestUserRole: normalizedRole,
    isBackoffice,
  });
}

const DELIVERY_COMPLETED_STATUSES = [
  "delivered",
  "received",
  "completed",
  "delivered_by_courier",
  "received_by_customer",
];

/**
 * Pure earnings aggregator over a courier's COMPLETED orders. Side-effect free
 * (exposed via __ordersRepoTestables) so the calculation rules can be unit
 * tested without a database. Only delivered/completed rows reach here, so
 * cancelled/rejected/returned/pending are never counted.
 */
function buildDeliveryEarnings(orderRows, referenceDate) {
  const ref = referenceDate || new Date();
  const startOfDay = new Date(ref.getFullYear(), ref.getMonth(), ref.getDate());
  const startOfMonth = new Date(ref.getFullYear(), ref.getMonth(), 1);
  let todayEarnings = 0;
  let monthEarnings = 0;
  let completedTodayCount = 0;
  let completedMonthCount = 0;
  let deliveryFeeSum = 0;
  let serviceFeeSum = 0;
  let appDueFromDeliverySum = 0;
  let storeNetReceivedAmountSum = 0;
  let differenceAmountSum = 0;
  let storeCashConfirmedCount = 0;
  const rows = [];
  for (const o of orderRows) {
    const fee = Number(o.delivery_fee || 0);
    const serviceFee = Number(o.service_fee || 0);
    const storeNetReceivedAmount = Number(
      o.store_net_received_amount || 0
    );
    const appDueFromDelivery = Number(o.app_due_from_delivery || 0);
    const differenceAmount = Number(o.difference_amount || 0);
    const when =
      o.delivered_at || o.customer_confirmed_at || o.created_at || null;
    const whenDate = when ? new Date(when) : null;
    deliveryFeeSum += fee;
    serviceFeeSum += serviceFee;
    appDueFromDeliverySum += appDueFromDelivery;
    storeNetReceivedAmountSum += storeNetReceivedAmount;
    differenceAmountSum += differenceAmount;
    if (o.store_cash_confirmed === true) {
      storeCashConfirmedCount += 1;
    }
    if (whenDate && whenDate >= startOfMonth) {
      monthEarnings += fee;
      completedMonthCount += 1;
    }
    if (whenDate && whenDate >= startOfDay) {
      todayEarnings += fee;
      completedTodayCount += 1;
    }
    rows.push({
      orderId: Number(o.id),
      orderNumber: Number(o.id),
      customerName: o.customer_name || null,
      merchantName: o.merchant_name || null,
      deliveredAt: when,
      deliveryFee: fee,
      serviceFee,
      totalInvoice: Number(o.total_amount || 0),
      storeNetReceivedAmount,
      appDueFromDelivery,
      differenceAmount,
      settlementStatus: o.settlement_status || null,
      storeCashConfirmed: o.store_cash_confirmed === true,
      paymentMethod: o.payment_method || null,
      status: o.status || null,
    });
  }
  return {
    todayEarnings,
    monthEarnings,
    completedTodayCount,
    completedMonthCount,
    deliveryFeeSum,
    serviceFeeSum,
    appDueFromDeliverySum,
    storeNetReceivedAmountSum,
    differenceAmountSum,
    storeCashConfirmedCount,
    rows,
  };
}

/**
 * Pure ratings aggregator. The rating lives ON the order (delivery_rating),
 * so every row is intrinsically linked to its orderId.
 */
function buildDeliveryRatings(orderRows) {
  const rows = [];
  let sum = 0;
  let count = 0;
  for (const o of orderRows) {
    const stars = Number(o.delivery_rating || 0);
    if (!(stars > 0)) continue;
    sum += stars;
    count += 1;
    rows.push({
      ratingId: Number(o.id),
      orderId: Number(o.id),
      orderNumber: Number(o.id),
      stars,
      comment: o.delivery_review || null,
      customerName: o.customer_name || null,
      merchantName: o.merchant_name || null,
      createdAt:
        o.delivered_at || o.customer_confirmed_at || o.created_at || null,
    });
  }
  const averageRating = count > 0 ? Math.round((sum / count) * 100) / 100 : 0;
  return { averageRating, ratingCount: count, rows };
}

export async function getDeliveryEarnings(deliveryUserId) {
  // NOTE: customer_order has no payment_method column (it lives on
  // merchant_payment_request / merchant_receivable_invoice). Selecting it here
  // previously caused a 42703 "column o.payment_method does not exist" 500.
  // paymentMethod is therefore returned as null while keeping the response shape.
  const result = await q(
    `SELECT o.id, o.status, o.delivery_fee, o.service_fee, o.total_amount,
            o.store_net_received_amount, o.app_due_from_delivery,
            o.difference_amount, o.settlement_status, o.store_cash_confirmed,
            o.delivered_at, o.customer_confirmed_at, o.created_at,
            c.full_name AS customer_name,
            m.name AS merchant_name
       FROM customer_order o
       JOIN merchant m ON m.id = o.merchant_id
       LEFT JOIN app_user c ON c.id = o.customer_user_id
      WHERE o.delivery_user_id = $1
        -- customer_order.status is the PostgreSQL enum order_status, so it must
        -- be cast to text before comparing to a text[] (otherwise Postgres
        -- raises 42883 operator does not exist: order_status = text).
        AND o.status::text = ANY($2::text[])
      ORDER BY COALESCE(o.delivered_at, o.customer_confirmed_at, o.updated_at, o.created_at) DESC
      LIMIT 300`,
    [Number(deliveryUserId), DELIVERY_COMPLETED_STATUSES]
  );
  return buildDeliveryEarnings(result.rows, new Date());
}

export async function getDeliveryRatings(deliveryUserId) {
  const result = await q(
    `SELECT o.id, o.delivery_rating, o.delivery_review,
            o.delivered_at, o.customer_confirmed_at, o.created_at,
            c.full_name AS customer_name,
            m.name AS merchant_name
       FROM customer_order o
       JOIN merchant m ON m.id = o.merchant_id
       LEFT JOIN app_user c ON c.id = o.customer_user_id
      WHERE o.delivery_user_id = $1
        AND o.delivery_rating IS NOT NULL
        AND o.delivery_rating > 0
      ORDER BY COALESCE(o.delivered_at, o.customer_confirmed_at, o.created_at) DESC
      LIMIT 300`,
    [Number(deliveryUserId)]
  );
  return buildDeliveryRatings(result.rows);
}

/**
 * يسمح لمندوب دلفري معتمد بالاستحواذ على طلب جاهز للتسليم إذا كان ضمن
 * النطاق المسموح ولا يوجد تعارض مع تعيين قائم.
 *
 * Failure modes:
 * - 0 rows updated تعني غالباً status غير صحيح، أو mismatch في block،
 *   أو الحساب غير معتمد/غير صالح كسائق app_driver.
 */
/**
 * يربط طلباً متاحاً بمندوب توصيل واحد داخل transaction مع locking صريح.
 *
 * Return value:
 * - كود حالة business مثل `ORDER_NOT_FOUND`, `ORDER_ALREADY_CLAIMED`, `OK`.
 *
 * Maintenance notes:
 * - عند تكرار شكاوى "طلب اختفى من شاشة المندوب" افحص هذه الدالة مع
 *   شروط الحالة والـ `FOR UPDATE` والحقول `delivery_user_id/status`.
 */
export async function claimDeliveryOrder(deliveryUserId, orderId, estimatedDeliveryMinutes) {
  const r = await q(
    `UPDATE customer_order o
     SET delivery_user_id = $3,
         is_merchant_delivery = FALSE,
         delivery_assignment_status = 'ASSIGNED',
         courier_source = 'app',
         status='on_the_way',
         picked_up_at=COALESCE(picked_up_at, NOW()),
         estimated_delivery_minutes=COALESCE($1, o.estimated_delivery_minutes)
     FROM merchant m
     JOIN app_user du ON du.id = $3
     LEFT JOIN courier_profile cp ON cp.user_id = du.id
     WHERE o.id=$2
       AND o.status='ready_for_delivery'
       AND COALESCE(o.is_merchant_delivery, FALSE) = FALSE
       AND du.role = 'delivery'
       AND du.delivery_account_approved = TRUE
       AND du.is_account_disabled = FALSE
       AND COALESCE(cp.driver_type, 'app_driver') = 'app_driver'
       AND o.delivery_assignment_status = 'ASSIGNED'
       AND o.delivery_user_id = $3
       AND NOT EXISTS (
         SELECT 1
         FROM taxi_captain_profile tcp
         WHERE tcp.user_id = du.id
       )
       AND (
         o.delivery_user_id = $3
       )
       AND o.merchant_id = m.id
     RETURNING
       o.id,
       o.customer_user_id,
       o.merchant_id,
       m.owner_user_id,
       m.name AS merchant_name`,
    [estimatedDeliveryMinutes, Number(orderId), Number(deliveryUserId)]
  );
  const row = r.rows[0];
  if (!row) return false;

  await createManyNotifications(
    [
      row.owner_user_id
        ? {
            userId: row.owner_user_id,
            type: "owner_delivery_picked_up",
            title: "تم استلام الطلب من المتجر",
            body: `الدلفري استلم الطلب #${row.id} من ${row.merchant_name}.`,
            orderId: row.id,
            merchantId: row.merchant_id,
            payload: {
              orderId: row.id,
              status: "on_the_way",
            },
          }
        : null,
      {
        userId: row.customer_user_id,
        type: "customer_order_on_the_way",
        title: "طلبك أصبح في الطريق",
        body: `الدلفري استلم الطلب #${row.id} وهو الآن في الطريق إليك.`,
        orderId: row.id,
        merchantId: row.merchant_id,
        payload: {
          orderId: row.id,
          status: "on_the_way",
          etaMinMinutes: 7,
          etaMaxMinutes: 10,
        },
      },
    ].filter(Boolean)
  );

  return row;
}

/**
 * ينقل الطلب من on_the_way إلى arrived ويبلغ العميل والمالك.
 */
/**
 * يثبت أن المندوب وصل إلى موقع التسليم دون إنهاء الطلب بعد.
 *
 * السبب:
 * - الفصل بين `arrived` و`delivered` مهم للإشعارات وواجهة تتبع العميل.
 */
export async function markOrderArrived(deliveryUserId, orderId) {
  const r = await q(
    `UPDATE customer_order o
     SET status='arrived',
         arrived_at=COALESCE(arrived_at, NOW())
     FROM merchant m
     WHERE o.id=$1
       AND o.delivery_user_id=$2
       AND o.delivery_assignment_status = 'ASSIGNED'
       AND o.status='on_the_way'
       AND o.merchant_id = m.id
     RETURNING
       o.id,
       o.customer_user_id,
       o.merchant_id,
       m.owner_user_id`,
    [Number(orderId), Number(deliveryUserId)]
  );
  const row = r.rows[0];
  if (!row) return false;

  await createManyNotifications(
    [
      {
        userId: row.customer_user_id,
        type: "customer_order_arrived",
        title: "الدلفري وصل إلى موقعك",
        body: `الدلفري وصل الآن بالطلب #${row.id}.`,
        orderId: row.id,
        merchantId: row.merchant_id,
        payload: {
          orderId: row.id,
          status: "arrived",
        },
      },
      row.owner_user_id
        ? {
            userId: row.owner_user_id,
            type: "owner_order_arrived",
            title: "الدلفري وصل إلى الزبون",
            body: `الدلفري وصل لتسليم الطلب #${row.id}.`,
            orderId: row.id,
            merchantId: row.merchant_id,
            payload: {
              orderId: row.id,
              status: "arrived",
            },
          }
        : null,
    ].filter(Boolean)
  );

  return row;
}

/**
 * يثبت أن الدلفري سلّم الطلب فعلياً ويبقي خطوة تأكيد العميل لاحقة منفصلة.
 */
/**
 * ينهي دورة الطلب من جانب الدليفري ويضع timestamps التسليم النهائية.
 *
 * Critical notes:
 * - يجب أن تبقى هذه النهاية idempotent بقدر الإمكان من ناحية الواجهة،
 *   لكن قاعدة البيانات ما زالت تمنع التكرار عبر status guard.
 */
export async function markOrderDelivered(deliveryUserId, orderId) {
  const r = await q(
    `UPDATE customer_order o
     SET status='delivered',
         delivery_assignment_status = 'COMPLETED',
         delivered_at=COALESCE(delivered_at, NOW())
     FROM merchant m
     WHERE o.id=$1
       AND o.delivery_user_id=$2
       AND o.delivery_assignment_status = 'ASSIGNED'
       AND o.status='arrived'
       AND o.merchant_id = m.id
     RETURNING
       o.id,
       o.customer_user_id,
       o.merchant_id,
       m.owner_user_id`,
    [Number(orderId), Number(deliveryUserId)]
  );
  const row = r.rows[0];
  if (!row) return false;

  await q(
    `UPDATE courier_assignment
     SET ended_at = COALESCE(ended_at, NOW()),
         ended_reason = COALESCE(ended_reason, 'COMPLETED'),
         status = CASE
           WHEN status IN ('assigned', 'accepted') THEN 'completed'
           ELSE status
         END
     WHERE order_id = $1
       AND courier_user_id = $2
       AND ended_at IS NULL`,
    [Number(orderId), Number(deliveryUserId)]
  );

  await createManyNotifications(
    [
      {
        userId: row.customer_user_id,
        type: "customer_order_delivered",
        title: "تم تسليم الطلب وبانتظار تأكيدك",
        body: `تم تسليم الطلب #${row.id}. يرجى الضغط على استلمت الطلب لتأكيد الاستلام.`,
        orderId: row.id,
        merchantId: row.merchant_id,
        payload: {
          orderId: row.id,
          status: "delivered",
          requiresAction: true,
        },
      },
      row.owner_user_id
        ? {
            userId: row.owner_user_id,
            type: "owner_order_delivered",
            title: "تم تسليم الطلب للزبون",
            body: `تم تسليم الطلب #${row.id} وبانتظار تأكيد الزبون.`,
            orderId: row.id,
            merchantId: row.merchant_id,
            payload: {
              orderId: row.id,
              status: "delivered",
            },
          }
        : null,
    ].filter(Boolean)
  );

  void requestDeliveryAssignmentRecovery({ limit: 25 }).catch((error) => {
    console.error("[delivery-assignment] recovery trigger failed", {
      orderId: Number(orderId),
      error: error?.message || String(error),
    });
  });

  return row;
}
export async function endDeliveryDay(deliveryUserId, archiveDate) {
  const date = archiveDate || new Date().toISOString().slice(0, 10);
  const client = await pool.connect();
  let notifyPayload = null;
  let archivedOrdersCount = 0;
  let archivedTotalAmount = 0;

  try {
    await client.query("BEGIN");

    const merchantScope = await client.query(
      `SELECT
         mda.merchant_id,
         m.owner_user_id
       FROM merchant_delivery_agent mda
       JOIN merchant m ON m.id = mda.merchant_id
       WHERE mda.delivery_user_id = $1
         AND mda.is_active = TRUE
       ORDER BY mda.updated_at DESC, mda.created_at DESC
       LIMIT 1`,
      [Number(deliveryUserId)]
    );

    const merchantId = merchantScope.rows[0]?.merchant_id
      ? Number(merchantScope.rows[0].merchant_id)
      : null;
    const ownerUserId = merchantScope.rows[0]?.owner_user_id
      ? Number(merchantScope.rows[0].owner_user_id)
      : null;

    if (merchantId) {
      const pendingSettlements = await client.query(
        `SELECT
           id,
           status,
           settlement_status,
           total_amount,
           store_net_received_amount,
           app_due_from_delivery,
           difference_amount,
           difference_reason
         FROM delivery_cash_settlement
         WHERE merchant_id = $1
           AND delivery_user_id = $2
           AND status IN ('pending', 'received')
           AND COALESCE(settlement_status, 'pending_store_confirmation') NOT IN ('closed', 'cancelled')
         ORDER BY requested_at ASC, id ASC`,
        [merchantId, Number(deliveryUserId)]
      );
      const readiness = evaluateCourierEndDayReadiness(pendingSettlements.rows);
      if (!readiness.canEndDay) {
        try {
          await insertOpsAuditLog({
            actorUserId: Number(deliveryUserId),
            actorRole: "delivery",
            action: "courier_end_day_blocked",
            targetType: "delivery_day",
            targetId: `${merchantId}:${date}`,
            metadata: {
              merchantId,
              deliveryUserId: Number(deliveryUserId),
              archiveDate: date,
              outstandingAmount: readiness.outstandingAmount,
              totalAppDue: readiness.totalAppDue,
              totalDifferenceDue: readiness.totalDifferenceDue,
              openSettlements: readiness.openSettlements,
            },
          });
        } catch (_) {
          // Best-effort audit logging; the block itself must still win.
        }
        const err = new Error("DELIVERY_DAY_HAS_OPEN_SETTLEMENTS");
        err.status = 409;
        err.details = {
          merchantId,
          deliveryUserId: Number(deliveryUserId),
          outstandingAmount: readiness.outstandingAmount,
          totalAppDue: readiness.totalAppDue,
          totalDifferenceDue: readiness.totalDifferenceDue,
          blockingReasonAr: readiness.blockingReasonAr,
          blockingReasonEn: readiness.blockingReasonEn,
          openSettlements: readiness.openSettlements,
        };
        throw err;
      }
    }

    const deliveredRows = await client.query(
      `UPDATE customer_order
       SET archived_by_delivery=TRUE,
           archived_by_delivery_at=NOW()
       WHERE delivery_user_id=$1
         AND status='delivered'
         AND archived_by_delivery=FALSE
         AND DATE(delivered_at)=$2
         AND ($3::bigint IS NULL OR merchant_id = $3)
       RETURNING *`,
      [Number(deliveryUserId), date, merchantId]
    );

    const ordersCount = deliveredRows.rows.length;
    const profile = merchantId
      ? await getMerchantBillingProfile(merchantId)
      : null;
    const settlementSnapshot = buildDeliveryCashSettlementSnapshot(
      deliveredRows.rows,
      profile || {}
    );
    const totalAmount = settlementSnapshot.totalAmount;
    archivedOrdersCount = ordersCount;
    archivedTotalAmount = totalAmount;

    await client.query(
      `INSERT INTO delivery_day_archive
        (delivery_user_id, archive_date, orders_count, total_amount)
       VALUES ($1,$2,$3,$4)
       ON CONFLICT (delivery_user_id, archive_date)
       DO UPDATE
       SET orders_count = delivery_day_archive.orders_count + EXCLUDED.orders_count,
           total_amount = delivery_day_archive.total_amount + EXCLUDED.total_amount`,
      [Number(deliveryUserId), date, ordersCount, totalAmount]
    );

    let pendingSettlementId = null;
    if (merchantId && ordersCount > 0 && totalAmount > 0) {
      const inserted = await client.query(
        `INSERT INTO delivery_cash_settlement
          (
            merchant_id,
            delivery_user_id,
            archive_date,
            orders_count,
            total_amount,
            store_net_received_amount,
            app_due_from_delivery,
            store_cash_confirmed,
            store_cash_confirmed_at,
            store_cash_confirmed_by_user_id,
            amount_received_actual,
            difference_amount,
            difference_reason,
            settlement_status,
            status,
            requested_at,
            created_at,
            updated_at
          )
         VALUES
          (
            $1,$2,$3,$4,$5,$6,$7,FALSE,NULL,NULL,0,0,NULL,'pending_store_confirmation','pending',NOW(),NOW(),NOW()
          )
         RETURNING id`,
        [
          merchantId,
          Number(deliveryUserId),
          date,
          ordersCount,
          totalAmount,
          settlementSnapshot.storeNetReceivedAmount,
          settlementSnapshot.appDueFromDelivery,
        ]
      );
      pendingSettlementId = Number(inserted.rows[0]?.id || 0);

      await insertOpsAuditLog({
        actorUserId: Number(deliveryUserId),
        actorRole: "delivery",
        action: "delivery_cash_settlement_created",
        targetType: "delivery_cash_settlement",
        targetId: pendingSettlementId,
        metadata: {
          merchantId,
          deliveryUserId: Number(deliveryUserId),
          archiveDate: date,
          ordersCount,
          totalAmount,
          storeNetReceivedAmount: settlementSnapshot.storeNetReceivedAmount,
          appDueFromDelivery: settlementSnapshot.appDueFromDelivery,
          settlementStatus: settlementSnapshot.settlementStatus,
        },
        client,
      });

      const recipients = await client.query(
        `SELECT accountant_user_id
         FROM merchant_accountant
         WHERE merchant_id = $1
           AND is_active = TRUE`,
        [merchantId]
      );

      notifyPayload = {
        merchantId,
        ownerUserId,
        deliveryUserId: Number(deliveryUserId),
        archiveDate: date,
        ordersCount,
        totalAmount,
        storeNetReceivedAmount: settlementSnapshot.storeNetReceivedAmount,
        appDueFromDelivery: settlementSnapshot.appDueFromDelivery,
        pendingSettlementId,
        accountantUserIds: recipients.rows.map((row) => Number(row.accountant_user_id)),
      };
    }

    await client.query("COMMIT");

    if (notifyPayload) {
      const notifications = [
        ...notifyPayload.accountantUserIds.map((accountantUserId) => ({
          userId: accountantUserId,
          type: "accountant_delivery_settlement_pending",
          title: "ذمة دلفري بانتظار الاستلام",
          body: `يوجد مبلغ ${Number(notifyPayload.storeNetReceivedAmount || 0).toFixed(0)} د.ع بانتظار تأكيد المتجر، والذمة الإجمالية ${Number(notifyPayload.totalAmount || 0).toFixed(0)} د.ع.`,
          payload: {
            settlementId: notifyPayload.pendingSettlementId,
            merchantId: notifyPayload.merchantId,
            deliveryUserId: notifyPayload.deliveryUserId,
            archiveDate: notifyPayload.archiveDate,
            totalAmount: notifyPayload.totalAmount,
            storeNetReceivedAmount: notifyPayload.storeNetReceivedAmount,
            appDueFromDelivery: notifyPayload.appDueFromDelivery,
            target: "accountant_dashboard",
          },
        })),
      ];

      if (notifyPayload.ownerUserId) {
        notifications.push({
          userId: notifyPayload.ownerUserId,
          type: "owner_delivery_settlement_pending",
          title: "ذمة دلفري جديدة",
          body: `الدلفري أنهى يومه بذمة إجمالية ${Number(notifyPayload.totalAmount || 0).toFixed(0)} د.ع، والمتوقع تسليم ${Number(notifyPayload.storeNetReceivedAmount || 0).toFixed(0)} د.ع للمتجر.`,
          payload: {
            settlementId: notifyPayload.pendingSettlementId,
            merchantId: notifyPayload.merchantId,
            deliveryUserId: notifyPayload.deliveryUserId,
            archiveDate: notifyPayload.archiveDate,
            totalAmount: notifyPayload.totalAmount,
            storeNetReceivedAmount: notifyPayload.storeNetReceivedAmount,
            appDueFromDelivery: notifyPayload.appDueFromDelivery,
            target: "owner_dashboard",
          },
        });
      }

      if (notifications.length) {
        await createManyNotifications(notifications);
      }
    }

    return {
      archiveDate: date,
      ordersCount: archivedOrdersCount,
      totalAmount: archivedTotalAmount,
      storeNetReceivedAmount: settlementSnapshot.storeNetReceivedAmount,
      appDueFromDelivery: settlementSnapshot.appDueFromDelivery,
      merchantId: notifyPayload?.merchantId || null,
      pendingSettlementId: notifyPayload?.pendingSettlementId || null,
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function getDeliveryEndDayReadiness(deliveryUserId) {
  const client = await pool.connect();
  try {
    const merchantScope = await client.query(
      `SELECT
         mda.merchant_id
       FROM merchant_delivery_agent mda
       JOIN merchant m ON m.id = mda.merchant_id
       WHERE mda.delivery_user_id = $1
         AND mda.is_active = TRUE
       ORDER BY mda.updated_at DESC, mda.created_at DESC
       LIMIT 1`,
      [Number(deliveryUserId)]
    );
    const merchantId = merchantScope.rows[0]?.merchant_id
      ? Number(merchantScope.rows[0].merchant_id)
      : null;
    if (!merchantId) {
      return {
        canEndDay: true,
        outstandingAmount: 0,
        openSettlements: [],
        merchantId: null,
      };
    }

    const pendingSettlements = await client.query(
      `SELECT
         id,
         status,
         settlement_status,
         total_amount,
         store_net_received_amount,
         app_due_from_delivery,
         difference_amount,
         difference_reason,
         archive_date
       FROM delivery_cash_settlement
       WHERE merchant_id = $1
         AND delivery_user_id = $2
         AND status IN ('pending', 'received')
         AND COALESCE(settlement_status, 'pending_store_confirmation') NOT IN ('closed', 'cancelled')
       ORDER BY requested_at ASC, id ASC`,
      [merchantId, Number(deliveryUserId)]
    );

    const readiness = evaluateCourierEndDayReadiness(pendingSettlements.rows);
    return {
      ...readiness,
      merchantId,
    };
  } finally {
    client.release();
  }
}

export async function listFavoriteProductIds(customerUserId) {
  const r = await q(
    `SELECT product_id
     FROM customer_favorite_product
     WHERE customer_user_id = $1`,
    [Number(customerUserId)]
  );

  return r.rows.map((row) => Number(row.product_id));
}

export async function listFavoriteProducts(
  customerUserId,
  { merchantId = null, limit = 40, offset = 0 } = {}
) {
  const safeLimit = Math.max(1, Math.min(120, Number(limit) || 40));
  const safeOffset = Math.max(0, Math.min(100000, Number(offset) || 0));

  const params = [Number(customerUserId)];
  let merchantWhere = "";
  if (merchantId) {
    params.push(Number(merchantId));
    merchantWhere = `AND p.merchant_id = $${params.length}`;
  }

  params.push(safeLimit + 1);
  const limitIndex = params.length;
  params.push(safeOffset);
  const offsetIndex = params.length;

  const r = await q(
    `SELECT
       p.*,
       m.name AS merchant_name,
       m.id AS merchant_id
     FROM customer_favorite_product f
     JOIN product p ON p.id = f.product_id
     JOIN merchant m ON m.id = p.merchant_id
     WHERE f.customer_user_id = $1
       AND p.is_available = TRUE
       AND m.is_approved = TRUE
       AND m.is_disabled = FALSE
       ${merchantWhere}
     ORDER BY f.created_at DESC, p.id DESC
     LIMIT $${limitIndex}
     OFFSET $${offsetIndex}`,
    params
  );

  const hasMore = r.rows.length > safeLimit;
  const items = hasMore ? r.rows.slice(0, safeLimit) : r.rows;
  return {
    items,
    nextOffset: hasMore ? safeOffset + safeLimit : null,
    limit: safeLimit,
    offset: safeOffset,
  };
}

export async function addFavoriteProduct(customerUserId, productId) {
  const insertResult = await q(
    `INSERT INTO customer_favorite_product (customer_user_id, product_id)
     SELECT $1, p.id
     FROM product p
     JOIN merchant m ON m.id = p.merchant_id
     WHERE p.id = $2
       AND m.is_approved = TRUE
       AND m.is_disabled = FALSE
     ON CONFLICT (customer_user_id, product_id) DO NOTHING
     RETURNING product_id`,
    [Number(customerUserId), Number(productId)]
  );

  if (insertResult.rows[0]) return true;

  const existsResult = await q(
    `SELECT id
     FROM product
     WHERE id = $1`,
    [Number(productId)]
  );

  if (!existsResult.rows[0]) {
    const err = new Error("PRODUCT_NOT_FOUND");
    err.status = 404;
    throw err;
  }

  return true;
}

export async function removeFavoriteProduct(customerUserId, productId) {
  await q(
    `DELETE FROM customer_favorite_product
     WHERE customer_user_id = $1
       AND product_id = $2`,
    [Number(customerUserId), Number(productId)]
  );
}

export async function getOrderForReorder(customerUserId, orderId) {
  const orderResult = await q(
    `SELECT
       id,
       merchant_id,
       note,
       customer_city,
       customer_block,
       customer_building_number,
       customer_apartment
     FROM customer_order
     WHERE id = $1
       AND customer_user_id = $2
       AND status NOT IN ('cancelled','cancelled_by_customer','cancelled_by_store','cancelled_by_admin')`,
    [Number(orderId), Number(customerUserId)]
  );

  const order = orderResult.rows[0];
  if (!order) return null;

  const itemsResult = await q(
    `SELECT
       product_id,
       selected_modifiers_json,
       selected_variant_json,
       SUM(quantity)::int AS quantity
     FROM order_item
     WHERE order_id = $1
       AND product_id IS NOT NULL
     GROUP BY product_id, selected_modifiers_json, selected_variant_json
     ORDER BY product_id ASC`,
    [Number(order.id)]
  );

  return {
    orderId: Number(order.id),
    merchantId: Number(order.merchant_id),
    note: order.note || null,
    customerCity: order.customer_city || "مدينة بسماية",
    customerBlock: order.customer_block,
    customerBuildingNumber: order.customer_building_number,
    customerApartment: order.customer_apartment,
    items: itemsResult.rows.map((row) => ({
      productId: Number(row.product_id),
      quantity: Number(row.quantity),
      selectedModifiers: Array.isArray(row.selected_modifiers_json)
        ? row.selected_modifiers_json
        : [],
      selectedVariant: row.selected_variant_json || null,
    })),
  };
}



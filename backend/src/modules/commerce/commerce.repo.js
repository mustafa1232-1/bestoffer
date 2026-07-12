import { pool, q } from "../../config/db.js";
import { AppError } from "../../shared/utils/errors.js";
import { createManyNotifications } from "../notifications/notifications.repo.js";
import {
  buildDeliveryAssignmentPresentation,
  DELIVERY_ASSIGNMENT_STATUSES,
  normalizeDeliveryAssignmentStatus,
} from "../orders/delivery-assignment.logic.js";
import {
  assertCompetitionTiers,
  finalizeExpiredCompetitionsTx,
  onOrderFinallyCompletedTx,
  resolveHighestRank,
} from "./competition.engine.js";
import {
  computeOrderFinancialSnapshot as buildOrderFinancialSnapshot,
  normalizeApprovalStatus,
  normalizeMerchantBillingProfile,
} from "./merchant-financial.logic.js";
import {
  loadProductRichCatalogByIds,
} from "../products/products.repo.js";
import { syncOrderIncentiveConsumptionForStatusTx } from "../orders/order-incentives.repo.js";

const DELIVERY_APPROVED_FILTER = `
  u.role = 'delivery'
  AND u.delivery_account_approved = TRUE
  AND u.is_account_disabled = FALSE
  AND NOT EXISTS (
    SELECT 1
    FROM taxi_captain_profile tcp
    WHERE tcp.user_id = u.id
  )
`;

const DEFAULT_ASSIGNMENT_TTL_MIN = 8;
const REQUEST_TYPE_STORE_PAYS_APP = "store_pays_app";
const REQUEST_TYPE_APP_PAYS_STORE = "app_pays_store";
const SELECTION_MODE_ALL_INVOICES = "all_invoices";
const SELECTION_MODE_MANUAL = "manual_selection";
const SELECTION_MODE_AUTO = "auto_match_amount";
const DRIVER_TYPE_APP = "app_driver";
const DRIVER_TYPE_STORE = "store_driver";
const STORE_PAYMENT_METHODS = new Set([
  "cash",
  "bank_transfer",
  "zain_cash",
  "asiacell_cash",
  "manual_handover",
  "other",
]);
const DEFAULT_DELIVERY_DISPATCH_POLICY_CONFIG = Object.freeze({
  maxRecipients: 12,
  waveSize: 4,
  weights: {
    rating: 0.42,
    speed: 0.28,
    proximity: 0.2,
    availability: 0.1,
    fatigue: 0.08,
  },
  fallback: {
    unratedCourierRating: 3.5,
    avgDeliveryMinutes: 40,
    sameBlockProximity: 1,
    nearbyBlockProximity: 0.55,
  },
});

function clampDispatchNumber(value, fallback, min, max) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function normalizeDeliveryDispatchPolicyConfig(input = {}) {
  const source = input && typeof input === "object" ? input : {};
  const weightsSource =
    source.weights && typeof source.weights === "object" ? source.weights : {};
  const fallbackSource =
    source.fallback && typeof source.fallback === "object"
      ? source.fallback
      : {};

  return {
    maxRecipients: Math.round(
      clampDispatchNumber(
        source.maxRecipients,
        DEFAULT_DELIVERY_DISPATCH_POLICY_CONFIG.maxRecipients,
        1,
        60
      )
    ),
    waveSize: Math.round(
      clampDispatchNumber(
        source.waveSize,
        DEFAULT_DELIVERY_DISPATCH_POLICY_CONFIG.waveSize,
        1,
        20
      )
    ),
    weights: {
      rating: clampDispatchNumber(
        weightsSource.rating,
        DEFAULT_DELIVERY_DISPATCH_POLICY_CONFIG.weights.rating,
        0,
        1
      ),
      speed: clampDispatchNumber(
        weightsSource.speed,
        DEFAULT_DELIVERY_DISPATCH_POLICY_CONFIG.weights.speed,
        0,
        1
      ),
      proximity: clampDispatchNumber(
        weightsSource.proximity,
        DEFAULT_DELIVERY_DISPATCH_POLICY_CONFIG.weights.proximity,
        0,
        1
      ),
      availability: clampDispatchNumber(
        weightsSource.availability,
        DEFAULT_DELIVERY_DISPATCH_POLICY_CONFIG.weights.availability,
        0,
        1
      ),
      fatigue: clampDispatchNumber(
        weightsSource.fatigue,
        DEFAULT_DELIVERY_DISPATCH_POLICY_CONFIG.weights.fatigue,
        0,
        1
      ),
    },
    fallback: {
      unratedCourierRating: clampDispatchNumber(
        fallbackSource.unratedCourierRating,
        DEFAULT_DELIVERY_DISPATCH_POLICY_CONFIG.fallback.unratedCourierRating,
        0,
        5
      ),
      avgDeliveryMinutes: clampDispatchNumber(
        fallbackSource.avgDeliveryMinutes,
        DEFAULT_DELIVERY_DISPATCH_POLICY_CONFIG.fallback.avgDeliveryMinutes,
        5,
        180
      ),
      sameBlockProximity: clampDispatchNumber(
        fallbackSource.sameBlockProximity,
        DEFAULT_DELIVERY_DISPATCH_POLICY_CONFIG.fallback.sameBlockProximity,
        0,
        1
      ),
      nearbyBlockProximity: clampDispatchNumber(
        fallbackSource.nearbyBlockProximity,
        DEFAULT_DELIVERY_DISPATCH_POLICY_CONFIG.fallback.nearbyBlockProximity,
        0,
        1
      ),
    },
  };
}

async function loadDeliveryDispatchPolicyTx(client) {
  try {
    const result = await client.query(
      `SELECT config_json
       FROM delivery_dispatch_policy
       WHERE policy_key = 'default'
       ORDER BY updated_at DESC
       LIMIT 1`
    );
    return normalizeDeliveryDispatchPolicyConfig(result.rows[0]?.config_json || {});
  } catch (error) {
    if (String(error?.code || "") === "42P01") {
      return normalizeDeliveryDispatchPolicyConfig({});
    }
    throw error;
  }
}

function computeCourierDispatchScore(row, { normalizedBlock, useBlock, policy }) {
  const availabilityStatus = String(row?.availability_status || "").trim().toLowerCase();
  const block = String(row?.block || "").trim().toUpperCase();
  const sameBlock =
    useBlock &&
    normalizedBlock.length > 0 &&
    block.length > 0 &&
    block === normalizedBlock.toUpperCase();

  const fallback = policy.fallback || DEFAULT_DELIVERY_DISPATCH_POLICY_CONFIG.fallback;
  const weights = policy.weights || DEFAULT_DELIVERY_DISPATCH_POLICY_CONFIG.weights;
  const ratingRaw = clampDispatchNumber(
    row?.courier_rating,
    fallback.unratedCourierRating,
    0,
    5
  );
  const ratingScore = ratingRaw / 5;
  const avgDeliveryMinutes = clampDispatchNumber(
    row?.avg_delivery_minutes,
    fallback.avgDeliveryMinutes,
    1,
    240
  );
  const speedScore = clampDispatchNumber((90 - avgDeliveryMinutes) / 90, 0, 0, 1);
  const proximityScore = useBlock
    ? sameBlock
      ? fallback.sameBlockProximity
      : fallback.nearbyBlockProximity
    : fallback.nearbyBlockProximity;
  const availabilityScore =
    availabilityStatus === "online"
      ? 1
      : availabilityStatus === "away"
        ? 0.5
        : 0.2;
  const pendingCount = clampDispatchNumber(row?.recent_pending_count, 0, 0, 50);
  const rejectCount = clampDispatchNumber(row?.recent_reject_count, 0, 0, 50);
  const fatiguePenalty = clampDispatchNumber(
    rejectCount * 0.12 + pendingCount * 0.06,
    0,
    0,
    1
  );

  const score =
    ratingScore * weights.rating +
    speedScore * weights.speed +
    proximityScore * weights.proximity +
    availabilityScore * weights.availability -
    fatiguePenalty * weights.fatigue;

  return {
    score,
    debug: {
      ratingRaw,
      ratingScore,
      avgDeliveryMinutes,
      speedScore,
      proximityScore,
      availabilityStatus,
      availabilityScore,
      fatiguePenalty,
      recentRejectCount: rejectCount,
      recentPendingCount: pendingCount,
      sameBlock,
      weights,
    },
  };
}

function normalizeCourierDriverType(value, fallback = DRIVER_TYPE_APP) {
  const normalized = String(value || "").trim().toLowerCase();
  if (normalized === DRIVER_TYPE_STORE) return DRIVER_TYPE_STORE;
  if (normalized === DRIVER_TYPE_APP) return DRIVER_TYPE_APP;
  return fallback;
}

function driverTypeFlags(driverType) {
  const normalized = normalizeCourierDriverType(driverType);
  return {
    driverType: normalized,
    isAppCourier: normalized === DRIVER_TYPE_APP,
    isMerchantCourier: normalized === DRIVER_TYPE_STORE,
  };
}

const REQUEST_STATUS = {
  draft: "draft",
  pendingAdminConfirmation: "pending_admin_confirmation",
  pendingAdminReview: "pending_admin_review",
  approvedByAdmin: "approved_by_admin",
  assignedForPayment: "assigned_for_payment",
  awaitingStoreConfirmation: "awaiting_store_confirmation",
  confirmedByAdmin: "confirmed_by_admin",
  confirmedReceivedByStore: "confirmed_received_by_store",
  returnedForRevision: "returned_for_revision",
  issueReportedByStore: "issue_reported_by_store",
  rejectedByAdmin: "rejected_by_admin",
  cancelled: "cancelled",
};

const LOCKED_REQUEST_STATUSES = new Set([
  REQUEST_STATUS.confirmedByAdmin,
  REQUEST_STATUS.confirmedReceivedByStore,
]);

const PAYMENT_REQUEST_PATCHABLE_COLUMNS = new Set([
  "status",
  "updated_by_user_id",
  "reviewed_at",
  "reviewed_by_user_id",
  "review_note",
  "internal_admin_note",
  "paid_amount",
  "final_confirmed_at",
  "final_confirmed_by_user_id",
  "assigned_to_user_id",
  "assigned_to_name",
  "admin_payment_method",
  "admin_reference_code",
  "admin_payment_date",
  "admin_payment_actor_name",
  "issue_note",
  "is_locked",
  "locked_at",
]);

const LIFECYCLE_LABEL = {
  pending: "PENDING",
  approved: "ACCEPTED_BY_STORE",
  preparing: "PREPARING",
  ready_for_delivery: "READY_FOR_PICKUP",
  on_the_way: "ON_THE_WAY",
  arrived: "ARRIVED",
  delivered: "DELIVERED_BY_COURIER",
  completed: "COMPLETED",
  cancelled: "CANCELLED_BY_STORE",
  cancelled_by_customer: "CANCELLED_BY_CUSTOMER",
  cancelled_by_store: "CANCELLED_BY_STORE",
  cancelled_by_admin: "CANCELLED_BY_ADMIN",
  failed_delivery: "FAILED_DELIVERY",
  returned_if_needed: "RETURNED_IF_NEEDED",
};

function toNumber(v, fallback = 0) {
  const n = Number(v);
  return Number.isFinite(n) ? n : fallback;
}

function round2(value) {
  return Math.round((toNumber(value, 0) + Number.EPSILON) * 100) / 100;
}

function normalizePaymentRequestType(value) {
  const normalized = String(value || "").trim().toLowerCase();
  if (normalized === REQUEST_TYPE_APP_PAYS_STORE) return REQUEST_TYPE_APP_PAYS_STORE;
  return REQUEST_TYPE_STORE_PAYS_APP;
}

function normalizePaymentScope(value) {
  const normalized = String(value || "").trim().toLowerCase();
  if (["commission", "service", "delivery", "all"].includes(normalized)) {
    return normalized;
  }
  return "all";
}

function normalizeSelectionMode(value) {
  const normalized = String(value || "").trim().toLowerCase();
  if (
    [
      SELECTION_MODE_ALL_INVOICES,
      SELECTION_MODE_MANUAL,
      SELECTION_MODE_AUTO,
    ].includes(normalized)
  ) {
    return normalized;
  }
  return SELECTION_MODE_ALL_INVOICES;
}

function normalizePaymentMethod(value) {
  const normalized = String(value || "").trim().toLowerCase();
  if (STORE_PAYMENT_METHODS.has(normalized)) return normalized;
  return null;
}

function normalizeRequestStatus(value) {
  const normalized = String(value || "").trim().toLowerCase();
  return Object.values(REQUEST_STATUS).includes(normalized)
    ? normalized
    : REQUEST_STATUS.pendingAdminConfirmation;
}

function parseJsonOrEmpty(value) {
  if (!value) return {};
  if (typeof value === "object" && !Array.isArray(value)) return value;
  try {
    const parsed = JSON.parse(String(value));
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) return parsed;
    return {};
  } catch (_) {
    return {};
  }
}

function lifecycleFromStatus(status, fallback = "PENDING") {
  return LIFECYCLE_LABEL[String(status || "").trim().toLowerCase()] || fallback;
}

function assertOwnerOrderEditable(status) {
  if (
    [
      "delivered",
      "completed",
      "cancelled",
      "cancelled_by_store",
      "cancelled_by_admin",
    ].includes(String(status || ""))
  ) {
    throw new AppError("ORDER_NOT_EDITABLE", { status: 409 });
  }
}

async function insertStatusHistoryTx(
  client,
  {
    orderId,
    oldStatus,
    newStatus,
    lifecycleOld,
    lifecycleNew,
    changedByUserId,
    changedByRole,
    note = null,
  }
) {
  let actorUserId = null;
  if (changedByUserId != null) {
    const actorCheck = await client.query(
      `SELECT 1
       FROM app_user
       WHERE id = $1
       LIMIT 1`,
      [Number(changedByUserId)]
    );
    if (actorCheck.rowCount > 0) {
      actorUserId = Number(changedByUserId);
    }
  }

  await client.query(
    `INSERT INTO order_status_history
      (
        order_id,
        old_status,
        new_status,
        lifecycle_old,
        lifecycle_new,
        changed_by_user_id,
        changed_by_role,
        note
      )
     VALUES ($1,$2::order_status,$3::order_status,$4,$5,$6,$7,$8)`,
    [
      Number(orderId),
      oldStatus || null,
      newStatus || null,
      lifecycleOld || null,
      lifecycleNew || null,
      actorUserId,
      changedByRole || null,
      note,
    ]
  );
}

async function ensureCourierProfileTx(
  client,
  {
    userId,
    driverType = DRIVER_TYPE_APP,
    merchantId = null,
    merchantIdSet = false,
    coverageBlock = null,
    vehicleType = null,
    availabilityStatus = null,
    activeStatus = null,
  }
) {
  const normalizedMerchantId =
    merchantId == null || merchantId === "" ? null : Number(merchantId);
  const flags = driverTypeFlags(driverType);
  await client.query(
    `INSERT INTO courier_profile
      (
        user_id,
        is_app_courier,
        is_merchant_courier,
        merchant_id,
        driver_type,
        active_status,
        availability_status
      )
     VALUES ($1,$2,$3,$4,$5,TRUE,'online')
     ON CONFLICT (user_id)
     DO UPDATE
       SET is_app_courier = EXCLUDED.is_app_courier,
           is_merchant_courier = EXCLUDED.is_merchant_courier,
           driver_type = EXCLUDED.driver_type,
           merchant_id = CASE
             WHEN $6::boolean THEN EXCLUDED.merchant_id
             ELSE courier_profile.merchant_id
           END,
           updated_at = NOW()`,
    [
      Number(userId),
      flags.isAppCourier,
      flags.isMerchantCourier,
      normalizedMerchantId,
      flags.driverType,
      merchantIdSet === true,
    ]
  );

  if (
    coverageBlock != null ||
    vehicleType != null ||
    availabilityStatus != null ||
    typeof activeStatus === "boolean"
  ) {
    await client.query(
      `UPDATE courier_profile
       SET coverage_block = COALESCE($2, coverage_block),
           vehicle_type = COALESCE($3, vehicle_type),
           availability_status = COALESCE($4, availability_status),
           active_status = COALESCE($5::boolean, active_status),
           updated_at = NOW()
       WHERE user_id = $1`,
      [
        Number(userId),
        coverageBlock || null,
        vehicleType ? String(vehicleType).trim().slice(0, 60) : null,
        availabilityStatus ? String(availabilityStatus).trim().slice(0, 20) : null,
        typeof activeStatus === "boolean" ? activeStatus : null,
      ]
    );
  }
}

async function deactivateCourierMerchantLinksTx(client, userId, exceptMerchantId = null) {
  await client.query(
    `UPDATE merchant_delivery_agent
     SET is_active = FALSE,
         updated_at = NOW()
     WHERE delivery_user_id = $1
       AND is_active = TRUE
       AND ($2::bigint IS NULL OR merchant_id <> $2::bigint)`,
    [Number(userId), exceptMerchantId == null ? null : Number(exceptMerchantId)]
  );
}

export async function courierHasActiveOrders(courierUserId, client = null) {
  const exec = client || { query: q };
  const result = await exec.query(
    `SELECT 1
     FROM customer_order
     WHERE delivery_user_id = $1
       AND status NOT IN (
         'delivered',
         'completed',
         'received_by_customer',
         'cancelled',
         'cancelled_by_store',
         'cancelled_by_admin',
         'cancelled_by_customer'
       )
     LIMIT 1`,
    [Number(courierUserId)]
  );
  return !!result.rows[0];
}

export async function syncCourierDriverAffiliation({
  userId,
  driverType,
  merchantId = null,
  merchantIdSet = false,
  coverageBlock = null,
  vehicleType = null,
  activeStatus = null,
  availabilityStatus = null,
  actorUserId = null,
  source = "admin",
  client: existingClient = null,
}) {
  const normalizedDriverType = normalizeCourierDriverType(driverType);
  const normalizedMerchantId =
    merchantId == null || merchantId === "" ? null : Number(merchantId);

  if (normalizedDriverType === DRIVER_TYPE_STORE) {
    if (!Number.isInteger(normalizedMerchantId) || normalizedMerchantId <= 0) {
      throw new AppError("STORE_DRIVER_MERCHANT_REQUIRED", { status: 400 });
    }
  }

  const client = existingClient || (await pool.connect());
  try {
    if (!existingClient) {
      await client.query("BEGIN");
    }

    const currentProfile = await client.query(
      `SELECT driver_type, merchant_id
       FROM courier_profile
       WHERE user_id = $1
       LIMIT 1`,
      [Number(userId)]
    );
    const currentProfileRow = currentProfile.rows[0] || null;
    const currentDriverType = currentProfileRow?.driver_type
      ? normalizeCourierDriverType(currentProfileRow.driver_type, DRIVER_TYPE_APP)
      : null;

    if (
      currentDriverType != null &&
      currentDriverType !== normalizedDriverType &&
      (await courierHasActiveOrders(Number(userId), client))
    ) {
      throw new AppError("DELIVERY_DRIVER_TYPE_CHANGE_BLOCKED_BY_ACTIVE_ORDERS", {
        status: 409,
      });
    }

    await ensureCourierProfileTx(client, {
      userId: Number(userId),
      driverType: normalizedDriverType,
      merchantId: normalizedMerchantId,
      merchantIdSet: merchantIdSet === true,
      coverageBlock,
      vehicleType,
      activeStatus,
      availabilityStatus,
    });

    if (normalizedDriverType === DRIVER_TYPE_STORE) {
      await deactivateCourierMerchantLinksTx(client, Number(userId), normalizedMerchantId);
      await client.query(
        `INSERT INTO merchant_delivery_agent
          (
            merchant_id,
            delivery_user_id,
            created_by_user_id,
            source,
            is_active,
            created_at,
            updated_at
          )
         VALUES ($1,$2,$3,$4,TRUE,NOW(),NOW())
         ON CONFLICT (merchant_id, delivery_user_id)
         DO UPDATE SET
           is_active = TRUE,
           source = EXCLUDED.source,
           created_by_user_id = COALESCE(EXCLUDED.created_by_user_id, merchant_delivery_agent.created_by_user_id),
           updated_at = NOW()`,
        [
          Number(normalizedMerchantId),
          Number(userId),
          Number(actorUserId) || null,
          String(source || "admin").slice(0, 20),
        ]
      );
    } else {
      await deactivateCourierMerchantLinksTx(client, Number(userId), null);
    }

    if (!existingClient) {
      await client.query("COMMIT");
    }
    return {
      userId: Number(userId),
      driverType: normalizedDriverType,
      merchantId: normalizedMerchantId,
    };
  } catch (error) {
    if (!existingClient) {
      await client.query("ROLLBACK");
    }
    throw error;
  } finally {
    if (!existingClient) {
      client.release();
    }
  }
}

export async function listBackofficeUserIds() {
  const r = await q(
    `SELECT id
     FROM app_user
     WHERE role IN ('admin', 'deputy_admin')
       AND is_account_disabled = FALSE`
  );
  return r.rows.map((row) => Number(row.id)).filter((id) => id > 0);
}

export async function listActiveCourierUsers() {
  const r = await q(
    `SELECT
       u.id,
       u.full_name
     FROM app_user u
     WHERE ${DELIVERY_APPROVED_FILTER}
     ORDER BY u.id DESC`
  );
  return r.rows.map((row) => ({
    id: Number(row.id),
    fullName: String(row.full_name || "").trim(),
  }));
}

export async function getOwnerOrderWithMerchant(
  ownerUserId,
  orderId,
  client = null,
  { forUpdate = false } = {}
) {
  const exec = client || { query: q };
  const r = await exec.query(
    `SELECT
       o.*,
       m.owner_user_id,
       m.name AS merchant_name,
       m.type AS merchant_type,
       m.phone AS merchant_phone,
       m.service_area_note,
       m.id AS merchant_id,
       m.is_open AS merchant_is_open,
       m.is_disabled AS merchant_is_disabled
     FROM customer_order o
     JOIN merchant m ON m.id = o.merchant_id
     WHERE o.id = $1
       AND m.owner_user_id = $2
     ${forUpdate ? "FOR UPDATE" : ""}`,
    [Number(orderId), Number(ownerUserId)]
  );
  return r.rows[0] || null;
}

async function listEligibleCouriersTx(
  client,
  { merchantId, customerBlock = null, explicitCourierUserId = null }
) {
  const dispatchPolicy = await loadDeliveryDispatchPolicyTx(client);
  if (explicitCourierUserId) {
    const explicit = await client.query(
      `SELECT
         u.id,
         u.full_name,
         u.phone,
         u.block,
         cp.availability_status,
         COALESCE(cp.rating, 0)::numeric AS courier_rating,
         COALESCE(cp.driver_type, CASE WHEN mda.delivery_user_id IS NULL THEN '${DRIVER_TYPE_APP}' ELSE '${DRIVER_TYPE_STORE}' END) AS driver_type,
         CASE
           WHEN COALESCE(cp.driver_type, '${DRIVER_TYPE_APP}') = '${DRIVER_TYPE_STORE}'
             AND mda.delivery_user_id IS NOT NULL
           THEN TRUE
           ELSE FALSE
         END AS is_merchant_courier,
         COALESCE(cds.avg_delivery_minutes, 0)::numeric AS avg_delivery_minutes,
         COALESCE(fatigue.recent_reject_count, 0)::int AS recent_reject_count,
         COALESCE(fatigue.recent_pending_count, 0)::int AS recent_pending_count
       FROM app_user u
       LEFT JOIN courier_profile cp ON cp.user_id = u.id
       LEFT JOIN merchant_delivery_agent mda
         ON mda.delivery_user_id = u.id
        AND mda.merchant_id = $2
        AND mda.is_active = TRUE
       LEFT JOIN LATERAL (
         SELECT AVG(cds.avg_delivery_minutes)::numeric AS avg_delivery_minutes
         FROM courier_daily_stats cds
         WHERE cds.courier_user_id = u.id
           AND cds.stat_date >= CURRENT_DATE - INTERVAL '30 day'
       ) cds ON TRUE
       LEFT JOIN LATERAL (
         SELECT
           COUNT(*) FILTER (
             WHERE ca.status = 'rejected'
               AND ca.requested_at >= NOW() - INTERVAL '6 hour'
           )::int AS recent_reject_count,
           COUNT(*) FILTER (
             WHERE ca.status = 'pending'
               AND ca.requested_at >= NOW() - INTERVAL '20 minute'
           )::int AS recent_pending_count
         FROM courier_assignment ca
         WHERE ca.courier_user_id = u.id
       ) fatigue ON TRUE
       WHERE u.id = $1
         AND ${DELIVERY_APPROVED_FILTER}
         AND (
           COALESCE(cp.driver_type, CASE WHEN mda.delivery_user_id IS NULL THEN '${DRIVER_TYPE_APP}' ELSE '${DRIVER_TYPE_STORE}' END) = '${DRIVER_TYPE_APP}'
           OR (
             COALESCE(cp.driver_type, CASE WHEN mda.delivery_user_id IS NULL THEN '${DRIVER_TYPE_APP}' ELSE '${DRIVER_TYPE_STORE}' END) = '${DRIVER_TYPE_STORE}'
             AND mda.delivery_user_id IS NOT NULL
           )
         )`,
      [Number(explicitCourierUserId), Number(merchantId)]
    );
    const normalizedBlock = String(customerBlock || "").trim();
    return explicit.rows.map((row) => {
      const ranking = computeCourierDispatchScore(row, {
        normalizedBlock,
        useBlock: normalizedBlock.length > 0,
        policy: dispatchPolicy,
      });
      return {
        ...row,
        dispatch_score: ranking.score,
        dispatch_rank: 1,
        dispatch_wave: 1,
        dispatch_wave_size: dispatchPolicy.waveSize,
        dispatch_debug: ranking.debug,
      };
    });
  }

  const normalizedBlock = String(customerBlock || "").trim();
  const useBlock = normalizedBlock.length > 0;

  const r = await client.query(
    `SELECT
       u.id,
       u.full_name,
       u.phone,
       u.block,
       cp.availability_status,
       COALESCE(cp.rating, 0)::numeric AS courier_rating,
       COALESCE(cp.driver_type, CASE WHEN mda.delivery_user_id IS NULL THEN '${DRIVER_TYPE_APP}' ELSE '${DRIVER_TYPE_STORE}' END) AS driver_type,
       CASE
         WHEN COALESCE(cp.driver_type, '${DRIVER_TYPE_APP}') = '${DRIVER_TYPE_STORE}'
           AND mda.delivery_user_id IS NOT NULL
         THEN TRUE
         ELSE FALSE
       END AS is_merchant_courier,
       COALESCE(cds.avg_delivery_minutes, 0)::numeric AS avg_delivery_minutes,
       COALESCE(fatigue.recent_reject_count, 0)::int AS recent_reject_count,
       COALESCE(fatigue.recent_pending_count, 0)::int AS recent_pending_count
     FROM app_user u
     LEFT JOIN courier_profile cp ON cp.user_id = u.id
     LEFT JOIN merchant_delivery_agent mda
       ON mda.delivery_user_id = u.id
      AND mda.merchant_id = $1
      AND mda.is_active = TRUE
     LEFT JOIN LATERAL (
       SELECT AVG(cds.avg_delivery_minutes)::numeric AS avg_delivery_minutes
       FROM courier_daily_stats cds
       WHERE cds.courier_user_id = u.id
         AND cds.stat_date >= CURRENT_DATE - INTERVAL '30 day'
     ) cds ON TRUE
     LEFT JOIN LATERAL (
       SELECT
         COUNT(*) FILTER (
           WHERE ca.status = 'rejected'
             AND ca.requested_at >= NOW() - INTERVAL '6 hour'
         )::int AS recent_reject_count,
         COUNT(*) FILTER (
           WHERE ca.status = 'pending'
             AND ca.requested_at >= NOW() - INTERVAL '20 minute'
         )::int AS recent_pending_count
       FROM courier_assignment ca
       WHERE ca.courier_user_id = u.id
     ) fatigue ON TRUE
     WHERE ${DELIVERY_APPROVED_FILTER}
       AND (
         (
           COALESCE(cp.driver_type, '${DRIVER_TYPE_APP}') = '${DRIVER_TYPE_STORE}'
           AND mda.delivery_user_id IS NOT NULL
         )
         OR (
           COALESCE(cp.driver_type, '${DRIVER_TYPE_APP}') = '${DRIVER_TYPE_APP}'
           AND $2::boolean = TRUE
           AND u.block IS NOT NULL
           AND UPPER(TRIM(u.block)) = UPPER(TRIM($3))
         )
       )
     ORDER BY u.id DESC`,
    [Number(merchantId), useBlock, normalizedBlock || null]
  );

  const ranked = r.rows
    .map((row) => {
      const ranking = computeCourierDispatchScore(row, {
        normalizedBlock,
        useBlock,
        policy: dispatchPolicy,
      });
      return {
        ...row,
        dispatch_score: ranking.score,
        dispatch_debug: ranking.debug,
      };
    })
    .sort((a, b) => {
      const merchantRankDiff =
        Number(b.is_merchant_courier === true) - Number(a.is_merchant_courier === true);
      if (merchantRankDiff !== 0) return merchantRankDiff;
      const scoreDiff = Number(b.dispatch_score || 0) - Number(a.dispatch_score || 0);
      if (scoreDiff !== 0) return scoreDiff;
      const ratingDiff = Number(b.courier_rating || 0) - Number(a.courier_rating || 0);
      if (ratingDiff !== 0) return ratingDiff;
      return Number(b.id || 0) - Number(a.id || 0);
    })
    .slice(0, Math.max(1, Number(dispatchPolicy.maxRecipients || 12)))
    .map((row, index) => ({
      ...row,
      dispatch_rank: index + 1,
      dispatch_wave: Math.floor(index / Math.max(1, dispatchPolicy.waveSize)) + 1,
      dispatch_wave_size: Math.max(1, dispatchPolicy.waveSize),
    }));

  return ranked;
}

function shuffleRows(rows) {
  const list = Array.isArray(rows) ? [...rows] : [];
  for (let i = list.length - 1; i > 0; i -= 1) {
    const j = Math.floor(Math.random() * (i + 1));
    if (j !== i) {
      const tmp = list[i];
      list[i] = list[j];
      list[j] = tmp;
    }
  }
  return list;
}

async function lockEligibleCourierCandidateTx(
  client,
  { merchantId, customerBlock = null, courierId, forceMerchantCourier = null }
) {
  const r = await client.query(
    `SELECT
       u.id,
       u.full_name,
       u.phone,
       u.image_url,
       u.block,
       cp.availability_status,
       COALESCE(cp.rating, 0)::numeric AS courier_rating,
       COALESCE(cp.driver_type, '${DRIVER_TYPE_APP}') AS driver_type,
       CASE
         WHEN COALESCE(cp.driver_type, '${DRIVER_TYPE_APP}') = '${DRIVER_TYPE_STORE}'
           AND mda.delivery_user_id IS NOT NULL
         THEN TRUE
         ELSE FALSE
       END AS is_merchant_courier,
       COALESCE(cds.avg_delivery_minutes, 0)::numeric AS avg_delivery_minutes,
       COALESCE(fatigue.recent_reject_count, 0)::int AS recent_reject_count,
       COALESCE(fatigue.recent_pending_count, 0)::int AS recent_pending_count
     FROM app_user u
     LEFT JOIN courier_profile cp ON cp.user_id = u.id
     LEFT JOIN merchant_delivery_agent mda
       ON mda.delivery_user_id = u.id
      AND mda.merchant_id = $2
      AND mda.is_active = TRUE
     LEFT JOIN LATERAL (
       SELECT AVG(cds.avg_delivery_minutes)::numeric AS avg_delivery_minutes
       FROM courier_daily_stats cds
       WHERE cds.courier_user_id = u.id
         AND cds.stat_date >= CURRENT_DATE - INTERVAL '30 day'
     ) cds ON TRUE
     LEFT JOIN LATERAL (
       SELECT
         COUNT(*) FILTER (
           WHERE ca.status = 'rejected'
             AND ca.requested_at >= NOW() - INTERVAL '6 hour'
         )::int AS recent_reject_count,
         COUNT(*) FILTER (
           WHERE ca.status = 'pending'
             AND ca.requested_at >= NOW() - INTERVAL '20 minute'
         )::int AS recent_pending_count
       FROM courier_assignment ca
       WHERE ca.courier_user_id = u.id
         AND ca.ended_at IS NULL
     ) fatigue ON TRUE
     WHERE u.id = $1
       AND ${DELIVERY_APPROVED_FILTER}
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
         FROM courier_assignment open_assignment
         WHERE open_assignment.courier_user_id = u.id
           AND open_assignment.ended_at IS NULL
       )
       AND NOT EXISTS (
         SELECT 1
         FROM taxi_captain_profile tcp
         WHERE tcp.user_id = u.id
       )
       AND (
         $3::boolean IS NULL
         OR (
           $3::boolean = TRUE
           AND COALESCE(cp.driver_type, '${DRIVER_TYPE_APP}') = '${DRIVER_TYPE_STORE}'
           AND mda.delivery_user_id IS NOT NULL
         )
         OR (
           $3::boolean = FALSE
           AND COALESCE(cp.driver_type, '${DRIVER_TYPE_APP}') = '${DRIVER_TYPE_APP}'
           AND (
             $4::text IS NULL
             OR (
               u.block IS NOT NULL
               AND UPPER(TRIM(u.block)) = UPPER(TRIM($4))
             )
           )
          )
        )
     FOR UPDATE OF u SKIP LOCKED
     LIMIT 1`,
    [
      Number(courierId),
      Number(merchantId),
      forceMerchantCourier,
      customerBlock == null ? null : String(customerBlock).trim() || null,
    ]
  );
  const row = r.rows[0] || null;
  if (!row) return null;

  const normalizedBlock = String(customerBlock || "").trim();
  const ranking = computeCourierDispatchScore(row, {
    normalizedBlock,
    useBlock: normalizedBlock.length > 0,
    policy: await loadDeliveryDispatchPolicyTx(client),
  });
  return {
    ...row,
    dispatch_score: ranking.score,
    dispatch_debug: ranking.debug,
  };
}

export async function directAssignDeliveryOrderTx(
  client,
  {
    orderId,
    merchantId,
    requestedByUserId = null,
    customerBlock = null,
    assignmentType = "store_auto",
    explicitCourierUserId = null,
    allowPending = true,
    note = null,
    forceMerchantCourier = null,
  }
) {
  const currentResult = await client.query(
    `SELECT
       o.id,
       o.merchant_id,
       o.status,
       o.customer_user_id,
       o.customer_block,
       o.delivery_user_id,
       o.delivery_assignment_status,
       o.assigned_by_store,
       o.is_merchant_delivery,
       o.courier_assigned_at,
       d.full_name AS delivery_full_name,
       d.phone AS delivery_phone,
       d.image_url AS delivery_image_url,
       cp.driver_type AS delivery_driver_type,
       cp.rating AS delivery_rating,
       cp.availability_status AS delivery_availability_status,
       cp.coverage_block AS delivery_coverage_block,
       cp.vehicle_type AS delivery_vehicle_type,
       m.name AS merchant_name
     FROM customer_order o
     JOIN merchant m ON m.id = o.merchant_id
     LEFT JOIN app_user d ON d.id = o.delivery_user_id
     LEFT JOIN courier_profile cp ON cp.user_id = d.id
     WHERE o.id = $1
       AND m.id = $2
      FOR UPDATE OF o, m`,
    [Number(orderId), Number(merchantId)]
  );

  const current = currentResult.rows[0] || null;
  if (!current) {
    throw new AppError("ORDER_NOT_FOUND", { status: 404 });
  }

  const normalizedStatus = normalizeDeliveryAssignmentStatus(
    current.delivery_assignment_status
  );
  if (
    normalizedStatus === DELIVERY_ASSIGNMENT_STATUSES.ASSIGNED &&
    Number(current.delivery_user_id || 0) > 0
  ) {
    const snapshot = await client.query(
      `SELECT
         ca.id,
         ca.status,
         ca.assigned_at,
         ca.ended_at,
         ca.ended_reason
       FROM courier_assignment ca
       WHERE ca.order_id = $1
         AND ca.ended_at IS NULL
       ORDER BY ca.id DESC
       LIMIT 1`,
      [Number(orderId)]
    );
    const deliveryAssignment = buildDeliveryAssignmentPresentation({
      order: current,
      openAssignmentRow: snapshot.rows[0] || null,
      latestAssignmentRow: snapshot.rows[0] || null,
    });
    return {
      order: current,
      driver: deliveryAssignment.driver,
      deliveryAssignment,
      alreadyAssigned: true,
      assignmentStatus: DELIVERY_ASSIGNMENT_STATUSES.ASSIGNED,
      pendingNoDriver: false,
      assignmentCreated: false,
    };
  }

  const orderStatus = String(current.status || "").trim().toLowerCase();
  const assignableStatuses = new Set([
    "approved",
    "preparing",
    "ready_for_delivery",
    "ready_for_pickup",
  ]);
  if (!assignableStatuses.has(orderStatus)) {
    return {
      order: current,
      driver: null,
      deliveryAssignment: buildDeliveryAssignmentPresentation({ order: current }),
      alreadyAssigned: false,
      assignmentStatus: normalizedStatus,
      pendingNoDriver: false,
      assignmentCreated: false,
      skipped: true,
    };
  }

  const eligibleRows = [];
  if (explicitCourierUserId != null) {
    const explicit = await lockEligibleCourierCandidateTx(client, {
      merchantId,
      customerBlock: customerBlock ?? current.customer_block ?? null,
      courierId: Number(explicitCourierUserId),
      forceMerchantCourier,
    });
    if (explicit) eligibleRows.push(explicit);
  } else {
    const ranked = await listEligibleCouriersTx(client, {
      merchantId: Number(merchantId),
      customerBlock: customerBlock ?? current.customer_block ?? null,
    });
    eligibleRows.push(...shuffleRows(ranked));
  }

  // Structured, non-sensitive diagnostics for "why did/didn't the order get a
  // driver". Never logs tokens, phones, or names — only ids and counts.
  const candidateUserIds = eligibleRows
    .map((row) => Number(row?.id))
    .filter((id) => Number.isFinite(id) && id > 0);
  const logAssignmentOutcome = (outcome) => {
    console.info("[delivery-auto-assign]", {
      orderId: Number(orderId),
      merchantId: Number(merchantId),
      requiresDelivery: true,
      assignmentType,
      explicit: explicitCourierUserId != null,
      eligibleDriversCount: candidateUserIds.length,
      candidateUserIds,
      ...outcome,
    });
  };

  const retryableErrors = new Set(["23505", "40001", "40P01"]);
  let lastError = null;
  const maxAttempts = Math.max(1, eligibleRows.length || 1);

  for (let attempt = 0; attempt < maxAttempts; attempt += 1) {
    const candidate = eligibleRows[attempt] || null;
    try {
      if (!candidate) break;

      const candidateLock = await lockEligibleCourierCandidateTx(client, {
        merchantId: Number(merchantId),
        customerBlock: customerBlock ?? current.customer_block ?? null,
        courierId: Number(candidate.id),
        forceMerchantCourier,
      });
      if (!candidateLock) continue;

      const activeAssignmentCheck = await client.query(
        `SELECT 1
         FROM customer_order active_order
         WHERE active_order.delivery_user_id = $1
           AND active_order.delivery_assignment_status = 'ASSIGNED'
         LIMIT 1`,
        [Number(candidateLock.id)]
      );
      if (activeAssignmentCheck.rowCount > 0) {
        continue;
      }

      let requestedByUserIdForAssignment = null;
      if (requestedByUserId != null) {
        const requestedByCheck = await client.query(
          `SELECT 1
           FROM app_user
           WHERE id = $1
           LIMIT 1`,
          [Number(requestedByUserId)]
        );
        if (requestedByCheck.rowCount > 0) {
          requestedByUserIdForAssignment = Number(requestedByUserId);
        }
      }

      const assignmentInsert = await client.query(
        `INSERT INTO courier_assignment
          (
            order_id,
            courier_user_id,
            assignment_type,
            status,
            requested_by_user_id,
            requested_at,
            assigned_at,
            responded_at,
            response_note,
            ended_at,
            ended_reason
          )
         VALUES ($1,$2,$3,'assigned',$4,NOW(),NOW(),NOW(),$5,NULL,NULL)
         RETURNING *`,
        [
          Number(orderId),
          Number(candidateLock.id),
          String(assignmentType || "store_auto"),
          requestedByUserIdForAssignment,
          note || null,
        ]
      );
      const assignment = assignmentInsert.rows[0];
      if (!assignment) {
        throw new AppError("DELIVERY_ASSIGNMENT_FAILED", { status: 409 });
      }

      const orderUpdate = await client.query(
        `UPDATE customer_order
         SET delivery_user_id = $1,
             delivery_assignment_status = 'ASSIGNED',
             courier_assigned_at = COALESCE(courier_assigned_at, NOW()),
             courier_requested_at = COALESCE(courier_requested_at, NOW()),
             courier_source = CASE
               WHEN $2::text = 'merchant_delivery' THEN 'merchant'
               ELSE 'app'
             END,
             is_merchant_delivery = CASE
               WHEN $2::text = 'merchant_delivery' THEN TRUE
               ELSE FALSE
             END,
             assigned_by_store = TRUE,
             updated_at = NOW()
         WHERE id = $3
         RETURNING *`,
        [Number(candidateLock.id), String(forceMerchantCourier === true ? "merchant_delivery" : assignmentType || "store_auto"), Number(orderId)]
      );
      const updatedOrder = orderUpdate.rows[0];

      await insertStatusHistoryTx(client, {
        orderId: Number(orderId),
        oldStatus: String(current.status),
        newStatus: String(current.status),
        lifecycleOld: lifecycleFromStatus(current.status),
        lifecycleNew: "DELIVERY_ASSIGNED",
        changedByUserId: requestedByUserId == null ? null : Number(requestedByUserId),
        changedByRole: "owner",
        note,
      });

      const deliveryAssignment = buildDeliveryAssignmentPresentation({
        order: {
          ...updatedOrder,
          delivery_assignment_id: assignment.id,
          delivery_assignment_row_status: assignment.status,
          delivery_assignment_assigned_at: assignment.assigned_at,
          delivery_assignment_ended_at: assignment.ended_at,
          delivery_assignment_ended_reason: assignment.ended_reason,
          delivery_image_url: candidateLock.image_url || null,
          delivery_rating: candidateLock.courier_rating,
          delivery_availability_status: candidateLock.availability_status,
          delivery_coverage_block: candidateLock.block || null,
          delivery_phone: candidateLock.phone || null,
          delivery_full_name: candidateLock.full_name || null,
        },
        openAssignmentRow: assignment,
        latestAssignmentRow: assignment,
      });

      logAssignmentOutcome({
        assignedDeliveryUserId: Number(candidateLock.id),
        assignmentId: Number(assignment.id),
        assignmentStatus: DELIVERY_ASSIGNMENT_STATUSES.ASSIGNED,
      });

      return {
        order: updatedOrder,
        driver: deliveryAssignment.driver,
        deliveryAssignment,
        alreadyAssigned: false,
        assignmentStatus: DELIVERY_ASSIGNMENT_STATUSES.ASSIGNED,
        pendingNoDriver: false,
        assignmentCreated: true,
        assignment,
      };
    } catch (error) {
      lastError = error;
      if (!retryableErrors.has(String(error?.code || ""))) {
        throw error;
      }
    }
  }

  if (!allowPending) {
    if (explicitCourierUserId != null) {
      throw lastError || new AppError("COURIER_NOT_AVAILABLE", { status: 404 });
    }
    throw lastError || new AppError("PENDING_NO_DRIVER", { status: 409 });
  }

  const pendingUpdate = await client.query(
    `UPDATE customer_order
     SET delivery_user_id = NULL,
         delivery_assignment_status = 'PENDING_NO_DRIVER',
         courier_requested_at = COALESCE(courier_requested_at, NOW()),
         assigned_by_store = TRUE,
         updated_at = NOW()
     WHERE id = $1
     RETURNING *`,
    [Number(orderId)]
  );
  const pendingOrder = pendingUpdate.rows[0] || current;
  await insertStatusHistoryTx(client, {
    orderId: Number(orderId),
    oldStatus: String(current.status),
    newStatus: String(current.status),
    lifecycleOld: lifecycleFromStatus(current.status),
    lifecycleNew: "DELIVERY_PENDING_NO_DRIVER",
    changedByUserId: requestedByUserId == null ? null : Number(requestedByUserId),
    changedByRole: "owner",
    note,
  });
  logAssignmentOutcome({
    assignedDeliveryUserId: null,
    assignmentId: null,
    assignmentStatus: DELIVERY_ASSIGNMENT_STATUSES.PENDING_NO_DRIVER,
  });
  return {
    order: pendingOrder,
    driver: null,
    deliveryAssignment: buildDeliveryAssignmentPresentation({
      order: pendingOrder,
    }),
    alreadyAssigned: false,
    assignmentStatus: DELIVERY_ASSIGNMENT_STATUSES.PENDING_NO_DRIVER,
    pendingNoDriver: true,
    assignmentCreated: false,
  };
}

async function cancelPendingAssignmentsTx(client, orderId, exceptCourierId = null) {
  await client.query(
    `UPDATE courier_assignment
     SET status = 'cancelled',
         responded_at = COALESCE(responded_at, NOW())
     WHERE order_id = $1
       AND status = 'pending'
       AND ($2::bigint IS NULL OR courier_user_id <> $2::bigint)`,
    [Number(orderId), exceptCourierId ? Number(exceptCourierId) : null]
  );
}

async function createAssignmentsTx(
  client,
  {
    orderId,
    requestedByUserId,
    assignmentType,
    courierIds,
    courierRows = null,
    ttlMinutes = DEFAULT_ASSIGNMENT_TTL_MIN,
  }
) {
  const inserted = [];
  const targets =
    Array.isArray(courierRows) && courierRows.length > 0
      ? courierRows.map((row) => ({
          courierId: Number(row.id),
          dispatchRank:
            Number.isInteger(Number(row.dispatch_rank)) && Number(row.dispatch_rank) > 0
              ? Number(row.dispatch_rank)
              : null,
          dispatchWave:
            Number.isInteger(Number(row.dispatch_wave)) && Number(row.dispatch_wave) > 0
              ? Number(row.dispatch_wave)
              : null,
        }))
      : (courierIds || []).map((courierId) => ({
          courierId: Number(courierId),
          dispatchRank: null,
          dispatchWave: null,
        }));
  for (const target of targets) {
    try {
      const r = await client.query(
        `INSERT INTO courier_assignment
          (
            order_id,
            courier_user_id,
            assignment_type,
            status,
            requested_by_user_id,
            requested_at,
            expires_at,
            dispatch_rank,
            dispatch_wave
          )
         VALUES ($1,$2,$3,'pending',$4,NOW(), NOW() + ($5::text || ' minutes')::interval,$6,$7)
         RETURNING *`,
        [
          Number(orderId),
          Number(target.courierId),
          String(assignmentType || "broadcast"),
          requestedByUserId ? Number(requestedByUserId) : null,
          Number(ttlMinutes || DEFAULT_ASSIGNMENT_TTL_MIN),
          target.dispatchRank,
          target.dispatchWave,
        ]
      );
      inserted.push(r.rows[0]);
    } catch (error) {
      if (String(error?.code || "") !== "42703") throw error;
      const legacyInsert = await client.query(
        `INSERT INTO courier_assignment
          (
            order_id,
            courier_user_id,
            assignment_type,
            status,
            requested_by_user_id,
            requested_at,
            expires_at
          )
         VALUES ($1,$2,$3,'pending',$4,NOW(), NOW() + ($5::text || ' minutes')::interval)
         RETURNING *`,
        [
          Number(orderId),
          Number(target.courierId),
          String(assignmentType || "broadcast"),
          requestedByUserId ? Number(requestedByUserId) : null,
          Number(ttlMinutes || DEFAULT_ASSIGNMENT_TTL_MIN),
        ]
      );
      inserted.push(legacyInsert.rows[0]);
    }
  }
  return inserted;
}

async function recordCourierDispatchAuditTx(
  client,
  {
    orderId,
    merchantId,
    requestedByUserId = null,
    assignmentType = "broadcast",
    customerBlock = null,
    couriers = [],
  }
) {
  const rows = Array.isArray(couriers) ? couriers : [];
  const normalizedCouriers = rows.map((row) => ({
    courierUserId: Number(row.id || 0),
    rank: Number(row.dispatch_rank || 0),
    wave: Number(row.dispatch_wave || 1),
    score: Number(row.dispatch_score || 0),
    isMerchantCourier: row.is_merchant_courier === true,
    driverType: row.driver_type || DRIVER_TYPE_APP,
    rating: Number(row.courier_rating || 0),
    avgDeliveryMinutes: Number(row.avg_delivery_minutes || 0),
    recentRejectCount: Number(row.recent_reject_count || 0),
    recentPendingCount: Number(row.recent_pending_count || 0),
    availabilityStatus: row.availability_status || null,
    debug: row.dispatch_debug || null,
  }));
  const waveSize =
    normalizedCouriers.length > 0 ? Number(rows[0]?.dispatch_wave_size || 1) : 1;
  try {
    const inserted = await client.query(
      `INSERT INTO delivery_dispatch_audit
        (
          order_id,
          merchant_id,
          requested_by_user_id,
          assignment_type,
          customer_block,
          total_candidates,
          wave_size,
          couriers_json
        )
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8::jsonb)
       RETURNING id`,
      [
        Number(orderId),
        Number(merchantId),
        requestedByUserId == null ? null : Number(requestedByUserId),
        String(assignmentType || "broadcast").slice(0, 30),
        customerBlock == null ? null : String(customerBlock || "").trim() || null,
        normalizedCouriers.length,
        Math.max(1, Number(waveSize || 1)),
        JSON.stringify(normalizedCouriers),
      ]
    );
    return Number(inserted.rows[0]?.id || 0) || null;
  } catch (error) {
    if (String(error?.code || "") === "42P01") {
      return null;
    }
    throw error;
  }
}

export async function startPreparingAndRequestCourier({
  ownerUserId,
  orderId,
  preferredCourierUserId = null,
  estimatedPrepMinutes = null,
  note = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const current = await getOwnerOrderWithMerchant(ownerUserId, orderId, client, {
      forUpdate: true,
    });
    if (!current) throw new AppError("ORDER_NOT_FOUND", { status: 404 });

    assertOwnerOrderEditable(current.status);
    const oldStatus = String(current.status || "pending");
    if (!["pending", "approved", "preparing"].includes(oldStatus)) {
      throw new AppError("ORDER_PREPARING_NOT_ALLOWED", { status: 409 });
    }

    const updatedResult = await client.query(
      `UPDATE customer_order
       SET status = 'preparing'::order_status,
           approved_at = COALESCE(approved_at, NOW()),
           preparing_started_at = COALESCE(preparing_started_at, NOW()),
           estimated_prep_minutes = COALESCE($1::int, estimated_prep_minutes),
           courier_requested_at = COALESCE(courier_requested_at, NOW()),
           assigned_by_store = CASE WHEN $2::bigint IS NULL THEN FALSE ELSE TRUE END,
           updated_at = NOW()
       WHERE id = $3
       RETURNING *`,
      [
        estimatedPrepMinutes == null ? null : Number(estimatedPrepMinutes),
        preferredCourierUserId == null ? null : Number(preferredCourierUserId),
        Number(orderId),
      ]
    );
    const updated = updatedResult.rows[0];

    await insertStatusHistoryTx(client, {
      orderId: updated.id,
      oldStatus,
      newStatus: "preparing",
      lifecycleOld: lifecycleFromStatus(oldStatus),
      lifecycleNew: "PREPARING",
      changedByUserId: ownerUserId,
      changedByRole: "owner",
      note,
    });
    const assignmentResult = await directAssignDeliveryOrderTx(client, {
      orderId: Number(orderId),
      merchantId: Number(current.merchant_id),
      requestedByUserId: Number(ownerUserId),
      customerBlock: current.customer_block || null,
      assignmentType: preferredCourierUserId ? "manual" : "store_auto",
      explicitCourierUserId:
        preferredCourierUserId == null ? null : Number(preferredCourierUserId),
      allowPending: true,
      note,
      forceMerchantCourier: null,
    });

    await client.query("COMMIT");
    return {
      order: assignmentResult.order || updated,
      merchantName: current.merchant_name,
      oldStatus,
      newStatus: "preparing",
      assignmentCreated: assignmentResult.assignmentCreated,
      assignmentStatus: assignmentResult.assignmentStatus,
      assignments: assignmentResult.assignmentCreated
        ? [assignmentResult.assignment]
        : [],
      courierRecipients:
        assignmentResult.assignmentCreated && assignmentResult.driver
          ? [assignmentResult.driver]
          : [],
      deliveryAssignment: assignmentResult.deliveryAssignment,
      dispatchAuditId: null,
      preferredOnly: Boolean(preferredCourierUserId),
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function assignCourierByStore({
  ownerUserId,
  orderId,
  courierUserId,
  assignmentMode = "manual",
  note = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const current = await getOwnerOrderWithMerchant(ownerUserId, orderId, client, {
      forUpdate: true,
    });
    if (!current) throw new AppError("ORDER_NOT_FOUND", { status: 404 });

    assertOwnerOrderEditable(current.status);
    if (!["approved", "preparing", "ready_for_delivery", "pending"].includes(String(current.status))) {
      throw new AppError("ORDER_ASSIGNMENT_NOT_ALLOWED", { status: 409 });
    }

    const assignmentResult = await directAssignDeliveryOrderTx(client, {
      orderId: Number(orderId),
      merchantId: Number(current.merchant_id),
      requestedByUserId: Number(ownerUserId),
      customerBlock: current.customer_block || null,
      assignmentType: assignmentMode || "manual",
      explicitCourierUserId: Number(courierUserId),
      allowPending: false,
      note,
      forceMerchantCourier: assignmentMode === "merchant_delivery" ? true : false,
    });

    await client.query("COMMIT");
    return {
      order: assignmentResult.order || current,
      assignment: assignmentResult.assignment || null,
      courier: assignmentResult.assignmentCreated ? assignmentResult.driver : null,
      deliveryAssignment: assignmentResult.deliveryAssignment,
      assignmentCreated: assignmentResult.assignmentCreated,
      assignmentStatus: assignmentResult.assignmentStatus,
      dispatchAuditId: null,
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function markReadyForPickupByStore({
  ownerUserId,
  orderId,
  estimatedDeliveryMinutes = null,
  note = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const current = await getOwnerOrderWithMerchant(ownerUserId, orderId, client, {
      forUpdate: true,
    });
    if (!current) throw new AppError("ORDER_NOT_FOUND", { status: 404 });

    assertOwnerOrderEditable(current.status);
    if (!["preparing", "approved"].includes(String(current.status))) {
      throw new AppError("ORDER_READY_NOT_ALLOWED", { status: 409 });
    }

    const oldStatus = String(current.status);
    const updatedResult = await client.query(
      `UPDATE customer_order
       SET status = 'ready_for_delivery'::order_status,
           preparing_started_at = COALESCE(preparing_started_at, NOW()),
           prepared_at = COALESCE(prepared_at, NOW()),
           ready_for_pickup_at = COALESCE(ready_for_pickup_at, NOW()),
           estimated_delivery_minutes = COALESCE($1::int, estimated_delivery_minutes),
           courier_requested_at = COALESCE(courier_requested_at, NOW()),
           updated_at = NOW()
       WHERE id = $2
       RETURNING *`,
      [
        estimatedDeliveryMinutes == null ? null : Number(estimatedDeliveryMinutes),
        Number(orderId),
      ]
    );
    const updated = updatedResult.rows[0];

    await insertStatusHistoryTx(client, {
      orderId: Number(orderId),
      oldStatus,
      newStatus: "ready_for_delivery",
      lifecycleOld: lifecycleFromStatus(oldStatus),
      lifecycleNew: "READY_FOR_PICKUP",
      changedByUserId: Number(ownerUserId),
      changedByRole: "owner",
      note,
    });

    const assignmentResult = await directAssignDeliveryOrderTx(client, {
      orderId: Number(orderId),
      merchantId: Number(updated.merchant_id),
      requestedByUserId: Number(ownerUserId),
      customerBlock: updated.customer_block || null,
      assignmentType: "store_auto",
      allowPending: true,
      note,
      forceMerchantCourier: null,
    });

    await client.query("COMMIT");
    return {
      order: assignmentResult.order || updated,
      merchantName: current.merchant_name,
      assignmentCreated: assignmentResult.assignmentCreated,
      assignmentStatus: assignmentResult.assignmentStatus,
      courierRecipients:
        assignmentResult.assignmentCreated && assignmentResult.driver
          ? [assignmentResult.driver]
          : [],
      deliveryAssignment: assignmentResult.deliveryAssignment,
      dispatchAuditId: null,
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

async function resolveCourierOrderForActionTx(
  client,
  { courierUserId, orderId, lock = true }
) {
  const r = await client.query(
    `SELECT
       o.*,
       m.owner_user_id,
       m.name AS merchant_name,
       m.id AS merchant_id,
       cu.full_name AS customer_name,
       cu.phone AS customer_phone,
       au.full_name AS assigned_courier_name
     FROM customer_order o
     JOIN merchant m ON m.id = o.merchant_id
     JOIN app_user cu ON cu.id = o.customer_user_id
     LEFT JOIN app_user au ON au.id = o.delivery_user_id
     WHERE o.id = $1
     ${lock ? "FOR UPDATE OF o" : ""}`,
    [Number(orderId)]
  );

  const order = r.rows[0];
  if (!order) throw new AppError("ORDER_NOT_FOUND", { status: 404 });

  const courierCheck = await client.query(
    `SELECT
       u.id,
       u.full_name,
       u.phone,
       u.block,
       COALESCE(cp.driver_type, '${DRIVER_TYPE_APP}') AS driver_type,
       cp.merchant_id AS courier_merchant_id,
       EXISTS (
         SELECT 1
         FROM merchant_delivery_agent mda
         WHERE mda.delivery_user_id = u.id
           AND mda.merchant_id = $2
           AND mda.is_active = TRUE
       ) AS is_store_driver_for_merchant
     FROM app_user u
     LEFT JOIN courier_profile cp ON cp.user_id = u.id
     WHERE u.id = $1
       AND ${DELIVERY_APPROVED_FILTER}
     LIMIT 1`,
    [Number(courierUserId), Number(order.merchant_id)]
  );
  const courier = courierCheck.rows[0];
  if (!courier) throw new AppError("COURIER_NOT_ALLOWED", { status: 403 });

  return { order, courier };
}

export async function courierAcceptAssignment({
  courierUserId,
  orderId,
  note = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const { order, courier } = await resolveCourierOrderForActionTx(client, {
      courierUserId,
      orderId,
      lock: true,
    });

    if (!["preparing", "ready_for_delivery"].includes(String(order.status))) {
      throw new AppError("ORDER_NOT_ACCEPTABLE", { status: 409 });
    }
    if (order.delivery_user_id && Number(order.delivery_user_id) !== Number(courierUserId)) {
      throw new AppError("ORDER_ALREADY_ASSIGNED", { status: 409 });
    }

    const assignment = await client.query(
      `SELECT *
       FROM courier_assignment
       WHERE order_id = $1
         AND courier_user_id = $2
         AND status = 'pending'
       ORDER BY requested_at DESC
       LIMIT 1
       FOR UPDATE`,
      [Number(orderId), Number(courierUserId)]
    );

    const hasPendingAssignment = !!assignment.rows[0];
    const canClaimByBlock =
      !hasPendingAssignment &&
      !order.delivery_user_id &&
      String(order.customer_block || "").trim().toUpperCase() ===
        String(courier.block || "").trim().toUpperCase();

    if (!hasPendingAssignment && !canClaimByBlock) {
      throw new AppError("ASSIGNMENT_NOT_AVAILABLE", { status: 409 });
    }

    let acceptedAssignmentId = null;

    if (hasPendingAssignment) {
      const accepted = await client.query(
        `UPDATE courier_assignment
         SET status = 'accepted',
             responded_at = NOW(),
             response_note = COALESCE($2, response_note)
         WHERE id = $1`,
        [Number(assignment.rows[0].id), note || null]
      );
      acceptedAssignmentId = Number(
        accepted.rows?.[0]?.id || assignment.rows[0]?.id || 0
      ) || Number(assignment.rows[0]?.id || 0) || null;
    } else {
      await createAssignmentsTx(client, {
        orderId: Number(orderId),
        requestedByUserId: null,
        assignmentType: "broadcast_claim",
        courierIds: [Number(courierUserId)],
      });
      const accepted = await client.query(
        `UPDATE courier_assignment
         SET status = 'accepted',
             responded_at = NOW(),
             response_note = COALESCE($2, response_note)
         WHERE order_id = $1
           AND courier_user_id = $3
           AND status = 'pending'
         RETURNING id`,
        [Number(orderId), note || null, Number(courierUserId)]
      );
      acceptedAssignmentId = Number(accepted.rows?.[0]?.id || 0) || null;
    }

    await client.query(
      `UPDATE courier_assignment
       SET status = 'cancelled',
           responded_at = COALESCE(responded_at, NOW())
       WHERE order_id = $1
         AND status = 'pending'
         AND ($2::bigint IS NULL OR id <> $2::bigint)`,
      [Number(orderId), acceptedAssignmentId]
    );

    const courierDriverType = normalizeCourierDriverType(courier.driver_type);
    const isMerchantCourier =
      courierDriverType === DRIVER_TYPE_STORE &&
      courier.is_store_driver_for_merchant === true;

    if (courierDriverType === DRIVER_TYPE_STORE && !isMerchantCourier) {
      throw new AppError("COURIER_NOT_ALLOWED", { status: 403 });
    }

    await ensureCourierProfileTx(client, {
      userId: Number(courierUserId),
      driverType: courierDriverType,
      merchantId: isMerchantCourier ? Number(order.merchant_id) : null,
      merchantIdSet: true,
      coverageBlock: courier.block || order.customer_block || null,
    });

    await client.query(
      `UPDATE customer_order
       SET delivery_user_id = $1,
           courier_assigned_at = COALESCE(courier_assigned_at, NOW()),
           courier_source = CASE WHEN $2::boolean THEN 'merchant' ELSE 'app' END,
           is_merchant_delivery = $2,
           updated_at = NOW()
       WHERE id = $3`,
      [Number(courierUserId), isMerchantCourier, Number(orderId)]
    );

    await insertStatusHistoryTx(client, {
      orderId: Number(orderId),
      oldStatus: String(order.status),
      newStatus: String(order.status),
      lifecycleOld: lifecycleFromStatus(order.status),
      lifecycleNew: "COURIER_ASSIGNED",
      changedByUserId: Number(courierUserId),
      changedByRole: "delivery",
      note,
    });

    await client.query("COMMIT");
    return { order, courier, isMerchantCourier };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function courierRejectAssignment({
  courierUserId,
  orderId,
  note = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const assignment = await client.query(
      `UPDATE courier_assignment
       SET status = 'rejected',
           responded_at = NOW(),
           response_note = COALESCE($3, response_note)
       WHERE order_id = $1
         AND courier_user_id = $2
         AND status = 'pending'
       RETURNING *`,
      [Number(orderId), Number(courierUserId), note || null]
    );
    if (!assignment.rows[0]) {
      throw new AppError("ASSIGNMENT_NOT_AVAILABLE", { status: 404 });
    }

    const orderRow = await client.query(
      `SELECT o.id, o.merchant_id, m.owner_user_id, m.name AS merchant_name
       FROM customer_order o
       JOIN merchant m ON m.id = o.merchant_id
       WHERE o.id = $1`,
      [Number(orderId)]
    );

    const pendingLeft = await client.query(
      `SELECT COUNT(*)::int AS pending_count
       FROM courier_assignment
       WHERE order_id = $1
         AND status = 'pending'`,
      [Number(orderId)]
    );

    await client.query("COMMIT");
    return {
      order: orderRow.rows[0] || null,
      pendingCount: Number(pendingLeft.rows[0]?.pending_count || 0),
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

function nowIsoDate() {
  return new Date().toISOString();
}

function toIsoOrNull(value) {
  if (!value) return null;
  const dt = new Date(value);
  if (Number.isNaN(dt.getTime())) return null;
  return dt.toISOString();
}

function parseWindow({ period = "day", from = null, to = null } = {}) {
  const normalizedPeriod = String(period || "day").trim().toLowerCase();
  const validPeriod = [
    "all",
    "day",
    "yesterday",
    "week",
    "month",
    "year",
    "custom",
  ].includes(normalizedPeriod)
    ? normalizedPeriod
    : "day";
  const now = Date.now();
  const start =
    validPeriod === "custom"
      ? toIsoOrNull(from)
      : validPeriod === "all"
      ? toIsoOrNull(new Date("1970-01-01T00:00:00.000Z"))
      : validPeriod === "year"
      ? toIsoOrNull(new Date(now - 365 * 24 * 60 * 60 * 1000))
      : validPeriod === "yesterday"
      ? toIsoOrNull(new Date(now - 2 * 24 * 60 * 60 * 1000))
      : validPeriod === "week"
      ? toIsoOrNull(new Date(now - 7 * 24 * 60 * 60 * 1000))
      : validPeriod === "month"
      ? toIsoOrNull(new Date(now - 30 * 24 * 60 * 60 * 1000))
      : toIsoOrNull(new Date(now - 24 * 60 * 60 * 1000));
  const end =
    validPeriod === "custom"
      ? toIsoOrNull(to)
      : validPeriod === "yesterday"
      ? toIsoOrNull(new Date(now - 24 * 60 * 60 * 1000))
      : nowIsoDate();
  return { period: validPeriod, start, end };
}

function sanitizeLimit(value, fallback = 120, max = 500) {
  const n = Number(value);
  if (!Number.isFinite(n) || n <= 0) return fallback;
  return Math.max(1, Math.min(max, Math.floor(n)));
}

function sanitizeOffset(value, fallback = 0) {
  const n = Number(value);
  if (!Number.isFinite(n) || n < 0) return fallback;
  return Math.max(0, Math.floor(n));
}

function sanitizeSearch(value) {
  const text = String(value || "").trim();
  return text.length ? text.slice(0, 140) : null;
}

async function getMerchantByOwnerTx(client, ownerUserId) {
  const r = await client.query(
    `SELECT id, owner_user_id, name, type, phone
     FROM merchant
     WHERE owner_user_id = $1
     LIMIT 1`,
    [Number(ownerUserId)]
  );
  return r.rows[0] || null;
}

async function getBackofficeUserIdsTx(client) {
  const r = await client.query(
    `SELECT id
     FROM app_user
     WHERE role IN ('admin','deputy_admin')
        OR is_super_admin = TRUE`
  );
  return r.rows.map((row) => Number(row.id));
}

async function getMerchantLedgerBalanceTx(client, merchantId) {
  const r = await client.query(
    `SELECT COALESCE(
       SUM(
         CASE
           WHEN direction = 'debit' THEN amount
           WHEN direction = 'credit' THEN -amount
           ELSE 0
         END
       ),
       0
     )::numeric AS balance
     FROM merchant_receivables_ledger
     WHERE merchant_id = $1`,
    [Number(merchantId)]
  );
  return toNumber(r.rows[0]?.balance, 0);
}

async function appendMerchantLedgerEntryTx(
  client,
  {
    merchantId,
    orderId = null,
    entryType,
    amount,
    direction,
    referenceType = null,
    referenceId = null,
    note = null,
  }
) {
  const absoluteAmount = round2(Math.abs(toNumber(amount, 0)));
  if (absoluteAmount <= 0) return null;
  const safeDirection = direction === "credit" ? "credit" : "debit";
  const currentBalance = await getMerchantLedgerBalanceTx(client, Number(merchantId));
  const signedDelta = safeDirection === "debit" ? absoluteAmount : -absoluteAmount;
  const nextBalance = round2(currentBalance + signedDelta);
  const inserted = await client.query(
    `INSERT INTO merchant_receivables_ledger
      (
        merchant_id,
        order_id,
        entry_type,
        amount,
        direction,
        balance_after,
        reference_type,
        reference_id,
        note
      )
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
     RETURNING *`,
    [
      Number(merchantId),
      orderId == null ? null : Number(orderId),
      String(entryType || "adjustment"),
      absoluteAmount,
      safeDirection,
      nextBalance,
      referenceType,
      referenceId == null ? null : Number(referenceId),
      note,
    ]
  );
  return inserted.rows[0] || null;
}

async function getMerchantAppPayablesBalanceTx(client, merchantId) {
  const r = await client.query(
    `SELECT COALESCE(
       SUM(
         CASE
           WHEN direction = 'debit' THEN amount
           WHEN direction = 'credit' THEN -amount
           ELSE 0
         END
       ),
       0
     )::numeric AS balance
     FROM merchant_app_payables_ledger
     WHERE merchant_id = $1`,
    [Number(merchantId)]
  );
  return toNumber(r.rows[0]?.balance, 0);
}

async function appendMerchantAppPayablesLedgerEntryTx(
  client,
  {
    merchantId,
    orderId = null,
    entryType,
    amount,
    direction,
    referenceType = null,
    referenceId = null,
    note = null,
  }
) {
  const absoluteAmount = round2(Math.abs(toNumber(amount, 0)));
  if (absoluteAmount <= 0) return null;
  const safeDirection = direction === "credit" ? "credit" : "debit";
  const currentBalance = await getMerchantAppPayablesBalanceTx(client, Number(merchantId));
  const signedDelta = safeDirection === "debit" ? absoluteAmount : -absoluteAmount;
  const nextBalance = round2(currentBalance + signedDelta);
  const isAutoOrderAccrual =
    String(referenceType || "") === "order_auto_accrual" &&
    String(entryType || "") === "order_share" &&
    safeDirection === "debit" &&
    referenceId != null;
  let inserted;
  if (isAutoOrderAccrual) {
    try {
      inserted = await client.query(
        `INSERT INTO merchant_app_payables_ledger
          (
            merchant_id,
            order_id,
            entry_type,
            amount,
            direction,
            balance_after,
            reference_type,
            reference_id,
            note
          )
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
         ON CONFLICT (merchant_id, reference_id)
         WHERE reference_type = 'order_auto_accrual'
           AND entry_type = 'order_share'
           AND direction = 'debit'
         DO NOTHING
         RETURNING *`,
        [
          Number(merchantId),
          orderId == null ? null : Number(orderId),
          String(entryType || "adjustment"),
          absoluteAmount,
          safeDirection,
          nextBalance,
          referenceType,
          referenceId == null ? null : Number(referenceId),
          note,
        ]
      );
    } catch (error) {
      if (error?.code !== "42P10") throw error;
      inserted = await client.query(
        `INSERT INTO merchant_app_payables_ledger
          (
            merchant_id,
            order_id,
            entry_type,
            amount,
            direction,
            balance_after,
            reference_type,
            reference_id,
            note
          )
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
         ON CONFLICT DO NOTHING
         RETURNING *`,
        [
          Number(merchantId),
          orderId == null ? null : Number(orderId),
          String(entryType || "adjustment"),
          absoluteAmount,
          safeDirection,
          nextBalance,
          referenceType,
          referenceId == null ? null : Number(referenceId),
          note,
        ]
      );
    }
  } else {
    inserted = await client.query(
        `INSERT INTO merchant_app_payables_ledger
          (
            merchant_id,
            order_id,
            entry_type,
            amount,
            direction,
            balance_after,
            reference_type,
            reference_id,
            note
          )
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
         RETURNING *`,
        [
          Number(merchantId),
          orderId == null ? null : Number(orderId),
          String(entryType || "adjustment"),
          absoluteAmount,
          safeDirection,
          nextBalance,
          referenceType,
          referenceId == null ? null : Number(referenceId),
          note,
        ]
      );
  }
  if (inserted.rows[0]) return inserted.rows[0];

  if (isAutoOrderAccrual) {
    const existing = await client.query(
      `SELECT *
       FROM merchant_app_payables_ledger
       WHERE merchant_id = $1
         AND reference_type = 'order_auto_accrual'
         AND reference_id = $2
         AND entry_type = 'order_share'
         AND direction = 'debit'
       ORDER BY id DESC
       LIMIT 1`,
      [Number(merchantId), Number(referenceId)]
    );
    return existing.rows[0] || null;
  }

  return null;
}

async function insertPaymentRequestStatusHistoryTx(
  client,
  {
    paymentRequestId,
    oldStatus = null,
    newStatus,
    changedByUserId = null,
    changedByRole = null,
    note = null,
    metadata = null,
  }
) {
  await client.query(
    `INSERT INTO merchant_payment_request_status_history
      (
        payment_request_id,
        old_status,
        new_status,
        changed_by_user_id,
        changed_by_role,
        note,
        metadata_json
      )
     VALUES ($1,$2,$3,$4,$5,$6,$7::jsonb)`,
    [
      Number(paymentRequestId),
      oldStatus,
      String(newStatus || ""),
      changedByUserId ? Number(changedByUserId) : null,
      changedByRole || null,
      note || null,
      JSON.stringify(metadata && typeof metadata === "object" ? metadata : {}),
    ]
  );
}

async function updatePaymentRequestStatusTx(
  client,
  {
    paymentRequestId,
    fromStatuses = [],
    toStatus,
    actorUserId = null,
    actorRole = null,
    note = null,
    metadata = null,
    patch = {},
    lockRequest = false,
  }
) {
  const requestResult = await client.query(
    `SELECT *
     FROM merchant_payment_request
     WHERE id = $1
     FOR UPDATE`,
    [Number(paymentRequestId)]
  );
  const row = requestResult.rows[0];
  if (!row) throw new AppError("PAYMENT_REQUEST_NOT_FOUND", { status: 404 });
  if (row.is_locked === true || LOCKED_REQUEST_STATUSES.has(String(row.status || "").toLowerCase())) {
    throw new AppError("PAYMENT_REQUEST_LOCKED", { status: 409 });
  }

  const oldStatus = normalizeRequestStatus(row.status);
  const allowed = (fromStatuses || []).map((s) => String(s || "").toLowerCase());
  if (allowed.length && !allowed.includes(oldStatus)) {
    throw new AppError("PAYMENT_REQUEST_INVALID_STATUS_TRANSITION", {
      status: 409,
      details: { oldStatus, required: allowed, targetStatus: toStatus },
    });
  }

  const updatePayload = {
    status: normalizeRequestStatus(toStatus),
    updated_by_user_id: actorUserId ? Number(actorUserId) : null,
    ...patch,
  };
  if (lockRequest) {
    updatePayload.is_locked = true;
    updatePayload.locked_at = "NOW()";
  }

  const fields = [];
  const values = [];
  let i = 1;
  for (const [key, value] of Object.entries(updatePayload)) {
    if (value === undefined) continue;
    if (!PAYMENT_REQUEST_PATCHABLE_COLUMNS.has(key)) continue;
    if (value === "NOW()") {
      fields.push(`${key} = NOW()`);
      continue;
    }
    fields.push(`${key} = $${i}`);
    values.push(value);
    i += 1;
  }
  values.push(Number(paymentRequestId));

  const updated = await client.query(
    `UPDATE merchant_payment_request
     SET ${fields.join(",\n         ")}
     WHERE id = $${i}
     RETURNING *`,
    values
  );
  const next = updated.rows[0];

  await insertPaymentRequestStatusHistoryTx(client, {
    paymentRequestId: Number(paymentRequestId),
    oldStatus,
    newStatus: next.status,
    changedByUserId: actorUserId,
    changedByRole: actorRole,
    note,
    metadata,
  });

  return next;
}

function calculateServiceFee(order, profile) {
  return round2(buildOrderFinancialSnapshot(order, profile).serviceFeeAmount);
}

function calculateCommission(order, profile) {
  return round2(buildOrderFinancialSnapshot(order, profile).commissionAmount);
}

function calculateDeliveryDue(order, profile) {
  return round2(buildOrderFinancialSnapshot(order, profile).appDeliveryFeeAmount);
}

function calculateAppPayableDue(order, profile) {
  return round2(buildOrderFinancialSnapshot(order, profile).storeNetAmount);
}

function computeOrderFinancialSnapshot(order, profile = {}) {
  return buildOrderFinancialSnapshot(order, profile);
}

async function resolveMerchantBillingProfileTx(client, merchantId) {
  const result = await client.query(
    `SELECT *
     FROM merchant_billing_profile
     WHERE merchant_id = $1
     LIMIT 1`,
    [Number(merchantId)]
  );
  return normalizeMerchantBillingProfile(
    result.rows[0] || { merchant_id: Number(merchantId) }
  );
}

async function ensureOrderFinancialSnapshotTx(client, orderRow, profile = null) {
  if (!orderRow?.id || !orderRow?.merchant_id) {
    return computeOrderFinancialSnapshot(orderRow || {}, profile || {});
  }

  const existingSnapshot =
    orderRow.financial_config_snapshot_json &&
    typeof orderRow.financial_config_snapshot_json === "object"
      ? orderRow.financial_config_snapshot_json
      : null;
  if (existingSnapshot?.appReceivableAmount != null) {
    const recomputed = computeOrderFinancialSnapshot(orderRow, existingSnapshot);
    const snapshotChanged =
      String(existingSnapshot.courierSource || "") !== String(recomputed.courierSource || "") ||
      Number(existingSnapshot.appDeliveryFeeAmount || 0) !== Number(recomputed.appDeliveryFeeAmount || 0) ||
      Number(existingSnapshot.storeDeliveryFeeAmount || 0) !== Number(recomputed.storeDeliveryFeeAmount || 0) ||
      Number(existingSnapshot.appReceivableAmount || 0) !== Number(recomputed.appReceivableAmount || 0) ||
      Number(existingSnapshot.storeNetAmount || 0) !== Number(recomputed.storeNetAmount || 0);
    const needsBackfill =
      orderRow.store_net_received_amount == null ||
      orderRow.app_due_from_delivery == null ||
      orderRow.store_cash_confirmed == null ||
      orderRow.amount_received_actual == null ||
      orderRow.difference_amount == null ||
      orderRow.difference_reason == null ||
      orderRow.settlement_status == null;

    if (!snapshotChanged && !needsBackfill) {
      return recomputed;
    }

    const refreshed = await client.query(
      `UPDATE customer_order
       SET store_net_received_amount = $2,
           app_due_from_delivery = $3,
           store_cash_confirmed = $4,
           store_cash_confirmed_at = $5::timestamptz,
           store_cash_confirmed_by_user_id = $6,
           amount_received_actual = $7,
           difference_amount = $8,
           difference_reason = $9,
           settlement_status = $10,
           financial_config_snapshot_json = $11::jsonb,
           updated_at = NOW()
       WHERE id = $1
       RETURNING *`,
      [
        Number(orderRow.id),
        recomputed.storeNetReceivedAmount,
        recomputed.appDueFromDelivery,
        recomputed.storeCashConfirmed === true,
        recomputed.storeCashConfirmedAt || null,
        recomputed.storeCashConfirmedByUserId,
        recomputed.amountReceivedActual,
        recomputed.differenceAmount,
        recomputed.differenceReason || null,
        recomputed.settlementStatus || "pending_store_confirmation",
        JSON.stringify(recomputed),
      ]
    );
    const next = refreshed.rows[0] || orderRow;
    return computeOrderFinancialSnapshot(next, recomputed);
  }

  const resolvedProfile =
    profile || (await resolveMerchantBillingProfileTx(client, Number(orderRow.merchant_id)));
  const snapshot = computeOrderFinancialSnapshot(orderRow, resolvedProfile);

  const updated = await client.query(
    `UPDATE customer_order
     SET service_fee = CASE
           WHEN COALESCE(service_fee, 0) <= 0 THEN $2
           ELSE service_fee
         END,
         store_net_received_amount = $3,
         app_due_from_delivery = $4,
         store_cash_confirmed = $5,
         store_cash_confirmed_at = $6::timestamptz,
         store_cash_confirmed_by_user_id = $7,
         amount_received_actual = $8,
         difference_amount = $9,
         difference_reason = $10,
         settlement_status = $11,
         financial_profile_version = $12,
         financial_config_snapshot_json = $13::jsonb
     WHERE id = $1
     RETURNING *`,
    [
      Number(orderRow.id),
      snapshot.serviceFeeAmount,
      snapshot.storeNetReceivedAmount,
      snapshot.appDueFromDelivery,
      snapshot.storeCashConfirmed === true,
      snapshot.storeCashConfirmedAt || null,
      snapshot.storeCashConfirmedByUserId,
      snapshot.amountReceivedActual,
      snapshot.differenceAmount,
      snapshot.differenceReason || null,
      snapshot.settlementStatus || "pending_store_confirmation",
      snapshot.profileVersion,
      JSON.stringify(snapshot),
    ]
  );
  const next = updated.rows[0] || orderRow;
  return computeOrderFinancialSnapshot(next, snapshot);
}

async function getMerchantReceivableInvoicePaidAmountTx(client, receivableInvoiceId) {
  const result = await client.query(
    `SELECT COALESCE(SUM(allocated_amount), 0)::numeric AS total_paid
     FROM merchant_payment_invoice_allocation
     WHERE receivable_invoice_id = $1`,
    [Number(receivableInvoiceId)]
  );
  return round2(toNumber(result.rows[0]?.total_paid, 0));
}

async function syncReceivableInvoiceStatusTx(client, receivableInvoiceId) {
  const current = await client.query(
    `SELECT *
     FROM merchant_receivable_invoice
     WHERE id = $1
     LIMIT 1`,
    [Number(receivableInvoiceId)]
  );
  const row = current.rows[0];
  if (!row) return null;
  const paidAmount = await getMerchantReceivableInvoicePaidAmountTx(
    client,
    Number(receivableInvoiceId)
  );
  const appReceivableAmount = round2(toNumber(row.app_receivable_amount, 0));
  const outstandingAmount = round2(Math.max(appReceivableAmount - paidAmount, 0));
  const invoiceStatus =
    outstandingAmount <= 0.009
      ? "paid"
      : paidAmount > 0
      ? "partially_paid"
      : "unpaid";
  const updated = await client.query(
    `UPDATE merchant_receivable_invoice
     SET paid_amount = $2,
         outstanding_amount = $3,
         invoice_status = $4,
         updated_at = NOW()
     WHERE id = $1
     RETURNING *`,
    [
      Number(receivableInvoiceId),
      paidAmount,
      outstandingAmount,
      invoiceStatus,
    ]
  );
  return updated.rows[0] || null;
}

async function upsertMerchantReceivableInvoiceTx(client, orderRow, profile = null) {
  if (!orderRow?.merchant_id || !orderRow?.id) return null;
  const status = String(orderRow.status || "").toLowerCase();
  if (!["delivered", "completed"].includes(status)) return null;
  const snapshot = await ensureOrderFinancialSnapshotTx(client, orderRow, profile);
  const current = await client.query(
    `SELECT id
     FROM merchant_receivable_invoice
     WHERE order_id = $1
     LIMIT 1`,
    [Number(orderRow.id)]
  );
  const invoiceNumber = `INV-${Number(orderRow.id)}`;
  if (current.rows[0]) {
    const updated = await client.query(
      `UPDATE merchant_receivable_invoice
       SET merchant_id = $2,
           invoice_number = $3,
           issued_at = $4::timestamptz,
           order_status = $5,
           subtotal = $6,
           commission_amount = $7,
           service_fee_amount = $8,
           app_delivery_fee_amount = $9,
           store_delivery_fee_amount = $10,
           app_receivable_amount = $11,
           store_net_amount = $12,
           store_net_received_amount = $13,
           app_due_from_delivery = $14,
           difference_amount = $15,
           difference_reason = $16,
           updated_at = NOW()
       WHERE id = $1
       RETURNING *`,
      [
        Number(current.rows[0].id),
        Number(orderRow.merchant_id),
        invoiceNumber,
        snapshot.issuedAt,
        status,
        snapshot.subtotal,
        snapshot.commissionAmount,
        snapshot.serviceFeeAmount,
        snapshot.appDeliveryFeeAmount,
        snapshot.storeDeliveryFeeAmount,
        snapshot.appReceivableAmount,
        snapshot.storeNetAmount,
        snapshot.storeNetReceivedAmount,
        snapshot.appDueFromDelivery,
        snapshot.differenceAmount ?? 0,
        snapshot.differenceReason ?? null,
      ]
    );
    return syncReceivableInvoiceStatusTx(client, Number(updated.rows[0].id));
  }
  const inserted = await client.query(
    `INSERT INTO merchant_receivable_invoice
      (
        merchant_id,
        order_id,
        invoice_number,
        issued_at,
        order_status,
        subtotal,
        commission_amount,
        service_fee_amount,
        app_delivery_fee_amount,
        store_delivery_fee_amount,
        app_receivable_amount,
        store_net_amount,
        store_net_received_amount,
        app_due_from_delivery,
        difference_amount,
        difference_reason,
        paid_amount,
        outstanding_amount,
        invoice_status,
        created_at,
        updated_at
      )
     VALUES ($1,$2,$3,$4::timestamptz,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,0,$11,'unpaid',NOW(),NOW())
     RETURNING *`,
    [
      Number(orderRow.merchant_id),
      Number(orderRow.id),
      invoiceNumber,
      snapshot.issuedAt,
      status,
      snapshot.subtotal,
      snapshot.commissionAmount,
      snapshot.serviceFeeAmount,
      snapshot.appDeliveryFeeAmount,
      snapshot.storeDeliveryFeeAmount,
      snapshot.appReceivableAmount,
      snapshot.storeNetAmount,
      snapshot.storeNetReceivedAmount,
      snapshot.appDueFromDelivery,
      snapshot.differenceAmount ?? 0,
      snapshot.differenceReason ?? null,
    ]
  );
  return inserted.rows[0] || null;
}

async function listMerchantReceivableInvoicesTx(
  client,
  merchantId,
  {
    invoiceIds = null,
    onlyOpen = false,
    limit = 500,
    offset = 0,
    window = null,
  } = {}
) {
  const params = [Number(merchantId)];
  const where = [`merchant_id = $1`];
  if (Array.isArray(invoiceIds) && invoiceIds.length > 0) {
    params.push(invoiceIds.map((id) => Number(id)).filter((id) => id > 0));
    where.push(`id = ANY($${params.length}::bigint[])`);
  }
  if (onlyOpen) {
    where.push(`outstanding_amount > 0.009`);
  }
  if (window?.start) {
    params.push(window.start);
    where.push(`issued_at >= $${params.length}::timestamptz`);
  }
  if (window?.end) {
    params.push(window.end);
    where.push(`issued_at <= $${params.length}::timestamptz`);
  }
  params.push(sanitizeLimit(limit, 500, 2000));
  const limitParam = params.length;
  params.push(sanitizeOffset(offset, 0));
  const offsetParam = params.length;
  const result = await client.query(
    `SELECT *
     FROM merchant_receivable_invoice
     WHERE ${where.join(" AND ")}
     ORDER BY issued_at ASC, id ASC
     LIMIT $${limitParam} OFFSET $${offsetParam}`,
    params
  );
  return result.rows.map((row) => ({
    ...row,
    subtotal: round2(toNumber(row.subtotal, 0)),
    commission_amount: round2(toNumber(row.commission_amount, 0)),
    service_fee_amount: round2(toNumber(row.service_fee_amount, 0)),
    app_delivery_fee_amount: round2(toNumber(row.app_delivery_fee_amount, 0)),
    store_delivery_fee_amount: round2(toNumber(row.store_delivery_fee_amount, 0)),
    app_receivable_amount: round2(toNumber(row.app_receivable_amount, 0)),
    store_net_amount: round2(toNumber(row.store_net_amount, 0)),
    store_net_received_amount: round2(
      toNumber(row.store_net_received_amount, row.store_net_amount || 0)
    ),
    app_due_from_delivery: round2(
      toNumber(row.app_due_from_delivery, row.app_receivable_amount || 0)
    ),
    difference_amount: round2(toNumber(row.difference_amount, 0)),
    difference_reason: row.difference_reason || null,
    paid_amount: round2(toNumber(row.paid_amount, 0)),
    outstanding_amount: round2(toNumber(row.outstanding_amount, 0)),
  }));
}

function summarizeInvoiceRows(invoiceRows = []) {
  const summary = {
    invoicesCount: invoiceRows.length,
    subtotal: 0,
    commissionAmount: 0,
    serviceFeeAmount: 0,
    appDeliveryFeeAmount: 0,
    storeDeliveryFeeAmount: 0,
    appReceivableAmount: 0,
    storeNetAmount: 0,
    storeNetReceivedAmount: 0,
    appDueFromDelivery: 0,
    differenceAmount: 0,
    oldestIssuedAt: invoiceRows[0]?.issued_at || null,
    latestIssuedAt: invoiceRows[invoiceRows.length - 1]?.issued_at || null,
  };
  for (const row of invoiceRows) {
    summary.subtotal += round2(toNumber(row.subtotal, 0));
    summary.commissionAmount += round2(toNumber(row.commission_amount, 0));
    summary.serviceFeeAmount += round2(toNumber(row.service_fee_amount, 0));
    summary.appDeliveryFeeAmount += round2(
      toNumber(row.app_delivery_fee_amount, 0)
    );
    summary.storeDeliveryFeeAmount += round2(
      toNumber(row.store_delivery_fee_amount, 0)
    );
    summary.appReceivableAmount += round2(toNumber(row.outstanding_amount, 0));
    summary.storeNetAmount += round2(toNumber(row.store_net_amount, 0));
    summary.storeNetReceivedAmount += round2(
      toNumber(row.store_net_received_amount, row.store_net_amount || 0)
    );
    summary.appDueFromDelivery += round2(
      toNumber(row.app_due_from_delivery, row.app_receivable_amount || 0)
    );
    summary.differenceAmount += round2(toNumber(row.difference_amount, 0));
  }
  return {
    invoicesCount: summary.invoicesCount,
    subtotal: round2(summary.subtotal),
    commissionAmount: round2(summary.commissionAmount),
    serviceFeeAmount: round2(summary.serviceFeeAmount),
    appDeliveryFeeAmount: round2(summary.appDeliveryFeeAmount),
    storeDeliveryFeeAmount: round2(summary.storeDeliveryFeeAmount),
    appReceivableAmount: round2(summary.appReceivableAmount),
    storeNetAmount: round2(summary.storeNetAmount),
    storeNetReceivedAmount: round2(summary.storeNetReceivedAmount),
    appDueFromDelivery: round2(summary.appDueFromDelivery),
    differenceAmount: round2(summary.differenceAmount),
    oldestIssuedAt: summary.oldestIssuedAt,
    latestIssuedAt: summary.latestIssuedAt,
  };
}

function formatInvoiceSelectionPreviewMessage({
  exactMatch,
  targetAmount,
  finalizedAmount,
  nearestLowerAmount,
  nearestHigherAmount,
}) {
  if (exactMatch) {
    return "Exact invoice match found.";
  }
  if (nearestHigherAmount > 0 && nearestLowerAmount > 0) {
    return `Requested ${round2(targetAmount)} does not exactly match open invoices. Choose ${round2(
      nearestLowerAmount
    )} or ${round2(nearestHigherAmount)}.`;
  }
  if (nearestHigherAmount > 0) {
    return `Requested ${round2(targetAmount)} was adjusted to ${round2(
      finalizedAmount || nearestHigherAmount
    )} to match the oldest eligible invoices.`;
  }
  if (nearestLowerAmount > 0) {
    return `Nearest available amount is ${round2(nearestLowerAmount)}.`;
  }
  return "No open invoices match the requested payment.";
}

async function buildMerchantPaymentSelectionPreviewTx(
  client,
  {
    merchantId,
    selectionMode,
    selectedInvoiceIds = [],
    targetAmount = null,
    confirmedAdjustedAmount = null,
    window = null,
  }
) {
  const normalizedSelectionMode = normalizeSelectionMode(selectionMode);
  const openInvoices = await listMerchantReceivableInvoicesTx(client, merchantId, {
    onlyOpen: true,
    limit: 3000,
    window,
  });
  if (openInvoices.length === 0) {
    throw new AppError("NO_OPEN_RECEIVABLE_INVOICES", { status: 400 });
  }

  let selected = [];
  let exactMatch = false;
  let requiresAmountConfirmation = false;
  let requestedAmount = targetAmount == null ? null : round2(toNumber(targetAmount, 0));
  let finalizedAmount = 0;
  let nearestLowerAmount = 0;
  let nearestHigherAmount = 0;
  let adjustmentDirection = null;

  if (normalizedSelectionMode === SELECTION_MODE_ALL_INVOICES) {
    selected = [...openInvoices];
    finalizedAmount = round2(
      selected.reduce(
        (sum, row) => sum + toNumber(row.outstanding_amount, 0),
        0
      )
    );
    exactMatch = true;
  } else if (normalizedSelectionMode === SELECTION_MODE_MANUAL) {
    const idSet = new Set(
      (selectedInvoiceIds || []).map((id) => Number(id)).filter((id) => id > 0)
    );
    selected = openInvoices.filter((row) => idSet.has(Number(row.id)));
    if (selected.length !== idSet.size || selected.length === 0) {
      throw new AppError("INVALID_SELECTED_RECEIVABLE_INVOICES", {
        status: 400,
        details: {
          selectedInvoiceIds,
          openInvoiceIds: openInvoices.map((row) => Number(row.id)),
        },
      });
    }
    finalizedAmount = round2(
      selected.reduce(
        (sum, row) => sum + toNumber(row.outstanding_amount, 0),
        0
      )
    );
    exactMatch = true;
  } else {
    if (!(requestedAmount > 0)) {
      throw new AppError("INVALID_TARGET_AMOUNT", { status: 400 });
    }
    const prefixSelection = [];
    let running = 0;
    for (const invoice of openInvoices) {
      const invoiceOutstanding = round2(toNumber(invoice.outstanding_amount, 0));
      const lowerRows = [...prefixSelection];
      const lowerAmount = round2(running);
      prefixSelection.push(invoice);
      running = round2(running + invoiceOutstanding);
      if (running === requestedAmount) {
        selected = [...prefixSelection];
        exactMatch = true;
        finalizedAmount = running;
        nearestLowerAmount = lowerAmount;
        nearestHigherAmount = running;
        break;
      }
      if (running > requestedAmount) {
        nearestLowerAmount = lowerAmount;
        nearestHigherAmount = running;
        if (confirmedAdjustedAmount != null) {
          const confirmed = round2(toNumber(confirmedAdjustedAmount, 0));
          if (Math.abs(confirmed - running) <= 0.009) {
            selected = [...prefixSelection];
            finalizedAmount = running;
            adjustmentDirection = "higher";
            break;
          }
          if (Math.abs(confirmed - lowerAmount) <= 0.009 && lowerAmount > 0) {
            selected = [...lowerRows];
            finalizedAmount = lowerAmount;
            adjustmentDirection = "lower";
            break;
          }
        }
        requiresAmountConfirmation = true;
        break;
      }
    }
    if (!exactMatch && selected.length == 0 && running <= requestedAmount) {
      nearestLowerAmount = running;
      if (confirmedAdjustedAmount != null) {
        const confirmed = round2(toNumber(confirmedAdjustedAmount, 0));
        if (Math.abs(confirmed - running) <= 0.009 && running > 0) {
          selected = [...openInvoices];
          finalizedAmount = running;
          adjustmentDirection = "lower";
        }
      }
      if (selected.length === 0) {
        requiresAmountConfirmation = true;
      }
    }
    if (!exactMatch && selected.length === 0 && !requiresAmountConfirmation) {
      requiresAmountConfirmation = true;
    }
  }

  const summary = summarizeInvoiceRows(selected);
  if (finalizedAmount <= 0) {
    finalizedAmount = summary.appReceivableAmount;
  }

  return {
    selectionMode: normalizedSelectionMode,
    requestedAmount,
    exactMatch,
    requiresAmountConfirmation,
    confirmedAdjustedAmount:
        confirmedAdjustedAmount == null ? null : round2(toNumber(confirmedAdjustedAmount, 0)),
    finalizedAmount: round2(finalizedAmount),
    nearestLowerAmount: round2(nearestLowerAmount),
    nearestHigherAmount: round2(nearestHigherAmount),
    adjustmentDirection,
    message: formatInvoiceSelectionPreviewMessage({
      exactMatch,
      targetAmount: requestedAmount,
      finalizedAmount,
      nearestLowerAmount,
      nearestHigherAmount,
    }),
    selectedInvoiceIds: selected.map((row) => Number(row.id)),
    invoices: selected,
    summary,
  };
}

async function insertMerchantPaymentInvoiceAllocationsTx(
  client,
  {
    paymentRequestId,
    merchantId,
    invoices,
    allowPartialLastInvoice = false,
    requestedAmount = null,
  }
) {
  let remaining = round2(
    requestedAmount == null
      ? invoices.reduce(
          (sum, row) => sum + toNumber(row.outstanding_amount, 0),
          0
        )
      : toNumber(requestedAmount, 0)
  );
  const allocations = [];
  let order = 1;
  for (const invoice of invoices) {
    if (remaining <= 0.009) break;
    const invoiceOutstanding = round2(toNumber(invoice.outstanding_amount, 0));
    if (invoiceOutstanding <= 0.009) continue;
    const allocateAmount = allowPartialLastInvoice
      ? round2(Math.min(invoiceOutstanding, remaining))
      : invoiceOutstanding;
    if (allocateAmount <= 0.009) continue;
    if (!allowPartialLastInvoice && remaining + 0.009 < invoiceOutstanding) {
      break;
    }
    const inserted = await client.query(
      `INSERT INTO merchant_payment_invoice_allocation
        (
          payment_request_id,
          receivable_invoice_id,
          allocated_amount,
          allocation_order,
          coverage_type
        )
       VALUES ($1,$2,$3,$4,$5)
       ON CONFLICT (payment_request_id, receivable_invoice_id)
       DO UPDATE
         SET allocated_amount = EXCLUDED.allocated_amount,
             allocation_order = EXCLUDED.allocation_order,
             coverage_type = EXCLUDED.coverage_type,
             updated_at = NOW()
       RETURNING *`,
      [
        Number(paymentRequestId),
        Number(invoice.id),
        allocateAmount,
        order,
        allocateAmount + 0.009 >= invoiceOutstanding
          ? "full"
          : "partial_existing_balance",
      ]
    );
    allocations.push(inserted.rows[0]);
    remaining = round2(remaining - allocateAmount);
    order += 1;
  }

  if (remaining > 0.009 && !allowPartialLastInvoice) {
    throw new AppError("PAYMENT_REQUEST_SELECTION_OUTDATED", {
      status: 409,
      details: {
        paymentRequestId: Number(paymentRequestId),
        merchantId: Number(merchantId),
        remainingAmount: remaining,
      },
    });
  }

  const touchedInvoiceIds = new Set(
    allocations.map((row) => Number(row.receivable_invoice_id))
  );
  for (const invoiceId of touchedInvoiceIds) {
    await syncReceivableInvoiceStatusTx(client, invoiceId);
  }
  return allocations;
}

async function fetchPaymentRequestInvoiceAllocationsTx(client, paymentRequestId) {
  const result = await client.query(
    `SELECT
       pia.*,
       inv.invoice_number,
       inv.order_id,
       inv.issued_at,
       inv.order_status,
       inv.subtotal,
       inv.commission_amount,
       inv.service_fee_amount,
       inv.app_delivery_fee_amount,
       inv.store_delivery_fee_amount,
       inv.app_receivable_amount,
       inv.store_net_amount,
       inv.paid_amount,
       inv.outstanding_amount,
       inv.invoice_status
     FROM merchant_payment_invoice_allocation pia
     JOIN merchant_receivable_invoice inv ON inv.id = pia.receivable_invoice_id
     WHERE pia.payment_request_id = $1
     ORDER BY pia.allocation_order ASC, pia.id ASC`,
    [Number(paymentRequestId)]
  );
  return result.rows.map((row) => ({
    ...row,
    allocated_amount: round2(toNumber(row.allocated_amount, 0)),
    subtotal: round2(toNumber(row.subtotal, 0)),
    commission_amount: round2(toNumber(row.commission_amount, 0)),
    service_fee_amount: round2(toNumber(row.service_fee_amount, 0)),
    app_delivery_fee_amount: round2(toNumber(row.app_delivery_fee_amount, 0)),
    store_delivery_fee_amount: round2(toNumber(row.store_delivery_fee_amount, 0)),
    app_receivable_amount: round2(toNumber(row.app_receivable_amount, 0)),
    store_net_amount: round2(toNumber(row.store_net_amount, 0)),
    paid_amount: round2(toNumber(row.paid_amount, 0)),
    outstanding_amount: round2(toNumber(row.outstanding_amount, 0)),
  }));
}

async function reconcileHistoricalMerchantPaymentAllocationsTx(
  client,
  merchantId
) {
  const requests = await client.query(
    `SELECT *
     FROM merchant_payment_request
     WHERE merchant_id = $1
       AND request_type = 'store_pays_app'
       AND status = 'confirmed_by_admin'
       AND NOT EXISTS (
         SELECT 1
         FROM merchant_payment_invoice_allocation pia
         WHERE pia.payment_request_id = merchant_payment_request.id
       )
     ORDER BY COALESCE(final_confirmed_at, reviewed_at, submitted_at) ASC, id ASC`,
    [Number(merchantId)]
  );
  for (const request of requests.rows) {
    const openInvoices = await listMerchantReceivableInvoicesTx(client, merchantId, {
      onlyOpen: true,
      limit: 3000,
    });
    if (openInvoices.length === 0) break;
    const paidAmount = round2(
      toNumber(request.paid_amount, toNumber(request.requested_amount, request.amount))
    );
    if (paidAmount <= 0.009) continue;
    await insertMerchantPaymentInvoiceAllocationsTx(client, {
      paymentRequestId: Number(request.id),
      merchantId: Number(merchantId),
      invoices: openInvoices,
      requestedAmount: paidAmount,
      allowPartialLastInvoice: true,
    });
  }
}

async function syncMerchantReceivableBookTx(client, merchantId, { maxOrders = 3000 } = {}) {
  await backfillMissingOrderReceivablesTx(client, {
    merchantId: Number(merchantId),
    maxOrders,
  });
  await reconcileHistoricalMerchantPaymentAllocationsTx(client, Number(merchantId));
}

async function ensureOrderAppPayablesSeededTx(client, orderRow) {
  if (!orderRow) return { seeded: false, entry: null };
  const status = String(orderRow.status || "").toLowerCase();
  if (!["delivered", "completed"].includes(status)) {
    return { seeded: false, entry: null };
  }
  const existing = await client.query(
    `SELECT id
     FROM merchant_app_payables_ledger
     WHERE merchant_id = $1
       AND reference_type = 'order_auto_accrual'
       AND reference_id = $2
       AND entry_type = 'order_share'
       AND direction = 'debit'
     LIMIT 1`,
    [Number(orderRow.merchant_id), Number(orderRow.id)]
  );
  if (existing.rows[0]) return { seeded: false, entry: existing.rows[0] };

  const snapshot = await ensureOrderFinancialSnapshotTx(client, orderRow);
  const due = calculateAppPayableDue(orderRow, snapshot);
  if (due <= 0) return { seeded: false, entry: null };
  const entry = await appendMerchantAppPayablesLedgerEntryTx(client, {
    merchantId: Number(orderRow.merchant_id),
    orderId: Number(orderRow.id),
    entryType: "order_share",
    amount: due,
    direction: "debit",
    referenceType: "order_auto_accrual",
    referenceId: Number(orderRow.id),
    note: "Auto accrual from completed order",
  });
  return { seeded: Boolean(entry), entry };
}

async function ensureOrderReceivablesSeededTx(client, orderRow) {
  if (!orderRow) return { seeded: false, entries: [] };
  const status = String(orderRow.status || "").toLowerCase();
  if (!["delivered", "completed"].includes(status)) {
    return { seeded: false, entries: [] };
  }
  const existing = await client.query(
    `SELECT COUNT(*)::int AS count
     FROM merchant_receivables_ledger
     WHERE merchant_id = $1
       AND reference_type = 'order_receivable'
       AND reference_id = $2`,
    [Number(orderRow.merchant_id), Number(orderRow.id)]
  );
  const receivableAlreadySeeded = Number(existing.rows[0]?.count || 0) > 0;
  if (receivableAlreadySeeded) {
    const invoice = await upsertMerchantReceivableInvoiceTx(client, orderRow);
    const payableSeed = await ensureOrderAppPayablesSeededTx(client, orderRow);
    return {
      seeded: payableSeed.seeded === true || invoice != null,
      entries: [],
      invoice: invoice || null,
      appPayableEntry: payableSeed.entry || null,
    };
  }

  const profile = await resolveMerchantBillingProfileTx(client, Number(orderRow.merchant_id));
  const snapshot = await ensureOrderFinancialSnapshotTx(client, orderRow, profile);
  const commission = round2(snapshot.commissionAmount);
  const serviceFee = round2(snapshot.serviceFeeAmount);
  const deliveryDue = round2(snapshot.appDeliveryFeeAmount);
  const entries = [];
  if (commission > 0) {
    const inserted = await appendMerchantLedgerEntryTx(client, {
      merchantId: Number(orderRow.merchant_id),
      orderId: Number(orderRow.id),
      entryType: "commission",
      amount: commission,
      direction: "debit",
      referenceType: "order_receivable",
      referenceId: Number(orderRow.id),
      note: "Auto-generated from completed order",
    });
    if (inserted) entries.push(inserted);
  }
  if (serviceFee > 0) {
    const inserted = await appendMerchantLedgerEntryTx(client, {
      merchantId: Number(orderRow.merchant_id),
      orderId: Number(orderRow.id),
      entryType: "service_fee",
      amount: serviceFee,
      direction: "debit",
      referenceType: "order_receivable",
      referenceId: Number(orderRow.id),
      note: "Auto-generated from completed order",
    });
    if (inserted) entries.push(inserted);
  }
  if (deliveryDue > 0) {
    const inserted = await appendMerchantLedgerEntryTx(client, {
      merchantId: Number(orderRow.merchant_id),
      orderId: Number(orderRow.id),
      entryType: "delivery_fee",
      amount: deliveryDue,
      direction: "debit",
      referenceType: "order_receivable",
      referenceId: Number(orderRow.id),
      note: "Auto-generated from completed order",
    });
    if (inserted) entries.push(inserted);
  }
  const invoice = await upsertMerchantReceivableInvoiceTx(client, orderRow, profile);
  const payableSeed = await ensureOrderAppPayablesSeededTx(client, orderRow);
  return {
    seeded: entries.length > 0 || payableSeed.seeded === true || invoice != null,
    entries,
    invoice: invoice || null,
    appPayableEntry: payableSeed.entry || null,
  };
}

async function listReceivableSeedCandidatesTx(
  client,
  { merchantId = null, maxOrders = 1000 } = {}
) {
  const where = [
    "o.merchant_id IS NOT NULL",
    "o.status IN ('delivered','completed')",
    `(
       NOT EXISTS (
       SELECT 1
       FROM merchant_receivables_ledger l
       WHERE l.merchant_id = o.merchant_id
         AND l.reference_type = 'order_receivable'
         AND l.reference_id = o.id
       )
       OR NOT EXISTS (
        SELECT 1
        FROM merchant_app_payables_ledger apl
        WHERE apl.merchant_id = o.merchant_id
          AND apl.reference_type = 'order_auto_accrual'
          AND apl.reference_id = o.id
          AND apl.entry_type = 'order_share'
          AND apl.direction = 'debit'
       )
     )`,
  ];
  const params = [];
  if (merchantId != null) {
    params.push(Number(merchantId));
    where.push(`o.merchant_id = $${params.length}`);
  }
  params.push(Math.max(1, Math.min(5000, Number(maxOrders) || 1000)));
  const limitParam = params.length;
  return client.query(
    `SELECT o.*
     FROM customer_order o
     WHERE ${where.join("\n       AND ")}
     ORDER BY COALESCE(o.completed_at, o.delivered_at, o.updated_at, o.created_at) ASC, o.id ASC
     LIMIT $${limitParam}`,
    params
  );
}

async function backfillMissingOrderReceivablesTx(
  client,
  { merchantId = null, maxOrders = 1000 } = {}
) {
  const candidates = await listReceivableSeedCandidatesTx(client, {
    merchantId,
    maxOrders,
  });
  let seededOrders = 0;
  let seededEntries = 0;
  for (const orderRow of candidates.rows) {
    const seeded = await ensureOrderReceivablesSeededTx(client, orderRow);
    if (!seeded.seeded) continue;
    seededOrders += 1;
    seededEntries += seeded.entries.length;
  }
  return {
    scannedOrders: Number(candidates.rowCount || 0),
    seededOrders,
    seededEntries,
  };
}

async function updateCourierCompetitionProgressTx(
  client,
  { courierUserId, orderRow }
) {
  if (!orderRow || !courierUserId) return [];
  const activeCompetitions = await client.query(
    `SELECT *
     FROM courier_competition
     WHERE is_active = TRUE
       AND start_at <= NOW()
       AND end_at >= NOW()
     ORDER BY id DESC`
  );
  if ((activeCompetitions.rowCount || 0) === 0) return [];

  const applied = [];
  for (const competition of activeCompetitions.rows) {
    const filters = competition.filters_json || {};
    const type = String(competition.competition_type || "").toLowerCase();
    const target = toNumber(competition.target_value, 0);

    let increment = 0;
    if (type === "completed_orders") {
      increment = 1;
    } else if (type === "merchant_orders") {
      if (
        Number(filters?.merchantId || 0) === 0 ||
        Number(filters.merchantId) === Number(orderRow.merchant_id)
      ) {
        increment = 1;
      }
    } else if (type === "delivery_fee_total") {
      increment = toNumber(orderRow.delivery_fee, 0);
    } else if (type === "sales_total") {
      increment = toNumber(orderRow.total_amount, 0);
    }

    if (increment <= 0) continue;

    await client.query(
      `INSERT INTO courier_competition_progress
        (
          competition_id,
          courier_user_id,
          current_value,
          is_completed,
          completed_at,
          reward_status
        )
       VALUES ($1,$2,$3,$4,$5,'pending')
       ON CONFLICT (competition_id, courier_user_id)
       DO UPDATE
         SET current_value = courier_competition_progress.current_value + EXCLUDED.current_value,
             is_completed = CASE
               WHEN courier_competition_progress.current_value + EXCLUDED.current_value >= $6 THEN TRUE
               ELSE courier_competition_progress.is_completed
             END,
             completed_at = CASE
               WHEN courier_competition_progress.current_value + EXCLUDED.current_value >= $6
                    AND courier_competition_progress.completed_at IS NULL
               THEN NOW()
               ELSE courier_competition_progress.completed_at
             END,
             updated_at = NOW()`,
      [
        Number(competition.id),
        Number(courierUserId),
        round2(increment),
        target > 0 ? increment >= target : false,
        target > 0 && increment >= target ? new Date() : null,
        target,
      ]
    );
    applied.push({
      competitionId: Number(competition.id),
      increment: round2(increment),
    });
  }
  return applied;
}

export async function courierMarkPickedUp({
  courierUserId,
  orderId,
  note = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const { order, courier } = await resolveCourierOrderForActionTx(client, {
      courierUserId,
      orderId,
      lock: true,
    });
    if (Number(order.delivery_user_id || 0) !== Number(courierUserId)) {
      throw new AppError("ORDER_NOT_ASSIGNED_TO_COURIER", { status: 409 });
    }
    if (!["ready_for_delivery", "preparing", "approved"].includes(String(order.status))) {
      throw new AppError("ORDER_PICKUP_NOT_ALLOWED", { status: 409 });
    }

    await client.query(
      `UPDATE customer_order
       SET status = 'on_the_way'::order_status,
           picked_up_at = COALESCE(picked_up_at, NOW()),
           on_the_way_at = COALESCE(on_the_way_at, NOW()),
           updated_at = NOW()
       WHERE id = $1`,
      [Number(orderId)]
    );

    await insertStatusHistoryTx(client, {
      orderId: Number(orderId),
      oldStatus: String(order.status),
      newStatus: "on_the_way",
      lifecycleOld: lifecycleFromStatus(order.status),
      lifecycleNew: "ON_THE_WAY",
      changedByUserId: Number(courierUserId),
      changedByRole: "delivery",
      note,
    });

    const orderRefreshed = await client.query(
      `SELECT *
       FROM customer_order
       WHERE id = $1`,
      [Number(orderId)]
    );

    await client.query("COMMIT");
    return { order: orderRefreshed.rows[0], courier, ownerUserId: Number(order.owner_user_id) };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function courierMarkArrived({
  courierUserId,
  orderId,
  note = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const { order, courier } = await resolveCourierOrderForActionTx(client, {
      courierUserId,
      orderId,
      lock: true,
    });
    if (Number(order.delivery_user_id || 0) !== Number(courierUserId)) {
      throw new AppError("ORDER_NOT_ASSIGNED_TO_COURIER", { status: 409 });
    }
    if (!["on_the_way", "ready_for_delivery"].includes(String(order.status))) {
      throw new AppError("ORDER_ARRIVAL_NOT_ALLOWED", { status: 409 });
    }

    await client.query(
      `UPDATE customer_order
       SET status = 'arrived'::order_status,
           arrived_at = COALESCE(arrived_at, NOW()),
           updated_at = NOW()
       WHERE id = $1`,
      [Number(orderId)]
    );

    await insertStatusHistoryTx(client, {
      orderId: Number(orderId),
      oldStatus: String(order.status),
      newStatus: "arrived",
      lifecycleOld: lifecycleFromStatus(order.status),
      lifecycleNew: "ARRIVED",
      changedByUserId: Number(courierUserId),
      changedByRole: "delivery",
      note,
    });

    const orderRefreshed = await client.query(
      `SELECT *
       FROM customer_order
       WHERE id = $1`,
      [Number(orderId)]
    );

    await client.query("COMMIT");
    return { order: orderRefreshed.rows[0], courier, ownerUserId: Number(order.owner_user_id) };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function courierMarkDelivered({
  courierUserId,
  orderId,
  note = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const { order, courier } = await resolveCourierOrderForActionTx(client, {
      courierUserId,
      orderId,
      lock: true,
    });
    if (Number(order.delivery_user_id || 0) !== Number(courierUserId)) {
      throw new AppError("ORDER_NOT_ASSIGNED_TO_COURIER", { status: 409 });
    }
    if (!["arrived", "on_the_way"].includes(String(order.status))) {
      throw new AppError("ORDER_DELIVERY_NOT_ALLOWED", { status: 409 });
    }

    await client.query(
      `UPDATE customer_order
       SET status = 'delivered'::order_status,
           delivered_at = COALESCE(delivered_at, NOW()),
           updated_at = NOW()
       WHERE id = $1`,
      [Number(orderId)]
    );

    await insertStatusHistoryTx(client, {
      orderId: Number(orderId),
      oldStatus: String(order.status),
      newStatus: "delivered",
      lifecycleOld: lifecycleFromStatus(order.status),
      lifecycleNew: "DELIVERED_BY_COURIER",
      changedByUserId: Number(courierUserId),
      changedByRole: "delivery",
      note,
    });

    const orderRefreshed = await client.query(
      `SELECT *
       FROM customer_order
       WHERE id = $1`,
      [Number(orderId)]
    );

    await client.query("COMMIT");
    return { order: orderRefreshed.rows[0], courier, ownerUserId: Number(order.owner_user_id) };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function customerConfirmOrderReceived({
  customerUserId,
  orderId,
  note = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const orderResult = await client.query(
      `SELECT o.*, m.owner_user_id, m.name AS merchant_name
       FROM customer_order o
       JOIN merchant m ON m.id = o.merchant_id
       WHERE o.id = $1
         AND o.customer_user_id = $2
       FOR UPDATE`,
      [Number(orderId), Number(customerUserId)]
    );
    const order = orderResult.rows[0];
    if (!order) throw new AppError("ORDER_NOT_FOUND", { status: 404 });
    if (!["delivered", "completed"].includes(String(order.status))) {
      throw new AppError("ORDER_NOT_DELIVERED_YET", { status: 409 });
    }
    const transitionedToCompleted = String(order.status) !== "completed";

    await client.query(
      `UPDATE customer_order
       SET customer_confirmed_at = COALESCE(customer_confirmed_at, NOW()),
           completed_at = COALESCE(completed_at, NOW()),
           status = CASE
             WHEN status = 'completed'::order_status THEN status
             ELSE 'completed'::order_status
           END,
           updated_at = NOW()
       WHERE id = $1`,
      [Number(orderId)]
    );

    await insertStatusHistoryTx(client, {
      orderId: Number(orderId),
      oldStatus: String(order.status),
      newStatus: "completed",
      lifecycleOld: lifecycleFromStatus(order.status),
      lifecycleNew: "COMPLETED",
      changedByUserId: Number(customerUserId),
      changedByRole: "customer",
      note,
    });

    const refreshed = await client.query(
      `SELECT *
       FROM customer_order
       WHERE id = $1`,
      [Number(orderId)]
    );
    const finalOrder = refreshed.rows[0];

    await ensureOrderReceivablesSeededTx(client, finalOrder);
    let competitionUpdates = null;
    if (finalOrder.delivery_user_id && transitionedToCompleted) {
      competitionUpdates = await onOrderFinallyCompletedTx(client, {
        orderRow: finalOrder,
      });

      await client.query(
        `UPDATE courier_profile
         SET total_completed_orders = total_completed_orders + 1,
             updated_at = NOW()
         WHERE user_id = $1`,
        [Number(finalOrder.delivery_user_id)]
      );
    }

    await client.query("COMMIT");
    return {
      order: finalOrder,
      ownerUserId: Number(order.owner_user_id),
      courierUserId: finalOrder.delivery_user_id ? Number(finalOrder.delivery_user_id) : null,
      competitionUpdates: competitionUpdates || {
        applied: [],
        courierEvents: [],
        adminEvents: [],
        finalized: null,
      },
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

function isBackofficeRole(role) {
  const normalized = String(role || "").trim().toLowerCase();
  return normalized === "admin" || normalized === "deputy_admin";
}

function isTerminalStatus(status) {
  return [
    "completed",
    "cancelled",
    "cancelled_by_store",
    "cancelled_by_admin",
    "cancelled_by_customer",
    "failed_delivery",
    "returned_if_needed",
  ].includes(String(status || "").trim().toLowerCase());
}

async function getOrderParticipantsTx(client, orderId, { lock = false } = {}) {
  const r = await client.query(
    `SELECT
       o.*,
       m.owner_user_id
     FROM customer_order o
     JOIN merchant m ON m.id = o.merchant_id
     WHERE o.id = $1
     ${lock ? "FOR UPDATE" : ""}`,
    [Number(orderId)]
  );
  return r.rows[0] || null;
}

function resolveOrderChatAccess(order, { userId, userRole }) {
  const uid = Number(userId || 0);
  if (!uid || !order) return { allowed: false };
  if (isBackofficeRole(userRole)) {
    return { allowed: true, canWrite: true, role: "admin", isBackoffice: true };
  }
  if (uid === Number(order.customer_user_id)) {
    return { allowed: true, canWrite: true, role: "customer", isBackoffice: false };
  }
  if (uid === Number(order.delivery_user_id || 0)) {
    return { allowed: true, canWrite: true, role: "delivery", isBackoffice: false };
  }
  if (uid === Number(order.owner_user_id || 0)) {
    return { allowed: true, canWrite: false, role: "owner", isBackoffice: false };
  }
  return { allowed: false };
}

export async function listOrderChatMessages({
  userId,
  userRole,
  orderId,
  limit = 120,
  beforeId = null,
}) {
  const client = await pool.connect();
  try {
    const order = await getOrderParticipantsTx(client, Number(orderId));
    if (!order) throw new AppError("ORDER_NOT_FOUND", { status: 404 });

    const access = resolveOrderChatAccess(order, { userId, userRole });
    if (!access.allowed) throw new AppError("ORDER_CHAT_FORBIDDEN", { status: 403 });

    const isClosedForParticipants =
      !access.isBackoffice && isTerminalStatus(order.status);
    const canWrite = access.canWrite && !isClosedForParticipants;

    if (isClosedForParticipants) {
      return {
        orderId: Number(order.id),
        open: false,
        canWrite: false,
        messages: [],
      };
    }

    const params = [Number(orderId)];
    let whereBefore = "";
    if (beforeId != null) {
      params.push(Number(beforeId));
      whereBefore = `AND id < $${params.length}`;
    }
    params.push(Math.max(1, Math.min(400, Number(limit) || 120)));
    const limitIdx = params.length;

    const rows = await client.query(
      `SELECT
         id,
         order_id,
         sender_user_id,
         sender_role,
         message_text,
         created_at
       FROM order_chat_message
       WHERE order_id = $1
         ${whereBefore}
       ORDER BY id DESC
       LIMIT $${limitIdx}`,
      params
    );

    return {
      orderId: Number(order.id),
      open: true,
      canWrite,
      messages: rows.rows.reverse(),
    };
  } finally {
    client.release();
  }
}

export async function createOrderChatMessage({
  userId,
  userRole,
  orderId,
  message,
}) {
  const text = String(message || "").trim();
  if (!text) throw new AppError("CHAT_MESSAGE_REQUIRED", { status: 400 });

  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const order = await getOrderParticipantsTx(client, Number(orderId), {
      lock: true,
    });
    if (!order) throw new AppError("ORDER_NOT_FOUND", { status: 404 });

    const access = resolveOrderChatAccess(order, { userId, userRole });
    if (!access.allowed || !access.canWrite) {
      throw new AppError("ORDER_CHAT_FORBIDDEN", { status: 403 });
    }
    if (!access.isBackoffice && isTerminalStatus(order.status)) {
      throw new AppError("ORDER_CHAT_CLOSED", { status: 409 });
    }

    const inserted = await client.query(
      `INSERT INTO order_chat_message
        (order_id, sender_user_id, sender_role, message_text)
       VALUES ($1,$2,$3,$4)
       RETURNING id, order_id, sender_user_id, sender_role, message_text, created_at`,
      [Number(orderId), Number(userId), String(access.role), text]
    );

    await client.query("COMMIT");

    const notifyUserIds = [
      Number(order.customer_user_id || 0),
      Number(order.delivery_user_id || 0),
    ].filter((v, i, arr) => v > 0 && arr.indexOf(v) === i);

    const targetByUserId = {};
    const roleScopeByUserId = {};
    for (const uid of notifyUserIds) {
      if (uid === Number(order.delivery_user_id || 0)) {
        targetByUserId[String(uid)] = "courier_orders_current";
        roleScopeByUserId[String(uid)] = "courier";
      } else {
        targetByUserId[String(uid)] = "order_tracking";
        roleScopeByUserId[String(uid)] = "user";
      }
    }

    return {
      order,
      message: inserted.rows[0],
      notifyUserIds,
      targetByUserId,
      roleScopeByUserId,
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function createCourierCancelRequest({
  courierUserId,
  orderId,
  reasonCode,
  reasonText,
  reasonLabel,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const { order } = await resolveCourierOrderForActionTx(client, {
      courierUserId,
      orderId,
      lock: true,
    });

    if (Number(order.delivery_user_id || 0) !== Number(courierUserId)) {
      throw new AppError("ORDER_NOT_ASSIGNED_TO_COURIER", { status: 409 });
    }
    if (!["ready_for_delivery", "on_the_way", "arrived"].includes(String(order.status))) {
      throw new AppError("ORDER_CANCEL_REQUEST_NOT_ALLOWED", { status: 409 });
    }

    const normalizedCode = String(reasonCode || "").trim().toLowerCase();
    const normalizedText =
      reasonText == null ? null : String(reasonText).trim() || null;
    const legacyReason =
      normalizedText || String(reasonLabel || "").trim() || normalizedCode;

    const existing = await client.query(
      `SELECT *
       FROM courier_order_cancel_request
       WHERE order_id = $1
         AND status = 'pending'
       ORDER BY id DESC
       LIMIT 1
       FOR UPDATE`,
      [Number(orderId)]
    );

    let requestRow;
    if (existing.rows[0]) {
      if (Number(existing.rows[0].courier_user_id) !== Number(courierUserId)) {
        throw new AppError("ANOTHER_CANCEL_REQUEST_PENDING", { status: 409 });
      }
      const updated = await client.query(
        `UPDATE courier_order_cancel_request
         SET reason = $2,
             reason_code = $3,
             reason_text = $4,
             requested_at = NOW(),
             updated_at = NOW()
         WHERE id = $1
         RETURNING *`,
        [Number(existing.rows[0].id), legacyReason, normalizedCode, normalizedText]
      );
      requestRow = updated.rows[0];
    } else {
      const inserted = await client.query(
        `INSERT INTO courier_order_cancel_request
          (order_id, courier_user_id, reason, reason_code, reason_text, status)
         VALUES ($1,$2,$3,$4,$5,'pending')
         RETURNING *`,
        [
          Number(orderId),
          Number(courierUserId),
          legacyReason,
          normalizedCode,
          normalizedText,
        ]
      );
      requestRow = inserted.rows[0];
    }

    await client.query(
      `INSERT INTO order_action_event
        (order_id, actor_user_id, actor_scope, action_kind, reason_code, reason_text, metadata_json)
       VALUES ($1,$2,'courier','cancel',$3,$4,$5::jsonb)`,
      [
        Number(orderId),
        Number(courierUserId),
        normalizedCode,
        normalizedText,
        JSON.stringify({ stage: "request" }),
      ]
    );

    await insertStatusHistoryTx(client, {
      orderId: Number(orderId),
      oldStatus: String(order.status),
      newStatus: String(order.status),
      lifecycleOld: lifecycleFromStatus(order.status),
      lifecycleNew: lifecycleFromStatus(order.status),
      changedByUserId: Number(courierUserId),
      changedByRole: "delivery",
      note: `courier_cancel_request:${normalizedCode}`,
    });

    const admins = await client.query(
      `SELECT id
       FROM app_user
       WHERE role IN ('admin','deputy_admin')
         AND is_account_disabled = FALSE`
    );

    await client.query("COMMIT");
    return {
      request: requestRow,
      order,
      ownerUserId: Number(order.owner_user_id),
      adminRecipients: admins.rows.map((row) => Number(row.id)),
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

async function reviewCourierCancelRequestTx(
  client,
  {
    orderId,
    approved,
    reviewedByUserId,
    reviewedByRole,
    reviewNote,
  }
) {
  const order = await getOrderParticipantsTx(client, Number(orderId), {
    lock: true,
  });
  if (!order) throw new AppError("ORDER_NOT_FOUND", { status: 404 });

  const requestResult = await client.query(
    `SELECT *
     FROM courier_order_cancel_request
     WHERE order_id = $1
       AND status = 'pending'
     ORDER BY id DESC
     LIMIT 1
     FOR UPDATE`,
    [Number(orderId)]
  );
  const request = requestResult.rows[0];
  if (!request) throw new AppError("CANCEL_REQUEST_NOT_FOUND", { status: 404 });
  const requestReasonCode = String(request.reason_code || "").trim().toLowerCase();
  const requestReasonText =
    request.reason_text == null ? null : String(request.reason_text).trim() || null;
  const requestLegacyReason =
    String(request.reason || "").trim() || requestReasonCode || "courier_cancel_request";
  const effectiveReasonText = requestReasonText || requestLegacyReason;

  const nextStatus = approved ? "approved" : "rejected";
  const reviewed = await client.query(
    `UPDATE courier_order_cancel_request
     SET status = $2,
         reviewed_at = NOW(),
         reviewed_by_user_id = $3,
         review_note = $4,
         updated_at = NOW()
     WHERE id = $1
     RETURNING *`,
    [
      Number(request.id),
      nextStatus,
      Number(reviewedByUserId),
      reviewNote || null,
    ]
  );
  const updatedRequest = reviewed.rows[0];

  let finalOrder = order;
  if (approved) {
    if (isTerminalStatus(order.status)) {
      throw new AppError("ORDER_ALREADY_FINALIZED", { status: 409 });
    }
    const cancelled = await client.query(
      `UPDATE customer_order
       SET status = 'cancelled'::order_status,
           cancelled_at = COALESCE(cancelled_at, NOW()),
           cancelled_by_role = COALESCE(cancelled_by_role, $3),
           cancellation_reason = COALESCE(cancellation_reason, $2),
           cancellation_reason_code = COALESCE(cancellation_reason_code, $4),
           cancellation_reason_text = COALESCE(cancellation_reason_text, $5),
           updated_at = NOW()
       WHERE id = $1
       RETURNING *`,
      [
        Number(orderId),
        effectiveReasonText,
        reviewedByRole === "admin" ? "admin" : "store",
        requestReasonCode || null,
        requestReasonText,
      ]
    );
    finalOrder = { ...order, ...cancelled.rows[0] };
    await syncOrderIncentiveConsumptionForStatusTx(client, {
      orderId: Number(orderId),
      nextStatus: "cancelled",
      reason: `courier_cancel_request:${requestReasonCode || "approved"}`,
    });
    await cancelPendingAssignmentsTx(client, Number(orderId));
    await client.query(
      `INSERT INTO order_action_event
        (order_id, actor_user_id, actor_scope, action_kind, reason_code, reason_text, metadata_json)
       VALUES ($1,$2,$3,'cancel',$4,$5,$6::jsonb)`,
      [
        Number(orderId),
        Number(reviewedByUserId),
        reviewedByRole === "admin" ? "admin" : "store",
        requestReasonCode || null,
        requestReasonText || effectiveReasonText,
        JSON.stringify({
          source: "courier_cancel_request",
          requestId: Number(request.id),
          approved: true,
        }),
      ]
    );
    await insertStatusHistoryTx(client, {
      orderId: Number(orderId),
      oldStatus: String(order.status),
      newStatus: "cancelled",
      lifecycleOld: lifecycleFromStatus(order.status),
      lifecycleNew:
        reviewedByRole === "admin" ? "CANCELLED_BY_ADMIN" : "CANCELLED_BY_STORE",
      changedByUserId: Number(reviewedByUserId),
      changedByRole: reviewedByRole,
      note: `courier_cancel_request_approved:${requestReasonCode || requestLegacyReason}`,
    });
  } else {
    await client.query(
      `INSERT INTO order_action_event
        (order_id, actor_user_id, actor_scope, action_kind, reason_code, reason_text, metadata_json)
       VALUES ($1,$2,$3,'cancel',$4,$5,$6::jsonb)`,
      [
        Number(orderId),
        Number(reviewedByUserId),
        reviewedByRole === "admin" ? "admin" : "store",
        requestReasonCode || null,
        reviewNote || null,
        JSON.stringify({
          source: "courier_cancel_request",
          requestId: Number(request.id),
          approved: false,
        }),
      ]
    );
    await insertStatusHistoryTx(client, {
      orderId: Number(orderId),
      oldStatus: String(order.status),
      newStatus: String(order.status),
      lifecycleOld: lifecycleFromStatus(order.status),
      lifecycleNew: lifecycleFromStatus(order.status),
      changedByUserId: Number(reviewedByUserId),
      changedByRole: reviewedByRole,
      note: "courier_cancel_request_rejected",
    });
  }

  return {
    request: updatedRequest,
    order: finalOrder,
  };
}

export async function reviewCourierCancelRequestByOwner({
  ownerUserId,
  orderId,
  approved,
  reviewNote = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const order = await getOwnerOrderWithMerchant(ownerUserId, orderId, client, {
      forUpdate: true,
    });
    if (!order) throw new AppError("ORDER_NOT_FOUND", { status: 404 });

    const out = await reviewCourierCancelRequestTx(client, {
      orderId,
      approved,
      reviewedByUserId: ownerUserId,
      reviewedByRole: "owner",
      reviewNote,
    });

    await client.query("COMMIT");
    return out;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function reviewCourierCancelRequestByAdmin({
  adminUserId,
  orderId,
  approved,
  reviewNote = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const out = await reviewCourierCancelRequestTx(client, {
      orderId,
      approved,
      reviewedByUserId: adminUserId,
      reviewedByRole: "admin",
      reviewNote,
    });
    await client.query("COMMIT");
    return out;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function listCourierDashboard(courierUserId, { period, from, to } = {}) {
  const window = parseWindow({ period, from, to });
  const start = window.start;
  const end = window.end;

  const [totals, earnings, byMerchant] = await Promise.all([
    q(
      `SELECT
         COUNT(*)::int AS total_orders,
         COUNT(*) FILTER (WHERE status IN ('completed','delivered','delivered_by_courier','received_by_customer'))::int AS completed_orders,
         COUNT(*) FILTER (WHERE status IN ('cancelled','cancelled_by_store','cancelled_by_admin','cancelled_by_customer'))::int AS cancelled_orders,
         COUNT(*) FILTER (WHERE status IN ('approved','preparing','ready_for_delivery','on_the_way','arrived'))::int AS active_orders,
         AVG(EXTRACT(EPOCH FROM (COALESCE(delivered_at, NOW()) - COALESCE(picked_up_at, created_at))) / 60.0)::numeric(10,2) AS avg_delivery_minutes
       FROM customer_order
       WHERE delivery_user_id = $1
         AND created_at >= $2::timestamptz
         AND created_at <= $3::timestamptz`,
      [Number(courierUserId), start, end]
    ),
    q(
      `SELECT
         COALESCE(SUM(amount),0)::numeric AS total_earnings,
         COALESCE(SUM(amount) FILTER (WHERE created_at >= DATE_TRUNC('day', NOW())),0)::numeric AS today_earnings
       FROM courier_earning
       WHERE courier_user_id = $1
         AND created_at >= $2::timestamptz
         AND created_at <= $3::timestamptz`,
      [Number(courierUserId), start, end]
    ),
    q(
      `SELECT
         o.merchant_id,
         m.name AS merchant_name,
         COUNT(*)::int AS orders_count,
         COALESCE(SUM(o.delivery_fee),0)::numeric AS delivery_fee_total
       FROM customer_order o
       JOIN merchant m ON m.id = o.merchant_id
       WHERE o.delivery_user_id = $1
         AND o.created_at >= $2::timestamptz
         AND o.created_at <= $3::timestamptz
       GROUP BY o.merchant_id, m.name
       ORDER BY orders_count DESC, m.name ASC
       LIMIT 20`,
      [Number(courierUserId), start, end]
    ),
  ]);

  const t = totals.rows[0] || {};
  const e = earnings.rows[0] || {};
  return {
    window,
    kpis: {
      totalOrders: Number(t.total_orders || 0),
      completedOrders: Number(t.completed_orders || 0),
      cancelledOrders: Number(t.cancelled_orders || 0),
      activeOrders: Number(t.active_orders || 0),
      avgDeliveryMinutes: toNumber(t.avg_delivery_minutes, 0),
      acceptanceRate:
        Number(t.total_orders || 0) > 0
          ? round2((Number(t.completed_orders || 0) / Number(t.total_orders || 1)) * 100)
          : 0,
      totalEarnings: toNumber(e.total_earnings, 0),
      todayEarnings: toNumber(e.today_earnings, 0),
    },
    byMerchant: byMerchant.rows,
  };
}

export async function listCourierRequests(
  courierUserId,
  { limit = 40, offset = 0 } = {}
) {
  const l = Math.max(1, Math.min(200, Number(limit) || 40));
  const o = Math.max(0, Number(offset) || 0);

  const r = await q(
    `SELECT
       o.id AS order_id,
       o.status AS order_status,
       o.delivery_assignment_status,
       o.courier_assigned_at,
       o.subtotal,
       o.delivery_fee,
       o.total_amount,
       o.customer_full_name,
       o.customer_phone,
       o.customer_city,
       o.customer_block,
       o.customer_building_number,
       o.customer_apartment,
       o.note AS customer_note,
       o.created_at AS order_created_at,
       m.id AS merchant_id,
       m.name AS merchant_name,
       m.type AS merchant_type
     FROM customer_order o
     JOIN merchant m ON m.id = o.merchant_id
     WHERE o.delivery_user_id = $1
       AND o.delivery_assignment_status = 'ASSIGNED'
       AND o.status IN ('approved','preparing','ready_for_delivery','on_the_way','arrived')
     ORDER BY COALESCE(o.courier_assigned_at, o.updated_at, o.created_at) DESC, o.id DESC
     LIMIT $2 OFFSET $3`,
    [Number(courierUserId), l, o]
  );

  return { requests: r.rows, limit: l, offset: o };
}

export async function listCourierOrders(
  courierUserId,
  { status = null, merchantId = null, limit = 60, offset = 0 } = {}
) {
  const where = [`o.delivery_user_id = $1`];
  const params = [Number(courierUserId)];
  if (status) {
    params.push(String(status));
    where.push(`o.status = $${params.length}::order_status`);
  }
  if (merchantId) {
    params.push(Number(merchantId));
    where.push(`o.merchant_id = $${params.length}`);
  }
  params.push(Math.max(1, Math.min(200, Number(limit) || 60)));
  const limitIdx = params.length;
  params.push(Math.max(0, Number(offset) || 0));
  const offsetIdx = params.length;

  const r = await q(
    `SELECT
       o.*,
       m.name AS merchant_name,
       m.type AS merchant_type
     FROM customer_order o
     JOIN merchant m ON m.id = o.merchant_id
     WHERE ${where.join(" AND ")}
     ORDER BY o.updated_at DESC, o.id DESC
     LIMIT $${limitIdx} OFFSET $${offsetIdx}`,
    params
  );
  return { orders: r.rows };
}

export async function listCourierOrdersGroupedByMerchant(
  courierUserId,
  { period, from, to, status = null } = {}
) {
  const window = parseWindow({ period, from, to });
  const params = [Number(courierUserId), window.start, window.end];
  let statusClause = "";
  if (status) {
    params.push(String(status));
    statusClause = `AND o.status = $${params.length}::order_status`;
  }
  const r = await q(
    `SELECT
       o.merchant_id,
       m.name AS merchant_name,
       COUNT(*)::int AS orders_count,
       COALESCE(SUM(o.delivery_fee),0)::numeric AS delivery_total,
       AVG(EXTRACT(EPOCH FROM (COALESCE(o.delivered_at, NOW()) - COALESCE(o.picked_up_at, o.created_at))) / 60.0)::numeric(10,2) AS avg_delivery_minutes
     FROM customer_order o
     JOIN merchant m ON m.id = o.merchant_id
     WHERE o.delivery_user_id = $1
       AND o.created_at >= $2::timestamptz
       AND o.created_at <= $3::timestamptz
       ${statusClause}
     GROUP BY o.merchant_id, m.name
     ORDER BY orders_count DESC, m.name ASC`,
    params
  );
  return { window, groups: r.rows };
}

export async function listCourierReports(courierUserId, { period, from, to } = {}) {
  const dashboard = await listCourierDashboard(courierUserId, { period, from, to });
  const grouped = await listCourierOrdersGroupedByMerchant(courierUserId, { period, from, to });
  return {
    ...dashboard,
    groupedByMerchant: grouped.groups,
  };
}

export async function listCourierEarnings(
  courierUserId,
  { period, from, to, limit = 100, offset = 0 } = {}
) {
  const window = parseWindow({ period, from, to });
  const r = await q(
    `SELECT
       ce.*,
       m.name AS merchant_name
     FROM courier_earning ce
     LEFT JOIN merchant m ON m.id = ce.merchant_id
     WHERE ce.courier_user_id = $1
       AND ce.created_at >= $2::timestamptz
       AND ce.created_at <= $3::timestamptz
     ORDER BY ce.created_at DESC, ce.id DESC
     LIMIT $4 OFFSET $5`,
    [
      Number(courierUserId),
      window.start,
      window.end,
      Math.max(1, Math.min(300, Number(limit) || 100)),
      Math.max(0, Number(offset) || 0),
    ]
  );
  return { window, earnings: r.rows };
}

async function runCompetitionFinalizerPass() {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const out = await finalizeExpiredCompetitionsTx(client);
    await client.query("COMMIT");
    return out;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

function parseCompetitionScope(scopeRaw) {
  const scope = String(scopeRaw || "active").trim().toLowerCase();
  if (scope === "history" || scope === "ended" || scope === "archived") {
    return "history";
  }
  if (scope === "all") return "all";
  return "active";
}

function mapCompetitionTiers(rows = []) {
  const map = new Map();
  for (const row of rows) {
    const competitionId = Number(row.competition_id || 0);
    if (!competitionId) continue;
    const list = map.get(competitionId) || [];
    list.push({
      id: Number(row.id),
      sortOrder: Number(row.sort_order || 0),
      title: String(row.title || "").trim() || `Rank ${row.sort_order}`,
      requiredCompletedOrders: Number(row.required_completed_orders || 0),
      rewardAmount: toNumber(row.reward_amount, 0),
      rewardLabel: row.reward_label || null,
    });
    map.set(competitionId, list);
  }
  for (const [key, list] of map.entries()) {
    list.sort((a, b) => {
      if (b.requiredCompletedOrders !== a.requiredCompletedOrders) {
        return b.requiredCompletedOrders - a.requiredCompletedOrders;
      }
      return a.sortOrder - b.sortOrder;
    });
    map.set(key, list);
  }
  return map;
}

function deriveFallbackTier(competition) {
  return [
    {
      id: null,
      sortOrder: 1,
      title: "Rank 1",
      requiredCompletedOrders: Math.max(1, Math.floor(toNumber(competition?.target_value, 1))),
      rewardAmount: toNumber(competition?.reward_amount, 0),
      rewardLabel: null,
    },
  ];
}

function resolveNextTier(tiers, currentValue) {
  const count = Math.max(0, Math.floor(toNumber(currentValue, 0)));
  const pending = [...tiers]
    .sort((a, b) => {
      if (b.requiredCompletedOrders !== a.requiredCompletedOrders) {
        return b.requiredCompletedOrders - a.requiredCompletedOrders;
      }
      return a.sortOrder - b.sortOrder;
    })
    .filter((tier) => count < Number(tier.requiredCompletedOrders || 0));
  return pending.length ? pending[pending.length - 1] : null;
}

function enrichCompetitionRow(row, tiers) {
  const currentValue = toNumber(row.current_value, 0);
  const highestRank = resolveHighestRank(tiers, currentValue);
  const nextRank = resolveNextTier(tiers, currentValue);
  const denominator = Math.max(
    1,
    Number(
      nextRank?.requiredCompletedOrders ??
        highestRank?.requiredCompletedOrders ??
        tiers[tiers.length - 1]?.requiredCompletedOrders ??
        1
    )
  );
  const ratio = Math.max(0, Math.min(100, (currentValue / denominator) * 100));

  return {
    ...row,
    tiers,
    current_value: currentValue,
    currentValue: currentValue,
    highest_rank_sort_order: highestRank?.sortOrder ?? row.highest_rank_sort_order ?? null,
    highest_rank_title: highestRank?.title ?? row.highest_rank_title ?? null,
    current_rank_sort_order:
      row.current_rank_sort_order ?? highestRank?.sortOrder ?? null,
    current_rank_title: row.current_rank_title ?? highestRank?.title ?? null,
    next_rank: nextRank,
    nextRank,
    progress_percent: Number(ratio.toFixed(2)),
    progressPercent: Number(ratio.toFixed(2)),
    remaining_to_next_rank:
      nextRank == null
        ? 0
        : Math.max(0, Number(nextRank.requiredCompletedOrders) - Math.floor(currentValue)),
    remainingToNextRank:
      nextRank == null
        ? 0
        : Math.max(0, Number(nextRank.requiredCompletedOrders) - Math.floor(currentValue)),
  };
}

async function listCompetitionRowsForCourier(courierUserId, { scope = "active" } = {}) {
  const normalizedScope = parseCompetitionScope(scope);
  const whereParts = [];
  if (normalizedScope === "active") {
    whereParts.push(
      "(cc.is_active = TRUE AND cc.start_at <= NOW() AND cc.end_at >= NOW() AND cc.status IN ('active','draft'))"
    );
  } else if (normalizedScope === "history") {
    whereParts.push("(cc.end_at < NOW() OR cc.status IN ('ended','cancelled'))");
  }

  const whereClause = whereParts.length ? `WHERE ${whereParts.join(" AND ")}` : "";
  const rows = await q(
    `SELECT
       cc.*,
       ccp.current_value,
       ccp.is_completed,
       ccp.completed_at,
       ccp.reward_status,
       ccp.current_rank_sort_order,
       ccp.current_rank_title,
       ccp.highest_rank_sort_order,
       ccp.highest_rank_title,
       ccp.updated_at AS progress_updated_at
     FROM courier_competition cc
     LEFT JOIN courier_competition_progress ccp
       ON ccp.competition_id = cc.id
      AND ccp.courier_user_id = $1
     ${whereClause}
     ORDER BY cc.start_at DESC, cc.id DESC`,
    [Number(courierUserId)]
  );

  if ((rows.rowCount || 0) === 0) return [];

  const competitionIds = rows.rows.map((row) => Number(row.id)).filter((id) => id > 0);
  const tiersRows = await q(
    `SELECT *
     FROM courier_competition_tier
     WHERE competition_id = ANY($1::bigint[])
     ORDER BY competition_id ASC, required_completed_orders DESC, sort_order ASC`,
    [competitionIds]
  );
  const tiersMap = mapCompetitionTiers(tiersRows.rows);

  return rows.rows.map((row) => {
    const tiers = tiersMap.get(Number(row.id)) || deriveFallbackTier(row);
    return enrichCompetitionRow(row, tiers);
  });
}

export async function listCourierCompetitions(courierUserId, { scope = "active" } = {}) {
  await runCompetitionFinalizerPass();
  const competitions = await listCompetitionRowsForCourier(courierUserId, { scope });
  return { competitions, scope: parseCompetitionScope(scope) };
}

export async function getCourierCompetitionDetails(courierUserId, competitionId) {
  await runCompetitionFinalizerPass();
  const competitionRows = await listCompetitionRowsForCourier(courierUserId, { scope: "all" });
  const competition = competitionRows.find(
    (row) => Number(row.id || 0) === Number(competitionId || 0)
  );
  if (!competition) throw new AppError("COMPETITION_NOT_FOUND", { status: 404 });

  const leaderboard = await q(
    `SELECT
       ccp.courier_user_id,
       u.full_name,
       ccp.current_value,
       ccp.current_rank_sort_order,
       ccp.current_rank_title,
       ccp.highest_rank_sort_order,
       ccp.highest_rank_title,
       ccp.updated_at
     FROM courier_competition_progress ccp
     JOIN app_user u ON u.id = ccp.courier_user_id
     WHERE ccp.competition_id = $1
     ORDER BY ccp.current_value DESC, ccp.updated_at ASC
     LIMIT 200`,
    [Number(competitionId)]
  );

  return {
    competition,
    leaderboard: leaderboard.rows,
  };
}

export async function listCourierCompetitionProgress(courierUserId) {
  await runCompetitionFinalizerPass();
  const items = await listCompetitionRowsForCourier(courierUserId, { scope: "all" });
  return { progress: items, items };
}

export async function getCourierCompetitionAchievementsSummary(courierUserId) {
  const r = await q(
    `SELECT
       COUNT(*)::int AS competitions_participated,
       COUNT(*) FILTER (WHERE won = TRUE)::int AS competitions_won,
       COUNT(*) FILTER (WHERE won = TRUE AND final_rank_sort_order = 1)::int AS rank_1_wins,
       COUNT(*) FILTER (WHERE won = TRUE AND final_rank_sort_order = 2)::int AS rank_2_wins,
       COUNT(*) FILTER (WHERE won = TRUE AND final_rank_sort_order = 3)::int AS rank_3_wins,
       COALESCE(SUM(reward_amount),0)::numeric AS total_rewards,
       COALESCE(SUM(final_completed_orders),0)::int AS counted_completed_orders
     FROM courier_competition_result
     WHERE courier_user_id = $1`,
    [Number(courierUserId)]
  );
  return { summary: r.rows[0] || {} };
}

export async function listMerchantCouriers(ownerUserId) {
  const merchant = await q(
    `SELECT id
     FROM merchant
     WHERE owner_user_id = $1
     LIMIT 1`,
    [Number(ownerUserId)]
  );
  const merchantId = merchant.rows[0]?.id;
  if (!merchantId) throw new AppError("MERCHANT_NOT_FOUND", { status: 404 });

  const r = await q(
    `SELECT
       u.id,
       u.full_name,
       u.phone,
       u.block,
       u.image_url,
       mda.is_active,
       mda.updated_at,
       cp.vehicle_type,
       cp.availability_status,
       COALESCE(cp.driver_type, '${DRIVER_TYPE_STORE}') AS driver_type
     FROM merchant_delivery_agent mda
     JOIN app_user u ON u.id = mda.delivery_user_id
     LEFT JOIN courier_profile cp ON cp.user_id = u.id
     WHERE mda.merchant_id = $1
     ORDER BY mda.is_active DESC, u.full_name ASC`,
    [Number(merchantId)]
  );
  return { merchantId: Number(merchantId), couriers: r.rows };
}

export async function createMerchantCourier({
  ownerUserId,
  deliveryUserId,
  vehicleType = null,
  coverageBlock = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const merchant = await getMerchantByOwnerTx(client, Number(ownerUserId));
    if (!merchant) throw new AppError("MERCHANT_NOT_FOUND", { status: 404 });

    const userCheck = await client.query(
      `SELECT id, role, full_name, phone, delivery_account_approved, is_account_disabled
       FROM app_user
       WHERE id = $1
       LIMIT 1`,
      [Number(deliveryUserId)]
    );
    const user = userCheck.rows[0];
    if (!user || String(user.role) !== "delivery") {
      throw new AppError("DELIVERY_USER_NOT_FOUND", { status: 404 });
    }
    if (user.is_account_disabled === true || user.delivery_account_approved !== true) {
      throw new AppError("DELIVERY_USER_NOT_ELIGIBLE", { status: 409 });
    }

    await syncCourierDriverAffiliation({
      userId: Number(deliveryUserId),
      driverType: DRIVER_TYPE_STORE,
      merchantId: Number(merchant.id),
      merchantIdSet: true,
      coverageBlock: coverageBlock || null,
      vehicleType,
      actorUserId: Number(ownerUserId),
      source: "owner",
      client,
    });

    await client.query("COMMIT");
    return {
      merchantId: Number(merchant.id),
      mapping: {
        merchant_id: Number(merchant.id),
        delivery_user_id: Number(deliveryUserId),
        is_active: true,
      },
      courier: user,
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function updateMerchantCourier({
  ownerUserId,
  deliveryUserId,
  isActive,
  availabilityStatus = null,
  vehicleType = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const merchant = await getMerchantByOwnerTx(client, Number(ownerUserId));
    if (!merchant) throw new AppError("MERCHANT_NOT_FOUND", { status: 404 });

    const update = await client.query(
      `UPDATE merchant_delivery_agent
       SET is_active = COALESCE($3::boolean, is_active),
           updated_at = NOW()
       WHERE merchant_id = $1
         AND delivery_user_id = $2
       RETURNING *`,
      [Number(merchant.id), Number(deliveryUserId), isActive]
    );
    if (!update.rows[0]) throw new AppError("MERCHANT_COURIER_NOT_FOUND", { status: 404 });

    await ensureCourierProfileTx(client, {
      userId: Number(deliveryUserId),
      driverType: DRIVER_TYPE_STORE,
      merchantId: Number(merchant.id),
      merchantIdSet: true,
    });
    if (availabilityStatus || vehicleType) {
      await client.query(
        `UPDATE courier_profile
         SET availability_status = COALESCE($2, availability_status),
             vehicle_type = COALESCE($3, vehicle_type),
             active_status = COALESCE($4::boolean, active_status),
             updated_at = NOW()
         WHERE user_id = $1`,
        [
          Number(deliveryUserId),
          availabilityStatus ? String(availabilityStatus).slice(0, 20) : null,
          vehicleType ? String(vehicleType).slice(0, 60) : null,
          typeof isActive === "boolean" ? isActive : null,
        ]
      );
    }

    await client.query("COMMIT");
    return { merchantId: Number(merchant.id), mapping: update.rows[0] };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function getMerchantDashboard(ownerUserId, { period, from, to } = {}) {
  const merchantResult = await q(
    `SELECT id, name
     FROM merchant
     WHERE owner_user_id = $1
     LIMIT 1`,
    [Number(ownerUserId)]
  );
  const merchant = merchantResult.rows[0];
  if (!merchant) throw new AppError("MERCHANT_NOT_FOUND", { status: 404 });
  const window = parseWindow({ period, from, to });

  const [totals, courierSplit] = await Promise.all([
    q(
      `SELECT
         COUNT(*)::int AS total_orders,
         COUNT(*) FILTER (WHERE status IN ('completed','delivered','delivered_by_courier','received_by_customer'))::int AS completed_orders,
         COUNT(*) FILTER (WHERE status IN ('cancelled','cancelled_by_store','cancelled_by_admin','cancelled_by_customer'))::int AS cancelled_orders,
         COUNT(*) FILTER (WHERE status IN ('approved','preparing','ready_for_delivery','on_the_way','arrived'))::int AS active_orders,
         COALESCE(SUM(total_amount),0)::numeric AS gross_sales,
         COALESCE(SUM(subtotal),0)::numeric AS subtotal_sales,
         COALESCE(AVG(total_amount),0)::numeric AS avg_order_value
       FROM customer_order
       WHERE merchant_id = $1
         AND created_at >= $2::timestamptz
         AND created_at <= $3::timestamptz`,
      [Number(merchant.id), window.start, window.end]
    ),
    q(
      `SELECT
         COALESCE(SUM(CASE WHEN courier_source = 'app' THEN 1 ELSE 0 END),0)::int AS app_courier_orders,
         COALESCE(SUM(CASE WHEN courier_source = 'merchant' THEN 1 ELSE 0 END),0)::int AS merchant_courier_orders
       FROM customer_order
       WHERE merchant_id = $1
         AND created_at >= $2::timestamptz
         AND created_at <= $3::timestamptz`,
      [Number(merchant.id), window.start, window.end]
    ),
  ]);

  const t = totals.rows[0] || {};
  const split = courierSplit.rows[0] || {};
  return {
    merchant: {
      id: Number(merchant.id),
      name: merchant.name,
    },
    window,
    kpis: {
      totalOrders: Number(t.total_orders || 0),
      completedOrders: Number(t.completed_orders || 0),
      cancelledOrders: Number(t.cancelled_orders || 0),
      activeOrders: Number(t.active_orders || 0),
      grossSales: toNumber(t.gross_sales, 0),
      subtotalSales: toNumber(t.subtotal_sales, 0),
      avgOrderValue: toNumber(t.avg_order_value, 0),
      appCourierOrders: Number(split.app_courier_orders || 0),
      merchantCourierOrders: Number(split.merchant_courier_orders || 0),
    },
  };
}

export async function getMerchantKpis(ownerUserId, { period, from, to } = {}) {
  const dashboard = await getMerchantDashboard(ownerUserId, { period, from, to });
  const merchantId = Number(dashboard.merchant.id);
  const window = dashboard.window;

  const [topProducts, topCategories] = await Promise.all([
    q(
      `SELECT
         oi.product_id,
         oi.product_name,
         COALESCE(SUM(oi.quantity),0)::numeric AS qty_sold,
         COALESCE(SUM(oi.line_total),0)::numeric AS gross_amount
       FROM order_item oi
       JOIN customer_order o ON o.id = oi.order_id
       WHERE o.merchant_id = $1
         AND o.created_at >= $2::timestamptz
         AND o.created_at <= $3::timestamptz
       GROUP BY oi.product_id, oi.product_name
       ORDER BY qty_sold DESC, gross_amount DESC
       LIMIT 15`,
      [merchantId, window.start, window.end]
    ),
    q(
      `SELECT
         mc.id AS category_id,
         mc.name AS category_name,
         COALESCE(SUM(oi.quantity),0)::numeric AS qty_sold,
         COALESCE(SUM(oi.line_total),0)::numeric AS gross_amount
       FROM order_item oi
       JOIN customer_order o ON o.id = oi.order_id
       LEFT JOIN product p ON p.id = oi.product_id
       LEFT JOIN merchant_category mc ON mc.id = p.category_id
       WHERE o.merchant_id = $1
         AND o.created_at >= $2::timestamptz
         AND o.created_at <= $3::timestamptz
       GROUP BY mc.id, mc.name
       ORDER BY gross_amount DESC
       LIMIT 12`,
      [merchantId, window.start, window.end]
    ),
  ]);

  return {
    ...dashboard,
    topProducts: topProducts.rows,
    topCategories: topCategories.rows,
  };
}

export async function getMerchantTopProducts(ownerUserId, options = {}) {
  const kpis = await getMerchantKpis(ownerUserId, options);
  return { merchant: kpis.merchant, window: kpis.window, rows: kpis.topProducts };
}

export async function getMerchantTopCategories(ownerUserId, options = {}) {
  const kpis = await getMerchantKpis(ownerUserId, options);
  return { merchant: kpis.merchant, window: kpis.window, rows: kpis.topCategories };
}

export async function getMerchantOrdersReports(
  ownerUserId,
  { period, from, to, status = null, limit = 120, offset = 0 } = {}
) {
  const merchant = await q(
    `SELECT id, name
     FROM merchant
     WHERE owner_user_id = $1
     LIMIT 1`,
    [Number(ownerUserId)]
  );
  const m = merchant.rows[0];
  if (!m) throw new AppError("MERCHANT_NOT_FOUND", { status: 404 });

  const window = parseWindow({ period, from, to });
  const params = [Number(m.id), window.start, window.end];
  let statusClause = "";
  if (status) {
    params.push(String(status));
    statusClause = `AND o.status = $${params.length}::order_status`;
  }
  params.push(Math.max(1, Math.min(300, Number(limit) || 120)));
  const limitIndex = params.length;
  params.push(Math.max(0, Number(offset) || 0));
  const offsetIndex = params.length;

  const rows = await q(
    `SELECT
       o.*,
       u.full_name AS delivery_full_name,
       u.phone AS delivery_phone
     FROM customer_order o
     LEFT JOIN app_user u ON u.id = o.delivery_user_id
     WHERE o.merchant_id = $1
       AND o.created_at >= $2::timestamptz
       AND o.created_at <= $3::timestamptz
       ${statusClause}
     ORDER BY o.created_at DESC, o.id DESC
     LIMIT $${limitIndex} OFFSET $${offsetIndex}`,
    params
  );

  return {
    merchant: { id: Number(m.id), name: m.name },
    window,
    orders: rows.rows,
  };
}

export async function getMerchantVerifiedReviews(
  ownerUserId,
  { limit = 40, offset = 0 } = {}
) {
  const merchant = await q(
    `SELECT id, name
     FROM merchant
     WHERE owner_user_id = $1
     LIMIT 1`,
    [Number(ownerUserId)]
  );
  const m = merchant.rows[0];
  if (!m) throw new AppError("MERCHANT_NOT_FOUND", { status: 404 });

  const safeLimit = Math.max(1, Math.min(120, Number(limit) || 40));
  const safeOffset = Math.max(0, Number(offset) || 0);

  const reviewsResult = await q(
    `SELECT
       r.id,
       r.order_id,
       r.merchant_id,
       r.customer_user_id,
       r.rating,
       r.review_text,
       r.is_verified,
       r.created_at,
       u.username,
       u.full_name,
       u.image_url
     FROM merchant_verified_review r
     JOIN app_user u ON u.id = r.customer_user_id
     WHERE r.merchant_id = $1
     ORDER BY r.created_at DESC, r.id DESC
     LIMIT $2 OFFSET $3`,
    [Number(m.id), safeLimit, safeOffset]
  );

  const rows = reviewsResult.rows;
  const reviews = await Promise.all(
    rows.map(async (row) => {
      const historyResult = await q(
        `SELECT
           id,
           status,
           total_amount,
           created_at
         FROM customer_order
         WHERE merchant_id = $1
           AND customer_user_id = $2
         ORDER BY created_at DESC, id DESC
         LIMIT 5`,
        [Number(m.id), Number(row.customer_user_id)]
      );

      return {
        id: Number(row.id),
        orderId: Number(row.order_id),
        merchantId: Number(row.merchant_id),
        customerUserId: Number(row.customer_user_id),
        rating: Number(row.rating),
        reviewText: row.review_text || null,
        isVerified: row.is_verified === true,
        createdAt: row.created_at,
        customer: {
          username: row.username || null,
          fullName: row.full_name || null,
          imageUrl: row.image_url || null,
        },
        customerOrderContext: {
          totalOrdersCount: historyResult.rows.length,
          recentOrders: historyResult.rows.map((order) => ({
            orderId: Number(order.id),
            status: String(order.status || ""),
            totalAmount: Number(order.total_amount || 0),
            createdAt: order.created_at,
          })),
        },
      };
    })
  );

  return {
    merchant: { id: Number(m.id), name: m.name },
    reviews,
    pagination: {
      limit: safeLimit,
      offset: safeOffset,
      nextOffset: rows.length >= safeLimit ? safeOffset + safeLimit : null,
    },
  };
}

export async function getDeliveryDispatchPolicy() {
  let row = null;
  try {
    const result = await q(
      `SELECT id, policy_key, config_json, is_active, updated_by_user_id, updated_at, created_at
       FROM delivery_dispatch_policy
       WHERE policy_key = 'default'
       ORDER BY updated_at DESC
       LIMIT 1`
    );
    row = result.rows[0] || null;
  } catch (error) {
    if (String(error?.code || "") !== "42P01") throw error;
  }
  return {
    policyKey: "default",
    config: normalizeDeliveryDispatchPolicyConfig(row?.config_json || {}),
    isActive: row?.is_active ?? true,
    updatedByUserId: row?.updated_by_user_id ? Number(row.updated_by_user_id) : null,
    updatedAt: row?.updated_at || null,
    createdAt: row?.created_at || null,
  };
}

export async function updateDeliveryDispatchPolicy(actorUserId, patch = {}) {
  const existing = await getDeliveryDispatchPolicy();
  const patchObject =
    patch && typeof patch === "object"
      ? patch.config && typeof patch.config === "object"
        ? patch.config
        : patch
      : {};
  const merged = normalizeDeliveryDispatchPolicyConfig({
    ...existing.config,
    ...patchObject,
    weights: {
      ...(existing.config?.weights || {}),
      ...((patchObject && patchObject.weights) || {}),
    },
    fallback: {
      ...(existing.config?.fallback || {}),
      ...((patchObject && patchObject.fallback) || {}),
    },
  });

  try {
    await q(
      `INSERT INTO delivery_dispatch_policy
        (policy_key, config_json, is_active, updated_by_user_id, updated_at, created_at)
       VALUES
        ('default', $1::jsonb, TRUE, $2, NOW(), NOW())
       ON CONFLICT (policy_key)
       DO UPDATE SET
         config_json = EXCLUDED.config_json,
         is_active = EXCLUDED.is_active,
         updated_by_user_id = EXCLUDED.updated_by_user_id,
         updated_at = NOW()`,
      [JSON.stringify(merged), Number(actorUserId)]
    );
  } catch (error) {
    if (String(error?.code || "") === "42P01") {
      throw new AppError("DELIVERY_DISPATCH_POLICY_MIGRATION_REQUIRED", {
        status: 503,
      });
    }
    throw error;
  }

  return getDeliveryDispatchPolicy();
}

const DEFAULT_RELIABILITY_POLICY_CONFIG = Object.freeze({
  windowDays: 180,
  baseScore: 70,
  weights: {
    completed: 4,
    cancelledByCustomer: -8,
    failedDelivery: -10,
    noAnswer: -9,
    complaints: -12,
  },
  thresholds: {
    trustedMin: 80,
    needsAttentionMax: 45,
  },
  warningThreshold: 50,
});

function clampNumber(value, fallback, min, max) {
  const num = Number(value);
  if (!Number.isFinite(num)) return fallback;
  return Math.max(min, Math.min(max, num));
}

function normalizeReliabilityPolicyConfig(input = {}) {
  const source = input && typeof input === "object" ? input : {};
  const sourceWeights =
    source.weights && typeof source.weights === "object" ? source.weights : {};
  const sourceThresholds =
    source.thresholds && typeof source.thresholds === "object"
      ? source.thresholds
      : {};

  const trustedMin = clampNumber(
    sourceThresholds.trustedMin,
    DEFAULT_RELIABILITY_POLICY_CONFIG.thresholds.trustedMin,
    0,
    100
  );
  const needsAttentionMax = clampNumber(
    sourceThresholds.needsAttentionMax,
    DEFAULT_RELIABILITY_POLICY_CONFIG.thresholds.needsAttentionMax,
    0,
    trustedMin
  );

  return {
    windowDays: Math.round(
      clampNumber(
        source.windowDays,
        DEFAULT_RELIABILITY_POLICY_CONFIG.windowDays,
        1,
        3650
      )
    ),
    baseScore: clampNumber(
      source.baseScore,
      DEFAULT_RELIABILITY_POLICY_CONFIG.baseScore,
      0,
      100
    ),
    weights: {
      completed: clampNumber(
        sourceWeights.completed,
        DEFAULT_RELIABILITY_POLICY_CONFIG.weights.completed,
        -50,
        50
      ),
      cancelledByCustomer: clampNumber(
        sourceWeights.cancelledByCustomer,
        DEFAULT_RELIABILITY_POLICY_CONFIG.weights.cancelledByCustomer,
        -50,
        50
      ),
      failedDelivery: clampNumber(
        sourceWeights.failedDelivery,
        DEFAULT_RELIABILITY_POLICY_CONFIG.weights.failedDelivery,
        -50,
        50
      ),
      noAnswer: clampNumber(
        sourceWeights.noAnswer,
        DEFAULT_RELIABILITY_POLICY_CONFIG.weights.noAnswer,
        -50,
        50
      ),
      complaints: clampNumber(
        sourceWeights.complaints,
        DEFAULT_RELIABILITY_POLICY_CONFIG.weights.complaints,
        -50,
        50
      ),
    },
    thresholds: {
      trustedMin,
      needsAttentionMax,
    },
    warningThreshold: clampNumber(
      source.warningThreshold,
      DEFAULT_RELIABILITY_POLICY_CONFIG.warningThreshold,
      0,
      100
    ),
  };
}

async function loadDefaultReliabilityPolicyRow() {
  const result = await q(
    `SELECT id, policy_key, config_json, is_active, updated_by_user_id, updated_at, created_at
     FROM customer_reliability_policy
     WHERE policy_key = 'default'
     ORDER BY updated_at DESC
     LIMIT 1`
  );
  return result.rows[0] || null;
}

export async function getCustomerReliabilityPolicy() {
  const row = await loadDefaultReliabilityPolicyRow();
  const config = normalizeReliabilityPolicyConfig(row?.config_json || {});
  return {
    policyKey: "default",
    config,
    isActive: row?.is_active ?? true,
    updatedByUserId: row?.updated_by_user_id ? Number(row.updated_by_user_id) : null,
    updatedAt: row?.updated_at || null,
    createdAt: row?.created_at || null,
  };
}

export async function updateCustomerReliabilityPolicy(actorUserId, patch = {}) {
  const existing = await getCustomerReliabilityPolicy();
  const patchObject =
    patch && typeof patch === "object"
      ? (patch.config && typeof patch.config === "object" ? patch.config : patch)
      : {};
  const merged = normalizeReliabilityPolicyConfig({
    ...existing.config,
    ...patchObject,
    weights: {
      ...(existing.config?.weights || {}),
      ...((patchObject && patchObject.weights) || {}),
    },
    thresholds: {
      ...(existing.config?.thresholds || {}),
      ...((patchObject && patchObject.thresholds) || {}),
    },
  });

  await q(
    `INSERT INTO customer_reliability_policy
      (policy_key, config_json, is_active, updated_by_user_id, updated_at, created_at)
     VALUES
      ('default', $1::jsonb, TRUE, $2, NOW(), NOW())
     ON CONFLICT (policy_key)
     DO UPDATE SET
       config_json = EXCLUDED.config_json,
       is_active = EXCLUDED.is_active,
       updated_by_user_id = EXCLUDED.updated_by_user_id,
       updated_at = NOW()`,
    [JSON.stringify(merged), Number(actorUserId)]
  );

  return getCustomerReliabilityPolicy();
}

export async function getMerchantCustomerReliability(ownerUserId, customerUserId) {
  const merchant = await q(
    `SELECT id, name
     FROM merchant
     WHERE owner_user_id = $1
     LIMIT 1`,
    [Number(ownerUserId)]
  );
  const m = merchant.rows[0];
  if (!m) throw new AppError("MERCHANT_NOT_FOUND", { status: 404 });

  const relation = await q(
    `SELECT 1
     FROM customer_order
     WHERE merchant_id = $1
       AND customer_user_id = $2
     LIMIT 1`,
    [Number(m.id), Number(customerUserId)]
  );
  if (!relation.rows[0]) {
    throw new AppError("CUSTOMER_NOT_FOUND_FOR_MERCHANT", { status: 404 });
  }

  const policy = (await getCustomerReliabilityPolicy()).config;
  const windowDays = Number(policy?.windowDays ?? 180);
  const baseScore = Number(policy?.baseScore ?? 70);
  const weights = policy?.weights || {};
  const thresholds = policy?.thresholds || {};
  const trustedMin = Number(thresholds?.trustedMin ?? 80);
  const needsAttentionMax = Number(thresholds?.needsAttentionMax ?? 45);
  const warningThreshold = Number(policy?.warningThreshold ?? 50);

  const statsResult = await q(
    `SELECT
       COUNT(*) FILTER (WHERE status IN ('completed','delivered','received_by_customer'))::int AS completed_count,
       COUNT(*) FILTER (WHERE status = 'cancelled_by_customer')::int AS cancelled_by_customer_count,
       COUNT(*) FILTER (WHERE status = 'failed_delivery')::int AS failed_delivery_count,
       COUNT(*) FILTER (WHERE status = 'cancelled_by_store')::int AS cancelled_by_store_count,
       MAX(CASE WHEN status IN ('completed','delivered','received_by_customer') THEN created_at END) AS last_successful_order_at
     FROM customer_order
     WHERE customer_user_id = $1
       AND created_at >= NOW() - ($2::text || ' days')::interval`,
    [Number(customerUserId), Math.max(1, windowDays)]
  );
  const stats = statsResult.rows[0] || {};
  const completed = Number(stats.completed_count || 0);
  const cancelledByCustomer = Number(stats.cancelled_by_customer_count || 0);
  const failedDelivery = Number(stats.failed_delivery_count || 0);
  const cancelledByStore = Number(stats.cancelled_by_store_count || 0);

  const scoreRaw =
    baseScore +
    completed * Number(weights?.completed ?? 4) +
    cancelledByCustomer * Number(weights?.cancelledByCustomer ?? -8) +
    failedDelivery * Number(weights?.failedDelivery ?? -10) +
    cancelledByStore * Number(weights?.complaints ?? -3);
  const score = Math.max(0, Math.min(100, scoreRaw));
  const reliabilityTier =
    score >= trustedMin ? "trusted" : score <= needsAttentionMax ? "needs_attention" : "medium";
  const warningRequired = score <= warningThreshold;

  await q(
    `INSERT INTO customer_reliability_snapshot
      (
        customer_user_id,
        score,
        reliability_tier,
        completed_orders_count,
        cancelled_by_customer_count,
        failed_delivery_count,
        no_answer_count,
        complaints_count,
        last_successful_order_at,
        warning_required,
        snapshot_json,
        computed_at,
        updated_at
      )
     VALUES
      ($1,$2,$3,$4,$5,$6,0,$7,$8,$9,$10::jsonb,NOW(),NOW())
     ON CONFLICT (customer_user_id)
     DO UPDATE SET
       score = EXCLUDED.score,
       reliability_tier = EXCLUDED.reliability_tier,
       completed_orders_count = EXCLUDED.completed_orders_count,
       cancelled_by_customer_count = EXCLUDED.cancelled_by_customer_count,
       failed_delivery_count = EXCLUDED.failed_delivery_count,
       complaints_count = EXCLUDED.complaints_count,
       last_successful_order_at = EXCLUDED.last_successful_order_at,
       warning_required = EXCLUDED.warning_required,
       snapshot_json = EXCLUDED.snapshot_json,
       computed_at = NOW(),
       updated_at = NOW()`,
    [
      Number(customerUserId),
      score,
      reliabilityTier,
      completed,
      cancelledByCustomer,
      failedDelivery,
      cancelledByStore,
      stats.last_successful_order_at || null,
      warningRequired,
      JSON.stringify({
        windowDays,
        baseScore,
        weights,
        trustedMin,
        needsAttentionMax,
        warningThreshold,
      }),
    ]
  );

  return {
    merchant: { id: Number(m.id), name: m.name },
    customerUserId: Number(customerUserId),
    score,
    tier: reliabilityTier,
    warningRequired,
    stats: {
      completedOrders: completed,
      cancelledByCustomer,
      failedDelivery,
      complaints: cancelledByStore,
      lastSuccessfulOrderAt: stats.last_successful_order_at || null,
    },
  };
}

async function merchantReceivableBreakdownByType(
  client,
  merchantId,
  { includePendingPayments = true } = {}
) {
  const ledgerByType = await client.query(
    `SELECT
       entry_type,
       COALESCE(SUM(CASE WHEN direction = 'debit' THEN amount ELSE 0 END),0)::numeric AS debit_total,
       COALESCE(SUM(CASE WHEN direction = 'credit' THEN amount ELSE 0 END),0)::numeric AS credit_total
     FROM merchant_receivables_ledger
     WHERE merchant_id = $1
     GROUP BY entry_type`,
    [Number(merchantId)]
  );

  const acc = {
    commissionDebit: 0,
    commissionCredit: 0,
    serviceDebit: 0,
    serviceCredit: 0,
    deliveryDebit: 0,
    deliveryCredit: 0,
    totalDebit: 0,
    totalCredit: 0,
  };

  for (const row of ledgerByType.rows) {
    const type = String(row.entry_type || "").toLowerCase();
    const debit = toNumber(row.debit_total, 0);
    const credit = toNumber(row.credit_total, 0);
    acc.totalDebit += debit;
    acc.totalCredit += credit;
    if (type === "commission") {
      acc.commissionDebit += debit;
      acc.commissionCredit += credit;
    } else if (type === "service_fee") {
      acc.serviceDebit += debit;
      acc.serviceCredit += credit;
    } else if (type === "delivery_fee") {
      acc.deliveryDebit += debit;
      acc.deliveryCredit += credit;
    }
  }

  const pendingPayments = includePendingPayments
    ? await client.query(
        `SELECT COALESCE(SUM(amount),0)::numeric AS pending_amount
         FROM merchant_payment_request
         WHERE merchant_id = $1
           AND status = 'pending'`,
        [Number(merchantId)]
      )
    : { rows: [{ pending_amount: 0 }] };

  return {
    commission: {
      debit: round2(acc.commissionDebit),
      credit: round2(acc.commissionCredit),
      outstanding: round2(acc.commissionDebit - acc.commissionCredit),
    },
    serviceFee: {
      debit: round2(acc.serviceDebit),
      credit: round2(acc.serviceCredit),
      outstanding: round2(acc.serviceDebit - acc.serviceCredit),
    },
    deliveryFee: {
      debit: round2(acc.deliveryDebit),
      credit: round2(acc.deliveryCredit),
      outstanding: round2(acc.deliveryDebit - acc.deliveryCredit),
    },
    totals: {
      debit: round2(acc.totalDebit),
      credit: round2(acc.totalCredit),
      outstanding: round2(acc.totalDebit - acc.totalCredit),
      pendingPayments: toNumber(pendingPayments.rows[0]?.pending_amount, 0),
    },
  };
}

async function merchantAppPayablesBreakdownByType(
  client,
  merchantId,
  { includePendingOutgoing = true } = {}
) {
  const ledgerByType = await client.query(
    `SELECT
       entry_type,
       COALESCE(SUM(CASE WHEN direction = 'debit' THEN amount ELSE 0 END),0)::numeric AS debit_total,
       COALESCE(SUM(CASE WHEN direction = 'credit' THEN amount ELSE 0 END),0)::numeric AS credit_total
     FROM merchant_app_payables_ledger
     WHERE merchant_id = $1
     GROUP BY entry_type`,
    [Number(merchantId)]
  );

  const acc = {
    totalDebit: 0,
    totalCredit: 0,
    orderShareDebit: 0,
    orderShareCredit: 0,
    adjustmentDebit: 0,
    adjustmentCredit: 0,
    settlementDebit: 0,
    settlementCredit: 0,
  };

  for (const row of ledgerByType.rows) {
    const type = String(row.entry_type || "").toLowerCase();
    const debit = toNumber(row.debit_total, 0);
    const credit = toNumber(row.credit_total, 0);
    acc.totalDebit += debit;
    acc.totalCredit += credit;
    if (type === "order_share") {
      acc.orderShareDebit += debit;
      acc.orderShareCredit += credit;
    } else if (type === "adjustment") {
      acc.adjustmentDebit += debit;
      acc.adjustmentCredit += credit;
    } else {
      acc.settlementDebit += debit;
      acc.settlementCredit += credit;
    }
  }

  const pendingOutgoing = includePendingOutgoing
    ? await client.query(
        `SELECT COALESCE(SUM(COALESCE(paid_amount, amount)),0)::numeric AS pending_amount
         FROM merchant_payment_request
         WHERE merchant_id = $1
           AND request_type = $2
           AND status IN ('approved_by_admin', 'assigned_for_payment', 'awaiting_store_confirmation')`,
        [Number(merchantId), REQUEST_TYPE_APP_PAYS_STORE]
      )
    : { rows: [{ pending_amount: 0 }] };

  return {
    orderShare: {
      debit: round2(acc.orderShareDebit),
      credit: round2(acc.orderShareCredit),
      outstanding: round2(acc.orderShareDebit - acc.orderShareCredit),
    },
    adjustment: {
      debit: round2(acc.adjustmentDebit),
      credit: round2(acc.adjustmentCredit),
      outstanding: round2(acc.adjustmentDebit - acc.adjustmentCredit),
    },
    settlement: {
      debit: round2(acc.settlementDebit),
      credit: round2(acc.settlementCredit),
      outstanding: round2(acc.settlementDebit - acc.settlementCredit),
    },
    totals: {
      debit: round2(acc.totalDebit),
      credit: round2(acc.totalCredit),
      outstanding: round2(acc.totalDebit - acc.totalCredit),
      pendingOutgoing: toNumber(pendingOutgoing.rows[0]?.pending_amount, 0),
    },
  };
}

export async function getMerchantReceivablesSummary(ownerUserId) {
  const client = await pool.connect();
  try {
    const merchant = await getMerchantByOwnerTx(client, Number(ownerUserId));
    if (!merchant) throw new AppError("MERCHANT_NOT_FOUND", { status: 404 });

    await syncMerchantReceivableBookTx(client, Number(merchant.id), {
      maxOrders: 3000,
    });

    const profileResult = await client.query(
      `SELECT *
       FROM merchant_billing_profile
       WHERE merchant_id = $1
       LIMIT 1`,
      [Number(merchant.id)]
    );
    const breakdown = await merchantReceivableBreakdownByType(
      client,
      Number(merchant.id)
    );
    const appPayablesBreakdown = await merchantAppPayablesBreakdownByType(
      client,
      Number(merchant.id)
    );
    const latestPayment = await client.query(
      `SELECT *
       FROM merchant_payment_request
       WHERE merchant_id = $1
         AND request_type = $2
       ORDER BY submitted_at DESC, id DESC
       LIMIT 1`,
      [Number(merchant.id), REQUEST_TYPE_STORE_PAYS_APP]
    );
    const pendingList = await client.query(
      `SELECT *
       FROM merchant_payment_request
       WHERE merchant_id = $1
         AND request_type = $2
         AND status IN ('pending_admin_confirmation','returned_for_revision','pending_admin_review','issue_reported_by_store')
       ORDER BY submitted_at DESC, id DESC
       LIMIT 20`,
      [Number(merchant.id), REQUEST_TYPE_STORE_PAYS_APP]
    );
    const pendingIncoming = await client.query(
      `SELECT *
       FROM merchant_payment_request
       WHERE merchant_id = $1
         AND request_type = $2
         AND status IN ('pending_admin_review','approved_by_admin','assigned_for_payment','awaiting_store_confirmation','issue_reported_by_store')
       ORDER BY submitted_at DESC, id DESC
       LIMIT 20`,
      [Number(merchant.id), REQUEST_TYPE_APP_PAYS_STORE]
    );
    const openInvoices = await listMerchantReceivableInvoicesTx(
      client,
      Number(merchant.id),
      { onlyOpen: true, limit: 500 }
    );
    const allInvoices = await listMerchantReceivableInvoicesTx(
      client,
      Number(merchant.id),
      { onlyOpen: false, limit: 500 }
    );

    return {
      merchant: {
        id: Number(merchant.id),
        name: merchant.name,
      },
      billingProfile: profileResult.rows[0] || null,
      breakdown,
      appPayablesBreakdown,
      storePaysApp: {
        breakdown,
        outstanding: toNumber(breakdown?.totals?.outstanding, 0),
        pendingPaymentRequests: pendingList.rows,
      },
      appPaysStore: {
        breakdown: appPayablesBreakdown,
        outstanding: toNumber(appPayablesBreakdown?.totals?.outstanding, 0),
        pendingPaymentRequests: pendingIncoming.rows,
      },
      latestPayment: latestPayment.rows[0] || null,
      pendingPaymentRequests: pendingList.rows,
      receivableInvoices: {
        openCount: openInvoices.length,
        totalCount: allInvoices.length,
        summary: summarizeInvoiceRows(openInvoices),
        rows: openInvoices,
      },
    };
  } finally {
    client.release();
  }
}

export async function listMerchantReceivablesLedger(
  ownerUserId,
  { limit = 100, offset = 0, ledgerType = "all" } = {}
) {
  const client = await pool.connect();
  try {
    const merchant = await getMerchantByOwnerTx(client, Number(ownerUserId));
    if (!merchant) throw new AppError("MERCHANT_NOT_FOUND", { status: 404 });

    await syncMerchantReceivableBookTx(client, Number(merchant.id), {
      maxOrders: 3000,
    });

    const safeLimit = Math.max(1, Math.min(500, Number(limit) || 100));
    const safeOffset = Math.max(0, Number(offset) || 0);
    const normalizedType = String(ledgerType || "all").trim().toLowerCase();

    const outgoingRows = await client.query(
      `SELECT *
       FROM merchant_receivables_ledger
       WHERE merchant_id = $1
       ORDER BY created_at DESC, id DESC
       LIMIT $2 OFFSET $3`,
      [
        Number(merchant.id),
        safeLimit,
        safeOffset,
      ]
    );
    const incomingRows = await client.query(
      `SELECT *
       FROM merchant_app_payables_ledger
       WHERE merchant_id = $1
       ORDER BY created_at DESC, id DESC
       LIMIT $2 OFFSET $3`,
      [
        Number(merchant.id),
        safeLimit,
        safeOffset,
      ]
    );
    const mappedOutgoing = outgoingRows.rows.map((row) => ({
      ...row,
      ledger_type: REQUEST_TYPE_STORE_PAYS_APP,
    }));
    const mappedIncoming = incomingRows.rows.map((row) => ({
      ...row,
      ledger_type: REQUEST_TYPE_APP_PAYS_STORE,
    }));
    let rows = [];
    if (normalizedType === REQUEST_TYPE_STORE_PAYS_APP) {
      rows = mappedOutgoing;
    } else if (normalizedType === REQUEST_TYPE_APP_PAYS_STORE) {
      rows = mappedIncoming;
    } else {
      rows = [...mappedOutgoing, ...mappedIncoming].sort((a, b) => {
        const aTime = new Date(a.created_at || 0).getTime();
        const bTime = new Date(b.created_at || 0).getTime();
        return bTime - aTime || Number(b.id || 0) - Number(a.id || 0);
      });
    }
    return {
      merchant: { id: Number(merchant.id), name: merchant.name },
      rows,
      outgoingRows: mappedOutgoing,
      incomingRows: mappedIncoming,
    };
  } finally {
    client.release();
  }
}

export async function createMerchantPaymentRequest({
  ownerUserId,
  paymentScope,
  amount,
  requestType = REQUEST_TYPE_STORE_PAYS_APP,
  proofFileUrl = null,
  note = null,
  paymentMethod = null,
  paymentMethodOther = null,
  paymentDate = null,
  referenceCode = null,
  receiverName = null,
  selectionMode = null,
  selectedInvoiceIds = [],
  targetAmount = null,
  confirmedAdjustedAmount = null,
  selectionMeta = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const merchant = await getMerchantByOwnerTx(client, Number(ownerUserId));
    if (!merchant) throw new AppError("MERCHANT_NOT_FOUND", { status: 404 });

    const normalizedRequestType = normalizePaymentRequestType(requestType);
    const scope =
      normalizedRequestType === REQUEST_TYPE_STORE_PAYS_APP
        ? "all"
        : normalizePaymentScope(paymentScope);
    const normalizedPaymentMethod = normalizePaymentMethod(paymentMethod);
    const normalizedPaymentDate = toIsoOrNull(paymentDate);
    if (!["commission", "delivery", "service", "all"].includes(scope)) {
      throw new AppError("INVALID_PAYMENT_SCOPE", { status: 400 });
    }
    let numericAmount = round2(toNumber(amount, 0));
    let resolvedSelectionMode = null;
    let resolvedSelectionMeta = parseJsonOrEmpty(selectionMeta);

    if (normalizedRequestType === REQUEST_TYPE_STORE_PAYS_APP) {
      await syncMerchantReceivableBookTx(client, Number(merchant.id), {
        maxOrders: 3000,
      });
      const preview = await buildMerchantPaymentSelectionPreviewTx(client, {
        merchantId: Number(merchant.id),
        selectionMode,
        selectedInvoiceIds,
        targetAmount:
          normalizeSelectionMode(selectionMode) === SELECTION_MODE_AUTO
            ? targetAmount
            : amount,
        confirmedAdjustedAmount,
      });
      if (preview.requiresAmountConfirmation) {
        throw new AppError("PAYMENT_REQUEST_AMOUNT_CONFIRMATION_REQUIRED", {
          status: 400,
          details: preview,
        });
      }
      numericAmount = round2(preview.finalizedAmount);
      resolvedSelectionMode = preview.selectionMode;
      resolvedSelectionMeta = {
        ...resolvedSelectionMeta,
        requestedAmount: preview.requestedAmount,
        finalizedAmount: preview.finalizedAmount,
        exactMatch: preview.exactMatch,
        adjustmentDirection: preview.adjustmentDirection,
        nearestLowerAmount: preview.nearestLowerAmount,
        nearestHigherAmount: preview.nearestHigherAmount,
        confirmedAdjustedAmount: preview.confirmedAdjustedAmount,
        selectedInvoiceIds: preview.selectedInvoiceIds,
        invoiceCount: preview.summary.invoicesCount,
        oldestIssuedAt: preview.summary.oldestIssuedAt,
        latestIssuedAt: preview.summary.latestIssuedAt,
        summary: preview.summary,
      };
    } else {
      const appPayablesBreakdown = await merchantAppPayablesBreakdownByType(
        client,
        Number(merchant.id),
        {
          includePendingOutgoing: false,
        }
      );
      const scopeOutstanding = toNumber(appPayablesBreakdown?.totals?.outstanding, 0);
      if (!(scopeOutstanding > 0)) {
        throw new AppError("NO_OUTSTANDING_RECEIVABLES", { status: 400 });
      }
      if (!(numericAmount > 0)) {
        throw new AppError("INVALID_PAYMENT_AMOUNT", { status: 400 });
      }
      if (numericAmount - scopeOutstanding > 0.01) {
        throw new AppError("PAYMENT_AMOUNT_EXCEEDS_OUTSTANDING", {
          status: 400,
          details: {
            requestedAmount: numericAmount,
            maxOutstanding: round2(scopeOutstanding),
            paymentScope: scope,
            requestType: normalizedRequestType,
          },
        });
      }
    }

    if (!(numericAmount > 0)) {
      throw new AppError("INVALID_PAYMENT_AMOUNT", { status: 400 });
    }

    const inserted = await client.query(
      `INSERT INTO merchant_payment_request
        (
          merchant_id,
          request_type,
          payment_scope,
          amount,
          requested_amount,
          paid_amount,
          currency,
          status,
          proof_file_url,
          note,
          payment_method,
          payment_method_other,
          payment_date,
          reference_code,
          receiver_name,
          selection_mode,
          selection_meta_json,
          created_by_user_id,
          updated_by_user_id,
          submitted_at
        )
       VALUES ($1,$2,$3,$4,$5,0,'IQD',$6,$7,$8,$9,$10,$11,$12,$13,$14,$15::jsonb,$16,$16,NOW())
       RETURNING *`,
      [
        Number(merchant.id),
        normalizedRequestType,
        scope,
        numericAmount,
        numericAmount,
        normalizedRequestType === REQUEST_TYPE_STORE_PAYS_APP
          ? REQUEST_STATUS.pendingAdminConfirmation
          : REQUEST_STATUS.pendingAdminReview,
        proofFileUrl || null,
        note || null,
        normalizedPaymentMethod,
        normalizedPaymentMethod === "other"
          ? String(paymentMethodOther || "").trim().slice(0, 120) || null
          : null,
        normalizedPaymentDate || null,
        referenceCode || null,
        receiverName || null,
        resolvedSelectionMode,
        JSON.stringify(resolvedSelectionMeta || {}),
        Number(ownerUserId),
      ]
    );

    await insertPaymentRequestStatusHistoryTx(client, {
      paymentRequestId: Number(inserted.rows[0].id),
      oldStatus: null,
      newStatus: String(inserted.rows[0].status || ""),
      changedByUserId: Number(ownerUserId),
      changedByRole: "owner",
      note: "Request created by merchant",
      metadata: {
        requestType: normalizedRequestType,
        paymentScope: scope,
        amount: numericAmount,
        selectionMode: resolvedSelectionMode,
        invoiceCount: Number(resolvedSelectionMeta?.invoiceCount || 0),
      },
    });

    const adminIds = await getBackofficeUserIdsTx(client);

    await client.query("COMMIT");
    return {
      paymentRequest: inserted.rows[0],
      merchant,
      adminRecipients: adminIds,
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function listAdminMerchantsReceivables({
  status = null,
  limit = 120,
  offset = 0,
} = {}) {
  const client = await pool.connect();
  try {
    let statusClause = "";
    if (status && ["clear", "due", "overdue"].includes(String(status).toLowerCase())) {
      statusClause = String(status).toLowerCase();
    }

    await backfillMissingOrderReceivablesTx(client, {
      maxOrders: 4000,
    });

    const rows = await client.query(
      `SELECT
         m.id AS merchant_id,
         m.name AS merchant_name,
         m.owner_user_id,
         mbp.commission_rate,
         mbp.service_fee_mode,
         mbp.service_fee_value,
         mbp.delivery_fee_mode,
         mbp.delivery_fee_value,
         mbp.app_delivery_enabled,
         mbp.merchant_delivery_enabled,
         COALESCE(ledger.total_debit,0)::numeric AS total_debit,
         COALESCE(ledger.total_credit,0)::numeric AS total_credit,
         COALESCE(ledger.outstanding,0)::numeric AS outstanding,
         COALESCE(app_ledger.total_debit,0)::numeric AS app_payables_total_debit,
         COALESCE(app_ledger.total_credit,0)::numeric AS app_payables_total_credit,
         COALESCE(app_ledger.outstanding,0)::numeric AS app_payables_outstanding,
         COALESCE(pr.pending_payment_requests,0)::int AS pending_payment_requests,
         COALESCE(pr.pending_outgoing_requests,0)::int AS pending_outgoing_requests
       FROM merchant m
       LEFT JOIN merchant_billing_profile mbp ON mbp.merchant_id = m.id
       LEFT JOIN LATERAL (
         SELECT
           COALESCE(SUM(CASE WHEN l.direction = 'debit' THEN l.amount ELSE 0 END),0)::numeric AS total_debit,
           COALESCE(SUM(CASE WHEN l.direction = 'credit' THEN l.amount ELSE 0 END),0)::numeric AS total_credit,
           COALESCE(SUM(CASE WHEN l.direction = 'debit' THEN l.amount ELSE -l.amount END),0)::numeric AS outstanding
         FROM merchant_receivables_ledger l
         WHERE l.merchant_id = m.id
       ) ledger ON TRUE
       LEFT JOIN LATERAL (
         SELECT
           COALESCE(SUM(CASE WHEN l.direction = 'debit' THEN l.amount ELSE 0 END),0)::numeric AS total_debit,
           COALESCE(SUM(CASE WHEN l.direction = 'credit' THEN l.amount ELSE 0 END),0)::numeric AS total_credit,
           COALESCE(SUM(CASE WHEN l.direction = 'debit' THEN l.amount ELSE -l.amount END),0)::numeric AS outstanding
         FROM merchant_app_payables_ledger l
         WHERE l.merchant_id = m.id
       ) app_ledger ON TRUE
       LEFT JOIN LATERAL (
         SELECT
           COUNT(*) FILTER (
             WHERE pr.request_type = 'store_pays_app'
               AND pr.status IN ('pending_admin_confirmation','returned_for_revision')
           )::int AS pending_payment_requests,
           COUNT(*) FILTER (
             WHERE pr.request_type = 'app_pays_store'
               AND pr.status IN ('pending_admin_review','approved_by_admin','assigned_for_payment','awaiting_store_confirmation','issue_reported_by_store')
           )::int AS pending_outgoing_requests
         FROM merchant_payment_request pr
         WHERE pr.merchant_id = m.id
       ) pr ON TRUE
       ORDER BY outstanding DESC, m.id DESC
       LIMIT $1 OFFSET $2`,
      [
        Math.max(1, Math.min(500, Number(limit) || 120)),
        Math.max(0, Number(offset) || 0),
      ]
    );

    const mapped = rows.rows.map((row) => {
      const outstanding = toNumber(row.outstanding, 0);
      const statusLabel = outstanding <= 0 ? "clear" : "due";
      return {
        ...row,
        total_debit: toNumber(row.total_debit, 0),
        total_credit: toNumber(row.total_credit, 0),
        outstanding,
        app_payables_total_debit: toNumber(row.app_payables_total_debit, 0),
        app_payables_total_credit: toNumber(row.app_payables_total_credit, 0),
        app_payables_outstanding: toNumber(row.app_payables_outstanding, 0),
        settlement_status: statusLabel,
      };
    });
    return {
      merchants:
        statusClause.length > 0
          ? mapped.filter((row) => row.settlement_status === statusClause)
          : mapped,
    };
  } finally {
    client.release();
  }
}

export async function getAdminMerchantReceivables(merchantId) {
  const client = await pool.connect();
  try {
    const merchantResult = await client.query(
      `SELECT m.*, mbp.*
       FROM merchant m
       LEFT JOIN merchant_billing_profile mbp ON mbp.merchant_id = m.id
       WHERE m.id = $1
       LIMIT 1`,
      [Number(merchantId)]
    );
    const merchant = merchantResult.rows[0];
    if (!merchant) throw new AppError("MERCHANT_NOT_FOUND", { status: 404 });

    await syncMerchantReceivableBookTx(client, Number(merchantId), {
      maxOrders: 3000,
    });

    const breakdown = await merchantReceivableBreakdownByType(
      client,
      Number(merchantId)
    );
    const appPayablesBreakdown = await merchantAppPayablesBreakdownByType(
      client,
      Number(merchantId)
    );
    const paymentRequests = await client.query(
      `SELECT *
       FROM merchant_payment_request
       WHERE merchant_id = $1
       ORDER BY submitted_at DESC, id DESC
       LIMIT 100`,
      [Number(merchantId)]
    );
    const ledger = await client.query(
      `SELECT *
       FROM merchant_receivables_ledger
       WHERE merchant_id = $1
       ORDER BY created_at DESC, id DESC
       LIMIT 200`,
      [Number(merchantId)]
    );
    const appPayablesLedger = await client.query(
      `SELECT *
       FROM merchant_app_payables_ledger
       WHERE merchant_id = $1
       ORDER BY created_at DESC, id DESC
       LIMIT 200`,
      [Number(merchantId)]
    );
    const invoices = await listMerchantReceivableInvoicesTx(
      client,
      Number(merchantId),
      {
        limit: 400,
      }
    );
    const paymentRequestIds = paymentRequests.rows.map((row) => Number(row.id));
    const paymentRequestInvoices = [];
    for (const id of paymentRequestIds.slice(0, 100)) {
      const rows = await fetchPaymentRequestInvoiceAllocationsTx(client, id);
      paymentRequestInvoices.push({
        payment_request_id: id,
        invoices: rows,
      });
    }

    return {
      merchant,
      breakdown,
      appPayablesBreakdown,
      paymentRequests: paymentRequests.rows,
      invoices,
      paymentRequestInvoices,
      ledger: ledger.rows,
      appPayablesLedger: appPayablesLedger.rows,
    };
  } finally {
    client.release();
  }
}

function mapPaymentRequestRow(row) {
  if (!row) return null;
  const status = normalizeRequestStatus(row.status);
  const requestType = normalizePaymentRequestType(row.request_type);
  const selectionMeta = parseJsonOrEmpty(row.selection_meta_json);
  const merchantEditableStatuses = requestType === REQUEST_TYPE_STORE_PAYS_APP
    ? [
        REQUEST_STATUS.pendingAdminConfirmation,
        REQUEST_STATUS.returnedForRevision,
        REQUEST_STATUS.rejectedByAdmin,
      ]
    : [
        REQUEST_STATUS.pendingAdminReview,
        REQUEST_STATUS.returnedForRevision,
        REQUEST_STATUS.issueReportedByStore,
        REQUEST_STATUS.rejectedByAdmin,
      ];
  const canEditByMerchant =
    row.is_locked !== true &&
    merchantEditableStatuses.includes(status);
  const canConfirmByMerchant =
    row.is_locked !== true &&
    requestType === REQUEST_TYPE_APP_PAYS_STORE &&
    status === REQUEST_STATUS.awaitingStoreConfirmation;
  return {
    ...row,
    status,
    request_type: requestType,
    amount: toNumber(row.amount, 0),
    requested_amount: toNumber(row.requested_amount, toNumber(row.amount, 0)),
    paid_amount: toNumber(row.paid_amount, 0),
    payment_method: normalizePaymentMethod(row.payment_method) || row.payment_method,
    payment_method_other: row.payment_method_other || null,
    payment_date: row.payment_date ? toIsoOrNull(row.payment_date) : null,
    selection_mode: row.selection_mode || null,
    selection_meta_json: selectionMeta,
    linked_invoice_count: Number(selectionMeta?.invoiceCount || 0),
    can_edit_by_merchant: canEditByMerchant,
    can_confirm_by_merchant: canConfirmByMerchant,
    is_locked: row.is_locked === true,
  };
}

async function fetchPaymentRequestHistoryTx(client, paymentRequestId) {
  const r = await client.query(
    `SELECT h.*,
            u.full_name AS changed_by_name
     FROM merchant_payment_request_status_history h
     LEFT JOIN app_user u ON u.id = h.changed_by_user_id
     WHERE h.payment_request_id = $1
     ORDER BY h.created_at ASC, h.id ASC`,
    [Number(paymentRequestId)]
  );
  return r.rows;
}

export async function listMerchantPaymentRequests(
  ownerUserId,
  { requestType = null, status = null, limit = 100, offset = 0 } = {}
) {
  const client = await pool.connect();
  try {
    const merchant = await getMerchantByOwnerTx(client, Number(ownerUserId));
    if (!merchant) throw new AppError("MERCHANT_NOT_FOUND", { status: 404 });
    await syncMerchantReceivableBookTx(client, Number(merchant.id), {
      maxOrders: 3000,
    });

    const where = [`merchant_id = $1`];
    const params = [Number(merchant.id)];
    if (requestType) {
      params.push(normalizePaymentRequestType(requestType));
      where.push(`request_type = $${params.length}`);
    }
    if (status) {
      params.push(normalizeRequestStatus(status));
      where.push(`status = $${params.length}`);
    }
    params.push(Math.max(1, Math.min(300, Number(limit) || 100)));
    const limitIndex = params.length;
    params.push(Math.max(0, Number(offset) || 0));
    const offsetIndex = params.length;

    const rows = await client.query(
      `SELECT *
       FROM merchant_payment_request
       WHERE ${where.join(" AND ")}
       ORDER BY submitted_at DESC, id DESC
       LIMIT $${limitIndex} OFFSET $${offsetIndex}`,
      params
    );
    return {
      merchant: { id: Number(merchant.id), name: merchant.name },
      requests: rows.rows.map(mapPaymentRequestRow),
    };
  } finally {
    client.release();
  }
}

export async function getMerchantPaymentRequestDetails(ownerUserId, paymentRequestId) {
  const client = await pool.connect();
  try {
    const merchant = await getMerchantByOwnerTx(client, Number(ownerUserId));
    if (!merchant) throw new AppError("MERCHANT_NOT_FOUND", { status: 404 });
    await syncMerchantReceivableBookTx(client, Number(merchant.id), {
      maxOrders: 3000,
    });

    const row = await client.query(
      `SELECT *
       FROM merchant_payment_request
       WHERE id = $1
         AND merchant_id = $2
       LIMIT 1`,
      [Number(paymentRequestId), Number(merchant.id)]
    );
    const request = row.rows[0];
    if (!request) throw new AppError("PAYMENT_REQUEST_NOT_FOUND", { status: 404 });
    const history = await fetchPaymentRequestHistoryTx(client, Number(paymentRequestId));
    const invoices = await fetchPaymentRequestInvoiceAllocationsTx(
      client,
      Number(paymentRequestId)
    );
    return {
      merchant: { id: Number(merchant.id), name: merchant.name },
      request: mapPaymentRequestRow(request),
      history,
      invoices,
    };
  } finally {
    client.release();
  }
}

export async function listMerchantOpenReceivableInvoices(
  ownerUserId,
  { limit = 500, offset = 0, onlyOpen = true, period = "all", from = null, to = null } = {}
) {
  const client = await pool.connect();
  try {
    const merchant = await getMerchantByOwnerTx(client, Number(ownerUserId));
    if (!merchant) throw new AppError("MERCHANT_NOT_FOUND", { status: 404 });
    await syncMerchantReceivableBookTx(client, Number(merchant.id), {
      maxOrders: 3000,
    });
    const window = parseWindow({ period, from, to });
    const invoices = await listMerchantReceivableInvoicesTx(client, Number(merchant.id), {
      onlyOpen,
      limit,
      offset,
      window,
    });
    return {
      merchant: {
        id: Number(merchant.id),
        name: merchant.name,
      },
      window,
      summary: summarizeInvoiceRows(invoices),
      invoices,
      pagination: {
        limit: sanitizeLimit(limit, 500, 2000),
        offset: sanitizeOffset(offset, 0),
        total: invoices.length,
      },
    };
  } finally {
    client.release();
  }
}

export async function previewMerchantPaymentSelection({
  ownerUserId,
  selectionMode,
  selectedInvoiceIds = [],
  targetAmount = null,
  confirmedAdjustedAmount = null,
  amount = null,
}) {
  const client = await pool.connect();
  try {
    const merchant = await getMerchantByOwnerTx(client, Number(ownerUserId));
    if (!merchant) throw new AppError("MERCHANT_NOT_FOUND", { status: 404 });
    await syncMerchantReceivableBookTx(client, Number(merchant.id), {
      maxOrders: 3000,
    });
    const preview = await buildMerchantPaymentSelectionPreviewTx(client, {
      merchantId: Number(merchant.id),
      selectionMode,
      selectedInvoiceIds,
      targetAmount:
        normalizeSelectionMode(selectionMode) === SELECTION_MODE_AUTO
          ? targetAmount
          : amount,
      confirmedAdjustedAmount,
    });
    return {
      merchant: {
        id: Number(merchant.id),
        name: merchant.name,
      },
      preview,
    };
  } finally {
    client.release();
  }
}

export async function getMerchantPaymentRequestInvoices(ownerUserId, paymentRequestId) {
  const client = await pool.connect();
  try {
    const merchant = await getMerchantByOwnerTx(client, Number(ownerUserId));
    if (!merchant) throw new AppError("MERCHANT_NOT_FOUND", { status: 404 });
    const current = await client.query(
      `SELECT *
       FROM merchant_payment_request
       WHERE id = $1
         AND merchant_id = $2
       LIMIT 1`,
      [Number(paymentRequestId), Number(merchant.id)]
    );
    if (!current.rows[0]) {
      throw new AppError("PAYMENT_REQUEST_NOT_FOUND", { status: 404 });
    }
    const invoices = await fetchPaymentRequestInvoiceAllocationsTx(
      client,
      Number(paymentRequestId)
    );
    return {
      merchant: {
        id: Number(merchant.id),
        name: merchant.name,
      },
      request: mapPaymentRequestRow(current.rows[0]),
      invoices,
    };
  } finally {
    client.release();
  }
}

export async function getAdminPaymentRequestInvoices(paymentRequestId) {
  const client = await pool.connect();
  try {
    const current = await getPaymentRequestWithMerchantTx(client, Number(paymentRequestId));
    const invoices = await fetchPaymentRequestInvoiceAllocationsTx(
      client,
      Number(paymentRequestId)
    );
    return {
      merchant: {
        id: Number(current.merchant_id),
        name: current.merchant_name,
        owner_user_id: current.owner_user_id,
      },
      request: mapPaymentRequestRow(current),
      invoices,
    };
  } finally {
    client.release();
  }
}

export async function updateMerchantPaymentRequest({
  ownerUserId,
  paymentRequestId,
  amount = null,
  paymentScope = null,
  note = null,
  paymentMethod = null,
  paymentMethodOther = null,
  paymentDate = null,
  referenceCode = null,
  receiverName = null,
  proofFileUrl = null,
  selectionMode = null,
  selectedInvoiceIds = [],
  targetAmount = null,
  confirmedAdjustedAmount = null,
  selectionMeta = null,
  resubmit = false,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const merchant = await getMerchantByOwnerTx(client, Number(ownerUserId));
    if (!merchant) throw new AppError("MERCHANT_NOT_FOUND", { status: 404 });

    const currentResult = await client.query(
      `SELECT *
       FROM merchant_payment_request
       WHERE id = $1
         AND merchant_id = $2
       FOR UPDATE`,
      [Number(paymentRequestId), Number(merchant.id)]
    );
    const current = currentResult.rows[0];
    if (!current) throw new AppError("PAYMENT_REQUEST_NOT_FOUND", { status: 404 });
    if (current.is_locked === true) {
      throw new AppError("PAYMENT_REQUEST_LOCKED", { status: 409 });
    }
    const requestType = normalizePaymentRequestType(current.request_type);
    const currentStatus = normalizeRequestStatus(current.status);
    await syncMerchantReceivableBookTx(client, Number(merchant.id), {
      maxOrders: 3000,
    });

    const editableStatuses = requestType === REQUEST_TYPE_STORE_PAYS_APP
      ? [REQUEST_STATUS.pendingAdminConfirmation, REQUEST_STATUS.returnedForRevision, REQUEST_STATUS.rejectedByAdmin]
      : [
          REQUEST_STATUS.pendingAdminReview,
          REQUEST_STATUS.returnedForRevision,
          REQUEST_STATUS.issueReportedByStore,
          REQUEST_STATUS.rejectedByAdmin,
        ];
    if (!editableStatuses.includes(currentStatus)) {
      throw new AppError("PAYMENT_REQUEST_NOT_EDITABLE", { status: 409 });
    }

    const nextScope =
      requestType === REQUEST_TYPE_STORE_PAYS_APP
        ? "all"
        : paymentScope
        ? normalizePaymentScope(paymentScope)
        : normalizePaymentScope(current.payment_scope);
    const normalizedPaymentMethod =
      paymentMethod == null
        ? normalizePaymentMethod(current.payment_method)
        : normalizePaymentMethod(paymentMethod);
    const normalizedPaymentDate = paymentDate == null
      ? toIsoOrNull(current.payment_date)
      : toIsoOrNull(paymentDate);
    let nextAmount =
      amount == null
        ? toNumber(current.requested_amount, toNumber(current.amount, 0))
        : round2(toNumber(amount, 0));
    let resolvedSelectionMode =
      requestType === REQUEST_TYPE_STORE_PAYS_APP
        ? normalizeSelectionMode(selectionMode ?? current.selection_mode)
        : null;
    let resolvedSelectionMeta = {
      ...parseJsonOrEmpty(current.selection_meta_json),
      ...parseJsonOrEmpty(selectionMeta),
    };

    if (requestType === REQUEST_TYPE_STORE_PAYS_APP) {
      const preview = await buildMerchantPaymentSelectionPreviewTx(client, {
        merchantId: Number(merchant.id),
        selectionMode: resolvedSelectionMode,
        selectedInvoiceIds:
          selectedInvoiceIds && selectedInvoiceIds.length > 0
            ? selectedInvoiceIds
            : resolvedSelectionMeta.selectedInvoiceIds || [],
        targetAmount:
          resolvedSelectionMode === SELECTION_MODE_AUTO
            ? targetAmount ?? amount ?? resolvedSelectionMeta.requestedAmount
            : amount ?? resolvedSelectionMeta.finalizedAmount,
        confirmedAdjustedAmount:
          confirmedAdjustedAmount ?? resolvedSelectionMeta.confirmedAdjustedAmount,
      });
      if (preview.requiresAmountConfirmation) {
        throw new AppError("PAYMENT_REQUEST_AMOUNT_CONFIRMATION_REQUIRED", {
          status: 400,
          details: preview,
        });
      }
      nextAmount = round2(preview.finalizedAmount);
      resolvedSelectionMode = preview.selectionMode;
      resolvedSelectionMeta = {
        ...resolvedSelectionMeta,
        requestedAmount: preview.requestedAmount,
        finalizedAmount: preview.finalizedAmount,
        exactMatch: preview.exactMatch,
        adjustmentDirection: preview.adjustmentDirection,
        nearestLowerAmount: preview.nearestLowerAmount,
        nearestHigherAmount: preview.nearestHigherAmount,
        confirmedAdjustedAmount: preview.confirmedAdjustedAmount,
        selectedInvoiceIds: preview.selectedInvoiceIds,
        invoiceCount: preview.summary.invoicesCount,
        oldestIssuedAt: preview.summary.oldestIssuedAt,
        latestIssuedAt: preview.summary.latestIssuedAt,
        summary: preview.summary,
      };
    } else {
      const appPayablesBreakdown = await merchantAppPayablesBreakdownByType(
        client,
        Number(merchant.id),
        {
          includePendingOutgoing: false,
        }
      );
      const scopeOutstanding = toNumber(appPayablesBreakdown?.totals?.outstanding, 0);
      if (!(scopeOutstanding > 0)) {
        throw new AppError("NO_OUTSTANDING_RECEIVABLES", { status: 400 });
      }
      if (!(nextAmount > 0)) {
        throw new AppError("INVALID_PAYMENT_AMOUNT", { status: 400 });
      }
      if (nextAmount - scopeOutstanding > 0.01) {
        throw new AppError("PAYMENT_AMOUNT_EXCEEDS_OUTSTANDING", {
          status: 400,
          details: {
            requestedAmount: nextAmount,
            maxOutstanding: round2(scopeOutstanding),
            paymentScope: nextScope,
            requestType,
          },
        });
      }
    }

    if (!(nextAmount > 0)) {
      throw new AppError("INVALID_PAYMENT_AMOUNT", { status: 400 });
    }

    let nextStatus = currentStatus;
    if (resubmit === true) {
      nextStatus =
        requestType === REQUEST_TYPE_STORE_PAYS_APP
          ? REQUEST_STATUS.pendingAdminConfirmation
          : REQUEST_STATUS.pendingAdminReview;
    }

    const updated = await client.query(
      `UPDATE merchant_payment_request
       SET payment_scope = $2,
           amount = $3,
           requested_amount = $3,
           note = COALESCE($4, note),
           payment_method = COALESCE($5, payment_method),
           payment_method_other = COALESCE($6, payment_method_other),
           payment_date = COALESCE($7, payment_date),
           reference_code = COALESCE($8, reference_code),
           receiver_name = COALESCE($9, receiver_name),
           proof_file_url = COALESCE($10, proof_file_url),
           selection_mode = COALESCE($11, selection_mode),
           selection_meta_json = COALESCE($12::jsonb, selection_meta_json),
           status = $13,
           updated_by_user_id = $14
       WHERE id = $1
       RETURNING *`,
      [
        Number(paymentRequestId),
        nextScope,
        nextAmount,
        note,
        normalizedPaymentMethod,
        normalizedPaymentMethod == "other"
          ? String(paymentMethodOther || "").trim().slice(0, 120) || null
          : null,
        normalizedPaymentDate,
        referenceCode,
        receiverName,
        proofFileUrl,
        resolvedSelectionMode,
        JSON.stringify(resolvedSelectionMeta || {}),
        nextStatus,
        Number(ownerUserId),
      ]
    );
    const row = updated.rows[0];
    if (!row) throw new AppError("PAYMENT_REQUEST_UPDATE_FAILED", { status: 500 });

    if (currentStatus !== nextStatus) {
      await insertPaymentRequestStatusHistoryTx(client, {
        paymentRequestId: Number(paymentRequestId),
        oldStatus: currentStatus,
        newStatus: nextStatus,
        changedByUserId: Number(ownerUserId),
        changedByRole: "owner",
        note: resubmit === true ? "Merchant resubmitted request" : "Merchant updated request",
        metadata: {
          paymentScope: nextScope,
          amount: nextAmount,
          selectionMode: resolvedSelectionMode,
          invoiceCount: Number(resolvedSelectionMeta?.invoiceCount || 0),
        },
      });
    }

    await client.query("COMMIT");
    return {
      merchant: { id: Number(merchant.id), name: merchant.name },
      request: mapPaymentRequestRow(row),
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function merchantConfirmPaymentRequestReceived({
  ownerUserId,
  paymentRequestId,
  note = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const merchant = await getMerchantByOwnerTx(client, Number(ownerUserId));
    if (!merchant) throw new AppError("MERCHANT_NOT_FOUND", { status: 404 });

    const current = await client.query(
      `SELECT *
       FROM merchant_payment_request
       WHERE id = $1
         AND merchant_id = $2
       FOR UPDATE`,
      [Number(paymentRequestId), Number(merchant.id)]
    );
    const row = current.rows[0];
    if (!row) throw new AppError("PAYMENT_REQUEST_NOT_FOUND", { status: 404 });
    if (normalizePaymentRequestType(row.request_type) !== REQUEST_TYPE_APP_PAYS_STORE) {
      throw new AppError("PAYMENT_REQUEST_INVALID_TYPE", { status: 409 });
    }
    if (normalizeRequestStatus(row.status) !== REQUEST_STATUS.awaitingStoreConfirmation) {
      throw new AppError("PAYMENT_REQUEST_NOT_AWAITING_STORE_CONFIRMATION", { status: 409 });
    }
    if (row.is_locked === true) throw new AppError("PAYMENT_REQUEST_LOCKED", { status: 409 });

    const paidAmount = round2(
      toNumber(row.paid_amount, 0) > 0
        ? toNumber(row.paid_amount, 0)
        : toNumber(row.amount, 0)
    );
    if (!(paidAmount > 0)) {
      throw new AppError("PAYMENT_REQUEST_INVALID_PAID_AMOUNT", { status: 409 });
    }

    await appendMerchantAppPayablesLedgerEntryTx(client, {
      merchantId: Number(merchant.id),
      orderId: null,
      entryType: "settlement",
      amount: paidAmount,
      direction: "credit",
      referenceType: "payment_request",
      referenceId: Number(row.id),
      note: note || "Store confirmed receipt",
    });

    const updated = await updatePaymentRequestStatusTx(client, {
      paymentRequestId: Number(row.id),
      fromStatuses: [REQUEST_STATUS.awaitingStoreConfirmation],
      toStatus: REQUEST_STATUS.confirmedReceivedByStore,
      actorUserId: Number(ownerUserId),
      actorRole: "owner",
      note: note || "Store confirmed receiving payment",
      metadata: { paidAmount },
      patch: {
        final_confirmed_at: "NOW()",
        final_confirmed_by_user_id: Number(ownerUserId),
      },
      lockRequest: true,
    });

    await client.query("COMMIT");
    return {
      merchant: { id: Number(merchant.id), name: merchant.name },
      request: mapPaymentRequestRow(updated),
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function merchantReportPaymentRequestIssue({
  ownerUserId,
  paymentRequestId,
  issueNote = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const merchant = await getMerchantByOwnerTx(client, Number(ownerUserId));
    if (!merchant) throw new AppError("MERCHANT_NOT_FOUND", { status: 404 });
    const current = await client.query(
      `SELECT *
       FROM merchant_payment_request
       WHERE id = $1
         AND merchant_id = $2
       FOR UPDATE`,
      [Number(paymentRequestId), Number(merchant.id)]
    );
    const row = current.rows[0];
    if (!row) throw new AppError("PAYMENT_REQUEST_NOT_FOUND", { status: 404 });
    if (normalizePaymentRequestType(row.request_type) !== REQUEST_TYPE_APP_PAYS_STORE) {
      throw new AppError("PAYMENT_REQUEST_INVALID_TYPE", { status: 409 });
    }

    const updated = await updatePaymentRequestStatusTx(client, {
      paymentRequestId: Number(row.id),
      fromStatuses: [REQUEST_STATUS.awaitingStoreConfirmation],
      toStatus: REQUEST_STATUS.issueReportedByStore,
      actorUserId: Number(ownerUserId),
      actorRole: "owner",
      note: issueNote || "Store reported payment issue",
      patch: {
        issue_note: issueNote || null,
        is_locked: false,
      },
      metadata: { issueNote: issueNote || null },
      lockRequest: false,
    });
    await client.query("COMMIT");
    return {
      merchant: { id: Number(merchant.id), name: merchant.name },
      request: mapPaymentRequestRow(updated),
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function updateMerchantBillingProfile({
  client: externalClient = null,
  adminUserId,
  merchantId,
  commissionType = null,
  commissionValue = null,
  commissionRate = null,
  commissionModel = null,
  monthlySubscriptionAmount = null,
  serviceFeeType = null,
  serviceFeeMode = null,
  serviceFeeValue = null,
  deliveryFeeMode = null,
  appDeliveryFeeValue = null,
  storeDeliveryFeeValue = null,
  deliveryFeeValue = null,
  appDeliveryEnabled = null,
  merchantDeliveryEnabled = null,
  settlementCycle = null,
  distributionPolicy = null,
  gracePeriodDays = null,
  effectiveFrom = null,
  changeKind = "admin_update",
}) {
  const client = externalClient || (await pool.connect());
  const ownsTransaction = externalClient == null;
  try {
    if (ownsTransaction) {
      await client.query("BEGIN");
    }
    const currentResult = await client.query(
      `SELECT *
       FROM merchant_billing_profile
       WHERE merchant_id = $1
       LIMIT 1
       FOR UPDATE`,
      [Number(merchantId)]
    );
    const previousProfile = normalizeMerchantBillingProfile(
      currentResult.rows[0] || { merchant_id: Number(merchantId) }
    );
    const nextProfile = {
      ...previousProfile,
      commissionType:
        commissionType == null ? previousProfile.commissionType : String(commissionType),
      commissionModel:
        commissionModel == null
          ? previousProfile.commissionModel
          : String(commissionModel),
      commissionValue:
        commissionValue == null
          ? commissionRate == null
            ? previousProfile.commissionValue
            : round2(toNumber(commissionRate, previousProfile.commissionRate) * 100)
          : round2(toNumber(commissionValue, previousProfile.commissionValue)),
      monthlySubscriptionAmount:
        monthlySubscriptionAmount == null
          ? previousProfile.monthlySubscriptionAmount
          : round2(
              toNumber(
                monthlySubscriptionAmount,
                previousProfile.monthlySubscriptionAmount
              )
            ),
      serviceFeeType:
        serviceFeeType == null
          ? serviceFeeMode == null
            ? previousProfile.serviceFeeType
            : String(serviceFeeMode)
          : String(serviceFeeType),
      serviceFeeValue:
        serviceFeeValue == null
          ? previousProfile.serviceFeeValue
          : round2(toNumber(serviceFeeValue, previousProfile.serviceFeeValue)),
      deliveryFeeMode:
        deliveryFeeMode == null ? previousProfile.deliveryFeeMode : String(deliveryFeeMode),
      appDeliveryFeeValue:
        appDeliveryFeeValue == null
          ? deliveryFeeValue == null
            ? previousProfile.appDeliveryFeeValue
            : round2(toNumber(deliveryFeeValue, previousProfile.appDeliveryFeeValue))
          : round2(toNumber(appDeliveryFeeValue, previousProfile.appDeliveryFeeValue)),
      storeDeliveryFeeValue:
        storeDeliveryFeeValue == null
          ? previousProfile.storeDeliveryFeeValue
          : round2(toNumber(storeDeliveryFeeValue, previousProfile.storeDeliveryFeeValue)),
      appDeliveryEnabled:
        typeof appDeliveryEnabled === "boolean"
          ? appDeliveryEnabled
          : previousProfile.appDeliveryEnabled,
      merchantDeliveryEnabled:
        typeof merchantDeliveryEnabled === "boolean"
          ? merchantDeliveryEnabled
          : previousProfile.merchantDeliveryEnabled,
      settlementCycle: settlementCycle ?? previousProfile.settlementCycle,
      distributionPolicy: distributionPolicy ?? previousProfile.distributionPolicy,
      gracePeriodDays:
        gracePeriodDays == null
          ? previousProfile.gracePeriodDays
          : Math.max(0, Number(gracePeriodDays) || 0),
      effectiveFrom: effectiveFrom || new Date().toISOString(),
      profileVersion: Math.max(1, Number(previousProfile.profileVersion || 0) + 1),
    };
    nextProfile.commissionType = normalizeMerchantBillingProfile(nextProfile).commissionType;
    nextProfile.commissionModel = normalizeMerchantBillingProfile(nextProfile).commissionModel;
    nextProfile.serviceFeeType = normalizeMerchantBillingProfile(nextProfile).serviceFeeType;
    nextProfile.deliveryFeeMode = normalizeMerchantBillingProfile(nextProfile).deliveryFeeMode;
    nextProfile.monthlySubscriptionAmount = normalizeMerchantBillingProfile(nextProfile).monthlySubscriptionAmount;

    const upserted = await client.query(
      `INSERT INTO merchant_billing_profile
        (
          merchant_id,
          commission_type,
          commission_value,
          commission_rate,
          commission_model,
          monthly_subscription_amount,
          service_fee_type,
          service_fee_mode,
          service_fee_value,
          delivery_fee_mode,
          app_delivery_fee_value,
          store_delivery_fee_value,
          delivery_fee_value,
          app_delivery_enabled,
          merchant_delivery_enabled,
          settlement_cycle,
          distribution_policy,
          grace_period_days,
          effective_from,
          profile_version,
          updated_by_user_id,
          updated_at
        )
       VALUES
        (
          $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19::timestamptz,$20,$21,NOW()
        )
       ON CONFLICT (merchant_id)
       DO UPDATE
         SET commission_type = EXCLUDED.commission_type,
             commission_value = EXCLUDED.commission_value,
             commission_rate = EXCLUDED.commission_rate,
             commission_model = EXCLUDED.commission_model,
             monthly_subscription_amount = EXCLUDED.monthly_subscription_amount,
             service_fee_type = EXCLUDED.service_fee_type,
             service_fee_mode = EXCLUDED.service_fee_mode,
             service_fee_value = EXCLUDED.service_fee_value,
             delivery_fee_mode = EXCLUDED.delivery_fee_mode,
             app_delivery_fee_value = EXCLUDED.app_delivery_fee_value,
             store_delivery_fee_value = EXCLUDED.store_delivery_fee_value,
             delivery_fee_value = EXCLUDED.delivery_fee_value,
             app_delivery_enabled = EXCLUDED.app_delivery_enabled,
             merchant_delivery_enabled = EXCLUDED.merchant_delivery_enabled,
             settlement_cycle = EXCLUDED.settlement_cycle,
             distribution_policy = EXCLUDED.distribution_policy,
             grace_period_days = EXCLUDED.grace_period_days,
             effective_from = EXCLUDED.effective_from,
             profile_version = EXCLUDED.profile_version,
             updated_by_user_id = EXCLUDED.updated_by_user_id,
             updated_at = NOW()
       RETURNING *`,
      [
        Number(merchantId),
        nextProfile.commissionType,
        nextProfile.commissionValue,
        nextProfile.commissionType === "percentage"
          ? round2(nextProfile.commissionValue / 100)
          : 0,
        nextProfile.commissionModel,
        nextProfile.monthlySubscriptionAmount,
        nextProfile.serviceFeeType,
        nextProfile.serviceFeeType === "percentage" ? "percentage" : "fixed",
        nextProfile.serviceFeeValue,
        nextProfile.deliveryFeeMode,
        nextProfile.appDeliveryFeeValue,
        nextProfile.storeDeliveryFeeValue,
        nextProfile.appDeliveryFeeValue,
        nextProfile.appDeliveryEnabled,
        nextProfile.merchantDeliveryEnabled,
        nextProfile.settlementCycle,
        nextProfile.distributionPolicy,
        nextProfile.gracePeriodDays,
        nextProfile.effectiveFrom,
        nextProfile.profileVersion,
        Number(adminUserId),
      ]
    );

    await client.query(
      `INSERT INTO merchant_billing_profile_audit
        (
          merchant_id,
          profile_version,
          change_kind,
          effective_from,
          changed_by_user_id,
          previous_profile_json,
          next_profile_json
        )
       VALUES ($1,$2,$3,$4::timestamptz,$5,$6::jsonb,$7::jsonb)`,
      [
        Number(merchantId),
        Number(nextProfile.profileVersion),
        String(changeKind || "admin_update").slice(0, 40),
        nextProfile.effectiveFrom,
        Number(adminUserId) || null,
        JSON.stringify(previousProfile),
        JSON.stringify(normalizeMerchantBillingProfile(upserted.rows[0] || nextProfile)),
      ]
    );

    if (ownsTransaction) {
      await client.query("COMMIT");
    }
    return {
      billingProfile: upserted.rows[0] || null,
      billingProfileNormalized: normalizeMerchantBillingProfile(
        upserted.rows[0] || nextProfile
      ),
    };
  } catch (error) {
    if (ownsTransaction) {
      await client.query("ROLLBACK");
    }
    throw error;
  } finally {
    if (ownsTransaction) {
      client.release();
    }
  }
}

async function getMerchantApprovalContextTx(client, merchantId, { forUpdate = false } = {}) {
  const result = await client.query(
    `SELECT
       m.*,
       u.full_name AS owner_full_name,
       u.phone AS owner_phone
     FROM merchant m
     LEFT JOIN app_user u ON u.id = m.owner_user_id
     WHERE m.id = $1
     ${forUpdate ? "FOR UPDATE OF m" : ""}
     LIMIT 1`,
    [Number(merchantId)]
  );
  const row = result.rows[0];
  if (!row) {
    throw new AppError("MERCHANT_NOT_FOUND", { status: 404 });
  }
  return row;
}

export async function submitMerchantFinancialTermsForApproval({
  adminUserId,
  merchantId,
  patch = {},
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const merchant = await getMerchantApprovalContextTx(client, merchantId, {
      forUpdate: true,
    });
    const currentStatus = normalizeApprovalStatus(merchant.approval_status);
    if (merchant.is_approved === true && currentStatus === "approved") {
      throw new AppError("MERCHANT_ALREADY_APPROVED", { status: 409 });
    }

    const profileUpdate = await updateMerchantBillingProfile({
      client,
      adminUserId,
      merchantId,
    commissionType: patch.commissionType ?? null,
    commissionValue: patch.commissionValue ?? null,
    commissionRate: patch.commissionRate ?? null,
    commissionModel: patch.commissionModel ?? null,
    monthlySubscriptionAmount: patch.monthlySubscriptionAmount ?? null,
    serviceFeeType: patch.serviceFeeType ?? null,
    serviceFeeMode: patch.serviceFeeMode ?? null,
    serviceFeeValue: patch.serviceFeeValue ?? null,
      deliveryFeeMode: patch.deliveryFeeMode ?? null,
      appDeliveryFeeValue: patch.appDeliveryFeeValue ?? null,
      storeDeliveryFeeValue: patch.storeDeliveryFeeValue ?? null,
      deliveryFeeValue: patch.deliveryFeeValue ?? null,
      appDeliveryEnabled: patch.appDeliveryEnabled,
      merchantDeliveryEnabled: patch.merchantDeliveryEnabled,
      settlementCycle: patch.settlementCycle ?? null,
      distributionPolicy: patch.distributionPolicy ?? null,
      gracePeriodDays: patch.gracePeriodDays ?? null,
      effectiveFrom: patch.effectiveFrom ?? null,
      changeKind: "approval_terms",
    });
    const termsSnapshot = profileUpdate.billingProfileNormalized;

    const updatedMerchant = await client.query(
      `UPDATE merchant
       SET approval_status = 'awaiting_store_financial_acceptance',
           financial_terms_sent_at = NOW(),
           financial_terms_sent_by_user_id = $2,
           financial_terms_snapshot_json = $3::jsonb,
           financial_terms_rejected_at = NULL,
           financial_terms_rejection_note = NULL
       WHERE id = $1
       RETURNING *`,
      [
        Number(merchantId),
        Number(adminUserId),
        JSON.stringify(termsSnapshot),
      ]
    );

    await client.query("COMMIT");
    return {
      merchant: updatedMerchant.rows[0] || merchant,
      billingProfile: profileUpdate.billingProfile,
      financialTerms: termsSnapshot,
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function acceptMerchantFinancialTermsByOwner({ ownerUserId }) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const merchant = await getMerchantByOwnerTx(client, Number(ownerUserId));
    if (!merchant) {
      throw new AppError("MERCHANT_NOT_FOUND", { status: 404 });
    }
    const details = await getMerchantApprovalContextTx(client, Number(merchant.id), {
      forUpdate: true,
    });
    if (
      normalizeApprovalStatus(details.approval_status) !==
      "awaiting_store_financial_acceptance"
    ) {
      throw new AppError("MERCHANT_FINANCIAL_TERMS_NOT_PENDING", { status: 409 });
    }

    const updated = await client.query(
      `UPDATE merchant
       SET is_approved = TRUE,
           approval_status = 'approved',
           approved_at = NOW(),
           approved_by_user_id = COALESCE(financial_terms_sent_by_user_id, approved_by_user_id),
           financial_terms_accepted_at = NOW()
       WHERE id = $1
       RETURNING *`,
      [Number(details.id)]
    );

    await client.query(
      `UPDATE merchant_billing_profile
       SET last_accepted_at = NOW()
       WHERE merchant_id = $1`,
      [Number(details.id)]
    );

    await client.query("COMMIT");
    return {
      merchant: updated.rows[0] || details,
      financialTerms:
        details.financial_terms_snapshot_json &&
        typeof details.financial_terms_snapshot_json === "object"
          ? details.financial_terms_snapshot_json
          : null,
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function rejectMerchantFinancialTermsByOwner({
  ownerUserId,
  note = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const merchant = await getMerchantByOwnerTx(client, Number(ownerUserId));
    if (!merchant) {
      throw new AppError("MERCHANT_NOT_FOUND", { status: 404 });
    }
    const details = await getMerchantApprovalContextTx(client, Number(merchant.id), {
      forUpdate: true,
    });
    if (
      normalizeApprovalStatus(details.approval_status) !==
      "awaiting_store_financial_acceptance"
    ) {
      throw new AppError("MERCHANT_FINANCIAL_TERMS_NOT_PENDING", { status: 409 });
    }

    const updated = await client.query(
      `UPDATE merchant
       SET is_approved = FALSE,
           approval_status = 'pending_admin_review',
           financial_terms_rejected_at = NOW(),
           financial_terms_rejection_note = $2
       WHERE id = $1
       RETURNING *`,
      [Number(details.id), note == null ? null : String(note).slice(0, 1200)]
    );

    await client.query("COMMIT");
    return {
      merchant: updated.rows[0] || details,
      financialTerms:
        details.financial_terms_snapshot_json &&
        typeof details.financial_terms_snapshot_json === "object"
          ? details.financial_terms_snapshot_json
          : null,
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

function allocationPriorityFor(scope) {
  const normalizedScope = String(scope || "").toLowerCase();
  if (normalizedScope === "commission") return ["commission"];
  if (normalizedScope === "service") return ["service_fee"];
  if (normalizedScope === "delivery") return ["delivery_fee"];
  return ["commission", "service_fee", "delivery_fee"];
}

async function getPaymentRequestWithMerchantTx(client, paymentRequestId, { forUpdate = false } = {}) {
  const result = await client.query(
    `SELECT
       pr.*,
       m.id AS merchant_id,
       m.name AS merchant_name,
       m.owner_user_id
     FROM merchant_payment_request pr
     JOIN merchant m ON m.id = pr.merchant_id
     WHERE pr.id = $1
     ${forUpdate ? "FOR UPDATE" : ""}
     LIMIT 1`,
    [Number(paymentRequestId)]
  );
  const row = result.rows[0];
  if (!row) throw new AppError("PAYMENT_REQUEST_NOT_FOUND", { status: 404 });
  return row;
}

function resolveOutstandingByScope(breakdown, scope) {
  const normalizedScope = normalizePaymentScope(scope);
  if (normalizedScope === "commission") {
    return toNumber(breakdown?.commission?.outstanding, 0);
  }
  if (normalizedScope === "service") {
    return toNumber(breakdown?.serviceFee?.outstanding, 0);
  }
  if (normalizedScope === "delivery") {
    return toNumber(breakdown?.deliveryFee?.outstanding, 0);
  }
  return toNumber(breakdown?.totals?.outstanding, 0);
}

async function allocateStorePaymentIntoReceivablesTx(
  client,
  { paymentRequestId, merchantId, paymentScope, amount }
) {
  const breakdown = await merchantReceivableBreakdownByType(client, Number(merchantId), {
    includePendingPayments: false,
  });
  const targets = allocationPriorityFor(paymentScope);
  let remaining = round2(toNumber(amount, 0));
  if (!(remaining > 0)) {
    throw new AppError("INVALID_PAYMENT_AMOUNT", { status: 400 });
  }
  const allocations = [];
  for (const target of targets) {
    if (remaining <= 0) break;
    const outstanding =
      target === "commission"
        ? toNumber(breakdown?.commission?.outstanding, 0)
        : target === "service_fee"
          ? toNumber(breakdown?.serviceFee?.outstanding, 0)
          : toNumber(breakdown?.deliveryFee?.outstanding, 0);
    if (outstanding <= 0) continue;
    const allocate = round2(Math.min(remaining, outstanding));
    if (allocate <= 0) continue;
    await appendMerchantLedgerEntryTx(client, {
      merchantId: Number(merchantId),
      orderId: null,
      entryType: target,
      amount: allocate,
      direction: "credit",
      referenceType: "payment_request",
      referenceId: Number(paymentRequestId),
      note: "Payment request approved",
    });
    const allocationRow = await client.query(
      `INSERT INTO merchant_payment_allocation
        (payment_request_id, allocated_to_type, amount)
       VALUES ($1,$2,$3)
       RETURNING *`,
      [Number(paymentRequestId), target, allocate]
    );
    allocations.push(allocationRow.rows[0]);
    remaining = round2(remaining - allocate);
  }

  if (remaining > 0) {
    await appendMerchantLedgerEntryTx(client, {
      merchantId: Number(merchantId),
      orderId: null,
      entryType: "adjustment",
      amount: remaining,
      direction: "credit",
      referenceType: "payment_request",
      referenceId: Number(paymentRequestId),
      note: "Unallocated remainder from approved payment",
    });
    const allocationRow = await client.query(
      `INSERT INTO merchant_payment_allocation
        (payment_request_id, allocated_to_type, amount)
       VALUES ($1,$2,$3)
       RETURNING *`,
      [Number(paymentRequestId), "adjustment", remaining]
    );
    allocations.push(allocationRow.rows[0]);
  }
  return allocations;
}

export async function adminApprovePaymentRequest({
  adminUserId,
  paymentRequestId,
  reviewNote = null,
  internalAdminNote = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const current = await getPaymentRequestWithMerchantTx(client, paymentRequestId, {
      forUpdate: true,
    });
    const requestType = normalizePaymentRequestType(current.request_type);
    const status = normalizeRequestStatus(current.status);
    const amount = round2(
      toNumber(current.requested_amount, toNumber(current.amount, 0))
    );
    const merchantId = Number(current.merchant_id);
    if (!(amount > 0)) {
      throw new AppError("INVALID_PAYMENT_AMOUNT", { status: 400 });
    }

    let allocations = [];
    let invoiceAllocations = [];
    let updated = null;
    if (requestType === REQUEST_TYPE_STORE_PAYS_APP) {
      if (
        ![
          REQUEST_STATUS.pendingAdminConfirmation,
          REQUEST_STATUS.returnedForRevision,
        ].includes(status)
      ) {
        throw new AppError("PAYMENT_REQUEST_NOT_PENDING_ADMIN_CONFIRMATION", {
          status: 409,
        });
      }

      await syncMerchantReceivableBookTx(client, merchantId, {
        maxOrders: 3000,
      });
      const selectionMeta = parseJsonOrEmpty(current.selection_meta_json);
      const preview = await buildMerchantPaymentSelectionPreviewTx(client, {
        merchantId,
        selectionMode: current.selection_mode || selectionMeta.selectionMode,
        selectedInvoiceIds: selectionMeta.selectedInvoiceIds || [],
        targetAmount:
          current.selection_mode === SELECTION_MODE_AUTO
            ? selectionMeta.requestedAmount
            : current.requested_amount,
        confirmedAdjustedAmount:
          selectionMeta.confirmedAdjustedAmount ?? current.requested_amount,
      });
      if (preview.requiresAmountConfirmation || preview.invoices.length === 0) {
        throw new AppError("PAYMENT_REQUEST_SELECTION_OUTDATED", {
          status: 409,
          details: preview,
        });
      }
      if (Math.abs(round2(preview.finalizedAmount) - amount) > 0.01) {
        throw new AppError("PAYMENT_REQUEST_SELECTION_AMOUNT_CHANGED", {
          status: 409,
          details: {
            storedAmount: amount,
            resolvedAmount: round2(preview.finalizedAmount),
            paymentRequestId: Number(current.id),
          },
        });
      }

      const scopeOutstanding = resolveOutstandingByScope(
        await merchantReceivableBreakdownByType(client, merchantId, {
          includePendingPayments: false,
        }),
        current.payment_scope
      );
      if (!(scopeOutstanding > 0)) {
        throw new AppError("NO_OUTSTANDING_RECEIVABLES", { status: 409 });
      }

      await client.query(
        `DELETE FROM merchant_payment_invoice_allocation
         WHERE payment_request_id = $1`,
        [Number(current.id)]
      );
      invoiceAllocations = await insertMerchantPaymentInvoiceAllocationsTx(client, {
        paymentRequestId: Number(current.id),
        merchantId,
        invoices: preview.invoices,
        requestedAmount: amount,
        allowPartialLastInvoice: false,
      });
      allocations = await allocateStorePaymentIntoReceivablesTx(client, {
        paymentRequestId: Number(current.id),
        merchantId,
        paymentScope: current.payment_scope,
        amount,
      });
      updated = await updatePaymentRequestStatusTx(client, {
        paymentRequestId: Number(current.id),
        fromStatuses: [
          REQUEST_STATUS.pendingAdminConfirmation,
          REQUEST_STATUS.returnedForRevision,
        ],
        toStatus: REQUEST_STATUS.confirmedByAdmin,
        actorUserId: Number(adminUserId),
        actorRole: "admin",
        note: reviewNote || "Admin confirmed merchant payment",
        metadata: {
          reviewNote: reviewNote || null,
          internalAdminNote: internalAdminNote || null,
          allocationsCount: allocations.length,
          invoiceAllocationsCount: invoiceAllocations.length,
        },
        patch: {
          reviewed_at: "NOW()",
          reviewed_by_user_id: Number(adminUserId),
          review_note: reviewNote || null,
          internal_admin_note: internalAdminNote || null,
          paid_amount: amount,
          final_confirmed_at: "NOW()",
          final_confirmed_by_user_id: Number(adminUserId),
        },
        lockRequest: true,
      });
    } else {
      if (
        ![
          REQUEST_STATUS.pendingAdminReview,
          REQUEST_STATUS.returnedForRevision,
          REQUEST_STATUS.issueReportedByStore,
        ].includes(status)
      ) {
        throw new AppError("PAYMENT_REQUEST_NOT_PENDING_ADMIN_REVIEW", {
          status: 409,
        });
      }
      updated = await updatePaymentRequestStatusTx(client, {
        paymentRequestId: Number(current.id),
        fromStatuses: [
          REQUEST_STATUS.pendingAdminReview,
          REQUEST_STATUS.returnedForRevision,
          REQUEST_STATUS.issueReportedByStore,
        ],
        toStatus: REQUEST_STATUS.approvedByAdmin,
        actorUserId: Number(adminUserId),
        actorRole: "admin",
        note: reviewNote || "Admin approved payout request",
        metadata: {
          reviewNote: reviewNote || null,
          internalAdminNote: internalAdminNote || null,
        },
        patch: {
          reviewed_at: "NOW()",
          reviewed_by_user_id: Number(adminUserId),
          review_note: reviewNote || null,
          internal_admin_note: internalAdminNote || null,
        },
      });
    }

    await client.query("COMMIT");
    return {
      paymentRequest: mapPaymentRequestRow(updated),
      allocations,
      invoiceAllocations,
      merchant: {
        id: merchantId,
        name: current.merchant_name,
        owner_user_id: current.owner_user_id,
      },
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function adminAssignPaymentRequest({
  adminUserId,
  paymentRequestId,
  assignedToUserId = null,
  assignedToName = null,
  reviewNote = null,
  internalAdminNote = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const current = await getPaymentRequestWithMerchantTx(client, paymentRequestId, {
      forUpdate: true,
    });
    const requestType = normalizePaymentRequestType(current.request_type);
    if (requestType !== REQUEST_TYPE_APP_PAYS_STORE) {
      throw new AppError("PAYMENT_REQUEST_INVALID_TYPE", { status: 409 });
    }

    const updated = await updatePaymentRequestStatusTx(client, {
      paymentRequestId: Number(current.id),
      fromStatuses: [
        REQUEST_STATUS.approvedByAdmin,
        REQUEST_STATUS.issueReportedByStore,
      ],
      toStatus: REQUEST_STATUS.assignedForPayment,
      actorUserId: Number(adminUserId),
      actorRole: "admin",
      note: reviewNote || "Admin assigned payout execution",
      metadata: {
        assignedToUserId: assignedToUserId ? Number(assignedToUserId) : null,
        assignedToName: assignedToName || null,
        internalAdminNote: internalAdminNote || null,
      },
      patch: {
        assigned_to_user_id: assignedToUserId ? Number(assignedToUserId) : null,
        assigned_to_name: assignedToName || null,
        internal_admin_note: internalAdminNote || null,
        review_note: reviewNote || null,
      },
    });

    await client.query("COMMIT");
    return {
      paymentRequest: mapPaymentRequestRow(updated),
      merchant: {
        id: Number(current.merchant_id),
        name: current.merchant_name,
        owner_user_id: current.owner_user_id,
      },
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function adminMarkPaymentRequestPaid({
  adminUserId,
  paymentRequestId,
  paidAmount = null,
  paymentMethod = null,
  paymentDate = null,
  referenceCode = null,
  paymentActorName = null,
  assignedToUserId = null,
  assignedToName = null,
  reviewNote = null,
  internalAdminNote = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const current = await getPaymentRequestWithMerchantTx(client, paymentRequestId, {
      forUpdate: true,
    });
    const requestType = normalizePaymentRequestType(current.request_type);
    if (requestType !== REQUEST_TYPE_APP_PAYS_STORE) {
      throw new AppError("PAYMENT_REQUEST_INVALID_TYPE", { status: 409 });
    }
    const baseAmount = round2(
      toNumber(current.requested_amount, toNumber(current.amount, 0))
    );
    const effectivePaidAmount = round2(
      paidAmount == null ? baseAmount : toNumber(paidAmount, 0)
    );
    if (!(effectivePaidAmount > 0)) {
      throw new AppError("INVALID_PAYMENT_AMOUNT", { status: 400 });
    }
    const appOutstanding = toNumber(
      (
        await merchantAppPayablesBreakdownByType(client, Number(current.merchant_id), {
          includePendingOutgoing: false,
        })
      )?.totals?.outstanding,
      0
    );
    if (effectivePaidAmount - appOutstanding > 0.01) {
      throw new AppError("PAYMENT_AMOUNT_EXCEEDS_OUTSTANDING", {
        status: 400,
        details: {
          requestedAmount: effectivePaidAmount,
          maxOutstanding: round2(appOutstanding),
        },
      });
    }

    const updated = await updatePaymentRequestStatusTx(client, {
      paymentRequestId: Number(current.id),
      fromStatuses: [
        REQUEST_STATUS.approvedByAdmin,
        REQUEST_STATUS.assignedForPayment,
        REQUEST_STATUS.issueReportedByStore,
      ],
      toStatus: REQUEST_STATUS.awaitingStoreConfirmation,
      actorUserId: Number(adminUserId),
      actorRole: "admin",
      note: reviewNote || "Admin marked payout as paid",
      metadata: {
        paidAmount: effectivePaidAmount,
        paymentMethod: paymentMethod || null,
        paymentDate: paymentDate || null,
        referenceCode: referenceCode || null,
        paymentActorName: paymentActorName || null,
      },
      patch: {
        paid_amount: effectivePaidAmount,
        admin_payment_method: paymentMethod || null,
        admin_reference_code: referenceCode || null,
        admin_payment_date: paymentDate ? new Date(paymentDate).toISOString() : "NOW()",
        admin_payment_actor_name: paymentActorName || null,
        assigned_to_user_id: assignedToUserId ? Number(assignedToUserId) : null,
        assigned_to_name: assignedToName || null,
        review_note: reviewNote || null,
        internal_admin_note: internalAdminNote || null,
      },
    });

    await client.query("COMMIT");
    return {
      paymentRequest: mapPaymentRequestRow(updated),
      merchant: {
        id: Number(current.merchant_id),
        name: current.merchant_name,
        owner_user_id: current.owner_user_id,
      },
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function adminReturnPaymentRequestForRevision({
  adminUserId,
  paymentRequestId,
  reviewNote = null,
  internalAdminNote = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const current = await getPaymentRequestWithMerchantTx(client, paymentRequestId, {
      forUpdate: true,
    });
    const requestType = normalizePaymentRequestType(current.request_type);
    const fromStatuses =
      requestType === REQUEST_TYPE_STORE_PAYS_APP
        ? [REQUEST_STATUS.pendingAdminConfirmation]
        : [
            REQUEST_STATUS.pendingAdminReview,
            REQUEST_STATUS.approvedByAdmin,
            REQUEST_STATUS.assignedForPayment,
            REQUEST_STATUS.issueReportedByStore,
            REQUEST_STATUS.awaitingStoreConfirmation,
          ];

    const updated = await updatePaymentRequestStatusTx(client, {
      paymentRequestId: Number(current.id),
      fromStatuses,
      toStatus: REQUEST_STATUS.returnedForRevision,
      actorUserId: Number(adminUserId),
      actorRole: "admin",
      note: reviewNote || "Admin returned payment request for revision",
      metadata: {
        reviewNote: reviewNote || null,
        internalAdminNote: internalAdminNote || null,
      },
      patch: {
        review_note: reviewNote || null,
        internal_admin_note: internalAdminNote || null,
      },
      lockRequest: false,
    });

    await client.query("COMMIT");
    return {
      paymentRequest: mapPaymentRequestRow(updated),
      merchant: {
        id: Number(current.merchant_id),
        name: current.merchant_name,
        owner_user_id: current.owner_user_id,
      },
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function markPaymentRequestReceived({
  adminUserId,
  paymentRequestId,
  reviewNote = null,
}) {
  const current = await q(
    `SELECT request_type
     FROM merchant_payment_request
     WHERE id = $1
     LIMIT 1`,
    [Number(paymentRequestId)]
  );
  const row = current.rows[0];
  if (!row) throw new AppError("PAYMENT_REQUEST_NOT_FOUND", { status: 404 });
  const requestType = normalizePaymentRequestType(row.request_type);

  if (requestType === REQUEST_TYPE_STORE_PAYS_APP) {
    return adminApprovePaymentRequest({
      adminUserId,
      paymentRequestId,
      reviewNote,
    });
  }
  return adminMarkPaymentRequestPaid({
    adminUserId,
    paymentRequestId,
    reviewNote,
  });
}

export async function rejectPaymentRequest({
  adminUserId,
  paymentRequestId,
  reviewNote = null,
  internalAdminNote = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const current = await getPaymentRequestWithMerchantTx(client, paymentRequestId, {
      forUpdate: true,
    });
    const requestType = normalizePaymentRequestType(current.request_type);
    const fromStatuses =
      requestType === REQUEST_TYPE_STORE_PAYS_APP
        ? [
            REQUEST_STATUS.pendingAdminConfirmation,
            REQUEST_STATUS.returnedForRevision,
          ]
        : [
            REQUEST_STATUS.pendingAdminReview,
            REQUEST_STATUS.approvedByAdmin,
            REQUEST_STATUS.assignedForPayment,
            REQUEST_STATUS.issueReportedByStore,
          ];

    const updated = await updatePaymentRequestStatusTx(client, {
      paymentRequestId: Number(current.id),
      fromStatuses,
      toStatus: REQUEST_STATUS.rejectedByAdmin,
      actorUserId: Number(adminUserId),
      actorRole: "admin",
      note: reviewNote || "Admin rejected payment request",
      metadata: {
        reviewNote: reviewNote || null,
        internalAdminNote: internalAdminNote || null,
      },
      patch: {
        reviewed_at: "NOW()",
        reviewed_by_user_id: Number(adminUserId),
        review_note: reviewNote || null,
        internal_admin_note: internalAdminNote || null,
      },
      lockRequest: false,
    });
    await client.query("COMMIT");
    return {
      paymentRequest: mapPaymentRequestRow(updated),
      merchant: {
        id: Number(current.merchant_id),
        name: current.merchant_name,
        owner_user_id: current.owner_user_id,
      },
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function adminCreateMerchantAppPayablesAdjustment({
  adminUserId,
  merchantId,
  amount,
  direction,
  entryType = "adjustment",
  note = null,
  referenceCode = null,
  orderId = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const merchantResult = await client.query(
      `SELECT id, name, owner_user_id
       FROM merchant
       WHERE id = $1
       LIMIT 1`,
      [Number(merchantId)]
    );
    const merchant = merchantResult.rows[0];
    if (!merchant) throw new AppError("MERCHANT_NOT_FOUND", { status: 404 });
    const absoluteAmount = round2(Math.abs(toNumber(amount, 0)));
    if (!(absoluteAmount > 0)) {
      throw new AppError("INVALID_ADJUSTMENT_AMOUNT", { status: 400 });
    }
    const safeDirection = String(direction || "").trim().toLowerCase();
    if (!["debit", "credit"].includes(safeDirection)) {
      throw new AppError("INVALID_ADJUSTMENT_DIRECTION", { status: 400 });
    }
    const ledgerEntry = await appendMerchantAppPayablesLedgerEntryTx(client, {
      merchantId: Number(merchant.id),
      orderId: orderId == null ? null : Number(orderId),
      entryType: String(entryType || "adjustment").trim().toLowerCase() || "adjustment",
      amount: absoluteAmount,
      direction: safeDirection,
      referenceType: referenceCode ? "admin_adjustment_ref" : "admin_adjustment",
      referenceId: null,
      note:
        note ||
        `Admin adjustment by user ${Number(adminUserId)}${referenceCode ? ` (ref: ${referenceCode})` : ""}`,
    });

    await client.query("COMMIT");
    return {
      merchant,
      ledgerEntry,
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

function parseCompetitionStatusFilter({ status = null, activeOnly = false } = {}) {
  if (activeOnly === true) return "active";
  const normalized = String(status || "").trim().toLowerCase();
  if (["active", "ended", "draft", "cancelled", "history", "all"].includes(normalized)) {
    return normalized;
  }
  return "all";
}

async function loadCompetitionTiersByIds(competitionIds) {
  const ids = (competitionIds || [])
    .map((id) => Number(id))
    .filter((id) => Number.isFinite(id) && id > 0);
  if (!ids.length) return new Map();
  const tiers = await q(
    `SELECT *
     FROM courier_competition_tier
     WHERE competition_id = ANY($1::bigint[])
     ORDER BY competition_id ASC, required_completed_orders DESC, sort_order ASC`,
    [ids]
  );
  return mapCompetitionTiers(tiers.rows);
}

async function buildAdminCompetitionEnvelope(competitionRows = []) {
  const competitionIds = competitionRows
    .map((row) => Number(row.id))
    .filter((id) => Number.isFinite(id) && id > 0);
  const tiersMap = await loadCompetitionTiersByIds(competitionIds);
  return competitionRows.map((row) => ({
    ...row,
    tiers: tiersMap.get(Number(row.id)) || deriveFallbackTier(row),
  }));
}

export async function listAdminCompetitions({ status = null, activeOnly = false } = {}) {
  await runCompetitionFinalizerPass();
  const normalizedStatus = parseCompetitionStatusFilter({ status, activeOnly });
  const whereParts = [];
  if (normalizedStatus === "active") {
    whereParts.push("cc.is_active = TRUE", "cc.status IN ('active','draft')", "cc.end_at >= NOW()");
  } else if (normalizedStatus === "history" || normalizedStatus === "ended") {
    whereParts.push("(cc.status = 'ended' OR cc.end_at < NOW())");
  } else if (normalizedStatus === "draft") {
    whereParts.push("cc.status = 'draft'");
  } else if (normalizedStatus === "cancelled") {
    whereParts.push("cc.status = 'cancelled'");
  }
  const whereClause = whereParts.length ? `WHERE ${whereParts.join(" AND ")}` : "";

  const rows = await q(
    `SELECT
       cc.*,
       (
         SELECT COUNT(*)::int
         FROM courier_competition_progress ccp
         WHERE ccp.competition_id = cc.id
       ) AS participants_count,
       (
         SELECT COUNT(*)::int
         FROM courier_competition_result ccr
         WHERE ccr.competition_id = cc.id
           AND ccr.won = TRUE
       ) AS winners_count
     FROM courier_competition cc
     ${whereClause}
     ORDER BY cc.start_at DESC, cc.id DESC`
  );
  const competitions = await buildAdminCompetitionEnvelope(rows.rows);
  return { competitions, status: normalizedStatus };
}

export async function getAdminCompetitionDetails(competitionId) {
  await runCompetitionFinalizerPass();
  const main = await q(
    `SELECT
       cc.*,
       (
         SELECT COUNT(*)::int
         FROM courier_competition_progress ccp
         WHERE ccp.competition_id = cc.id
       ) AS participants_count,
       (
         SELECT COUNT(*)::int
         FROM courier_competition_result ccr
         WHERE ccr.competition_id = cc.id
           AND ccr.won = TRUE
       ) AS winners_count
     FROM courier_competition cc
     WHERE cc.id = $1
     LIMIT 1`,
    [Number(competitionId)]
  );
  const competition = main.rows[0];
  if (!competition) throw new AppError("COMPETITION_NOT_FOUND", { status: 404 });

  const competitions = await buildAdminCompetitionEnvelope([competition]);
  const envelope = competitions[0];

  const [leaderboard, winners] = await Promise.all([
    q(
      `SELECT
         ccp.courier_user_id,
         u.full_name,
         ccp.current_value,
         ccp.current_rank_sort_order,
         ccp.current_rank_title,
         ccp.highest_rank_sort_order,
         ccp.highest_rank_title,
         ccp.updated_at
       FROM courier_competition_progress ccp
       JOIN app_user u ON u.id = ccp.courier_user_id
       WHERE ccp.competition_id = $1
       ORDER BY ccp.current_value DESC, ccp.updated_at ASC
       LIMIT 300`,
      [Number(competitionId)]
    ),
    q(
      `SELECT
         ccr.*,
         u.full_name
       FROM courier_competition_result ccr
       JOIN app_user u ON u.id = ccr.courier_user_id
       WHERE ccr.competition_id = $1
       ORDER BY ccr.won DESC, ccr.final_rank_sort_order ASC NULLS LAST, ccr.final_completed_orders DESC`,
      [Number(competitionId)]
    ),
  ]);

  return {
    competition: envelope,
    leaderboard: leaderboard.rows,
    winners: winners.rows,
  };
}

export async function listAdminCompetitionWinners(competitionId) {
  const winners = await q(
    `SELECT
       ccr.*,
       u.full_name
     FROM courier_competition_result ccr
     JOIN app_user u ON u.id = ccr.courier_user_id
     WHERE ccr.competition_id = $1
       AND ccr.won = TRUE
     ORDER BY ccr.final_rank_sort_order ASC NULLS LAST, ccr.final_completed_orders DESC, ccr.id ASC`,
    [Number(competitionId)]
  );
  return { winners: winners.rows };
}

export async function createAdminCompetition({
  adminUserId,
  title,
  description = null,
  competitionType,
  targetValue,
  rewardAmount,
  rewardType = "cash",
  startAt,
  endAt,
  isActive = true,
  status = null,
  filtersJson = {},
  tiers = [],
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const normalizedTiers = tiers.length
      ? assertCompetitionTiers(tiers)
      : assertCompetitionTiers([
          {
            title: "Rank 1",
            sortOrder: 1,
            requiredCompletedOrders: Math.max(1, Math.floor(toNumber(targetValue, 1))),
            rewardAmount: toNumber(rewardAmount, 0),
          },
        ]);
    const highestTier = normalizedTiers[0];
    const effectiveStatus =
      status && ["draft", "active", "ended", "cancelled"].includes(String(status))
        ? String(status)
        : isActive === false
        ? "draft"
        : "active";
    const inserted = await client.query(
      `INSERT INTO courier_competition
        (
          title,
          description,
          competition_type,
          target_value,
          reward_amount,
          reward_type,
          start_at,
          end_at,
          is_active,
          status,
          filters_json,
          created_by_user_id,
          created_at,
          updated_at
        )
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11::jsonb,$12,NOW(),NOW())
       RETURNING *`,
      [
        String(title || "").trim(),
        description || null,
        String(competitionType || "completed_orders").trim(),
        Math.max(1, Number(highestTier.requiredCompletedOrders || 1)),
        round2(toNumber(highestTier.rewardAmount, toNumber(rewardAmount, 0))),
        String(rewardType || "cash").trim(),
        startAt ? new Date(startAt) : new Date(),
        endAt ? new Date(endAt) : new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
        effectiveStatus === "active",
        effectiveStatus,
        JSON.stringify(filtersJson || {}),
        Number(adminUserId),
      ]
    );
    const competition = inserted.rows[0];

    for (const tier of normalizedTiers) {
      await client.query(
        `INSERT INTO courier_competition_tier
          (
            competition_id,
            title,
            sort_order,
            required_completed_orders,
            reward_amount,
            reward_label,
            created_at,
            updated_at
          )
         VALUES ($1,$2,$3,$4,$5,$6,NOW(),NOW())`,
        [
          Number(competition.id),
          String(tier.title || `Rank ${tier.sortOrder}`),
          Number(tier.sortOrder),
          Number(tier.requiredCompletedOrders),
          round2(toNumber(tier.rewardAmount, 0)),
          tier.rewardLabel || null,
        ]
      );
    }

    await client.query("COMMIT");
    const details = await getAdminCompetitionDetails(Number(competition.id));
    return { competition: details.competition };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function updateAdminCompetition({
  competitionId,
  title = null,
  description = null,
  targetValue = null,
  rewardAmount = null,
  rewardType = null,
  startAt = null,
  endAt = null,
  isActive = null,
  status = null,
  filtersJson = null,
  tiers = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const current = await client.query(
      `SELECT *
       FROM courier_competition
       WHERE id = $1
       FOR UPDATE`,
      [Number(competitionId)]
    );
    const competition = current.rows[0];
    if (!competition) throw new AppError("COMPETITION_NOT_FOUND", { status: 404 });
    const currentStatus = String(competition.status || "").trim().toLowerCase();
    const currentIsActive = competition.is_active === true;
    if (currentStatus !== "active" || !currentIsActive) {
      throw new AppError("COMPETITION_ONLY_ACTIVE_CAN_EDIT", { status: 409 });
    }
    if (String(competition.status) === "ended" && Array.isArray(tiers)) {
      throw new AppError("COMPETITION_ENDED_CANNOT_EDIT_TIERS", { status: 409 });
    }

    let normalizedTiers = null;
    if (Array.isArray(tiers)) {
      normalizedTiers = assertCompetitionTiers(tiers);
    }
    const effectiveTarget = normalizedTiers?.[0]?.requiredCompletedOrders;
    const effectiveReward = normalizedTiers?.[0]?.rewardAmount;
    const effectiveStatus =
      status && ["draft", "active", "ended", "cancelled"].includes(String(status))
        ? String(status)
        : null;
    if (effectiveStatus && effectiveStatus !== "active") {
      throw new AppError("COMPETITION_PATCH_STATUS_NOT_ALLOWED", { status: 400 });
    }
    const resolvedIsActive =
      typeof isActive === "boolean"
        ? isActive
        : effectiveStatus == null
        ? null
        : effectiveStatus === "active";

    const updated = await client.query(
      `UPDATE courier_competition
       SET title = COALESCE($2, title),
           description = COALESCE($3, description),
           target_value = COALESCE($4, target_value),
           reward_amount = COALESCE($5, reward_amount),
           reward_type = COALESCE($6, reward_type),
           start_at = COALESCE($7, start_at),
           end_at = COALESCE($8, end_at),
           is_active = COALESCE($9::boolean, is_active),
           status = COALESCE($10, status),
           filters_json = COALESCE($11::jsonb, filters_json),
           updated_at = NOW()
       WHERE id = $1
       RETURNING *`,
      [
        Number(competitionId),
        title,
        description,
        effectiveTarget == null
          ? targetValue == null
            ? null
            : round2(toNumber(targetValue, 0))
          : effectiveTarget,
        effectiveReward == null
          ? rewardAmount == null
            ? null
            : round2(toNumber(rewardAmount, 0))
          : round2(toNumber(effectiveReward, 0)),
        rewardType,
        startAt ? new Date(startAt) : null,
        endAt ? new Date(endAt) : null,
        resolvedIsActive,
        effectiveStatus,
        filtersJson == null ? null : JSON.stringify(filtersJson),
      ]
    );

    if (normalizedTiers) {
      await client.query(
        `DELETE FROM courier_competition_tier
         WHERE competition_id = $1`,
        [Number(competitionId)]
      );
      for (const tier of normalizedTiers) {
        await client.query(
          `INSERT INTO courier_competition_tier
            (
              competition_id,
              title,
              sort_order,
              required_completed_orders,
              reward_amount,
              reward_label,
              created_at,
              updated_at
            )
           VALUES ($1,$2,$3,$4,$5,$6,NOW(),NOW())`,
          [
            Number(competitionId),
            String(tier.title || `Rank ${tier.sortOrder}`),
            Number(tier.sortOrder),
            Number(tier.requiredCompletedOrders),
            round2(toNumber(tier.rewardAmount, 0)),
            tier.rewardLabel || null,
          ]
        );
      }
    }

    await client.query("COMMIT");
    const details = await getAdminCompetitionDetails(Number(competitionId));
    return { competition: details.competition };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function endAdminCompetitionNow({ competitionId }) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const current = await client.query(
      `SELECT *
       FROM courier_competition
       WHERE id = $1
       FOR UPDATE`,
      [Number(competitionId)]
    );
    if (!current.rows[0]) throw new AppError("COMPETITION_NOT_FOUND", { status: 404 });

    const now = new Date();
    await client.query(
      `UPDATE courier_competition
       SET end_at = LEAST(end_at, $2::timestamptz),
           status = 'ended',
           is_active = FALSE,
           ended_at = COALESCE(ended_at, $2::timestamptz),
           updated_at = NOW()
       WHERE id = $1`,
      [Number(competitionId), now]
    );

    await finalizeExpiredCompetitionsTx(client, { now });
    await client.query("COMMIT");
    const details = await getAdminCompetitionDetails(Number(competitionId));
    return { competition: details.competition, winners: details.winners };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

async function computeFinancialKpisTx(
  client,
  { window, merchantId = null } = {}
) {
  const salesParams = [window.start, window.end];
  let salesWhereMerchant = "";
  if (merchantId != null) {
    salesParams.push(Number(merchantId));
    salesWhereMerchant = `AND inv.merchant_id = $${salesParams.length}`;
  }

  const sales = await client.query(
    `SELECT
       COALESCE(SUM(inv.subtotal), 0)::numeric AS total_sales,
       COALESCE(SUM(inv.commission_amount), 0)::numeric AS total_commission,
       COALESCE(SUM(inv.service_fee_amount), 0)::numeric AS total_service_fees,
       COALESCE(SUM(inv.app_delivery_fee_amount), 0)::numeric AS total_app_delivery_fees,
       COALESCE(SUM(inv.store_delivery_fee_amount), 0)::numeric AS total_store_delivery_fees,
       COALESCE(SUM(inv.app_receivable_amount), 0)::numeric AS total_app_due,
       COALESCE(SUM(inv.store_net_amount), 0)::numeric AS total_store_net_sales,
       COUNT(*)::int AS total_sales_orders
     FROM merchant_receivable_invoice inv
     WHERE inv.issued_at >= $1::timestamptz
       AND inv.issued_at <= $2::timestamptz
       ${salesWhereMerchant}`,
    salesParams
  );

  const collectedParams = [window.start, window.end];
  let collectedWhereMerchant = "";
  if (merchantId != null) {
    collectedParams.push(Number(merchantId));
    collectedWhereMerchant = `AND pr.merchant_id = $${collectedParams.length}`;
  }

  const collected = await client.query(
    `SELECT
       COALESCE(
         SUM(COALESCE(pr.paid_amount, pr.requested_amount, pr.amount)),
         0
       )::numeric AS total_collected,
       COUNT(*)::int AS total_collection_operations
     FROM merchant_payment_request pr
     WHERE pr.request_type = 'store_pays_app'
       AND pr.status = 'confirmed_by_admin'
       AND COALESCE(pr.final_confirmed_at, pr.reviewed_at, pr.submitted_at) >= $1::timestamptz
       AND COALESCE(pr.final_confirmed_at, pr.reviewed_at, pr.submitted_at) <= $2::timestamptz
       ${collectedWhereMerchant}`,
    collectedParams
  );

  const totalSales = toNumber(sales.rows[0]?.total_sales, 0);
  const totalCommission = toNumber(sales.rows[0]?.total_commission, 0);
  const totalServiceFees = toNumber(sales.rows[0]?.total_service_fees, 0);
  const totalAppDeliveryFees = toNumber(
    sales.rows[0]?.total_app_delivery_fees,
    0
  );
  const totalStoreDeliveryFees = toNumber(
    sales.rows[0]?.total_store_delivery_fees,
    0
  );
  const totalAppDue = toNumber(sales.rows[0]?.total_app_due, 0);
  const totalStoreNetSales = toNumber(
    sales.rows[0]?.total_store_net_sales,
    0
  );
  const totalCollected = toNumber(collected.rows[0]?.total_collected, 0);
  const netReceivables = round2(totalCollected - totalAppDue);
  const outstandingToCollect = round2(totalAppDue - totalCollected);

  return {
    totalSales: round2(totalSales),
    totalCommission: round2(totalCommission),
    totalServiceFees: round2(totalServiceFees),
    totalAppDeliveryFees: round2(totalAppDeliveryFees),
    totalStoreDeliveryFees: round2(totalStoreDeliveryFees),
    totalAppDue: round2(totalAppDue),
    totalStoreNetSales: round2(totalStoreNetSales),
    totalCollected: round2(totalCollected),
    netReceivables,
    outstandingToCollect,
    totalSalesOrders: Number(sales.rows[0]?.total_sales_orders || 0),
    totalCollectionOperations: Number(
      collected.rows[0]?.total_collection_operations || 0
    ),
  };
}

export async function getAdminFinancialKpis({
  period = "day",
  from = null,
  to = null,
} = {}) {
  const client = await pool.connect();
  try {
    const window = parseWindow({ period, from, to });
    const totals = await computeFinancialKpisTx(client, { window });
    return {
      window,
      currency: "IQD",
      totals,
    };
  } finally {
    client.release();
  }
}

function merchantSearchClause(search, params, alias = "m") {
  const normalized = sanitizeSearch(search);
  if (!normalized) return "";
  params.push(`%${normalized}%`);
  return `WHERE ${alias}.name ILIKE $${params.length}`;
}

export async function getAdminSalesReport({
  period = "day",
  from = null,
  to = null,
  search = null,
  limit = 120,
  offset = 0,
} = {}) {
  const client = await pool.connect();
  try {
    const window = parseWindow({ period, from, to });
    const cappedLimit = sanitizeLimit(limit, 120, 500);
    const safeOffset = sanitizeOffset(offset, 0);
    const params = [];
    const whereSearch = merchantSearchClause(search, params, "m");

    params.push(window.start, window.end, cappedLimit, safeOffset);
    const startParam = params.length - 3;
    const endParam = params.length - 2;
    const limitParam = params.length - 1;
    const offsetParam = params.length;

    const rows = await client.query(
      `SELECT
         m.id AS merchant_id,
         m.name AS merchant_name,
         COALESCE(COUNT(inv.id), 0)::int AS orders_count,
         COALESCE(SUM(inv.subtotal), 0)::numeric AS total_sales,
         MIN(inv.issued_at) AS first_order_at,
         MAX(inv.issued_at) AS last_order_at
       FROM merchant m
       LEFT JOIN merchant_receivable_invoice inv
         ON inv.merchant_id = m.id
        AND inv.issued_at >= $${startParam}::timestamptz
        AND inv.issued_at <= $${endParam}::timestamptz
       ${whereSearch}
       GROUP BY m.id, m.name
       ORDER BY total_sales DESC, orders_count DESC, m.id DESC
       LIMIT $${limitParam} OFFSET $${offsetParam}`,
      params
    );

    const summaryTotals = await computeFinancialKpisTx(client, { window });
    const totalRows = await client.query(
      `SELECT COUNT(*)::int AS total
       FROM merchant m
       ${whereSearch}`,
      params.slice(0, whereSearch ? 1 : 0)
    );

    return {
      window,
      currency: "IQD",
      summary: {
        totalSales: summaryTotals.totalSales,
        totalOrders: summaryTotals.totalSalesOrders,
        merchantsCount: Number(totalRows.rows[0]?.total || 0),
      },
      merchants: rows.rows.map((row) => ({
        merchant_id: Number(row.merchant_id),
        merchant_name: row.merchant_name,
        orders_count: Number(row.orders_count || 0),
        total_sales: toNumber(row.total_sales, 0),
        first_order_at: row.first_order_at,
        last_order_at: row.last_order_at,
      })),
      pagination: {
        limit: cappedLimit,
        offset: safeOffset,
        total: Number(totalRows.rows[0]?.total || 0),
      },
    };
  } finally {
    client.release();
  }
}

export async function getAdminSalesMerchantDetails({
  merchantId,
  period = "day",
  from = null,
  to = null,
  limit = 120,
  offset = 0,
} = {}) {
  const client = await pool.connect();
  try {
    const numericMerchantId = Number(merchantId);
    if (!Number.isFinite(numericMerchantId) || numericMerchantId <= 0) {
      throw new AppError("MERCHANT_NOT_FOUND", { status: 404 });
    }
    const merchant = await client.query(
      `SELECT id, name
       FROM merchant
       WHERE id = $1
       LIMIT 1`,
      [numericMerchantId]
    );
    if (!merchant.rows[0]) throw new AppError("MERCHANT_NOT_FOUND", { status: 404 });

    const window = parseWindow({ period, from, to });
    const cappedLimit = sanitizeLimit(limit, 120, 500);
    const safeOffset = sanitizeOffset(offset, 0);
    const rows = await client.query(
      `SELECT
         o.id AS order_id,
         COALESCE(inv.issued_at, o.created_at) AS created_at,
         o.status,
         o.total_amount,
         COALESCE(inv.subtotal, o.subtotal)::numeric AS subtotal,
         COALESCE(inv.commission_amount, 0)::numeric AS commission_amount,
         COALESCE(inv.service_fee_amount, 0)::numeric AS service_fee_amount,
         COALESCE(inv.app_delivery_fee_amount, 0)::numeric AS app_delivery_fee_amount,
         COALESCE(inv.store_delivery_fee_amount, 0)::numeric AS store_delivery_fee_amount,
         COALESCE(inv.app_receivable_amount, 0)::numeric AS app_receivable_amount,
         COALESCE(inv.store_net_amount, 0)::numeric AS store_net_amount,
         o.delivery_fee,
         o.courier_source,
         o.note,
         u.full_name AS customer_name,
         u.phone AS customer_phone
       FROM merchant_receivable_invoice inv
       JOIN customer_order o ON o.id = inv.order_id
       LEFT JOIN app_user u ON u.id = o.customer_user_id
       WHERE inv.merchant_id = $1
         AND inv.issued_at >= $2::timestamptz
         AND inv.issued_at <= $3::timestamptz
       ORDER BY inv.issued_at DESC, inv.id DESC
       LIMIT $4 OFFSET $5`,
      [numericMerchantId, window.start, window.end, cappedLimit, safeOffset]
    );

    const counts = await client.query(
      `SELECT
         COUNT(*)::int AS total_orders,
         COALESCE(SUM(inv.subtotal), 0)::numeric AS total_sales
       FROM merchant_receivable_invoice inv
       WHERE inv.merchant_id = $1
         AND inv.issued_at >= $2::timestamptz
         AND inv.issued_at <= $3::timestamptz`,
      [numericMerchantId, window.start, window.end]
    );

    return {
      window,
      currency: "IQD",
      merchant: {
        id: Number(merchant.rows[0].id),
        name: merchant.rows[0].name,
      },
      summary: {
        totalOrders: Number(counts.rows[0]?.total_orders || 0),
        totalSales: toNumber(counts.rows[0]?.total_sales, 0),
      },
      items: rows.rows.map((row) => ({
        order_id: Number(row.order_id),
        created_at: row.created_at,
        status: row.status,
        total_amount: toNumber(row.total_amount, 0),
        subtotal: toNumber(row.subtotal, 0),
        commission_amount: toNumber(row.commission_amount, 0),
        service_fee_amount: toNumber(row.service_fee_amount, 0),
        app_delivery_fee_amount: toNumber(row.app_delivery_fee_amount, 0),
        store_delivery_fee_amount: toNumber(row.store_delivery_fee_amount, 0),
        app_receivable_amount: toNumber(row.app_receivable_amount, 0),
        store_net_amount: toNumber(row.store_net_amount, 0),
        delivery_fee: toNumber(row.delivery_fee, 0),
        courier_source: row.courier_source,
        customer_name: row.customer_name,
        customer_phone: row.customer_phone,
        note: row.note,
      })),
      pagination: {
        limit: cappedLimit,
        offset: safeOffset,
        total: Number(counts.rows[0]?.total_orders || 0),
      },
    };
  } finally {
    client.release();
  }
}

export async function getAdminCollectionsReport({
  period = "day",
  from = null,
  to = null,
  search = null,
  limit = 120,
  offset = 0,
} = {}) {
  const client = await pool.connect();
  try {
    const window = parseWindow({ period, from, to });
    const cappedLimit = sanitizeLimit(limit, 120, 500);
    const safeOffset = sanitizeOffset(offset, 0);
    const params = [];
    const whereSearch = merchantSearchClause(search, params, "m");

    params.push(window.start, window.end, cappedLimit, safeOffset);
    const startParam = params.length - 3;
    const endParam = params.length - 2;
    const limitParam = params.length - 1;
    const offsetParam = params.length;

    const rows = await client.query(
      `SELECT
         m.id AS merchant_id,
         m.name AS merchant_name,
         COALESCE(COUNT(pr.id), 0)::int AS operations_count,
         COALESCE(SUM(COALESCE(pr.paid_amount, pr.requested_amount, pr.amount)), 0)::numeric AS total_collected,
         MIN(COALESCE(pr.final_confirmed_at, pr.reviewed_at, pr.submitted_at)) AS first_collected_at,
         MAX(COALESCE(pr.final_confirmed_at, pr.reviewed_at, pr.submitted_at)) AS last_collected_at
       FROM merchant m
       LEFT JOIN merchant_payment_request pr
         ON pr.merchant_id = m.id
        AND pr.request_type = 'store_pays_app'
        AND pr.status = 'confirmed_by_admin'
        AND COALESCE(pr.final_confirmed_at, pr.reviewed_at, pr.submitted_at) >= $${startParam}::timestamptz
        AND COALESCE(pr.final_confirmed_at, pr.reviewed_at, pr.submitted_at) <= $${endParam}::timestamptz
       ${whereSearch}
       GROUP BY m.id, m.name
       ORDER BY total_collected DESC, operations_count DESC, m.id DESC
       LIMIT $${limitParam} OFFSET $${offsetParam}`,
      params
    );

    const totals = await computeFinancialKpisTx(client, { window });
    const totalRows = await client.query(
      `SELECT COUNT(*)::int AS total
       FROM merchant m
       ${whereSearch}`,
      params.slice(0, whereSearch ? 1 : 0)
    );

    return {
      window,
      currency: "IQD",
      summary: {
        totalCollected: totals.totalCollected,
        totalOperations: totals.totalCollectionOperations,
        merchantsCount: Number(totalRows.rows[0]?.total || 0),
      },
      merchants: rows.rows.map((row) => ({
        merchant_id: Number(row.merchant_id),
        merchant_name: row.merchant_name,
        operations_count: Number(row.operations_count || 0),
        total_collected: toNumber(row.total_collected, 0),
        first_collected_at: row.first_collected_at,
        last_collected_at: row.last_collected_at,
      })),
      pagination: {
        limit: cappedLimit,
        offset: safeOffset,
        total: Number(totalRows.rows[0]?.total || 0),
      },
    };
  } finally {
    client.release();
  }
}

export async function getAdminCollectionsMerchantDetails({
  merchantId,
  period = "day",
  from = null,
  to = null,
  limit = 120,
  offset = 0,
} = {}) {
  const client = await pool.connect();
  try {
    const numericMerchantId = Number(merchantId);
    if (!Number.isFinite(numericMerchantId) || numericMerchantId <= 0) {
      throw new AppError("MERCHANT_NOT_FOUND", { status: 404 });
    }
    const merchant = await client.query(
      `SELECT id, name
       FROM merchant
       WHERE id = $1
       LIMIT 1`,
      [numericMerchantId]
    );
    if (!merchant.rows[0]) throw new AppError("MERCHANT_NOT_FOUND", { status: 404 });

    const window = parseWindow({ period, from, to });
    const cappedLimit = sanitizeLimit(limit, 120, 500);
    const safeOffset = sanitizeOffset(offset, 0);

    const rows = await client.query(
      `SELECT
         pr.id AS payment_request_id,
         pr.payment_scope,
         pr.status,
         pr.amount,
         pr.requested_amount,
         pr.paid_amount,
         pr.payment_method,
         pr.payment_date,
         pr.reference_code,
         pr.receiver_name,
         pr.review_note,
         pr.submitted_at,
         pr.reviewed_at,
         pr.final_confirmed_at,
         COALESCE(pr.final_confirmed_at, pr.reviewed_at, pr.submitted_at) AS event_at
       FROM merchant_payment_request pr
       WHERE pr.merchant_id = $1
         AND pr.request_type = 'store_pays_app'
         AND pr.status = 'confirmed_by_admin'
         AND COALESCE(pr.final_confirmed_at, pr.reviewed_at, pr.submitted_at) >= $2::timestamptz
         AND COALESCE(pr.final_confirmed_at, pr.reviewed_at, pr.submitted_at) <= $3::timestamptz
       ORDER BY event_at DESC, pr.id DESC
       LIMIT $4 OFFSET $5`,
      [numericMerchantId, window.start, window.end, cappedLimit, safeOffset]
    );

    const counts = await client.query(
      `SELECT
         COUNT(*)::int AS total_operations,
         COALESCE(SUM(COALESCE(pr.paid_amount, pr.requested_amount, pr.amount)), 0)::numeric AS total_collected
       FROM merchant_payment_request pr
       WHERE pr.merchant_id = $1
         AND pr.request_type = 'store_pays_app'
         AND pr.status = 'confirmed_by_admin'
         AND COALESCE(pr.final_confirmed_at, pr.reviewed_at, pr.submitted_at) >= $2::timestamptz
         AND COALESCE(pr.final_confirmed_at, pr.reviewed_at, pr.submitted_at) <= $3::timestamptz`,
      [numericMerchantId, window.start, window.end]
    );

    return {
      window,
      currency: "IQD",
      merchant: {
        id: Number(merchant.rows[0].id),
        name: merchant.rows[0].name,
      },
      summary: {
        totalOperations: Number(counts.rows[0]?.total_operations || 0),
        totalCollected: toNumber(counts.rows[0]?.total_collected, 0),
      },
      items: rows.rows.map((row) => ({
        payment_request_id: Number(row.payment_request_id),
        payment_scope: row.payment_scope,
        status: row.status,
        amount: toNumber(row.amount, 0),
        requested_amount: toNumber(row.requested_amount, 0),
        paid_amount: toNumber(row.paid_amount, 0),
        payment_method: row.payment_method,
        payment_date: row.payment_date,
        reference_code: row.reference_code,
        receiver_name: row.receiver_name,
        review_note: row.review_note,
        submitted_at: row.submitted_at,
        reviewed_at: row.reviewed_at,
        final_confirmed_at: row.final_confirmed_at,
        event_at: row.event_at,
      })),
      pagination: {
        limit: cappedLimit,
        offset: safeOffset,
        total: Number(counts.rows[0]?.total_operations || 0),
      },
    };
  } finally {
    client.release();
  }
}

export async function getAdminReceivablesReport({
  period = "day",
  from = null,
  to = null,
  search = null,
  limit = 120,
  offset = 0,
} = {}) {
  const client = await pool.connect();
  try {
    const window = parseWindow({ period, from, to });
    const cappedLimit = sanitizeLimit(limit, 120, 500);
    const safeOffset = sanitizeOffset(offset, 0);
    const params = [window.start, window.end];
    let searchClause = "";
    const safeSearch = sanitizeSearch(search);
    if (safeSearch) {
      params.push(`%${safeSearch}%`);
      searchClause = `WHERE m.name ILIKE $${params.length}`;
    }
    params.push(cappedLimit, safeOffset);
    const limitParam = params.length - 1;
    const offsetParam = params.length;

    const rows = await client.query(
      `WITH receivables AS (
         SELECT
           inv.merchant_id,
           COUNT(*)::int AS orders_count,
           COALESCE(SUM(inv.app_receivable_amount), 0)::numeric AS total_app_due
         FROM merchant_receivable_invoice inv
         WHERE inv.issued_at >= $1::timestamptz
           AND inv.issued_at <= $2::timestamptz
         GROUP BY inv.merchant_id
       ),
       collections AS (
         SELECT
           pr.merchant_id,
           COUNT(*)::int AS operations_count,
           COALESCE(SUM(COALESCE(pr.paid_amount, pr.requested_amount, pr.amount)), 0)::numeric AS total_collected
         FROM merchant_payment_request pr
         WHERE pr.request_type = 'store_pays_app'
           AND pr.status = 'confirmed_by_admin'
           AND COALESCE(pr.final_confirmed_at, pr.reviewed_at, pr.submitted_at) >= $1::timestamptz
           AND COALESCE(pr.final_confirmed_at, pr.reviewed_at, pr.submitted_at) <= $2::timestamptz
         GROUP BY pr.merchant_id
       )
       SELECT
         m.id AS merchant_id,
         m.name AS merchant_name,
         COALESCE(r.orders_count, 0)::int AS orders_count,
         COALESCE(c.operations_count, 0)::int AS collection_operations_count,
         COALESCE(r.total_app_due, 0)::numeric AS total_sales,
         COALESCE(c.total_collected, 0)::numeric AS total_collected,
         (COALESCE(c.total_collected, 0) - COALESCE(r.total_app_due, 0))::numeric AS net_receivables,
         (COALESCE(r.total_app_due, 0) - COALESCE(c.total_collected, 0))::numeric AS outstanding_to_collect
       FROM merchant m
       LEFT JOIN receivables r ON r.merchant_id = m.id
       LEFT JOIN collections c ON c.merchant_id = m.id
       ${searchClause}
       ORDER BY outstanding_to_collect DESC, m.id DESC
       LIMIT $${limitParam} OFFSET $${offsetParam}`,
      params
    );

    const totals = await computeFinancialKpisTx(client, { window });
    const countSearchClause = safeSearch ? "WHERE m.name ILIKE $1" : "";
    const countRows = await client.query(
      `SELECT COUNT(*)::int AS total
       FROM merchant m
       ${countSearchClause}`,
      safeSearch ? [`%${safeSearch}%`] : []
    );

    return {
      window,
      currency: "IQD",
      summary: {
        totalSales: totals.totalAppDue,
        totalCollected: totals.totalCollected,
        netReceivables: totals.netReceivables,
        outstandingToCollect: totals.outstandingToCollect,
        merchantsCount: Number(countRows.rows[0]?.total || 0),
      },
      merchants: rows.rows.map((row) => ({
        merchant_id: Number(row.merchant_id),
        merchant_name: row.merchant_name,
        orders_count: Number(row.orders_count || 0),
        collection_operations_count: Number(
          row.collection_operations_count || 0
        ),
        total_sales: toNumber(row.total_sales, 0),
        total_collected: toNumber(row.total_collected, 0),
        net_receivables: toNumber(row.net_receivables, 0),
        outstanding_to_collect: toNumber(row.outstanding_to_collect, 0),
      })),
      pagination: {
        limit: cappedLimit,
        offset: safeOffset,
        total: Number(countRows.rows[0]?.total || 0),
      },
    };
  } finally {
    client.release();
  }
}

export async function getAdminReceivablesMerchantStatement({
  merchantId,
  period = "day",
  from = null,
  to = null,
  limit = 120,
  offset = 0,
} = {}) {
  const client = await pool.connect();
  try {
    const numericMerchantId = Number(merchantId);
    if (!Number.isFinite(numericMerchantId) || numericMerchantId <= 0) {
      throw new AppError("MERCHANT_NOT_FOUND", { status: 404 });
    }
    const merchant = await client.query(
      `SELECT id, name
       FROM merchant
       WHERE id = $1
       LIMIT 1`,
      [numericMerchantId]
    );
    if (!merchant.rows[0]) throw new AppError("MERCHANT_NOT_FOUND", { status: 404 });

    const window = parseWindow({ period, from, to });
    const cappedLimit = sanitizeLimit(limit, 120, 500);
    const safeOffset = sanitizeOffset(offset, 0);

    const openingBeforeWindow = await client.query(
      `WITH receivables_before AS (
         SELECT COALESCE(SUM(inv.app_receivable_amount), 0)::numeric AS amount
         FROM merchant_receivable_invoice inv
         WHERE inv.merchant_id = $1
           AND inv.issued_at < $2::timestamptz
       ),
       collections_before AS (
         SELECT COALESCE(SUM(COALESCE(pr.paid_amount, pr.requested_amount, pr.amount)), 0)::numeric AS amount
         FROM merchant_payment_request pr
         WHERE pr.merchant_id = $1
           AND pr.request_type = 'store_pays_app'
           AND pr.status = 'confirmed_by_admin'
           AND COALESCE(pr.final_confirmed_at, pr.reviewed_at, pr.submitted_at) < $2::timestamptz
       )
       SELECT
         (SELECT amount FROM collections_before) - (SELECT amount FROM receivables_before) AS opening_balance`,
      [numericMerchantId, window.start]
    );

    const statementRows = await client.query(
      `WITH events AS (
         SELECT
           inv.issued_at AS event_at,
           'receivable_invoice'::text AS source_type,
           inv.order_id::bigint AS source_id,
           ('Invoice ' || inv.invoice_number || ' / Order #' || inv.order_id)::text AS description,
           inv.app_receivable_amount::numeric AS debit,
           0::numeric AS credit
         FROM merchant_receivable_invoice inv
         WHERE inv.merchant_id = $1
           AND inv.issued_at >= $2::timestamptz
           AND inv.issued_at <= $3::timestamptz

         UNION ALL

         SELECT
           COALESCE(pr.final_confirmed_at, pr.reviewed_at, pr.submitted_at) AS event_at,
           'collection_payment'::text AS source_type,
           pr.id::bigint AS source_id,
           ('Payment request #' || pr.id)::text AS description,
           0::numeric AS debit,
           COALESCE(pr.paid_amount, pr.requested_amount, pr.amount)::numeric AS credit
         FROM merchant_payment_request pr
         WHERE pr.merchant_id = $1
           AND pr.request_type = 'store_pays_app'
           AND pr.status = 'confirmed_by_admin'
           AND COALESCE(pr.final_confirmed_at, pr.reviewed_at, pr.submitted_at) >= $2::timestamptz
           AND COALESCE(pr.final_confirmed_at, pr.reviewed_at, pr.submitted_at) <= $3::timestamptz
       ),
       ranked AS (
         SELECT
           e.*,
           SUM(e.credit - e.debit) OVER (
             ORDER BY e.event_at ASC, e.source_id ASC
             ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
           )::numeric AS balance_delta
         FROM events e
       )
       SELECT *
       FROM ranked
       ORDER BY event_at DESC, source_id DESC
       LIMIT $4 OFFSET $5`,
      [numericMerchantId, window.start, window.end, cappedLimit, safeOffset]
    );

    const countRows = await client.query(
      `WITH events AS (
         SELECT inv.id
         FROM merchant_receivable_invoice inv
         WHERE inv.merchant_id = $1
           AND inv.issued_at >= $2::timestamptz
           AND inv.issued_at <= $3::timestamptz
         UNION ALL
         SELECT pr.id
         FROM merchant_payment_request pr
         WHERE pr.merchant_id = $1
           AND pr.request_type = 'store_pays_app'
           AND pr.status = 'confirmed_by_admin'
           AND COALESCE(pr.final_confirmed_at, pr.reviewed_at, pr.submitted_at) >= $2::timestamptz
           AND COALESCE(pr.final_confirmed_at, pr.reviewed_at, pr.submitted_at) <= $3::timestamptz
       )
       SELECT COUNT(*)::int AS total
       FROM events`,
      [numericMerchantId, window.start, window.end]
    );

    const totals = await computeFinancialKpisTx(client, {
      window,
      merchantId: numericMerchantId,
    });
    const openingBalance = toNumber(openingBeforeWindow.rows[0]?.opening_balance, 0);

    return {
      window,
      currency: "IQD",
      merchant: {
        id: Number(merchant.rows[0].id),
        name: merchant.rows[0].name,
      },
      summary: {
        openingBalance,
        totalSales: totals.totalAppDue,
        totalCollected: totals.totalCollected,
        netReceivables: totals.netReceivables,
        outstandingToCollect: totals.outstandingToCollect,
      },
      statement: statementRows.rows.map((row) => ({
        event_at: row.event_at,
        source_type: row.source_type,
        source_id: Number(row.source_id || 0),
        description: row.description,
        debit: toNumber(row.debit, 0),
        credit: toNumber(row.credit, 0),
        balance_after: round2(openingBalance + toNumber(row.balance_delta, 0)),
      })),
      pagination: {
        limit: cappedLimit,
        offset: safeOffset,
        total: Number(countRows.rows[0]?.total || 0),
      },
    };
  } finally {
    client.release();
  }
}

export async function getAdminPlatformKpis({ period, from, to } = {}) {
  const client = await pool.connect();
  try {
    const window = parseWindow({ period, from, to });
    await backfillMissingOrderReceivablesTx(client, { maxOrders: 4000 });
    const financial = await computeFinancialKpisTx(client, { window });

    const orders = await client.query(
      `SELECT
         COUNT(*)::int AS total_orders,
         COUNT(*) FILTER (WHERE status IN ('completed','delivered','delivered_by_courier','received_by_customer'))::int AS completed_orders,
         COUNT(*) FILTER (WHERE status IN ('cancelled','cancelled_by_store','cancelled_by_admin','cancelled_by_customer'))::int AS cancelled_orders,
         COALESCE(SUM(total_amount),0)::numeric AS gross_sales
       FROM customer_order
       WHERE created_at >= $1::timestamptz
         AND created_at <= $2::timestamptz`,
      [window.start, window.end]
    );

    const receivables = await client.query(
      `SELECT
         COALESCE(SUM(CASE WHEN direction='debit' THEN amount ELSE 0 END),0)::numeric AS total_debit,
         COALESCE(SUM(CASE WHEN direction='credit' THEN amount ELSE 0 END),0)::numeric AS total_credit
       FROM merchant_receivables_ledger
       WHERE created_at >= $1::timestamptz
         AND created_at <= $2::timestamptz`,
      [window.start, window.end]
    );

    const competitions = await client.query(
      `SELECT
         COUNT(*)::int AS total_competitions,
         COUNT(*) FILTER (WHERE is_active = TRUE AND status IN ('active','draft'))::int AS active_competitions,
         COUNT(*) FILTER (WHERE status = 'ended' OR end_at < NOW())::int AS ended_competitions,
         (
           SELECT COUNT(*)::int
           FROM courier_competition_result ccr
           WHERE ccr.won = TRUE
         ) AS total_winners,
         (
           SELECT COALESCE(SUM(ccr.reward_amount),0)::numeric
           FROM courier_competition_result ccr
           WHERE ccr.won = TRUE
         ) AS total_rewards,
         (
           SELECT ccr.courier_user_id
           FROM courier_competition_result ccr
           WHERE ccr.won = TRUE
           GROUP BY ccr.courier_user_id
           ORDER BY COUNT(*) DESC, SUM(ccr.reward_amount) DESC, ccr.courier_user_id ASC
           LIMIT 1
         ) AS top_courier_user_id
       FROM courier_competition`
    );

    const o = orders.rows[0] || {};
    const r = receivables.rows[0] || {};
    const c = competitions.rows[0] || {};
    return {
      window,
      platform: {
        totalOrders: Number(o.total_orders || 0),
        completedOrders: Number(o.completed_orders || 0),
        cancelledOrders: Number(o.cancelled_orders || 0),
        grossSales: toNumber(o.gross_sales, 0),
        receivableDebits: toNumber(r.total_debit, 0),
        receivableCredits: toNumber(r.total_credit, 0),
        outstandingReceivables: round2(
          toNumber(r.total_debit, 0) - toNumber(r.total_credit, 0)
        ),
        totalCompetitions: Number(c.total_competitions || 0),
        activeCompetitions: Number(c.active_competitions || 0),
        endedCompetitions: Number(c.ended_competitions || 0),
        competitionWinners: Number(c.total_winners || 0),
        competitionRewards: toNumber(c.total_rewards, 0),
        topCourierUserId: c.top_courier_user_id ? Number(c.top_courier_user_id) : null,
      },
      financial: {
        totalSales: financial.totalSales,
        totalCollected: financial.totalCollected,
        netReceivables: financial.netReceivables,
        outstandingToCollect: financial.outstandingToCollect,
        totalSalesOrders: financial.totalSalesOrders,
        totalCollectionOperations: financial.totalCollectionOperations,
        currency: "IQD",
      },
    };
  } finally {
    client.release();
  }
}

export async function searchProductsGlobal(customerUserId, query = {}) {
  const qText = String(query?.q || "").trim();
  if (!qText) {
    throw new AppError("SEARCH_QUERY_REQUIRED", { status: 400 });
  }

  const safeLimit = Math.max(1, Math.min(120, Number(query?.limit) || 40));
  const safeOffset = Math.max(0, Number(query?.offset) || 0);
  const sort = String(query?.sort || "best_offers").trim().toLowerCase();
  const merchantType = query?.merchantType
    ? String(query.merchantType).trim().toLowerCase()
    : null;
  const onlyAvailable = query?.onlyAvailable === true;
  const onlyDiscounted = query?.onlyDiscounted === true;
  const minPrice = Number.isFinite(Number(query?.minPrice))
    ? Number(query.minPrice)
    : null;
  const maxPrice = Number.isFinite(Number(query?.maxPrice))
    ? Number(query.maxPrice)
    : null;
  const minRating = Number.isFinite(Number(query?.minRating))
    ? Number(query.minRating)
    : null;
  const orderableSql = `
    CASE
      WHEN COALESCE(s.inventory_enabled, FALSE) = TRUE THEN
        CASE
          WHEN COALESCE(si.manual_disabled, FALSE) = TRUE THEN FALSE
          WHEN COALESCE(si.auto_disabled, FALSE) = TRUE THEN FALSE
          WHEN COALESCE(si.stock_status, 'in_stock') = 'manual_disabled' THEN FALSE
          WHEN COALESCE(si.quantity, 0) <= 0 THEN FALSE
          ELSE p.is_available
        END
      ELSE p.is_available
    END
  `;

  const userResult = await q(
    `SELECT city, block
     FROM app_user
     WHERE id = $1
     LIMIT 1`,
    [Number(customerUserId)]
  );
  const userCity = String(query?.city || userResult.rows[0]?.city || "").trim();
  const userBlock = String(query?.block || userResult.rows[0]?.block || "").trim();

  const params = [`%${qText}%`, qText, safeLimit + 1, safeOffset];
  const where = [
    "m.is_approved = TRUE",
    "m.is_disabled = FALSE",
    "(p.name ILIKE $1 OR COALESCE(p.description,'') ILIKE $1 OR to_tsvector('simple', COALESCE(p.name,'') || ' ' || COALESCE(p.description,'')) @@ plainto_tsquery('simple', $2))",
  ];

  if (merchantType) {
    params.push(merchantType);
    where.push(`m.type::text = $${params.length}`);
  }
  if (onlyAvailable) where.push(`(${orderableSql}) = TRUE`);
  if (onlyDiscounted) {
    where.push("(p.discounted_price IS NOT NULL AND p.discounted_price < p.price)");
  }
  if (minPrice != null) {
    params.push(minPrice);
    where.push(`COALESCE(p.discounted_price, p.price) >= $${params.length}`);
  }
  if (maxPrice != null) {
    params.push(maxPrice);
    where.push(`COALESCE(p.discounted_price, p.price) <= $${params.length}`);
  }
  if (minRating != null) {
    params.push(minRating);
    where.push(`COALESCE(ratings.avg_rating, 0) >= $${params.length}`);
  }

  let orderBy = "discount_percent DESC, final_price ASC, product_id DESC";
  switch (sort) {
    case "price_asc":
      orderBy = "final_price ASC, product_id DESC";
      break;
    case "most_ordered":
      orderBy = "orders_count DESC, final_price ASC, product_id DESC";
      break;
    case "rating_desc":
      orderBy = "merchant_rating DESC NULLS LAST, orders_count DESC, product_id DESC";
      break;
    case "nearest":
      orderBy = "proximity_rank ASC, merchant_rating DESC NULLS LAST, product_id DESC";
      break;
    case "fastest_delivery":
      orderBy = "eta_minutes ASC NULLS LAST, proximity_rank ASC, product_id DESC";
      break;
    case "best_offers":
    default:
      break;
  }

  params.push(userCity || null);
  const userCityIndex = params.length;
  params.push(userBlock || null);
  const userBlockIndex = params.length;

  const result = await q(
    `WITH ratings AS (
       SELECT
         merchant_id,
         AVG(rating)::numeric(5,2) AS avg_rating,
         COUNT(*)::int AS ratings_count
       FROM merchant_verified_review
       GROUP BY merchant_id
     ),
     product_orders AS (
       SELECT
         oi.product_id,
         COUNT(*)::int AS orders_count
       FROM order_item oi
       JOIN customer_order o ON o.id = oi.order_id
       WHERE o.status IN ('delivered', 'completed', 'received_by_customer')
       GROUP BY oi.product_id
     ),
     merchant_eta AS (
       SELECT
         o.merchant_id,
         AVG(EXTRACT(EPOCH FROM (COALESCE(o.delivered_at, o.updated_at) - o.created_at)) / 60.0)::numeric(8,2) AS eta_minutes
       FROM customer_order o
       WHERE o.status IN ('delivered', 'completed', 'received_by_customer')
         AND o.created_at >= NOW() - INTERVAL '60 days'
       GROUP BY o.merchant_id
     )
     SELECT
       p.id AS product_id,
       p.category_id AS product_category_id,
       c.name AS category_name,
       c.sort_order AS category_sort_order,
       p.name AS product_name,
       p.description AS product_description,
       p.image_url AS product_image_url,
       p.price AS base_price,
       p.discounted_price,
       COALESCE(p.discounted_price, p.price) AS final_price,
       CASE
         WHEN p.discounted_price IS NOT NULL AND p.price > 0
         THEN ROUND(((p.price - p.discounted_price) / p.price) * 100.0, 2)
         ELSE 0
       END AS discount_percent,
       p.is_available,
       COALESCE(s.inventory_enabled, FALSE) AS track_stock,
       CASE
         WHEN COALESCE(s.inventory_enabled, FALSE) = TRUE THEN 'tracked'
         ELSE 'untracked'
       END AS stock_mode,
       COALESCE(si.quantity, NULL) AS inventory_quantity,
       COALESCE(si.stock_status, NULL) AS inventory_stock_status,
       p.free_delivery,
       p.offer_label,
       m.id AS merchant_id,
       m.name AS merchant_name,
       m.type::text AS merchant_type,
       m.activity_type AS merchant_activity_type,
       m.image_url AS merchant_image_url,
       COALESCE(ratings.avg_rating, 0) AS merchant_rating,
       COALESCE(ratings.ratings_count, 0) AS merchant_ratings_count,
       COALESCE(product_orders.orders_count, 0) AS orders_count,
       merchant_eta.eta_minutes,
       CASE
         WHEN $${userBlockIndex}::text IS NOT NULL AND EXISTS (
           SELECT 1
           FROM customer_order co
           WHERE co.merchant_id = m.id
             AND co.customer_block IS NOT NULL
             AND UPPER(TRIM(co.customer_block)) = UPPER(TRIM($${userBlockIndex}::text))
           LIMIT 1
         ) THEN 0
         WHEN $${userCityIndex}::text IS NOT NULL AND EXISTS (
           SELECT 1
           FROM customer_order co
           WHERE co.merchant_id = m.id
             AND co.customer_city IS NOT NULL
             AND UPPER(TRIM(co.customer_city)) = UPPER(TRIM($${userCityIndex}::text))
           LIMIT 1
         ) THEN 1
         ELSE 2
       END AS proximity_rank
     FROM product p
     JOIN merchant m ON m.id = p.merchant_id
     LEFT JOIN merchant_category c ON c.id = p.category_id
     LEFT JOIN inventory_settings s ON s.merchant_id = p.merchant_id
     LEFT JOIN store_inventory_item si
       ON si.merchant_id = p.merchant_id
      AND si.product_id = p.id
     LEFT JOIN ratings ON ratings.merchant_id = m.id
     LEFT JOIN product_orders ON product_orders.product_id = p.id
     LEFT JOIN merchant_eta ON merchant_eta.merchant_id = m.id
     WHERE ${where.join(" AND ")}
     ORDER BY ${orderBy}
     LIMIT $3 OFFSET $4`,
    params
  );

  const hasMore = result.rows.length > safeLimit;
  const rows = hasMore ? result.rows.slice(0, safeLimit) : result.rows;
  const richCatalogMap = await loadProductRichCatalogByIds(
    rows.map((row) => Number(row.product_id))
  );

  return {
    query: qText,
    sort,
    filters: {
      merchantType,
      onlyAvailable,
      onlyDiscounted,
      minPrice,
      maxPrice,
      minRating,
      city: userCity || null,
      block: userBlock || null,
    },
    items: rows.map((row) => {
      const rich = richCatalogMap.get(Number(row.product_id)) || null;
      return mapSearchProductResultRow(row, rich);
    }),
    pagination: {
      limit: safeLimit,
      offset: safeOffset,
      nextOffset: hasMore ? safeOffset + safeLimit : null,
    },
  };
}

export function mapSearchProductResultRow(row, rich = null) {
  return {
    productId: Number(row.product_id),
    categoryId:
      row.product_category_id == null ? null : Number(row.product_category_id),
    categoryName: row.category_name || null,
    categorySortOrder:
      row.category_sort_order == null ? null : Number(row.category_sort_order),
    name: row.product_name,
    description: row.product_description,
    imageUrl: rich?.primaryMedia?.imageUrl || row.product_image_url,
    price: Number(row.base_price || 0),
    discountedPrice:
      row.discounted_price == null ? null : Number(row.discounted_price),
    finalPrice: Number(row.final_price || 0),
    discountPercent: Number(row.discount_percent || 0),
    isAvailable: row.is_available === true,
    trackStock: row.track_stock === true,
    stockMode: row.stock_mode || null,
    stockQuantity:
      row.inventory_quantity == null ? null : Number(row.inventory_quantity),
    freeDelivery: row.free_delivery === true,
    offerLabel: row.offer_label || null,
    hasVariants: rich?.hasVariants === true,
    summaryAttributes: rich?.summaryAttributes || rich?.highlights || [],
    variantGroups: rich?.variantGroups || [],
    variants: rich?.variants || [],
    media: rich?.media || [],
    primaryMedia: rich?.primaryMedia || null,
    merchant: {
      id: Number(row.merchant_id),
      name: row.merchant_name,
      type: row.merchant_type,
      activityType: row.merchant_activity_type || row.merchant_type,
      imageUrl: row.merchant_image_url,
      city: null,
      block: null,
      rating: Number(row.merchant_rating || 0),
      ratingsCount: Number(row.merchant_ratings_count || 0),
    },
    stats: {
      ordersCount: Number(row.orders_count || 0),
      etaMinutes: row.eta_minutes == null ? null : Number(row.eta_minutes),
      proximityRank: Number(row.proximity_rank || 2),
    },
  };
}


import * as repo from "./commerce.repo.js";
import { createManyNotifications } from "../notifications/notifications.repo.js";
import { getOrderActionReason } from "../orders/order-action-reasons.repo.js";
import * as ordersRepo from "../orders/orders.repo.js";
import { invalidateOrderListCacheForUser } from "../orders/orders.service.js";
import { emitRealtimeToUser } from "../../shared/realtime/realtime-gateway.js";
import { requestDeliveryAssignmentRecovery } from "../orders/delivery-assignment.worker.js";
import { q } from "../../config/db.js";

function inferModuleFromTarget(target) {
  const normalized = String(target || "").trim().toLowerCase();
  if (normalized.startsWith("courier")) return "courier";
  if (normalized.startsWith("delivery")) return "courier";
  if (normalized.startsWith("merchant")) return "merchant";
  if (normalized.startsWith("owner")) return "merchant";
  if (normalized.startsWith("customer")) return "customer";
  if (normalized.startsWith("admin")) return "admin";
  if (normalized.startsWith("taxi")) return "taxi";
  if (normalized.startsWith("social")) return "social";
  if (normalized.startsWith("jobs")) return "jobs";
  if (normalized === "order_tracking") return "customer";
  return "system";
}

function inferRoleScopeFromModule(module) {
  switch (String(module || "").trim().toLowerCase()) {
    case "courier":
      return "courier";
    case "merchant":
      return "owner";
    case "admin":
      return "admin";
    case "taxi":
      return "taxi_captain";
    case "customer":
      return "user";
    default:
      return "user";
  }
}

function toOrderPayload(order, target, options = {}) {
  const targetModule =
    options.targetModule || inferModuleFromTarget(target);
  const roleScope =
    options.roleScope || inferRoleScopeFromModule(targetModule);
  const orderId = Number(order?.id || 0);
  return {
    target,
    orderId,
    status: String(order?.status || "").trim().toLowerCase(),
    merchantId: order?.merchant_id ? Number(order.merchant_id) : null,
    targetModule,
    target_module: targetModule,
    roleScope,
    role_scope: roleScope,
    action: options.action || null,
    targetEntity: "order",
    target_entity: "order",
    entityId: orderId > 0 ? orderId : null,
    entity_id: orderId > 0 ? orderId : null,
    notificationType: options.notificationType || null,
    notification_type: options.notificationType || null,
  };
}

function invalidateCustomerOrderList(order) {
  const customerUserId = Number(order?.customer_user_id || 0);
  if (customerUserId > 0) {
    invalidateOrderListCacheForUser(customerUserId);
  }
}

async function notify(rows) {
  const list = Array.isArray(rows)
    ? rows.filter((row) => row && Number(row.userId || 0) > 0)
    : [];
  if (!list.length) return;
  const normalized = list.map((row) => {
    const payload =
      row.payload && typeof row.payload === "object" && !Array.isArray(row.payload)
        ? { ...row.payload }
        : {};
    const type = String(row.type || "").trim();
    if (type) {
      payload.notificationType = payload.notificationType || type;
      payload.notification_type = payload.notification_type || type;
    }
    return {
      ...row,
      payload,
    };
  });
  await createManyNotifications(normalized);
}

async function buildCompetitionNotifications({ out, orderId }) {
  const competitionUpdates = out?.competitionUpdates || {};
  const courierEvents = Array.isArray(competitionUpdates.courierEvents)
    ? competitionUpdates.courierEvents
    : [];
  const adminEvents = Array.isArray(competitionUpdates.adminEvents)
    ? competitionUpdates.adminEvents
    : [];
  const finalizedSummaryEvents = Array.isArray(
    competitionUpdates.finalized?.summaryEvents
  )
    ? competitionUpdates.finalized.summaryEvents
    : [];
  const finalizedCourierEvents = Array.isArray(
    competitionUpdates.finalized?.courierFinishedEvents
  )
    ? competitionUpdates.finalized.courierFinishedEvents
    : [];

  if (
    !courierEvents.length &&
    !adminEvents.length &&
    !finalizedSummaryEvents.length &&
    !finalizedCourierEvents.length
  ) {
    return [];
  }

  const adminRecipients = await repo.listBackofficeUserIds();
  const adminRecipientSet = new Set(
    adminRecipients.map((id) => Number(id)).filter((id) => id > 0)
  );

  const courierNotifications = courierEvents
    .filter((event) => Number(event.courierUserId || 0) > 0)
    .map((event) => ({
      userId: Number(event.courierUserId),
      type: String(event.type || "courier_competition_rank_unlocked"),
      title:
        String(event.type) === "courier_competition_upgraded_rank"
          ? "Competition rank upgraded"
          : "Competition rank unlocked",
      body:
        String(event.type) === "courier_competition_upgraded_rank"
          ? `You moved up to ${event.rankTitle || "a higher rank"} in ${event.competitionTitle || "competition"}.`
          : `You unlocked ${event.rankTitle || "a rank"} in ${event.competitionTitle || "competition"}.`,
      orderId: Number(event.orderId || 0) || undefined,
      merchantId: Number(out.order.merchant_id),
      payload: {
        ...toOrderPayload(out.order, "courier_competitions", {
          action: "open_courier_competitions",
          roleScope: "courier",
          notificationType: String(
            event.type || "courier_competition_rank_unlocked"
          ),
        }),
        competitionId: Number(event.competitionId || 0) || null,
        rankSortOrder: Number(event.rankSortOrder || 0) || null,
        rankTitle: event.rankTitle || null,
        currentCount: Number(event.currentCount || 0),
      },
    }));

  for (const event of finalizedCourierEvents) {
    if (Number(event.courierUserId || 0) <= 0) continue;
    courierNotifications.push({
      userId: Number(event.courierUserId),
      type: "courier_competition_finished",
      title: "Competition finished",
      body: event.won
        ? `You finished ${event.competitionTitle || "competition"} with ${event.rankTitle || "a winning rank"}.`
        : `${event.competitionTitle || "Competition"} has ended.`,
      orderId: Number(orderId),
      merchantId: Number(out.order.merchant_id),
      payload: {
        ...toOrderPayload(out.order, "courier_competitions", {
          action: "open_courier_competitions",
          roleScope: "courier",
          notificationType: "courier_competition_finished",
        }),
        competitionId: Number(event.competitionId || 0) || null,
        rankSortOrder: Number(event.rankSortOrder || 0) || null,
        rankTitle: event.rankTitle || null,
        won: event.won === true,
        finalCompletedOrders: Number(event.finalCompletedOrders || 0),
        rewardAmount: Number(event.rewardAmount || 0),
      },
    });
  }

  const adminEventRows = [
    ...adminEvents.map((event) => ({
      type: String(event.type || "admin_competition_new_winner"),
      title: "Competition winner update",
      body: `${event.rankTitle || "Rank"} unlocked in ${event.competitionTitle || "competition"}.`,
      payload: {
        target: "admin_competitions",
        targetModule: "admin",
        target_module: "admin",
        roleScope: "admin",
        role_scope: "admin",
        action: "open_admin_competition",
        targetEntity: "competition",
        target_entity: "competition",
        entityId: Number(event.competitionId || 0) || null,
        entity_id: Number(event.competitionId || 0) || null,
        notificationType: String(event.type || "admin_competition_new_winner"),
        notification_type: String(event.type || "admin_competition_new_winner"),
        competitionId: Number(event.competitionId || 0) || null,
        courierUserId: Number(event.courierUserId || 0) || null,
        rankSortOrder: Number(event.rankSortOrder || 0) || null,
        rankTitle: event.rankTitle || null,
      },
    })),
    ...finalizedSummaryEvents.map((event) => ({
      type: "admin_competition_finished_summary",
      title: "Competition finalized",
      body: `${event.competitionTitle || "Competition"} finished with ${Number(event.winnersCount || 0)} winner(s).`,
      payload: {
        target: "admin_competitions",
        targetModule: "admin",
        target_module: "admin",
        roleScope: "admin",
        role_scope: "admin",
        action: "open_admin_competition",
        targetEntity: "competition",
        target_entity: "competition",
        entityId: Number(event.competitionId || 0) || null,
        entity_id: Number(event.competitionId || 0) || null,
        notificationType: "admin_competition_finished_summary",
        notification_type: "admin_competition_finished_summary",
        competitionId: Number(event.competitionId || 0) || null,
        winnersCount: Number(event.winnersCount || 0),
        participantsCount: Number(event.participantsCount || 0),
      },
    })),
  ];

  const adminNotifications = [];
  for (const event of adminEventRows) {
    for (const adminId of adminRecipientSet) {
      adminNotifications.push({
        userId: adminId,
        type: event.type,
        title: event.title,
        body: event.body,
        orderId: Number(orderId),
        merchantId: Number(out.order.merchant_id),
        payload: event.payload,
      });
    }
  }

  return [...courierNotifications, ...adminNotifications];
}

export async function ownerStartPreparing(ownerUserId, orderId, body = {}) {
  const out = await repo.startPreparingAndRequestCourier({
    ownerUserId,
    orderId,
    preferredCourierUserId: body?.preferredCourierUserId ?? null,
    estimatedPrepMinutes: body?.estimatedPrepMinutes ?? null,
    note: body?.note ?? null,
  });
  invalidateCustomerOrderList(out.order);
  const courierTargets =
    Array.isArray(out.courierRecipients) && out.courierRecipients.length > 0
      ? out.courierRecipients
      : out.assignmentCreated === true && out.deliveryAssignment?.driver
        ? [out.deliveryAssignment.driver]
        : [];

  await notify([
    {
      userId: Number(out.order.customer_user_id),
      type: "order_status_update",
      title: "Order preparation started",
      body: `Store started preparing order #${out.order.id}.`,
      orderId: Number(out.order.id),
      merchantId: Number(out.order.merchant_id),
      payload: toOrderPayload(out.order, "order_tracking", {
        action: "open_order_tracking",
      }),
    },
    ...courierTargets.map((courier) => ({
      userId: Number(courier.id),
      type: "delivery_order_available",
      title: "New delivery request",
      body: `Order #${out.order.id} from ${out.merchantName || "store"} is available.`,
      orderId: Number(out.order.id),
      merchantId: Number(out.order.merchant_id),
      payload: {
        ...toOrderPayload(out.order, "courier_orders_current", {
          action: "open_order_offer",
          roleScope: "courier",
        }),
        requiresAction: true,
      },
    })),
  ]);

  return out;
}

export async function ownerAssignCourier(ownerUserId, orderId, body = {}) {
  const out = await repo.assignCourierByStore({
    ownerUserId,
    orderId,
    courierUserId: body?.courierUserId,
    assignmentMode: body?.assignmentMode || "manual",
    note: body?.note ?? null,
  });
  invalidateCustomerOrderList(out.order);

  return out;
}

export async function ownerReadyForPickup(ownerUserId, orderId, body = {}) {
  const out = await repo.markReadyForPickupByStore({
    ownerUserId,
    orderId,
    estimatedDeliveryMinutes: body?.estimatedDeliveryMinutes ?? null,
    note: body?.note ?? null,
  });
  invalidateCustomerOrderList(out.order);
  const courierTargets =
    (Array.isArray(out.courierRecipients) && out.courierRecipients.length > 0
      ? out.courierRecipients
      : out.deliveryAssignment?.driver
        ? [out.deliveryAssignment.driver]
        : []);

  await notify([
    {
      userId: Number(out.order.customer_user_id),
      type: "order_status_update",
      title: "Order ready for delivery",
      body: `Order #${out.order.id} is ready for pickup.`,
      orderId: Number(out.order.id),
      merchantId: Number(out.order.merchant_id),
      payload: toOrderPayload(out.order, "order_tracking", {
        action: "open_order_tracking",
      }),
    },
    ...courierTargets.map((courier) => ({
      userId: Number(courier.id),
      type: "delivery_order_ready_for_pickup",
      title: "Order ready for pickup",
      body: `Order #${out.order.id} from ${out.merchantName || "store"} is ready.`,
      orderId: Number(out.order.id),
      merchantId: Number(out.order.merchant_id),
      payload: {
        ...toOrderPayload(out.order, "courier_orders_current", {
          action: "open_ready_for_pickup",
          roleScope: "courier",
        }),
        requiresAction: true,
      },
    })),
  ]);

  return out;
}

export async function courierAcceptOrder(courierUserId, orderId, body = {}) {
  const out = await repo.courierAcceptAssignment({
    courierUserId,
    orderId,
    note: body?.note ?? null,
  });
  invalidateCustomerOrderList(out.order);

  await notify([
    {
      userId: Number(out.order.owner_user_id),
      type: "owner_delivery_assigned",
      title: "Courier accepted order",
      body: `${out.courier.full_name || "Courier"} accepted order #${orderId}.`,
      orderId: Number(orderId),
      merchantId: Number(out.order.merchant_id),
      payload: {
        ...toOrderPayload(out.order, "owner_orders", {
          action: "open_owner_order",
          roleScope: "owner",
        }),
        courierId: Number(out.courier.id),
      },
    },
    {
      userId: Number(out.order.customer_user_id),
      type: "order_courier_assigned",
      title: "Courier assigned",
      body: "Courier is heading to store for your order.",
      orderId: Number(orderId),
      merchantId: Number(out.order.merchant_id),
      payload: toOrderPayload(out.order, "order_tracking", {
        action: "open_order_tracking",
      }),
    },
  ]);

  return out;
}

export async function courierRejectOrder(courierUserId, orderId, body = {}) {
  const out = await repo.courierRejectAssignment({
    courierUserId,
    orderId,
    note: body?.note ?? null,
  });
  invalidateCustomerOrderList(out.order);

  if (Number(out.pendingCount || 0) === 0 && out.order?.owner_user_id) {
    await notify([
      {
        userId: Number(out.order.owner_user_id),
        type: "owner_delivery_pool_empty",
        title: "No courier accepted yet",
        body: `No courier accepted order #${orderId} yet.`,
        orderId: Number(orderId),
        merchantId: Number(out.order.merchant_id),
        payload: {
          orderId: Number(orderId),
          target: "owner_orders",
          targetModule: "merchant",
          target_module: "merchant",
          roleScope: "owner",
          role_scope: "owner",
          action: "open_owner_orders",
          targetEntity: "order",
          target_entity: "order",
          entityId: Number(orderId),
          entity_id: Number(orderId),
        },
      },
    ]);
  }

  return out;
}

export async function courierPickedUpOrder(courierUserId, orderId, body = {}) {
  const out = await repo.courierMarkPickedUp({
    courierUserId,
    orderId,
    note: body?.note ?? null,
  });
  invalidateCustomerOrderList(out.order);

  await notify([
    {
      userId: Number(out.order.customer_user_id),
      type: "order_status_update",
      title: "Order picked up",
      body: `Courier picked up order #${orderId}.`,
      orderId: Number(orderId),
      merchantId: Number(out.order.merchant_id),
      payload: toOrderPayload(out.order, "order_tracking"),
    },
    {
      userId: Number(out.ownerUserId),
      type: "owner_order_picked_up",
      title: "Order picked up by courier",
      body: `Courier picked up order #${orderId}.`,
      orderId: Number(orderId),
      merchantId: Number(out.order.merchant_id),
      payload: toOrderPayload(out.order, "owner_orders"),
    },
  ]);

  return out;
}

export async function courierArrivedOrder(courierUserId, orderId, body = {}) {
  const out = await repo.courierMarkArrived({
    courierUserId,
    orderId,
    note: body?.note ?? null,
  });
  invalidateCustomerOrderList(out.order);

  await notify([
    {
      userId: Number(out.order.customer_user_id),
      type: "order_status_update",
      title: "Courier arrived",
      body: `Courier arrived for order #${orderId}.`,
      orderId: Number(orderId),
      merchantId: Number(out.order.merchant_id),
      payload: toOrderPayload(out.order, "order_tracking"),
    },
  ]);

  return out;
}

export async function courierDeliveredOrder(courierUserId, orderId, body = {}) {
  const out = await repo.courierMarkDelivered({
    courierUserId,
    orderId,
    note: body?.note ?? null,
  });
  invalidateCustomerOrderList(out.order);

  await notify([
    {
      userId: Number(out.order.customer_user_id),
      type: "order_status_update",
      title: "Order delivered",
      body: `Order #${orderId} was delivered. Please confirm receipt.`,
      orderId: Number(orderId),
      merchantId: Number(out.order.merchant_id),
      payload: toOrderPayload(out.order, "order_tracking"),
    },
    {
      userId: Number(out.ownerUserId),
      type: "owner_order_delivered",
      title: "Order delivered to customer",
      body: `Courier delivered order #${orderId}.`,
      orderId: Number(orderId),
      merchantId: Number(out.order.merchant_id),
      payload: toOrderPayload(out.order, "owner_orders"),
    },
  ]);

  return out;
}

export async function courierUpsertPresence(courierUserId, body = {}) {
  const orderId = body?.orderId == null ? null : Number(body.orderId);
  let trackedOrder = null;
  if (orderId != null) {
    trackedOrder = await ordersRepo.findCourierTrackableOrder(courierUserId, orderId);
    if (!trackedOrder) {
      const error = new Error("ORDER_NOT_AVAILABLE");
      error.status = 404;
      throw error;
    }
  }

  const isOnline = body.isOnline !== false;
  const presence = await ordersRepo.upsertCourierPresence({
    courierUserId,
    orderId,
    latitude: body.latitude == null ? null : Number(body.latitude),
    longitude: body.longitude == null ? null : Number(body.longitude),
    headingDeg: body.headingDeg == null ? null : Number(body.headingDeg),
    speedKmh: body.speedKmh == null ? null : Number(body.speedKmh),
    accuracyM: body.accuracyM == null ? null : Number(body.accuracyM),
    isOnline,
  });

  // Keep courier_profile.availability_status in sync with the heartbeat's
  // declared availability. Eligibility requires availability_status='online',
  // so a driver whose profile was left 'offline'/'away' would otherwise stay
  // invisible to auto-assignment despite sending fresh presence.
  await q(
    `UPDATE courier_profile
     SET availability_status = $2, updated_at = NOW()
     WHERE user_id = $1
       AND COALESCE(LOWER(availability_status), '') <> $2`,
    [Number(courierUserId), isOnline ? "online" : "offline"]
  );

  // Phase 10: a heartbeat from an idle, available driver should immediately try
  // to clear the oldest PENDING_NO_DRIVER order rather than waiting for the
  // periodic recovery worker. The recovery run coalesces across concurrent
  // callers and is a no-op when nothing is pending, so this is cheap.
  if (orderId == null && isOnline) {
    void requestDeliveryAssignmentRecovery({ limit: 5 }).catch(() => {});
  }

  if (trackedOrder?.customer_user_id) {
    const snapshot = await ordersRepo.getCustomerOrderTrackingSnapshot(
      Number(trackedOrder.customer_user_id),
      Number(trackedOrder.id)
    );
    if (snapshot) {
      const trackingEvent = {
          orderId: Number(trackedOrder.id),
          status: trackedOrder.status,
          stage: snapshot.stage,
          latestLocation: snapshot.latestLocation,
          lastUpdatedAt: snapshot.lastUpdatedAt,
          target: "order_tracking",
      };
      const viewers = new Set(
        [
          trackedOrder.customer_user_id,
          trackedOrder.owner_user_id,
          trackedOrder.delivery_user_id,
        ]
          .map(Number)
          .filter((id) => Number.isInteger(id) && id > 0)
      );
      await Promise.all(
        [...viewers].map((viewerUserId) =>
          emitRealtimeToUser(viewerUserId, "order_tracking_update", trackingEvent, {
            channel: "notifications",
          })
        )
      );
    }
  }

  return {
    presence,
    orderId: trackedOrder ? Number(trackedOrder.id) : orderId,
  };
}

export async function customerConfirmReceived(customerUserId, orderId, body = {}) {
  const out = await repo.customerConfirmOrderReceived({
    customerUserId,
    orderId,
    note: body?.note ?? null,
  });
  invalidateCustomerOrderList(out.order);

  const competitionNotifications = await buildCompetitionNotifications({
    out,
    orderId,
  });

  await notify([
    {
      userId: Number(out.ownerUserId),
      type: "owner_customer_received",
      title: "Customer confirmed receipt",
      body: `Customer confirmed receiving order #${orderId}.`,
      orderId: Number(orderId),
      merchantId: Number(out.order.merchant_id),
      payload: toOrderPayload(out.order, "owner_orders", {
        action: "open_owner_order",
        roleScope: "owner",
      }),
    },
    ...(out.courierUserId
      ? [
          {
            userId: Number(out.courierUserId),
            type: "delivery_customer_received",
            title: "Receipt confirmed",
            body: `Customer confirmed order #${orderId}.`,
            orderId: Number(orderId),
            merchantId: Number(out.order.merchant_id),
            payload: toOrderPayload(out.order, "courier_orders_completed", {
              action: "open_completed_order",
              roleScope: "courier",
            }),
          },
        ]
      : []),
    ...competitionNotifications,
  ]);

  return out;
}

export async function courierRequestCancelOrder(courierUserId, orderId, body = {}) {
  const reasonCode = String(body?.reasonCode || "").trim().toLowerCase();
  const reasonText =
    body?.reasonText == null ? null : String(body.reasonText).trim() || null;
  const reasonMeta = await getOrderActionReason({
    actorScope: "courier",
    actionKind: "cancel",
    reasonCode,
  });
  if (!reasonMeta) {
    const error = new Error("ORDER_ACTION_REASON_INVALID");
    error.status = 400;
    throw error;
  }
  if (reasonMeta.allowsOtherText && !reasonText) {
    const error = new Error("ORDER_ACTION_REASON_TEXT_REQUIRED");
    error.status = 400;
    throw error;
  }

  const out = await repo.createCourierCancelRequest({
    courierUserId,
    orderId,
    reasonCode: reasonMeta.reasonCode,
    reasonText,
    reasonLabel: reasonMeta.reasonLabelAr || reasonMeta.reasonCode,
  });

  await notify([
    {
      userId: Number(out.ownerUserId),
      type: "owner_courier_cancel_request",
      title: "Courier requested cancellation",
      body: `Courier requested cancelling order #${orderId}.`,
      orderId: Number(orderId),
      merchantId: Number(out.order.merchant_id),
      payload: {
        ...toOrderPayload(out.order, "owner_orders", {
          action: "open_owner_order",
          roleScope: "owner",
          notificationType: "owner_courier_cancel_request",
        }),
        cancelRequestId: Number(out.request.id),
      },
    },
    ...(out.adminRecipients || []).map((adminId) => ({
      userId: Number(adminId),
      type: "admin_courier_cancel_request",
      title: "Courier cancel request",
      body: `Order #${orderId} has a courier cancellation request.`,
      orderId: Number(orderId),
      merchantId: Number(out.order.merchant_id),
      payload: {
        ...toOrderPayload(out.order, "admin_orders", {
          action: "open_admin_order",
          roleScope: "admin",
          targetModule: "admin",
          notificationType: "admin_courier_cancel_request",
        }),
        cancelRequestId: Number(out.request.id),
      },
    })),
  ]);

  return out;
}

export async function ownerReviewCourierCancelRequest(ownerUserId, orderId, body = {}) {
  const out = await repo.reviewCourierCancelRequestByOwner({
    ownerUserId,
    orderId,
    approved: body?.approved === true,
    reviewNote: body?.reviewNote ?? null,
  });
  invalidateCustomerOrderList(out.order);

  await notify([
    {
      userId: Number(out.request.courier_user_id),
      type: body?.approved === true ? "courier_cancel_request_approved" : "courier_cancel_request_rejected",
      title: body?.approved === true ? "Cancellation approved" : "Cancellation rejected",
      body:
        body?.approved === true
          ? `Store approved cancellation for order #${orderId}.`
          : `Store rejected cancellation for order #${orderId}.`,
      orderId: Number(orderId),
      merchantId: Number(out.order.merchant_id),
      payload: {
        ...toOrderPayload(out.order, "courier_orders_current", {
          action:
            body?.approved === true ? "open_cancelled_order" : "open_current_order",
          roleScope: "courier",
          notificationType:
            body?.approved === true
              ? "courier_cancel_request_approved"
              : "courier_cancel_request_rejected",
        }),
        cancelRequestId: Number(out.request.id),
      },
    },
    ...(body?.approved === true
      ? [
          {
            userId: Number(out.order.customer_user_id),
            type: "customer_order_cancelled",
            title: "Order cancelled",
            body: `Order #${orderId} has been cancelled.`,
            orderId: Number(orderId),
            merchantId: Number(out.order.merchant_id),
            payload: toOrderPayload(out.order, "order_tracking", {
              action: "open_order_tracking",
              notificationType: "customer_order_cancelled",
            }),
          },
        ]
      : []),
  ]);

  return out;
}

export async function adminReviewCourierCancelRequest(adminUserId, orderId, body = {}) {
  const out = await repo.reviewCourierCancelRequestByAdmin({
    adminUserId,
    orderId,
    approved: body?.approved === true,
    reviewNote: body?.reviewNote ?? null,
  });
  invalidateCustomerOrderList(out.order);

  await notify([
    {
      userId: Number(out.request.courier_user_id),
      type: body?.approved === true ? "courier_cancel_request_approved" : "courier_cancel_request_rejected",
      title: body?.approved === true ? "Cancellation approved" : "Cancellation rejected",
      body:
        body?.approved === true
          ? `Admin approved cancellation for order #${orderId}.`
          : `Admin rejected cancellation for order #${orderId}.`,
      orderId: Number(orderId),
      merchantId: Number(out.order.merchant_id),
      payload: {
        ...toOrderPayload(out.order, "courier_orders_current", {
          action:
            body?.approved === true ? "open_cancelled_order" : "open_current_order",
          roleScope: "courier",
        }),
        cancelRequestId: Number(out.request.id),
      },
    },
    ...(body?.approved === true
      ? [
          {
            userId: Number(out.order.customer_user_id),
            type: "customer_order_cancelled",
            title: "Order cancelled",
            body: `Order #${orderId} has been cancelled.`,
            orderId: Number(orderId),
            merchantId: Number(out.order.merchant_id),
            payload: toOrderPayload(out.order, "order_tracking", {
              action: "open_order_tracking",
            }),
          },
          {
            userId: Number(out.order.owner_user_id),
            type: "owner_order_cancelled",
            title: "Order cancelled",
            body: `Order #${orderId} was cancelled by admin.`,
            orderId: Number(orderId),
            merchantId: Number(out.order.merchant_id),
            payload: toOrderPayload(out.order, "owner_orders", {
              action: "open_owner_order",
              roleScope: "owner",
            }),
          },
        ]
      : []),
  ]);

  return out;
}

export async function listOrderChatMessages({
  userId,
  userRole,
  orderId,
  limit = 120,
  beforeId = null,
}) {
  return repo.listOrderChatMessages({
    userId,
    userRole,
    orderId,
    limit,
    beforeId,
  });
}

export async function sendOrderChatMessage({
  userId,
  userRole,
  orderId,
  message,
}) {
  const out = await repo.createOrderChatMessage({
    userId,
    userRole,
    orderId,
    message,
  });

  const notifications = [];
  for (const participantId of out.notifyUserIds || []) {
    if (Number(participantId) === Number(userId)) continue;
    notifications.push({
      userId: Number(participantId),
      type: "order_chat_message",
      title: "New order message",
      body: `New message for order #${orderId}.`,
      orderId: Number(orderId),
      merchantId: Number(out.order.merchant_id),
      payload: {
        ...toOrderPayload(out.order, out.targetByUserId?.[String(participantId)] || "order_tracking", {
          action: "open_order_chat",
          roleScope: out.roleScopeByUserId?.[String(participantId)] || null,
          notificationType: "order_chat_message",
        }),
        target: out.targetByUserId?.[String(participantId)] || "order_tracking",
        chatOrderId: Number(orderId),
      },
    });
  }
  await notify(notifications);

  return out;
}

export async function getCourierDashboard(courierUserId, query = {}) {
  return repo.listCourierDashboard(courierUserId, query);
}

export async function getCourierOrders(courierUserId, query = {}) {
  return repo.listCourierOrders(courierUserId, query);
}

export async function getCourierRequests(courierUserId, query = {}) {
  return repo.listCourierRequests(courierUserId, query);
}

export async function getCourierOrdersGroupedByMerchant(courierUserId, query = {}) {
  return repo.listCourierOrdersGroupedByMerchant(courierUserId, query);
}

export async function getCourierReports(courierUserId, query = {}) {
  return repo.listCourierReports(courierUserId, query);
}

export async function getCourierEarnings(courierUserId, query = {}) {
  return repo.listCourierEarnings(courierUserId, query);
}

export async function getCourierCompetitions(courierUserId, query = {}) {
  return repo.listCourierCompetitions(courierUserId, {
    scope: query?.scope || "active",
  });
}

export async function getCourierCompetitionDetails(courierUserId, competitionId) {
  return repo.getCourierCompetitionDetails(courierUserId, competitionId);
}

export async function getCourierCompetitionProgress(courierUserId) {
  return repo.listCourierCompetitionProgress(courierUserId);
}

export async function getCourierCompetitionAchievementsSummary(courierUserId) {
  return repo.getCourierCompetitionAchievementsSummary(courierUserId);
}

export async function getMerchantDashboard(ownerUserId, query = {}) {
  return repo.getMerchantDashboard(ownerUserId, query);
}

export async function getMerchantKpis(ownerUserId, query = {}) {
  return repo.getMerchantKpis(ownerUserId, query);
}

export async function getMerchantTopProducts(ownerUserId, query = {}) {
  return repo.getMerchantTopProducts(ownerUserId, query);
}

export async function getMerchantTopCategories(ownerUserId, query = {}) {
  return repo.getMerchantTopCategories(ownerUserId, query);
}

export async function getMerchantOrdersReports(ownerUserId, query = {}) {
  return repo.getMerchantOrdersReports(ownerUserId, query);
}

export async function getMerchantVerifiedReviews(ownerUserId, query = {}) {
  return repo.getMerchantVerifiedReviews(ownerUserId, query);
}

export async function getMerchantCustomerReliability(
  ownerUserId,
  customerUserId
) {
  return repo.getMerchantCustomerReliability(ownerUserId, customerUserId);
}

export async function getCustomerReliabilityPolicy() {
  return repo.getCustomerReliabilityPolicy();
}

export async function updateCustomerReliabilityPolicy(actorUserId, patch = {}) {
  return repo.updateCustomerReliabilityPolicy(actorUserId, patch);
}

export async function getDeliveryDispatchPolicy() {
  return repo.getDeliveryDispatchPolicy();
}

export async function updateDeliveryDispatchPolicy(actorUserId, patch = {}) {
  return repo.updateDeliveryDispatchPolicy(actorUserId, patch);
}

export async function listMerchantCouriers(ownerUserId) {
  return repo.listMerchantCouriers(ownerUserId);
}

export async function createMerchantCourier(ownerUserId, body = {}) {
  return repo.createMerchantCourier({
    ownerUserId,
    deliveryUserId: body?.deliveryUserId,
    vehicleType: body?.vehicleType || null,
    coverageBlock: body?.coverageBlock || null,
  });
}

export async function updateMerchantCourier(ownerUserId, courierUserId, body = {}) {
  return repo.updateMerchantCourier({
    ownerUserId,
    deliveryUserId: courierUserId,
    isActive: typeof body?.isActive === "boolean" ? body.isActive : null,
    availabilityStatus: body?.availabilityStatus || null,
    vehicleType: body?.vehicleType || null,
  });
}

export async function getMerchantReceivables(ownerUserId) {
  return repo.getMerchantReceivablesSummary(ownerUserId);
}

export async function getMerchantReceivablesLedger(ownerUserId, query = {}) {
  return repo.listMerchantReceivablesLedger(ownerUserId, query);
}

export async function listMerchantReceivableInvoices(ownerUserId, query = {}) {
  return repo.listMerchantOpenReceivableInvoices(ownerUserId, query);
}

export async function previewMerchantPaymentSelection(ownerUserId, body = {}) {
  return repo.previewMerchantPaymentSelection({
    ownerUserId,
    selectionMode: body?.selectionMode,
    selectedInvoiceIds: body?.selectedInvoiceIds ?? [],
    targetAmount: body?.targetAmount,
    confirmedAdjustedAmount: body?.confirmedAdjustedAmount,
    amount: body?.amount,
  });
}

export async function createMerchantPaymentRequest(ownerUserId, body = {}) {
  const out = await repo.createMerchantPaymentRequest({
    ownerUserId,
    requestType: body?.requestType || "store_pays_app",
    paymentScope: body?.paymentScope,
    amount: body?.amount,
    proofFileUrl: body?.proofFileUrl || null,
    note: body?.note || null,
    paymentMethod: body?.paymentMethod || null,
    paymentMethodOther: body?.paymentMethodOther || null,
    paymentDate: body?.paymentDate || null,
    referenceCode: body?.referenceCode || null,
    receiverName: body?.receiverName || null,
    selectionMode: body?.selectionMode || null,
    selectedInvoiceIds: body?.selectedInvoiceIds ?? [],
    targetAmount: body?.targetAmount,
    confirmedAdjustedAmount: body?.confirmedAdjustedAmount,
    selectionMeta: body?.selectionMeta || null,
  });

  const isStorePays = String(out.paymentRequest?.request_type || "") === "store_pays_app";
  const notificationType = isStorePays
    ? "admin_merchant_payment_request"
    : "admin_merchant_outgoing_payment_request";
  const notificationTitle = isStorePays
    ? "Merchant payment submitted"
    : "Merchant requested payout";
  const notificationBody = isStorePays
    ? `${out.merchant.name || "Merchant"} submitted a payment to platform.`
    : `${out.merchant.name || "Merchant"} requested app payout.`;

  await notify(
    out.adminRecipients.map((adminId) => ({
      userId: Number(adminId),
      type: notificationType,
      title: notificationTitle,
      body: notificationBody,
      merchantId: Number(out.merchant.id),
      payload: {
        target: "admin_payment_requests",
        paymentRequestId: Number(out.paymentRequest.id),
        merchantId: Number(out.merchant.id),
        targetModule: "admin",
        target_module: "admin",
        roleScope: "admin",
        role_scope: "admin",
        action: "open_payment_requests",
        targetEntity: "payment_request",
        target_entity: "payment_request",
        entityId: Number(out.paymentRequest.id),
        entity_id: Number(out.paymentRequest.id),
        requestType: String(out.paymentRequest?.request_type || "store_pays_app"),
        status: String(out.paymentRequest?.status || ""),
      },
    }))
  );

  return out;
}

export async function listMerchantPaymentRequests(ownerUserId, query = {}) {
  return repo.listMerchantPaymentRequests(ownerUserId, query);
}

export async function getMerchantPaymentRequestDetails(ownerUserId, paymentRequestId) {
  return repo.getMerchantPaymentRequestDetails(ownerUserId, paymentRequestId);
}

export async function getMerchantPaymentRequestInvoices(ownerUserId, paymentRequestId) {
  return repo.getMerchantPaymentRequestInvoices(ownerUserId, paymentRequestId);
}

export async function updateMerchantPaymentRequest(
  ownerUserId,
  paymentRequestId,
  body = {}
) {
  const out = await repo.updateMerchantPaymentRequest({
    ownerUserId,
    paymentRequestId,
    amount: body?.amount ?? null,
    paymentScope: body?.paymentScope ?? null,
    note: body?.note ?? null,
    paymentMethod: body?.paymentMethod ?? null,
    paymentMethodOther: body?.paymentMethodOther ?? null,
    paymentDate: body?.paymentDate ?? null,
    referenceCode: body?.referenceCode ?? null,
    receiverName: body?.receiverName ?? null,
    proofFileUrl: body?.proofFileUrl ?? null,
    selectionMode: body?.selectionMode ?? null,
    selectedInvoiceIds: body?.selectedInvoiceIds ?? [],
    targetAmount: body?.targetAmount ?? null,
    confirmedAdjustedAmount: body?.confirmedAdjustedAmount ?? null,
    selectionMeta: body?.selectionMeta ?? null,
    resubmit: body?.resubmit === true,
  });
  return out;
}

export async function confirmMerchantPaymentRequestReceived(
  ownerUserId,
  paymentRequestId,
  body = {}
) {
  const out = await repo.merchantConfirmPaymentRequestReceived({
    ownerUserId,
    paymentRequestId,
    note: body?.note || null,
  });
  const adminIds = await repo.listBackofficeUserIds();
  await notify(
    adminIds.map((adminId) => ({
      userId: Number(adminId),
      type: "admin_merchant_payment_confirmed_received",
      title: "Merchant confirmed receiving payment",
      body: `${out.merchant?.name || "Merchant"} confirmed payout receipt.`,
      merchantId: Number(out.merchant?.id || 0) || undefined,
      payload: {
        target: "admin_payment_requests",
        paymentRequestId: Number(out.request?.id || 0) || null,
        merchantId: Number(out.merchant?.id || 0) || null,
        requestType: "app_pays_store",
        targetModule: "admin",
        target_module: "admin",
        roleScope: "admin",
        role_scope: "admin",
        action: "open_payment_requests",
        targetEntity: "payment_request",
        target_entity: "payment_request",
        entityId: Number(out.request?.id || 0) || null,
        entity_id: Number(out.request?.id || 0) || null,
      },
    }))
  );
  return out;
}

export async function reportMerchantPaymentRequestIssue(
  ownerUserId,
  paymentRequestId,
  body = {}
) {
  const out = await repo.merchantReportPaymentRequestIssue({
    ownerUserId,
    paymentRequestId,
    issueNote: body?.issueNote || null,
  });
  const adminIds = await repo.listBackofficeUserIds();
  await notify(
    adminIds.map((adminId) => ({
      userId: Number(adminId),
      type: "admin_merchant_payment_issue_reported",
      title: "Merchant reported payout issue",
      body: `${out.merchant?.name || "Merchant"} reported an issue on payment request #${out.request?.id || "-"}.`,
      merchantId: Number(out.merchant?.id || 0) || undefined,
      payload: {
        target: "admin_payment_requests",
        paymentRequestId: Number(out.request?.id || 0) || null,
        merchantId: Number(out.merchant?.id || 0) || null,
        requestType: "app_pays_store",
        targetModule: "admin",
        target_module: "admin",
        roleScope: "admin",
        role_scope: "admin",
        action: "open_payment_requests",
        targetEntity: "payment_request",
        target_entity: "payment_request",
        entityId: Number(out.request?.id || 0) || null,
        entity_id: Number(out.request?.id || 0) || null,
      },
    }))
  );
  return out;
}

export async function getAdminMerchantsReceivables(query = {}) {
  return repo.listAdminMerchantsReceivables(query);
}

export async function getAdminMerchantReceivables(merchantId) {
  return repo.getAdminMerchantReceivables(merchantId);
}

export async function getAdminPaymentRequestInvoices(paymentRequestId) {
  return repo.getAdminPaymentRequestInvoices(paymentRequestId);
}

export async function patchAdminMerchantBillingProfile(adminUserId, merchantId, body = {}) {
  return repo.updateMerchantBillingProfile({
    adminUserId,
    merchantId,
    commissionType: body?.commissionType ?? null,
    commissionValue: body?.commissionValue ?? null,
    commissionRate: body?.commissionRate ?? null,
    serviceFeeType: body?.serviceFeeType ?? null,
    serviceFeeMode: body?.serviceFeeMode ?? null,
    serviceFeeValue: body?.serviceFeeValue ?? null,
    deliveryFeeMode: body?.deliveryFeeMode ?? null,
    appDeliveryFeeValue: body?.appDeliveryFeeValue ?? null,
    storeDeliveryFeeValue: body?.storeDeliveryFeeValue ?? null,
    deliveryFeeValue: body?.deliveryFeeValue ?? null,
    appDeliveryEnabled:
      typeof body?.appDeliveryEnabled === "boolean" ? body.appDeliveryEnabled : null,
    merchantDeliveryEnabled:
      typeof body?.merchantDeliveryEnabled === "boolean"
        ? body.merchantDeliveryEnabled
        : null,
    settlementCycle: body?.settlementCycle ?? null,
    distributionPolicy: body?.distributionPolicy ?? null,
    gracePeriodDays: body?.gracePeriodDays ?? null,
    effectiveFrom: body?.effectiveFrom ?? null,
  });
}

export async function adminMarkPaymentRequestReceived(adminUserId, paymentRequestId, body = {}) {
  const out = await repo.markPaymentRequestReceived({
    adminUserId,
    paymentRequestId,
    reviewNote: body?.reviewNote || null,
  });

  if (out.merchant?.owner_user_id) {
    await notify([
      {
        userId: Number(out.merchant.owner_user_id),
        type: "owner_payment_request_confirmed_by_admin",
        title: "Payment request confirmed",
        body: `Payment request #${out.paymentRequest.id} was confirmed.`,
        merchantId: Number(out.merchant.id),
        payload: {
          target: "merchant_receivables",
          paymentRequestId: Number(out.paymentRequest.id),
          targetModule: "merchant",
          target_module: "merchant",
          roleScope: "owner",
          role_scope: "owner",
          action: "open_merchant_receivables",
          targetEntity: "payment_request",
          target_entity: "payment_request",
          entityId: Number(out.paymentRequest.id),
          entity_id: Number(out.paymentRequest.id),
          requestType: String(out.paymentRequest?.request_type || ""),
          status: String(out.paymentRequest?.status || ""),
        },
      },
    ]);
  }

  return out;
}

export async function adminRejectPaymentRequest(adminUserId, paymentRequestId, body = {}) {
  const out = await repo.rejectPaymentRequest({
    adminUserId,
    paymentRequestId,
    reviewNote: body?.reviewNote || null,
  });

  if (out.merchant?.owner_user_id) {
    await notify([
      {
        userId: Number(out.merchant.owner_user_id),
        type: "owner_payment_request_rejected",
        title: "Payment request rejected",
        body: `Payment request #${out.paymentRequest.id} was rejected.`,
        merchantId: Number(out.merchant.id),
        payload: {
          target: "merchant_receivables",
          paymentRequestId: Number(out.paymentRequest.id),
          targetModule: "merchant",
          target_module: "merchant",
          roleScope: "owner",
          role_scope: "owner",
          action: "open_merchant_receivables",
          targetEntity: "payment_request",
          target_entity: "payment_request",
          entityId: Number(out.paymentRequest.id),
          entity_id: Number(out.paymentRequest.id),
          requestType: String(out.paymentRequest?.request_type || ""),
          status: String(out.paymentRequest?.status || ""),
        },
      },
    ]);
  }

  return out;
}

export async function adminApprovePaymentRequest(
  adminUserId,
  paymentRequestId,
  body = {}
) {
  const out = await repo.adminApprovePaymentRequest({
    adminUserId,
    paymentRequestId,
    reviewNote: body?.reviewNote || null,
    internalAdminNote: body?.internalAdminNote || null,
  });

  if (out.merchant?.owner_user_id) {
    await notify([
      {
        userId: Number(out.merchant.owner_user_id),
        type: "owner_payment_request_approved",
        title: "Payment request approved",
        body: `Payment request #${out.paymentRequest.id} has been approved.`,
        merchantId: Number(out.merchant.id),
        payload: {
          target: "merchant_receivables",
          paymentRequestId: Number(out.paymentRequest.id),
          targetModule: "merchant",
          target_module: "merchant",
          roleScope: "owner",
          role_scope: "owner",
          action: "open_merchant_receivables",
          targetEntity: "payment_request",
          target_entity: "payment_request",
          entityId: Number(out.paymentRequest.id),
          entity_id: Number(out.paymentRequest.id),
          requestType: String(out.paymentRequest?.request_type || ""),
          status: String(out.paymentRequest?.status || ""),
        },
      },
    ]);
  }

  return out;
}

export async function adminAssignPaymentRequest(
  adminUserId,
  paymentRequestId,
  body = {}
) {
  const out = await repo.adminAssignPaymentRequest({
    adminUserId,
    paymentRequestId,
    assignedToUserId: body?.assignedToUserId ?? null,
    assignedToName: body?.assignedToName ?? null,
    reviewNote: body?.reviewNote ?? null,
    internalAdminNote: body?.internalAdminNote ?? null,
  });

  if (out.merchant?.owner_user_id) {
    await notify([
      {
        userId: Number(out.merchant.owner_user_id),
        type: "owner_payment_request_assigned",
        title: "Payment execution assigned",
        body: `Payment request #${out.paymentRequest.id} is assigned for execution.`,
        merchantId: Number(out.merchant.id),
        payload: {
          target: "merchant_receivables",
          paymentRequestId: Number(out.paymentRequest.id),
          targetModule: "merchant",
          target_module: "merchant",
          roleScope: "owner",
          role_scope: "owner",
          action: "open_merchant_receivables",
          targetEntity: "payment_request",
          target_entity: "payment_request",
          entityId: Number(out.paymentRequest.id),
          entity_id: Number(out.paymentRequest.id),
          requestType: String(out.paymentRequest?.request_type || ""),
          status: String(out.paymentRequest?.status || ""),
        },
      },
    ]);
  }

  return out;
}

export async function adminMarkPaymentRequestPaid(
  adminUserId,
  paymentRequestId,
  body = {}
) {
  const out = await repo.adminMarkPaymentRequestPaid({
    adminUserId,
    paymentRequestId,
    paidAmount: body?.paidAmount ?? null,
    paymentMethod: body?.paymentMethod ?? null,
    paymentDate: body?.paymentDate ?? null,
    referenceCode: body?.referenceCode ?? null,
    paymentActorName: body?.paymentActorName ?? null,
    assignedToUserId: body?.assignedToUserId ?? null,
    assignedToName: body?.assignedToName ?? null,
    reviewNote: body?.reviewNote ?? null,
    internalAdminNote: body?.internalAdminNote ?? null,
  });

  if (out.merchant?.owner_user_id) {
    await notify([
      {
        userId: Number(out.merchant.owner_user_id),
        type: "owner_payment_request_awaiting_confirmation",
        title: "Payment marked as paid",
        body: `Payment request #${out.paymentRequest.id} is awaiting your confirmation.`,
        merchantId: Number(out.merchant.id),
        payload: {
          target: "merchant_receivables",
          paymentRequestId: Number(out.paymentRequest.id),
          targetModule: "merchant",
          target_module: "merchant",
          roleScope: "owner",
          role_scope: "owner",
          action: "open_merchant_receivables",
          targetEntity: "payment_request",
          target_entity: "payment_request",
          entityId: Number(out.paymentRequest.id),
          entity_id: Number(out.paymentRequest.id),
          requestType: String(out.paymentRequest?.request_type || ""),
          status: String(out.paymentRequest?.status || ""),
        },
      },
    ]);
  }

  return out;
}

export async function adminReturnPaymentRequestForRevision(
  adminUserId,
  paymentRequestId,
  body = {}
) {
  const out = await repo.adminReturnPaymentRequestForRevision({
    adminUserId,
    paymentRequestId,
    reviewNote: body?.reviewNote || null,
    internalAdminNote: body?.internalAdminNote || null,
  });
  if (out.merchant?.owner_user_id) {
    await notify([
      {
        userId: Number(out.merchant.owner_user_id),
        type: "owner_payment_request_returned_for_revision",
        title: "Payment request returned for revision",
        body: `Payment request #${out.paymentRequest.id} needs revision.`,
        merchantId: Number(out.merchant.id),
        payload: {
          target: "merchant_receivables",
          paymentRequestId: Number(out.paymentRequest.id),
          targetModule: "merchant",
          target_module: "merchant",
          roleScope: "owner",
          role_scope: "owner",
          action: "open_merchant_receivables",
          targetEntity: "payment_request",
          target_entity: "payment_request",
          entityId: Number(out.paymentRequest.id),
          entity_id: Number(out.paymentRequest.id),
          requestType: String(out.paymentRequest?.request_type || ""),
          status: String(out.paymentRequest?.status || ""),
        },
      },
    ]);
  }
  return out;
}

export async function adminCreateAppPayablesAdjustment(
  adminUserId,
  merchantId,
  body = {}
) {
  const out = await repo.adminCreateMerchantAppPayablesAdjustment({
    adminUserId,
    merchantId,
    amount: body?.amount,
    direction: body?.direction,
    entryType: body?.entryType,
    note: body?.note,
    referenceCode: body?.referenceCode,
    orderId: body?.orderId ?? null,
  });
  if (Number(out?.merchant?.owner_user_id || 0) > 0) {
    await notify([
      {
        userId: Number(out.merchant.owner_user_id),
        type: "owner_app_payables_adjusted",
        title: "Settlement balance adjusted",
        body: `Your app payable balance was updated by admin.`,
        merchantId: Number(out.merchant.id),
        payload: {
          target: "merchant_receivables",
          merchantId: Number(out.merchant.id),
          targetModule: "merchant",
          target_module: "merchant",
          roleScope: "owner",
          role_scope: "owner",
          action: "open_merchant_receivables",
          targetEntity: "merchant",
          target_entity: "merchant",
          entityId: Number(out.merchant.id),
          entity_id: Number(out.merchant.id),
        },
      },
    ]);
  }
  return out;
}

export async function getAdminCompetitions(query = {}) {
  return repo.listAdminCompetitions({
    status: query?.status || null,
    activeOnly:
      query?.activeOnly === true ||
      String(query?.activeOnly || "").toLowerCase() === "true" ||
      String(query?.activeOnly || "") === "1",
  });
}

export async function getAdminCompetitionDetails(competitionId) {
  return repo.getAdminCompetitionDetails(competitionId);
}

export async function getAdminCompetitionWinners(competitionId) {
  return repo.listAdminCompetitionWinners(competitionId);
}

export async function createAdminCompetition(adminUserId, body = {}) {
  const out = await repo.createAdminCompetition({
    adminUserId,
    title: body?.title,
    description: body?.description || null,
    competitionType: body?.competitionType,
    targetValue: body?.targetValue,
    rewardAmount: body?.rewardAmount,
    rewardType: body?.rewardType || "cash",
    startAt: body?.startAt || null,
    endAt: body?.endAt || null,
    isActive: typeof body?.isActive === "boolean" ? body.isActive : true,
    status: body?.status || null,
    filtersJson: body?.filters || {},
    tiers: Array.isArray(body?.tiers) ? body.tiers : [],
  });

  const competition = out?.competition || {};
  const competitionId = Number(competition.id || 0);
  const competitionStatus = String(competition.status || "").trim().toLowerCase();
  const competitionIsActive = competition.is_active === true;
  const startAt = competition.start_at ? new Date(competition.start_at) : null;
  const endAt = competition.end_at ? new Date(competition.end_at) : null;
  const shouldNotifyCouriers =
    competitionId > 0 && competitionIsActive && competitionStatus === "active";

  if (shouldNotifyCouriers) {
    const couriers = await repo.listActiveCourierUsers();
    if (couriers.length) {
      const now = Date.now();
      const startsInFuture = startAt instanceof Date && !Number.isNaN(startAt.getTime())
        ? startAt.getTime() > now
        : false;
      const title = startsInFuture
        ? "New competition scheduled"
        : "New courier competition";
      const bodyText = startsInFuture
        ? `${String(competition.title || "Competition")} starts soon.`
        : `${String(competition.title || "Competition")} is now active.`;

      await notify(
        couriers.map((courier) => ({
          userId: Number(courier.id),
          type: "courier_competition_started",
          title,
          body: bodyText,
          merchantId: null,
          payload: {
            target: "courier_competitions",
            targetModule: "courier",
            target_module: "courier",
            roleScope: "courier",
            role_scope: "courier",
            action: "open_courier_competitions",
            targetEntity: "competition",
            target_entity: "competition",
            entityId: competitionId,
            entity_id: competitionId,
            notificationType: "courier_competition_started",
            notification_type: "courier_competition_started",
            competitionId,
            competitionTitle: String(competition.title || "").trim() || null,
            competitionStatus,
            startAt: startAt ? startAt.toISOString() : null,
            endAt: endAt ? endAt.toISOString() : null,
          },
        }))
      );
    }
  }

  return out;
}

export async function updateAdminCompetition(competitionId, body = {}) {
  return repo.updateAdminCompetition({
    competitionId,
    title: body?.title ?? null,
    description: body?.description ?? null,
    targetValue: body?.targetValue ?? null,
    rewardAmount: body?.rewardAmount ?? null,
    rewardType: body?.rewardType ?? null,
    startAt: body?.startAt ?? null,
    endAt: body?.endAt ?? null,
    isActive: typeof body?.isActive === "boolean" ? body.isActive : null,
    status: body?.status ?? null,
    filtersJson: body?.filters ?? null,
    tiers: Array.isArray(body?.tiers) ? body.tiers : null,
  });
}

export async function endAdminCompetition(competitionId) {
  return repo.endAdminCompetitionNow({ competitionId });
}

export async function getAdminPlatformKpis(query = {}) {
  return repo.getAdminPlatformKpis(query);
}

export async function getAdminFinancialKpis(query = {}) {
  return repo.getAdminFinancialKpis(query);
}

export async function getAdminSalesReport(query = {}) {
  return repo.getAdminSalesReport(query);
}

export async function getAdminSalesMerchantDetails(merchantId, query = {}) {
  return repo.getAdminSalesMerchantDetails({ merchantId, ...query });
}

export async function getAdminCollectionsReport(query = {}) {
  return repo.getAdminCollectionsReport(query);
}

export async function getAdminCollectionsMerchantDetails(
  merchantId,
  query = {}
) {
  return repo.getAdminCollectionsMerchantDetails({ merchantId, ...query });
}

export async function getAdminReceivablesReport(query = {}) {
  return repo.getAdminReceivablesReport(query);
}

export async function getAdminReceivablesMerchantStatement(
  merchantId,
  query = {}
) {
  return repo.getAdminReceivablesMerchantStatement({ merchantId, ...query });
}

export async function searchProductsGlobal(customerUserId, query = {}) {
  return repo.searchProductsGlobal(customerUserId, query);
}

const DELIVERY_ASSIGNMENT_STATUSES = Object.freeze({
  NOT_REQUIRED: "NOT_REQUIRED",
  PENDING_NO_DRIVER: "PENDING_NO_DRIVER",
  ASSIGNED: "ASSIGNED",
  COMPLETED: "COMPLETED",
  CANCELLED: "CANCELLED",
});

const DELIVERY_ASSIGNMENT_END_REASONS = Object.freeze({
  RELEASED: "RELEASED",
  EXPIRED: "EXPIRED",
  ORDER_CANCELLED: "ORDER_CANCELLED",
  COMPLETED: "COMPLETED",
  DRIVER_REJECTED: "DRIVER_REJECTED",
  MANUAL_REASSIGNMENT: "MANUAL_REASSIGNMENT",
});

const ASSIGNED_ORDER_STATUSES = new Set([
  "approved",
  "preparing",
  "ready_for_delivery",
  "on_the_way",
  "arrived",
]);

const TERMINAL_ORDER_STATUSES = new Set([
  "delivered",
  "delivered_by_courier",
  "received_by_customer",
  "completed",
  "cancelled",
  "cancelled_by_customer",
  "cancelled_by_store",
  "cancelled_by_admin",
]);

function normalizeText(value) {
  return String(value || "").trim();
}

function normalizeUpper(value) {
  return normalizeText(value).toUpperCase();
}

export function normalizeDeliveryAssignmentStatus(value) {
  const normalized = normalizeUpper(value);
  if (normalized in DELIVERY_ASSIGNMENT_STATUSES) {
    return normalized;
  }
  return DELIVERY_ASSIGNMENT_STATUSES.NOT_REQUIRED;
}

export function normalizeDeliveryAssignmentEndReason(value) {
  const normalized = normalizeUpper(value);
  if (normalized in DELIVERY_ASSIGNMENT_END_REASONS) {
    return normalized;
  }
  return null;
}

export function isDeliveryAssignmentOpen(row) {
  return !!row && row.ended_at == null;
}

export function isDeliveryAssignmentAssigned(row) {
  return normalizeDeliveryAssignmentStatus(row?.delivery_assignment_status) ===
      DELIVERY_ASSIGNMENT_STATUSES.ASSIGNED &&
    Number(row?.delivery_user_id || 0) > 0;
}

export function isDeliveryAssignmentPending(row) {
  return (
    normalizeDeliveryAssignmentStatus(row?.delivery_assignment_status) ===
    DELIVERY_ASSIGNMENT_STATUSES.PENDING_NO_DRIVER
  );
}

export function deriveDeliveryAssignmentStatus(order = {}, openAssignmentRow = null) {
  const explicit = normalizeUpper(order?.delivery_assignment_status);
  if (explicit in DELIVERY_ASSIGNMENT_STATUSES) {
    return explicit;
  }

  const orderStatus = normalizeText(order?.status).toLowerCase();
  if (TERMINAL_ORDER_STATUSES.has(orderStatus)) {
    if (orderStatus === "cancelled" ||
        orderStatus === "cancelled_by_customer" ||
        orderStatus === "cancelled_by_store" ||
        orderStatus === "cancelled_by_admin") {
      return DELIVERY_ASSIGNMENT_STATUSES.CANCELLED;
    }
    return DELIVERY_ASSIGNMENT_STATUSES.COMPLETED;
  }

  if (Number(order?.delivery_user_id || 0) > 0 || isDeliveryAssignmentOpen(openAssignmentRow)) {
    return DELIVERY_ASSIGNMENT_STATUSES.ASSIGNED;
  }

  if (ASSIGNED_ORDER_STATUSES.has(orderStatus)) {
    return DELIVERY_ASSIGNMENT_STATUSES.PENDING_NO_DRIVER;
  }

  return DELIVERY_ASSIGNMENT_STATUSES.NOT_REQUIRED;
}

function buildVehicleSummary(order = {}) {
  return {
    type: normalizeText(order.delivery_vehicle_type || order.vehicle_type || null) || null,
    model: null,
    color: null,
    plateNumber: null,
  };
}

export function buildDeliveryDriverSummary(order = {}) {
  const driverId = Number(order?.delivery_user_id || 0);
  if (!driverId) return null;
  return {
    id: driverId,
    name: order.delivery_full_name || null,
    photoUrl: order.delivery_image_url || null,
    phone: order.delivery_phone || null,
    rating:
      order.delivery_rating == null ? null : Number(order.delivery_rating || 0),
    availabilityStatus: order.delivery_availability_status || null,
    coverageBlock: order.delivery_coverage_block || null,
    courierSource: order.delivery_courier_source || order.courier_source || null,
    isMerchantDelivery: order.delivery_is_merchant_delivery === true,
    vehicle: buildVehicleSummary(order),
  };
}

export function buildDeliveryAssignmentPresentation({
  order = {},
  openAssignmentRow = null,
  latestAssignmentRow = null,
} = {}) {
  const assignmentSource = openAssignmentRow || latestAssignmentRow || null;
  const assignmentStatus = deriveDeliveryAssignmentStatus(order, openAssignmentRow);
  const assignmentId = assignmentSource?.id == null ? null : Number(assignmentSource.id);
  const assignedAt =
    assignmentSource?.assigned_at ||
    assignmentSource?.responded_at ||
    assignmentSource?.requested_at ||
    order?.courier_assigned_at ||
    null;

  return {
    assignmentStatus,
    assignmentId,
    assignedAt,
    endedAt: assignmentSource?.ended_at || null,
    endedReason: normalizeDeliveryAssignmentEndReason(
      assignmentSource?.ended_reason || null
    ),
    orderId: Number(order?.id || 0) || null,
    driver: buildDeliveryDriverSummary(order),
  };
}

export function isDeliveryAssignmentRecoverable(order = {}) {
  const status = normalizeText(order?.delivery_assignment_status).toUpperCase();
  if (status === DELIVERY_ASSIGNMENT_STATUSES.ASSIGNED) return false;
  const orderStatus = normalizeText(order?.status).toLowerCase();
  return ASSIGNED_ORDER_STATUSES.has(orderStatus) || status === DELIVERY_ASSIGNMENT_STATUSES.PENDING_NO_DRIVER;
}

export { DELIVERY_ASSIGNMENT_STATUSES, DELIVERY_ASSIGNMENT_END_REASONS };

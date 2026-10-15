function firstNonEmpty(...values) {
  for (const value of values) {
    if (value == null) continue;
    const normalized = String(value).trim();
    if (normalized) return normalized;
  }
  return null;
}

function assignI18n(
  payload,
  titleKey,
  bodyKey,
  { titleArgs = null, bodyArgs = null } = {}
) {
  if (!payload.i18nTitleKey) {
    payload.i18nTitleKey = titleKey;
  }
  if (!payload.i18nBodyKey) {
    payload.i18nBodyKey = bodyKey;
  }
  if (titleArgs && !payload.i18nTitleArgs) {
    payload.i18nTitleArgs = titleArgs;
  }
  if (bodyArgs && !payload.i18nBodyArgs) {
    payload.i18nBodyArgs = bodyArgs;
  }
  return payload;
}

function normalizeToken(value) {
  return String(value || "")
    .trim()
    .toLowerCase()
    .replace(/[\s-]+/g, "_");
}

function typeHas(normalizedType, ...tokens) {
  return tokens.some((token) => normalizedType.includes(token));
}

function readStatus(payload, ...extraValues) {
  return normalizeToken(
    firstNonEmpty(
      ...extraValues,
      payload.status,
      payload.statusKey,
      payload.status_key,
      payload.orderStatus,
      payload.order_status,
      payload.deliveryStatus,
      payload.delivery_status,
      payload.deliveryAssignmentStatus,
      payload.delivery_assignment_status,
      payload.assignmentStatus,
      payload.assignment_status,
      payload.rideStatus,
      payload.ride_status,
      payload.requestStatus,
      payload.request_status,
      payload.lifecycleStatus,
      payload.lifecycle_status,
      payload.action,
      payload.event
    )
  );
}

function readOrderArgs(payload) {
  const storeName = firstNonEmpty(
    payload.storeName,
    payload.store_name,
    payload.merchantName,
    payload.merchant_name,
    payload.shopName,
    payload.shop_name
  );
  const orderNumber = firstNonEmpty(
    payload.orderNumber,
    payload.order_number,
    payload.orderId,
    payload.order_id,
    payload.entityId,
    payload.entity_id
  );
  const courierName = firstNonEmpty(
    payload.courierName,
    payload.courier_name,
    payload.deliveryName,
    payload.delivery_name,
    payload.driverName,
    payload.driver_name
  );
  const statusText = firstNonEmpty(payload.statusText, payload.status_text);
  return {
    storeName: storeName || "المتجر",
    orderNumber: orderNumber || "",
    orderRef: orderNumber ? `#${orderNumber}` : "",
    courierName: courierName || "الدلفري",
    statusText: statusText || "",
  };
}

function readDeliveryArgs(payload) {
  const args = readOrderArgs(payload);
  const customerName = firstNonEmpty(
    payload.customerName,
    payload.customer_name,
    payload.recipientName,
    payload.recipient_name
  );
  return {
    ...args,
    customerName: customerName || "الزبون",
    reviewNote: firstNonEmpty(
      payload.reviewNote,
      payload.review_note,
      payload.reconciliationReviewNote,
    ) || "",
  };
}

function readStoreArgs(payload) {
  const args = readDeliveryArgs(payload);
  const amount = firstNonEmpty(
    payload.amount,
    payload.totalAmount,
    payload.total_amount,
    payload.settlementAmount,
    payload.settlement_amount
  );
  return {
    ...args,
    amount: amount || "",
  };
}

function readTaxiArgs(payload) {
  const rideId = firstNonEmpty(
    payload.rideId,
    payload.ride_id,
    payload.entityId,
    payload.entity_id
  );
  const captainName = firstNonEmpty(
    payload.captainName,
    payload.captain_name,
    payload.driverName,
    payload.driver_name,
    payload.taxiCaptainName,
    payload.taxi_captain_name
  );
  const fare = firstNonEmpty(
    payload.fare,
    payload.fareIqd,
    payload.fare_iqd,
    payload.suggestedFareIqd,
    payload.suggested_fare_iqd,
    payload.proposedFareIqd,
    payload.proposed_fare_iqd
  );
  return {
    rideId: rideId || "",
    rideRef: rideId ? `#${rideId}` : "",
    captainName: captainName || "الكابتن",
    fare: fare || "",
  };
}

function readServiceArgs(payload) {
  const requestId = firstNonEmpty(
    payload.requestId,
    payload.request_id,
    payload.serviceRequestId,
    payload.service_request_id,
    payload.entityId,
    payload.entity_id
  );
  const providerName = firstNonEmpty(
    payload.providerName,
    payload.provider_name,
    payload.serviceProviderName,
    payload.service_provider_name,
    payload.companyName,
    payload.company_name
  );
  const serviceName = firstNonEmpty(
    payload.serviceName,
    payload.service_name,
    payload.categoryName,
    payload.category_name,
    payload.title
  );
  return {
    requestId: requestId || "",
    requestRef: requestId ? `#${requestId}` : "",
    providerName: providerName || "مقدم الخدمة",
    serviceName: serviceName || "الخدمة",
  };
}

function assignOrderEventI18n(normalizedType, payload) {
  const status = readStatus(payload);
  const args = readOrderArgs(payload);
  const pick = (name) =>
    assignI18n(
      payload,
      `notifications.orders.${name}.title`,
      `notifications.orders.${name}.body`,
      { bodyArgs: args }
    );

  if (
    typeHas(normalizedType, "merchant_accepted", "store_accepted") ||
    ["accepted", "approved", "confirmed", "store_accepted", "merchant_accepted"].includes(status)
  ) {
    return pick("merchant_accepted");
  }
  if (typeHas(normalizedType, "preparing") || ["preparing", "in_preparation"].includes(status)) {
    return pick("preparing");
  }
  if (
    typeHas(normalizedType, "ready") ||
    ["ready", "ready_for_delivery", "ready_for_pickup", "waiting_pickup"].includes(status)
  ) {
    return pick("ready");
  }
  if (
    typeHas(normalizedType, "courier_assigned", "delivery_assigned", "assigned") ||
    ["assigned", "courier_assigned", "delivery_assigned"].includes(status)
  ) {
    return pick("courier_assigned");
  }
  if (typeHas(normalizedType, "reassigned") || ["reassigned", "courier_reassigned"].includes(status)) {
    return pick("courier_reassigned");
  }
  if (
    typeHas(normalizedType, "on_the_way", "out_for_delivery", "in_transit") ||
    ["on_the_way", "out_for_delivery", "in_transit", "picked_up"].includes(status)
  ) {
    return pick("on_the_way");
  }
  if (typeHas(normalizedType, "arrived") || ["arrived", "courier_arrived"].includes(status)) {
    return pick("arrived");
  }
  if (
    typeHas(normalizedType, "delivered", "completed") ||
    ["delivered", "completed", "received_by_customer", "delivered_by_courier"].includes(status)
  ) {
    return pick("delivered");
  }
  if (typeHas(normalizedType, "cancelled", "canceled") || ["cancelled", "canceled"].includes(status)) {
    return pick("cancelled");
  }
  if (typeHas(normalizedType, "rejected", "declined") || ["rejected", "declined"].includes(status)) {
    return pick("rejected");
  }
  if (["pending_no_driver", "no_driver"].includes(status)) {
    return pick("pending_no_driver");
  }

  return null;
}

function assignDeliveryEventI18n(normalizedType, payload) {
  const args = readDeliveryArgs(payload);
  const pick = (name) =>
    assignI18n(
      payload,
      `notifications.delivery.${name}.title`,
      `notifications.delivery.${name}.body`,
      { bodyArgs: args }
    );

  if (typeHas(normalizedType, "reconciliation_approved")) {
    return pick("reconciliation_approved");
  }
  if (typeHas(normalizedType, "reconciliation_rejected")) {
    return pick("reconciliation_rejected");
  }
  if (typeHas(normalizedType, "removed", "released", "cancelled", "canceled")) {
    return pick("removed");
  }
  if (typeHas(normalizedType, "reassigned")) {
    return pick("reassigned");
  }
  if (typeHas(normalizedType, "available", "offered", "offer")) {
    return pick("available");
  }
  if (typeHas(normalizedType, "assigned")) {
    return pick("assigned");
  }
  return null;
}

function assignStoreEventI18n(normalizedType, payload) {
  const status = readStatus(payload);
  const args = readStoreArgs(payload);
  const pick = (name) =>
    assignI18n(
      payload,
      `notifications.store.${name}.title`,
      `notifications.store.${name}.body`,
      { bodyArgs: args }
    );

  if (typeHas(normalizedType, "settlement_approved", "cash_received")) {
    return pick("settlement_approved");
  }
  if (typeHas(normalizedType, "settlement_rejected", "settlement_declined")) {
    return pick("settlement_rejected");
  }
  if (
    typeHas(normalizedType, "customer_received", "customer_confirmed") ||
    ["received_by_customer", "customer_confirmed", "delivered", "completed"].includes(status)
  ) {
    return pick("customer_confirmed");
  }
  if (typeHas(normalizedType, "cancelled", "canceled") || ["cancelled", "canceled"].includes(status)) {
    return pick("customer_cancelled");
  }
  if (
    typeHas(normalizedType, "courier_assigned", "delivery_assigned", "assigned") ||
    ["assigned", "courier_assigned", "delivery_assigned"].includes(status)
  ) {
    return pick("courier_assigned");
  }
  if (typeHas(normalizedType, "reassigned") || ["reassigned", "courier_reassigned"].includes(status)) {
    return pick("courier_reassigned");
  }
  if (typeHas(normalizedType, "ready") || ["ready", "ready_for_delivery", "ready_for_pickup"].includes(status)) {
    return pick("ready_for_pickup");
  }
  if (typeHas(normalizedType, "preparing") || ["preparing", "in_preparation"].includes(status)) {
    return pick("preparing");
  }
  if (typeHas(normalizedType, "no_driver") || ["pending_no_driver", "no_driver"].includes(status)) {
    return pick("no_driver");
  }
  if (typeHas(normalizedType, "new_order", "order_created", "pending") || ["pending", "created", "new"].includes(status)) {
    return pick("new_order");
  }
  if (typeHas(normalizedType, "merchant_approved")) {
    return pick("merchant_approved");
  }

  return null;
}

function assignTaxiEventI18n(normalizedType, payload) {
  const status = readStatus(payload);
  const args = readTaxiArgs(payload);
  const pick = (name) =>
    assignI18n(
      payload,
      `notifications.taxi.${name}.title`,
      `notifications.taxi.${name}.body`,
      { bodyArgs: args }
    );

  if (
    typeHas(normalizedType, "assigned", "captain_assigned", "driver_assigned") ||
    ["assigned", "captain_assigned", "driver_assigned"].includes(status)
  ) {
    return pick("assigned");
  }
  if (typeHas(normalizedType, "arriving") || ["arriving", "captain_arriving"].includes(status)) {
    return pick("arriving");
  }
  if (typeHas(normalizedType, "arrived") || ["arrived", "captain_arrived"].includes(status)) {
    return pick("arrived");
  }
  if (
    typeHas(normalizedType, "started", "on_the_way", "in_progress") ||
    ["started", "on_the_way", "in_progress"].includes(status)
  ) {
    return pick("started");
  }
  if (typeHas(normalizedType, "completed") || ["completed", "finished"].includes(status)) {
    return pick("completed");
  }
  if (typeHas(normalizedType, "cancelled", "canceled") || ["cancelled", "canceled"].includes(status)) {
    return pick("cancelled");
  }
  if (typeHas(normalizedType, "fare", "price", "bid", "offer")) {
    return pick("fare_update");
  }
  return null;
}

function assignServiceEventI18n(normalizedType, payload) {
  const status = readStatus(payload);
  const args = readServiceArgs(payload);
  const pick = (name) =>
    assignI18n(
      payload,
      `notifications.services.${name}.title`,
      `notifications.services.${name}.body`,
      { bodyArgs: args }
    );

  if (typeHas(normalizedType, "quote") || ["quote_sent", "priced", "price_sent"].includes(status)) {
    return pick("quote_sent");
  }
  if (typeHas(normalizedType, "accepted", "approved") || ["accepted", "approved"].includes(status)) {
    return pick("accepted");
  }
  if (typeHas(normalizedType, "rejected", "declined") || ["rejected", "declined"].includes(status)) {
    return pick("rejected");
  }
  if (typeHas(normalizedType, "completed", "done") || ["completed", "done"].includes(status)) {
    return pick("completed");
  }
  if (typeHas(normalizedType, "cancelled", "canceled") || ["cancelled", "canceled"].includes(status)) {
    return pick("cancelled");
  }
  if (typeHas(normalizedType, "message", "chat")) {
    return pick("message");
  }
  if (typeHas(normalizedType, "request", "created", "new")) {
    return pick("new_request");
  }
  return null;
}

export function attachNotificationI18n({ type, payload }) {
  const normalizedType = String(type || "").trim().toLowerCase();
  const out =
    payload && typeof payload === "object" && !Array.isArray(payload)
      ? { ...payload }
      : {};

  if (!normalizedType) {
    return assignI18n(
      out,
      "notifications.generic.title",
      "notifications.generic.body"
    );
  }

  const actorName = firstNonEmpty(
    out.remoteDisplayName,
    out.remote_display_name,
    out.senderName,
    out.sender_name,
    out.actorName,
    out.actor_name,
    out.callerName,
    out.caller_name
  );

  if (
    normalizedType.startsWith("social.call.") ||
    normalizedType.startsWith("social_call.")
  ) {
    return assignI18n(
      out,
      "notifications.social.call.title",
      "notifications.social.call.body",
      {
        bodyArgs: actorName ? { senderName: actorName } : null,
      }
    );
  }

  if (
    normalizedType.startsWith("social.chat.") ||
    normalizedType.startsWith("social_chat.") ||
    normalizedType === "social_chat_message" ||
    normalizedType === "order_chat_message" ||
    normalizedType === "taxi.chat.message"
  ) {
    return assignI18n(
      out,
      "notifications.chat.message.title",
      "notifications.chat.message.body",
      {
        bodyArgs: actorName ? { senderName: actorName } : null,
      }
    );
  }

  if (normalizedType.startsWith("social.post.like")) {
    return assignI18n(
      out,
      "notifications.social.post.like.title",
      "notifications.social.post.like.body"
    );
  }

  if (normalizedType.startsWith("social.reel.like")) {
    return assignI18n(
      out,
      "notifications.social.reel.like.title",
      "notifications.social.reel.like.body"
    );
  }

  if (
    normalizedType.startsWith("social.story.") ||
    normalizedType.startsWith("social_story.")
  ) {
    return assignI18n(
      out,
      "notifications.social.story.title",
      "notifications.social.story.body",
      {
        bodyArgs: actorName ? { senderName: actorName } : null,
      }
    );
  }

  if (normalizedType.includes(".comment")) {
    return assignI18n(
      out,
      "notifications.social.comment.title",
      "notifications.social.comment.body"
    );
  }

  if (
    normalizedType.startsWith("social.mention.") ||
    normalizedType.startsWith("social.tag.")
  ) {
    return assignI18n(
      out,
      "notifications.social.mention.title",
      "notifications.social.mention.body"
    );
  }

  if (normalizedType.startsWith("social.relation.")) {
    return assignI18n(
      out,
      "notifications.social.relation.title",
      "notifications.social.relation.body"
    );
  }

  if (normalizedType.startsWith("social.report.")) {
    return assignI18n(
      out,
      "notifications.social.report.title",
      "notifications.social.report.body"
    );
  }

  if (
    normalizedType.startsWith("social.community.") ||
    normalizedType.startsWith("social_community.") ||
    normalizedType === "same_block" ||
    normalizedType === "same_building" ||
    normalizedType === "same_compound"
  ) {
    return assignI18n(
      out,
      "notifications.social.community.title",
      "notifications.social.community.body"
    );
  }

  if (normalizedType.startsWith("social.")) {
    return assignI18n(
      out,
      "notifications.social.activity.title",
      "notifications.social.activity.body"
    );
  }

  if (
    normalizedType.startsWith("residence.change.") ||
    normalizedType.startsWith("profile.")
  ) {
    return assignI18n(
      out,
      "notifications.profile.title",
      "notifications.profile.body"
    );
  }

  if (
    normalizedType.startsWith("hr.") ||
    normalizedType.startsWith("employee.") ||
    normalizedType.startsWith("accountant.")
  ) {
    return assignI18n(
      out,
      "notifications.hr.title",
      "notifications.hr.body"
    );
  }

  if (
    normalizedType.startsWith("admin_") ||
    normalizedType.includes("approval") ||
    normalizedType.includes("settlement")
  ) {
    if (normalizedType.startsWith("owner_")) {
      const storeEvent = assignStoreEventI18n(normalizedType, out);
      if (storeEvent) return storeEvent;
    }
    return assignI18n(
      out,
      "notifications.admin.title",
      "notifications.admin.body"
    );
  }

  if (normalizedType.startsWith("real_estate.")) {
    return assignI18n(
      out,
      "notifications.real_estate.title",
      "notifications.real_estate.body"
    );
  }

  if (normalizedType.startsWith("jobs.")) {
    return assignI18n(
      out,
      "notifications.jobs.title",
      "notifications.jobs.body"
    );
  }

  if (normalizedType.startsWith("paid_upgrade.")) {
    return assignI18n(
      out,
      "notifications.paid_upgrades.title",
      "notifications.paid_upgrades.body"
    );
  }

  if (
    normalizedType === "taxi.ride.requested" ||
    String(out.target || "").trim().toLowerCase() === "taxi_ride_requested"
  ) {
    const fare = firstNonEmpty(
      out.fare,
      out.suggestedFareIqd,
      out.proposedFareIqd
    );
    return assignI18n(
      out,
      "notifications.taxi.ride_request.title",
      "notifications.taxi.ride_request.body",
      { bodyArgs: { fare: fare || "" } }
    );
  }

  if (normalizedType.startsWith("taxi.")) {
    const taxiEvent = assignTaxiEventI18n(normalizedType, out);
    if (taxiEvent) return taxiEvent;
    return assignI18n(
      out,
      "notifications.taxi.title",
      "notifications.taxi.body"
    );
  }

  if (
    normalizedType.startsWith("delivery.") ||
    normalizedType.startsWith("delivery_") ||
    normalizedType.startsWith("courier_") ||
    normalizedType.startsWith("customer_delivery")
  ) {
    const deliveryEvent = assignDeliveryEventI18n(normalizedType, out);
    if (deliveryEvent) return deliveryEvent;
    return assignI18n(
      out,
      "notifications.delivery.title",
      "notifications.delivery.body"
    );
  }

  if (
    normalizedType.startsWith("services.") ||
    normalizedType.startsWith("service.") ||
    normalizedType.startsWith("service_") ||
    normalizedType.startsWith("provider_request") ||
    normalizedType.startsWith("customer_service")
  ) {
    const serviceEvent = assignServiceEventI18n(normalizedType, out);
    if (serviceEvent) return serviceEvent;
    return assignI18n(
      out,
      "notifications.services.title",
      "notifications.services.body"
    );
  }

  if (
    normalizedType.startsWith("company.") ||
    normalizedType.startsWith("company_")
  ) {
    return assignI18n(
      out,
      "notifications.company.title",
      "notifications.company.body"
    );
  }

  if (normalizedType === "customer_order_received") {
    const { orderNumber } = readOrderArgs(out);
    return assignI18n(
      out,
      "notifications.orders.received.title",
      "notifications.orders.received.body",
      { bodyArgs: { orderRef: orderNumber || "" } }
    );
  }

  if (normalizedType === "customer_order_status") {
    const orderEvent = assignOrderEventI18n(normalizedType, out);
    if (orderEvent) return orderEvent;
    const storeName = firstNonEmpty(
      out.storeName,
      out.store_name,
      out.merchantName,
      out.merchant_name
    );
    const orderNumber = firstNonEmpty(out.orderNumber, out.orderId, out.order_id);
    const statusTextArg = firstNonEmpty(out.statusText, out.status_text);
    return assignI18n(
      out,
      "notifications.orders.status.title",
      "notifications.orders.status.body",
      {
        bodyArgs: {
          storeName: storeName || "المتجر",
          orderNumber: orderNumber || "",
          statusText: statusTextArg || "",
        },
      }
    );
  }

  if (
    normalizedType.startsWith("owner_") ||
    normalizedType.startsWith("merchant_") ||
    normalizedType.startsWith("customer_order") ||
    normalizedType.startsWith("order_") ||
    normalizedType.includes("order")
  ) {
    if (normalizedType.startsWith("owner_") || normalizedType.startsWith("merchant_")) {
      const storeEvent = assignStoreEventI18n(normalizedType, out);
      if (storeEvent) return storeEvent;
    }
    const orderEvent = assignOrderEventI18n(normalizedType, out);
    if (orderEvent) return orderEvent;
    return assignI18n(
      out,
      "notifications.orders.title",
      "notifications.orders.body"
    );
  }

  return assignI18n(
    out,
    "notifications.generic.title",
    "notifications.generic.body"
  );
}

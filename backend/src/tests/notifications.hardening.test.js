import assert from "node:assert/strict";
import test from "node:test";

import { validatePushTokenContext } from "../modules/notifications/notifications.service.js";
import { attachNotificationI18n } from "../modules/notifications/notification.i18n.js";
import { renderNotificationTextForLocale } from "../modules/notifications/notification.render.js";
import {
  __notificationsRepoTestables,
  buildNotificationAudienceMetadata,
} from "../modules/notifications/notifications.repo.js";
import {
  buildAdminOrderCreatedNotifications,
  buildAdminTaxiRideRequestedNotifications,
} from "../modules/admin/admin-notification-recipients.js";
import { validateCreateThread } from "../modules/feed/feed.validators.js";

const auth = {
  userId: 42,
  sessionId: 77,
  role: "delivery",
  deviceContext: { deviceFingerprint: "device-hash" },
};

test("push registration uses authenticated session and canonical role surface", () => {
  assert.deepEqual(
    validatePushTokenContext(auth, {
      userId: 42,
      sessionId: 77,
      appFlavor: "courier",
    }),
    {
      userId: 42,
      sessionId: 77,
      appSurface: "delivery",
      deviceFingerprint: "device-hash",
    }
  );
});

test("service provider push registration resolves to the user app surface", () => {
  const ctx = validatePushTokenContext(
    {
      userId: 88,
      sessionId: 91,
      role: "service_provider",
      deviceContext: { deviceFingerprint: "provider-device" },
    },
    {
      userId: 88,
      sessionId: 91,
      appFlavor: "user",
    }
  );

  assert.deepEqual(ctx, {
    userId: 88,
    sessionId: 91,
    appSurface: "user",
    deviceFingerprint: "provider-device",
  });
});

test("push registration rejects user, session, and flavor hints that mismatch auth", () => {
  for (const body of [
    { userId: 41 },
    { sessionId: 78 },
    { appFlavor: "user" },
  ]) {
    assert.throws(
      () => validatePushTokenContext(auth, body),
      (error) =>
        error?.message === "PUSH_TOKEN_CONTEXT_MISMATCH" && error?.status === 409
    );
  }
});

test("notification audience metadata maps order and taxi roles to isolated surfaces", () => {
  assert.deepEqual(buildNotificationAudienceMetadata("user"), {
    appSurface: "user",
    roleScope: "customer",
    targetModule: "customer",
  });
  assert.equal(buildNotificationAudienceMetadata("owner").appSurface, "store");
  assert.equal(buildNotificationAudienceMetadata("delivery").appSurface, "delivery");
  assert.equal(buildNotificationAudienceMetadata("taxi_captain").appSurface, "taxi");
  assert.deepEqual(buildNotificationAudienceMetadata("service_provider"), {
    appSurface: "user",
    roleScope: "customer",
    targetModule: "customer",
  });
});

test("push fan-out is isolated by app surface and fails closed without one", () => {
  const targets = [
    { token: "customer-token", appSurface: "user", recipientSurface: "delivery" },
    { token: "courier-token", appSurface: "delivery", recipientSurface: "delivery" },
    { token: "store-token", appSurface: "store", recipientSurface: "delivery" },
  ];
  const selectTargets = __notificationsRepoTestables.selectPushTargetsForSurface;

  const delivery = selectTargets(
    { payload: { appSurface: "delivery" } },
    targets
  );
  assert.equal(delivery.intendedSurface, "delivery");
  assert.deepEqual(delivery.targets.map((target) => target.token), ["courier-token"]);

  const wrongRecipientSurface = selectTargets(
    { payload: { appSurface: "user" } },
    targets
  );
  assert.deepEqual(wrongRecipientSurface.targets, []);
  assert.equal(wrongRecipientSurface.suppressed, "recipient_surface_mismatch");

  const user = selectTargets(
    { payload: { app_surface: "user" } },
    targets.map((target) => ({ ...target, recipientSurface: "user" }))
  );
  assert.deepEqual(user.targets.map((target) => target.token), ["customer-token"]);

  const missingAudience = selectTargets(
    { payload: { target: "order_tracking" } },
    targets
  );
  assert.deepEqual(missingAudience.targets, []);
  assert.equal(missingAudience.suppressed, "missing_surface");
});

test("push message carries the canonical target app surface", () => {
  const message = __notificationsRepoTestables.buildMulticastMessage(
    {
      id: 8,
      type: "customer_order_on_the_way",
      title: "Update",
      body: "Moving",
      payload: {
        appSurface: "user",
        roleScope: "customer",
        targetModule: "customer",
      },
    },
    ["redacted-token"],
    12,
    { title: "Update", body: "Moving" },
    "user"
  );
  assert.equal(message.data.appSurface, "user");
  assert.equal(message.data.roleScope, "customer");
  assert.equal(message.data.targetModule, "customer");
});

test("customer order updates replace the same Android notification and group on iOS", () => {
  const message = __notificationsRepoTestables.buildMulticastMessage(
    {
      id: 88,
      type: "customer_order_on_the_way",
      title: "Order update",
      body: "The courier is on the way",
      payload: { appSurface: "user", targetModule: "customer" },
    },
    ["redacted-token"],
    190,
    { title: "Order update", body: "The courier is on the way" },
    "user",
  );

  assert.equal(message.android.notification.tag, "customer-order:190");
  assert.equal(message.apns.headers["apns-collapse-id"], "customer-order:190");
  assert.equal(message.apns.payload.aps.threadId, "customer-order:190");
  assert.equal(message.data.orderId, "190");
  assert.equal(message.data.target, "order_tracking");
});

test("push message carries complete tap routing payload for web and mobile", () => {
  const message = __notificationsRepoTestables.buildMulticastMessage(
    {
      id: 18,
      type: "taxi.offer.received",
      title: "Taxi offer",
      body: "Open offer",
      payload: {
        appSurface: "user",
        target: "taxi_offer_received",
        targetModule: "taxi",
        roleScope: "customer",
        action: "open_offer",
        requestId: 501,
        offerId: 701,
        bidId: 801,
        rideId: 901,
        captainId: 21,
        customerUserId: 42,
        requiresAction: true,
      },
    },
    ["redacted-token"],
    null,
    { title: "Taxi offer", body: "Open offer" },
    "user"
  );

  assert.equal(message.data.notificationId, "18");
  assert.equal(message.data.target, "taxi_offer_received");
  assert.equal(message.data.deepLinkTarget, "taxi_offer_received");
  assert.equal(message.data.action, "open_offer");
  assert.equal(message.data.requestId, "501");
  assert.equal(message.data.ticketId, "501");
  assert.equal(message.data.offerId, "701");
  assert.equal(message.data.bidId, "801");
  assert.equal(message.data.rideId, "901");
  assert.equal(message.data.captainId, "21");
  assert.equal(message.data.customerUserId, "42");
  assert.equal(message.data.requiresAction, "true");
});

test("listing notifications resolve to direct car and real-estate targets", () => {
  const carMessage = __notificationsRepoTestables.buildMulticastMessage(
    {
      id: 9,
      type: "car_listing",
      title: "Car listing",
      body: "Open the listing",
      payload: {
        target: "car_listing",
        targetModule: "customer",
        entityId: 991,
      },
    },
    ["redacted-token"],
    null,
    { title: "Car listing", body: "Open the listing" },
    "user"
  );
  assert.equal(carMessage.data.target, "car_listing");
  assert.equal(carMessage.data.deepLinkTarget, "car_listing");
  assert.equal(carMessage.data.entityId, "991");

  const estateMessage = __notificationsRepoTestables.buildMulticastMessage(
    {
      id: 10,
      type: "real_estate_listing",
      title: "Real estate listing",
      body: "Open the listing",
      payload: {
        target: "real_estate_listing",
        targetModule: "customer",
        entityId: 881,
      },
    },
    ["redacted-token"],
    null,
    { title: "Real estate listing", body: "Open the listing" },
    "user"
  );
  assert.equal(estateMessage.data.target, "real_estate_listing");
  assert.equal(estateMessage.data.deepLinkTarget, "real_estate_listing");
  assert.equal(estateMessage.data.entityId, "881");
});

test("pharmacy order notifications preserve explicit deep-link targets", () => {
  const customerMessage = __notificationsRepoTestables.buildMulticastMessage(
    {
      id: 11,
      type: "pharmacy.order.created",
      title: "Pharmacy order created",
      body: "Open the order",
      payload: {
        target: "order_details",
        targetModule: "customer",
        orderId: 731,
        conversationId: 44,
      },
    },
    ["redacted-token"],
    731,
    { title: "Pharmacy order created", body: "Open the order" },
    "user"
  );
  assert.equal(customerMessage.data.target, "order_details");
  assert.equal(customerMessage.data.deepLinkTarget, "order_details");
  assert.equal(customerMessage.data.orderId, "731");

  const ownerMessage = __notificationsRepoTestables.buildMulticastMessage(
    {
      id: 12,
      type: "pharmacy.order.created.store",
      title: "Pharmacy order created",
      body: "Open the order",
      payload: {
        target: "owner_order_details",
        targetModule: "merchant",
        orderId: 731,
        conversationId: 44,
      },
    },
    ["redacted-token"],
    731,
    { title: "Pharmacy order created", body: "Open the order" },
    "store"
  );
  assert.equal(ownerMessage.data.target, "owner_order_details");
  assert.equal(ownerMessage.data.deepLinkTarget, "owner_order_details");
  assert.equal(ownerMessage.data.orderId, "731");
});

test("admin order notifications resolve to monitoring order details", () => {
  const rows = buildAdminOrderCreatedNotifications({
    recipientUserIds: [2, "2", 4, null],
    order: {
      id: 731,
      merchant_id: 9,
      merchant_name: "علوة مسلكي",
      status: "pending",
    },
    orderGroupId: 33,
    storesCount: 2,
  });
  assert.equal(rows.length, 2);
  assert.deepEqual(
    rows.map((row) => row.userId),
    [2, 4],
  );
  assert.equal(rows[0].type, "admin_order_created");
  assert.equal(rows[0].payload.target, "admin_order_details");
  assert.equal(rows[0].payload.targetModule, "admin");
  assert.equal(rows[0].payload.roleScope, "admin");
  assert.equal(rows[0].payload.orderId, 731);
  assert.equal(rows[0].payload.entityId, 731);
  assert.equal(rows[0].payload.orderGroupId, 33);

  const message = __notificationsRepoTestables.buildMulticastMessage(
    {
      id: 20,
      type: "admin_order_created",
      title: rows[0].title,
      body: rows[0].body,
      payload: rows[0].payload,
    },
    ["redacted-token"],
    731,
    { title: rows[0].title, body: rows[0].body },
    "company",
  );
  assert.equal(message.data.target, "admin_order_details");
  assert.equal(message.data.deepLinkTarget, "admin_order_details");
  assert.equal(message.data.targetModule, "admin");
  assert.equal(message.data.roleScope, "admin");
  assert.equal(message.data.orderId, "731");
});

test("admin taxi ride notifications resolve to monitoring ride details", () => {
  const rows = buildAdminTaxiRideRequestedNotifications({
    recipientUserIds: [3, 3, "5"],
    ride: {
      id: 44,
      customerUserId: 99,
      proposedFareIqd: 7000,
      status: "searching",
      pickup: { label: "البوابة" },
      dropoff: { label: "السوق" },
    },
  });
  assert.equal(rows.length, 2);
  assert.deepEqual(
    rows.map((row) => row.userId),
    [3, 5],
  );
  assert.equal(rows[0].type, "admin_taxi_ride_requested");
  assert.equal(rows[0].payload.target, "admin_taxi_ride_details");
  assert.equal(rows[0].payload.targetModule, "admin");
  assert.equal(rows[0].payload.roleScope, "admin");
  assert.equal(rows[0].payload.rideId, 44);
  assert.equal(rows[0].payload.entityId, 44);

  const message = __notificationsRepoTestables.buildMulticastMessage(
    {
      id: 21,
      type: "admin_taxi_ride_requested",
      title: rows[0].title,
      body: rows[0].body,
      payload: rows[0].payload,
    },
    ["redacted-token"],
    null,
    { title: rows[0].title, body: rows[0].body },
    "company",
  );
  assert.equal(message.data.target, "admin_taxi_ride_details");
  assert.equal(message.data.deepLinkTarget, "admin_taxi_ride_details");
  assert.equal(message.data.targetModule, "admin");
  assert.equal(message.data.roleScope, "admin");
  assert.equal(message.data.rideId, "44");
});

test("courier assignment change pushes resolve to current courier orders", () => {
  for (const type of [
    "delivery_order_assigned",
    "delivery_order_removed",
    "delivery_order_reassigned",
    "delivery_assigned_by_owner",
  ]) {
    const message = __notificationsRepoTestables.buildMulticastMessage(
      {
        id: 30,
        type,
        title: "Delivery update",
        body: "Open the order",
        payload: {
          appSurface: "delivery",
          roleScope: "courier",
          targetModule: "courier",
        },
      },
      ["redacted-token"],
      88,
      { title: "Delivery update", body: "Open the order" },
      "delivery",
    );
    assert.equal(message.data.target, "courier_orders_current");
    assert.equal(message.data.deepLinkTarget, "courier_orders_current");
    assert.equal(message.data.targetModule, "courier");
    assert.equal(message.data.roleScope, "courier");
    assert.equal(message.data.orderId, "88");
  }
});

test("customer order notifications describe the exact status update", () => {
  const payload = attachNotificationI18n({
    type: "customer_order_status",
    payload: {
      orderId: 42,
      status: "on_the_way",
      courierName: "Ali",
      storeName: "Maslaki Oven",
    },
  });

  assert.equal(payload.i18nTitleKey, "notifications.orders.on_the_way.title");
  assert.equal(payload.i18nBodyKey, "notifications.orders.on_the_way.body");

  const text = renderNotificationTextForLocale({
    locale: "en",
    title: "Order update",
    body: "There is a new update on your order.",
    payload,
  });
  assert.match(text.title, /on the way/i);
  assert.match(text.body, /Ali/);
  assert.match(text.body, /#42/);
  assert.doesNotMatch(text.body, /new update on your order/i);
});

test("customer receipt confirmation has a clear localized completion notice", () => {
  const payload = attachNotificationI18n({
    type: "customer_order_received",
    payload: { orderId: 190, status: "received" },
  });

  assert.equal(payload.i18nTitleKey, "notifications.orders.received.title");
  assert.equal(payload.i18nBodyKey, "notifications.orders.received.body");
  const text = renderNotificationTextForLocale({
    locale: "en",
    title: "Order update",
    body: "There is a new update on your order.",
    payload,
  });
  assert.equal(text.title, "Order received");
  assert.match(text.body, /order 190/i);
  assert.match(text.body, /complete/i);
});

test("delivery notifications describe assignment changes", () => {
  const payload = attachNotificationI18n({
    type: "delivery_order_assigned",
    payload: {
      orderId: 88,
      storeName: "Family Mart",
      customerName: "Sara",
    },
  });

  assert.equal(payload.i18nTitleKey, "notifications.delivery.assigned.title");
  assert.equal(payload.i18nBodyKey, "notifications.delivery.assigned.body");

  const text = renderNotificationTextForLocale({
    locale: "en",
    title: "Delivery update",
    body: "A delivery request or courier status has changed.",
    payload,
  });
  assert.match(text.body, /assigned/i);
  assert.match(text.body, /Family Mart/);
  assert.match(text.body, /Sara/);
});

test("courier reconciliation notification explains the review decision", () => {
  const payload = attachNotificationI18n({
    type: "courier_reconciliation_rejected",
    payload: {
      orderId: 148,
      reviewNote: "Receipt is unclear",
    },
  });

  assert.equal(
    payload.i18nTitleKey,
    "notifications.delivery.reconciliation_rejected.title",
  );
  assert.equal(
    payload.i18nBodyKey,
    "notifications.delivery.reconciliation_rejected.body",
  );
  const text = renderNotificationTextForLocale({
    locale: "en",
    title: "Settlement update",
    body: "Open the report",
    payload,
  });
  assert.match(text.body, /#148/);
  assert.match(text.body, /Receipt is unclear/);
});

test("store owner notifications describe store-side order events", () => {
  const payload = attachNotificationI18n({
    type: "owner_new_order",
    payload: {
      orderId: 91,
      storeName: "Green Market",
      customerName: "Mina",
    },
  });

  assert.equal(payload.i18nTitleKey, "notifications.store.new_order.title");
  assert.equal(payload.i18nBodyKey, "notifications.store.new_order.body");

  const text = renderNotificationTextForLocale({
    locale: "en",
    title: "New order",
    body: "Order received",
    payload,
  });
  assert.match(text.title, /store order/i);
  assert.match(text.body, /#91/);
  assert.match(text.body, /Mina/);
  assert.match(text.body, /accept/i);
});

test("store settlement notifications show payout details", () => {
  const payload = attachNotificationI18n({
    type: "owner_settlement_approved",
    payload: {
      storeName: "Green Market",
      amount: "45000",
    },
  });

  assert.equal(payload.i18nTitleKey, "notifications.store.settlement_approved.title");
  assert.equal(payload.i18nBodyKey, "notifications.store.settlement_approved.body");

  const text = renderNotificationTextForLocale({
    locale: "en",
    title: "Admin update",
    body: "There is a new administrative review or action.",
    payload,
  });
  assert.match(text.title, /payout approved/i);
  assert.match(text.body, /Green Market/);
  assert.match(text.body, /45000/);
});

test("taxi notifications describe ride lifecycle events", () => {
  const payload = attachNotificationI18n({
    type: "taxi.ride.assigned",
    payload: { rideId: 7, captainName: "Omar" },
  });

  assert.equal(payload.i18nTitleKey, "notifications.taxi.assigned.title");
  assert.equal(payload.i18nBodyKey, "notifications.taxi.assigned.body");

  const text = renderNotificationTextForLocale({
    locale: "en",
    title: "Ride update",
    body: "Your ride status has been updated.",
    payload,
  });
  assert.match(text.title, /accepted/i);
  assert.match(text.body, /Omar/);
  assert.match(text.body, /#7/);
});

test("service notifications describe request events", () => {
  const payload = attachNotificationI18n({
    type: "services.request.accepted",
    payload: {
      requestId: 19,
      providerName: "Fix Pro",
      serviceName: "AC repair",
    },
  });

  assert.equal(payload.i18nTitleKey, "notifications.services.accepted.title");
  assert.equal(payload.i18nBodyKey, "notifications.services.accepted.body");

  const text = renderNotificationTextForLocale({
    locale: "en",
    title: "Service update",
    body: "There is a new update on your service request.",
    payload,
  });
  assert.match(text.body, /Fix Pro/);
  assert.match(text.body, /AC repair/);
  assert.match(text.body, /#19/);
});

test("business thread validation accepts car and real-estate contexts", () => {
  assert.equal(
    validateCreateThread({
      userId: 7,
      kind: "business",
      contextType: "car_listing",
      contextId: 11,
    }).ok,
    true
  );
  assert.equal(
    validateCreateThread({
      userId: 7,
      kind: "business",
      contextType: "real_estate_listing",
      contextId: 22,
    }).ok,
    true
  );
});

test("notification action tracking only links notifications owned by the actor", () => {
  const sql = __notificationsRepoTestables.notificationActionEventInsertSql;

  assert.match(sql, /FROM app_notification n/i);
  assert.match(sql, /n\.id = \$1::bigint/i);
  assert.match(sql, /n\.user_id = \$2/i);
});

# Notifications: content, deep links, role isolation, incoming calls

Last updated 2026-10-18. Source of truth in code:

| Concern | Backend | App |
| --- | --- | --- |
| Title/body rules | `backend/src/modules/notifications/notification.i18n.js` (`GENERIC_NOTIFICATION_KEYS`), `notification.render.js` | `lib/core/i18n/notification_localizer.dart` |
| Deep-link payload | `notifications.repo.js` → `resolveNotificationTarget`, `attachDeepLinkEntity` | `lib/core/notifications/notification_navigation.dart` → `resolveDestination` / `buildRoute` |
| Role isolation | `applyRecipientAudience`, `selectPushTargetsForSurface`, inbox `surfaceFilter` | `isPayloadAllowedForFlavor`, `notificationPayloadMatchesAppFlavor`, `appFlavorForPackageName` |
| Calls | `backend/src/modules/feed/feed.call-push.js`, `notifications/apns-voip.js` | `lib/core/calls/incoming_call_service.dart`, `android/.../MainApplication.kt`, `ios/Runner/AppDelegate.swift` |

Tests pinning this document: `backend/src/tests/notifications.content-routing-isolation.test.js`,
`backend/src/tests/social.call-ringing.db.test.js`,
`test/core/notifications/notification_destination_table_test.dart`,
`test/core/notifications/notification_text_specificity_test.dart`.

## 1. Content rules

* The caller of `createNotification` writes the **specific** Arabic title/body (who, what, which order/ticket/ride).
  English copy travels as `textEn: { title, body }` (top-level param or `payload.textEn`) and is used for devices whose
  locale is `en` (push render and in-app list).
* Event templates with real arguments (`notifications.orders.preparing.*`, `notifications.delivery.assigned.*`,
  `notifications.taxi.*`, `notifications.services.*` …) still localise per device.
* **Category-level keys** (`notifications.admin.*`, `hr`, `jobs`, `company`, `profile`, `generic`, `social.activity` …,
  full list in `GENERIC_NOTIFICATION_KEYS`) are only used when the caller left the piece empty. This is what caused
  "تحديث إداري جديد" for admins: the generic key used to overwrite the real title. Legacy rows that still carry a
  generic key render their stored text in both backend and app.
* Copy fixed in this pass: support (every ticket event names the ticket number + subject, urgent tickets read
  "🚨 تذكرة دعم عاجلة: …"), Mimo escalations, HR/payroll, jobs, courier/captain account approvals, social likes/
  comments/stories/reports, store/courier commerce events (accept/pick-up/cancel/payouts/competitions), order
  revisions, outbox store/courier events (incl. a mojibake title), missed calls.

## 2. Deep-link payload contract

Every stored notification and every push `data` map carries:

| Field | Meaning |
| --- | --- |
| `type` | event type (e.g. `support.mimo.escalation`) |
| `target` | screen key (table below) — set by the caller or derived by `resolveNotificationTarget` |
| `targetEntity` + `entityId` | the entity (`order`, `taxi_ride`, `social_thread`, `support_ticket`, `social_post`, …) |
| `orderId` / `rideId` / `threadId` / `ticketId`(=`requestId`) / `postId` / `sessionId` … | typed ids |
| `appSurface` / `roleScope` / `targetModule` | the recipient's own app (always rewritten from the recipient's role) |

Taps from the system tray (foreground local notification, background `onMessageOpenedApp`, cold start
`getInitialMessage` / local `getNotificationAppLaunchDetails`) and from the in-app list (`payloadFromModel`) all go
through `NotificationNavigation.open → resolveDestination → buildRoute`.

## 3. Routing table (type/target → screen, per app)

### Customer app (`user`)

| Notification | Screen |
| --- | --- |
| order events (`customer_order_*`, `order_*`, target `order_tracking`, any `orderId`) | `DeliveryLiveTrackingScreen(orderId)` |
| `customer_orders_current/completed/cancelled` | order lists |
| `social.chat.message` (target `social_chat`) | `SocialShellScreen(messages, threadId)` → that conversation |
| `social.call.incoming` (target `social_call`) | `SocialCallScreen(threadId, sessionId)` |
| `social.call.missed/declined/ended` | that conversation (never the call screen) |
| `support.*` / `support_ticket` | `SupportTicketDetailsScreen(ticketId)` |
| taxi assigned/arrived/started/completed/cancelled (+`rideId`) | `TaxiLiveTrackingScreen(rideId)` |
| taxi offers / ride chat / request | `MapPage` (offers are accepted on the live request) |
| `taxi.ride.shared` | `TaxiSharedRideTrackingScreen(rideId)` |
| `social.post.*` / `social.reel.*` / `social.story.*` | post / reel / story |
| `social.relation.*`, `profile.*` | profile |
| `social.capability.restricted` | `SocialRestrictionsScreen` |
| `services.request.*` | `ServiceRequestDetailsScreen(requestId)` |
| `services.central.*` / `customer_emergency_request` | `EmergencyRequestTrackingScreen(requestId)` |
| `pharmacy.*` | `PharmacyConversationScreen(conversationId)` (order created → order) |
| `real_estate.*`, `car_listing` | listing details / workspace / marketplace |
| `jobs.*` | my applications (tab by status) |
| `paid_upgrade.*` | paid upgrades |
| anything else | notifications list |

### Store app (`store`)

| Notification | Screen |
| --- | --- |
| `owner_*` order events with `orderId`, `merchant_order_details`, `order_tracking`, `order_revision`, `merchant_review_created` | `MerchantOrderDetailsPage(orderId)` |
| `owner_orders` / `merchant_orders_current` without id | current orders |
| `owner_payment_request_*`, `merchant_receivable*`, settlements | `MerchantReceivablesPage` |
| `support.*` | `SupportTicketDetailsScreen(ticketId)` |
| `pharmacy.*` | owner pharmacy conversation |
| `jobs.*`, `hr.*`, `accountant.*`, `employee.*` (owner) | job applications / HR / accountant / employee portal |
| `owner.*` (subscriptions, payroll) | owner dashboard |
| anything else with `orderId` | that order; otherwise store notifications |

### Delivery app (`delivery`)

| Notification | Screen |
| --- | --- |
| assignment changes (`delivery_order_assigned/reassigned/removed`, `delivery_assigned_by_owner`, `delivery_order_ready*`, invoice updated) | `CourierOrderDetailsPage(orderId)` |
| open offers (`delivery_order_available/offer`, `requiresAction` without "assigned") | `CourierOrdersNewPage` |
| grouped job (`delivery_grouped_assigned`) | `CourierOrdersCurrentPage` |
| completed / cancelled | that order (or the list) |
| competitions / earnings / reports / reconciliation | their pages |
| `support.*` | ticket |
| customer / social targets | `DeliveryRestrictedScreen` (hard isolation) |

### Captain app (`taxi`)

| Notification | Screen |
| --- | --- |
| `taxi.ride.requested` / `taxi_new_request` (+`rideId`) | `TaxiTripDetailsPage(rideId)` to accept |
| offers, ride chat, assigned/arrived/started/completed/cancelled | `TaxiTripDetailsPage(rideId)` |
| competitions / earnings / reports | their pages |

### Company / admin / super admin (`company`; super admin also in the user app)

| Notification | Screen |
| --- | --- |
| `admin_support_ticket_created`, `support.*` incl. **`support.mimo.escalation`** | `AdminSupportTicketDetailsScreen(ticketId)` |
| `admin_order_created`, `admin.order.*`, any `orderId` | `MonitoringDetailScreen(order)` |
| `admin_taxi_ride_requested`, `admin.taxi.ride.*`, any `rideId` | `MonitoringDetailScreen(taxiRide)` |
| `admin_pending_merchant`, `admin_delivery_pending_approval`, `admin_taxi_captain_pending_approval` | `AdminMerchantApprovalsScreen` |
| other approvals / profile / residence requests | approvals hub / residence requests |
| settlements / payment requests | `AdminReceivablesScreen` |
| `social.report.*.created` | `AdminSocialReportsScreen` |
| `admin.ops.*` | notification center / crash center / feature flags / permissions / AI dev incident (`entityId`) |
| `services.*` approvals / emergencies | services hub / `EmergencyRequestTrackingScreen(adminMode)` |
| taxi payments / profile edits / governance | their screens |
| `paid_upgrade.*`, `real_estate.pending_admin_review` | review queues |
| HR (`hr` role) | `HrDashboardScreen`; accountant → `AccountantDashboardScreen` |

## 4. Role isolation

1. **Recipient decides the audience.** `applyRecipientAudience` sets `appSurface` from the recipient's role and
   rewrites a conflicting `roleScope`/`targetModule` (e.g. a customer-shaped support payload sent to an owner becomes
   `merchant`; `support_ticket` becomes `admin_support_ticket` for admins and back for everyone else).
2. **Push tokens are per app surface + session.** `user_push_token.app_surface` is set from the authenticated role at
   registration; `auth_session_id` must be a live session. A token re-registered by another account/app moves with
   `ON CONFLICT (push_token)`. Fan-out sends only to tokens whose surface equals the recipient's surface.
3. **Inbox + badge** (`GET /api/notifications`, unread count) only return rows tagged for the caller's current surface
   (untagged legacy rows stay visible), so a customer who became a courier no longer sees customer rows.
4. **App guards.** Each app ignores pushes/taps for another surface (`notificationPayloadMatchesAppFlavor`), and the
   FCM background isolate now resolves its flavor from the package name — before, every non-customer app dropped all
   data-only pushes while closed (e.g. captains never saw ride requests).
5. Captains are no longer routed through the customer branch.

## 5. Incoming calls

* `POST …/call/start` → `sendIncomingCallPush`: **data-only, high priority** FCM (`social.call.incoming`, TTL 45 s,
  collapse key `social-call:<session>`) + **PushKit VoIP** push on iOS when APNs keys are configured. Not stored in
  the inbox.
* Android: the background handler shows `flutter_callkit_incoming`'s full-screen incoming-call activity (system
  ringtone, loops, Answer / Decline, lock screen, self-managed `ConnectionService`). iOS: CallKit via PushKit.
* **Answer** → app opens straight into `SocialCallScreen(initialAction: accept)` (also on cold start via
  `activeCalls()`); the platform call is kept connected (mic foreground service / CallKit audio) and ended when the
  call screen closes.
* **Decline** → native code posts the signed `callActionToken` to `POST /api/feed/chats/calls/decline` (works with the
  app closed); the caller immediately gets the decline signal.
* Caller hangs up / timeout / declined on another device → silent `social.call.ended` push dismisses the ringing UI;
  the callee gets a stored **"مكالمة فائتة من X"** (opens the chat), the caller "X ما رد على مكالمتك".
* App in foreground: the SSE `incoming_call` event opens the in-app call screen; the push never adds a second ring.

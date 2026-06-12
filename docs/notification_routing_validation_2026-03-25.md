# Notification Routing Validation - 2026-03-25

## Scope
- Project: MASLAKI
- Focus:
  - Notification routing correctness by role/module.
  - Courier vs Taxi separation.
  - Lifecycle entry points: `foreground`, `background`, `terminated`.
  - Warnings clean-up in the touched notification/routing files.

## Automated checks executed

### 1) Routing matrix tests
File: `test/core/notifications/notification_routing_test.dart`

Scenarios:
- `courier_order_offer` -> courier module.
- `taxi_trip_offer` -> taxi module.
- `merchant_payment_confirmed` -> merchant receivables.
- `admin_payment_request` -> admin payment requests.
- `customer_order_update` -> customer order tracking.

Result: **PASS** (6/6 tests).

### 2) Lifecycle wiring tests
Validated presence of the real handlers and wiring:
- `FirebaseMessaging.getInitialMessage()` (terminated / FCM launch)
- `FirebaseMessaging.onMessageOpenedApp.listen(...)` (background tap)
- `FirebaseMessaging.onMessage.listen(...)` (foreground)
- `FlutterLocalNotificationsPlugin.getNotificationAppLaunchDetails()` (terminated / local launch)
- Unified handoff in app shell:
  - `localNotifications.tapStream.listen(_handleNotificationTap)`
  - `push.tapStream.listen(_handleNotificationTap)`
  - final route open via `NotificationNavigation.open(...)`

Result: **PASS**.

### 3) Static analysis for touched files
Command:
- `dart analyze` on modified notification/routing/order-owner files + test file.

Result: **PASS** (No issues found).

## Fixes included in this validation batch
- Added missing role-target mapping in `notification_type_registry.dart`:
  - `merchant_payment* / merchant_settlement* / merchant_receivable*` -> `merchant_receivables`.
  - `admin_payment* / admin_settlement* / admin_receivable*` -> `admin_payment_requests`.
- Added focused notification routing test suite.
- Removed warnings in touched files:
  - removed unnecessary casts in `owner_controller.dart`.
  - suppressed intentional private helper warnings in `order_receipt_printing.dart` via file-level ignore.

## Current status
- Notification routing for tested critical paths: **PASS**.
- Courier/Taxi module separation for tested notification types: **PASS**.
- Foreground/Background/Terminated wiring presence: **PASS**.

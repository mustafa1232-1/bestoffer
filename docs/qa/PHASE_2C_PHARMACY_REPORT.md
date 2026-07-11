# Phase 2C Pharmacy Report

## Scope

- Pharmacy app and pharmacy-facing backend APIs
- Customer pharmacy conversation flow
- Merchant pharmacy conversation / cart proposal flow
- Notification targets and deep-link routing for pharmacy commerce

## Verification Summary

- Backend unit tests continued to pass after the Pharmacy notification target assertions were added.
- `backend/src/scripts/pharmacyE2ECheck.js` passed on Railway and exercised the full Pharmacy commerce flow.

## Runtime Evidence

- Approved pharmacy merchant creation and approval were required before conversation access.
- Customer pharmacy conversation creation, messaging, and attachment upload worked.
- Merchant proposed a cart, customer accepted it, and the proposal converted to the expected order path.
- Notification targets stayed stable for:
  - `pharmacy_conversation`
  - `order_details`
  - `owner_order_details`
- The runtime flow preserved the existing auth/session behavior while proving the Pharmacy-specific endpoints.

## Related Test Coverage

- `backend/src/tests/notifications.hardening.test.js`
- `backend/src/scripts/pharmacyE2ECheck.js`
- `test/core/notifications/notification_routing_test.dart`

## Device QA

- No real-device gate was required for Pharmacy in this phase.
- The phase remains runtime-verified only.


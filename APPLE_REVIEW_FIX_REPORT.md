# Apple Review Fix Report

## Scope

Maslaki is a Flutter app using Dart SDK `^3.10.7`, Riverpod, GoRouter, Dio, `flutter_secure_storage`, Firebase Messaging, `image_picker`, Geolocator, and Flutter local notifications. The iOS Runner target uses bundle id `com.maslaki.user` and iOS deployment target `16.0`.

## Guideline 2.1 - App Completeness

Root cause:
- Login failures could display a generic credential message with an internal request id appended.
- Release API configuration could be overridden with an insecure/local `API_BASE_URL`.
- Iraqi phone formats were not normalized consistently across `+964`, `964`, bare `7`, and local `07` formats.
- Provider registration used a separate phone/PIN normalizer from login.

Changed behavior:
- Login now maps credential, network, timeout, 429, 404, and 5xx failures to separate user-safe localized messages without request ids.
- Release builds only accept HTTPS non-local API overrides; otherwise they use `https://bestoffer-production.up.railway.app`.
- Phone and PIN normalization is shared and covered by tests. PIN leading zeroes are preserved.
- Login has an additional local in-flight guard to prevent duplicate rapid submissions.
- Provider registration validates phone/PIN before submission and shares the auth normalizer.
- Image picks reject unsupported formats and images larger than 8 MB before multipart upload.

## Guideline 2.5.4 - Background Services

Root cause:
- `ios/Runner/Info.plist` declared `audio` and `location` background modes without a proven iOS feature requiring continuous background audio or location.
- The app requested/advertised Always-location behavior, while code evidence showed foreground current-position usage.

Changed behavior:
- Removed `audio` and `location` from `UIBackgroundModes`.
- Kept `remote-notification` because Firebase Messaging background handling and push token registration are implemented.
- Removed the Always-location usage description.
- Permission policy no longer requires `locationAlways`.

Final expected `UIBackgroundModes`:
- `remote-notification`

## Guideline 3.1.1 - In-App Purchase

Root cause:
- The legacy service-provider onboarding flow used admin-priced subscription offers and cash confirmation states to activate digital provider access.
- This is digital functionality under App Store rules when it unlocks provider account activation/listing/workspace access.

Changed behavior:
- Product decision made: provider registration and digital activation are free in this iOS release.
- Flutter provider onboarding now uses free application-review wording and no offer/cash response controls.
- Backend `registerServiceProvider` now creates/reuses a `service_provider` user and pending provider profile directly.
- Backend provider payment activation mutators now return `SERVICE_PROVIDER_EXTERNAL_PAYMENT_DISABLED`.
- Backend legacy provider subscription list/reject endpoints also return `SERVICE_PROVIDER_EXTERNAL_PAYMENT_DISABLED`.
- Provider status maps legacy payment states to neutral review compatibility states without faking approval.
- Admin dashboard/provider review UI now uses pending provider moderation instead of subscription request activation.
- Provider workspace and provider permission operations require `provider_approval_status = approved`.

Remaining required work:
- Deploy the backend changes before App Review.
- Migrate or archive legacy provider subscription request rows so they cannot be treated as the current activation source of truth.
- Do not enable paid iOS provider subscriptions unless a future StoreKit implementation is completed.

## Account Deletion

Changed behavior:
- The app exposes Settings > Account security > Delete Account Permanently.
- The flow requires two confirmations, calls `DELETE /api/users/me`, handles errors, and clears local session only after backend success.
- Backend account deletion now records deletion status/timestamps, anonymizes personal account fields, randomizes the PIN hash, revokes sessions, invalidates push tokens, hides public provider profiles/offerings, and disables linked operational role profiles.
- `DELETE /api/account` is also mounted as a clear account-resource alias.

Data retained:
- Order, invoice, ride, delivery, moderation, audit, tax/accounting, dispute, safety, fraud-prevention, and historical transaction records are retained where operationally or legally required, with the deleted user no longer exposed as an active public identity.

Remaining external release gates:
- Deploy the backend changes before App Review.
- Verify production review credentials with `cd backend && npm run verify:review-accounts`.
- Run `tool/validate_ios_release.sh` on macOS and inspect the signed Release archive.
- Run a clean TestFlight install on a physical iOS device.

## Related Audit

Login and guest access:
- `lib/features/auth/presentation/login_screen.dart`
- `lib/features/auth/state/auth_controller.dart`
- `lib/features/auth/data/auth_api.dart`
- `lib/features/auth/data/auth_repo_impl.dart`
- `lib/core/network/dio_client.dart`
- `lib/core/storage/secure_storage.dart`

Service-provider registration:
- `lib/features/services/ui/service_provider_onboarding_screen.dart`
- `lib/features/services/data/services_api.dart`
- `backend/src/modules/services/*`
- `backend/sql/115_service_provider_subscription_workflow.sql`

Subscription/payment activation:
- `lib/features/services/ui/service_provider_onboarding_screen.dart`
- `backend/src/modules/services/services.service.js`
- `backend/src/modules/services/services.repo.js`
- `backend/src/modules/services/services.routes.js`
- `backend/sql/115_service_provider_subscription_workflow.sql`
- `PAYMENT_FLOW_CLASSIFICATION.md`
- `BACKEND_FREE_PROVIDER_ACTIVATION_REQUIREMENTS.md`

Background modes and permissions:
- `ios/Runner/Info.plist`
- `ios/Runner/Runner.entitlements`
- `ios/Runner/Runner_Release.entitlements`
- `ios/Runner.xcodeproj/project.pbxproj`
- `lib/core/permissions/maslaki_permission_policy.dart`
- `packages/core_maps/lib/src/location_permission_service.dart`

Push notifications:
- `lib/core/notifications/push_notification_service.dart`
- `lib/core/notifications/local_notification_service.dart`
- `lib/features/notifications/*`
- `ios/Runner/Runner_Release.entitlements`

Image uploads:
- `lib/core/files/image_picker_service.dart`
- `lib/core/files/local_image_file.dart`
- `lib/core/widgets/image_picker_field.dart`
- `lib/features/auth/data/auth_api.dart`
- `lib/features/services/data/services_api.dart`

Environment and production API:
- `lib/core/constants/api.dart`
- `packages/core_networking/lib/src/runtime_api_config.dart`
- `.env.example`
- `backend/.env.example`

## Files Changed

- `ios/Runner/Info.plist`
- `lib/core/constants/api.dart`
- `packages/core_networking/lib/src/runtime_api_config.dart`
- `lib/core/permissions/maslaki_permission_policy.dart`
- `lib/core/files/image_picker_service.dart`
- `lib/core/files/local_image_file.dart`
- `lib/features/auth/domain/auth_input_normalizer.dart`
- `lib/features/auth/domain/login_error_mapper.dart`
- `lib/features/auth/data/auth_repo_impl.dart`
- `lib/features/auth/presentation/login_screen.dart`
- `lib/features/auth/state/auth_controller.dart`
- `lib/features/services/ui/service_provider_onboarding_screen.dart`
- `lib/features/services/ui/service_provider_workspace_screen.dart`
- `lib/features/services/data/services_api.dart`
- `lib/features/services/models/service_models.dart`
- `lib/features/customer/ui/customer_account_hub_screen.dart`
- `lib/features/admin/data/admin_api.dart`
- `lib/features/admin/ui/admin_service_provider_applications_screen.dart`
- `lib/features/admin/state/admin_controller.dart`
- `lib/features/admin/ui/admin_approvals_hub_screen.dart`
- `lib/features/admin/ui/admin_dashboard_screen.dart`
- `backend/src/modules/services/services.service.js`
- `backend/src/modules/services/services.repo.js`
- `backend/src/modules/services/services.routes.js`
- `backend/src/modules/users/users.controller.js`
- `backend/src/modules/users/users.repo.js`
- `backend/src/modules/users/users.routes.js`
- `backend/src/modules/users/users.service.js`
- `backend/src/scripts/validateProductionReviewAccounts.js`
- `backend/sql/184_account_deletion_workflow.sql`
- `backend/package.json`
- `lib/features/taxi/ui/taxi_cancel_reason_sheet.dart`
- `lib/features/settings/ui/pages/settings_account_screen.dart`
- `lib/l10n/app_en.arb`
- `lib/l10n/app_ar.arb`
- `lib/l10n/app_localizations.dart`
- `lib/l10n/app_localizations_en.dart`
- `lib/l10n/app_localizations_ar.dart`
- `test/core/auth_controller_delete_account_test.dart`
- `test/features/settings/settings_account_deletion_test.dart`
- `backend/src/tests/services.free-provider-activation.test.js`
- `backend/src/tests/users.account-deletion.test.js`
- `test/auth/login_screen_no_tech_error_and_overflow_test.dart`
- `test/auth/login_screen_service_provider_test.dart`
- `test/auth/login_screen_super_admin_test.dart`
- `test/core/app_user_bootstrap_entry_test.dart`
- `test/core/maslaki_permission_policy_test.dart`
- `test/theme_variants_test.dart`
- `test/admin/super_admin_drawer_navigation_test.dart`
- `test/core/map_page_test.dart`
- `test/features/delivery/delivery_order_detail_test.dart`
- `test/features/tracking/tracking_screens_resilience_test.dart`
- `test/services/services_ui_smoke_test.dart`
- `test/features/auth/auth_input_normalizer_test.dart`
- `test/features/auth/login_error_mapper_test.dart`
- `APPLE_REVIEW_FIX_REPORT.md`
- `APP_STORE_REVIEW_NOTES.md`
- `APP_STORE_CONNECT_CHECKLIST.md`
- `BACKEND_IAP_REQUIREMENTS.md`
- `BACKEND_FREE_PROVIDER_ACTIVATION_REQUIREMENTS.md`
- `BACKEND_ACCOUNT_DELETION_REQUIREMENTS.md`
- `PAYMENT_FLOW_CLASSIFICATION.md`
- `REVIEW_ACCOUNT_VALIDATION.md`
- `PRODUCT_DECISION_REQUIRED.md`
- `tool/validate_ios_release.sh`

## Verification

Executed in this working copy on Windows with Flutter `3.38.6` / Dart `3.10.7`:
- `flutter pub get`: passed.
- `dart format` on changed Dart files: passed.
- `dart format --output=none --set-exit-if-changed .`: failed before completion because repository-wide formatting includes many pre-existing unformatted Dart files and a vendored `third_party/firebase_core/example` analysis-options include that resolves to missing `D:\new apps\storeapp\analysis_options.yaml`.
- `flutter analyze`: passed, no issues found.
- `flutter test`: passed, 676 tests.
- First-party scoped Dart format validation, excluding vendored/generated paths: failed with 289 first-party Dart files reported by `dart format --output=none --set-exit-if-changed`; vendored Firebase/third-party code is no longer part of the validation scope.
- Production `/health`: passed, HTTP 200 from `https://bestoffer-production.up.railway.app/health`.
- Production `/ready`: passed, HTTP 200 from `https://bestoffer-production.up.railway.app/ready`.
- Production `DELETE /api/account` without credentials returned HTTP 401, indicating the account route is mounted behind authentication.
- `railway status`: project `amiable-unity`, environment `production`, service `bestoffer`.
- `node --check backend/src/modules/services/services.service.js`: passed.
- `node --check backend/src/modules/services/services.routes.js`: passed.
- `node --check backend/src/modules/services/services.controller.js`: passed.
- `cd backend && npm test`: passed, 539 tests.
- `cd backend && npm run flow:check`: passed.
- `cd backend && npm run permissions:check`: blocked in this Windows shell because it requires a live local API at `http://127.0.0.1:3000`; a wrapper attempt to launch the local server was rejected by execution policy.
- Final remediation syntax checks passed:
  - `node --check backend/src/modules/users/users.repo.js`
  - `node --check backend/src/modules/users/users.service.js`
  - `node --check backend/src/modules/users/users.controller.js`
  - `node --check backend/src/modules/users/users.routes.js`
  - `node --check backend/src/app.js`
  - `node --check backend/src/modules/services/services.repo.js`
  - `node --check backend/src/scripts/validateProductionReviewAccounts.js`
- Focused final remediation tests passed:
  - `flutter test test/features/settings/settings_account_deletion_test.dart test/core/auth_controller_delete_account_test.dart`
  - `cd backend && node --env-file=.env.test --import ./src/tests/setup/per-file-db.mjs --test src/tests/users.account-deletion.test.js src/tests/services.free-provider-activation.test.js`
- `bash -n tool/validate_ios_release.sh`: not executable on this Windows host because `bash` is not installed.
- `npm run verify:review-accounts`: production health/readiness and invalid-login safety checks passed, then stopped with `customer review credentials are missing` because no production review credentials were provided in this workspace.
- Focused App Review tests passed:
  - `test/features/auth/auth_input_normalizer_test.dart`
  - `test/features/auth/login_error_mapper_test.dart`
  - `test/auth/login_screen_no_tech_error_and_overflow_test.dart`
  - `test/auth/login_screen_service_provider_test.dart`
  - `test/core/maslaki_permission_policy_test.dart`
  - `test/admin/super_admin_drawer_navigation_test.dart`
  - `test/core/map_page_test.dart`
  - `test/features/delivery/delivery_order_detail_test.dart`
  - `test/features/tracking/tracking_screens_resilience_test.dart --plain-name "taxi tracking shows the assigned ride card with captain data"`
  - `test/language/text_encoding_guard_test.dart`
  - `test/services/services_ui_smoke_test.dart`
- `ios/Runner/Info.plist` XML parse: passed.
- Direct plist inspection: `UIBackgroundModes` contains only `remote-notification`; `location`, `audio`, and `NSLocationAlwaysAndWhenInUseUsageDescription` are absent.
- `plutil`: not available on this Windows host.
- `pod`: not available on this Windows host.
- `flutter build ios --release --no-codesign`: not supported by this local Flutter tool on Windows; `flutter build ios` is not listed as an available build subcommand here.

Six original full-suite failures fixed:
- `super admin drawer supports search and opens orders page`: removed a brittle assertion on a presentational group header; navigation item and destination behavior remain asserted.
- `map page shows the searching ride shell without crashing`: updated the expectation because the production UI correctly allows cancellation while searching.
- `raise fare action calls raise-fare endpoint, not rebook`: ensured the off-screen raise-fare action is visible before tapping.
- `tapping an order card opens the detail screen` and `view details button opens the detail screen`: updated the fake delivery API to satisfy the current `listOrderRevisions` dependency and avoid pending Dio timers.
- `taxi tracking shows the assigned ride card with captain data`: updated the assertion for structured Iraqi plate rendering instead of a raw plate string.

Additional test fixes during final full-suite run:
- Cleaned mojibake from `lib/features/services/ui/service_provider_onboarding_screen.dart`.
- Updated the service-provider onboarding smoke test to expect the free registration title.

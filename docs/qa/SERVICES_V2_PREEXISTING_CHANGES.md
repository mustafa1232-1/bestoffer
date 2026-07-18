# Services V2 Preexisting Changes

This file inventories the dirty worktree before Services V2 Phase 1 starts. It is a stabilization snapshot only.

- Base SHA: 7eb2da1dbfdc33ddd4616e7289f6e11586023056
- Current branch: feat/services-booking-v2-production-closure
- Backup branch: backup/pre-services-v2-production-closure
- Classification hash: 65c4055b106af5c0dc82a2735b5bf8b6a143967229b139e7b75b405ece48a2b1
- Service-related preexisting files: 25
- Unrelated preexisting files: 120
- Baseline documents: 3

## Classification Rules

- `SERVICE_PREEXISTING`: files already modified before Services V2 that touch the service booking surface or its immediate tests/docs.
- `UNRELATED_PREEXISTING`: all other preexisting modifications, including taxi, social, coupons, build artifacts, and other workstreams.
- `BASELINE_NEW`: the three new Services V2 baseline documents only.

## SERVICE_PREEXISTING

| path | status | service-related | +lines | -lines | secrets | decision | note |
|---|---|---|---:|---:|---|---|---|
| backend/sql/148_service_categories_seed_expansion.sql | ?? | Yes | 15 | 0 | No | REVIEW_BEFORE_V2 | - |
| backend/sql/149_service_categories_seed_coverage.sql | ?? | Yes | 25 | 0 | No | REVIEW_BEFORE_V2 | - |
| backend/sql/150_service_categories_seed_subcategories.sql | ?? | Yes | 141 | 0 | No | REVIEW_BEFORE_V2 | - |
| backend/sql/151_service_offering_moderation_changes_requested.sql | ?? | Yes | 5 | 0 | No | REVIEW_BEFORE_V2 | - |
| backend/src/modules/services/services.constants.js | M | Yes | 1 | 0 | No | REVIEW_BEFORE_V2 | - |
| backend/src/modules/services/services.controller.js | M | Yes | 18 | 1 | No | REVIEW_BEFORE_V2 | - |
| backend/src/modules/services/services.repo.js | M | Yes | 224 | 37 | No | REVIEW_BEFORE_V2 | - |
| backend/src/modules/services/services.routes.js | M | Yes | 1 | 0 | No | REVIEW_BEFORE_V2 | - |
| backend/src/modules/services/services.service.js | M | Yes | 123 | 4 | No | REVIEW_BEFORE_V2 | - |
| backend/src/modules/services/services.validators.js | M | Yes | 15 | 0 | No | REVIEW_BEFORE_V2 | - |
| backend/src/tests/services.categories.test.js | ?? | Yes | 76 | 0 | No | REVIEW_BEFORE_V2 | - |
| lib/features/admin/ui/admin_service_provider_subscription_requests_screen.dart | M | Yes | 82 | 0 | No | REVIEW_BEFORE_V2 | - |
| lib/features/admin/ui/admin_services_hub_screen.dart | M | Yes | 175 | 36 | No | REVIEW_BEFORE_V2 | - |
| lib/features/services/data/services_api.dart | M | Yes | 21 | 6 | No | REVIEW_BEFORE_V2 | - |
| lib/features/services/models/service_models.dart | M | Yes | 35 | 25 | No | REVIEW_BEFORE_V2 | - |
| lib/features/services/state/service_provider_workspace_controller.dart | M | Yes | 39 | 1 | No | REVIEW_BEFORE_V2 | - |
| lib/features/services/ui/service_offering_details_screen.dart | M | Yes | 67 | 16 | No | REVIEW_BEFORE_V2 | - |
| lib/features/services/ui/service_provider_onboarding_screen.dart | M | Yes | 170 | 4 | No | REVIEW_BEFORE_V2 | - |
| lib/features/services/ui/service_provider_profile_screen.dart | M | Yes | 73 | 11 | No | REVIEW_BEFORE_V2 | - |
| lib/features/services/ui/service_provider_workspace_screen.dart | M | Yes | 942 | 340 | No | REVIEW_BEFORE_V2 | - |
| lib/features/services/ui/services_marketplace_screen.dart | M | Yes | 140 | 37 | No | REVIEW_BEFORE_V2 | - |
| test/features/admin/admin_services_hub_screen_test.dart | ?? | Yes | 163 | 0 | No | REVIEW_BEFORE_V2 | - |
| test/features/services/service_provider_workspace_employee_permissions_test.dart | M | Yes | 457 | 56 | No | REVIEW_BEFORE_V2 | - |
| test/services/service_provider_onboarding_categories_test.dart | ?? | Yes | 146 | 0 | No | REVIEW_BEFORE_V2 | - |
| test/services/services_ui_smoke_test.dart | M | Yes | 1 | 1 | No | REVIEW_BEFORE_V2 | - |

## UNRELATED_PREEXISTING

| path | status | service-related | +lines | -lines | secrets | decision | note |
|---|---|---|---:|---:|---|---|---|
| backend/sql/147_social_post_story_style.sql | ?? | No | 4 | 0 | No | PRESERVE_UNTOUCHED | - |
| backend/sql/154_taxi_price_raise_round.sql | ?? | No | 107 | 0 | No | PRESERVE_UNTOUCHED | - |
| backend/src/config/db.js | M | No | 154 | 2 | No | PRESERVE_UNTOUCHED | - |
| backend/src/modules/auth/auth.service.js | M | No | 5 | 1 | No | PRESERVE_UNTOUCHED | - |
| backend/src/modules/commerce/commerce.repo.js | M | No | 41 | 23 | No | PRESERVE_UNTOUCHED | - |
| backend/src/modules/company/company.repo.js | M | No | 6 | 1 | No | PRESERVE_UNTOUCHED | - |
| backend/src/modules/coupons/coupons.repo.js | M | No | 236 | 87 | No | PRESERVE_UNTOUCHED | - |
| backend/src/modules/coupons/coupons.service.js | M | No | 32 | 7 | No | PRESERVE_UNTOUCHED | - |
| backend/src/modules/feed/feed.product.mappers.js | M | No | 4 | 0 | No | PRESERVE_UNTOUCHED | - |
| backend/src/modules/feed/feed.repo.js | M | No | 10 | 1 | No | PRESERVE_UNTOUCHED | - |
| backend/src/modules/feed/feed.service.js | M | No | 17 | 12 | No | PRESERVE_UNTOUCHED | - |
| backend/src/modules/feed/feed.validators.js | M | No | 5 | 0 | No | PRESERVE_UNTOUCHED | - |
| backend/src/modules/taxi/taxi.controller.js | M | No | 21 | 0 | No | PRESERVE_UNTOUCHED | - |
| backend/src/modules/taxi/taxi.mappers.js | M | No | 16 | 1 | No | PRESERVE_UNTOUCHED | - |
| backend/src/modules/taxi/taxi.repo.js | M | No | 153 | 20 | No | PRESERVE_UNTOUCHED | - |
| backend/src/modules/taxi/taxi.routes.js | M | No | 1 | 0 | No | PRESERVE_UNTOUCHED | - |
| backend/src/modules/taxi/taxi.service.js | M | No | 94 | 9 | No | PRESERVE_UNTOUCHED | - |
| backend/src/modules/taxi/taxi.validators.js | M | No | 32 | 8 | No | PRESERVE_UNTOUCHED | - |
| backend/src/scripts/taxiE2ECheck.js | M | No | 17 | 14 | No | PRESERVE_UNTOUCHED | - |
| backend/src/scripts/taxiSmokeApiCheck.js | M | No | 3 | 3 | No | PRESERVE_UNTOUCHED | - |
| backend/src/shared/middleware/access-auth.js | M | No | 12 | 3 | No | PRESERVE_UNTOUCHED | - |
| backend/src/shared/realtime/realtime-sanitizer.js | M | No | 12 | 0 | No | PRESERVE_UNTOUCHED | - |
| backend/src/shared/utils/app-surface.js | M | No | 7 | 0 | No | PRESERVE_UNTOUCHED | - |
| backend/src/tests/app-surface.test.js | M | No | 22 | 15 | No | PRESERVE_UNTOUCHED | - |
| backend/src/tests/coupons.scope.test.js | M | No | 119 | 1 | No | PRESERVE_UNTOUCHED | - |
| backend/src/tests/coupons.validate.db.test.js | ?? | No | 99 | 0 | No | PRESERVE_UNTOUCHED | - |
| backend/src/tests/feed.phase3b.test.js | M | No | 25 | 0 | No | PRESERVE_UNTOUCHED | - |
| backend/src/tests/feed.story-interactions.test.js | M | No | 87 | 0 | No | PRESERVE_UNTOUCHED | - |
| backend/src/tests/notifications.end-to-end.test.js | M | No | 73 | 1 | No | PRESERVE_UNTOUCHED | - |
| backend/src/tests/taxi.hardening.test.js | M | No | 14 | 1 | No | PRESERVE_UNTOUCHED | - |
| backend/src/tests/taxi.negotiation.test.js | M | No | 5 | 5 | No | PRESERVE_UNTOUCHED | - |
| docs/qa/STORE_PRODUCTION_CLOSURE_BASELINE.md | ?? | No | 68 | 0 | No | PRESERVE_UNTOUCHED | - |
| lib/app_delivery_bootstrap.dart | M | No | 8 | 0 | No | PRESERVE_UNTOUCHED | - |
| lib/app_user_bootstrap.dart | M | No | 6 | 6 | No | PRESERVE_UNTOUCHED | - |
| lib/core/notifications/notification_navigation.dart | M | No | 52 | 15 | No | PRESERVE_UNTOUCHED | - |
| lib/core/notifications/notification_type_registry.dart | M | No | 26 | 0 | No | PRESERVE_UNTOUCHED | - |
| lib/core/widgets/image_picker_field.dart | M | No | 12 | 3 | No | PRESERVE_UNTOUCHED | - |
| lib/features/admin/data/admin_api.dart | M | No | 44 | 2 | No | PRESERVE_UNTOUCHED | - |
| lib/features/admin/state/admin_controller.dart | M | No | 76 | 19 | No | PRESERVE_UNTOUCHED | - |
| lib/features/admin/ui/admin_approvals_hub_screen.dart | M | No | 93 | 0 | No | PRESERVE_UNTOUCHED | - |
| lib/features/admin/ui/admin_dashboard_screen.dart | M | No | 102 | 22 | No | PRESERVE_UNTOUCHED | - |
| lib/features/admin/ui/admin_delivery_approvals_screen.dart | M | No | 81 | 0 | No | PRESERVE_UNTOUCHED | - |
| lib/features/admin/ui/admin_merchant_approvals_screen.dart | M | No | 83 | 0 | No | PRESERVE_UNTOUCHED | - |
| lib/features/admin/ui/admin_receivables_screen.dart | M | No | 109 | 24 | No | PRESERVE_UNTOUCHED | - |
| lib/features/admin/ui/admin_taxi_captain_requests_screen.dart | M | No | 90 | 16 | No | PRESERVE_UNTOUCHED | - |
| lib/features/admin/ui/admin_taxi_cash_payments_screen.dart | M | No | 87 | 9 | No | PRESERVE_UNTOUCHED | - |
| lib/features/auth/presentation/login_screen.dart | M | No | 5 | 1 | No | PRESERVE_UNTOUCHED | - |
| lib/features/auth/state/auth_controller.dart | M | No | 4 | 2 | No | PRESERVE_UNTOUCHED | - |
| lib/features/company/models/company_models.dart | M | No | 22 | 0 | No | PRESERVE_UNTOUCHED | - |
| lib/features/company/ui/company_promotions_screen.dart | M | No | 86 | 12 | No | PRESERVE_UNTOUCHED | - |
| lib/features/coupons/ui/coupon_management_screen.dart | M | No | 90 | 26 | No | PRESERVE_UNTOUCHED | - |
| lib/features/customer/ui/customer_global_product_search_screen.dart | M | No | 26 | 0 | No | PRESERVE_UNTOUCHED | - |
| lib/features/delivery/state/delivery_controller.dart | M | No | 35 | 3 | No | PRESERVE_UNTOUCHED | - |
| lib/features/merchants/ui/merchant_product_details_screen.dart | M | No | 49 | 59 | No | PRESERVE_UNTOUCHED | - |
| lib/features/merchants/ui/merchant_products_screen.dart | M | No | 56 | 10 | No | PRESERVE_UNTOUCHED | - |
| lib/features/notifications/state/notifications_controller.dart | M | No | 56 | 11 | No | PRESERVE_UNTOUCHED | - |
| lib/features/orders/data/orders_api.dart | M | No | 5 | 1 | No | PRESERVE_UNTOUCHED | - |
| lib/features/orders/ui/cart_screen.dart | M | No | 4 | 1 | No | PRESERVE_UNTOUCHED | - |
| lib/features/orders/ui/product_reviews_sheet.dart | M | No | 10 | 6 | No | PRESERVE_UNTOUCHED | - |
| lib/features/owner/ui/owner_product_form_sheet.dart | M | No | 11 | 4 | No | PRESERVE_UNTOUCHED | - |
| lib/features/products/ui/product_summary_card.dart | M | No | 168 | 20 | No | PRESERVE_UNTOUCHED | - |
| lib/features/products/ui/product_variant_picker_sheet.dart | M | No | 49 | 5 | No | PRESERVE_UNTOUCHED | - |
| lib/features/products/utils/product_variant_label_set.dart | ?? | No | 46 | 0 | No | PRESERVE_UNTOUCHED | - |
| lib/features/social/ui/social_chat_thread_screen.dart | M | No | 81 | 24 | No | PRESERVE_UNTOUCHED | - |
| lib/features/social/ui/social_chat_threads_screen.dart | M | No | 3 | 0 | No | PRESERVE_UNTOUCHED | - |
| lib/features/social/ui/social_profile_screen.dart | M | No | 3 | 0 | No | PRESERVE_UNTOUCHED | - |
| lib/features/social/ui/social_share_sheet.dart | M | No | 24 | 3 | No | PRESERVE_UNTOUCHED | - |
| lib/features/social/ui/social_user_search_screen.dart | M | No | 3 | 0 | No | PRESERVE_UNTOUCHED | - |
| lib/features/social_v3/composer/reel_composer_state.dart | M | No | 3 | 0 | No | PRESERVE_UNTOUCHED | - |
| lib/features/social_v3/composer/reel_composer_v3.dart | M | No | 549 | 100 | No | PRESERVE_UNTOUCHED | - |
| lib/features/social_v3/composer/story_composer_v3.dart | M | No | 218 | 28 | No | PRESERVE_UNTOUCHED | - |
| lib/features/social_v3/pickers/social_media_picker_v3.dart | M | No | 42 | 4 | No | PRESERVE_UNTOUCHED | - |
| lib/features/social_v3/state/social_reels_v3_connector.dart | M | No | 1 | 12 | No | PRESERVE_UNTOUCHED | - |
| lib/features/social_v3/upload/reel_upload_api_impl.dart | M | No | 4 | 0 | No | PRESERVE_UNTOUCHED | - |
| lib/features/taxi/data/taxi_api.dart | M | No | 15 | 4 | No | PRESERVE_UNTOUCHED | - |
| lib/features/taxi/ui/taxi_captain_competitions_screen.dart | ?? | No | 9 | 0 | No | PRESERVE_UNTOUCHED | - |
| lib/features/taxi/ui/taxi_captain_dashboard_screen.dart | M | No | 60 | 8 | No | PRESERVE_UNTOUCHED | - |
| lib/features/taxi/ui/taxi_captain_loyalty_screen.dart | M | No | 25 | 14 | No | PRESERVE_UNTOUCHED | - |
| lib/features/taxi/ui/taxi_captain_notifications_screen.dart | ?? | No | 9 | 0 | No | PRESERVE_UNTOUCHED | - |
| lib/features/taxi/ui/taxi_pages.dart | M | No | 21 | 2 | No | PRESERVE_UNTOUCHED | - |
| lib/features/tracking/tracking_map_utils.dart | M | No | 1 | 0 | No | PRESERVE_UNTOUCHED | - |
| packages/social_core/lib/src/models/social_models.dart | M | No | 404 | 436 | No | PRESERVE_UNTOUCHED | - |
| packages/social_core/lib/src/models/social_story_document.dart | M | No | 50 | 27 | No | PRESERVE_UNTOUCHED | - |
| pubspec.yaml | M | No | 1 | 1 | No | PRESERVE_UNTOUCHED | - |
| release_uploads/captain_aab_v10/maslaki-captain-release-v10.aab | ?? | No | binary | binary | No | PRESERVE_UNTOUCHED | binary/untracked artifact |
| release_uploads/store_aab_20260718/maslaki-captain-release.aab | ?? | No | binary | binary | No | PRESERVE_UNTOUCHED | binary/untracked artifact |
| release_uploads/store_aab_20260718/maslaki-delivery-release.aab | ?? | No | binary | binary | No | PRESERVE_UNTOUCHED | binary/untracked artifact |
| release_uploads/store_aab_20260718/maslaki-store-release.aab | ?? | No | binary | binary | No | PRESERVE_UNTOUCHED | binary/untracked artifact |
| release_uploads/store_aab_20260718/maslaki-user-release.aab | ?? | No | binary | binary | No | PRESERVE_UNTOUCHED | binary/untracked artifact |
| release_uploads/user_aab_v10/maslaki-user-release-v10.aab | ?? | No | binary | binary | No | PRESERVE_UNTOUCHED | binary/untracked artifact |
| test/admin/super_admin_drawer_navigation_test.dart | M | No | 79 | 0 | No | PRESERVE_UNTOUCHED | - |
| test/auth/login_screen_service_provider_test.dart | ?? | No | 94 | 0 | No | PRESERVE_UNTOUCHED | - |
| test/company/company_promotions_screen_test.dart | ?? | No | 68 | 0 | No | PRESERVE_UNTOUCHED | - |
| test/core/app_user_bootstrap_entry_test.dart | M | No | 136 | 3 | No | PRESERVE_UNTOUCHED | - |
| test/core/customer_main_market_screen_test.dart | M | No | 1 | 1 | No | PRESERVE_UNTOUCHED | - |
| test/core/map_page_test.dart | M | No | 17 | 12 | No | PRESERVE_UNTOUCHED | - |
| test/core/notifications/notification_routing_test.dart | M | No | 62 | 15 | No | PRESERVE_UNTOUCHED | - |
| test/core/taxi_pages_wrappers_test.dart | M | No | 6 | 0 | No | PRESERVE_UNTOUCHED | - |
| test/coupons/coupon_management_screen_test.dart | M | No | 80 | 3 | No | PRESERVE_UNTOUCHED | - |
| test/features/delivery/courier_orders_filter_test.dart | M | No | 4 | 1 | No | PRESERVE_UNTOUCHED | - |
| test/features/delivery/delivery_presence_sync_test.dart | M | No | 51 | 0 | No | PRESERVE_UNTOUCHED | - |
| test/features/merchants/merchant_product_details_screen_variant_test.dart | ?? | No | 209 | 0 | No | PRESERVE_UNTOUCHED | - |
| test/features/owner/ui/store_owner_orders_screen_test.dart | M | No | 51 | 0 | No | PRESERVE_UNTOUCHED | - |
| test/features/social_v3/live_create_routes_test.dart | M | No | 13 | 0 | No | PRESERVE_UNTOUCHED | - |
| test/features/social_v3/reel_composer_controller_test.dart | M | No | 22 | 0 | No | PRESERVE_UNTOUCHED | - |
| test/features/social_v3/reel_composer_v3_test.dart | ?? | No | 119 | 0 | No | PRESERVE_UNTOUCHED | - |
| test/features/social_v3/reel_publish_integration_test.dart | M | No | 11 | 0 | No | PRESERVE_UNTOUCHED | - |
| test/features/social_v3/share_sheet_v3_test.dart | M | No | 1 | 0 | No | PRESERVE_UNTOUCHED | - |
| test/features/taxi/taxi_captain_dashboard_screen_test.dart | M | No | 114 | 2 | No | PRESERVE_UNTOUCHED | - |
| test/products/product_summary_card_test.dart | M | No | 95 | 0 | No | PRESERVE_UNTOUCHED | - |
| test/social/social_chat_thread_policy_test.dart | ?? | No | 74 | 0 | No | PRESERVE_UNTOUCHED | - |
| test/social/social_story_document_test.dart | M | No | 65 | 0 | No | PRESERVE_UNTOUCHED | - |
| third_party/jni/android/.cxx/Debug/h1y6g501/arm64-v8a/configure_fingerprint.bin | M | No | 12 | 12 | No | PRESERVE_UNTOUCHED | - |
| third_party/jni/android/.cxx/Debug/h1y6g501/armeabi-v7a/configure_fingerprint.bin | M | No | 12 | 12 | No | PRESERVE_UNTOUCHED | - |
| third_party/jni/android/.cxx/Debug/h1y6g501/x86/configure_fingerprint.bin | M | No | 12 | 12 | No | PRESERVE_UNTOUCHED | - |
| third_party/jni/android/.cxx/Debug/h1y6g501/x86_64/configure_fingerprint.bin | M | No | 12 | 12 | No | PRESERVE_UNTOUCHED | - |
| third_party/jni/android/.cxx/RelWithDebInfo/2q3k6f4v/arm64-v8a/configure_fingerprint.bin | M | No | 12 | 12 | No | PRESERVE_UNTOUCHED | - |
| third_party/jni/android/.cxx/RelWithDebInfo/2q3k6f4v/armeabi-v7a/configure_fingerprint.bin | M | No | 12 | 12 | No | PRESERVE_UNTOUCHED | - |
| third_party/jni/android/.cxx/RelWithDebInfo/2q3k6f4v/x86/configure_fingerprint.bin | M | No | 12 | 12 | No | PRESERVE_UNTOUCHED | - |
| third_party/jni/android/.cxx/RelWithDebInfo/2q3k6f4v/x86_64/configure_fingerprint.bin | M | No | 12 | 12 | No | PRESERVE_UNTOUCHED | - |

## BASELINE_NEW

| path | status | service-related | +lines | -lines | secrets | decision | note |
|---|---|---|---:|---:|---|---|---|
| docs/qa/SERVICES_V2_BASELINE.md | ?? | No | 366 | 0 | No | BASELINE_DOCUMENT | - |
| docs/qa/SERVICES_V2_PREEXISTING_CHANGES.md | ?? | No | 340 | 0 | No | BASELINE_DOCUMENT | - |
| docs/qa/SERVICES_V2_PREEXISTING_DIFF_SUMMARY.txt | ?? | No | 388 | 0 | No | BASELINE_DOCUMENT | - |

## Service Baseline Themes

- Backend service module changes are concentrated in `backend/src/modules/services/*` and preserve the existing quote/request/admin moderation model.
- Flutter service closure changes are concentrated in `lib/features/services/*` and the related onboarding/workspace/profile/request flows.
- The current service surface still models provider registration, quote creation, request negotiation, service moderation, saved items, and reviews.
- The preexisting tree also contains broader taxi, social, coupons, and admin changes that must remain untouched while Services V2 is not yet started.

## Full Inventory Snapshot

BASELINE_NEW	docs/qa/SERVICES_V2_BASELINE.md	??	366	0	No	No	BASELINE_DOCUMENT
BASELINE_NEW	docs/qa/SERVICES_V2_PREEXISTING_CHANGES.md	??	340	0	No	No	BASELINE_DOCUMENT
BASELINE_NEW	docs/qa/SERVICES_V2_PREEXISTING_DIFF_SUMMARY.txt	??	388	0	No	No	BASELINE_DOCUMENT
SERVICE_PREEXISTING	backend/sql/148_service_categories_seed_expansion.sql	??	15	0	Yes	No	REVIEW_BEFORE_V2
SERVICE_PREEXISTING	backend/sql/149_service_categories_seed_coverage.sql	??	25	0	Yes	No	REVIEW_BEFORE_V2
SERVICE_PREEXISTING	backend/sql/150_service_categories_seed_subcategories.sql	??	141	0	Yes	No	REVIEW_BEFORE_V2
SERVICE_PREEXISTING	backend/sql/151_service_offering_moderation_changes_requested.sql	??	5	0	Yes	No	REVIEW_BEFORE_V2
SERVICE_PREEXISTING	backend/src/modules/services/services.constants.js	M	1	0	Yes	No	REVIEW_BEFORE_V2
SERVICE_PREEXISTING	backend/src/modules/services/services.controller.js	M	18	1	Yes	No	REVIEW_BEFORE_V2
SERVICE_PREEXISTING	backend/src/modules/services/services.repo.js	M	224	37	Yes	No	REVIEW_BEFORE_V2
SERVICE_PREEXISTING	backend/src/modules/services/services.routes.js	M	1	0	Yes	No	REVIEW_BEFORE_V2
SERVICE_PREEXISTING	backend/src/modules/services/services.service.js	M	123	4	Yes	No	REVIEW_BEFORE_V2
SERVICE_PREEXISTING	backend/src/modules/services/services.validators.js	M	15	0	Yes	No	REVIEW_BEFORE_V2
SERVICE_PREEXISTING	backend/src/tests/services.categories.test.js	??	76	0	Yes	No	REVIEW_BEFORE_V2
SERVICE_PREEXISTING	lib/features/admin/ui/admin_service_provider_subscription_requests_screen.dart	M	82	0	Yes	No	REVIEW_BEFORE_V2
SERVICE_PREEXISTING	lib/features/admin/ui/admin_services_hub_screen.dart	M	175	36	Yes	No	REVIEW_BEFORE_V2
SERVICE_PREEXISTING	lib/features/services/data/services_api.dart	M	21	6	Yes	No	REVIEW_BEFORE_V2
SERVICE_PREEXISTING	lib/features/services/models/service_models.dart	M	35	25	Yes	No	REVIEW_BEFORE_V2
SERVICE_PREEXISTING	lib/features/services/state/service_provider_workspace_controller.dart	M	39	1	Yes	No	REVIEW_BEFORE_V2
SERVICE_PREEXISTING	lib/features/services/ui/service_offering_details_screen.dart	M	67	16	Yes	No	REVIEW_BEFORE_V2
SERVICE_PREEXISTING	lib/features/services/ui/service_provider_onboarding_screen.dart	M	170	4	Yes	No	REVIEW_BEFORE_V2
SERVICE_PREEXISTING	lib/features/services/ui/service_provider_profile_screen.dart	M	73	11	Yes	No	REVIEW_BEFORE_V2
SERVICE_PREEXISTING	lib/features/services/ui/service_provider_workspace_screen.dart	M	942	340	Yes	No	REVIEW_BEFORE_V2
SERVICE_PREEXISTING	lib/features/services/ui/services_marketplace_screen.dart	M	140	37	Yes	No	REVIEW_BEFORE_V2
SERVICE_PREEXISTING	test/features/admin/admin_services_hub_screen_test.dart	??	163	0	Yes	No	REVIEW_BEFORE_V2
SERVICE_PREEXISTING	test/features/services/service_provider_workspace_employee_permissions_test.dart	M	457	56	Yes	No	REVIEW_BEFORE_V2
SERVICE_PREEXISTING	test/services/service_provider_onboarding_categories_test.dart	??	146	0	Yes	No	REVIEW_BEFORE_V2
SERVICE_PREEXISTING	test/services/services_ui_smoke_test.dart	M	1	1	Yes	No	REVIEW_BEFORE_V2
UNRELATED_PREEXISTING	backend/sql/147_social_post_story_style.sql	??	4	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	backend/sql/154_taxi_price_raise_round.sql	??	107	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	backend/src/config/db.js	M	154	2	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	backend/src/modules/auth/auth.service.js	M	5	1	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	backend/src/modules/commerce/commerce.repo.js	M	41	23	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	backend/src/modules/company/company.repo.js	M	6	1	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	backend/src/modules/coupons/coupons.repo.js	M	236	87	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	backend/src/modules/coupons/coupons.service.js	M	32	7	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	backend/src/modules/feed/feed.product.mappers.js	M	4	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	backend/src/modules/feed/feed.repo.js	M	10	1	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	backend/src/modules/feed/feed.service.js	M	17	12	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	backend/src/modules/feed/feed.validators.js	M	5	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	backend/src/modules/taxi/taxi.controller.js	M	21	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	backend/src/modules/taxi/taxi.mappers.js	M	16	1	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	backend/src/modules/taxi/taxi.repo.js	M	153	20	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	backend/src/modules/taxi/taxi.routes.js	M	1	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	backend/src/modules/taxi/taxi.service.js	M	94	9	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	backend/src/modules/taxi/taxi.validators.js	M	32	8	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	backend/src/scripts/taxiE2ECheck.js	M	17	14	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	backend/src/scripts/taxiSmokeApiCheck.js	M	3	3	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	backend/src/shared/middleware/access-auth.js	M	12	3	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	backend/src/shared/realtime/realtime-sanitizer.js	M	12	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	backend/src/shared/utils/app-surface.js	M	7	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	backend/src/tests/app-surface.test.js	M	22	15	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	backend/src/tests/coupons.scope.test.js	M	119	1	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	backend/src/tests/coupons.validate.db.test.js	??	99	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	backend/src/tests/feed.phase3b.test.js	M	25	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	backend/src/tests/feed.story-interactions.test.js	M	87	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	backend/src/tests/notifications.end-to-end.test.js	M	73	1	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	backend/src/tests/taxi.hardening.test.js	M	14	1	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	backend/src/tests/taxi.negotiation.test.js	M	5	5	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	docs/qa/STORE_PRODUCTION_CLOSURE_BASELINE.md	??	68	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/app_delivery_bootstrap.dart	M	8	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/app_user_bootstrap.dart	M	6	6	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/core/notifications/notification_navigation.dart	M	52	15	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/core/notifications/notification_type_registry.dart	M	26	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/core/widgets/image_picker_field.dart	M	12	3	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/admin/data/admin_api.dart	M	44	2	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/admin/state/admin_controller.dart	M	76	19	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/admin/ui/admin_approvals_hub_screen.dart	M	93	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/admin/ui/admin_dashboard_screen.dart	M	102	22	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/admin/ui/admin_delivery_approvals_screen.dart	M	81	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/admin/ui/admin_merchant_approvals_screen.dart	M	83	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/admin/ui/admin_receivables_screen.dart	M	109	24	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/admin/ui/admin_taxi_captain_requests_screen.dart	M	90	16	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/admin/ui/admin_taxi_cash_payments_screen.dart	M	87	9	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/auth/presentation/login_screen.dart	M	5	1	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/auth/state/auth_controller.dart	M	4	2	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/company/models/company_models.dart	M	22	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/company/ui/company_promotions_screen.dart	M	86	12	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/coupons/ui/coupon_management_screen.dart	M	90	26	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/customer/ui/customer_global_product_search_screen.dart	M	26	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/delivery/state/delivery_controller.dart	M	35	3	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/merchants/ui/merchant_product_details_screen.dart	M	49	59	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/merchants/ui/merchant_products_screen.dart	M	56	10	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/notifications/state/notifications_controller.dart	M	56	11	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/orders/data/orders_api.dart	M	5	1	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/orders/ui/cart_screen.dart	M	4	1	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/orders/ui/product_reviews_sheet.dart	M	10	6	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/owner/ui/owner_product_form_sheet.dart	M	11	4	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/products/ui/product_summary_card.dart	M	168	20	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/products/ui/product_variant_picker_sheet.dart	M	49	5	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/products/utils/product_variant_label_set.dart	??	46	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/social/ui/social_chat_thread_screen.dart	M	81	24	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/social/ui/social_chat_threads_screen.dart	M	3	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/social/ui/social_profile_screen.dart	M	3	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/social/ui/social_share_sheet.dart	M	24	3	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/social/ui/social_user_search_screen.dart	M	3	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/social_v3/composer/reel_composer_state.dart	M	3	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/social_v3/composer/reel_composer_v3.dart	M	549	100	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/social_v3/composer/story_composer_v3.dart	M	218	28	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/social_v3/pickers/social_media_picker_v3.dart	M	42	4	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/social_v3/state/social_reels_v3_connector.dart	M	1	12	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/social_v3/upload/reel_upload_api_impl.dart	M	4	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/taxi/data/taxi_api.dart	M	15	4	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/taxi/ui/taxi_captain_competitions_screen.dart	??	9	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/taxi/ui/taxi_captain_dashboard_screen.dart	M	60	8	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/taxi/ui/taxi_captain_loyalty_screen.dart	M	25	14	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/taxi/ui/taxi_captain_notifications_screen.dart	??	9	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/taxi/ui/taxi_pages.dart	M	21	2	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	lib/features/tracking/tracking_map_utils.dart	M	1	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	packages/social_core/lib/src/models/social_models.dart	M	404	436	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	packages/social_core/lib/src/models/social_story_document.dart	M	50	27	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	pubspec.yaml	M	1	1	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	release_uploads/captain_aab_v10/maslaki-captain-release-v10.aab	??	binary	binary	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	release_uploads/store_aab_20260718/maslaki-captain-release.aab	??	binary	binary	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	release_uploads/store_aab_20260718/maslaki-delivery-release.aab	??	binary	binary	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	release_uploads/store_aab_20260718/maslaki-store-release.aab	??	binary	binary	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	release_uploads/store_aab_20260718/maslaki-user-release.aab	??	binary	binary	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	release_uploads/user_aab_v10/maslaki-user-release-v10.aab	??	binary	binary	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	test/admin/super_admin_drawer_navigation_test.dart	M	79	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	test/auth/login_screen_service_provider_test.dart	??	94	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	test/company/company_promotions_screen_test.dart	??	68	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	test/core/app_user_bootstrap_entry_test.dart	M	136	3	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	test/core/customer_main_market_screen_test.dart	M	1	1	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	test/core/map_page_test.dart	M	17	12	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	test/core/notifications/notification_routing_test.dart	M	62	15	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	test/core/taxi_pages_wrappers_test.dart	M	6	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	test/coupons/coupon_management_screen_test.dart	M	80	3	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	test/features/delivery/courier_orders_filter_test.dart	M	4	1	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	test/features/delivery/delivery_presence_sync_test.dart	M	51	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	test/features/merchants/merchant_product_details_screen_variant_test.dart	??	209	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	test/features/owner/ui/store_owner_orders_screen_test.dart	M	51	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	test/features/social_v3/live_create_routes_test.dart	M	13	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	test/features/social_v3/reel_composer_controller_test.dart	M	22	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	test/features/social_v3/reel_composer_v3_test.dart	??	119	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	test/features/social_v3/reel_publish_integration_test.dart	M	11	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	test/features/social_v3/share_sheet_v3_test.dart	M	1	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	test/features/taxi/taxi_captain_dashboard_screen_test.dart	M	114	2	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	test/products/product_summary_card_test.dart	M	95	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	test/social/social_chat_thread_policy_test.dart	??	74	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	test/social/social_story_document_test.dart	M	65	0	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	third_party/jni/android/.cxx/Debug/h1y6g501/arm64-v8a/configure_fingerprint.bin	M	12	12	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	third_party/jni/android/.cxx/Debug/h1y6g501/armeabi-v7a/configure_fingerprint.bin	M	12	12	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	third_party/jni/android/.cxx/Debug/h1y6g501/x86/configure_fingerprint.bin	M	12	12	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	third_party/jni/android/.cxx/Debug/h1y6g501/x86_64/configure_fingerprint.bin	M	12	12	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	third_party/jni/android/.cxx/RelWithDebInfo/2q3k6f4v/arm64-v8a/configure_fingerprint.bin	M	12	12	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	third_party/jni/android/.cxx/RelWithDebInfo/2q3k6f4v/armeabi-v7a/configure_fingerprint.bin	M	12	12	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	third_party/jni/android/.cxx/RelWithDebInfo/2q3k6f4v/x86/configure_fingerprint.bin	M	12	12	No	No	PRESERVE_UNTOUCHED
UNRELATED_PREEXISTING	third_party/jni/android/.cxx/RelWithDebInfo/2q3k6f4v/x86_64/configure_fingerprint.bin	M	12	12	No	No	PRESERVE_UNTOUCHED

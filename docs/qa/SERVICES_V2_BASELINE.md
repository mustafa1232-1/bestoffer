# Services V2 Baseline

This document records the current service-system baseline before any Services V2 implementation work.

- Created at: 2026-07-18
- No Services V2 feature implementation has started.

## Repository State

- Current branch: feat/services-booking-v2-production-closure
- Baseline SHA: 7eb2da1dbfdc33ddd4616e7289f6e11586023056
- Backup branch: backup/pre-services-v2-production-closure
- Worktree status: dirty, with existing unrelated and related service changes already present
- Highest migration in the working tree: 154
- Migration file: backend/sql/154_taxi_price_raise_round.sql
- Migration 154 tracked state: untracked
- Do not reserve 155 for Services V2 until Phase 2 rechecks the branch and local tree.
- Existing uncommitted service-related files in the tree include:
  - backend/sql/147_social_post_story_style.sql
  - backend/sql/148_service_categories_seed_expansion.sql
  - backend/sql/149_service_categories_seed_coverage.sql
  - backend/sql/150_service_categories_seed_subcategories.sql
  - backend/sql/151_service_offering_moderation_changes_requested.sql
  - backend/src/tests/services.categories.test.js
  - test/services/service_provider_onboarding_categories_test.dart
  - test/services/services_ui_smoke_test.dart

## Verified Baseline Tests

- flutter analyze: PASS
- flutter test: PASS, 565 tests
- cd backend && npm test: PASS, 386 backend tests
- These are local baseline results only, not production E2E evidence.

## Current Service Backend Surface

### Public and Authenticated Discovery

- GET /api/services/public/categories
- GET /api/services/public/search
- GET /api/services/public/providers/:providerId
- GET /api/services/public/offerings/:offeringId
- GET /api/services/public/providers/:providerId/reviews
- GET /api/services/public/offerings/:offeringId/reviews
- POST /api/services/public/categories
- POST /api/services/public/providers/:providerId/save
- DELETE /api/services/public/providers/:providerId/save
- POST /api/services/public/offerings/:offeringId/save
- DELETE /api/services/public/offerings/:offeringId/save
- GET /api/services/public/saved/providers
- GET /api/services/public/saved/offerings
- GET /api/services/public/recent-views

### Provider Workspace and Requests

- POST /api/services/provider/register
- POST /api/services/provider/subscription/status
- POST /api/services/provider/subscription/requests/:requestId/respond-offer
- GET /api/services/provider/workspace
- GET /api/services/provider/employees
- POST /api/services/provider/employees/invite
- POST /api/services/provider/employees/upsert
- GET /api/services/provider/employees/activity-log
- GET /api/services/provider/profile
- PATCH /api/services/provider/profile
- POST /api/services/provider/offerings
- PATCH /api/services/provider/offerings/:offeringId
- PUT /api/services/provider/offerings/:offeringId/pricing
- POST /api/services/provider/promotions
- POST /api/services/provider/portfolio
- DELETE /api/services/provider/portfolio/:portfolioId
- POST /api/services/provider/category-suggestions
- GET /api/services/provider/category-suggestions
- GET /api/services/provider/requests
- POST /api/services/provider/requests/:requestId/quotes
- POST /api/services/provider/requests/:requestId/status

### Customer Requests

- POST /api/services/requests
- GET /api/services/requests/mine
- GET /api/services/requests/:requestId
- POST /api/services/requests/:requestId/status
- POST /api/services/requests/:requestId/quotes/:quoteId/respond

### Reviews

- GET /api/services/reviews/provider/:providerId
- GET /api/services/reviews/offering/:offeringId
- POST /api/services/reviews

### Admin Moderation

- GET /api/services/admin/subscription-requests
- POST /api/services/admin/subscription-requests/:requestId/offer
- POST /api/services/admin/subscription-requests/:requestId/reject
- POST /api/services/admin/subscription-requests/:requestId/confirm-cash-payment
- GET /api/services/admin/providers/pending
- PATCH /api/services/admin/providers/:providerId/status
- GET /api/services/admin/offerings/pending
- PATCH /api/services/admin/offerings/:offeringId/status
- GET /api/services/admin/categories/suggestions
- PATCH /api/services/admin/categories/suggestions/:suggestionId/review
- GET /api/services/admin/reports
- PATCH /api/services/admin/reports/:reportId/review
- GET /api/services/admin/requests
- GET /api/services/admin/stats
- GET /api/services/admin/settings
- PUT /api/services/admin/settings

## Current Service Domain States

### Pricing Models

- per_hour
- per_visit
- per_day
- per_device
- per_room
- per_meter
- per_item
- fixed_package
- starting_from
- inspection_required
- custom_quote

### Pricing Units

- hour
- visit
- day
- device
- room
- meter
- item
- package
- job
- custom

### Execution Modes

- home
- provider_location
- both
- remote

### Booking Policies

- instant
- approval_required

### Service Request Statuses

- pending
- awaiting_provider
- accepted
- scheduled
- in_progress
- completed
- cancelled
- rejected

### Provider Approval Statuses

- pending
- approved
- rejected
- suspended

### Offering Moderation Statuses

- pending
- approved
- rejected
- changes_requested
- hidden

### Category Suggestion Statuses

- pending
- approved
- rejected
- merged

### Quote Statuses

- pending_customer
- accepted
- rejected
- expired
- cancelled

### Provider Subscription Request Statuses

- pending_offer
- offer_sent
- offer_accepted
- offer_rejected
- payment_pending_confirmation
- payment_confirmed
- account_created
- cancelled
- rejected

### Provider Subscription Offer Statuses

- pending_provider
- accepted
- rejected
- superseded
- cancelled
- expired

## Current Service Database Tables

The current services module is backed by these tables:

- service_categories
- service_category_suggestions
- service_provider_profiles
- service_provider_areas
- service_provider_availability_rules
- service_provider_unavailable_slots
- service_offerings
- service_offering_media
- service_pricing_options
- service_promotions
- service_promotion_targets
- service_portfolio_items
- service_requests
- service_request_attachments
- service_request_quotes
- service_request_status_history
- service_reviews
- service_saved_providers
- service_saved_offerings
- service_recent_views
- service_reports
- service_module_settings
- service_provider_subscription_requests
- service_provider_subscription_offers
- service_provider_subscription_status_history
- service_provider_employee_profile

## Current Flutter Surfaces

### Screens and Workspace Surfaces

- lib/features/services/ui/services_marketplace_screen.dart
- lib/features/services/ui/service_offering_details_screen.dart
- lib/features/services/ui/service_provider_profile_screen.dart
- lib/features/services/ui/service_provider_onboarding_screen.dart
- lib/features/services/ui/service_provider_workspace_screen.dart
- lib/features/services/ui/service_my_requests_screen.dart
- lib/features/services/ui/service_request_create_screen.dart
- lib/features/services/ui/service_request_details_screen.dart

### State / API / Models

- lib/features/services/data/services_api.dart
- lib/features/services/models/service_models.dart
- lib/features/services/state/services_discovery_controller.dart
- lib/features/services/state/service_provider_workspace_controller.dart

## Current Flow Summary

### Discovery and Marketplace

- Public categories are loaded and filtered client-side.
- Service search currently queries offerings by category, subcategory, city, area, pricing model, pricing unit, and sort.
- Providers and offerings can be saved/unsaved and revisited from recent views.

### Provider Onboarding

- Provider registration currently uses:
  - full name
  - phone
  - PIN
  - business name
  - main category
  - city / area / address
  - execution mode flags
  - pricing mode
  - availability rules
  - optional logo / cover / profile image uploads
- The onboarding screen currently supports:
  - category search
  - add new category
  - parent category selection
  - submission of a provider subscription request

### Provider Workspace

- Provider workspace currently exposes:
  - profile summary
  - service requests
  - offering creation
  - pricing replacement
  - promotions
  - portfolio items
  - employee management
  - category suggestions
  - request status updates
  - quote creation
- The UI still uses a quote-based request lifecycle.

### Customer Request Lifecycle

- Request creation is currently tied to an offering.
- The current request lifecycle supports:
  - pending
  - awaiting provider
  - accepted
  - scheduled
  - in progress
  - completed
  - cancelled
  - rejected
- Customer request detail currently supports:
  - status updates
  - provider quote response
  - review submission after completion

## Known Baseline Gaps

- The current services flow still relies on provider/workspace quoting and request negotiation.
- There is no documented V2 direct-booking contract yet.
- There is no documented booking_version = 2 migration yet.
- The provider admin moderation experience is spread across provider requests, offerings, categories, reports, and settings.
- The services UI still needs a production closure pass for:
  - direct booking semantics
  - clearer provider onboarding outcome handling
  - unified service provider shell entry
  - stronger admin review visibility

## Current Test Coverage Observed

### Present and passing

- Category creation/listing baseline test
- Services marketplace smoke test
- Provider onboarding category search/add test
- Backend tests for:
  - service provider subscription workflow
  - public categories
  - service requests
  - quote lifecycle
  - reviews
  - admin moderation
  - employee permissions

### Missing or still incomplete

- No V2 direct-booking tests yet.
- No booking-version migration tests yet.
- No end-to-end baseline for:
  - provider direct booking
  - pricing-mode-specific request creation
  - admin offer/review loops for the new service closure model

## Notes

- This baseline intentionally reflects the current live code and existing dirty worktree.
- Do not treat this as a cleaned or frozen release state.
- This file is the phase-0 reference for the service closure effort.


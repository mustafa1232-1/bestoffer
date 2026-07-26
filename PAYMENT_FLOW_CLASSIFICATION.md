# Payment Flow Classification

## Category A - Provider Digital Account/Platform Activation

Removed or disabled for the current iOS release:

- Flutter provider onboarding: `lib/features/services/ui/service_provider_onboarding_screen.dart`
  - Removed provider offer acceptance/rejection controls.
  - Replaced subscription copy with free application review copy.
  - Status UI only shows submitted, under review, approved, rejected, or suspended.
- Flutter provider API: `lib/features/services/data/services_api.dart`
  - Uses `createProviderApplication`.
  - Uses `getProviderApplicationStatus`.
  - No provider offer-response client method remains for onboarding.
- Backend provider registration: `backend/src/modules/services/services.service.js`
  - `registerServiceProvider` now creates a free provider user/profile with pending review.
  - Admin subscription listing, rejection, offer, and cash-confirmation activation methods are disabled.
  - Provider workspace and provider permission operations require provider moderation approval.
  - Backend tests verify bogus payment flags in provider registration do not activate paid behavior, pending providers cannot access workspace, legacy payment endpoints return `SERVICE_PROVIDER_EXTERNAL_PAYMENT_DISABLED`, and admin approval unlocks workspace without payment.
- Backend routes:
  - `POST /api/services/provider/register`: free application creation.
  - `POST /api/services/provider/application/status`: free application status.
  - Legacy subscription/payment mutation routes return disabled errors.

Legacy payment workflow retained only for migration/history documentation:

- `backend/sql/115_service_provider_subscription_workflow.sql`
- `service_provider_subscription_requests`
- `service_provider_subscription_offers`
- `service_provider_subscription_status_history`

These must not be used to unlock current iOS provider access.

## Category B - Real-World Service or Operational Payments

Retained because they are not provider digital account activation:

- Service request pricing and quotes: `lib/features/services/ui/service_request_create_screen.dart`, `service_request_details_screen.dart`, `services_api.dart`
  - Payment concerns real-world work performed by the provider.
- Provider workspace offering prices: `service_provider_workspace_screen.dart`, `service_offering_details_screen.dart`
  - Pricing describes real-world services offered to customers.
- Customer orders, invoices, delivery fees, receivables, and merchant cash settlement screens.
  - Operational commerce/settlement for real goods, delivery, or services.
- Taxi ride fare, raise-fare, cancellation, and cash-payment flows.
  - Payment concerns transportation service outside the app.
- Merchant, real-estate, car, or paid-upgrade features.
  - Separate product areas. They were audited for wording but are not service-provider account activation.

## Wording Rule

Category B UI may mention price, fare, invoice, receipt, or cash only when it clearly relates to the actual real-world service, order, ride, delivery, merchant settlement, or invoice. It must not be described as a provider subscription, provider activation fee, account unlock, or digital platform membership.

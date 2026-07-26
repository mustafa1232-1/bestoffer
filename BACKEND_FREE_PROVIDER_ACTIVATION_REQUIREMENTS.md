# Backend Free Provider Activation Requirements

## Decision

For the current iOS release, service-provider registration and activation are free. No digital provider subscription is sold or activated through external payment.

## Affected Endpoints

- `POST /api/services/provider/register`
  - Current release behavior: creates or reuses a `service_provider` user and creates a `service_provider_profiles` row with `provider_approval_status = pending`.
  - Approval must be based only on identity, submitted data, service category, safety, policy, or content quality.
- `POST /api/services/provider/application/status`
  - Current release behavior: authenticates phone/PIN and returns a free provider application state.
- `POST /api/services/provider/subscription/status`
  - Legacy compatibility alias only. It must not return payment instructions.
- `POST /api/services/provider/subscription/requests/:requestId/respond-offer`
  - Disabled for this release with `SERVICE_PROVIDER_EXTERNAL_PAYMENT_DISABLED`.
- `GET /api/admin/services/subscription-requests`
  - Disabled for this release with `SERVICE_PROVIDER_EXTERNAL_PAYMENT_DISABLED`; admins must use pending providers moderation.
- `POST /api/admin/services/subscription-requests/:requestId/offer`
  - Disabled for this release with `SERVICE_PROVIDER_EXTERNAL_PAYMENT_DISABLED`.
- `POST /api/admin/services/subscription-requests/:requestId/reject`
  - Disabled for this release with `SERVICE_PROVIDER_EXTERNAL_PAYMENT_DISABLED`; admins must reject through provider moderation with a non-payment reason.
- `POST /api/admin/services/subscription-requests/:requestId/confirm-cash-payment`
  - Disabled for this release with `SERVICE_PROVIDER_EXTERNAL_PAYMENT_DISABLED`.
- `PATCH /api/admin/services/providers/:providerId/status`
  - Correct admin path for review decisions: `approved`, `rejected`, or `suspended`.

## Legacy Payment Fields

Legacy tables and fields still exist for migration/history and must not gate iOS provider access:

- `service_provider_subscription_requests.status`
- `selected_offer_id`
- `offered_amount`
- `offered_currency`
- `offered_title`
- `offered_description`
- `offered_valid_until`
- `offer_sent_at`
- `offer_accepted_at`
- `offer_rejected_at`
- `payment_confirmed_by_user_id`
- `payment_confirmed_at`
- `account_created_user_id`
- `service_provider_subscription_offers.amount`
- `service_provider_subscription_offers.currency`
- `service_provider_subscription_offers.status`

## Required Response State Machine

Provider-facing responses may only expose:

- `not_submitted`
- `draft`
- `submitted`
- `under_review`
- `approved`
- `rejected`
- `suspended`

Legacy payment statuses must be mapped to a neutral compatibility response and must not approve locally:

- `pending_offer`
- `offer_sent`
- `offer_accepted`
- `offer_rejected`
- `payment_pending_confirmation`
- `payment_confirmed`
- `account_created`
- `cancelled`

## Database/State Changes

- New iOS registration should write to `app_user` and `service_provider_profiles`, not create a paid subscription request.
- `provider_approval_status = pending` means under review, not awaiting payment.
- `provider_approval_status = approved` unlocks provider workspace access.
- `provider_approval_status = rejected` must include a non-payment reason when possible.
- `provider_approval_status = suspended` is only for policy, safety, fraud, or account reasons.

## Migration Considerations

- Legacy rows in `service_provider_subscription_requests` should be migrated or archived.
- Any active `offer_sent`, `offer_accepted`, `payment_pending_confirmation`, or `payment_confirmed` row must not block a free iOS registration.
- If a legacy row already created a `service_provider` user/profile, use the profile status as the source of truth.
- Admin dashboards should use `service_provider_profiles.provider_approval_status` for current review work.

## Acceptance Criteria

- A new provider can register without being quoted a fee.
- Registration does not require an admin offer, cash confirmation, receipt, invoice, bank transfer, or WhatsApp payment.
- The provider can check review status without seeing payment instructions.
- Admin approval through provider moderation unlocks provider access.
- Pending, rejected, or suspended providers cannot access the provider workspace or provider permission operations.
- Legacy provider payment endpoints cannot activate accounts in this release.
- Production review account validation passes without storing credentials in source control.

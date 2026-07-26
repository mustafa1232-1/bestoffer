# Product Decision

For the current iOS release, service-provider registration and activation are free. No digital provider subscription is sold or activated through external payment.

The business may add StoreKit subscriptions in a future version, but this release must not require, mention, imply, or depend on external payment for provider account activation or access to digital app functionality.

## Current Release Path

- Provider registration is a free application.
- Provider activation is based on administrative review of identity, submitted data, service category, safety, policy, or content quality.
- Administrative approval is not payment confirmation.
- Provider digital access is controlled by `service_provider_profiles.provider_approval_status`, not by payment fields.
- Real-world customer-to-provider payments may still exist for services performed outside the app.

## Future StoreKit Path

If paid provider digital subscriptions are added later, the implementation must use StoreKit and server-side App Store transaction verification before any iOS sale or activation dependency is enabled.

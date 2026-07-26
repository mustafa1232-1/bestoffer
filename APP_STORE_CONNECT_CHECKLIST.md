# App Store Connect Checklist

## Review Access

- Create or verify permanent production review accounts.
- Enter active review credentials in App Review notes:
  - Customer phone/PIN: `[CUSTOMER_REVIEW_PHONE]` / `[CUSTOMER_REVIEW_PIN]`
  - Provider phone/PIN: `[PROVIDER_REVIEW_PHONE]` / `[PROVIDER_REVIEW_PIN]`
- Confirm the customer account does not require OTP, SMS, payment, or location presence.
- Confirm the provider account is approved without payment and can access provider features.
- Add a reviewer contact who can respond during review.

## Provider Activation

- Confirm provider registration and activation are free in this iOS version.
- Do not attach provider subscription IAP products to this version.
- Confirm no App Review notes, screenshots, or metadata mention external payment for provider activation.
- Keep `BACKEND_IAP_REQUIREMENTS.md` only as a future StoreKit reference.

## Backend

- Confirm production backend uptime during review.
- Deploy the free provider activation backend behavior documented in `BACKEND_FREE_PROVIDER_ACTIVATION_REQUIREMENTS.md`.
- Confirm legacy provider offer/cash-confirmation endpoints cannot activate iOS provider access.
- Deploy the account deletion migration/workflow documented in `BACKEND_ACCOUNT_DELETION_REQUIREMENTS.md`.
- Run `cd backend && npm run verify:review-accounts` with production review credentials.
- Seed the production review account with complete customer and provider-visible data.

## App Metadata

- Add live HTTPS Privacy Policy and Support URLs.
- Verify App Privacy answers match data collection and permissions.
- Upload accurate screenshots that do not expose real user data.
- Describe significant changes in "What's New".
- Paste `APP_STORE_REVIEW_NOTES.md` into App Review notes and replace placeholders.
- Confirm selected build number and attached IAP products match the submission.

## Final QA

- Test through TestFlight on a clean iOS install.
- Test through TestFlight on a physical iOS device with production review accounts.
- Verify sign-in, invalid sign-in, guest mode, logout, expired session, poor/no network, provider registration, image upload, Arabic/English, RTL/LTR, returning from background, small iPhone, and iPad layouts.
- Verify in-app account deletion against production using a disposable review account.
- Inspect the submitted Release app bundle `Info.plist` and confirm `UIBackgroundModes` contains only justified modes.
- Run `tool/validate_ios_release.sh` on macOS and attach results to release QA notes.

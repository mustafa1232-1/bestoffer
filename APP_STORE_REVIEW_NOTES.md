# App Store Review Notes

Maslaki is a local marketplace that helps customers discover and contact providers of real-world services.

## Review Accounts

Customer phone: [CUSTOMER_REVIEW_PHONE]  
Customer PIN: [CUSTOMER_REVIEW_PIN]

Provider phone: [PROVIDER_REVIEW_PHONE]  
Provider PIN: [PROVIDER_REVIEW_PIN]

These credentials must be active on the production backend and must not require OTP, SMS verification, manual approval, location presence, or payment during review.

## Backend Availability

Production API: `https://bestoffer-production.up.railway.app`

Health checks:
- `https://bestoffer-production.up.railway.app/health`
- `https://bestoffer-production.up.railway.app/ready`

## Main Feature Paths

Sign in:
1. Launch the app.
2. Enter the review phone and PIN.
3. Tap **Sign In**.

Guest mode:
1. Launch the app.
2. Tap **Continue as Guest**.
3. Browse customer-visible marketplace, services, social, taxi, and discovery areas.
4. Protected actions prompt for sign-in instead of failing silently.

Customer flow:
1. Sign in with the customer review account.
2. Browse marketplace/services.
3. Open a provider, listing, store, product, or service request flow.
4. Any payment discussed between a customer and a provider is for a real-world local service performed outside the app.

Provider flow:
1. Sign in with the approved provider review account, or from the sign-in screen open **Create service-provider account**.
2. Fill the provider registration fields to submit a free application.
3. Pick optional logo/cover images only when needed.
4. Submit the request or use **Check status**.
5. Provider registration and digital account activation are free in this iOS version.

Account deletion:
1. Sign in with a review account that is safe to delete, or request a disposable deletion-review account from the developer contact.
2. Open Settings > Account security.
3. Tap **Delete Account Permanently**.
4. Confirm both deletion dialogs.
5. The app revokes the local session only after the production backend accepts deletion. The backend anonymizes personal account/profile data, revokes sessions and push tokens, hides public provider listings, and retains only legally or operationally required records.

## Payment Model

Maslaki connects customers with providers of real-world local services. Provider registration and digital provider account activation are free in this iOS version. The app does not require external payment to activate provider functionality.

Any payment discussed between customers and providers is for a real-world service performed outside the app. It is not an app subscription, digital feature purchase, or provider account activation fee.

## Background Modes

The iOS build keeps only `remote-notification` background mode. This is used for Firebase push notification delivery and app notification routing. Unnecessary `audio` and continuous `location` background modes were removed.

## Privacy and Permissions

The app requests camera/photo permissions only when media selection or capture is used. Location is requested as when-in-use for address, map, taxi, delivery, and nearby-service features while the app is in use.

## Reviewer Notes

Please use the credentials above against the production backend. Do not use test/staging endpoints. If the review account cannot sign in, contact the developer immediately because the app no longer displays internal request ids or backend diagnostics to end users.

Production review credentials must be verified before submission with `npm run verify:review-accounts` from the backend directory.

# Maslaki App Store Review Notes

Maslaki is a marketplace / mobility / community app. The app supports browsing, search, shopping, delivery, taxi, chat, social content, and merchant workspaces. The current iOS release surface is user-facing; the store/delivery/captain/company surfaces are not treated as the App Store submission target for this build.

## Review access

- Guest browsing is available for discovery screens where sign-in is not required.
- If a logged-in session is needed during review, use the staging/review credentials provisioned by the release manager.
- For local non-production QA, the backend seeds a development admin account by default:
  - phone: `07701234567`
  - PIN: `1234`
  - This seed is disabled in production.

## What to verify in review

1. Launch the app and confirm splash/login flow.
2. Browse merchants and products.
3. Open a product with colors/sizes and verify variant selection.
4. Add an item to the cart and submit an order.
5. Open support, privacy policy, and terms screens.
6. Test report/block/delete-own-content flows in social features if exposed in the build.
7. Verify account deletion is reachable from Settings → Account security → Delete my account.

## Privacy, tracking, and diagnostics

- The app does not use App Tracking Transparency or advertising SDKs.
- No cross-app / cross-website tracking is intended.
- Device fingerprints and push tokens are used for session security and delivery of app functionality.
- Diagnostics / crash reporting are used for service stability and support; if any crash data is shared with third-party providers, it is limited to operational support and error reporting.
- Analytics consent is explicit in the sign-up flow.

## UGC, moderation, and safety

- Social/community content can be reported.
- Users can block other users.
- Users can delete their own content.
- Admin moderation tools exist for review and enforcement when content is reported.
- Privacy policy, terms of use, and support links are exposed inside the app.

## iOS platform notes

- This repository currently has a single iOS bundle identity in the Runner target (`com.maslaki.user`).
- The iOS project includes user-oriented runtime wiring; additional iOS flavor wiring for non-user surfaces should be added before treating those surfaces as App Store-ready on iOS.
- `BGTaskScheduler` identifiers are not declared because no native task registration is implemented yet.
- Background modes should stay limited to the capabilities that are actually used by the app.

## Privacy manifest note

- No app-level `PrivacyInfo.xcprivacy` file is committed at the moment.
- Validate the native dependency manifests during the Mac/iOS build. If Xcode or App Store validation surfaces a missing manifest or required-reason API issue, add the minimal manifest before submission.

## Contact

- Support is available from the in-app support page and the hosted support URL shown in the app.

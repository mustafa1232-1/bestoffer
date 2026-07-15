# Social V3 Post-7a73125 Verification

Branch: `feat/social-v3-interactions-reviews-closure`
Base commit: `7a73125e4eb0253995dbe63535440f42af7a8823`

## What was verified from the closure baseline

- Social capabilities fail closed by default.
- Story audience-scope gate remains authoritative on the backend.
- The live story viewer path is the V3 full-screen flow.
- The social shared-entity contract is used by chat and community flows.
- Reel/story sharing already uses the canonical share sheet entry points.

## What was fixed in this iteration

- Added a stale-completion guard to `SocialCapabilitiesController` so an older async fetch cannot overwrite a newer fail-closed state after logout or account switch.
- Added authoritative per-story interaction settings to the backend story contract:
  - `allowLikes`
  - `allowPrivateReplies`
  - `allowComments`
  - `allowSharing`
  - `allowReshare`
- Persisted those settings on `social_story` and surfaced them in the Flutter `SocialStory` model.
- Expanded typed shared-content routing so story, profile, user, reel, review, and merchant-review attachments map to the correct destination.
- Enriched story shares so the share sheet receives a usable shared snapshot instead of only an entity id.

## Remaining release-gate work

- Runtime/device verification is still required for the broader Social V3 release-closure plan.
- The current iteration covered the contract and routing gaps above; it did not attempt a full media-pipeline migration.

## Files of interest

- `backend/src/modules/feed/feed.validators.js`
- `backend/src/modules/feed/feed.service.js`
- `backend/src/modules/feed/feed.repo.js`
- `packages/social_core/lib/src/models/social_models.dart`
- `lib/features/social/ui/social_content_navigation.dart`
- `lib/features/social/ui/social_share_sheet.dart`
- `lib/features/social/ui/social_story_quick_viewer.dart`
- `lib/features/social_v3/capabilities/social_capabilities_controller.dart`


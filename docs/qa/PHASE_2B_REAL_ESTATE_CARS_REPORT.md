# Phase 2B Real Estate and Cars Report

## Scope

- Real-estate marketplace runtime closure
- Cars marketplace runtime closure
- Backend notification routing and business chat thread targeting for listing contexts

## Verified Runtime Evidence

### Real Estate

- `backend/src/scripts/realEstateE2ECheck.js` passed on Railway.
- Seller and buyer registration succeeded with valid Basmaya addresses.
- Super admin approved the seller paid-upgrade request.
- Approved listing became visible to the buyer and seller workspace.
- Business thread creation passed through `/api/feed/chats/threads`.
- Thread messaging worked for the approved listing context.
- Notification targets stayed stable for `real_estate_workspace` and `admin_real_estate_pending`.
- Runtime identifiers observed: `requestId=31`, `listingId=29`, `threadId=22`.

### Cars

- `backend/src/scripts/carsE2ECheck.js` passed on Railway.
- Seller and buyer registration succeeded with valid Basmaya addresses.
- Super admin approved the seller paid-upgrade request.
- Approved listing became visible to the buyer and seller workspace.
- Business thread creation passed through `/api/feed/chats/threads`.
- Thread messaging worked for the approved listing context.
- Notification targets stayed stable for `paid_upgrades_home` and listing routing.
- Runtime identifiers observed: `requestId=32`, `listingId=1`, `threadId=23`.

## Verification

- `flutter analyze` passed.
- `flutter test` passed.
- `cd backend && npm test` passed.
- `cd backend && npm run verify:release:local` passed.
- `cd backend && railway run --service bestoffer npm run verify:release:runtime` passed.

## Notes

- These flows are runtime-only and are not device-gated.
- The implemented chat route for both marketplace flows uses `/api/feed/chats/threads`.
- The notification registry now resolves direct car and real-estate listing targets.


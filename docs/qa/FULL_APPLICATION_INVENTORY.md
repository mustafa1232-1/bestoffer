# Full Application Inventory

This file is the Phase 0 index for the closure program.

## Inventory Rules

- Use this file to map the platform at module level.
- Use `FULL_APPLICATION_AUDIT_MATRIX.md` for row-by-row proof and status.
- A row is only complete when it has evidence, not because the screen opens.
- Phase 0 seeds the structure; later phases expand the matrix into screen/button-level rows.

## In-Scope Apps

- User app
- Store/Merchant app
- Delivery/Courier app
- Taxi Captain app
- Company/Admin app
- Pharmacy app
- Shared Flutter core
- Backend APIs
- PostgreSQL database
- Realtime stack
- Push notifications

## Inventory Buckets

### Phase 1 priority

- Authentication and sessions
- Store creation and catalog visibility
- Fashion department separation
- Category and product visibility
- Cart and checkout
- Order lifecycle
- Taxi negotiation and session regressions

### Phase 2 priority

- Services
- Jobs
- Real estate
- Cars
- Pharmacy
- Company/admin reports

### Phase 3 priority

- Stories autoplay/progress
- Reel sharing
- Social discovery/profile/messaging

### Cross-cutting platform layers

- Notification routing and deep links
- Realtime event registry and deduplication
- Security and firewall
- Performance and load behavior
- Release artifacts and signing

## Evidence Sources

- Flutter widget and controller tests
- Backend unit, route, and runtime E2E checks
- Railway runtime verification
- Real-device QA
- Manual reproduction with logs


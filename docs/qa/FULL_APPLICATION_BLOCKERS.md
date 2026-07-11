# Full Application Blockers

This list starts as the authoritative working blocker set for the closure program.

## P0 Launch Blockers

| Priority | Blocker | P0 reproduction status | Repro / evidence | Notes |
|---|---|---|---|---|
| P0 | Second store creation returns only `فشل` | REPRODUCED | Owner register path can return `OWNER_ALREADY_HAS_MERCHANT`, and the shared Flutter mapper now translates it instead of falling back to a generic failure | Second-store restriction still needs a live owner-register smoke on the Store app |
| P0 | Men/women fashion leakage | NOT_YET_REPRODUCED | Backend department-scope tests exist and currently enforce men / women / unisex separation | Still needs live create/list/search proof on Store and User surfaces |
| P0 | Missing category visibility | NOT_YET_REPRODUCED | Category taxonomy tests exist and category cache invalidation is already wired | Needs deterministic create/list/search E2E |
| P0 | Missing product visibility | NOT_YET_REPRODUCED | Product catalog authoring tests exist and hidden-product reasons are represented | Needs deterministic create/list/search E2E |
| P0 | Merchant/admin coupon failure | PARTIALLY_REPRODUCED | Merchant/admin coupon scope tests exist; merchant and admin coupon surfaces are separated in the backend | Needs scoped coupon create/preview/checkout runtime proof |
| P0 | Order -> store -> delivery workflow gaps | PARTIALLY_REPRODUCED | Automated and runtime baseline coverage exists, but real-device proof still missing | Includes notifications and deep links |
| P0 | Taxi notification / negotiation regressions | PARTIALLY_REPRODUCED | Automated and runtime baseline coverage exists, but real-device push/background proof still missing | Two-captain negotiation remains the target baseline |
| P0 | Stale-token / push-token / session regressions | PARTIALLY_REPRODUCED | Runtime checks are green; device token lifecycle proof still missing | 401 vs 403 semantics must stay strict |

## P1+

| Priority | Blocker | Current status | Notes |
|---|---|---|---|
| P1 | Services coverage | NOT_STARTED | Audit after P0 closure |
| P1 | Jobs coverage | NOT_STARTED | Audit after P0 closure |
| P1 | Real estate coverage | NOT_STARTED | Audit after P0 closure |
| P1 | Cars coverage | NOT_STARTED | Audit after P0 closure |
| P1 | Pharmacy coverage | NOT_STARTED | Audit after P0 closure |
| P1 | Company/admin reports | NOT_STARTED | Audit after P0 closure |
| P2 | Stories autoplay/progress | NOT_STARTED | Audit later |
| P2 | Reel sharing | NOT_STARTED | Audit later |
| P2 | Social/discovery/profile/messaging | NOT_STARTED | Audit later |


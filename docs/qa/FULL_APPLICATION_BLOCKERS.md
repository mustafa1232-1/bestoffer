# Full Application Blockers

This list starts as the authoritative working blocker set for the closure program.

## P0 Launch Blockers

| Priority | Blocker | Current status | Repro / evidence | Notes |
|---|---|---|---|---|
| P0 | Second store creation returns only `فشل` | IN_PROGRESS | Needs deterministic create/list/update E2E | Must surface a structured Arabic error or confirm multi-store rules |
| P0 | Men/women fashion leakage | IN_PROGRESS | Needs backend query + UI verification | Backend must enforce department scope, not UI only |
| P0 | Missing category visibility | IN_PROGRESS | Needs create/list/search E2E | Category creation must appear immediately |
| P0 | Missing product visibility | IN_PROGRESS | Needs create/list/search E2E | Hidden products must explain the reason |
| P0 | Merchant/admin coupon failure | IN_PROGRESS | Needs scoped coupon E2E | Merchant and admin coupon scopes must be proven separately |
| P0 | Order -> store -> delivery workflow gaps | IN_PROGRESS | Needs end-to-end order lifecycle proof | Includes notifications and deep links |
| P0 | Taxi notification / negotiation regressions | IN_PROGRESS | Taxi runtime E2E and push checks | Two-captain negotiation already exists and remains the target baseline |
| P0 | Stale-token / push-token / session regressions | IN_PROGRESS | Auth/runtime checks | 401 vs 403 semantics must stay strict |

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


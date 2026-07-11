# Full Application Blockers

This list starts as the authoritative working blocker set for the closure program.

## P0 Launch Blockers

| Priority | Blocker | P0 reproduction status | Repro / evidence | Notes |
|---|---|---|---|---|
| P0 | Second store creation returns only `فشل` | PASS_RUNTIME | Owner register path can return `OWNER_ALREADY_HAS_MERCHANT`; the shared Flutter mapper translates it instead of falling back to a generic failure, and live duplicate-owner smoke now proves the backend surface | Store-app device smoke still pending |
| P0 | Men/women fashion leakage | PASS_RUNTIME | Department-aware browse cache keys now separate men / women / unisex results and live create/list/search smoke passed | Device proof still pending |
| P0 | Missing category visibility | PASS_RUNTIME | Category create/list/runtime smoke now shows immediate visibility on owner and public merchant surfaces | Device proof still pending |
| P0 | Missing product visibility | PASS_RUNTIME | Product create/list/runtime smoke now shows immediate visibility on owner and public merchant surfaces | Device proof still pending |
| P0 | Merchant/admin coupon failure | PASS_RUNTIME | Merchant/admin coupon runtime smoke now passes create/validate/preview/checkout with the correct scopes | Device proof still pending |
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

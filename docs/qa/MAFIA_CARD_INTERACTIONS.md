# Mafia Card Interactions

Date: 2026-10-08. Scope: the Maslaki Night room UI, not Knowledge Map or voice transport.

## Behavior

- Server-confirmed egg, rose and tea gifts travel from the sender's actual card to the recipient's card. Egg impact changes to a cracked egg/splat; rose has petals; tea has steam.
- Emotions appear over their sender. All effects ignore pointer input, expire after 2.8 seconds, and do not change seats, roles, voting, chat or microphone permissions.
- A shared RTL-aware geometry positions both seats and effects, including resize. First-row arcs stay inside the arena.
- All newly received interactions are consumed, not just the last snapshot item. IDs deduplicate command receipts and realtime/polling responses even when responses arrive out of order.
- Initial snapshots and resume history are silent. Old samples use the snapshot's server time, never the handset clock. Pausing/disposal cancels active effect timers.
- Work is bounded to 32 simultaneous effects and 512 remembered IDs. Each effect repaints independently. Art is bundled and decoded at bounded cache sizes, not downloaded for each gift.
- Reduced-motion mode shows a stationary recipient gift instead of flight, rotation or particles.
- The scene uses a Baghdad courtyard illustration; compact phase information leaves more room for players. Mission/profile content is retained below the arena and phase controls.

## Verification

- Focused Flutter suite: 29 passing (`mafia-interactions-tests.log`). Covers flight endpoints, egg impact, first-row clipping, RTL/resize, sender reactions, reduced motion, expiry/disposal, missing recipients, historical events, clock skew, out-of-order deduplication, authoritative receipt without an extra GET, plus existing room commands.
- Backend Mafia rules, flow and responsiveness: 26 passing (`mafia-interactions-backend.log`), using isolated local databases. No production fixtures were created.
- Browser harness uses real local HTTP commands and SSE updates. Captures flight/impact for egg, rose, tea and laugh; validates own gift HTTP 201, asset HTTP 200 and no browser errors. Viewports: 390x844, 320x740, 1200x900. See `mafia-interactions-browser.json` and `mafia-*-flight.png` / `mafia-*-impact.png`.
- Final full Flutter run: **888 passed, 1 skipped, 0 failed** (`mafia-interactions-full-flutter-final.log`). Full `flutter analyze`: **no issues** (`mafia-interactions-analyze.log`). Backend `flow:check`: **OK** (`mafia-interactions-flow.log`).
- The final local browser sample measured event visibility after 278 ms (egg), 219 ms (rose), 227 ms (tea), 205 ms (laugh). These are four local debug observations, not production/mobile latency guarantees.
- Read-only production `/health` and `/ready` both returned HTTP 200. This does not certify the un-deployed UI on production.

## Limits

- No version bump, Android build, migration or deployment performed for this change. No production backend logic changed; the backend addition is a loopback-only QA endpoint.
- Physical Android/iPhone performance, release GPU behavior and real LiveKit audio were not exercised by this visual task. The local fixture has voice disabled explicitly.
- Full backend `npm test` was not rerun here: this scoped change has no production backend edits. The previous broader run's unrelated delivery/outbox failures remain documented in `MAFIA_RESPONSIVENESS.md`.
- The first full Flutter run started before the final arc adjustment and failed the newly added arc regression test. Its log is preserved; both the focused rerun and the full fixed-source-tree rerun passed.

## Generated Art

Mode: built-in imagegen, new assets. Originals retained under the Codex generated-images directory. No external search assets or image-editing scripts were used. The atlas is consumed directly in Flutter by clipping its four quadrants.

- `assets/games/mafia/courtyard.png`: opaque scene, 3,544,906 bytes.
- `assets/games/mafia/gifts.png`: transparent 2x2 atlas, 1,448,642 bytes; top-left egg, top-right rose, bottom-left tea, bottom-right impact.

### Courtyard Prompt

undefined

### Gift Atlas Prompt

undefined

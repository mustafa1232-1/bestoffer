# Phase 3D Final Internal Testing Gate

## Purpose

This phase closes the last approval gate before Android Internal Testing:

- final permissions matrix
- real-device QA
- internal testing approval decision

## Verified Baseline

- Working branch: `closure/full-application-closure`
- Current HEAD in this turn: `884d4f6cd6af6394b22e83248399b7619db7f021`
- Working tree: clean before the Phase 3D runtime diagnostics in this turn

## Backend Parity

- Railway production service `bestoffer` is healthy.
- `GET /health` returned `200`.
- `GET /ready` returned `200`.
- The Railway CLI exposed deployment id `edc91328-bda4-454f-991b-1eee71653176`.
- The CLI did not expose a deployed commit hash for that active deployment, so none is asserted here.

## Permissions Matrix State

- The standalone permissions checker now has a matrix-aware entry point at `backend/src/scripts/rolePermissionCheckMatrix.js`.
- The QA bootstrap for controlled role fixtures is available at `backend/src/scripts/qaRoleMatrixBootstrap.js`.
- The matrix itself is still a runtime artifact, not a device proof.
- The phase does not claim a full matrix pass in this workspace because the required real-device approval gate is still blocked.

## Runtime Diagnostics

The earlier `verify:release:runtime` timeouts were caused by the overall wall-clock budget being too small for the full chain, not by a single script that failed to exit.

### Individual Stage Durations

| Stage | Duration | Exit |
|---|---:|---:|
| `realtime:runtime:check` | `44,890 ms` | `0` |
| `security:runtime:check` | `17,798 ms` | `0` |
| `auth:session:push:check` | `56,122 ms` | `0` |
| `e2e:new-streams:check` | `10,418 ms` | `0` |
| `e2e:order:check` | `82,176 ms` | `0` |
| `e2e:taxi:check` | `107,149 ms` | `0` |
| `e2e:community:check` | `66,782 ms` | `0` |
| `e2e:social:check` | `76,035 ms` | `0` |
| `e2e:stories:check` | `48,313 ms` | `0` |
| `e2e:reels:check` | `44,670 ms` | `0` |
| `e2e:services:check` | `54,159 ms` | `0` |
| `e2e:jobs:check` | `57,446 ms` | `0` |
| `e2e:real-estate:check` | `56,649 ms` | `0` |
| `e2e:cars:check` | `54,944 ms` | `0` |
| `e2e:pharmacy:check` | `42,820 ms` | `0` |

### Full Chain Result

- Command: `railway run --service bestoffer npm run verify:release:runtime`
- Total duration: `929,415 ms` (`15m 29s`)
- Exit code: `0`
- Result: `PASS`
- Note: `community` required one retry because the first attempt hit a transient backend/network failure. The retry succeeded and did not require a code change.

## Real Device State

- `flutter devices` only exposed Windows desktop, Chrome, and Edge in this workspace.
- No controllable Android device is connected.
- Therefore foreground/background/killed push, notification cold-start routing, and live device churn remain blocked.

## Decision

- Status: `BLOCKED`
- Internal testing approval: `NOT READY`
- Reason: no physical Android device session available to complete the required QA gate.

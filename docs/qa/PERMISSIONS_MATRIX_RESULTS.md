# Permissions Matrix Results

## Scope

This matrix documents the role/surface gating evidence used by the Phase 3D approval gate.

## Matrix Tools

- Bootstrap: `backend/src/scripts/qaRoleMatrixBootstrap.js`
- Checker: `backend/src/scripts/rolePermissionCheckMatrix.js`

## Result Summary

| Role group | App surface | Login path | Backend evidence | Device evidence | Current verdict |
|---|---|---|---|---|---|
| Super admin | User | `/api/auth/login` | Phase 1C auth/session/push runtime proof | Real device still blocked | `PASS_RUNTIME` |
| Customer | User | `/api/auth/login` | Phase 1C auth/session runtime proof | Real device still blocked | `PASS_RUNTIME` |
| Store owner | Store | `/api/owner/register` + `/api/auth/login` | Phase 1A / 1B catalog and order runtime proof | Store device smoke still blocked | `PASS_RUNTIME` |
| Delivery courier | Delivery | `/api/admin/users` + `/api/admin/delivery/:id/approve` + `/api/auth/login` | Phase 1B / 1C runtime proof | Delivery device smoke still blocked | `PASS_RUNTIME` |
| Taxi captain | Taxi | `/api/taxi/captain/register` + `/api/auth/login` | Phase 1D taxi negotiation runtime proof | Taxi device smoke still blocked | `PASS_RUNTIME` |
| Company portal | Company | `/api/company/auth/login` | Phase 2D company/admin runtime proof | Company device QA not required in this gate | `PASS_RUNTIME` |
| Service provider | User | `/api/services/provider/register` + `/api/auth/login` | Phase 2A services runtime proof | Not part of this gate | `PASS_RUNTIME` |

## Notes

- The matrix-aware checker is now present so the standalone permissions gate is no longer blocked by a missing script reference.
- This document does not claim internal testing readiness.
- The final approval remains blocked because no physical Android device is available in this workspace.


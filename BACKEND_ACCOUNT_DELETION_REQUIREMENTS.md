# Backend Account Deletion Implementation

## Current Status

The Flutter app exposes account deletion in Settings > Account security > Delete Account Permanently. The flow requires two confirmations, calls `DELETE /api/users/me`, handles backend failures without logging the user out, and clears local credentials only after the backend accepts deletion.

The backend now performs immediate deletion/anonymization in a transaction and records the deletion state on `app_user`. The endpoint is available at both:

- `DELETE /api/users/me`
- `DELETE /api/account`

## Architecture

- Route requires an authenticated, session-bound access token.
- Super-admin self-deletion is blocked with `SUPER_ADMIN_SELF_DELETE_FORBIDDEN`.
- Repository work is transactional and idempotent.
- `app_user` stores deletion timestamps/status and retention policy version.
- Active sessions are revoked and push tokens are invalidated/anonymized.
- Public/provider visibility is removed during the same transaction.

## Data Deleted or Anonymized

- `app_user`: phone is replaced with `deleted_<userId>`, PIN hash is randomized, personal name/address/work/profile/social fields are removed or neutralized, and account is disabled.
- `user_session`: active sessions are revoked with `account_deleted`.
- `user_push_token`: tokens are deactivated and replaced with non-deliverable `deleted:<id>` markers.
- `service_provider_profiles`: provider profile is disabled/suspended, public business/contact/search/media fields are cleared, and public listing access stops.
- `service_offerings`: offerings are disabled/hidden and removed from search.
- Role/profile tables: service employee, taxi captain, courier, merchant employee, delivery agent, and company-user links are disabled where present.

## Data Retained

Operational records that may be required for accounting, disputes, fraud prevention, safety, or tax/legal retention are retained but no longer expose the deleted account as an active public identity. Examples include order, invoice, ride, delivery, moderation, audit, and historical transaction rows.

## Acceptance Criteria

- Normal users can initiate deletion in-app.
- The user must pass two permanent-action confirmations.
- Backend records completion and anonymizes/deactivates user-owned personal/public data.
- Local session is cleared only after backend success.
- Backend failures keep the user signed in and show an error.
- Deleted users cannot log in with their old phone/PIN.
- Other sessions and push tokens are revoked.
- Public provider profiles are hidden after deletion.

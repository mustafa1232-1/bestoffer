# Unified Identity and Design System

## Identity
- Same backend auth/JWT/session for Android/iOS/Web/Windows.
- API authorization enforced in backend (`/ops` protected).
- UI visibility is not the security boundary.

## Permissions
- `ai_dev_support_access`
- `ai_dev_support_view_incidents`
- `ai_dev_support_approve_action`
- `ai_dev_support_reject_action`
- `ai_dev_support_request_code_fix`
- `ai_dev_support_create_github_issue`
- `ai_dev_support_manage_settings`
- `ai_dev_support_view_audit_logs`

## Design system
- Added central tokens/files under `lib/core/theme`:
  - `app_colors.dart`
  - `app_text_styles.dart`
  - `app_spacing.dart`
  - `app_radius.dart`
- AI DEV SUPPORT uses unified theme direction.

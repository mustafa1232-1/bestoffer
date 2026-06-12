# Observability Guide

## Backend
- Sentry (optional runtime if DSN exists)
- Datadog tracing/log metrics (optional runtime if key exists)
- Request ID correlation
- `/health`, `/ready`, `/version`

## Flutter
- `sentry_flutter` initialization via `SENTRY_DSN`
- Breadcrumbs for auth/navigation/notification events

## Privacy
- Redaction before AI analysis and before storing webhook payloads

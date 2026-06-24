# Troubleshooting Guide

## Startup or early crash
Check:
- `apps/app_user/lib/main.dart`
- the relevant runtime package under `packages/app_*_runtime`
- `AuthController.bootstrap`
- startup logs and Flutter zone errors

Common causes:
- corrupted stored session
- crash during notification bootstrap
- invalid locale or app settings bootstrap

## Login or register fails
Check:
- Flutter auth controller and runtime login screen
- backend auth routes and service
- stored token/session state

Look for:
- `INVALID_TOKEN`
- `PHONE_EXISTS`
- `VALIDATION_ERROR`

## Orders fail or stay stuck
Check:
- runtime order list and detail flow
- backend orders service and repository
- order creation transaction and stock checks

## Notifications do not update
Check:
- notification controller
- runtime notification hub
- backend notifications service
- realtime or polling fallback

## Company portal issues
Check:
- `packages/app_company_runtime`
- bootstrap response memberships
- selected company context
- role mapping in auth response

## Taxi ride issues
Check:
- `packages/app_user_runtime`
- `packages/app_taxi_captain_runtime`
- backend taxi routes and service
- ride status transitions and bids

## Upload or media failures
Check:
- `backend/src/shared/utils/upload.js`
- `/health` and `/ready`
- Cloudflare R2 configuration

## Current shipping entrypoints
- `lib/main.dart`
- `lib/main_store.dart`
- `apps/app_delivery/lib/main.dart`
- `apps/app_taxi_captain/lib/main.dart`
- `apps/app_company/lib/main.dart`

The old standalone store harness has been retired; use `lib/main_store.dart`.

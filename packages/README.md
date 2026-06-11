# Shared Packages Structure

This monorepo now includes two package groups:

## 1) App runtime bootstrap packages
- `app_user_runtime`
- `app_store_runtime`
- `app_delivery_runtime`
- `app_taxi_captain_runtime`
- `app_company_runtime`

These packages isolate split app wrappers from direct `apps/* -> bestoffer` imports.

## 2) Core/shared packages
- `core_auth`
- `core_networking`
- `core_localization`
- `core_design_system`
- `core_notifications`
- `core_realtime`
- `core_storage`
- `core_maps`
- `core_analytics`
- `shared_models`
- `core_utils`

Current state:
- Runtime extraction is in progress.
- Core package names are materialized and ready for incremental code moves.
- Root package `bestoffer` remains a transitional implementation source until feature code is migrated into `packages/*`.

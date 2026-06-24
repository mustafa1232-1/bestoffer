# App Split And Structure Guide

## Current Operating Model
- The repository uses root entrypoints for the user and store surfaces, plus
  split service apps under `apps/*`.
- Each surface boots through its runtime package:
  - `lib/main.dart` -> user app
  - `lib/main_store.dart` -> `app_store_runtime`
  - `apps/app_delivery` -> `app_delivery_runtime`
  - `apps/app_taxi_captain` -> `app_taxi_captain_runtime`
  - `apps/app_company` -> `app_company_runtime`
- Shared design primitives are served from `packages/core_design_system`.

## Scope Ownership
- `app_user`: consumer flows (home, stores, pharmacy customer flow, taxi rider, social/reels, profile/settings).
- `lib/main_store.dart`: owner/store operations.
- `app_delivery`: courier flow only.
- `app_taxi_captain`: captain flow only.
- `app_company`: company/admin operations only.

## Boundaries (Enforced)
- `apps/*` cannot import `package:bestoffer/*` directly.
- Legacy shell packages (`app_*_shell`) are removed.
- Cross-runtime imports are blocked by boundary checks.
- Boundary guard: `scripts/check_import_boundaries.ps1`.

## Shipping Note
- `lib/main.dart` and `lib/main_store.dart` are the user/store shipping entrypoints.
- Split service apps under `apps/*` remain the shipping entrypoints for delivery,
  taxi captain, and company.
- New feature work must land in runtime packages and shared `core_*` packages,
  not in duplicate app harnesses.

## Design System Source Of Truth
- Primary theme exports:
  - `packages/core_design_system/lib/src/theme_preset.dart`
  - `packages/core_design_system/lib/src/app_theme.dart`
  - `packages/core_design_system/lib/src/app_backdrop.dart`
  - `packages/core_design_system/lib/src/app_responsive_shell.dart`
- Root theme files re-export from `core_design_system` to avoid duplicated logic.

## Required Gates Before Release
1. `powershell -ExecutionPolicy Bypass -File .\\scripts\\check_import_boundaries.ps1`
2. `powershell -ExecutionPolicy Bypass -File .\\scripts\\check_localization_terms.ps1`
3. Root:
   - `flutter analyze`
   - `flutter test`
4. Each remaining app in `apps/*`:
   - `flutter analyze`
   - `flutter test`

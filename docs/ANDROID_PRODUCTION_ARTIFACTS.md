# Android Production Release Artifacts

- Updated at: 2026-04-08 16:40:00

## Current testing artifacts
- The verified current artifacts are clean `profile + arm64` APKs rebuilt after `flutter clean`.
- They are the correct baseline for direct device testing while release signing remains external.

| App | Package ID | Build | APK Path | APK Size (MB) |
| --- | --- | --- | --- | ---: |
| app_user | `com.maslaki.user` | PASS | `apps/app_user/build/app/outputs/flutter-apk/app-profile.apk` | 22.54 |
| app_store | `com.maslaki.store` | PASS | `apps/app_store/build/app/outputs/flutter-apk/app-profile.apk` | 22.54 |
| app_delivery | `com.maslaki.delivery` | PASS | `apps/app_delivery/build/app/outputs/flutter-apk/app-profile.apk` | 22.54 |
| app_taxi_captain | `com.maslaki.captain` | PASS | `apps/app_taxi_captain/build/app/outputs/flutter-apk/app-profile.apk` | 22.54 |
| app_company | `com.maslaki.company` | PASS | `apps/app_company/build/app/outputs/flutter-apk/app-profile.apk` | 22.54 |

## Historical signed release artifacts
- Previously generated signed release APK/AAB files still exist on disk but were produced before the latest clean split verification.
- Keep them only as archive evidence until fresh signed release artifacts are regenerated from the current clean state.

## Notes
- Release signing is still controlled by external keystore configuration.
- For production handoff, regenerate signed AABs from the current clean state after attaching the correct keystore.

# Real Device QA Results

This file is intentionally strict.

## Rule

- If a flow has not been executed on a real controllable device, it must remain blocked.
- Emulator results do not satisfy killed-app push, camera/location, or real notification tap validation.

## Manual Checklist

| Flow | Required artifact | Status | Notes |
|---|---|---|---|
| Push while foreground | signed APK | BLOCKED: REAL_DEVICE_REQUIRED | Needs a real device session |
| Push while background | signed APK | BLOCKED: REAL_DEVICE_REQUIRED | Needs a real device session |
| Push while app killed | signed APK | BLOCKED: REAL_DEVICE_REQUIRED | Needs a real device session |
| Notification tap cold start | signed APK | BLOCKED: REAL_DEVICE_REQUIRED | Needs a real device session |
| Location permissions | signed APK | BLOCKED: REAL_DEVICE_REQUIRED | Needs a real device session |
| Taxi live location | signed APK | BLOCKED: REAL_DEVICE_REQUIRED | Needs a real device session |
| Story/video playback | signed APK | BLOCKED: REAL_DEVICE_REQUIRED | Needs a real device session |
| Media uploads | signed APK | BLOCKED: REAL_DEVICE_REQUIRED | Needs a real device session |
| Keyboard-safe bottom sheets | signed APK | BLOCKED: REAL_DEVICE_REQUIRED | Needs a real device session |
| Store order notifications | signed APK | BLOCKED: REAL_DEVICE_REQUIRED | Needs a real device session |
| Delivery notifications | signed APK | BLOCKED: REAL_DEVICE_REQUIRED | Needs a real device session |
| Captain notifications | signed APK | BLOCKED: REAL_DEVICE_REQUIRED | Needs a real device session |

## Current APK Paths For Manual QA

- User: `build/app/outputs/flutter-apk/app-user-release.apk`
- Store: `build/app/outputs/flutter-apk/app-store-release.apk`
- Delivery: `build/app/outputs/flutter-apk/app-delivery-release.apk`
- Captain: `build/app/outputs/flutter-apk/app-captain-release.apk`

## Notes

- Company/admin does not currently have a verified release APK in this snapshot.
- Pharmacy currently has a release APK present, but it is outside the minimum device-QA set requested for this phase.
- Phase 1C runtime verification is complete, but push/background/killed-app, notification tap cold start, and live device session churn are still `BLOCKED: REAL_DEVICE_REQUIRED` until the signed APKs are executed on a controllable device.

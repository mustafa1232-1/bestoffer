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

- User: `qa_artifacts/phase_1e_android_apks/user/app-user-release.apk`
- Store: `qa_artifacts/phase_1e_android_apks/store/app-store-release.apk`
- Delivery: `qa_artifacts/phase_1e_android_apks/delivery/app-delivery-release.apk`
- Captain: `qa_artifacts/phase_1e_android_apks/captain/app-captain-release.apk`

## Notes

- Company/admin does not currently have a verified release APK in this snapshot.
- Pharmacy currently has a release APK present, but it is outside the minimum device-QA set requested for this phase.
- Phase 1C runtime verification is complete, Phase 1D taxi runtime verification is complete, and the current Phase 1E APKs have been rebuilt from HEAD `4034661545ea66366a6bc741b3327d13b4767b0d`, but push/background/killed-app, notification tap cold start, and live device session churn are still `BLOCKED: REAL_DEVICE_REQUIRED` until the signed APKs are executed on a controllable device.

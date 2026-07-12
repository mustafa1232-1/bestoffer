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
| Company/Admin exports and print/share | signed APK | BLOCKED: REAL_DEVICE_REQUIRED | Needs a real device session |
| Company/Admin notification tap cold start | signed APK | BLOCKED: REAL_DEVICE_REQUIRED | Needs a real device session |

## Current APK Paths For Manual QA

- User: `qa_artifacts/phase_3c_android_rc/user/app-user-release.apk`
- Store: `qa_artifacts/phase_3c_android_rc/store/app-store-release.apk`
- Delivery: `qa_artifacts/phase_3c_android_rc/delivery/app-delivery-release.apk`
- Captain: `qa_artifacts/phase_3c_android_rc/captain/app-captain-release.apk`

## Notes

- Company/admin and pharmacy also have RC artifacts in `qa_artifacts/phase_3c_android_rc/`, but the minimum device-QA set remains user / store / delivery / captain.
- Phase 1C runtime verification is complete, Phase 1D taxi runtime verification is complete, and the current Phase 3C RC APKs were rebuilt from HEAD `6db2be2dee1d2260f0dfcd0f751efcfabad411fc`, but push/background/killed-app, notification tap cold start, and live device session churn are still `BLOCKED: REAL_DEVICE_REQUIRED` until the signed APKs are executed on a controllable device.

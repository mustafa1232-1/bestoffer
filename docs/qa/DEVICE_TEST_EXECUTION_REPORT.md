# Device Test Execution Report

## Device Inventory

Observed via `flutter devices` in this workspace:

- Windows desktop
- Chrome
- Edge

No Android device is attached.

## Required Manual Flows

| Flow | Artifact | Status | Evidence |
|---|---|---|---|
| Push while foreground | signed APK | `BLOCKED: REAL_DEVICE_REQUIRED` | No Android device session available |
| Push while background | signed APK | `BLOCKED: REAL_DEVICE_REQUIRED` | No Android device session available |
| Push while app killed | signed APK | `BLOCKED: REAL_DEVICE_REQUIRED` | No Android device session available |
| Notification tap cold start | signed APK | `BLOCKED: REAL_DEVICE_REQUIRED` | No Android device session available |
| Location permissions | signed APK | `BLOCKED: REAL_DEVICE_REQUIRED` | No Android device session available |
| Taxi live location | signed APK | `BLOCKED: REAL_DEVICE_REQUIRED` | No Android device session available |
| Story/video playback | signed APK | `BLOCKED: REAL_DEVICE_REQUIRED` | No Android device session available |
| Media uploads | signed APK | `BLOCKED: REAL_DEVICE_REQUIRED` | No Android device session available |
| Keyboard-safe bottom sheets | signed APK | `BLOCKED: REAL_DEVICE_REQUIRED` | No Android device session available |
| Store order notifications | signed APK | `BLOCKED: REAL_DEVICE_REQUIRED` | No Android device session available |
| Delivery notifications | signed APK | `BLOCKED: REAL_DEVICE_REQUIRED` | No Android device session available |
| Captain notifications | signed APK | `BLOCKED: REAL_DEVICE_REQUIRED` | No Android device session available |
| Company/Admin exports and print/share | signed APK | `BLOCKED: REAL_DEVICE_REQUIRED` | No Android device session available |
| Company/Admin notification tap cold start | signed APK | `BLOCKED: REAL_DEVICE_REQUIRED` | No Android device session available |

## Conclusion

- Real-device QA did not execute in this workspace.
- Emulator/desktop/browser results are not sufficient for the approval gate.
- Internal testing approval remains blocked.


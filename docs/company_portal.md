# Company Portal

Company Portal is a standalone product that sits above the existing store model.
It is not mounted inside the user app or the store app.

## Entry points
- User app: `lib/main.dart`
- Store app: `lib/main_store.dart`
- Company app: `apps/app_company/lib/main.dart`

## Shared backend boundaries
The three apps share the same backend ecosystem and database, but Company Portal uses its own APIs and auth gate under `/api/company`.

## Company product scope
Company Portal is for HQ and supervisory roles:
- company owner
- company manager
- finance viewer
- operations viewer

It is used for:
- company dashboard
- branch oversight
- branch requests
- product copy between branches
- company coupons and campaigns
- inventory oversight
- company users and permissions

It does not handle daily order operations for stores.

## Admin ownership
Companies are created and linked by the admin side through `/api/company/admin/...`.
Company accounts are not customer accounts and not store operator accounts.

## Build commands
### Run locally
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run_company_app.ps1
```
This runs the split app from `apps/app_company`.

### Android
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build_company_android.ps1
```
Artifacts are copied into `build/company/android`.
Use `run_company_app.ps1` for local debug sessions on a device or emulator.

### Web
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build_company_web.ps1
```
Artifacts are copied into `build/company/web`.

### Web preview deploy
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\deploy_company_web_preview.ps1
```
This creates a preview deployment for `build/company/web` and prints:
- preview URL
- claim URL

### Windows
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build_company_windows.ps1
```
Artifacts are copied into `build/company/windows`.

## Android package separation
The Android build script defaults Company Portal to:
- application id: `com.maslaki.company`
- label: `Company Portal`

If `google-services.json` does not contain a matching Firebase client for the selected `APP_ID`, the Google Services plugin is skipped so the build can still succeed.
This keeps Company Portal buildable before a dedicated Firebase package is provisioned.

## Deployment intent
- Web should be published on a dedicated company host or subdomain.
- Windows should be distributed as a separate office desktop build.
- Android should be distributed as a separate APK/AAB from the user and store apps.

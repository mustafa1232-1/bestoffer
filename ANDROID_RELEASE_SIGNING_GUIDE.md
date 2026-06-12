# ANDROID_RELEASE_SIGNING_GUIDE

## Goal
Unified release signing flow for all split apps under `apps/*` using one upload key policy.

## Supported Inputs

The Android Gradle setup in each app supports:
- `key.properties` file
- environment variables

Used vars:
- `ANDROID_KEYSTORE_PATH`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

CI helper var:
- `ANDROID_KEYSTORE_BASE64` (decoded to a temporary `.jks`, then exported as `ANDROID_KEYSTORE_PATH`).

## 1) Generate Upload Keystore (Local)

PowerShell:
```powershell
./scripts/android/generate-upload-keystore.ps1 -OutFile "keys/maslaki-upload.jks" -Alias "upload"
```

Bash:
```bash
./scripts/android/generate-upload-keystore.sh keys/maslaki-upload.jks upload
```

## 2) Create key.properties

Root app:
- Copy `android/key.properties.example` -> `android/key.properties`

Each split app:
- Copy `apps/<app>/android/key.properties.example` -> `apps/<app>/android/key.properties`

Template values:
```properties
storePassword=CHANGE_ME
keyPassword=CHANGE_ME
keyAlias=upload
storeFile=../../../keys/maslaki-upload.jks
```

For root app example path:
```properties
storeFile=../../keys/maslaki-upload.jks
```

## 3) Build Commands

Per split app:
```powershell
cd apps/app_user
flutter build appbundle --release
```

Repeat for:
- `app_store`
- `app_delivery`
- `app_taxi_captain`
- `app_company`

Debug (without signing secrets):
```powershell
flutter build apk --debug
```

## 4) CI / GitHub Actions

Workflow added:
- `.github/workflows/android-release.yml`

Behavior:
- Always builds debug APKs for matrix apps.
- Builds release appbundle only when all signing secrets exist.
- If signing secrets are missing, release step is skipped (non-fatal).

Required secrets for release step:
- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

## 5) Security Rules

- Never commit:
  - `key.properties`
  - `*.jks`
  - `*.keystore`
- Keep secrets in CI secret store only.
- Use upload key policy rotation only outside this fix cycle.
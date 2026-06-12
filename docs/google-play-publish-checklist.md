# Google Play Publishing Checklist (Maslaki)

## 1) Final Android identity

1. Set your final package name (`applicationId`) before first production release.
2. Keep `namespace` aligned with package name.
3. If you change package name, add the same package in Firebase and replace:
   - `android/app/google-services.json`

## 2) Release signing

1. Generate upload keystore:

```bash
keytool -genkeypair -v \
  -storetype JKS \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload \
  -keystore keys/maslaki-upload.jks
```

2. Copy `android/key.properties.example` to `android/key.properties`.
3. Fill `storeFile`, `storePassword`, `keyAlias`, `keyPassword`.
4. Alternative for CI: set env vars:
   - `ANDROID_KEYSTORE_PATH`
   - `ANDROID_KEYSTORE_PASSWORD`
   - `ANDROID_KEY_ALIAS`
   - `ANDROID_KEY_PASSWORD`

## 3) Build release AAB

```bash
flutter clean
flutter pub get
flutter build appbundle --release
```

Output:

`build/app/outputs/bundle/release/app-release.aab`

## 4) Play Console required declarations

1. Data safety form
2. App access (review login if needed)
3. Content rating
4. Ads declaration
5. Sensitive permissions declarations (microphone/location/full-screen intent/foreground service)
6. Account deletion URL + in-app account deletion flow

## 5) Store listing assets

1. App icon (512x512)
2. Feature graphic (1024x500)
3. Phone screenshots
4. Short description + full description
5. Privacy policy URL

## 6) Testing and rollout

1. Internal test upload first
2. Closed test (required for some personal accounts before production)
3. Fix pre-launch report issues
4. Start with staged rollout (e.g. 10%)

## Notes for this project

- Release signing is now enforced for release tasks.
- Cleartext HTTP is enabled only for `debug`; release expects HTTPS.
- `targetSdk` and `compileSdk` are pinned to at least API 35.

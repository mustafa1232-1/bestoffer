# Social V3 — Device Evidence Procedure

This is the on-device acceptance loop (§0, §15). It must be run on a **physical
Android device** (and iPhone when available). It cannot be done from the
development environment used to write the code — there is no `adb`/device there,
so this section is **NOT_TESTED** until someone runs it.

## 1. Build the user APK with an authoritative SHA stamp

The `BuildInfo` contract reads these dart-defines. Passing them is what makes the
installed binary self-report its SHA in the hidden diagnostics screen and the
startup log.

```bash
GIT_SHA=$(git rev-parse HEAD)
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
BUILD_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
FLUTTER_VER=$(flutter --version | head -1)

flutter clean
flutter pub get
flutter build apk --release --flavor user -t lib/main.dart \
  --dart-define=GIT_SHA=$GIT_SHA \
  --dart-define=GIT_BRANCH=$GIT_BRANCH \
  --dart-define=BUILD_TIMESTAMP=$BUILD_TS \
  --dart-define=FLUTTER_VERSION="$FLUTTER_VER" \
  --dart-define=APP_FLAVOR=user \
  --dart-define=APP_VERSION=1.0.1+9 \
  --dart-define=BACKEND_RELEASE_SHA=<railway release sha>
```

Output APK: `build/app/outputs/flutter-apk/app-user-release.apk`.
Do **not** reuse an APK from a previous output directory.

## 2. Install the exact new APK and clear data

```bash
adb uninstall com.maslaki.user || true
adb install -r build/app/outputs/flutter-apk/app-user-release.apk
adb shell pm clear com.maslaki.user
```

## 3. Prove which build is running

* Launch the app; in `adb logcat` confirm the `[buildinfo] sha=<short> ...`
  line matches `GIT_SHA`.
* In-app: Settings → tap the version label at the bottom **7 times** → the
  **Build diagnostics** screen shows the full SHA, branch, applicationId,
  version, backend URL. Screenshot it. This is the SHA proof.

## 4. Capture the 21-step evidence (§15)

Record screen videos + screenshots for: build SHA screen → Reels tab → reel
playing → vertical swipe → pause/play → mute/unmute → comments without playback
reset → share sheet → Add to Story → shared reel filling the story canvas →
publish story → story auto-advance → final story closing → open native gallery →
select large reel → upload progress → interrupt+resume → processing → reel in
feed → reel in profile → open canonical link from WhatsApp.

## 5. Compare against the failure baseline

The captured Reels screen must visibly differ from the baseline screenshot:
full-screen video, no rounded feed card, no circular placeholder, no reaction
chips under the media, no floating Create button over the reel, no AppBar/bottom
nav framing the reel.

> No PASS is claimed for §0/§15 until this procedure has been executed with
> visible evidence attached.

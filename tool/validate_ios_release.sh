#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

REPORT_PATH="${IOS_VALIDATION_REPORT:-build/ios_release_validation_report.json}"
mkdir -p "$(dirname "$REPORT_PATH")"

json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'
}

write_report() {
  local status="$1"
  local message="$2"
  local app_path="${3:-}"
  local bundle_id="${4:-}"
  local short_version="${5:-}"
  local build_number="${6:-}"
  cat >"$REPORT_PATH" <<JSON
{
  "status": $(printf '%s' "$status" | json_escape),
  "message": $(printf '%s' "$message" | json_escape),
  "appPath": $(printf '%s' "$app_path" | json_escape),
  "bundleIdentifier": $(printf '%s' "$bundle_id" | json_escape),
  "shortVersion": $(printf '%s' "$short_version" | json_escape),
  "buildNumber": $(printf '%s' "$build_number" | json_escape),
  "generatedAt": $(date -u +"%Y-%m-%dT%H:%M:%SZ" | json_escape)
}
JSON
}

fail() {
  local message="$1"
  echo "$message" >&2
  write_report "failed" "$message"
  exit 1
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  write_report "blocked" "This validation must run on macOS with Xcode installed."
  echo "This validation must run on macOS with Xcode installed." >&2
  exit 2
fi

command -v flutter >/dev/null || fail "flutter is not installed or not on PATH."
command -v dart >/dev/null || fail "dart is not installed or not on PATH."
command -v python3 >/dev/null || fail "python3 is not installed or not on PATH."
command -v pod >/dev/null || fail "CocoaPods is not installed or not on PATH."
command -v xcodebuild >/dev/null || fail "Xcode command line tools are not installed."
command -v plutil >/dev/null || fail "plutil is not available."
command -v /usr/libexec/PlistBuddy >/dev/null || fail "PlistBuddy is not available."

SCHEME="${IOS_SCHEME:-}"
TARGET="${IOS_TARGET:-}"

if [[ -z "$SCHEME" ]]; then
  if [[ -f ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme ]]; then
    SCHEME="Runner"
  else
    SCHEME="$(find ios -maxdepth 5 -name '*.xcscheme' | sed 's#.*/##; s#\.xcscheme$##' | sort | head -n 1)"
  fi
fi

if [[ -z "$TARGET" ]]; then
  if [[ -f lib/main.dart ]]; then
    TARGET="lib/main.dart"
  else
    TARGET="$(find lib -maxdepth 1 -name 'main*.dart' | sort | head -n 1)"
  fi
fi

if [[ -z "$SCHEME" || -z "$TARGET" ]]; then
  fail "Could not detect iOS scheme or Flutter target. Set IOS_SCHEME and IOS_TARGET."
fi

FORMAT_PATHS=()
for path in lib test integration_test tool; do
  [[ -d "$path" ]] && FORMAT_PATHS+=("$path")
done
if [[ -d packages ]]; then
  while IFS= read -r path; do
    FORMAT_PATHS+=("$path")
  done < <(find packages -mindepth 2 -maxdepth 2 \( -name lib -o -name test \) -type d | sort)
fi

EXCLUDED_PATHS=(
  ".dart_tool/"
  "build/"
  "third_party/"
  "vendor/"
  "ios/Pods/"
  "android/.gradle/"
  "generated plugin examples"
)

echo "Detected iOS scheme: $SCHEME"
echo "Detected Flutter target: $TARGET"
echo "First-party Dart format paths:"
printf '  %s\n' "${FORMAT_PATHS[@]}"
echo "Excluded vendored/generated paths:"
printf '  %s\n' "${EXCLUDED_PATHS[@]}"

flutter clean
flutter pub get

set +e
FORMAT_OUTPUT="$(dart format --output=none --set-exit-if-changed "${FORMAT_PATHS[@]}" 2>&1)"
FORMAT_STATUS=$?
set -e
if [[ "$FORMAT_STATUS" -ne 0 ]]; then
  echo "$FORMAT_OUTPUT" >&2
  fail "First-party Dart format validation failed. The output above lists each failing file."
fi

flutter analyze
flutter test

(cd ios && pod install)

if [[ "${IOS_CODESIGN:-1}" == "0" ]]; then
  BUILD_ARGS=(build ios --release --target "$TARGET" --no-codesign)
else
  BUILD_ARGS=(build ipa --release --target "$TARGET")
fi
if [[ "$SCHEME" != "Runner" ]]; then
  BUILD_ARGS+=(--flavor "$SCHEME")
fi

set +e
flutter "${BUILD_ARGS[@]}"
BUILD_STATUS=$?
set -e
if [[ "$BUILD_STATUS" -ne 0 ]]; then
  fail "iOS release build failed. If this is signing-related, open ios/Runner.xcworkspace in Xcode, select the correct Team and provisioning profile, or rerun with IOS_CODESIGN=0 only for unsigned bundle inspection."
fi

ARCHIVE_PATH="$(find build/ios -path '*.xcarchive' -type d | sort | tail -n 1 || true)"
if [[ -n "$ARCHIVE_PATH" ]]; then
  APP_PATH="$(find "$ARCHIVE_PATH/Products/Applications" -path '*.app' -type d | sort | tail -n 1 || true)"
else
  APP_PATH="$(find build/ios -path '*.app' -type d | sort | tail -n 1 || true)"
fi
if [[ -z "$ARCHIVE_PATH" && "${IOS_CODESIGN:-1}" != "0" ]]; then
  fail "No .xcarchive was found. Do not claim archive success from a simulator or unsigned build."
fi
if [[ -z "$APP_PATH" ]]; then
  fail "Could not locate a built .app under build/ios."
fi

INFO_PLIST="$APP_PATH/Info.plist"
[[ -f "$INFO_PLIST" ]] || fail "Built app Info.plist not found at $INFO_PLIST."
plutil -lint "$INFO_PLIST"

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$INFO_PLIST")"
SHORT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$INFO_PLIST")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$INFO_PLIST")"

echo "Bundle identifier: $BUNDLE_ID"
echo "Short version: $SHORT_VERSION"
echo "Build number: $BUILD_NUMBER"
echo "Archive path: ${ARCHIVE_PATH:-not produced because IOS_CODESIGN=0}"
echo "App path: $APP_PATH"

echo "UIBackgroundModes:"
if /usr/libexec/PlistBuddy -c 'Print UIBackgroundModes' "$INFO_PLIST"; then
  if /usr/libexec/PlistBuddy -c 'Print UIBackgroundModes' "$INFO_PLIST" | grep -E '\b(audio|location|voip|fetch|processing)\b'; then
    fail "Invalid iOS background mode found. Only remote-notification is allowed for this release."
  fi
else
  echo "No UIBackgroundModes key found."
fi

if /usr/libexec/PlistBuddy -c 'Print UIBackgroundModes' "$INFO_PLIST" 2>/dev/null | grep -q 'remote-notification'; then
  grep -R -q -a 'FirebaseMessaging\|push-token\|remote-notification' lib ios || \
    fail "remote-notification is present but push-notification implementation markers were not found."
fi

echo "Permission usage descriptions:"
/usr/libexec/PlistBuddy -c 'Print NSCameraUsageDescription' "$INFO_PLIST" || true
/usr/libexec/PlistBuddy -c 'Print NSPhotoLibraryUsageDescription' "$INFO_PLIST" || true
/usr/libexec/PlistBuddy -c 'Print NSLocationWhenInUseUsageDescription' "$INFO_PLIST" || true
if /usr/libexec/PlistBuddy -c 'Print NSLocationAlwaysAndWhenInUseUsageDescription' "$INFO_PLIST" >/dev/null 2>&1; then
  fail "Always-location usage description is present in the release bundle."
fi

if grep -R -a -E 'localhost|127\.0\.0\.1|http://|10\.[0-9]+\.[0-9]+\.[0-9]+|172\.(1[6-9]|2[0-9]|3[0-1])\.[0-9]+\.[0-9]+|192\.168\.[0-9]+\.[0-9]+' "$APP_PATH"; then
  fail "Development or private API marker found in built bundle."
fi

if grep -R -a -E 'Dart VM Service|Observatory|FLUTTER_BUILD_MODE=debug|Debug.xcconfig' "$APP_PATH"; then
  fail "Debug marker found in built bundle."
fi

write_report "passed" "iOS release validation passed." "$APP_PATH" "$BUNDLE_ID" "$SHORT_VERSION" "$BUILD_NUMBER"
echo "iOS release validation passed. Report: $REPORT_PATH"

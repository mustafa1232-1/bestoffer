param(
  [string]$VersionName = "1.0.1",
  [int]$UserVersionCode = 13,
  [int]$StoreVersionCode = 13,
  [int]$DeliveryVersionCode = 13,
  [int]$CaptainVersionCode = 13,
  [string]$BackendReleaseSha = "",
  [string]$ApiBaseUrl = "https://bestoffer-production.up.railway.app",
  [string]$OutputRoot = "",
  [switch]$SkipApk,
  [switch]$SkipAab
)

$ErrorActionPreference = "Stop"

function Fail($Message) {
  throw "[build_android_apps] $Message"
}

function Read-ManifestValue($ManifestPath, $Name) {
  if (-not (Test-Path -LiteralPath $ManifestPath)) {
    Fail "merged manifest not found: $ManifestPath"
  }
  $content = Get-Content -Raw -LiteralPath $ManifestPath
  $match = [regex]::Match($content, "$Name=`"([^`"]+)`"")
  if (-not $match.Success) {
    Fail "manifest value '$Name' not found in $ManifestPath"
  }
  return $match.Groups[1].Value
}

function Get-AppVersionCode($Key) {
  switch ($Key) {
    "user" { return $UserVersionCode }
    "store" { return $StoreVersionCode }
    "delivery" { return $DeliveryVersionCode }
    "captain" { return $CaptainVersionCode }
    default { Fail "unknown app key: $Key" }
  }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Push-Location $repoRoot
try {
  $branch = (git branch --show-current).Trim()
  if ($branch -ne "maslaki-final-v") {
    Fail "refusing to build from branch '$branch'; expected maslaki-final-v"
  }

  $status = (git status --short)
  if ($status) {
    Fail "refusing to build from a dirty worktree:`n$status"
  }

  $headSha = (git rev-parse HEAD).Trim()
  $shortSha = (git rev-parse --short=7 HEAD).Trim()
  $matrixPath = Join-Path $repoRoot "tool\release\android_apps.json"
  $matrix = Get-Content -Raw -LiteralPath $matrixPath | ConvertFrom-Json
  if ([string]::IsNullOrWhiteSpace($BackendReleaseSha)) {
    $BackendReleaseSha = $matrix.backendReleaseSha
  }
  if ([string]::IsNullOrWhiteSpace($BackendReleaseSha)) {
    Fail "BackendReleaseSha is required"
  }

  if (-not (Test-Path -LiteralPath "android\key.properties") -and
      [string]::IsNullOrWhiteSpace($env:ANDROID_KEYSTORE_PATH)) {
    Fail "release signing is not configured; android/key.properties or ANDROID_* env vars are required"
  }

  $flutterVersion = (flutter --version --machine | ConvertFrom-Json).frameworkVersion
  $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path (Split-Path $repoRoot -Parent) "publish-android-$VersionName-$shortSha"
  }
  New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

  flutter pub get

  $report = [ordered]@{
    repository = $repoRoot
    branch = $branch
    headSha = $headSha
    versionName = $VersionName
    backendReleaseSha = $BackendReleaseSha
    apiBaseUrl = $ApiBaseUrl
    builtAtUtc = $timestamp
    artifacts = @()
  }

  foreach ($entry in $matrix.apps.PSObject.Properties) {
    $key = $entry.Name
    $app = $entry.Value
    $versionCode = Get-AppVersionCode $key
    $appVersion = "$VersionName+$versionCode"
    $baseName = "maslaki-$key-$VersionName+$versionCode-$shortSha-play"

    $defines = @(
      "--dart-define=GIT_SHA=$headSha",
      "--dart-define=GIT_BRANCH=$branch",
      "--dart-define=BUILD_TIMESTAMP=$timestamp",
      "--dart-define=BUILD_FLUTTER_VERSION=$flutterVersion",
      "--dart-define=BACKEND_RELEASE_SHA=$BackendReleaseSha",
      "--dart-define=APP_VERSION=$appVersion",
      "--dart-define=APP_FLAVOR=$($app.flavor)",
      "--dart-define=APP_SURFACE=$($app.surface)",
      "--dart-define=API_BASE_URL=$ApiBaseUrl"
    )

    if (-not $SkipAab) {
      flutter build appbundle --release --flavor $app.flavor --target $app.target --build-name $VersionName --build-number $versionCode @defines
      $sourceAab = Join-Path $repoRoot "build\app\outputs\bundle\$($app.flavor)Release\app-$($app.flavor)-release.aab"
      if (-not (Test-Path -LiteralPath $sourceAab)) {
        Fail "AAB output missing for $key at $sourceAab"
      }
      $destAab = Join-Path $OutputRoot "$baseName.aab"
      Copy-Item -LiteralPath $sourceAab -Destination $destAab -Force
      $aabHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $destAab).Hash
      $report.artifacts += [ordered]@{
        app = $key
        type = "aab"
        path = $destAab
        sha256 = $aabHash
        applicationId = $app.applicationId
        flavor = $app.flavor
        surface = $app.surface
        target = $app.target
        versionCode = $versionCode
        versionName = $VersionName
      }
    }

    if (-not $SkipApk) {
      flutter build apk --release --flavor $app.flavor --target $app.target --build-name $VersionName --build-number $versionCode @defines
      $sourceApk = Join-Path $repoRoot "build\app\outputs\flutter-apk\app-$($app.flavor)-release.apk"
      if (-not (Test-Path -LiteralPath $sourceApk)) {
        Fail "APK output missing for $key at $sourceApk"
      }
      $destApk = Join-Path $OutputRoot "$baseName.apk"
      Copy-Item -LiteralPath $sourceApk -Destination $destApk -Force
      $apkHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $destApk).Hash
      $report.artifacts += [ordered]@{
        app = $key
        type = "apk"
        path = $destApk
        sha256 = $apkHash
        applicationId = $app.applicationId
        flavor = $app.flavor
        surface = $app.surface
        target = $app.target
        versionCode = $versionCode
        versionName = $VersionName
      }
    }

    $manifestCandidates = @(
      "build\app\intermediates\merged_manifest\$($app.flavor)Release\process$($app.flavor.Substring(0,1).ToUpper())$($app.flavor.Substring(1))ReleaseMainManifest\AndroidManifest.xml",
      "build\app\intermediates\merged_manifest\$($app.flavor)Release\output$($app.flavor.Substring(0,1).ToUpper())$($app.flavor.Substring(1))ReleaseAppLinkSettings\AndroidManifest.xml"
    )
    $manifestPath = $manifestCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    $actualApplicationId = Read-ManifestValue $manifestPath "package"
    $actualVersionCode = [int](Read-ManifestValue $manifestPath "android:versionCode")
    $actualVersionName = Read-ManifestValue $manifestPath "android:versionName"
    if ($actualApplicationId -ne $app.applicationId) {
      Fail "$key applicationId mismatch: expected $($app.applicationId), got $actualApplicationId"
    }
    if ($actualVersionCode -ne $versionCode) {
      Fail "$key versionCode mismatch: expected $versionCode, got $actualVersionCode"
    }
    if ($actualVersionName -ne $VersionName) {
      Fail "$key versionName mismatch: expected $VersionName, got $actualVersionName"
    }
    if ($key -ne "user" -and $app.target -eq "lib/main.dart") {
      Fail "$key target must not be lib/main.dart"
    }
  }

  $reportPath = Join-Path $OutputRoot "android-release-manifest-$VersionName-$shortSha.json"
  $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8
  Get-ChildItem -LiteralPath $OutputRoot -File |
    Get-FileHash -Algorithm SHA256 |
    Sort-Object Path |
    ForEach-Object { "$([IO.Path]::GetFileName($_.Path)) $($_.Hash)" } |
    Set-Content -LiteralPath (Join-Path $OutputRoot "SHA256SUMS.txt") -Encoding UTF8
  Write-Output "Release artifacts written to: $OutputRoot"
  Write-Output "Release manifest: $reportPath"
} finally {
  Pop-Location
}

# Builds the three Play-deliverable flavors (user / store / delivery) as both
# AAB (Play upload) and APK (internal testing) after the Android 15 edge-to-edge
# fix. Uses the committed product-flavor Gradle config, so each build passes
# --flavor and the matching Dart entrypoint. Continues on failure to produce a
# full matrix and logs everything.

$ErrorActionPreference = "Continue"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

$outDir = Join-Path $repoRoot "release_uploads/edge_to_edge_fix"
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$logPath = Join-Path $outDir "build_log.txt"
"== edge-to-edge release build started $(Get-Date -Format o) ==" | Out-File $logPath -Encoding utf8

$targets = @(
  @{ Flavor = "user";     Target = "lib/main.dart";          AppId = "com.maslaki.user" },
  @{ Flavor = "store";    Target = "lib/main_store.dart";     AppId = "com.maslaki.store" },
  @{ Flavor = "delivery"; Target = "lib/main_delivery.dart";  AppId = "com.maslaki.delivery" }
)

function Log($msg) {
  $line = "[$(Get-Date -Format HH:mm:ss)] $msg"
  Write-Host $line
  $line | Out-File $logPath -Append -Encoding utf8
}

foreach ($t in $targets) {
  $flavor = $t.Flavor
  foreach ($kind in @("appbundle", "apk")) {
    Log "BUILD START $flavor $kind"
    & flutter build $kind --release --flavor $flavor -t $t.Target *>> $logPath
    $code = $LASTEXITCODE
    if ($code -eq 0) {
      Log "BUILD OK $flavor $kind"
      if ($kind -eq "appbundle") {
        $src = "build/app/outputs/bundle/${flavor}Release/app-$flavor-release.aab"
      } else {
        $src = "build/app/outputs/flutter-apk/app-$flavor-release.apk"
      }
      if (Test-Path $src) {
        $ext = if ($kind -eq "appbundle") { "aab" } else { "apk" }
        $dest = Join-Path $outDir "maslaki-$flavor-$($t.AppId).$ext"
        Copy-Item $src $dest -Force
        $mb = "{0:N2}" -f ((Get-Item $dest).Length / 1MB)
        $sha = (Get-FileHash -Algorithm SHA256 $dest).Hash
        Log "ARTIFACT $dest  ${mb}MB  SHA256=$sha"
      } else {
        Log "WARN expected artifact missing: $src"
      }
    } else {
      Log "BUILD FAIL $flavor $kind exit=$code"
    }
  }
}
Log "== ALL BUILDS DONE =="

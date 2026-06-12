param(
  [ValidateSet('release')]
  [string]$Mode = 'release',
  [switch]$Bundle,
  [string]$AppId = 'com.maslaki.company',
  [string]$AppLabel = 'Company Portal'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$appDir = Join-Path $repoRoot 'apps/app_company'
Push-Location $appDir
$previousAppId = $env:ORG_GRADLE_PROJECT_APP_ID
$previousAppLabel = $env:ORG_GRADLE_PROJECT_APP_LABEL
try {
  $env:ORG_GRADLE_PROJECT_APP_ID = $AppId
  $env:ORG_GRADLE_PROJECT_APP_LABEL = $AppLabel

  $apkOutputDir = Join-Path $appDir 'build/app/outputs/flutter-apk'
  $bundleOutputDir = Join-Path $appDir 'build/app/outputs/bundle/release'

  if ($Bundle) {
    if ($Mode -ne 'release') { throw 'Android app bundles are supported only with release mode.' }
    if (Test-Path -LiteralPath $bundleOutputDir) {
      Get-ChildItem -LiteralPath $bundleOutputDir -Filter '*.aab' -File | Remove-Item -Force
    }
    $args = @('build', 'appbundle', '--release')
  } else {
    if (Test-Path -LiteralPath $apkOutputDir) {
      Get-ChildItem -LiteralPath $apkOutputDir -Filter '*.apk' -File | Remove-Item -Force
    }
    $args = @('build', 'apk', '--release')
  }

  & flutter @args
  if ($LASTEXITCODE -ne 0) { throw "flutter build failed with exit code $LASTEXITCODE" }

  $outputDir = Join-Path $repoRoot 'build/company/android'
  New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

  if ($Bundle) {
    $source = Get-ChildItem -LiteralPath $bundleOutputDir -Filter '*.aab' -File |
      Sort-Object LastWriteTimeUtc -Descending |
      Select-Object -First 1
    $target = Join-Path $outputDir 'company-release.aab'
  } else {
    $source = Get-ChildItem -LiteralPath $apkOutputDir -Filter '*.apk' -File |
      Sort-Object LastWriteTimeUtc -Descending |
      Select-Object -First 1
    $target = Join-Path $outputDir "company-release.apk"
  }

  if (-not $source) {
    throw 'Expected build artifact was not produced.'
  }
  Copy-Item -LiteralPath $source.FullName -Destination $target -Force
  Write-Host "Created $target from $($source.Name)" -ForegroundColor Green
}
finally {
  $env:ORG_GRADLE_PROJECT_APP_ID = $previousAppId
  $env:ORG_GRADLE_PROJECT_APP_LABEL = $previousAppLabel
  Pop-Location
}

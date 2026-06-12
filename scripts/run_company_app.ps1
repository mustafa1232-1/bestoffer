param(
  [string]$DeviceId,
  [ValidateSet('debug', 'profile', 'release')]
  [string]$Mode = 'debug',
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
  $args = @('run')
  if ($Mode -ne 'debug') { $args += @('--' + $Mode) }
  if ($DeviceId) { $args += @('-d', $DeviceId) }
  & flutter @args
  if ($LASTEXITCODE -ne 0) { throw "flutter run failed with exit code $LASTEXITCODE" }
}
finally {
  $env:ORG_GRADLE_PROJECT_APP_ID = $previousAppId
  $env:ORG_GRADLE_PROJECT_APP_LABEL = $previousAppLabel
  Pop-Location
}

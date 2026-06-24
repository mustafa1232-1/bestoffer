param(
  [string]$Rebuild = "true",
  [string]$OutputPath = "docs/APP_SIZE_DIFF_REPORT.md"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

$normalizedRebuild = $Rebuild.Trim().ToLowerInvariant()
$shouldRebuild = @("1", "true", "yes", "y", "on").Contains($normalizedRebuild)

function Invoke-CheckedCommand {
  param(
    [Parameter(Mandatory = $true)][string]$Command,
    [Parameter(Mandatory = $false)][string[]]$Arguments = @()
  )

  & $Command @Arguments | Out-Host
  if ($LASTEXITCODE -ne 0) {
    throw "Command failed with exit code ${LASTEXITCODE}: $Command $($Arguments -join ' ')"
  }
}

function Parse-KeyPropertiesFile {
  param([Parameter(Mandatory = $true)][string]$Path)

  $map = @{}
  foreach ($line in Get-Content $Path) {
    $trimmed = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
    if ($trimmed.StartsWith("#")) { continue }
    $idx = $trimmed.IndexOf("=")
    if ($idx -lt 1) { continue }
    $key = $trimmed.Substring(0, $idx).Trim()
    $value = $trimmed.Substring($idx + 1).Trim()
    if (-not [string]::IsNullOrWhiteSpace($key)) {
      $map[$key] = $value
    }
  }
  return $map
}

function Resolve-KeystorePath {
  param(
    [Parameter(Mandatory = $true)][string]$RawPath,
    [Parameter(Mandatory = $true)][string]$KeyPropertiesDirectory,
    [Parameter(Mandatory = $true)][string]$RepoRootPath
  )

  if ([string]::IsNullOrWhiteSpace($RawPath)) { return $null }

  if ([IO.Path]::IsPathRooted($RawPath) -and (Test-Path $RawPath)) {
    return (Resolve-Path $RawPath).Path
  }

  $candidates = @(
    (Join-Path $KeyPropertiesDirectory $RawPath),
    (Join-Path $RepoRootPath $RawPath),
    (Join-Path (Join-Path $RepoRootPath "keys") ([IO.Path]::GetFileName($RawPath)))
  )

  foreach ($candidate in $candidates) {
    if (Test-Path $candidate) {
      return (Resolve-Path $candidate).Path
    }
  }

  return (Join-Path $KeyPropertiesDirectory $RawPath)
}

function Initialize-AndroidSigningEnvironment {
  param([Parameter(Mandatory = $true)][string]$RepoRootPath)

  $requiredVars = @(
    "ANDROID_KEYSTORE_PATH",
    "ANDROID_KEYSTORE_PASSWORD",
    "ANDROID_KEY_ALIAS",
    "ANDROID_KEY_PASSWORD"
  )

  $allPresent = $true
  foreach ($name in $requiredVars) {
    if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) {
      $allPresent = $false
      break
    }
  }
  if ($allPresent) {
    Write-Host "Android signing environment already populated."
    return
  }

  $keyPropsPath = Join-Path $RepoRootPath "android/key.properties"
  if (-not (Test-Path $keyPropsPath)) {
    Write-Warning "android/key.properties not found. Split app release builds may fail."
    return
  }

  $props = Parse-KeyPropertiesFile -Path $keyPropsPath
  $keyPropsDirectory = Split-Path -Parent $keyPropsPath
  $storeFileRaw = ""
  if ($props.ContainsKey("storeFile") -and -not [string]::IsNullOrWhiteSpace($props["storeFile"])) {
    $storeFileRaw = $props["storeFile"]
  }
  $storePathResolved = Resolve-KeystorePath -RawPath $storeFileRaw -KeyPropertiesDirectory $keyPropsDirectory -RepoRootPath $RepoRootPath

  if (-not [string]::IsNullOrWhiteSpace($storePathResolved) -and [string]::IsNullOrWhiteSpace($env:ANDROID_KEYSTORE_PATH)) {
    $env:ANDROID_KEYSTORE_PATH = $storePathResolved
  }
  if (-not [string]::IsNullOrWhiteSpace($props["storePassword"]) -and [string]::IsNullOrWhiteSpace($env:ANDROID_KEYSTORE_PASSWORD)) {
    $env:ANDROID_KEYSTORE_PASSWORD = $props["storePassword"]
  }
  if (-not [string]::IsNullOrWhiteSpace($props["keyAlias"]) -and [string]::IsNullOrWhiteSpace($env:ANDROID_KEY_ALIAS)) {
    $env:ANDROID_KEY_ALIAS = $props["keyAlias"]
  }
  if (-not [string]::IsNullOrWhiteSpace($props["keyPassword"]) -and [string]::IsNullOrWhiteSpace($env:ANDROID_KEY_PASSWORD)) {
    $env:ANDROID_KEY_PASSWORD = $props["keyPassword"]
  }
}

function Get-ApkInfo([string]$Path) {
  if (-not (Test-Path $Path)) {
    return [pscustomobject]@{
      Exists = $false
      SizeBytes = 0
      SizeMB = "0.00"
      Sha256 = "-"
    }
  }
  $item = Get-Item $Path
  $hash = (Get-FileHash -Algorithm SHA256 -Path $Path).Hash
  return [pscustomobject]@{
    Exists = $true
    SizeBytes = $item.Length
    SizeMB = "{0:N2}" -f ($item.Length / 1MB)
    Sha256 = $hash
  }
}

function Invoke-Build(
  [string]$WorkingDir,
  [string]$Label,
  [string]$Target = "",
  [string]$AppId = "",
  [string]$AppLabel = ""
) {
  if (-not $shouldRebuild) {
    Write-Host "Skipping build for $Label (Rebuild=false)"
    return [pscustomobject]@{ Succeeded = $true; Error = "" }
  }

  Write-Host "Building $Label..."
  Push-Location $WorkingDir
  $previousAppId = $env:ORG_GRADLE_PROJECT_APP_ID
  $previousAppLabel = $env:ORG_GRADLE_PROJECT_APP_LABEL
  try {
    if (-not [string]::IsNullOrWhiteSpace($AppId)) {
      $env:ORG_GRADLE_PROJECT_APP_ID = $AppId
    }
    if (-not [string]::IsNullOrWhiteSpace($AppLabel)) {
      $env:ORG_GRADLE_PROJECT_APP_LABEL = $AppLabel
    }

    Invoke-CheckedCommand -Command "flutter" -Arguments @("pub", "get")
    $buildArgs = @("build", "apk", "--release")
    if (-not [string]::IsNullOrWhiteSpace($Target)) {
      $buildArgs += @("-t", $Target)
    }
    Invoke-CheckedCommand -Command "flutter" -Arguments $buildArgs
    return [pscustomobject]@{ Succeeded = $true; Error = "" }
  } catch {
    Write-Warning "Build failed for ${Label}: $($_.Exception.Message)"
    return [pscustomobject]@{ Succeeded = $false; Error = $_.Exception.Message }
  } finally {
    $env:ORG_GRADLE_PROJECT_APP_ID = $previousAppId
    $env:ORG_GRADLE_PROJECT_APP_LABEL = $previousAppLabel
    Pop-Location
  }
}

$targets = @(
  @{ Name = "root_monolith"; WorkingDir = "."; ApkPath = "build/app/outputs/flutter-apk/app-release.apk" },
  @{ Name = "app_user"; WorkingDir = "apps/app_user"; ApkPath = "apps/app_user/build/app/outputs/flutter-apk/app-release.apk" },
  @{
    Name = "app_store";
    WorkingDir = ".";
    Target = "lib/main_store.dart";
    AppId = "com.maslaki.store";
    AppLabel = "Maslaki Store";
    ApkPath = "build/app/outputs/flutter-apk/app-release.apk"
  },
  @{ Name = "app_delivery"; WorkingDir = "apps/app_delivery"; ApkPath = "apps/app_delivery/build/app/outputs/flutter-apk/app-release.apk" },
  @{ Name = "app_taxi_captain"; WorkingDir = "apps/app_taxi_captain"; ApkPath = "apps/app_taxi_captain/build/app/outputs/flutter-apk/app-release.apk" },
  @{ Name = "app_company"; WorkingDir = "apps/app_company"; ApkPath = "apps/app_company/build/app/outputs/flutter-apk/app-release.apk" }
)

Initialize-AndroidSigningEnvironment -RepoRootPath $repoRoot.Path

$rowsList = New-Object System.Collections.Generic.List[object]
foreach ($target in $targets) {
  $targetEntrypoint = if ($target.ContainsKey("Target")) { $target.Target } else { "" }
  $targetAppId = if ($target.ContainsKey("AppId")) { $target.AppId } else { "" }
  $targetAppLabel = if ($target.ContainsKey("AppLabel")) { $target.AppLabel } else { "" }
  $buildResult = Invoke-Build `
    -WorkingDir $target.WorkingDir `
    -Label $target.Name `
    -Target $targetEntrypoint `
    -AppId $targetAppId `
    -AppLabel $targetAppLabel
  $info = Get-ApkInfo -Path $target.ApkPath
  if ($null -eq $buildResult -or -not ($buildResult.PSObject.Properties.Name -contains "Succeeded")) {
    $buildResult = [pscustomobject]@{ Succeeded = $false; Error = "No build result captured." }
  }
  $rowsList.Add([pscustomobject]@{
    App = $target.Name
    Build = if ($buildResult.Succeeded) { "PASS" } else { "FAIL" }
    BuildError = $buildResult.Error
    ApkPath = $target.ApkPath
    Exists = $info.Exists
    SizeMB = $info.SizeMB
    SizeBytes = $info.SizeBytes
    Sha256 = $info.Sha256
  })
}
$rows = @($rowsList)

$rootRow = $rows | Where-Object { $_.App -eq "root_monolith" } | Select-Object -First 1
$rootSizeBytes = 0
if ($rootRow) {
  $rootSizeBytes = [int64]$rootRow.SizeBytes
}

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$reportLines = @()
$reportLines += "# APK Size Report"
$reportLines += ""
$reportLines += "- Generated at: $timestamp"
$reportLines += "- Rebuild: $shouldRebuild"
$reportLines += ""
$reportLines += "| App | Build | APK Path | Exists | Size (MB) | Size (bytes) | Delta vs root (MB) | Delta vs root (%) | SHA256 |"
$reportLines += "| --- | --- | --- | --- | ---: | ---: | ---: | ---: | --- |"
foreach ($row in $rows) {
  $deltaMbText = "-"
  $deltaPctText = "-"
  if ($rootSizeBytes -gt 0) {
    $deltaBytes = [int64]$row.SizeBytes - $rootSizeBytes
    $deltaMbText = "{0:N2}" -f ($deltaBytes / 1MB)
    $deltaPctText = "{0:N2}" -f (($deltaBytes * 100.0) / $rootSizeBytes)
  }
  $reportLines += "| $($row.App) | $($row.Build) | $($row.ApkPath) | $($row.Exists) | $($row.SizeMB) | $($row.SizeBytes) | $deltaMbText | $deltaPctText | $($row.Sha256) |"
}

$failedRows = @($rows | Where-Object { $_.Build -eq "FAIL" })
if ($failedRows.Count -gt 0) {
  $reportLines += ""
  $reportLines += "## Build Failures"
  foreach ($failed in $failedRows) {
    $reportLines += "- **$($failed.App)**: $($failed.BuildError)"
  }
}

Set-Content -Path $OutputPath -Value ($reportLines -join "`r`n") -Encoding UTF8
Write-Host "Report written to $OutputPath"

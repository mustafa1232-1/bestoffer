param(
  [string]$OutputDir = "qa_artifacts/android_release",
  [string]$ReportPath = "docs/ANDROID_PRODUCTION_ARTIFACTS.md",
  [switch]$StopOnFirstFailure
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$targets = @(
  @{ Name = "app_user"; Dir = "apps/app_user"; PackageId = "com.maslaki.user" },
  @{ Name = "app_store"; Dir = "apps/app_store"; PackageId = "com.maslaki.store" },
  @{ Name = "app_delivery"; Dir = "apps/app_delivery"; PackageId = "com.maslaki.delivery" },
  @{ Name = "app_taxi_captain"; Dir = "apps/app_taxi_captain"; PackageId = "com.maslaki.captain" },
  @{ Name = "app_company"; Dir = "apps/app_company"; PackageId = "com.maslaki.company" }
)

$rows = New-Object System.Collections.Generic.List[object]

function Invoke-CheckedCommand {
  param(
    [Parameter(Mandatory = $true)][string]$Command,
    [Parameter(Mandatory = $false)][string[]]$Arguments = @()
  )

  & $Command @Arguments
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

  if ([string]::IsNullOrWhiteSpace($RawPath)) {
    return $null
  }

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
    Write-Warning "android/key.properties not found. Relying on pre-configured environment variables for signing."
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

  if ([string]::IsNullOrWhiteSpace($env:ANDROID_KEYSTORE_PATH)) {
    Write-Warning "ANDROID_KEYSTORE_PATH is still empty after loading key.properties."
  } elseif (-not (Test-Path $env:ANDROID_KEYSTORE_PATH)) {
    Write-Warning "Resolved keystore path does not exist: $($env:ANDROID_KEYSTORE_PATH)"
  } else {
    Write-Host "Android release keystore resolved successfully."
  }
}

function Get-ArtifactInfo([string]$path) {
  if (-not (Test-Path $path)) {
    return [pscustomobject]@{
      Exists = $false
      Bytes = 0
      MB = "0.00"
      Sha256 = "-"
    }
  }
  $item = Get-Item $path
  $hash = (Get-FileHash -Algorithm SHA256 -Path $path).Hash
  return [pscustomobject]@{
    Exists = $true
    Bytes = $item.Length
    MB = "{0:N2}" -f ($item.Length / 1MB)
    Sha256 = $hash
  }
}

Initialize-AndroidSigningEnvironment -RepoRootPath $repoRoot.Path

foreach ($target in $targets) {
  $name = $target.Name
  $dir = Join-Path $repoRoot $target.Dir
  Write-Host "Building release artifacts for $name..."

  $buildSucceeded = $true
  $buildError = ""

  Push-Location $dir
  try {
    $buildOutputRoot = Join-Path $dir "build/app/outputs"
    if (Test-Path $buildOutputRoot) {
      Remove-Item -Recurse -Force (Join-Path $buildOutputRoot "flutter-apk") -ErrorAction SilentlyContinue
      Remove-Item -Recurse -Force (Join-Path $buildOutputRoot "bundle/release") -ErrorAction SilentlyContinue
    }
    Invoke-CheckedCommand -Command "flutter" -Arguments @("pub", "get")
    Invoke-CheckedCommand -Command "flutter" -Arguments @("build", "apk", "--release")
    Invoke-CheckedCommand -Command "flutter" -Arguments @("build", "appbundle", "--release")
  } catch {
    $buildSucceeded = $false
    $buildError = $_.Exception.Message
    Write-Warning "Build failed for ${name}: $buildError"
    if ($StopOnFirstFailure) {
      throw
    }
  } finally {
    Pop-Location
  }

  $apkPath = Join-Path $dir "build/app/outputs/flutter-apk/app-release.apk"
  $aabPath = Join-Path $dir "build/app/outputs/bundle/release/app-release.aab"
  $apkInfo = Get-ArtifactInfo $apkPath
  $aabInfo = Get-ArtifactInfo $aabPath

  $targetOutputDir = Join-Path $OutputDir $name
  New-Item -ItemType Directory -Path $targetOutputDir -Force | Out-Null
  if ($buildSucceeded -and $apkInfo.Exists) {
    Copy-Item $apkPath (Join-Path $targetOutputDir "$name-release.apk") -Force
  }
  if ($buildSucceeded -and $aabInfo.Exists) {
    Copy-Item $aabPath (Join-Path $targetOutputDir "$name-release.aab") -Force
  }

  $rows.Add([pscustomobject]@{
    App = $name
    PackageId = $target.PackageId
    BuildSucceeded = $buildSucceeded
    BuildError = $buildError
    ApkPath = $apkPath.Replace($repoRoot.Path + "\", "")
    ApkExists = $apkInfo.Exists
    ApkMB = $apkInfo.MB
    ApkBytes = $apkInfo.Bytes
    ApkSha256 = $apkInfo.Sha256
    AabPath = $aabPath.Replace($repoRoot.Path + "\", "")
    AabExists = $aabInfo.Exists
    AabMB = $aabInfo.MB
    AabBytes = $aabInfo.Bytes
    AabSha256 = $aabInfo.Sha256
  })
}

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$lines = @()
$lines += "# Android Production Release Artifacts"
$lines += ""
$lines += "- Generated at: $timestamp"
$lines += "- Output directory: $OutputDir"
$lines += ""
$lines += "| App | Package ID | Build | APK Exists | APK Size (MB) | APK SHA256 | AAB Exists | AAB Size (MB) | AAB SHA256 |"
$lines += "| --- | --- | --- | --- | ---: | --- | --- | ---: | --- |"
foreach ($row in $rows) {
  $buildCell = if ($row.BuildSucceeded) { "PASS" } else { "FAIL" }
  $lines += "| $($row.App) | $($row.PackageId) | $buildCell | $($row.ApkExists) | $($row.ApkMB) | $($row.ApkSha256) | $($row.AabExists) | $($row.AabMB) | $($row.AabSha256) |"
}
$lines += ""
$lines += "## Artifact Paths"
foreach ($row in $rows) {
  $lines += "- **$($row.App)**"
  if (-not $row.BuildSucceeded) {
    $lines += "  - Build status: FAIL"
    $lines += "  - Error: $($row.BuildError)"
  } else {
    $lines += "  - Build status: PASS"
  }
  $lines += "  - APK: $($row.ApkPath)"
  $lines += "  - AAB: $($row.AabPath)"
}

Set-Content -Path $ReportPath -Value ($lines -join "`r`n") -Encoding UTF8
Write-Host "Release artifact report written to $ReportPath"

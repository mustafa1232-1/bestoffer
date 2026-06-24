param(
  [switch]$StrictRuntimeNoBridge
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

$errors = New-Object System.Collections.Generic.List[string]

function Add-Error([string]$message) {
  $script:errors.Add($message)
}

function Get-Text([string]$path) {
  return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
}

Write-Host "Running import boundary checks..."

$appContracts = @(
  @{
    AppMain = "apps/app_user/lib/main.dart"
    AppPubspec = "apps/app_user/pubspec.yaml"
    RuntimePackageName = "app_user_runtime"
    RuntimeImport = "package:app_user_runtime/app_user_runtime.dart"
  },
  @{
    AppMain = "apps/app_company/lib/main.dart"
    AppPubspec = "apps/app_company/pubspec.yaml"
    RuntimePackageName = "app_company_runtime"
    RuntimeImport = "package:app_company_runtime/app_company_runtime.dart"
  }
)

# 1) apps/* pubspec must depend on its runtime package only (no bestoffer/shell)
foreach ($contract in $appContracts) {
  $pubspec = $contract.AppPubspec
  if (-not (Test-Path $pubspec)) {
    Add-Error "Missing pubspec: $pubspec"
    continue
  }

  $text = Get-Text $pubspec
  $runtimeName = [regex]::Escape($contract.RuntimePackageName)
  if ($text -notmatch "(?m)^\s*$runtimeName\s*:") {
    Add-Error "Missing required runtime dependency '$($contract.RuntimePackageName)' in $pubspec"
  }

  if ($text -match "(?m)^\s*bestoffer\s*:") {
    Add-Error "Direct bestoffer dependency is forbidden in $pubspec"
  }
  if ($text -match "(?m)^\s*app_(user|store|delivery|taxi_captain|company)_shell\s*:") {
    Add-Error "Shell dependency is forbidden in $pubspec"
  }
}

# 2) apps/* lib imports: app main.dart imports only assigned runtime package
$allowedMainImports = @{}
foreach ($contract in $appContracts) {
  $normalizedMain = $contract.AppMain.Replace('\', '/')
  $allowedMainImports[$normalizedMain] = $contract.RuntimeImport
}

# The store app is consolidated onto the full in-repo workspace
# (lib/main_store.dart -> app_store_bootstrap.dart -> features/owner), not a
# thin runtime package. So there is no app_store_runtime boundary to enforce.
$rootStoreMain = "lib/main_store.dart"
if (-not (Test-Path $rootStoreMain)) {
  Add-Error "Missing root store entrypoint: $rootStoreMain"
}

$appLibFiles = Get-ChildItem "apps" -Recurse -Filter "*.dart" |
  Where-Object { $_.FullName -like "*\lib\*" }
foreach ($file in $appLibFiles) {
  $text = Get-Text $file.FullName
  $relPath = $file.FullName.Replace($repoRoot.Path + '\', '').Replace('\', '/')
  $imports = @([System.Text.RegularExpressions.Regex]::Matches($text, "import\s+'([^']+)'\s*(?:as\s+\w+\s*)?;") |
    ForEach-Object { $_.Groups[1].Value })

  if ($allowedMainImports.ContainsKey($relPath)) {
    $allowed = $allowedMainImports[$relPath]
    foreach ($import in $imports) {
      if ($import -like "package:app_*_runtime/*" -and $import -ne $allowed) {
        Add-Error "Forbidden runtime import in ${relPath}: $import (allowed: $allowed)"
      }
    }
    if ($imports -notcontains $allowed) {
      Add-Error "Missing required runtime import in ${relPath}: $allowed"
    }
  } else {
    if ($imports | Where-Object { $_ -like "package:app_*_runtime/*" }) {
      Add-Error "Runtime package import is forbidden outside app main.dart in $relPath"
    }
  }

  if ($imports | Where-Object { $_ -like "package:bestoffer/*" }) {
    Add-Error "Direct bestoffer import is forbidden in app file: $relPath"
  }
  if ($imports | Where-Object { $_ -like "package:app_*_shell/*" }) {
    Add-Error "Shell import is forbidden in app file: $relPath"
  }
  if ($text -match "import\s+'(\.\./)+") {
    Add-Error "Forbidden parent-relative import in app lib file: $relPath"
  }
}

# 3) runtime packages
# Default mode keeps runtime packages independent and does not require a
# bestoffer bridge dependency. Strict mode additionally fails any remaining
# bestoffer dependency/import in runtimes and core packages.
$runtimeContracts = @(
  @{
    RuntimeName = "app_user_runtime"
    RuntimeLib = "packages/app_user_runtime/lib/app_user_runtime.dart"
    RuntimePubspec = "packages/app_user_runtime/pubspec.yaml"
  },
  @{
    RuntimeName = "app_company_runtime"
    RuntimeLib = "packages/app_company_runtime/lib/app_company_runtime.dart"
    RuntimePubspec = "packages/app_company_runtime/pubspec.yaml"
  }
)

foreach ($contract in $runtimeContracts) {
  if (-not (Test-Path $contract.RuntimePubspec)) {
    Add-Error "Missing runtime pubspec: $($contract.RuntimePubspec)"
    continue
  }
  $pubspecText = Get-Text $contract.RuntimePubspec
  $hasBestofferDependency = $pubspecText -match "(?m)^\s*bestoffer\s*:"
  if ($hasBestofferDependency) {
    $prefix = if ($StrictRuntimeNoBridge) { "Strict mode: " } else { "" }
    Add-Error "${prefix}bestoffer dependency is forbidden in runtime pubspec: $($contract.RuntimePubspec)"
  }

  if (-not (Test-Path $contract.RuntimeLib)) {
    Add-Error "Missing runtime lib file: $($contract.RuntimeLib)"
    continue
  }
  $runtimeDir = Split-Path $contract.RuntimeLib -Parent
  $runtimeFiles = Get-ChildItem $runtimeDir -Recurse -Filter "*.dart"
  foreach ($runtimeFile in $runtimeFiles) {
    $runtimeFileRel = $runtimeFile.FullName.Replace($repoRoot.Path + '\', '').Replace('\', '/')
    $runtimeText = Get-Text $runtimeFile.FullName
    $imports = @([System.Text.RegularExpressions.Regex]::Matches($runtimeText, "import\s+'([^']+)'\s*(?:as\s+\w+\s*)?;") |
      ForEach-Object { $_.Groups[1].Value })
    foreach ($import in $imports) {
      if ($import -like "package:app_*_runtime/*" -and $import -notlike "package:$($contract.RuntimeName)/*") {
        Add-Error "Cross-runtime import is forbidden: ${runtimeFileRel} -> $import"
      }
      if ($import -like "package:app_*_shell/*") {
        Add-Error "Shell import is forbidden in runtime file: ${runtimeFileRel} -> $import"
      }
      if ($StrictRuntimeNoBridge) {
        if ($import -like "package:bestoffer/*") {
          Add-Error "Strict mode: bestoffer import is forbidden in runtime file: ${runtimeFileRel} -> $import"
        }
      } else {
        if ($import -match "^package:bestoffer/main(_[a-z_]+)?\.dart$") {
          Add-Error "Runtime entrypoint bridge import is forbidden in runtime file: ${runtimeFileRel} -> $import"
        }
      }
    }
  }
}

# 4) legacy shell packages must not be referenced anywhere in apps or runtime
$scanFiles = @(
  (Get-ChildItem "apps" -Recurse -File -Include *.dart, pubspec.yaml),
  (Get-ChildItem "packages" -Recurse -File -Include *.dart, pubspec.yaml)
) | ForEach-Object { $_ }

foreach ($file in $scanFiles) {
  $path = $file.FullName.Replace($repoRoot.Path + '\', '')
  $content = Get-Text $file.FullName
  if ($content -match "app_(user|store|delivery|taxi_captain|company)_shell") {
    Add-Error "Legacy shell reference found in $path"
  }
}

if ($StrictRuntimeNoBridge) {
  $strictBridgePubspecs = @(
    (Get-ChildItem "packages" -Directory -Filter "core_*" | ForEach-Object { Join-Path $_.FullName "pubspec.yaml" }),
    (Get-ChildItem "packages" -Directory -Filter "shared_models" | ForEach-Object { Join-Path $_.FullName "pubspec.yaml" })
  ) | ForEach-Object { $_ } | Where-Object { Test-Path $_ }

  foreach ($pubspecPath in $strictBridgePubspecs) {
    $pubspecRel = $pubspecPath.Replace($repoRoot.Path + '\', '').Replace('\', '/')
    $pubspecText = Get-Text $pubspecPath
    if ($pubspecText -match "(?m)^\s*bestoffer\s*:") {
      Add-Error "Strict mode: bestoffer dependency is forbidden in ${pubspecRel}"
    }
  }

  $strictSourceRoots = @(
    "packages/app_user_runtime/lib",
    "packages/app_company_runtime/lib",
    "packages/core_auth/lib",
    "packages/core_design_system/lib",
    "packages/core_localization/lib",
    "packages/core_storage/lib",
    "packages/core_networking/lib",
    "packages/core_notifications/lib",
    "packages/core_realtime/lib",
    "packages/core_maps/lib",
    "packages/core_utils/lib",
    "packages/core_analytics/lib",
    "packages/shared_models/lib"
  )

  foreach ($root in $strictSourceRoots) {
    if (-not (Test-Path $root)) { continue }
    $strictFiles = Get-ChildItem $root -Recurse -Filter "*.dart"
    foreach ($strictFile in $strictFiles) {
      $strictText = Get-Text $strictFile.FullName
      $strictRel = $strictFile.FullName.Replace($repoRoot.Path + '\', '').Replace('\', '/')
      $strictImports = @([System.Text.RegularExpressions.Regex]::Matches($strictText, "import\s+'([^']+)'\s*(?:as\s+\w+\s*)?;") |
        ForEach-Object { $_.Groups[1].Value })
      foreach ($import in $strictImports) {
        if ($import -like "package:bestoffer/*") {
          Add-Error "Strict mode: bestoffer import is forbidden in ${strictRel} -> $import"
        }
      }
    }
  }
}

# 5) shipping user runtime must not include delivery/captain/store coupling
$userRuntimePath = "packages/app_user_runtime/lib/app_user_runtime.dart"
if (Test-Path $userRuntimePath) {
  $userRuntime = Get-Text $userRuntimePath
  $forbiddenInUserRuntime = @(
    "features/delivery/",
    "DeliveryOfferOverlayScreen",
    "DeliveryApi",
    "LoginScope.owner",
    "LoginScope.delivery",
    "LoginScope.taxiCaptain"
  )
  foreach ($token in $forbiddenInUserRuntime) {
    if ($userRuntime.Contains($token)) {
      Add-Error "Forbidden shipping runtime coupling found in ${userRuntimePath}: ${token}"
    }
  }
}

if ($errors.Count -gt 0) {
  Write-Host ""
  Write-Host "Boundary check failed with $($errors.Count) issue(s):" -ForegroundColor Red
  foreach ($boundaryIssue in $errors) {
    Write-Host " - $boundaryIssue" -ForegroundColor Red
  }
  exit 1
}

Write-Host "Boundary check passed." -ForegroundColor Green

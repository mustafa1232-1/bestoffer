param(
  [Parameter(Mandatory = $true)]
  [string]$Version
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$release = $Version.Trim()
if ([string]::IsNullOrWhiteSpace($release)) {
  throw "Version must not be empty."
}

$targets = @(
  @{
    Index = Join-Path $repoRoot "web/index.html";
    Bootstrap = Join-Path $repoRoot "web/flutter_bootstrap.js";
    ReleaseJson = Join-Path $repoRoot "web/maslaki-release.json"
  },
  @{
    Index = Join-Path $repoRoot "apps/app_user/web/index.html";
    Bootstrap = $null;
    ReleaseJson = Join-Path $repoRoot "apps/app_user/web/maslaki-release.json"
  },
  @{
    Index = Join-Path $repoRoot "apps/app_company/web/index.html";
    Bootstrap = $null;
    ReleaseJson = Join-Path $repoRoot "apps/app_company/web/maslaki-release.json"
  }
)

foreach ($target in $targets) {
  $indexPath = $target.Index
  if (Test-Path $indexPath) {
    $html = Get-Content -Raw -Path $indexPath
    $html = $html -replace 'window\.__MASLAKI_WEB_RELEASE__ = "[^"]+";', "window.__MASLAKI_WEB_RELEASE__ = `"$release`";"
    $html = $html -replace 'maslaki_boot_diagnostics\.js\?v=[^"]+', "maslaki_boot_diagnostics.js?v=$release"
    $html = $html -replace 'maslaki_web_update\.js\?v=[^"]+', "maslaki_web_update.js?v=$release"
    $html = $html -replace 'flutter_bootstrap\.js\?v=[^"]+', "flutter_bootstrap.js?v=$release"
    Set-Content -Path $indexPath -Value $html -NoNewline
  }

  $bootstrapPath = $target.Bootstrap
  if ($bootstrapPath -and (Test-Path $bootstrapPath)) {
    $bootstrap = Get-Content -Raw -Path $bootstrapPath
    $bootstrap = $bootstrap -replace "main\.dart\.js\?v=[^']+", "main.dart.js?v=$release"
    Set-Content -Path $bootstrapPath -Value $bootstrap -NoNewline
  }

  $releasePath = $target.ReleaseJson
  if (Test-Path $releasePath) {
    $json = Get-Content -Raw -Path $releasePath | ConvertFrom-Json
    $json.version = $release
    $json | ConvertTo-Json -Depth 4 | Set-Content -Path $releasePath
  }
}

Write-Host "Web release version set to $release"

param(
  [string]$BaseHref = '/',
  [switch]$Wasm,
  [string]$OutputDir = 'build/company/web'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$appDir = Join-Path $repoRoot 'apps/app_company'
Push-Location $appDir
try {
  $args = @('build', 'web', '--base-href', $BaseHref)
  if ($Wasm) { $args += '--wasm' }
  & flutter @args
  if ($LASTEXITCODE -ne 0) { throw "flutter build web failed with exit code $LASTEXITCODE" }

  $source = Join-Path $appDir 'build/web'
  $target = Join-Path $repoRoot $OutputDir
  if (Test-Path -LiteralPath $target) {
    Remove-Item -LiteralPath $target -Recurse -Force
  }
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
  Copy-Item -LiteralPath $source -Destination $target -Recurse -Force
  Write-Host "Created $target" -ForegroundColor Green
}
finally {
  Pop-Location
}

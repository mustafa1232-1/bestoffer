param(
  [ValidateSet('debug', 'release')]
  [string]$Mode = 'release',
  [string]$OutputDir = 'build/company/windows'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$appDir = Join-Path $repoRoot 'apps/app_company'
Push-Location $appDir
try {
  $args = @('build', 'windows')
  if ($Mode -eq 'debug') { $args += '--debug' }
  & flutter @args
  if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed with exit code $LASTEXITCODE" }

  $source = if ($Mode -eq 'debug') {
    Join-Path $appDir 'build/windows/x64/runner/Debug'
  } else {
    Join-Path $appDir 'build/windows/x64/runner/Release'
  }
  $target = Join-Path $repoRoot $OutputDir
  if (Test-Path -LiteralPath $target) {
    Remove-Item -LiteralPath $target -Recurse -Force
  }
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
  Copy-Item -LiteralPath $source -Destination $target -Recurse -Force

  $exe = Get-ChildItem -LiteralPath $target -Filter '*.exe' -File | Select-Object -First 1
  if ($exe) {
    $renamed = Join-Path $exe.DirectoryName 'company_portal.exe'
    Move-Item -LiteralPath $exe.FullName -Destination $renamed -Force
  }

  Write-Host "Created $target" -ForegroundColor Green
}
finally {
  Pop-Location
}

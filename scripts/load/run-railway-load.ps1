param(
  [string]$BaseUrl = "https://bestoffer-production.up.railway.app",
  [string]$Stages = "25,50,100,250,500,1000,2500,5000",
  [int]$CustomerPool = 160,
  [string]$Duration = "45s",
  [string]$K6Path = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$backendDir = Join-Path $repoRoot "backend"
$k6Script = Join-Path $repoRoot "tests\load\k6\mixed-workload.js"

if (-not $K6Path) {
  $k6Command = Get-Command k6 -ErrorAction SilentlyContinue
  if ($k6Command) {
    $K6Path = $k6Command.Source
  } else {
    $defaultK6Path = "C:\Program Files\k6\k6.exe"
    if (Test-Path $defaultK6Path) {
      $K6Path = $defaultK6Path
    }
  }
}

if (-not $K6Path -or -not (Test-Path $K6Path)) {
  throw "k6 is not installed or not available in PATH."
}

Push-Location $backendDir
try {
  $seedJson = & railway run --service bestoffer node src/scripts/seedLoadFixtures.js --customer-pool $CustomerPool `
    2>$null | Select-Object -Last 1
}
finally {
  Pop-Location
}

if (-not $seedJson) {
  throw "Seed command did not return fixture JSON."
}

$fixtures = $seedJson | ConvertFrom-Json
$runTag = [string]$fixtures.runTag
$authTokensJson = ($fixtures.authTokens | ConvertTo-Json -Compress)
$authTokensFile = Join-Path ([System.IO.Path]::GetTempPath()) ("bestoffer-load-auth-{0}.json" -f $runTag)
[System.IO.File]::WriteAllText($authTokensFile, $authTokensJson, [System.Text.UTF8Encoding]::new($false))

Write-Host "Seeded Railway fixtures for runTag=$runTag"

if ($fixtures.authTokens.Count -gt 0) {
  $warmAuth = $fixtures.authTokens[0]
  $warmHeaders = @{
    Authorization         = "Bearer $($warmAuth.token)"
    "X-Device-Id"         = [string]$warmAuth.deviceId
    "X-Client-Platform"   = [string]$warmAuth.platform
    "X-App-Version"       = [string]$warmAuth.appVersion
    "X-Device-Model"      = [string]$warmAuth.model
    "User-Agent"          = [string]$warmAuth.userAgent
  }
  $warmTargets = @(
    "$BaseUrl/api/merchants",
    "$BaseUrl/api/merchants?type=restaurant",
    "$BaseUrl/api/merchants?type=market"
  )
  foreach ($warmTarget in $warmTargets) {
    try {
      Invoke-WebRequest -Uri $warmTarget -Headers $warmHeaders -UseBasicParsing -TimeoutSec 20 | Out-Null
    } catch {
      Write-Warning "Prewarm failed for $warmTarget : $($_.Exception.Message)"
    }
  }
}

try {
  $stageList = $Stages.Split(",") | ForEach-Object { [int]($_.Trim()) } | Where-Object { $_ -gt 0 }
  foreach ($stage in $stageList) {
    Write-Host "=== k6 stage: $stage ==="
    $env:BASE_URL = $BaseUrl
    $env:TOTAL_VUS = [string]$stage
    $env:DURATION = $Duration
    $env:RUN_TAG = $runTag
    $env:AUTH_TOKENS_FILE = $authTokensFile
    $env:MERCHANT_ID = [string]$fixtures.merchantId
    $env:PRODUCT_ID = [string]$fixtures.productId
    $env:PHARMACY_MERCHANT_ID = [string]$fixtures.pharmacyMerchantId
    $env:PHARMACY_PRODUCT_ID = [string]$fixtures.pharmacyProductId
    try {
      & $K6Path run $k6Script
    }
    finally {
      Remove-Item Env:BASE_URL, Env:TOTAL_VUS, Env:DURATION, Env:RUN_TAG, Env:AUTH_TOKENS_FILE, `
        Env:MERCHANT_ID, Env:PRODUCT_ID, Env:PHARMACY_MERCHANT_ID, Env:PHARMACY_PRODUCT_ID `
        -ErrorAction SilentlyContinue
    }

    Write-Host "=== SSE stage: $stage ==="
    Push-Location $backendDir
    try {
      $env:STRESS_AUTH_TOKENS_FILE = $authTokensFile
      $env:LOAD_RUN_TAG = $runTag
      node src/scripts/sseStreamStress.js --base-url $BaseUrl --users $stage --observe-ms 8000
    }
    finally {
      Remove-Item Env:STRESS_AUTH_TOKENS_FILE -ErrorAction SilentlyContinue
      Remove-Item Env:LOAD_RUN_TAG -ErrorAction SilentlyContinue
      Pop-Location
    }
  }
}
finally {
  Push-Location $backendDir
  try {
    & railway run --service bestoffer node src/scripts/cleanupLoadFixtures.js --run-tag $runTag
  }
  finally {
    Pop-Location
    Remove-Item $authTokensFile -ErrorAction SilentlyContinue
  }
}

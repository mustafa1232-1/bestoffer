param(
  [string]$Service = "bestoffer",
  [string]$Environment = "production",
  [string]$ProjectId,
  [string]$HealthUrl = "https://bestoffer-production.up.railway.app/health",
  [int]$PollIntervalSeconds = 5,
  [int]$TimeoutSeconds = 300,
  [switch]$KeepBundle,
  [switch]$SkipHealthCheck
)

$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) {
  Write-Host "==> $Message" -ForegroundColor Cyan
}

function Require-Command([string]$Name) {
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Required command '$Name' is not available in PATH."
  }
}

function Get-LinkedProjectId {
  $statusJson = railway status --json
  if (-not $statusJson) {
    throw "Unable to read Railway status. Run 'railway login' and 'railway link' first."
  }
  $status = $statusJson | ConvertFrom-Json
  if (-not $status.id) {
    throw "Unable to determine Railway project id from 'railway status --json'."
  }
  return [string]$status.id
}

function Copy-DeployItem([string]$SourcePath, [string]$DestinationPath) {
  if (Test-Path -LiteralPath $SourcePath) {
    Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Recurse -Force
  }
}

Require-Command "railway"

$whoami = railway whoami
if (-not $whoami) {
  throw "Railway CLI is not authenticated. Run 'railway login' first."
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$backendRoot = Join-Path $repoRoot "backend"

if (-not (Test-Path -LiteralPath $backendRoot)) {
  throw "Backend directory was not found at '$backendRoot'."
}

if (-not (Test-Path -LiteralPath (Join-Path $backendRoot "railway.json"))) {
  throw "Expected backend/railway.json was not found."
}

if (-not $ProjectId) {
  $ProjectId = Get-LinkedProjectId
}

$bundleRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("bestoffer-railway-" + [guid]::NewGuid().ToString("N"))
$bundleBackend = Join-Path $bundleRoot "backend"

New-Item -ItemType Directory -Path $bundleBackend -Force | Out-Null

$itemsToCopy = @(
  "src",
  "sql",
  "sql_supabase",
  "deploy",
  "package.json",
  "package-lock.json",
  "Dockerfile",
  "railway.json",
  ".dockerignore",
  ".env.example",
  "README.md",
  "DEPLOY.md",
  "ENV_KEYS_CHECKLIST.txt",
  "SECURITY_CHECKLIST.md"
)

foreach ($item in $itemsToCopy) {
  Copy-DeployItem -SourcePath (Join-Path $backendRoot $item) -DestinationPath $bundleBackend
}

$beforeDeployments = railway deployment list --service $Service --environment $Environment --json | ConvertFrom-Json
$previousLatestId = $null
if ($beforeDeployments -and $beforeDeployments.Count -gt 0) {
  $previousLatestId = [string]$beforeDeployments[0].id
}

Write-Step "Deploying a clean backend bundle to Railway service '$Service' in environment '$Environment'."
Write-Step "Project id: $ProjectId"
Write-Step "Bundle root: $bundleRoot"

Push-Location $bundleRoot
try {
  railway up --detach --project $ProjectId --environment $Environment --service $Service | Out-Host
}
finally {
  Pop-Location
}

Write-Step "Waiting for Railway to register the new deployment."

$deployment = $null
$registerDeadline = (Get-Date).AddSeconds(60)
while ((Get-Date) -lt $registerDeadline) {
  $deployments = railway deployment list --service $Service --environment $Environment --json | ConvertFrom-Json
  if ($deployments -and $deployments.Count -gt 0) {
    $candidate = $deployments | Where-Object { [string]$_.id -ne $previousLatestId } | Select-Object -First 1
    if ($candidate) {
      $deployment = $candidate
      break
    }
  }
  Start-Sleep -Seconds 2
}

if (-not $deployment) {
  throw "Railway accepted the upload but a new deployment id was not registered within 60 seconds."
}

$deploymentId = [string]$deployment.id
Write-Step "Deployment id: $deploymentId"

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
while ((Get-Date) -lt $deadline) {
  $deployments = railway deployment list --service $Service --environment $Environment --json | ConvertFrom-Json
  $current = $deployments | Where-Object { [string]$_.id -eq $deploymentId } | Select-Object -First 1
  if (-not $current) {
    throw "Deployment '$deploymentId' disappeared from Railway deployment list."
  }

  $status = [string]$current.status
  Write-Host "   deployment status: $status"

  if ($status -eq "SUCCESS") {
    break
  }

  if ($status -in @("FAILED", "REMOVED")) {
    $configErrors = @()
    if ($current.meta -and $current.meta.configErrors) {
      $configErrors = @($current.meta.configErrors)
    }
    $errorSuffix = ""
    if ($configErrors.Count -gt 0) {
      $errorSuffix = " Config errors: " + ($configErrors -join " | ")
    }
    throw "Railway deployment '$deploymentId' finished with status '$status'.$errorSuffix"
  }

  Start-Sleep -Seconds $PollIntervalSeconds
}

if (-not $SkipHealthCheck) {
  Write-Step "Checking health endpoint: $HealthUrl"
  $healthUri = [System.UriBuilder]::new($HealthUrl)
  $healthQuerySuffix = "t=" + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  if ([string]::IsNullOrWhiteSpace($healthUri.Query)) {
    $healthUri.Query = $healthQuerySuffix
  } else {
    $existingQuery = $healthUri.Query.TrimStart("?")
    $healthUri.Query = $existingQuery + "&" + $healthQuerySuffix
  }
  $healthResponse = Invoke-WebRequest `
    -UseBasicParsing `
    -Uri $healthUri.Uri.AbsoluteUri `
    -Headers @{
      "Cache-Control" = "no-cache"
      "Pragma" = "no-cache"
    } `
    -TimeoutSec 30
  Write-Host $healthResponse.Content
}

if (-not $KeepBundle -and (Test-Path -LiteralPath $bundleRoot)) {
  Remove-Item -LiteralPath $bundleRoot -Recurse -Force
}

Write-Step "Backend deployment completed successfully."

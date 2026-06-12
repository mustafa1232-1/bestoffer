param(
  [string]$InputDir = "build/company/web",
  [int]$TimeoutSeconds = 300
)

$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) {
  Write-Host "==> $Message" -ForegroundColor Cyan
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$sourceDir = Join-Path $repoRoot $InputDir
if (-not (Test-Path -LiteralPath $sourceDir)) {
  throw "Input directory '$sourceDir' was not found. Build the Company web app first."
}

$endpoint = "https://codex-deploy-skills.vercel.sh/api/deploy"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("company-web-preview-" + [guid]::NewGuid().ToString("N"))
$stagingDir = Join-Path $tempRoot "staging"
$tarball = Join-Path $tempRoot "company-web.tgz"
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
  Write-Step "Preparing a slim preview package from '$sourceDir'."
  Copy-Item -LiteralPath $sourceDir -Destination $stagingDir -Recurse -Force

  $canvasKitDir = Join-Path $stagingDir "canvaskit"
  if (Test-Path -LiteralPath $canvasKitDir) {
    Remove-Item -LiteralPath $canvasKitDir -Recurse -Force
  }

  $noticesFile = Join-Path $stagingDir "assets\\NOTICES"
  if (Test-Path -LiteralPath $noticesFile) {
    Remove-Item -LiteralPath $noticesFile -Force
  }

  Get-ChildItem -LiteralPath $stagingDir -Recurse -File |
    Where-Object { $_.Name -like "*.symbols" } |
    ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }

  foreach ($brandingPath in @(
    "assets\\assets\\branding\\app_icon.png",
    "assets\\assets\\branding\\app_icon_foreground.png"
  )) {
    $fullBrandingPath = Join-Path $stagingDir $brandingPath
    if (Test-Path -LiteralPath $fullBrandingPath) {
      Remove-Item -LiteralPath $fullBrandingPath -Force
    }
  }

  $bootstrapPath = Join-Path $stagingDir "flutter_bootstrap.js"
  if (Test-Path -LiteralPath $bootstrapPath) {
    $bootstrap = Get-Content -LiteralPath $bootstrapPath -Raw
    $bootstrap = $bootstrap -replace "serviceWorkerSettings:\s*\{\s*serviceWorkerVersion:\s*`"[^`"]+`"\s*\}", "serviceWorkerSettings: null"
    Set-Content -LiteralPath $bootstrapPath -Value $bootstrap -Encoding UTF8
  }

  Write-Step "Packaging slim preview bundle."
  & tar.exe -czf $tarball -C $stagingDir .
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to create tarball for Company web build."
  }

  Write-Step "Uploading preview deployment."
  $responseText = & curl.exe -s -X POST $endpoint `
    -F "file=@$tarball" `
    -F "framework=null"
  if ($LASTEXITCODE -ne 0) {
    throw "Preview deployment upload failed."
  }

  $response = $responseText | ConvertFrom-Json
  if ($response.error) {
    throw "Preview deployment failed: $($response.error)"
  }

  if (-not $response.previewUrl) {
    throw "Preview deployment did not return a preview URL."
  }

  $previewUrl = [string]$response.previewUrl
  $claimUrl = [string]$response.claimUrl

  Write-Step "Preview URL: $previewUrl"
  if ($claimUrl) {
    Write-Step "Claim URL: $claimUrl"
  }

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    try {
      $status = [int](Invoke-WebRequest -UseBasicParsing -Uri $previewUrl -TimeoutSec 20).StatusCode
      if ($status -ge 200 -and $status -lt 500) {
        break
      }
    } catch {
      $responseObject = $_.Exception.Response
      if ($responseObject) {
        $statusCode = [int]$responseObject.StatusCode
        if ($statusCode -ge 400 -and $statusCode -lt 500) {
          break
        }
      }
    }
    Start-Sleep -Seconds 5
  }

  Write-Host ""
  Write-Host "Preview URL: $previewUrl" -ForegroundColor Green
  if ($claimUrl) {
    Write-Host "Claim URL:   $claimUrl" -ForegroundColor Yellow
  }
} finally {
  if (Test-Path -LiteralPath $tempRoot) {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
  }
}

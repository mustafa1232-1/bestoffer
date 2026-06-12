param(
  [string]$BaseUrl = "https://bestoffer-production.up.railway.app",
  [string]$Service = "bestoffer",
  [string]$Environment = "production",
  [string]$PhoneVar = "SUPER_ADMIN_PHONE",
  [string]$PinVar = "SUPER_ADMIN_PIN",
  [switch]$FailOnUnexpected = $true
)

$ErrorActionPreference = "Stop"

function Invoke-HttpStatus {
  param(
    [Parameter(Mandatory = $true)][string]$Url,
    [hashtable]$Headers = @{}
  )

  try {
    $response = Invoke-WebRequest -UseBasicParsing -Uri $Url -Headers $Headers -TimeoutSec 30
    return [int]$response.StatusCode
  } catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    if (-not $statusCode) { return -1 }
    return [int]$statusCode
  }
}

$varsJson = railway.cmd variables --service $Service --environment $Environment --json
$vars = $varsJson | ConvertFrom-Json
$phone = [string]$vars.$PhoneVar
$pin = [string]$vars.$PinVar

if ([string]::IsNullOrWhiteSpace($phone) -or [string]::IsNullOrWhiteSpace($pin)) {
  throw "CREDENTIALS_MISSING:$PhoneVar/$PinVar"
}

$loginPayload = @{ phone = $phone; pin = $pin } | ConvertTo-Json
$login = Invoke-RestMethod -Method Post -Uri "$BaseUrl/api/auth/login" -ContentType "application/json" -Body $loginPayload -TimeoutSec 30
$token = [string]$login.token
if ([string]::IsNullOrWhiteSpace($token)) {
  throw "LOGIN_FAILED:$PhoneVar"
}

$headers = @{ Authorization = "Bearer $token" }
$checks = @(
  @{ path = "/health"; expected = @(200) },
  @{ path = "/ready"; expected = @(200) },
  @{ path = "/api/admin/analytics"; expected = @(200) },
  @{ path = "/api/admin/platform-kpis"; expected = @(200) },
  @{ path = "/api/admin/financial/kpis"; expected = @(200) },
  @{ path = "/api/admin/reports/sales"; expected = @(200) },
  @{ path = "/api/admin/reports/collections"; expected = @(200) },
  @{ path = "/api/admin/reports/receivables"; expected = @(200) },
  @{ path = "/api/admin/taxi/kpi/overview"; expected = @(200) },
  @{ path = "/api/admin/taxi/reports"; expected = @(200) },
  @{ path = "/api/admin/ops/alerts"; expected = @(200) },
  @{ path = "/api/admin/ops/notifications/overview"; expected = @(200) },
  @{ path = "/api/admin/ops/device-push-health"; expected = @(200) },
  @{ path = "/api/owner/analytics"; expected = @(403) },
  @{ path = "/api/merchant/orders/reports"; expected = @(403) },
  @{ path = "/api/delivery/analytics"; expected = @(403) },
  @{ path = "/api/courier/reports"; expected = @(403) },
  @{ path = "/api/taxi/captain/dashboard"; expected = @(403) },
  @{ path = "/api/taxi/captain/subscription/ledger"; expected = @(403) },
  @{ path = "/api/company/admin/companies?limit=5"; expected = @(200) },
  @{ path = "/api/feed/communities/scopes/me"; expected = @(200) }
)

$failures = 0
$results = @()

foreach ($check in $checks) {
  $path = [string]$check.path
  $expected = @($check.expected)
  $useAuth = -not ($path -eq "/health" -or $path -eq "/ready")
  $status = Invoke-HttpStatus -Url "$BaseUrl$path" -Headers ($(if ($useAuth) { $headers } else { @{} }))
  $ok = $expected -contains $status
  if (-not $ok) { $failures++ }
  $expectedText = ($expected -join ",")
  $line = "{0} => {1} (expected: {2}) [{3}]" -f $path, $status, $expectedText, ($(if ($ok) { "PASS" } else { "FAIL" }))
  Write-Output $line
  $results += [PSCustomObject]@{
    path = $path
    status = $status
    expected = $expectedText
    ok = $ok
  }
}

$summary = [PSCustomObject]@{
  baseUrl = $BaseUrl
  checkedAt = (Get-Date).ToString("o")
  total = $results.Count
  failures = $failures
}

Write-Output ("SUMMARY: total={0} failures={1}" -f $summary.total, $summary.failures)

if ($FailOnUnexpected -and $failures -gt 0) {
  exit 1
}

if (-not $FailOnUnexpected -and $failures -gt 0) {
  exit 0
}

exit 0

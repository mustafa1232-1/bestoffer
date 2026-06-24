$ErrorActionPreference = 'Stop'
$base = 'https://bestoffer-production.up.railway.app'
$ua = 'codex-live-audit/1'
$globalHeaders = @{
  'X-Device-Id' = 'codex-live-audit-device'
  'X-Client-Platform' = 'codex'
  'X-App-Version' = 'codex-live-audit/1'
  'X-Device-Model' = 'codex-runner'
}

function Parse-Body($text) {
  if ([string]::IsNullOrWhiteSpace($text)) { return $null }
  try { return $text | ConvertFrom-Json -Depth 100 } catch { return $text }
}

function Invoke-Api {
  param(
    [string]$Method,
    [string]$Path,
    [string]$Token,
    $Body = $null
  )

  $headers = @{}
  foreach ($k in $globalHeaders.Keys) { $headers[$k] = $globalHeaders[$k] }
  if ($Token) { $headers['Authorization'] = "Bearer $Token" }
  $jsonBody = $null
  if ($null -ne $Body) { $jsonBody = $Body | ConvertTo-Json -Depth 100 }
  try {
    if ($Method -eq 'GET' -or $Method -eq 'DELETE') {
      $resp = Invoke-WebRequest -UseBasicParsing -Uri ($base + $Path) -Method $Method -Headers $headers -UserAgent $ua
    } else {
      $resp = Invoke-WebRequest -UseBasicParsing -Uri ($base + $Path) -Method $Method -Headers $headers -UserAgent $ua -ContentType 'application/json' -Body $jsonBody
    }
    return [pscustomobject]@{ status = [int]$resp.StatusCode; data = Parse-Body $resp.Content; raw = $resp.Content }
  } catch {
    $status = 0
    $bodyText = ''
    if ($_.Exception.Response) {
      $status = [int]$_.Exception.Response.StatusCode.value__
      try {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $bodyText = $reader.ReadToEnd()
      } catch {}
    } else {
      throw
    }
    return [pscustomobject]@{ status = $status; data = Parse-Body $bodyText; raw = $bodyText }
  }
}

function Assert-Status {
  param($Resp, [int[]]$Expected, [string]$Label)
  if ($Expected -notcontains [int]$Resp.status) {
    throw "${Label} expected status $($Expected -join ',') but got $($Resp.status). body=$($Resp.raw)"
  }
}

function Log-Check {
  param([string]$Label, $Resp)
  Write-Output ("[check] {0} -> {1}" -f $Label, $Resp.status)
}

$report = [ordered]@{}
$cleanupTokens = @()
$seed = [int](Get-Date -Format 'HHmmssff')
$deputyPhone = '078' + ($seed.ToString().PadLeft(8,'0').Substring(0,8))
$deliveryPhone = '077' + (($seed + 1).ToString().PadLeft(8,'0').Substring(0,8))
$userOnePhone = '079' + (($seed + 2).ToString().PadLeft(8,'0').Substring(0,8))
$userTwoPhone = '079' + (($seed + 3).ToString().PadLeft(8,'0').Substring(0,8))

try {
  $superLogin = Invoke-Api 'POST' '/api/auth/login' $null @{ phone = '07746515247'; pin = '1998' }
  Assert-Status $superLogin @(200) 'super admin login'
  Log-Check 'super admin login' $superLogin
  $superToken = [string]$superLogin.data.token
  $report.superAdminUser = $superLogin.data.user

  $checks = @(
    @{ path='/api/admin/analytics'; label='super admin analytics' },
    @{ path='/api/admin/orders/overview'; label='super admin orders overview' },
    @{ path='/api/admin/approval-inbox'; label='super admin approval inbox' },
    @{ path='/api/feed/admin/chats/threads?kind=all&limit=5'; label='super admin chat monitor' },
    @{ path='/api/jobs/applications/monitor?limit=5'; label='super admin jobs monitor' },
    @{ path='/api/admin/customers/insights?limit=5'; label='super admin customer insights' }
  )
  foreach ($item in $checks) {
    $resp = Invoke-Api 'GET' $item.path $superToken
    Assert-Status $resp @(200) $item.label
    Log-Check $item.label $resp
  }

  $ai1 = Invoke-Api 'GET' '/api/assistant/health' $superToken
  $ai2 = Invoke-Api 'GET' '/api/admin/ai/health' $superToken
  Log-Check 'assistant route with auth' $ai1
  Log-Check 'admin ai route with auth' $ai2
  $report.aiRouteStatus = @{ assistant = $ai1.status; adminAi = $ai2.status }

  $deputyCreate = Invoke-Api 'POST' '/api/admin/users' $superToken @{
    fullName = 'Audit Deputy Admin'
    phone = $deputyPhone
    pin = '1234'
    block = 'A'
    buildingNumber = '10'
    apartment = '10'
    role = 'deputy_admin'
  }
  Assert-Status $deputyCreate @(201) 'create deputy admin'
  Log-Check 'create deputy admin' $deputyCreate

  $deliveryCreate = Invoke-Api 'POST' '/api/admin/users' $superToken @{
    fullName = 'Audit Delivery'
    phone = $deliveryPhone
    pin = '1234'
    block = 'A'
    buildingNumber = '11'
    apartment = '11'
    role = 'delivery'
    driverType = 'app_driver'
  }
  Assert-Status $deliveryCreate @(201) 'create delivery user'
  Log-Check 'create delivery user' $deliveryCreate

  $deputyLogin = Invoke-Api 'POST' '/api/auth/login' $null @{ phone = $deputyPhone; pin = '1234' }
  Assert-Status $deputyLogin @(200) 'deputy admin login'
  Log-Check 'deputy admin login' $deputyLogin
  $deputyToken = [string]$deputyLogin.data.token
  $cleanupTokens += $deputyToken

  $deliveryLogin = Invoke-Api 'POST' '/api/auth/login' $null @{ phone = $deliveryPhone; pin = '1234' }
  Assert-Status $deliveryLogin @(200) 'delivery login'
  Log-Check 'delivery login' $deliveryLogin
  $deliveryToken = [string]$deliveryLogin.data.token
  $cleanupTokens += $deliveryToken

  foreach ($path in @('/api/admin/analytics','/api/admin/orders/overview','/api/admin/delivery/pending','/api/admin/taxi-captains/pending')) {
    $resp = Invoke-Api 'GET' $path $deputyToken
    Assert-Status $resp @(200) "deputy admin $path"
    Log-Check "deputy admin $path" $resp
  }

  foreach ($path in @('/api/feed/admin/chats/threads?kind=all&limit=5','/api/jobs/applications/monitor?limit=5','/api/admin/customers/insights?limit=5')) {
    $resp = Invoke-Api 'GET' $path $deputyToken
    Assert-Status $resp @(403) "deputy blocked $path"
    Log-Check "deputy blocked $path" $resp
  }

  foreach ($path in @('/api/delivery/orders/current','/api/delivery/orders/history','/api/delivery/analytics')) {
    $resp = Invoke-Api 'GET' $path $deliveryToken
    Assert-Status $resp @(200) "delivery $path"
    Log-Check "delivery $path" $resp
  }

  $userOneRegister = Invoke-Api 'POST' '/api/auth/register' $null @{
    fullName = 'Audit User One'
    phone = $userOnePhone
    pin = '1234'
    block = 'A1'
    buildingNumber = 'A101'
    apartment = '101'
    analyticsConsentAccepted = $true
    analyticsConsentVersion = 'analytics_v1'
  }
  Assert-Status $userOneRegister @(201) 'user one register'
  Log-Check 'user one register' $userOneRegister
  $userOneToken = [string]$userOneRegister.data.token
  $userOneId = [int]$userOneRegister.data.user.id
  $cleanupTokens += $userOneToken

  $userTwoRegister = Invoke-Api 'POST' '/api/auth/register' $null @{
    fullName = 'Audit User Two'
    phone = $userTwoPhone
    pin = '1234'
    block = 'A1'
    buildingNumber = 'A102'
    apartment = '102'
    analyticsConsentAccepted = $true
    analyticsConsentVersion = 'analytics_v1'
  }
  Assert-Status $userTwoRegister @(201) 'user two register'
  Log-Check 'user two register' $userTwoRegister
  $userTwoToken = [string]$userTwoRegister.data.token
  $userTwoId = [int]$userTwoRegister.data.user.id
  $cleanupTokens += $userTwoToken

  foreach ($path in @('/api/users/me','/api/orders/my','/api/feed/profile/me/social-restrictions','/api/taxi/rides/current','/api/cars/brands','/api/cars/browse','/api/cars/entitlements','/api/paid-upgrades/plans','/api/paid-upgrades/me','/api/merchants/discovery','/api/merchants/ad-board','/api/feed/posts?limit=5','/api/feed/stories','/api/feed/users/search?search=audit&limit=5')) {
    $resp = Invoke-Api 'GET' $path $userOneToken
    Assert-Status $resp @(200) "customer $path"
    Log-Check "customer $path" $resp
  }

  $relReq = Invoke-Api 'POST' ("/api/feed/users/{0}/relation/request" -f $userTwoId) $userOneToken
  Assert-Status $relReq @(200) 'relation request'
  Log-Check 'relation request' $relReq

  $incoming = Invoke-Api 'GET' '/api/feed/relations/incoming' $userTwoToken
  Assert-Status $incoming @(200) 'incoming relation requests'
  Log-Check 'incoming relation requests' $incoming

  $relAccept = Invoke-Api 'POST' ("/api/feed/users/{0}/relation/accept" -f $userOneId) $userTwoToken
  Assert-Status $relAccept @(200) 'relation accept'
  Log-Check 'relation accept' $relAccept

  $threadCreate = Invoke-Api 'POST' '/api/feed/chats/threads' $userOneToken @{ userId = $userTwoId }
  Assert-Status $threadCreate @(201) 'create direct thread'
  Log-Check 'create direct thread' $threadCreate
  $threadId = [int]$threadCreate.data.thread.id

  $threadSend = Invoke-Api 'POST' ("/api/feed/chats/threads/{0}/messages" -f $threadId) $userOneToken @{ body = 'audit-direct-message' }
  Assert-Status $threadSend @(201) 'send direct thread message'
  Log-Check 'send direct thread message' $threadSend

  $threadList = Invoke-Api 'GET' '/api/feed/chats/threads' $userTwoToken
  Assert-Status $threadList @(200) 'list threads for recipient'
  Log-Check 'list threads for recipient' $threadList

  $threadMessages = Invoke-Api 'GET' ("/api/feed/chats/threads/{0}/messages" -f $threadId) $userTwoToken
  Assert-Status $threadMessages @(200) 'list thread messages'
  Log-Check 'list thread messages' $threadMessages

  $rideCreate = Invoke-Api 'POST' '/api/taxi/rides' $userOneToken @{
    pickupLatitude = 33.31456
    pickupLongitude = 44.36611
    dropoffLatitude = 33.32091
    dropoffLongitude = 44.39118
    pickupLabel = 'Audit pickup'
    dropoffLabel = 'Audit dropoff'
    proposedFareIqd = 9000
    searchRadiusM = 2000
    note = 'audit-ride'
  }
  Assert-Status $rideCreate @(201) 'create taxi ride'
  Log-Check 'create taxi ride' $rideCreate
  $rideId = [int]$rideCreate.data.ride.id

  $rideCurrent = Invoke-Api 'GET' '/api/taxi/rides/current' $userOneToken
  Assert-Status $rideCurrent @(200) 'current taxi ride after create'
  Log-Check 'current taxi ride after create' $rideCurrent

  $rideCancel = Invoke-Api 'POST' ("/api/taxi/rides/{0}/cancel" -f $rideId) $userOneToken
  Assert-Status $rideCancel @(200) 'cancel taxi ride'
  Log-Check 'cancel taxi ride' $rideCancel

  $paidReq = Invoke-Api 'POST' '/api/paid-upgrades/requests' $userOneToken @{
    planCodes = @('premium_monthly')
    activityName = 'Audit Premium Request'
    activityDescription = 'audit'
    contactPhone = $userOnePhone
    notes = 'audit cancel'
  }
  Assert-Status $paidReq @(201) 'create paid upgrade request'
  Log-Check 'create paid upgrade request' $paidReq
  $requestId = [int]$paidReq.data.requests[0].id

  $paidCancel = Invoke-Api 'POST' ("/api/paid-upgrades/requests/{0}/cancel" -f $requestId) $userOneToken @{}
  Assert-Status $paidCancel @(200) 'cancel paid upgrade request'
  Log-Check 'cancel paid upgrade request' $paidCancel

  $report.summary = [ordered]@{
    superAdminSensitiveRoutes = 'PASS'
    deputyAdminOperationalRoutes = 'PASS'
    deputyAdminSensitiveBlocked = 'PASS'
    deliveryBaseRoutes = 'PASS'
    customerBaseRoutes = 'PASS'
    socialDirectMessaging = 'PASS'
    taxiCreateCancel = 'PASS'
    paidUpgradeRequestCancel = 'PASS'
  }

  $report.ids = [ordered]@{
    deputyAdminPhone = $deputyPhone
    deliveryPhone = $deliveryPhone
    userOnePhone = $userOnePhone
    userTwoPhone = $userTwoPhone
    threadId = $threadId
    rideId = $rideId
    paidUpgradeRequestId = $requestId
  }

  $report | ConvertTo-Json -Depth 100
}
finally {
  foreach ($token in $cleanupTokens) {
    try {
      $resp = Invoke-Api 'DELETE' '/api/users/me' $token
      Write-Output ("[cleanup] delete self -> {0}" -f $resp.status)
    } catch {
      Write-Output ("[cleanup] delete self failed -> {0}" -f $_.Exception.Message)
    }
  }
}

param(
  [Parameter(Mandatory = $true)]
  [string] $OutputDir,

  [Parameter(Mandatory = $true)]
  [string] $Name,

  [Parameter(Mandatory = $true)]
  [string] $ShortName,

  [Parameter(Mandatory = $true)]
  [string] $Description
)

$ErrorActionPreference = 'Stop'

$indexPath = Join-Path $OutputDir 'index.html'
$manifestPath = Join-Path $OutputDir 'manifest.json'

if (-not (Test-Path -LiteralPath $indexPath)) {
  throw "Missing index.html in $OutputDir"
}

if (-not (Test-Path -LiteralPath $manifestPath)) {
  throw "Missing manifest.json in $OutputDir"
}

$html = Get-Content -Raw -LiteralPath $indexPath
$escapedName = [System.Net.WebUtility]::HtmlEncode($Name)
$escapedDescription = [System.Net.WebUtility]::HtmlEncode($Description)

$html = [regex]::Replace($html, '<title>.*?</title>', "<title>$escapedName</title>")
$html = [regex]::Replace(
  $html,
  '<meta name="description" content=".*?">',
  "<meta name=`"description`" content=`"$escapedDescription`">"
)
$html = [regex]::Replace(
  $html,
  '<meta property="og:title" content=".*?">',
  "<meta property=`"og:title`" content=`"$escapedName`">"
)
$html = [regex]::Replace(
  $html,
  '<meta property="og:description" content=".*?">',
  "<meta property=`"og:description`" content=`"$escapedDescription`">"
)
$html = [regex]::Replace(
  $html,
  '<meta name="apple-mobile-web-app-title" content=".*?">',
  "<meta name=`"apple-mobile-web-app-title`" content=`"$escapedName`">"
)

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText((Resolve-Path -LiteralPath $indexPath), $html, $utf8NoBom)

$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$manifest.name = $Name
$manifest.short_name = $ShortName
$manifest.description = $Description
$manifest.start_url = '/'
$manifest.scope = '/'
$manifest.display = 'standalone'
$manifest.background_color = '#F5EEE4'
$manifest.theme_color = '#F5EEE4'
$manifest.orientation = 'portrait-primary'
$manifest.dir = 'rtl'
$manifest.lang = 'ar'
$manifest.prefer_related_applications = $false

$manifestJson = $manifest | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText((Resolve-Path -LiteralPath $manifestPath), $manifestJson, $utf8NoBom)

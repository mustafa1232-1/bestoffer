param(
  [switch]$StrictHardcodedArabic
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

function Join-Codepoints([int[]]$codes) {
  return -join ($codes | ForEach-Object { [char]$_ })
}

$l10nDir = "lib/l10n"
if (-not (Test-Path $l10nDir)) {
  Write-Host "Missing directory: $l10nDir" -ForegroundColor Red
  exit 1
}

$arbFiles = Get-ChildItem $l10nDir -Filter "*.arb" -File
if ($arbFiles.Count -eq 0) {
  Write-Host "No ARB files found under $l10nDir" -ForegroundColor Red
  exit 1
}

$arPath = Join-Path $l10nDir "app_ar.arb"
if (-not (Test-Path $arPath)) {
  Write-Host "Missing file: $arPath" -ForegroundColor Red
  exit 1
}

$arText = [System.IO.File]::ReadAllText((Resolve-Path $arPath), [System.Text.Encoding]::UTF8)

$bannedTerms = @(
  (Join-Codepoints @(0x0625,0x0646,0x0634,0x0627,0x0621,0x0020,0x062A,0x0627,0x062C,0x0631)), # إنشاء تاجر
  (Join-Codepoints @(0x0645,0x0633,0x0644,0x0642,0x064A)),                                     # مسلقي
  (Join-Codepoints @(0x0645,0x0633,0x0643,0x0644,0x064A)),                                     # مسكلي
  (Join-Codepoints @(0x0628,0x0643,0x0631,0x0627,0x062A))                                      # بكرات
)

$requiredTerms = @(
  (Join-Codepoints @(0x0645,0x0633,0x0644,0x0643,0x064A)),                                     # مسلكي
  (Join-Codepoints @(0x0625,0x0646,0x0634,0x0627,0x0621,0x0020,0x0645,0x062A,0x062C,0x0631)), # إنشاء متجر
  (Join-Codepoints @(0x0631,0x064A,0x0644,0x0632))                                              # ريلز
)

$errors = New-Object System.Collections.Generic.List[string]

foreach ($term in $bannedTerms) {
  if ($arText.Contains($term)) {
    $errors.Add("Banned Arabic term found in app_ar.arb.")
  }
}

foreach ($term in $requiredTerms) {
  if (-not $arText.Contains($term)) {
    $errors.Add("Required Arabic baseline term missing in app_ar.arb.")
  }
}

foreach ($arb in $arbFiles) {
  $content = [System.IO.File]::ReadAllText($arb.FullName, [System.Text.Encoding]::UTF8)
  if ($content -match '[\u00D8\u00D9\u00C3\u00C2]') {
    $errors.Add("Mojibake marker detected in ARB: $($arb.FullName)")
  }
}

$sourceRoots = @("lib", "packages", "apps") | Where-Object { Test-Path $_ }
$dartFiles = foreach ($root in $sourceRoots) {
  Get-ChildItem $root -Recurse -File -Filter "*.dart" |
    Where-Object {
      $_.FullName -notmatch '\\lib\\l10n\\' -and
      $_.FullName -notmatch '\\test\\' -and
      $_.FullName -notmatch '\\build\\' -and
      $_.Name -notmatch '\.g\.dart$' -and
      $_.Name -ne 'generated_plugin_registrant.dart'
    }
}

foreach ($file in $dartFiles) {
  $content = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
  foreach ($term in $bannedTerms) {
    if ($content.Contains($term)) {
      $errors.Add("Banned Arabic term found in Dart source: $($file.FullName)")
      break
    }
  }
}

if ($StrictHardcodedArabic) {
  $hardcodedArabicRegex = '[''"][^''"]*[\u0600-\u06FF][^''"]*[''"]'
  foreach ($file in $dartFiles) {
    $content = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
    if ($content -match $hardcodedArabicRegex) {
      $errors.Add("Hardcoded Arabic literal detected in strict mode: $($file.FullName)")
      break
    }
  }
}

if ($errors.Count -gt 0) {
  Write-Host "Localization term check failed:" -ForegroundColor Red
  foreach ($entry in $errors) {
    Write-Host " - $entry" -ForegroundColor Red
  }
  exit 1
}

Write-Host "Localization term check passed." -ForegroundColor Green

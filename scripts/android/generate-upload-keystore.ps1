param(
  [string]$OutFile = "keys/maslaki-upload.jks",
  [string]$Alias = "upload",
  [int]$ValidityDays = 10000,
  [string]$KeyAlg = "RSA",
  [int]$KeySize = 2048
)

$targetDir = Split-Path -Parent $OutFile
if ($targetDir -and -not (Test-Path $targetDir)) {
  New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
}

Write-Host "Generating keystore: $OutFile"
Write-Host "Alias: $Alias"
Write-Host "You will be prompted for passwords by keytool."

& keytool -genkeypair `
  -v `
  -keystore $OutFile `
  -alias $Alias `
  -keyalg $KeyAlg `
  -keysize $KeySize `
  -validity $ValidityDays

Write-Host ""
Write-Host "Done. Next steps:"
Write-Host "1) Copy android/key.properties.example to android/key.properties"
Write-Host "2) Fill storePassword/keyPassword/keyAlias/storeFile"
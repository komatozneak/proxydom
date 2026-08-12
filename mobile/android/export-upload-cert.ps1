# Export upload certificate (.pem) for Play Console App Signing setup.
# Run from mobile\android after key.properties is filled:
#   .\export-upload-cert.ps1

$ErrorActionPreference = "Stop"
$keyProps = Join-Path $PSScriptRoot "key.properties"
if (-not (Test-Path $keyProps)) {
    Write-Error "Create key.properties first"
}
$lines = Get-Content $keyProps | Where-Object { $_ -match "=" -and -not $_.StartsWith("#") }
$cfg = @{}
foreach ($line in $lines) {
    $k, $v = $line -split "=", 2
    $cfg[$k.Trim()] = $v.Trim()
}
$storeFile = Join-Path $PSScriptRoot ($cfg["storeFile"] -replace "^\.\./", "")
if (-not (Test-Path $storeFile)) {
    $storeFile = Join-Path $PSScriptRoot "teremok-upload.jks"
}
$out = Join-Path $PSScriptRoot "upload_certificate.pem"
$keytool -export -rfc `
    -alias $cfg["keyAlias"] `
    -file $out `
    -keystore $storeFile `
    -storepass $cfg["storePassword"]
Write-Host "Written: $out"
Write-Host "Upload to Play Console if asked for upload key certificate."

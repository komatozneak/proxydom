# Build signed AAB for Google Play Internal testing.
# Prerequisite: key.properties with real passwords (not YOUR_STORE_PASSWORD_HERE).
#
#   cd mobile\android
#   notepad key.properties   # fill storePassword + keyPassword
#   cd ..
#   .\android\play-build.ps1

$ErrorActionPreference = "Stop"
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$keyProps = Join-Path $PSScriptRoot "key.properties"
$jks = Join-Path $PSScriptRoot "teremok-upload.jks"

if (-not (Test-Path $jks)) {
    Write-Error "Missing teremok-upload.jks in mobile\android"
}
if (-not (Test-Path $keyProps)) {
    Write-Error "Missing key.properties - copy from key.properties.template"
}
$text = Get-Content $keyProps -Raw
if ($text -match "YOUR_.*_PASSWORD_HERE") {
    Write-Error "Edit key.properties: replace YOUR_STORE_PASSWORD_HERE and YOUR_KEY_PASSWORD_HERE"
}

Write-Host "Building app bundle (release, signed)..."
# Release minify + resource shrink (incl. optimized shrinking on AGP 8.11) come
# from app/build.gradle.kts + gradle.properties. AGP 9 is a follow-up.
Push-Location (Join-Path $root "mobile")
try {
    flutter pub get
    flutter build appbundle --release
    $aab = "build\app\outputs\bundle\release\app-release.aab"
    if (Test-Path $aab) {
        $size = (Get-Item $aab).Length / 1MB
        Write-Host "OK: $aab ($([math]::Round($size, 1)) MB)"
        Write-Host "Play Console -> Internal testing -> Upload this AAB"
    } else {
        Write-Error "AAB not found after build"
    }
} finally {
    Pop-Location
}

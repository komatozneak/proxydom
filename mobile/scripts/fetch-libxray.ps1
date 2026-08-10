# Fetch prebuilt libXray.aar (gomobile) into android/app/libs/.
# Source: homa-games/libXray Maven mirror of XTLS/libXray.
# See docs/decisions/005-mobile-xray-core-migration.md
#
# HARD PIN: default 26.6.27. Do not bump past this without Marzban/VPS Xray
# lockstep + owner go. 26.7+ often fails Reality against our current server
# ("REALITY: received real certificate" → dial timeouts).
param(
    [string]$Version = $(if ($env:LIBXRAY_VERSION) { $env:LIBXRAY_VERSION } else { "26.6.27" })
)

$ErrorActionPreference = "Stop"
$Pinned = "26.6.27"
if ($Version -ne $Pinned) {
    Write-Warning "libXray pin is $Pinned; requested $Version — ensure Marzban/VPS Xray was upgraded (owner go)."
}

$Root = Split-Path -Parent $PSScriptRoot
$Out = Join-Path $Root "android\app\libs\libXray.aar"
$Url = "https://raw.githubusercontent.com/homa-games/libXray/repo/repo/io/github/homa-games/libXray/$Version/libXray-$Version.aar"

New-Item -ItemType Directory -Force -Path (Split-Path $Out) | Out-Null
Write-Host "Downloading libXray $Version → $Out"
Invoke-WebRequest -Uri $Url -OutFile $Out -UseBasicParsing
$Size = (Get-Item $Out).Length
Write-Host "OK: $Size bytes (pin policy: default $Pinned)"

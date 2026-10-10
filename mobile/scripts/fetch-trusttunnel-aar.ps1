# Fetch trusttunnel-client-android AAR into android/app/libs/.
# Source: GitHub Packages of TrustTunnel/TrustTunnelClient (no Maven Central
# publication; building from source needs Conan+CMake+NDK — avoid).
# The artefact is not on the Gradle classpath; see android/app/libs/README.md.
#
# REQUIRES: a GitHub PAT with `read:packages` scope in $env:GPR_KEY.
# Create at https://github.com/settings/tokens (read:packages, public_repo).
# The gh CLI keyring token usually LACKS read:packages (401) — use a PAT.
param(
    [string]$Version = $(if ($env:TT_CLIENT_VERSION) { $env:TT_CLIENT_VERSION } else { "1.1.5-rc.2" })
)

$ErrorActionPreference = "Stop"
$Pinned = "1.1.5-rc.2"
if ($Version -ne $Pinned) {
    Write-Warning "trusttunnel-client-android pin is $Pinned; requested $Version — owner go required."
}

if (-not $env:GPR_KEY) {
    Write-Error "GPR_KEY env var missing. Create a GitHub PAT with read:packages scope and set `$env:GPR_KEY."
}

$Root = Split-Path -Parent $PSScriptRoot
$Out = Join-Path $Root "android\app\libs\trusttunnel-client-android.aar"
$Url = "https://maven.pkg.github.com/TrustTunnel/TrustTunnelClient/com/adguard/trusttunnel/trusttunnel-client-android/$Version/trusttunnel-client-android-$Version.aar"

New-Item -ItemType Directory -Force -Path (Split-Path $Out) | Out-Null
Write-Host "Downloading trusttunnel-client-android $Version -> $Out"
$Headers = @{ Authorization = "Bearer $($env:GPR_KEY)" }
Invoke-WebRequest -Uri $Url -Headers $Headers -OutFile $Out -UseBasicParsing
$Size = (Get-Item $Out).Length
if ($Size -lt 1MB) {
    Remove-Item $Out -Force
    Write-Error "Downloaded $Size bytes — suspiciously small for a native AAR; deleted. Check token scope (read:packages) and version."
}
Write-Host "OK: $Size bytes (pin policy: default $Pinned)"

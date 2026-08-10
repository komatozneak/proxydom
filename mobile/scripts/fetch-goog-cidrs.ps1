# Fetch public Google IP ranges → mobile/assets/rules/youtube-google.cidr
#
# Source: https://www.gstatic.com/ipranges/goog.json (Google's published prefixes).
# Do NOT copy DedProxy youtube.txt / google.txt.
#
# Usage (from mobile/):
#   .\scripts\fetch-goog-cidrs.ps1

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $root "assets\rules"
$outFile = Join-Path $outDir "youtube-google.cidr"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$jsonPath = Join-Path $env:TEMP "teremok-goog.json"
Write-Host "Downloading goog.json..."
Invoke-WebRequest -Uri "https://www.gstatic.com/ipranges/goog.json" `
    -OutFile $jsonPath -UseBasicParsing

$data = Get-Content $jsonPath -Raw | ConvertFrom-Json
$cidrs = @(
    foreach ($p in $data.prefixes) {
        if ($p.ipv4Prefix) { $p.ipv4Prefix }
    }
) | Sort-Object -Unique

$generated = Get-Date -Format "yyyy-MM-dd"
$header = @(
    "# Teremok YouTube/Google force-proxy CIDRs",
    "# Source: https://www.gstatic.com/ipranges/goog.json",
    "# Generated: $generated",
    "# sync-token: $($data.syncToken)",
    "# ipv4 count: $($cidrs.Count)",
    "#"
    "# Regenerate: mobile/scripts/fetch-goog-cidrs.ps1",
    ""
)

Set-Content -Path $outFile -Value ($header + $cidrs) -Encoding utf8
Write-Host "Wrote $($cidrs.Count) IPv4 CIDRs → $outFile"

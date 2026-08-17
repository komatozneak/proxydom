# Download pinned hysteria.exe + wintun.dll (does not compile Hy2).
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Bin = Join-Path $Root "bin"
$Sums = Join-Path $Root "SHA256SUMS"
$HysteriaAsset = "hysteria-windows-amd64.exe"
$HysteriaBase = "https://github.com/apernet/hysteria/releases/download/app%2Fv2.6.2"
$WintunZipUrl = "https://www.wintun.net/builds/wintun-0.14.1.zip"
New-Item -ItemType Directory -Force -Path $Bin | Out-Null
Push-Location $Bin
try {

function Get-Sha256([string]$Path) {
    (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLowerInvariant()
}

function Get-PinnedSha([string]$Name) {
    $line = Get-Content -LiteralPath $Sums | Where-Object {
        $_ -match ('^[0-9a-f]{64}\s+' + [regex]::Escape($Name) + '$')
    } | Select-Object -First 1
    if (-not $line) { throw "SHA256SUMS missing pin for $Name" }
    return ($line -split "\s+")[0].ToLowerInvariant()
}

$HyPin = Get-PinnedSha $HysteriaAsset
$WintunZipSha = Get-PinnedSha "wintun-0.14.1.zip"

Write-Host "=== fetch hysteria app/v2.6.2 ==="
Invoke-WebRequest -UseBasicParsing -Uri "$HysteriaBase/hashes.txt" -OutFile "hashes.txt"
$HyLine = Get-Content "hashes.txt" |
    Where-Object { $_ -match '(^|\s)(build/)?hysteria-windows-amd64\.exe$' } |
    Where-Object { $_ -notmatch '-avx' } |
    Select-Object -Last 1
if (-not $HyLine) { throw "hashes.txt missing hysteria-windows-amd64.exe" }
$HySha = ($HyLine -split "\s+")[0].ToLowerInvariant()
if ($HySha -ne $HyPin) { throw "hashes.txt $HySha != SHA256SUMS pin $HyPin" }
Invoke-WebRequest -UseBasicParsing -Uri "$HysteriaBase/$HysteriaAsset" -OutFile $HysteriaAsset
$Got = Get-Sha256 $HysteriaAsset
if ($Got -ne $HyPin) { throw "hysteria hash mismatch $Got != $HyPin" }
Copy-Item -Force $HysteriaAsset "hysteria.exe"

Write-Host "=== fetch wintun 0.14.1 amd64 ==="
Invoke-WebRequest -UseBasicParsing -Uri $WintunZipUrl -OutFile "wintun-0.14.1.zip"
$ZipSha = Get-Sha256 "wintun-0.14.1.zip"
if ($ZipSha -ne $WintunZipSha) { throw "wintun zip hash mismatch $ZipSha != $WintunZipSha" }
$Extract = Join-Path $Bin "wintun-extract"
if (Test-Path $Extract) { Remove-Item -Recurse -Force $Extract }
Expand-Archive -Path "wintun-0.14.1.zip" -DestinationPath $Extract -Force
Copy-Item -Force (Join-Path $Extract "wintun\bin\amd64\wintun.dll") "wintun.dll"
$DllPin = Get-PinnedSha "wintun.dll"
$DllSha = Get-Sha256 "wintun.dll"
if ($DllSha -ne $DllPin) { throw "wintun.dll hash mismatch $DllSha != $DllPin" }
$License = Join-Path $Extract "wintun\LICENSE.txt"
if (Test-Path $License) {
    Copy-Item -Force $License "WINTUN-LICENSE.txt"
}
Remove-Item -Force "hashes.txt", $HysteriaAsset, "wintun-0.14.1.zip"
Remove-Item -Recurse -Force $Extract
Write-Host "OK $Bin\hysteria.exe $Bin\wintun.dll"
} finally {
    Pop-Location
}

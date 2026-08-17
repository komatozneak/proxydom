#Requires -Version 5.1
# Local SOCKS smoke: fetch bins, build host, connect, prove egress, exit.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
& "$PSScriptRoot\fetch-bins.ps1"
Get-ChildItem -LiteralPath (Join-Path $Root "bin") -File | Unblock-File
$env:CGO_ENABLED = "0"
go build -trimpath -ldflags="-s -w" -o "$Root\bin\teremok-host.exe" .\cmd\teremok-host
Write-Host "SOCKS connect + prove (exits after egress)..."
& "$Root\bin\teremok-host.exe" -bin-dir "$Root\bin" -mode socks -prove -headless -once
if ($LASTEXITCODE -ne 0) {
    throw "SOCKS prove failed with exit $LASTEXITCODE"
}
Write-Host @"
SOCKS prove OK.

TUN (UAC on hysteria.exe only; host stays unelevated):
  $($Root)\bin\teremok-host.exe -bin-dir $($Root)\bin -mode tun -prove -headless -once

Keep the tunnel up (Ctrl+C to stop):
  $($Root)\bin\teremok-host.exe -bin-dir $($Root)\bin -mode socks -headless
"@

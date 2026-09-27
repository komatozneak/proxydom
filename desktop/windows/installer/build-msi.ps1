# Visible per-machine MSI for Прокси Дом (ADR 023 / ADR 029).
# Humans get the Russian WiX wizard. Pass -Quiet only for CI.
param(
    [string]$Version = "1.0.0.1",
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
$Installer = $PSScriptRoot
$WindowsRoot = Split-Path $Installer -Parent
$Repo = Split-Path (Split-Path $WindowsRoot -Parent) -Parent
$Mobile = Join-Path $Repo "mobile"
$Service = Join-Path $WindowsRoot "service"
$ThirdParty = Join-Path $WindowsRoot "third_party"
$Payload = Join-Path $Installer "payload"
$OutDir = Join-Path $Installer "out"
$FlutterRelease = Join-Path $Mobile "build\windows\x64\runner\Release"

function Find-VcVars {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) { throw "Visual Studio Build Tools not found." }
    $root = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    $bat = Join-Path $root "VC\Auxiliary\Build\vcvars64.bat"
    if (-not (Test-Path $bat)) { throw "vcvars64.bat not found." }
    return $bat
}

function Ensure-WixExtension([string]$Name) {
    $listed = & wix extension list 2>&1 | Out-String
    if ($listed -notmatch [regex]::Escape($Name)) {
        & wix extension add -g "$Name/5.0.2"
        if ($LASTEXITCODE -ne 0) { throw "wix extension add $Name failed." }
    }
}

function Ensure-ThirdParty {
    New-Item -ItemType Directory -Force -Path $ThirdParty | Out-Null
    $sing = Join-Path $ThirdParty "sing-box.exe"
    $wintun = Join-Path $ThirdParty "wintun.dll"
    if (-not (Test-Path $sing)) {
        $zip = Join-Path $ThirdParty "sing-box.zip"
        $url = "https://github.com/SagerNet/sing-box/releases/download/v1.14.2/sing-box-1.14.2-windows-amd64.zip"
        Invoke-WebRequest -Uri $url -OutFile $zip
        $unpack = Join-Path $ThirdParty "sing-box-unpack"
        if (Test-Path $unpack) { Remove-Item $unpack -Recurse -Force }
        Expand-Archive -Path $zip -DestinationPath $unpack -Force
        $found = Get-ChildItem $unpack -Recurse -Filter "sing-box.exe" | Select-Object -First 1
        if (-not $found) { throw "sing-box.exe was not in the release zip." }
        Copy-Item $found.FullName $sing -Force
    }
    if (-not (Test-Path $wintun)) {
        $zip = Join-Path $ThirdParty "wintun.zip"
        Invoke-WebRequest -Uri "https://www.wintun.net/builds/wintun-0.14.1.zip" -OutFile $zip
        $unpack = Join-Path $ThirdParty "wintun-unpack"
        if (Test-Path $unpack) { Remove-Item $unpack -Recurse -Force }
        Expand-Archive -Path $zip -DestinationPath $unpack -Force
        $found = Get-ChildItem $unpack -Recurse -Filter "wintun.dll" | Where-Object { $_.FullName -match "amd64" } | Select-Object -First 1
        if (-not $found) { throw "wintun.dll amd64 was not in the zip." }
        Copy-Item $found.FullName $wintun -Force
    }
}

Write-Host "Building ProxyDomTunnelService"
$vcvars = Find-VcVars
New-Item -ItemType Directory -Force -Path $Payload | Out-Null
$serviceOut = Join-Path $Payload "ProxyDomTunnelService.exe"
Push-Location $Service
try {
    cmd /c "call `"$vcvars`" >nul && cl /nologo /std:c++17 /EHsc /W3 /DUNICODE /D_UNICODE /Fe:`"$serviceOut`" service.cpp protocol.cpp cleanup.cpp /link /SUBSYSTEM:WINDOWS ws2_32.lib iphlpapi.lib setupapi.lib advapi32.lib"
    if ($LASTEXITCODE -ne 0) { throw "Service compile failed." }
} finally {
    Pop-Location
}
Get-ChildItem $Service -Include *.obj,*.pdb -File | Remove-Item -Force

if (-not (Test-Path (Join-Path $FlutterRelease "proxy_dom.exe"))) {
    Write-Host "Building Flutter window"
    Push-Location $Mobile
    try {
        flutter build windows --release
        if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed." }
    } finally {
        Pop-Location
    }
}

Write-Host "Staging payload"
Get-ChildItem $Payload -Exclude "ProxyDomTunnelService.exe" | Remove-Item -Recurse -Force
Copy-Item (Join-Path $FlutterRelease "*") $Payload -Recurse -Force
Ensure-ThirdParty
Copy-Item (Join-Path $ThirdParty "sing-box.exe") $Payload -Force
Copy-Item (Join-Path $ThirdParty "wintun.dll") $Payload -Force

Ensure-WixExtension "WixToolset.UI.wixext"
Ensure-WixExtension "WixToolset.Util.wixext"

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$msi = Join-Path $OutDir "ProxyDom-$Version.msi"
$wixArgs = @(
    "build",
    (Join-Path $Installer "Product.wxs"),
    "-arch", "x64",
    "-culture", "ru-ru",
    "-ext", "WixToolset.UI.wixext",
    "-ext", "WixToolset.Util.wixext",
    "-d", "ProductVersion=$Version",
    "-d", "PayloadDir=$Payload",
    "-d", "InstallerDir=$Installer",
    "-out", $msi
)
if ($Quiet) { }
Write-Host "Building MSI"
& wix @wixArgs
if ($LASTEXITCODE -ne 0) { throw "wix build failed." }
Write-Host "MSI: $msi"

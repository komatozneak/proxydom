# Visible per-machine MSI for Прокси Дом (ADR 023 / ADR 029).
# Humans get the Russian WiX wizard. Pass -Quiet only for CI.
param(
    [string]$Version = "1.0.7.0",
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

# A native tool writing to stderr is not a failure. Under ErrorActionPreference
# "Stop" PowerShell promotes every CMake or WiX warning to a terminating error
# and the build dies on a harmless warning. Native calls are gated on
# $LASTEXITCODE instead; cmdlet failures keep the strict behaviour above.
function Invoke-Native {
    param([scriptblock]$Command, [string]$What)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & $Command
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
    }
    if ($code -ne 0) { throw "$What failed (exit $code)." }
}

$Installer = $PSScriptRoot
$WindowsRoot = Split-Path $Installer -Parent
$Repo = Split-Path (Split-Path $WindowsRoot -Parent) -Parent
$Mobile = Join-Path $Repo "mobile"
$Service = Join-Path $WindowsRoot "service"
$ThirdParty = Join-Path $WindowsRoot "third_party"
$Payload = Join-Path $Installer "payload"
$OutDir = Join-Path $Installer "out"
$FlutterRelease = Join-Path $Mobile "build\windows\x64\runner\Release"

function Find-Cmake {
    $cmd = Get-Command cmake -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    $root = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    $bundled = Join-Path $root "Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
    if (Test-Path $bundled) { return $bundled }
    throw "cmake was not found. Install the Visual Studio CMake component."
}

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

Write-Host "Building ProxyDomBroker and ProxyDomCtl"
$vcvars = Find-VcVars
$cmake = Find-Cmake
New-Item -ItemType Directory -Force -Path $Payload | Out-Null
$build = Join-Path $Service "build-release"
# A Debug cache links VCRUNTIME140D.dll. That DLL is not on another PC, so SCM cannot start the service.
if (Test-Path (Join-Path $build "CMakeCache.txt")) {
    $cache = Get-Content -LiteralPath (Join-Path $build "CMakeCache.txt") -Raw
    if ($cache -notmatch "CMAKE_BUILD_TYPE:STRING=Release") {
        Remove-Item -LiteralPath $build -Recurse -Force
    }
}
Invoke-Native { cmd /c "call `"$vcvars`" >nul && `"$cmake`" -S `"$Service`" -B `"$build`" -DCMAKE_BUILD_TYPE=Release && `"$cmake`" --build `"$build`" --config Release --target ProxyDomBroker ProxyDomCtl" } "CMake build"
$bin = Join-Path $build "Release"
if (-not (Test-Path (Join-Path $bin "ProxyDomBroker.exe"))) { $bin = $build }
Copy-Item (Join-Path $bin "ProxyDomBroker.exe") (Join-Path $Payload "ProxyDomBroker.exe") -Force
Copy-Item (Join-Path $bin "ProxyDomCtl.exe") (Join-Path $Payload "ProxyDomCtl.exe") -Force

if (-not (Test-Path (Join-Path $FlutterRelease "proxy_dom.exe"))) {
    Write-Host "Building Flutter window"
    Push-Location $Mobile
    try {
        Invoke-Native { flutter build windows --release } "flutter build windows"
    } finally {
        Pop-Location
    }
}

Write-Host "Staging payload"
Get-ChildItem $Payload -Exclude "ProxyDomBroker.exe","ProxyDomCtl.exe" | Remove-Item -Recurse -Force
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
Invoke-Native { & wix @wixArgs } "wix build"
Write-Host "MSI: $msi"

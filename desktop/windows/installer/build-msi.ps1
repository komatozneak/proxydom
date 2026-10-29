# Visible per-machine MSI for Прокси Дом (ADR 023 / ADR 029).
# Humans get the Russian WiX wizard. Pass -Quiet only for CI.
#
# -Version is mandatory on purpose. It used to carry a literal default, the
# literal went stale, and a build went out with the wrong version stamped into
# the MSI and its file name. A required parameter cannot go stale; the caller
# states the version every time, and there is no second place holding one.
#
# -Signing controls Authenticode signing. "auto" signs when a certificate is
# configured and warns when it is not, "require" refuses to ship an unsigned
# build, "off" skips signing for a local experiment. Windows 11 Smart App
# Control blocks unsigned executables, so a release is built with "require".
# docs/windows-signing.md has the certificate and environment variable list.
param(
    [Parameter(Mandatory = $true)]
    [string]$Version,
    [switch]$Quiet,
    [ValidateSet("auto", "require", "off")]
    [string]$Signing = "auto"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "signing.ps1")

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

# The signing identity is resolved before the first compile. A missing, expired
# or token-less certificate is a first-second mistake, and finding it after ten
# minutes of Flutter and CMake work is a waste of the build.
$signingConfiguration = $null
if ($Signing -ne "off") {
    $signingConfiguration = Resolve-ProxyDomSigningConfiguration
}
if ($Signing -eq "require" -and -not $signingConfiguration) {
    throw ("-Signing require was passed but no certificate is configured. Set " +
           "PROXYDOM_SIGN_THUMBPRINT, PROXYDOM_SIGN_PFX_PATH or the PROXYDOM_ARTIFACT_SIGNING_* " +
           "variables; docs/windows-signing.md has the details.")
}

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
    $wintun = Join-Path $ThirdParty "wintun.dll"
    # The prebuilt-binaries license travels with the DLL it covers.
    $wintunLicense = Join-Path $ThirdParty "wintun-LICENSE.txt"
    if (-not (Test-Path $wintun) -or -not (Test-Path $wintunLicense)) {
        $zip = Join-Path $ThirdParty "wintun.zip"
        Invoke-WebRequest -Uri "https://www.wintun.net/builds/wintun-0.14.1.zip" -OutFile $zip
        $unpack = Join-Path $ThirdParty "wintun-unpack"
        if (Test-Path $unpack) { Remove-Item $unpack -Recurse -Force }
        Expand-Archive -Path $zip -DestinationPath $unpack -Force
        $found = Get-ChildItem $unpack -Recurse -Filter "wintun.dll" | Where-Object { $_.FullName -match "amd64" } | Select-Object -First 1
        if (-not $found) { throw "wintun.dll amd64 was not in the zip." }
        Copy-Item $found.FullName $wintun -Force
        $license = Get-ChildItem $unpack -Recurse -Filter "LICENSE.txt" | Select-Object -First 1
        if (-not $license) { throw "LICENSE.txt was not in the Wintun zip." }
        Copy-Item $license.FullName $wintunLicense -Force
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

# A release build that already exists is not evidence that it is current. The
# Flutter window used to be built only when proxy_dom.exe was missing, so any
# build after the first packaged whatever binary was already sitting there — a
# merge could land in mobile/lib and the next MSI would ship the old AOT without
# a word. The build now always runs, and this is the backstop for the day someone
# reintroduces a skip.
#
# The check is on content, not on timestamps. Timestamps looked right and were
# wrong: a branch switch rewrites the mtime of every file in the tree, so the
# first version of this guard failed a build whose sources had not changed by a
# byte. What matters is whether the snapshot was made from the sources now on
# disk, and only a hash of those sources can answer that.
function Get-DartSourceStamp {
    param([string]$Root)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $files = @(Get-ChildItem (Join-Path $Root "lib") -Recurse -File -Filter *.dart)
    foreach ($name in @("pubspec.yaml", "pubspec.lock")) {
        $item = Get-Item (Join-Path $Root $name) -ErrorAction SilentlyContinue
        if ($item) { $files += $item }
    }
    $lines = foreach ($file in ($files | Sort-Object FullName)) {
        $relative = $file.FullName.Substring($Root.Length).Replace('\', '/')
        $digest = [System.BitConverter]::ToString(
            $sha.ComputeHash([System.IO.File]::ReadAllBytes($file.FullName))).Replace('-', '')
        "$relative $digest"
    }
    $body = [System.Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))
    return [System.BitConverter]::ToString($sha.ComputeHash($body)).Replace('-', '')
}

$stampFile = Join-Path $Mobile "build\.pd_source_stamp"
$stamp = Get-DartSourceStamp -Root $Mobile
$aot = Join-Path $FlutterRelease "data\app.so"
if (Test-Path $aot) {
    if (-not (Test-Path $stampFile)) {
        throw ("A Flutter build is present but nothing records which sources it came " +
               "from, so it cannot be vouched for. Run 'flutter clean' in mobile and " +
               "build again.")
    }
    $built = (Get-Content $stampFile -Raw).Trim()
    if ($built -ne $stamp) {
        throw ("Flutter snapshot is stale: data\app.so was built from sources with " +
               "stamp $built, and mobile now hashes to $stamp. The window would ship " +
               "code that no longer matches the repository. Run 'flutter clean' in " +
               "mobile and build again.")
    }
}
Write-Host "Building Flutter window"
Push-Location $Mobile
try {
    Invoke-Native { flutter build windows --release } "flutter build windows"
} finally {
    Pop-Location
}
if (-not (Test-Path $aot)) {
    throw "Flutter build produced no data\app.so, so there is nothing to package."
}
Set-Content -LiteralPath $stampFile -Value $stamp -NoNewline
Write-Host "Flutter snapshot checked: sources hash $stamp"

Write-Host "Staging payload"
Get-ChildItem $Payload -Exclude "ProxyDomBroker.exe","ProxyDomCtl.exe" | Remove-Item -Recurse -Force
Copy-Item (Join-Path $FlutterRelease "*") $Payload -Recurse -Force
Ensure-ThirdParty
Copy-Item (Join-Path $ThirdParty "wintun.dll") $Payload -Force
Copy-Item (Join-Path $ThirdParty "wintun-LICENSE.txt") $Payload -Force
Write-Host "Building proxydom-engine.exe"
$engineDir = Join-Path $Repo "mobile\android\hysteria-bind"
$prevGOOS = $env:GOOS
$prevGOARCH = $env:GOARCH
$prevCGO = $env:CGO_ENABLED
Push-Location $engineDir
try {
    $env:GOOS = "windows"
    $env:GOARCH = "amd64"
    $env:CGO_ENABLED = "0"
    Invoke-Native { go build -o (Join-Path $Payload "proxydom-engine.exe") ./cmd/proxydom-engine } "go build proxydom-engine"
} finally {
    Pop-Location
    if ($null -eq $prevGOOS) { Remove-Item Env:GOOS -ErrorAction SilentlyContinue } else { $env:GOOS = $prevGOOS }
    if ($null -eq $prevGOARCH) { Remove-Item Env:GOARCH -ErrorAction SilentlyContinue } else { $env:GOARCH = $prevGOARCH }
    if ($null -eq $prevCGO) { Remove-Item Env:CGO_ENABLED -ErrorAction SilentlyContinue } else { $env:CGO_ENABLED = $prevCGO }
}
# Also inside data\flutter_assets; a copy next to the executables is the one a
# person finds in Program Files.
Copy-Item (Join-Path $Mobile "assets\legal\THIRD-PARTY-NOTICES.md") $Payload -Force

Write-Host "Checking payload licenses"
$licenseCheck = Join-Path $Installer "check-payload-licenses.ps1"
Invoke-Native { & $licenseCheck -Payload $Payload } "Payload license check"

# The payload is signed before WiX packs it: an MSI whose files are signed after
# packaging would carry a hash mismatch, and a file signed after the MSI would
# never match what the MSI installs. The MSI itself gets its own signature after
# the build, which is the one SmartScreen looks at on download.
if ($signingConfiguration) {
    Write-Host "Signing payload with $($signingConfiguration.Description)"
    $signTargets = @(Get-ProxyDomPayloadSignTargets -Payload $Payload)
    $signed = @(Invoke-ProxyDomSigning -Files $signTargets -Configuration $signingConfiguration -SkipAlreadySigned)
    foreach ($item in $signed) {
        Write-Host ("  {0,-7} {1} <- {2}" -f $item.Action, (Split-Path $item.Path -Leaf), $item.Signer)
    }
    # A signature Windows does not trust is the same failure as no signature,
    # only harder to notice: every file we just signed is verified before it
    # enters the MSI. Files kept because they already carry a valid signature
    # are not ours to verify; some of them are catalog-signed by Microsoft and
    # have no embedded signature for signtool verify /pa to find.
    foreach ($item in @($signed | Where-Object { $_.Action -eq "signed" })) {
        $check = Test-ProxyDomSignature -Path $item.Path -ExpectedSubject $signingConfiguration.ExpectedSubject
        if (-not $check.IsValid) {
            throw ("'$($item.Path)' carries a signature Windows does not trust " +
                   "(status $($check.Status)). Smart App Control needs a certificate from the " +
                   "Microsoft Trusted Root Program; docs/windows-signing.md lists the options.")
        }
    }
    # Third-party binaries that keep their own publisher are expected here.
    # Anything unsigned at this point is a gap in the signature, not a warning.
    $unsigned = @(Get-ChildItem $Payload -File |
        Where-Object { $_.Extension -eq ".exe" -or $_.Extension -eq ".dll" } |
        Where-Object { (Get-AuthenticodeSignature -LiteralPath $_.FullName).Status -ne "Valid" })
    if ($unsigned.Count -gt 0) {
        Write-Warning ("Payload files without a trusted signature: " +
                       (($unsigned | Select-Object -ExpandProperty Name) -join ", "))
    }
} else {
    Write-Warning ("The MSI and its executables will be unsigned. Windows 11 Smart App Control " +
                   "blocks unsigned programs, and antivirus reputation has nothing to attach to. " +
                   "Build releases with -Signing require; see docs/windows-signing.md.")
}

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

if ($signingConfiguration) {
    Write-Host "Signing MSI"
    Invoke-ProxyDomSigning -Files @($msi) -Configuration $signingConfiguration | Out-Null
    $msiCheck = Test-ProxyDomSignature -Path $msi -ExpectedSubject $signingConfiguration.ExpectedSubject
    if (-not $msiCheck.IsValid) {
        throw ("The MSI signature does not validate (status $($msiCheck.Status)). It would be " +
               "delivered as an unknown publisher; docs/windows-signing.md explains why.")
    }
    Write-Host "MSI signed: $($msiCheck.Subject)"
} else {
    Write-Warning "MSI is unsigned: Windows will report an unknown publisher for the installer."
}

# Smart App Control blocks the unsigned build before a person ever sees the app,
# and the dialog offers no "run anyway". The explanation therefore has to sit
# next to the installer as a separate file: it is the only thing a blocked user
# can open. The page it duplicates is docs/guide/windows-sac.md.
$releaseReadme = Join-Path $Installer "README-RELEASE.txt"
if (Test-Path -LiteralPath $releaseReadme) {
    $readmeOut = Join-Path $OutDir "ProxyDom-$Version-README-RU.txt"
    Copy-Item -LiteralPath $releaseReadme -Destination $readmeOut -Force
    Write-Host "Instructions for users: $readmeOut"
}

# A hash next to the installer is the only check a user can run themselves while
# the build is unsigned: SmartScreen shows no publisher to compare against.
$msiHash = (Get-FileHash -LiteralPath $msi -Algorithm SHA256).Hash
$hashFile = "$msi.sha256"
Set-Content -LiteralPath $hashFile -Value ("{0}  {1}" -f $msiHash, (Split-Path $msi -Leaf)) -Encoding ASCII
Write-Host "SHA256: $msiHash"

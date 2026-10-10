# Build a production sideload APK from sources (upload keystore).
# Never re-signs an already-shipped APK. CI artifacts are not this script.
#
#   cd mobile\android
#   .\build-sideload.ps1

$ErrorActionPreference = "Stop"
$ProductionPackage = "com.proxy.dom"
$RequiredAbis = @("arm64-v8a", "armeabi-v7a", "x86_64")

$androidDir = $PSScriptRoot
$mobileDir = Split-Path $androidDir -Parent
$keyProps = Join-Path $androidDir "key.properties"
$jks = Join-Path $androidDir "teremok-upload.jks"
$q = [char]39

function Invoke-Flutter {
    param(
        [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)]
        [string[]]$FlutterArgs
    )
    $cmd = Get-Command flutter -ErrorAction Stop
    $bat = [System.IO.Path]::ChangeExtension($cmd.Source, ".bat")
    if (-not (Test-Path -LiteralPath $bat)) {
        $bat = $cmd.Source
    }
    Write-Host ('>> flutter {0}' -f ($FlutterArgs -join ' '))
    & $bat @FlutterArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Error ('flutter {0} failed with exit {1}' -f ($FlutterArgs -join ' '), $LASTEXITCODE)
    }
}

function Read-KeyProperty {
    param([string]$Name)
    $line = Get-Content -LiteralPath $keyProps | Where-Object { $_ -match "^$Name=" } | Select-Object -First 1
    if (-not $line) {
        Write-Error "key.properties missing $Name"
    }
    return ($line -split "=", 2)[1]
}

function Normalize-Sha256 {
    param([string]$Value)
    return (($Value -replace '[^0-9a-fA-F]', '')).ToLowerInvariant()
}

function Find-BuildTool {
    param([string]$Name)
    $sdk = $env:ANDROID_HOME
    if (-not $sdk) { $sdk = $env:ANDROID_SDK_ROOT }
    if (-not $sdk) { $sdk = Join-Path $env:LOCALAPPDATA "Android\Sdk" }
    $tools = Get-ChildItem -LiteralPath (Join-Path $sdk "build-tools") -Directory -ErrorAction Stop |
        Sort-Object Name
    foreach ($dir in ($tools | Sort-Object Name -Descending)) {
        $candidate = Join-Path $dir.FullName $Name
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }
    Write-Error "Android build-tools '$Name' not found under $sdk"
}

function Get-AaptField {
    param([string]$Text, [string]$Needle)
    if ([string]::IsNullOrEmpty($Text) -or $Text.IndexOf($Needle) -lt 0) {
        Write-Error "aapt output missing: $Needle"
    }
}

if (-not (Test-Path -LiteralPath $jks)) {
    Write-Error "Missing teremok-upload.jks in mobile\android"
}
if (-not (Test-Path -LiteralPath $keyProps)) {
    Write-Error "Missing key.properties. Copy from key.properties.template"
}
$keyText = Get-Content -LiteralPath $keyProps -Raw
if ($keyText -match "YOUR_.*_PASSWORD_HERE") {
    Write-Error "Edit key.properties: replace YOUR_STORE_PASSWORD_HERE and YOUR_KEY_PASSWORD_HERE"
}

# The APK links libs/hysteria-client.aar, not the Go source, and that archive is
# a build product kept out of git. Refuse to build a production APK from an
# archive that predates hy2bind: #317 shipped an engine that was 9 commits old
# exactly this way, and nothing complained.
$hy2bindDir = Join-Path $androidDir "hysteria-bind"
$hy2Aar = Join-Path $androidDir "app\libs\hysteria-client.aar"
Write-Host "Checking hysteria-client.aar against hy2bind..."
$prevEap = $ErrorActionPreference
$ErrorActionPreference = "Continue"
Push-Location $hy2bindDir
try {
    $stampOut = & go run ./cmd/aarstamp verify . "$hy2Aar" 2>&1
    $stampCode = $LASTEXITCODE
} finally {
    Pop-Location
    $ErrorActionPreference = $prevEap
}
if ($stampCode -ne 0) {
    Write-Host ($stampOut | Out-String)
    Write-Error ("hysteria-client.aar does not match hysteria-bind. Run: " +
        "bash mobile/android/hysteria-bind/build-aar.sh")
}
Write-Host ($stampOut | Out-String)

$storePass = Read-KeyProperty "storePassword"
$keyPass = Read-KeyProperty "keyPassword"
$alias = Read-KeyProperty "keyAlias"
$pubspec = Get-Content -LiteralPath (Join-Path $mobileDir "pubspec.yaml") -Raw
$versionPattern = '(?m)^version:\s*([0-9.]+)\+(\d+)'
if ($pubspec -notmatch $versionPattern) {
    Write-Error "Could not parse version from mobile/pubspec.yaml"
}
$expectedVersionName = $Matches[1]
$expectedVersionCode = $Matches[2]

$aapt = Find-BuildTool "aapt.exe"
$apksigner = Find-BuildTool "apksigner.bat"
$zipalign = Find-BuildTool "zipalign.exe"

Write-Host "Building production sideload APK..."
Push-Location $mobileDir
try {
    Invoke-Flutter pub get
    Invoke-Flutter gen-l10n
    Invoke-Flutter build apk --release
} finally {
    Pop-Location
}

$apkBuilt = Join-Path $mobileDir "build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path -LiteralPath $apkBuilt)) {
    Write-Error "APK not found: $apkBuilt"
}
$builtInfo = Get-Item -LiteralPath $apkBuilt
if ($builtInfo.Length -lt 1MB) {
    Write-Error ('APK too small ({0} bytes) at {1}' -f $builtInfo.Length, $apkBuilt)
}

# aapt/apksigner on a subst/mapped Z: path can report type=1 and skip native-code.
$apk = Join-Path $env:TEMP "proxydom-sideload-app-release.apk"
Copy-Item -LiteralPath $apkBuilt -Destination $apk -Force
$apkMb = [math]::Round((Get-Item -LiteralPath $apk).Length / 1MB, 1)
Write-Host ('Checking {0} ({1} MB)' -f (Split-Path $apk -Leaf), $apkMb)

$prevEap = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
    $aaptOut = & $aapt dump badging $apk 2>&1 | Out-String
    $aaptCode = $LASTEXITCODE
} finally {
    $ErrorActionPreference = $prevEap
}
if ($aaptCode -ne 0) {
    Write-Error ('aapt dump badging failed: {0}' -f $aaptOut)
}

Get-AaptField $aaptOut ("package: name=" + $q + $ProductionPackage + $q)
Get-AaptField $aaptOut ("versionCode=" + $q + $expectedVersionCode + $q)
Get-AaptField $aaptOut ("versionName=" + $q + $expectedVersionName + $q)
Get-AaptField $aaptOut ("sdkVersion:" + $q + "26" + $q)
if (-not [string]::IsNullOrEmpty($aaptOut) -and $aaptOut.IndexOf("application-debuggable") -ge 0) {
    Write-Error "APK is DEBUGGABLE. Refuse to publish."
}
foreach ($abi in $RequiredAbis) {
    Get-AaptField $aaptOut $abi
}

$prevEap = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$verifyFile = Join-Path $env:TEMP "proxydom-apksigner-out.txt"
$zipFile = Join-Path $env:TEMP "proxydom-zipalign-out.txt"
try {
    cmd.exe /c "`"$zipalign`" -c -P 16 4 `"$apk`" > `"$zipFile`" 2>&1"
    $zipCode = $LASTEXITCODE
    if ($zipCode -ne 0) {
        Write-Host "16 KB zipalign failed, checking 4 KB..."
        cmd.exe /c "`"$zipalign`" -c 4 `"$apk`" > `"$zipFile`" 2>&1"
        $zipCode = $LASTEXITCODE
    }
    cmd.exe /c "`"$apksigner`" verify --verbose --print-certs `"$apk`" > `"$verifyFile`" 2>&1"
    $verifyCode = $LASTEXITCODE
} finally {
    $ErrorActionPreference = $prevEap
}
if ($zipCode -ne 0) {
    Write-Error "zipalign check failed"
}
if ($verifyCode -ne 0) {
    Write-Error "apksigner verify failed"
}
$verifyText = Get-Content -LiteralPath $verifyFile -Raw -ErrorAction Stop
if ($verifyText -notlike "*Verified using v2 scheme (APK Signature Scheme v2): true*") {
    Write-Error "APK is missing APK Signature Scheme v2"
}
if ([string]::IsNullOrWhiteSpace($keyPass)) {
    Write-Error "keyPassword empty"
}
$apkShaLine = (
    $verifyText -split "`r?`n" |
        Where-Object { $_ -like "*certificate SHA-256 digest:*" -and $_ -notlike "*public key*" } |
        Select-Object -First 1
)
if (-not $apkShaLine) { Write-Error "Could not read APK signer SHA-256" }
$apkSha = Normalize-Sha256 (($apkShaLine -split "digest:", 2)[-1])

$prevEap = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
    $keytoolOut = & keytool -list -v -keystore $jks -alias $alias -storepass $storePass 2>&1
    $keytoolCode = $LASTEXITCODE
} finally {
    $ErrorActionPreference = $prevEap
}
if ($keytoolCode -ne 0) {
    Write-Error "keytool -list failed (wrong alias/password?)"
}
$ksShaLine = ($keytoolOut | Select-String -Pattern "SHA256:" | Select-Object -First 1).ToString()
if (-not $ksShaLine) { Write-Error "Could not read keystore SHA-256" }
$ksSha = Normalize-Sha256 (($ksShaLine -split "SHA256:", 2)[-1])
if ($apkSha -ne $ksSha) {
    Write-Error "APK signer SHA-256 does not match teremok-upload.jks"
}

# Do not print passwords. Fingerprints are public (same as Play upload cert).
$sizeMb = [math]::Round((Get-Item -LiteralPath $apkBuilt).Length / 1MB, 1)
Write-Host ('OK: {0} ({1} MB)' -f $apkBuilt, $sizeMb)
Write-Host ('package={0} version={1}+{2} minSdk=26' -f $ProductionPackage, $expectedVersionName, $expectedVersionCode)
Write-Host ('signerSha256={0}' -f $apkSha)
Write-Host "Upload the APK above to the proxydom.su downloads directory (do not use android-apk-ci)."

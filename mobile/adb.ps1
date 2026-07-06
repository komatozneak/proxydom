# Teremok Connect — adb wrapper (Windows: adb не в PATH по умолчанию)
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
if (-not (Test-Path $adb)) {
    Write-Error "adb not found: $adb"
    exit 1
}
& $adb @args

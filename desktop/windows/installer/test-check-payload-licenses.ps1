# Proves check-payload-licenses.ps1 fails on the payloads it exists to stop,
# and that the sing-box ratchet has all three outcomes. CI has no real payload:
# build-msi.ps1 stages it on the owner's PC and runs the same check before WiX.
$ErrorActionPreference = "Stop"

$check = Join-Path $PSScriptRoot "check-payload-licenses.ps1"
$work = Join-Path ([System.IO.Path]::GetTempPath()) ("payload-check-" + [guid]::NewGuid())

function New-Binary([string]$Path, [string]$Body = "") {
    New-Item -ItemType Directory -Force -Path (Split-Path $Path -Parent) | Out-Null
    $bytes = [byte[]](0x4D, 0x5A) + [System.Text.Encoding]::ASCII.GetBytes("`0" + $Body)
    [System.IO.File]::WriteAllBytes($Path, $bytes)
}

# The migration payload: sing-box.exe is present, so the known-violation entry
# is satisfied and the check warns instead of failing.
function New-CleanPayload([string]$Name) {
    $dir = Join-Path $work $Name
    foreach ($exe in @("ProxyDomBroker.exe", "ProxyDomCtl.exe", "proxy_dom.exe",
                       "flutter_windows.dll", "rive_native.dll", "wintun.dll")) {
        New-Binary (Join-Path $dir $exe)
    }
    $aot = Join-Path $dir "data/app.so"
    New-Item -ItemType Directory -Force -Path (Split-Path $aot -Parent) | Out-Null
    [System.IO.File]::WriteAllBytes($aot, [byte[]](0x7F, 0x45, 0x4C, 0x46, 0x02))
    New-Item -ItemType Directory -Force -Path (Join-Path $dir "data/flutter_assets") | Out-Null
    Set-Content -LiteralPath (Join-Path $dir "data/flutter_assets/NOTICES.Z") -Value "notices"
    Set-Content -LiteralPath (Join-Path $dir "THIRD-PARTY-NOTICES.md") -Value "# Third-party notices"
    return $dir
}

$script:SingBox = "Go buildinf: path github.com/sagernet/sing-box/cmd/sing-box"
$script:Xray = "Go buildinf: path github.com/xtls/xray-core/cmd/xray"
$cases = @(
    @{ Name = "clean payload has no sing-box"; Want = 0
       MustContain = "Payload license check passed"
       Setup = { param($d) } },
    @{ Name = "ratchet: entry deleted and sing-box.exe present"; Want = 1
       Known = @{}; MustContain = "FAIL sing-box.exe embeds github.com/sagernet/"
       Setup = { param($d) New-Binary (Join-Path $d "sing-box.exe") $script:SingBox } },
    @{ Name = "ratchet: entry present and sing-box.exe absent"; Want = 1
       Known = @{ "sing-box.exe" = "removed by task 05" }
       MustContain = "sing-box.exe is listed but the binary is not in the payload"
       Setup = { param($d) } },
    @{ Name = "sing-box bytes under an allowed name"; Want = 1
       MustContain = "FAIL wintun.dll embeds github.com/sagernet/"
       Setup = { param($d) New-Binary (Join-Path $d "wintun.dll") $script:SingBox } },
    @{ Name = "xray bytes under an allowed name"; Want = 1
       MustContain = "FAIL wintun.dll embeds github.com/xtls/xray-core"
       Setup = { param($d) New-Binary (Join-Path $d "wintun.dll") $script:Xray } },
    @{ Name = "sing-box hidden in a subfolder without an extension"; Want = 1
       MustContain = "FAIL data/engine embeds github.com/sagernet/"
       Setup = { param($d) New-Binary (Join-Path $d "data/engine") $script:SingBox } },
    @{ Name = "unreviewed dll"; Want = 1
       MustContain = "FAIL libbox.dll is not on the reviewed list"
       Setup = { param($d) New-Binary (Join-Path $d "libbox.dll") } },
    @{ Name = "executable disguised as data"; Want = 1
       MustContain = "FAIL data/core.dat is not on the reviewed list"
       Setup = { param($d) New-Binary (Join-Path $d "data/core.dat") } },
    @{ Name = "allowed name in another case"; Want = 0
       MustContain = "ok   WINTUN.DLL"
       Setup = { param($d) Remove-Item (Join-Path $d "wintun.dll"); New-Binary (Join-Path $d "WINTUN.DLL") } }
)

$failed = 0
try {
    $i = 0
    foreach ($case in $cases) {
        $i++
        $dir = New-CleanPayload "case$i"
        & $case.Setup $dir
        Write-Host "--- $($case.Name)"
        $params = @{ Payload = $dir }
        if ($case.ContainsKey('Known')) { $params.KnownViolations = $case.Known }
        # Write-Host goes to the information stream, so *>&1 is what captures it.
        $out = (& $check @params *>&1 | Out-String)
        $got = $LASTEXITCODE
        Write-Host $out.TrimEnd()
        if ($got -ne $case.Want) {
            Write-Host "WRONG: $($case.Name) exited $got, want $($case.Want)"
            $failed++
        } elseif ($case.MustContain -and -not $out.Contains($case.MustContain)) {
            Write-Host "WRONG: $($case.Name) output lacks [$($case.MustContain)]"
            $failed++
        }
    }
    Write-Host "--- missing payload directory"
    & $check -Payload (Join-Path $work "absent")
    if ($LASTEXITCODE -ne 1) {
        Write-Host "WRONG: a missing payload exited $LASTEXITCODE, want 1"
        $failed++
    }
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failed -gt 0) {
    Write-Host "check-payload-licenses.ps1 self-test: $failed case(s) wrong."
    exit 1
}
Write-Host "check-payload-licenses.ps1 self-test passed: $($cases.Count + 1) cases."
exit 0

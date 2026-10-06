# Fails when the MSI payload carries a binary nobody has reviewed, or a binary
# that embeds a GPL Go module under any file name (ADR 036).
#
#   pwsh -File check-payload-licenses.ps1 [-Payload <dir>]
#
# Exit 0: every binary is on the reviewed list, or is a known violation that
# still has an entry below. Exit 1: anything else, a known violation whose
# entry was already deleted, a known-violation entry whose binary is gone,
# or a missing payload. An empty check can never pass for a real payload.
param(
    [string]$Payload = (Join-Path $PSScriptRoot "payload"),
    # Tests pass their own table. Omitted means the table below.
    [hashtable]$KnownViolations
)

$ErrorActionPreference = "Stop"

# Every binary the MSI may carry, by path relative to the payload, with the
# license it ships under. Add an entry only after reading that license; a
# copyleft or non-commercial license does not get an entry at all.
$Allowed = @{
    "ProxyDomBroker.exe"                        = "Proxy Dom service, own code"
    "ProxyDomCtl.exe"                           = "Proxy Dom controller, own code"
    "proxy_dom.exe"                             = "Proxy Dom window, own code on the Flutter runner (BSD-3-Clause)"
    "flutter_windows.dll"                       = "Flutter engine, BSD-3-Clause; notices in data/flutter_assets/NOTICES.Z"
    "data/app.so"                               = "Dart AOT snapshot of the window; Dart package notices in NOTICES.Z"
    "app_links_plugin.dll"                      = "app_links, Apache-2.0"
    "flutter_secure_storage_windows_plugin.dll" = "flutter_secure_storage_windows, BSD-3-Clause"
    "rive_native_plugin.dll"                    = "rive_native, MIT"
    "rive_native.dll"                           = "rive_native runtime, MIT"
    "share_plus_plugin.dll"                     = "share_plus, BSD-3-Clause"
    "url_launcher_windows_plugin.dll"           = "url_launcher_windows, BSD-3-Clause"
    "dartjni.dll"                               = "jni, BSD-3-Clause"
    # Not on the ADR 036 permissive list and not copyleft: WireGuard LLC lets
    # it be redistributed unmodified next to software that only calls wintun.h.
    "wintun.dll"                                = "Wintun Prebuilt Binaries License (WireGuard LLC)"
}

# Copyleft binaries that still ship. Each entry names the task that removes it.
# The entry MUST be deleted by that task; while it is present the check warns
# instead of failing so Windows keeps working during the migration.
# Three outcomes, matched by file name:
#   entry and binary both present  -> warning, and the check can still pass;
#   binary present, entry deleted  -> failure (the binary came back);
#   entry present, binary absent   -> failure (the entry is stale).
if (-not $PSBoundParameters.ContainsKey('KnownViolations')) {
    $KnownViolations = @{
        "sing-box.exe" = "removed by docs/ops/engine-migration/05-windows-engine-swap.md"
    }
}

# Go module paths that mark a GPL engine inside a binary, whatever it is named.
$ForbiddenMarkers = @("github.com/sagernet/")

$BinaryExtensions = @(".exe", ".dll", ".sys", ".so")

function Test-BinaryHeader([string]$Path) {
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $head = New-Object byte[] 4
        $read = $stream.Read($head, 0, 4)
    } finally {
        $stream.Dispose()
    }
    if ($read -ge 2 -and $head[0] -eq 0x4D -and $head[1] -eq 0x5A) { return $true }  # MZ (PE)
    if ($read -eq 4 -and $head[0] -eq 0x7F -and $head[1] -eq 0x45 -and
        $head[2] -eq 0x4C -and $head[3] -eq 0x46) { return $true }                # ELF
    return $false
}

function Find-ForbiddenMarker([string]$Path) {
    # Latin-1 maps every byte to one char, so an ordinal search finds ASCII
    # module paths in the raw image.
    $latin1 = [System.Text.Encoding]::GetEncoding(28591)
    $text = $latin1.GetString([System.IO.File]::ReadAllBytes($Path))
    foreach ($marker in $ForbiddenMarkers) {
        if ($text.IndexOf($marker, [System.StringComparison]::Ordinal) -ge 0) { return $marker }
    }
    return $null
}

if (-not (Test-Path -LiteralPath $Payload -PathType Container)) {
    Write-Host "FAIL payload directory not found: $Payload"
    exit 1
}
$root = (Resolve-Path -LiteralPath $Payload).Path

$failures = 0
$checked = 0
$presentViolations = @{}
foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File | Sort-Object FullName) {
    $extension = [System.IO.Path]::GetExtension($file.Name).ToLowerInvariant()
    if (-not ($BinaryExtensions -contains $extension) -and -not (Test-BinaryHeader $file.FullName)) {
        continue
    }
    $checked++
    $relative = $file.FullName.Substring($root.Length).TrimStart('\', '/').Replace('\', '/')
    $license = $Allowed[$relative]
    $marker = Find-ForbiddenMarker $file.FullName
    $task = $KnownViolations[$file.Name]
    if ($task) {
        # One entry covers every copy of that file name. A second copy under
        # another name still fails the checks below.
        $presentViolations[$file.Name] = $true
        $msg = "known payload violation ${relative}: $task"
        Write-Host "WARNING $msg"
        if ($env:GITHUB_ACTIONS -eq "true") {
            Write-Host "::warning title=License guard::$msg"
        }
    } elseif ($marker) {
        Write-Host "FAIL $relative embeds $marker (GPL Go module, ADR 036)"
        $failures++
    } elseif (-not $license) {
        Write-Host "FAIL $relative is not on the reviewed list in check-payload-licenses.ps1"
        $failures++
    } else {
        Write-Host "ok   $relative ($license)"
    }
}

foreach ($name in @($KnownViolations.Keys)) {
    if ($presentViolations.ContainsKey($name)) { continue }
    Write-Host ("FAIL known payload violation $name is listed but the binary is not in the payload; " +
        "delete the entry ($($KnownViolations[$name]))")
    $failures++
}

if ($failures -gt 0) {
    Write-Host "Payload license check failed: $failures of $checked binaries."
    exit 1
}
Write-Host "Payload license check passed: $checked binaries."
exit 0

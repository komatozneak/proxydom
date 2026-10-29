# Authenticode signing for the Windows build.
#
# Smart App Control refuses an executable unless Microsoft's app intelligence
# already knows the file or the file carries a signature from a CA in the
# Microsoft Trusted Root Program. An unsigned proxy_dom.exe is blocked on every
# Windows 11 machine where the feature is on, and an unsigned MSI is blocked one
# step earlier. docs/windows-signing.md covers which certificate fixes that and
# which one only looks like it does.
#
# Three signing identities are supported because the build must not care which
# one the publisher ends up with: a certificate already in the Windows store
# (USB token or HSM), a PFX file, and Azure Artifact Signing (formerly Trusted
# Signing), where the private key never reaches this machine.
#
# Every path here finishes by reading the signature back, because SignTool
# returning 0 only means the signature was written. Whether Windows trusts the
# chain is a separate question, answered by Test-ProxyDomSignature: a build that
# skips that check can ship a file that still says "unknown publisher".

function Get-ProxyDomSignTool {
    [CmdletBinding()]
    param([string]$Path)

    if ($Path) {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw "signtool was not found at '$Path'."
        }
        return (Resolve-Path -LiteralPath $Path).Path
    }

    if ($env:PROXYDOM_SIGNTOOL) {
        if (-not (Test-Path -LiteralPath $env:PROXYDOM_SIGNTOOL -PathType Leaf)) {
            throw "PROXYDOM_SIGNTOOL points at '$env:PROXYDOM_SIGNTOOL', which does not exist."
        }
        return (Resolve-Path -LiteralPath $env:PROXYDOM_SIGNTOOL).Path
    }

    $onPath = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if (-not $onPath) { $onPath = Get-Command signtool -ErrorAction SilentlyContinue }
    if ($onPath) { return $onPath.Source }

    # SignTool ships with the Windows SDK, not with Windows itself. The x64 build
    # is the one the Artifact Signing dlib requires, so x64 is the only candidate.
    $roots = @()
    if (${env:ProgramFiles(x86)}) {
        $roots += (Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\bin")
    }
    if ($env:ProgramFiles) {
        $roots += (Join-Path $env:ProgramFiles "Windows Kits\10\bin")
    }
    $candidates = foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        Get-ChildItem -LiteralPath $root -Directory |
            Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
            Sort-Object { [version]$_.Name } -Descending |
            ForEach-Object { Join-Path $_.FullName "x64\signtool.exe" }
    }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }

    throw ("signtool.exe was not found. Install the Windows SDK (Visual Studio " +
           "Installer -> Windows 10/11 SDK) or set PROXYDOM_SIGNTOOL to its path.")
}

function Invoke-SignToolCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SignTool,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$What
    )

    # A native tool writing to stderr is not a failure. Under
    # ErrorActionPreference "Stop" PowerShell turns the first SignTool warning
    # into a terminating error and hides the exit code that actually matters.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & $SignTool @Arguments 2>&1 | Out-String
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
    }
    if ($code -ne 0) {
        throw "$What failed (exit $code).`n$($output.Trim())"
    }
    return $output
}

function Find-ProxyDomSigningCertificate {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Thumbprint)

    $wanted = ($Thumbprint -replace '\s', '').ToUpperInvariant()
    foreach ($store in @("Cert:\CurrentUser\My", "Cert:\LocalMachine\My")) {
        $match = Get-ChildItem -Path $store -ErrorAction SilentlyContinue |
            Where-Object { $_.Thumbprint -eq $wanted }
        if (-not $match) { continue }
        if (-not $match.HasPrivateKey) {
            throw ("The certificate $wanted is in $store but its private key is not " +
                   "available. A token that is not plugged in looks exactly like this.")
        }
        return [pscustomobject]@{
            Certificate = $match
            MachineStore = ($store -like "*LocalMachine*")
        }
    }
    return $null
}

function Resolve-ProxyDomSigningConfiguration {
    [CmdletBinding()]
    param(
        [ValidateSet("Auto", "Pfx", "Store", "ArtifactSigning", "None")]
        [string]$Method = "Auto",
        [string]$PfxPath,
        [string]$PfxPassword,
        [string]$Thumbprint,
        [string]$ArtifactSigningEndpoint,
        [string]$ArtifactSigningAccount,
        [string]$ArtifactSigningProfile,
        [string]$ArtifactSigningDlib,
        [string]$TimestampUrl,
        [string]$ExpectedSubject
    )

    if (-not $PfxPath) { $PfxPath = $env:PROXYDOM_SIGN_PFX_PATH }
    if (-not $PfxPassword) { $PfxPassword = $env:PROXYDOM_SIGN_PFX_PASSWORD }
    if (-not $Thumbprint) { $Thumbprint = $env:PROXYDOM_SIGN_THUMBPRINT }
    if (-not $ArtifactSigningEndpoint) { $ArtifactSigningEndpoint = $env:PROXYDOM_ARTIFACT_SIGNING_ENDPOINT }
    if (-not $ArtifactSigningAccount) { $ArtifactSigningAccount = $env:PROXYDOM_ARTIFACT_SIGNING_ACCOUNT }
    if (-not $ArtifactSigningProfile) { $ArtifactSigningProfile = $env:PROXYDOM_ARTIFACT_SIGNING_PROFILE }
    if (-not $ArtifactSigningDlib) { $ArtifactSigningDlib = $env:PROXYDOM_ARTIFACT_SIGNING_DLIB }
    if (-not $TimestampUrl) { $TimestampUrl = $env:PROXYDOM_SIGN_TIMESTAMP_URL }
    if (-not $ExpectedSubject) { $ExpectedSubject = $env:PROXYDOM_SIGN_EXPECTED_SUBJECT }

    if ($Method -eq "None") { return $null }

    $artifactSigningRequested = ($ArtifactSigningEndpoint -or $ArtifactSigningAccount -or
                                 $ArtifactSigningProfile -or $ArtifactSigningDlib)
    $configured = @()
    if ($PfxPath) { $configured += "Pfx" }
    if ($Thumbprint) { $configured += "Store" }
    if ($artifactSigningRequested) { $configured += "ArtifactSigning" }

    if ($Method -eq "Auto") {
        if ($configured.Count -eq 0) { return $null }
        if ($configured.Count -gt 1) {
            throw ("More than one signing identity is configured ($($configured -join ', ')). " +
                   "Keep one set of variables, or name the one to use with -Method.")
        }
        $Method = $configured[0]
    } elseif ($configured -notcontains $Method) {
        throw ("Signing method '$Method' was requested but its settings are missing. " +
               "Configured: $(if ($configured.Count) { $configured -join ', ' } else { 'nothing' }).")
    }

    $configuration = [pscustomobject]@{
        Method = $Method
        TimestampUrl = $TimestampUrl
        ExpectedSubject = $ExpectedSubject
        PfxPath = $null
        PfxPassword = $null
        Thumbprint = $null
        MachineStore = $false
        CertificateThumbprint = $null
        ArtifactSigningEndpoint = $null
        ArtifactSigningAccount = $null
        ArtifactSigningProfile = $null
        ArtifactSigningDlib = $null
        Description = $null
    }

    switch ($Method) {
        "Pfx" {
            if (-not (Test-Path -LiteralPath $PfxPath -PathType Leaf)) {
                throw "PROXYDOM_SIGN_PFX_PATH points at '$PfxPath', which does not exist."
            }
            $resolved = (Resolve-Path -LiteralPath $PfxPath).Path
            # Opening the PFX here turns a wrong password into one clear sentence
            # instead of a SignTool traceback after the build has done its work.
            try {
                $certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList $resolved, $PfxPassword
            } catch {
                throw "The PFX '$resolved' could not be opened. Wrong password, or not a PFX: $($_.Exception.Message)"
            }
            try {
                $subject = $certificate.Subject
                $thumbprint = $certificate.Thumbprint
                $expires = $certificate.NotAfter
            } finally {
                $certificate.Dispose()
            }
            if ($expires -lt (Get-Date)) {
                throw "The PFX certificate '$subject' expired on $($expires.ToString('yyyy-MM-dd'))."
            }
            $configuration.PfxPath = $resolved
            $configuration.PfxPassword = $PfxPassword
            $configuration.CertificateThumbprint = $thumbprint
            if (-not $TimestampUrl) { $configuration.TimestampUrl = "http://timestamp.digicert.com" }
            $configuration.Description = "PFX $resolved, $subject, expires $($expires.ToString('yyyy-MM-dd'))"
        }
        "Store" {
            if (-not $Thumbprint) {
                throw "The Store signing method needs a thumbprint: set PROXYDOM_SIGN_THUMBPRINT or pass -Thumbprint."
            }
            $found = Find-ProxyDomSigningCertificate -Thumbprint $Thumbprint
            if (-not $found) {
                throw ("No code-signing certificate with thumbprint $Thumbprint was found in " +
                       "CurrentUser\My or LocalMachine\My. certmgr.msc lists what is installed.")
            }
            if ($found.Certificate.NotAfter -lt (Get-Date)) {
                throw "The certificate '$($found.Certificate.Subject)' expired on $($found.Certificate.NotAfter.ToString('yyyy-MM-dd'))."
            }
            $configuration.Thumbprint = ($Thumbprint -replace '\s', '').ToUpperInvariant()
            $configuration.MachineStore = $found.MachineStore
            $configuration.CertificateThumbprint = $found.Certificate.Thumbprint
            if (-not $TimestampUrl) { $configuration.TimestampUrl = "http://timestamp.digicert.com" }
            $configuration.Description = ("store certificate $($found.Certificate.Subject), " +
                                          "expires $($found.Certificate.NotAfter.ToString('yyyy-MM-dd'))")
        }
        "ArtifactSigning" {
            $missing = @()
            if (-not $ArtifactSigningEndpoint) { $missing += "PROXYDOM_ARTIFACT_SIGNING_ENDPOINT" }
            if (-not $ArtifactSigningAccount) { $missing += "PROXYDOM_ARTIFACT_SIGNING_ACCOUNT" }
            if (-not $ArtifactSigningProfile) { $missing += "PROXYDOM_ARTIFACT_SIGNING_PROFILE" }
            if (-not $ArtifactSigningDlib) { $missing += "PROXYDOM_ARTIFACT_SIGNING_DLIB" }
            if ($missing.Count -gt 0) {
                throw "Artifact Signing is missing: $($missing -join ', '). See docs/windows-signing.md."
            }
            if (-not (Test-Path -LiteralPath $ArtifactSigningDlib -PathType Leaf)) {
                throw ("PROXYDOM_ARTIFACT_SIGNING_DLIB points at '$ArtifactSigningDlib', which " +
                       "does not exist. The dlib comes with the Artifact Signing Client Tools " +
                       "(winget install -e --id Microsoft.Azure.ArtifactSigningClientTools).")
            }
            $configuration.ArtifactSigningEndpoint = $ArtifactSigningEndpoint
            $configuration.ArtifactSigningAccount = $ArtifactSigningAccount
            $configuration.ArtifactSigningProfile = $ArtifactSigningProfile
            $configuration.ArtifactSigningDlib = (Resolve-Path -LiteralPath $ArtifactSigningDlib).Path
            if (-not $TimestampUrl) { $configuration.TimestampUrl = "http://timestamp.acs.microsoft.com" }
            $configuration.Description = ("Azure Artifact Signing $ArtifactSigningAccount/$ArtifactSigningProfile " +
                                          "at $ArtifactSigningEndpoint")
        }
        default {
            throw "Unknown signing method '$Method'."
        }
    }

    if (-not $configuration.TimestampUrl -and $Method -eq "ArtifactSigning") {
        throw "Artifact Signing certificates are short-lived; a timestamp URL is mandatory."
    }
    return $configuration
}

function Get-ProxyDomPayloadSignTargets {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Payload)

    if (-not (Test-Path -LiteralPath $Payload -PathType Container)) {
        throw "The payload directory '$Payload' does not exist."
    }
    # Only the root of the payload is code the loader maps. data\ holds the Dart
    # AOT snapshot and assets. wintun.dll is WireGuard's binary and keeps its own
    # signature: re-signing it would claim a publisher that did not build it.
    Get-ChildItem -LiteralPath $Payload -File |
        Where-Object { $_.Extension -eq ".exe" -or ($_.Extension -eq ".dll" -and $_.Name -ne "wintun.dll") } |
        Select-Object -ExpandProperty FullName
}

function Invoke-ProxyDomSigning {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string[]]$Files,
        [Parameter(Mandatory = $true)]$Configuration,
        [string]$SignTool,
        [switch]$SkipAlreadySigned,
        [switch]$NoTimestamp
    )

    $tool = Get-ProxyDomSignTool -Path $SignTool
    if ($NoTimestamp -and $Configuration.Method -eq "ArtifactSigning") {
        throw ("Artifact Signing certificates live for three days, so an unstamped " +
               "signature stops validating almost immediately. Timestamping is not " +
               "optional for that method.")
    }

    $metadataPath = $null
    if ($Configuration.Method -eq "ArtifactSigning") {
        $metadataPath = Join-Path ([System.IO.Path]::GetTempPath()) ("proxydom-signing-" + [guid]::NewGuid().ToString("N") + ".json")
        $metadata = [ordered]@{
            Endpoint = $Configuration.ArtifactSigningEndpoint
            CodeSigningAccountName = $Configuration.ArtifactSigningAccount
            CertificateProfileName = $Configuration.ArtifactSigningProfile
        } | ConvertTo-Json
        # The dlib reads this file itself; a BOM that PowerShell's own
        # "-Encoding utf8" adds is not part of the JSON grammar.
        [System.IO.File]::WriteAllText($metadataPath, $metadata, (New-Object System.Text.UTF8Encoding($false)))
    }

    $results = @()
    try {
        foreach ($file in $Files) {
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
                throw "Nothing to sign at '$file'."
            }
            $resolved = (Resolve-Path -LiteralPath $file).Path
            $before = Get-AuthenticodeSignature -LiteralPath $resolved
            if ($SkipAlreadySigned -and $before.Status -eq "Valid") {
                $results += [pscustomobject]@{
                    Path = $resolved
                    Action = "kept"
                    Signer = $before.SignerCertificate.Subject
                }
                continue
            }

            $arguments = @("sign", "/v", "/fd", "SHA256")
            switch ($Configuration.Method) {
                "Pfx" {
                    $arguments += @("/f", $Configuration.PfxPath)
                    if ($Configuration.PfxPassword) { $arguments += @("/p", $Configuration.PfxPassword) }
                }
                "Store" {
                    if ($Configuration.MachineStore) { $arguments += "/sm" }
                    $arguments += @("/sha1", $Configuration.Thumbprint)
                }
                "ArtifactSigning" {
                    $arguments += @("/dlib", $Configuration.ArtifactSigningDlib, "/dmdf", $metadataPath)
                }
                default {
                    throw "Unknown signing method '$($Configuration.Method)'."
                }
            }
            if (-not $NoTimestamp) {
                if (-not $Configuration.TimestampUrl) {
                    throw ("No timestamp URL. A signature without a timestamp dies with the " +
                           "certificate, and every installed copy then reports an invalid publisher.")
                }
                $arguments += @("/tr", $Configuration.TimestampUrl, "/td", "SHA256")
            }
            $arguments += $resolved

            $name = [System.IO.Path]::GetFileName($resolved)
            Invoke-SignToolCommand -SignTool $tool -Arguments $arguments -What "Signing $name" | Out-Null

            # A signature that exists is not yet a signature Windows trusts: the
            # chain check belongs to Test-ProxyDomSignature, which the build runs
            # on every file it signs. What is proved here is that the file got a
            # signature and that the signature came from the configured identity.
            $after = Get-AuthenticodeSignature -LiteralPath $resolved
            if (-not $after.SignerCertificate) {
                throw ("SignTool reported success but '$resolved' carries no signature. " +
                       "A file that only looks signed is worse than an unsigned one.")
            }
            if ($after.Status -eq "HashMismatch" -or $after.Status -eq "NotSigned") {
                $detail = ""
                if ($after.PSObject.Properties["StatusMessage"]) { $detail = " " + $after.StatusMessage }
                throw "'$resolved' does not match the signature that was just written (status $($after.Status)).$detail"
            }
            $subject = $after.SignerCertificate.Subject
            $thumbprint = $after.SignerCertificate.Thumbprint
            if ($Configuration.CertificateThumbprint -and $thumbprint -ne $Configuration.CertificateThumbprint) {
                throw ("'$resolved' was signed by certificate $thumbprint, not by the configured " +
                       "$($Configuration.CertificateThumbprint). The wrong certificate is in the store.")
            }
            if ($Configuration.ExpectedSubject -and $subject -notlike "*$($Configuration.ExpectedSubject)*") {
                throw ("'$resolved' was signed by '$subject', which does not match the expected " +
                       "publisher '$($Configuration.ExpectedSubject)'.")
            }
            $results += [pscustomobject]@{
                Path = $resolved
                Action = "signed"
                Signer = $subject
            }
        }
    } finally {
        if ($metadataPath -and (Test-Path -LiteralPath $metadataPath)) {
            Remove-Item -LiteralPath $metadataPath -Force
        }
    }
    return $results
}

function Test-ProxyDomSignature {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$SignTool,
        [string]$ExpectedSubject
    )

    $tool = Get-ProxyDomSignTool -Path $SignTool
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Nothing to verify at '$Path'."
    }
    $resolved = (Resolve-Path -LiteralPath $Path).Path

    # verify /pa is the same check Windows itself runs when Smart App Control or
    # SmartScreen asks "is this publisher real?".
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & $tool verify /pa /all $resolved 2>&1 | Out-String
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
    }

    $signature = Get-AuthenticodeSignature -LiteralPath $resolved
    $subject = if ($signature.SignerCertificate) { $signature.SignerCertificate.Subject } else { "" }
    $subjectMatches = $true
    if ($ExpectedSubject) { $subjectMatches = $subject -like "*$ExpectedSubject*" }

    return [pscustomobject]@{
        IsValid = ($code -eq 0 -and $subjectMatches)
        Path = $resolved
        Status = $signature.Status
        Subject = $subject
        Output = $output
    }
}

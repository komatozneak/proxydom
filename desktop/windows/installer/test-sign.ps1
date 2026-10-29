# Behavioral self-test for signing.ps1.
#
# It signs a real PE with a throwaway certificate, reads the signature back,
# proves that changing one byte breaks it, and pins the configuration resolver's
# failure modes. A test that only watched exit codes would pass on a script that
# signs nothing, which is exactly the failure this pipeline cannot afford.
#
# The throwaway certificate is deliberately not trusted: installing a root CA
# needs an interactive "do you want to trust this?" confirmation, so a test that
# depended on it would hang in an interactive session and behave differently in
# CI. Trust is therefore exercised from the other side: Test-ProxyDomSignature
# must accept a Microsoft-signed file and must reject the self-signed one, which
# is also what keeps a self-signed certificate from shipping.
#
# Needs the Windows SDK (signtool) and the PKI module; CI runs it on
# windows-latest, where both are present.
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "signing.ps1")

function Assert-Signing {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function Assert-SigningThrows {
    param([scriptblock]$Action, [string]$MessageMatch, [string]$What)
    try {
        & $Action | Out-Null
    } catch {
        if ($_.Exception.Message -notlike "*$MessageMatch*") {
            throw "Expected '$What' to fail with '$MessageMatch', got: $($_.Exception.Message)"
        }
        return
    }
    throw "Expected '$What' to throw, and it did not."
}

# The resolver falls back to environment variables, so the test must own them.
# Otherwise a developer with a real certificate configured would get a different
# answer from the same script than CI does.
$signingEnvironment = @(
    "PROXYDOM_SIGNTOOL",
    "PROXYDOM_SIGN_PFX_PATH",
    "PROXYDOM_SIGN_PFX_PASSWORD",
    "PROXYDOM_SIGN_THUMBPRINT",
    "PROXYDOM_ARTIFACT_SIGNING_ENDPOINT",
    "PROXYDOM_ARTIFACT_SIGNING_ACCOUNT",
    "PROXYDOM_ARTIFACT_SIGNING_PROFILE",
    "PROXYDOM_ARTIFACT_SIGNING_DLIB",
    "PROXYDOM_SIGN_TIMESTAMP_URL",
    "PROXYDOM_SIGN_EXPECTED_SUBJECT"
)
$savedEnvironment = @{}
foreach ($name in $signingEnvironment) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name)
    [Environment]::SetEnvironmentVariable($name, $null)
}

$temp = Join-Path ([System.IO.Path]::GetTempPath()) ("proxydom-sign-test-" + [guid]::NewGuid().ToString("N"))
$certificate = $null
try {
    $signTool = Get-ProxyDomSignTool
    Write-Host "Using signtool: $signTool"

    New-Item -ItemType Directory -Path $temp -Force | Out-Null

    # A Microsoft-signed binary is the positive control: it proves the
    # verification path can return "trusted", not merely "not trusted". The
    # signature must be embedded (Authenticode), not catalog-only: installers and
    # executables we sign carry embedded signatures, and signtool verify /pa
    # looks at exactly those. Most Windows system binaries are catalog-signed,
    # hence the search outside System32.
    $controlCandidates = @(
        (Join-Path $env:ProgramFiles "dotnet\dotnet.exe"),
        (Join-Path $env:ProgramFiles "Git\cmd\git.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"),
        (Join-Path $env:ProgramFiles "Microsoft\Edge\Application\msedge.exe")
    )
    $trustedSample = $null
    foreach ($candidate in $controlCandidates) {
        if (-not $candidate -or -not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        $candidateSignature = Get-AuthenticodeSignature -LiteralPath $candidate -ErrorAction SilentlyContinue
        if ($candidateSignature -and $candidateSignature.Status -eq "Valid" -and $candidateSignature.SignatureType -eq "Authenticode") {
            $trustedSample = $candidate
            break
        }
    }
    Assert-Signing ($null -ne $trustedSample) "an embedded-signed Microsoft binary is available as a control"
    $trustedCheck = Test-ProxyDomSignature -Path $trustedSample
    Assert-Signing $trustedCheck.IsValid "signtool verify /pa accepts a trusted signature"
    Assert-Signing ($trustedCheck.Subject -like "*Microsoft*") "the trusted signature names its publisher"
    Write-Host "  trusted signature recognised ($trustedSample)"

    $subject = "CN=Proxy Dom Signing Self-Test"
    $certificate = New-SelfSignedCertificate `
        -Type CodeSigningCert `
        -Subject $subject `
        -CertStoreLocation "Cert:\CurrentUser\My" `
        -KeyExportPolicy Exportable `
        -NotAfter (Get-Date).AddDays(2)

    $storeConfiguration = Resolve-ProxyDomSigningConfiguration -Method Store -Thumbprint $certificate.Thumbprint
    Assert-Signing ($storeConfiguration.Method -eq "Store") "the store configuration resolves"
    Assert-Signing ($storeConfiguration.TimestampUrl -like "http*") "the store method gets a timestamp URL by default"
    Assert-Signing ($storeConfiguration.CertificateThumbprint -eq $certificate.Thumbprint) "the configuration pins the certificate thumbprint"

    $sample = Join-Path $temp "sample.exe"
    Copy-Item -LiteralPath $trustedSample -Destination $sample
    $results = @(Invoke-ProxyDomSigning -Files $sample -Configuration $storeConfiguration -NoTimestamp)
    Assert-Signing ($results.Count -eq 1 -and $results[0].Action -eq "signed") "the sample is signed"
    $signature = Get-AuthenticodeSignature -LiteralPath $sample
    Assert-Signing ($null -ne $signature.SignerCertificate) "the sample carries a signature"
    Assert-Signing ($signature.SignerCertificate.Thumbprint -eq $certificate.Thumbprint) "the signer is the test certificate"
    Assert-Signing ($signature.Status -eq "UnknownError") "an untrusted chain is reported as such, not as a broken signature (status $($signature.Status))"
    Write-Host "  signed by the configured certificate"

    # A self-signed signature is not a release signature: Windows cannot chain it
    # to a trusted CA, so the build-level check must refuse it.
    $selfSignedCheck = Test-ProxyDomSignature -Path $sample
    Assert-Signing (-not $selfSignedCheck.IsValid) "signtool verify /pa rejects a self-signed signature"
    Write-Host "  self-signed signature refused by verification"

    # One changed byte in the DOS stub is enough: the Authenticode digest covers
    # it. A stale signature is worse than none, because Windows says "this file
    # was signed but has been altered since".
    $bytes = [System.IO.File]::ReadAllBytes($sample)
    $marker = [System.Text.Encoding]::ASCII.GetBytes("This program cannot be run in DOS mode")
    $offset = -1
    for ($i = 0; $i -le $bytes.Length - $marker.Length; $i++) {
        $hit = $true
        for ($j = 0; $j -lt $marker.Length; $j++) {
            if ($bytes[$i + $j] -ne $marker[$j]) { $hit = $false; break }
        }
        if ($hit) { $offset = $i; break }
    }
    Assert-Signing ($offset -ge 0) "the DOS stub marker is present in the sample"
    $bytes[$offset] = $bytes[$offset] -bxor 0xFF
    [System.IO.File]::WriteAllBytes($sample, $bytes)
    $tampered = Get-AuthenticodeSignature -LiteralPath $sample
    Assert-Signing ($tampered.Status -eq "HashMismatch") "tampering breaks the signature (status $($tampered.Status))"
    Assert-Signing (-not (Test-ProxyDomSignature -Path $sample).IsValid) "signtool verify rejects the tampered file"
    Write-Host "  tampering detected"

    # The PFX path opens the file and asks for its password, so it is exercised
    # separately from the store path even though both end in the same SignTool.
    $pfxPath = Join-Path $temp "self-test.pfx"
    $pfxPassword = "self-test-password"
    Export-PfxCertificate -Cert $certificate -FilePath $pfxPath `
        -Password (ConvertTo-SecureString -String $pfxPassword -AsPlainText -Force) | Out-Null
    $pfxSample = Join-Path $temp "pfx-sample.exe"
    Copy-Item -LiteralPath $trustedSample -Destination $pfxSample
    $pfxConfiguration = Resolve-ProxyDomSigningConfiguration -Method Pfx -PfxPath $pfxPath -PfxPassword $pfxPassword
    $pfxResults = @(Invoke-ProxyDomSigning -Files $pfxSample -Configuration $pfxConfiguration -NoTimestamp)
    Assert-Signing ($pfxResults[0].Action -eq "signed") "the PFX path signs"
    $pfxSignature = Get-AuthenticodeSignature -LiteralPath $pfxSample
    Assert-Signing ($pfxSignature.SignerCertificate.Thumbprint -eq $certificate.Thumbprint) "the PFX signs with its own certificate"
    Write-Host "  PFX path signs"

    # A file that already carries a trusted signature must be left alone: the
    # payload contains Microsoft and WireGuard binaries, and re-signing them
    # would replace the publisher that actually built them.
    $keptPath = Join-Path $temp "already-signed.exe"
    Copy-Item -LiteralPath $trustedSample -Destination $keptPath
    $kept = @(Invoke-ProxyDomSigning -Files $keptPath -Configuration $storeConfiguration -SkipAlreadySigned -NoTimestamp)
    Assert-Signing ($kept[0].Action -eq "kept") "an already valid signature is left alone"
    $keptSignature = Get-AuthenticodeSignature -LiteralPath $keptPath
    Assert-Signing ($keptSignature.SignerCertificate.Thumbprint -ne $certificate.Thumbprint) "the kept file keeps its original publisher"
    Write-Host "  already signed files are kept"

    $wrongSubject = Resolve-ProxyDomSigningConfiguration -Method Store -Thumbprint $certificate.Thumbprint -ExpectedSubject "Somebody Else Ltd"
    $otherSample = Join-Path $temp "wrong-subject.exe"
    Copy-Item -LiteralPath $trustedSample -Destination $otherSample
    $global:LASTEXITCODE = 0
    Assert-SigningThrows {
        Invoke-ProxyDomSigning -Files $otherSample -Configuration $wrongSubject -NoTimestamp
    } "does not match the expected publisher" "a signature from an unexpected publisher"
    Assert-Signing ($LASTEXITCODE -eq 0) "a rejected signature must not leak the native exit code"
    Write-Host "  unexpected publisher rejected"

    $unsignedPath = Join-Path $temp "not-a-program.txt"
    Set-Content -LiteralPath $unsignedPath -Value "nothing to sign here"
    $global:LASTEXITCODE = 0
    Assert-Signing (-not (Test-ProxyDomSignature -Path $unsignedPath).IsValid) "verification rejects a file with no signature"
    Assert-Signing ($LASTEXITCODE -eq 0) "a failed verify must not leak the native exit code"

    # What the build signs is a decision of its own: every root executable and
    # DLL, but not the assets and not WireGuard's wintun.dll, which keeps the
    # signature of the project that built it.
    $fakePayload = Join-Path $temp "payload"
    New-Item -ItemType Directory -Path $fakePayload -Force | Out-Null
    foreach ($name in @("proxy_dom.exe", "proxydom-engine.exe", "ProxyDomBroker.exe", "flutter_windows.dll", "wintun.dll", "THIRD-PARTY-NOTICES.md")) {
        Set-Content -LiteralPath (Join-Path $fakePayload $name) -Value $name
    }
    $targets = @(Get-ProxyDomPayloadSignTargets -Payload $fakePayload)
    Assert-Signing ($targets.Count -eq 4) "the payload selection takes the four project binaries (got $($targets.Count))"
    Assert-Signing (@($targets | Where-Object { $_ -like "*wintun.dll" }).Count -eq 0) "wintun.dll is left to its own publisher"
    Assert-Signing (@($targets | Where-Object { $_ -like "*.md" }).Count -eq 0) "documents are not signed"
    Write-Host "  payload selection is right"

    $artifactConfiguration = [pscustomobject]@{
        Method = "ArtifactSigning"
        ArtifactSigningEndpoint = "https://eus.codesigning.azure.net"
        ArtifactSigningAccount = "self-test"
        ArtifactSigningProfile = "self-test"
        ArtifactSigningDlib = "self-test"
        TimestampUrl = "http://timestamp.acs.microsoft.com"
        CertificateThumbprint = $null
        ExpectedSubject = $null
    }
    Assert-SigningThrows {
        Invoke-ProxyDomSigning -Files $otherSample -Configuration $artifactConfiguration -NoTimestamp
    } "Timestamping is not optional" "Artifact Signing without a timestamp"

    Assert-Signing ($null -eq (Resolve-ProxyDomSigningConfiguration)) "Auto with nothing configured resolves to nothing"
    Assert-Signing ($null -eq (Resolve-ProxyDomSigningConfiguration -Method None -Thumbprint $certificate.Thumbprint)) "None ignores configured material"
    Assert-SigningThrows {
        Resolve-ProxyDomSigningConfiguration -Method Pfx -PfxPath (Join-Path $temp "absent.pfx")
    } "does not exist" "a missing PFX"
    Assert-SigningThrows {
        Resolve-ProxyDomSigningConfiguration -Method Pfx -PfxPath $pfxPath -PfxPassword "wrong password"
    } "could not be opened" "a PFX with the wrong password"
    Assert-SigningThrows {
        Resolve-ProxyDomSigningConfiguration -Method Store -PfxPath $pfxPath
    } "settings are missing" "Store without a thumbprint"
    Assert-SigningThrows {
        Resolve-ProxyDomSigningConfiguration -Method Auto -PfxPath $pfxPath -Thumbprint $certificate.Thumbprint
    } "More than one signing identity" "two identities at once"
    Assert-SigningThrows {
        Resolve-ProxyDomSigningConfiguration -Method ArtifactSigning
    } "settings are missing" "Artifact Signing without settings"
    Assert-SigningThrows {
        Invoke-ProxyDomSigning -Files (Join-Path $temp "absent.exe") -Configuration $storeConfiguration -NoTimestamp
    } "Nothing to sign" "signing a file that is not there"
    Write-Host "  configuration rejects bad input"

    Write-Host "PASS signing self-test"
} finally {
    if ($certificate) {
        $installed = Get-ChildItem -Path "Cert:\CurrentUser\My" -ErrorAction SilentlyContinue |
            Where-Object { $_.Thumbprint -eq $certificate.Thumbprint }
        foreach ($item in @($installed)) {
            Remove-Item -LiteralPath $item.PSPath -Force -ErrorAction SilentlyContinue
        }
    }
    if (Test-Path -LiteralPath $temp) {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
    foreach ($name in $signingEnvironment) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name])
    }
}

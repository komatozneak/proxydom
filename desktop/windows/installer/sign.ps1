# Signs and verifies files with the configured Windows code-signing identity.
#
# The build calls the same functions (signing.ps1) before it packages the MSI and
# again on the MSI itself. This wrapper exists for the cases outside a full
# build: signing an already built installer, or checking what a certificate
# would produce, without rebuilding Flutter and the service.
#
# Usage:
#   .\sign.ps1 -Path .\out\ProxyDom-1.0.0.msi
#   .\sign.ps1 -Path .\payload\proxy_dom.exe -Method Pfx -PfxPath C:\certs\pd.pfx
#
# Without -Path arguments nothing is signed; see docs/windows-signing.md for the
# environment variables each method reads.
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string[]]$Path,
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
    [string]$ExpectedSubject,
    [switch]$SkipAlreadySigned,
    [switch]$NoTimestamp
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "signing.ps1")

$configuration = Resolve-ProxyDomSigningConfiguration `
    -Method $Method `
    -PfxPath $PfxPath `
    -PfxPassword $PfxPassword `
    -Thumbprint $Thumbprint `
    -ArtifactSigningEndpoint $ArtifactSigningEndpoint `
    -ArtifactSigningAccount $ArtifactSigningAccount `
    -ArtifactSigningProfile $ArtifactSigningProfile `
    -ArtifactSigningDlib $ArtifactSigningDlib `
    -TimestampUrl $TimestampUrl `
    -ExpectedSubject $ExpectedSubject

if (-not $configuration) {
    throw ("No signing identity is configured. Set PROXYDOM_SIGN_THUMBPRINT, " +
           "PROXYDOM_SIGN_PFX_PATH, or the PROXYDOM_ARTIFACT_SIGNING_* variables; " +
           "docs/windows-signing.md has the full list.")
}

Write-Host "Signing identity: $($configuration.Description)"
$results = Invoke-ProxyDomSigning -Files $Path -Configuration $configuration `
    -SkipAlreadySigned:$SkipAlreadySigned -NoTimestamp:$NoTimestamp

$results | Format-Table -AutoSize | Out-String | Write-Host
Write-Host "Signed $((@($results | Where-Object { $_.Action -eq 'signed' })).Count) file(s)."

# Signing wrote the signature; this is the question Windows asks. A file whose
# signature does not chain to a trusted CA still shows "unknown publisher", so a
# successful SignTool run is not a finished job.
$untrusted = @()
foreach ($result in $results) {
    $check = Test-ProxyDomSignature -Path $result.Path -ExpectedSubject $configuration.ExpectedSubject
    if (-not $check.IsValid) {
        $untrusted += "$($result.Path) ($($check.Status))"
    }
}
if ($untrusted.Count -gt 0) {
    throw ("Windows does not trust the signature on:`n  " + ($untrusted -join "`n  ") +
           "`nA self-signed certificate or an expired one produces exactly this. " +
           "Smart App Control needs a CA from the Microsoft Trusted Root Program.")
}
Write-Host "Signature verified by signtool /pa."

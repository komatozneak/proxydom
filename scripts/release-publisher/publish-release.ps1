# Publishes signed, obfuscated build artifacts to the public mirror.
#
# The source repository stays private. This script copies only finished
# binaries plus a machine-readable RELEASE.json into a separate public
# distribution checkout, hashes them, commits, and pushes. It refuses source
# files, debug/CI builds and symbol maps.
#
# Example:
#   pwsh ./publish-release.ps1 `
#     -Version 1.0.0 `
#     -Artifacts ..\..\dist\proxydom-1.0.0.apk,..\..\dist\proxydom-1.0.0.aab,..\..\dist\proxydom-1.0.0.msi `
#     -DistRepo ..\..\..\proxydom-releases `
#     -DownloadBaseUrl https://dl.proxydom.su/releases/1.0.0 `
#     -NotesFile ..\..\dist\RELEASE-NOTES.md
param(
    [Parameter(Mandatory = $true)]
    [string]$Version,

    [Parameter(Mandatory = $true)]
    [string[]]$Artifacts,

    [Parameter(Mandatory = $true)]
    [string]$DistRepo,

    [Parameter(Mandatory = $true)]
    [string]$DownloadBaseUrl,

    [string]$NotesFile,
    [string]$Channel = "stable",
    [string]$MinOs = "",
    [switch]$SkipPush
)

$ErrorActionPreference = "Stop"

if ($Version -notmatch '^\d+\.\d+\.\d+([.-][A-Za-z0-9.-]+)?$') {
    throw "Version must look like 1.2.3 or 1.2.3-rc.1: $Version"
}
if ($Channel -notin @("stable", "beta", "internal")) {
    throw "Channel must be stable, beta or internal: $Channel"
}

$allowedExtensions = @(".apk", ".aab", ".ipa", ".msi", ".exe", ".dmg")
$forbiddenNameParts = @("debug", "profile", "ci", "symbols", "unsigned")

$repo = (Resolve-Path -LiteralPath $DistRepo).Path
if (-not (Test-Path -LiteralPath (Join-Path $repo ".git") -PathType Container)) {
    throw "Not a git checkout: $repo"
}
$dirty = git -C $repo status --porcelain
if ($dirty) {
    throw "Distribution checkout is not clean. Commit or clean it before publishing:`n$dirty"
}

$releaseDir = Join-Path $repo (Join-Path "releases" $Version)
if (Test-Path -LiteralPath $releaseDir) {
    throw "Release $Version already exists in the distribution repo: $releaseDir"
}

$staging = Join-Path $repo (".staging-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $staging -Force | Out-Null

try {
    $entries = @()
    foreach ($artifact in $Artifacts) {
        if (-not (Test-Path -LiteralPath $artifact -PathType Leaf)) {
            throw "Artifact not found: $artifact"
        }
        $source = (Resolve-Path -LiteralPath $artifact).Path
        $name = [System.IO.Path]::GetFileName($source)
        $extension = [System.IO.Path]::GetExtension($name).ToLowerInvariant()
        if ($allowedExtensions -notcontains $extension) {
            throw "Refusing non-release file: $name"
        }
        $lower = $name.ToLowerInvariant()
        foreach ($part in $forbiddenNameParts) {
            if ($lower.Contains($part)) {
                throw "Refusing debug/CI/symbol artifact: $name"
            }
        }
        $sha = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
        $size = (Get-Item -LiteralPath $source).Length
        Copy-Item -LiteralPath $source -Destination (Join-Path $staging $name)
        Set-Content -LiteralPath (Join-Path $staging "$name.sha256") -Value $sha -NoNewline
        $entries += [ordered]@{
            name   = $name
            sha256 = $sha
            size   = $size
            url    = "$($DownloadBaseUrl.TrimEnd('/'))/$name"
        }
        Write-Host ("staged {0} ({1:N1} MB) sha256={2}" -f $name, ($size / 1MB), $sha)
    }

    $entries = $entries | Sort-Object { $_.name }
    $notes = ""
    if ($NotesFile) {
        if (-not (Test-Path -LiteralPath $NotesFile -PathType Leaf)) {
            throw "Notes file not found: $NotesFile"
        }
        $notes = Get-Content -LiteralPath $NotesFile -Raw -Encoding UTF8
    }

    $manifest = [ordered]@{
        schema     = 1
        product    = "Proxy Dom"
        version    = $Version
        channel    = $Channel
        publishedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        minOs      = $MinOs
        notes      = $notes.Trim()
        artifacts  = $entries
    }
    $manifestJson = $manifest | ConvertTo-Json -Depth 6
    Set-Content -LiteralPath (Join-Path $staging "RELEASE.json") -Value $manifestJson -Encoding UTF8

    New-Item -ItemType Directory -Path $releaseDir -Force | Out-Null
    Get-ChildItem -LiteralPath $staging -File | ForEach-Object {
        Move-Item -LiteralPath $_.FullName -Destination (Join-Path $releaseDir $_.Name)
    }

    $relative = "releases/$Version"
    git -C $repo add -- $relative
    git -C $repo commit -m "release: $Version"
    if (-not $SkipPush) {
        git -C $repo push
    }
    Write-Host "Published $Version to $repo/$relative"
} finally {
    if (Test-Path -LiteralPath $staging) {
        Remove-Item -LiteralPath $staging -Recurse -Force
    }
}

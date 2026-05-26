[CmdletBinding()]
param(
    [string]$ManifestPath = '.\fixtures\lecture-video.gdev-101-design-vocabulary.json',
    [string]$RenderedMediaPath = '.\fixtures\lecture-rendered-media.gdev-101.json',
    [string]$OutputPath = '',
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-HasText {
    param([object]$Value)
    return -not [string]::IsNullOrWhiteSpace([string]$Value)
}

function ConvertTo-SafePathSegment {
    param([string]$Value)
    if (-not (Test-HasText $Value)) {
        return 'unnamed'
    }
    return ($Value -replace '[^A-Za-z0-9._-]', '_')
}

function Get-Sha256File {
    param([string]$Path)

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $hashBytes = $sha.ComputeHash($stream)
            return ([System.BitConverter]::ToString($hashBytes) -replace '-', '').ToLowerInvariant()
        }
        finally {
            $sha.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Get-Sha256Text {
    param([string]$Value)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        $hashBytes = $sha.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($hashBytes) -replace '-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-MediaKind {
    param([string]$Type)

    if ($Type -like 'video/*') {
        return 'video'
    }
    if ($Type -like 'audio/*') {
        return 'audio'
    }
    return 'other'
}

function Get-RelativeArchivePath {
    param(
        [string]$ArchiveRoot,
        [object]$Media
    )

    $mediaPath = [string]$Media.path
    if ($mediaPath.StartsWith('var\lecture-media\')) {
        return $mediaPath
    }

    $kind = Get-MediaKind -Type ([string]$Media.type)
    $extension = [System.IO.Path]::GetExtension($mediaPath)
    if (-not (Test-HasText $extension)) {
        $extension = '.bin'
    }
    return "$ArchiveRoot\$kind\$($Media.assetId)$extension"
}

function Resolve-RepoPath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path -Path (Get-Location).Path -ChildPath $Path))
}

function Test-AllowedOutputPath {
    param([string]$Path)

    $fullPath = Resolve-RepoPath -Path $Path
    $repoRoot = [System.IO.Path]::GetFullPath((Get-Location).Path)
    $archiveRoot = [System.IO.Path]::GetFullPath((Join-Path -Path $repoRoot -ChildPath 'var\lecture-media'))
    $tmpRoot = [System.IO.Path]::GetFullPath((Join-Path -Path $repoRoot -ChildPath '.codex-cache\tmp'))
    return $fullPath.StartsWith($archiveRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        $fullPath.StartsWith($tmpRoot, [System.StringComparison]::OrdinalIgnoreCase)
}

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Missing lecture manifest: $ManifestPath"
}
if (-not (Test-Path -LiteralPath $RenderedMediaPath -PathType Leaf)) {
    throw "Missing rendered media metadata: $RenderedMediaPath"
}
if ($Apply -and -not (Test-HasText $OutputPath)) {
    throw 'OutputPath is required when -Apply is used.'
}
if ($Apply -and -not (Test-AllowedOutputPath -Path $OutputPath)) {
    throw 'Archive manifest output must be written under var\lecture-media or .codex-cache\tmp.'
}

$lectureRaw = Get-Content -LiteralPath $ManifestPath -Raw
$lecture = $lectureRaw | ConvertFrom-Json
$renderedMedia = Get-Content -LiteralPath $RenderedMediaPath -Raw | ConvertFrom-Json

$sourceId = [string]$lecture.contentSource.sourceId
$safePackageId = ConvertTo-SafePathSegment -Value ([string]$lecture.packageId)
$archiveRoot = "var\lecture-media\$sourceId\$safePackageId"
$packageMetadataSha = Get-Sha256File -Path (Resolve-RepoPath -Path $ManifestPath)
$captionText = [string]$lecture.captions.text
$captionSha = Get-Sha256Text -Value $captionText
$publishBlockers = [System.Collections.Generic.List[string]]::new()
$mediaEntries = @()

foreach ($media in @($lecture.media)) {
    $kind = Get-MediaKind -Type ([string]$media.type)
    $expectedArchivePath = Get-RelativeArchivePath -ArchiveRoot $archiveRoot -Media $media
    $entryBlockers = [System.Collections.Generic.List[string]]::new()
    $actualSha256 = $null
    $archiveStatus = 'pending'

    if ($media.status -eq 'planned') {
        $archiveStatus = 'planned'
        if ($media.requiredForPublish -eq $true) {
            $entryBlockers.Add("Required $kind asset is still planned: $($media.assetId)")
        }
    }
    elseif ($media.status -in @('rendered', 'archived')) {
        if (-not ([string]$media.path).StartsWith('var\lecture-media\')) {
            $entryBlockers.Add("Rendered $kind asset is outside the local archive: $($media.assetId)")
        }
        if ([string]$media.sha256 -notmatch '^[a-f0-9]{64}$') {
            $entryBlockers.Add("Rendered $kind asset is missing a lowercase SHA-256 checksum: $($media.assetId)")
        }

        $resolvedMediaPath = Resolve-RepoPath -Path ([string]$media.path)
        if (-not (Test-Path -LiteralPath $resolvedMediaPath -PathType Leaf)) {
            $entryBlockers.Add("Rendered $kind asset file is missing: $($media.path)")
        }
        else {
            $actualSha256 = Get-Sha256File -Path $resolvedMediaPath
            if ($actualSha256 -ne [string]$media.sha256) {
                $entryBlockers.Add("Rendered $kind asset checksum mismatch: $($media.assetId)")
            }
        }

        if ($entryBlockers.Count -eq 0) {
            $archiveStatus = 'archived'
        }
        else {
            $archiveStatus = 'blocked'
        }
    }
    else {
        $archiveStatus = 'blocked'
        $entryBlockers.Add("Media asset has unsupported status: $($media.status)")
    }

    foreach ($blocker in $entryBlockers) {
        $publishBlockers.Add($blocker)
    }

    $mediaEntries += [ordered]@{
        assetId = $media.assetId
        kind = $kind
        type = $media.type
        packagePath = $media.path
        archivePath = $expectedArchivePath
        requiredForPublish = $media.requiredForPublish
        sourceStatus = $media.status
        archiveStatus = $archiveStatus
        checksumAlgorithm = 'sha256'
        manifestSha256 = $media.sha256
        actualSha256 = $actualSha256
        blockers = @($entryBlockers)
    }
}

$renderedEntry = @($mediaEntries | Where-Object { $_.assetId -eq $renderedMedia.assetId })
if ($renderedEntry.Count -ne 1) {
    $publishBlockers.Add("Rendered media metadata asset is missing from package media: $($renderedMedia.assetId)")
}

$captionEntry = [ordered]@{
    assetId = 'captions-webvtt-inline'
    kind = 'captions'
    type = 'text/vtt'
    packagePath = 'lecture-video.json#captions.text'
    archivePath = "$archiveRoot\captions\captions.vtt"
    requiredForPublish = $true
    sourceStatus = 'packaged'
    archiveStatus = 'packaged'
    checksumAlgorithm = 'sha256'
    sha256 = $captionSha
    length = $captionText.Length
}

$packageMetadataEntry = [ordered]@{
    assetId = 'lecture-video-json'
    kind = 'package-metadata'
    type = 'application/json'
    packagePath = $ManifestPath
    archivePath = "$archiveRoot\package\lecture-video.json"
    requiredForPublish = $true
    sourceStatus = 'packaged'
    archiveStatus = 'packaged'
    checksumAlgorithm = 'sha256'
    sha256 = $packageMetadataSha
    length = $lectureRaw.Length
}

$archiveManifest = [ordered]@{
    schemaVersion = 1
    manifestId = "lecture-archive-manifest:$safePackageId"
    packageId = $lecture.packageId
    generationMode = 'deterministic'
    dryRun = -not $Apply
    archiveRoot = $archiveRoot
    renderedMediaMetadataPath = $RenderedMediaPath
    assets = [ordered]@{
        media = @($mediaEntries)
        captions = @($captionEntry)
        packageMetadata = @($packageMetadataEntry)
    }
    summary = [ordered]@{
        mediaAssetCount = @($mediaEntries).Count
        archivedMediaAssetCount = @($mediaEntries | Where-Object { $_.archiveStatus -eq 'archived' }).Count
        plannedRequiredMediaAssetCount = @($mediaEntries | Where-Object { $_.requiredForPublish -eq $true -and $_.archiveStatus -eq 'planned' }).Count
        captionChecksumCount = 1
        packageMetadataChecksumCount = 1
        publishBlockerCount = $publishBlockers.Count
    }
    publishReady = ($publishBlockers.Count -eq 0)
    requiresOperatorPublishGate = $true
    publishBlockers = @($publishBlockers)
}

$json = $archiveManifest | ConvertTo-Json -Depth 12

if ($Apply) {
    $resolvedOutputPath = Resolve-RepoPath -Path $OutputPath
    $outputDirectory = Split-Path -Parent $resolvedOutputPath
    if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $outputDirectory | Out-Null
    }
    Set-Content -LiteralPath $resolvedOutputPath -Value $json -Encoding UTF8
}

$json

exit 0

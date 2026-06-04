[CmdletBinding()]
param(
    [string]$ManifestPath = '..\open-education-game-development\generated-lectures\gdev-101-design-vocabulary\lecture-video.json',
    [string]$RenderedMediaPath = '..\open-education-game-development\generated-lectures\gdev-101-design-vocabulary\lecture-rendered-media.json',
    [string]$OutputPath = '',
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. .\scripts\teaching\lecture-paths.ps1

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
    if ($mediaPath.StartsWith($ArchiveRoot)) {
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
    param(
        [string]$Path,
        [string]$ContentRoot,
        [string]$ArchiveRoot
    )

    $fullPath = if ([System.IO.Path]::IsPathRooted($Path)) {
        [System.IO.Path]::GetFullPath($Path)
    }
    elseif ($Path.StartsWith($ArchiveRoot)) {
        Resolve-LectureContentPath -ContentRoot $ContentRoot -Path $Path
    }
    else {
        Resolve-RepoPath -Path $Path
    }
    $repoRoot = [System.IO.Path]::GetFullPath((Get-Location).Path)
    $contentArchiveRoot = Resolve-LectureContentPath -ContentRoot $ContentRoot -Path $ArchiveRoot
    $tmpRoot = [System.IO.Path]::GetFullPath((Join-Path -Path $repoRoot -ChildPath '.codex-cache\tmp'))
    return $fullPath.StartsWith($contentArchiveRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        $fullPath.StartsWith($tmpRoot, [System.StringComparison]::OrdinalIgnoreCase)
}

$resolvedManifestPath = Resolve-LecturePath -Path $ManifestPath
$resolvedRenderedMediaPath = Resolve-LecturePath -Path $RenderedMediaPath

if (-not (Test-Path -LiteralPath $resolvedManifestPath -PathType Leaf)) {
    throw "Missing lecture manifest: $ManifestPath"
}
if (-not (Test-Path -LiteralPath $resolvedRenderedMediaPath -PathType Leaf)) {
    throw "Missing rendered media metadata: $RenderedMediaPath"
}
if ($Apply -and -not (Test-HasText $OutputPath)) {
    throw 'OutputPath is required when -Apply is used.'
}

$lectureRaw = Get-Content -LiteralPath $resolvedManifestPath -Raw
$lecture = $lectureRaw | ConvertFrom-Json
$assetRoot = Get-LectureAssetRoot -Lecture $lecture -ManifestPath $resolvedManifestPath
$renderedMedia = Get-Content -LiteralPath $resolvedRenderedMediaPath -Raw | ConvertFrom-Json
if ($Apply -and -not (Test-AllowedOutputPath -Path $OutputPath -ContentRoot ([string]$assetRoot.contentRoot) -ArchiveRoot ([string]$assetRoot.relativePath))) {
    throw 'Archive manifest output must be written under the subject lecture archive or .codex-cache\tmp.'
}

$safePackageId = ConvertTo-SafePathSegment -Value ([string]$lecture.packageId)
$archiveRoot = [string]$assetRoot.relativePath
$packageMetadataSha = Get-Sha256File -Path $resolvedManifestPath
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
        if (-not ([string]$media.path).StartsWith($archiveRoot)) {
            $entryBlockers.Add("Rendered $kind asset is outside the subject lecture archive: $($media.assetId)")
        }
        if ([string]$media.sha256 -notmatch '^[a-f0-9]{64}$') {
            $entryBlockers.Add("Rendered $kind asset is missing a lowercase SHA-256 checksum: $($media.assetId)")
        }

        $resolvedMediaPath = Resolve-LectureContentPath -ContentRoot ([string]$assetRoot.contentRoot) -Path ([string]$media.path)
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
    renderedMediaMetadataPath = ConvertTo-LectureContentRelativePath -ContentRoot ([string]$assetRoot.contentRoot) -Path $resolvedRenderedMediaPath
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
    $resolvedOutputPath = if ([System.IO.Path]::IsPathRooted($OutputPath)) {
        [System.IO.Path]::GetFullPath($OutputPath)
    }
    elseif ($OutputPath.StartsWith($archiveRoot)) {
        Resolve-LectureContentPath -ContentRoot ([string]$assetRoot.contentRoot) -Path $OutputPath
    }
    else {
        Resolve-RepoPath -Path $OutputPath
    }
    $outputDirectory = Split-Path -Parent $resolvedOutputPath
    if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $outputDirectory | Out-Null
    }
    Set-Content -LiteralPath $resolvedOutputPath -Value $json -Encoding UTF8
}

$json

exit 0

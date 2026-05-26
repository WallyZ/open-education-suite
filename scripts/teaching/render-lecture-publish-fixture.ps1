[CmdletBinding()]
param(
    [string]$ManifestPath = '.\fixtures\lecture-video.gdev-101-design-vocabulary.json',
    [string]$RenderedMediaPath = '.\fixtures\lecture-rendered-media.gdev-101.json'
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

function Resolve-RepoPath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path -Path (Get-Location).Path -ChildPath $Path))
}

function ConvertTo-RepoRelativePath {
    param([string]$Path)

    $repoRoot = [System.IO.Path]::GetFullPath((Get-Location).Path)
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if (-not $fullPath.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside the repo: $Path"
    }

    return $fullPath.Substring($repoRoot.Length).TrimStart('\')
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

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Missing lecture manifest: $ManifestPath"
}
if (-not (Test-Path -LiteralPath $RenderedMediaPath -PathType Leaf)) {
    throw "Missing rendered media metadata: $RenderedMediaPath"
}

$ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
if ($null -eq $ffmpeg) {
    throw 'ffmpeg is required to render the deterministic publish fixture media.'
}

$lecture = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$renderedMedia = Get-Content -LiteralPath $RenderedMediaPath -Raw | ConvertFrom-Json
$sourceAudioPath = Resolve-RepoPath -Path ([string]$renderedMedia.path)
if (-not (Test-Path -LiteralPath $sourceAudioPath -PathType Leaf)) {
    throw "Missing rendered source audio: $($renderedMedia.path)"
}

$sourceId = [string]$lecture.contentSource.sourceId
$safePackageId = ConvertTo-SafePathSegment -Value ([string]$lecture.packageId)
$archiveRoot = "var\lecture-media\$sourceId\$safePackageId"
$audioDirectory = Resolve-RepoPath -Path "$archiveRoot\audio"
$videoDirectory = Resolve-RepoPath -Path "$archiveRoot\video"
New-Item -ItemType Directory -Path $audioDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $videoDirectory -Force | Out-Null

$m4aPath = Join-Path -Path $audioDirectory -ChildPath 'lecture-audio-m4a.m4a'
$mp4Path = Join-Path -Path $videoDirectory -ChildPath 'lecture-video-mp4.mp4'

& $ffmpeg.Source -y -hide_banner -loglevel error -i $sourceAudioPath -c:a aac -b:a 96k $m4aPath
if ($LASTEXITCODE -ne 0) {
    throw "ffmpeg failed to render M4A publish fixture with exit code $LASTEXITCODE."
}

& $ffmpeg.Source -y -hide_banner -loglevel error -f lavfi -i 'color=c=0x14213d:s=1280x720:r=24' -i $sourceAudioPath -map '0:v:0' -map '1:a:0' -shortest -c:v libx264 -pix_fmt yuv420p -c:a aac -b:a 96k $mp4Path
if ($LASTEXITCODE -ne 0) {
    throw "ffmpeg failed to render MP4 publish fixture with exit code $LASTEXITCODE."
}

$m4aItem = Get-Item -LiteralPath $m4aPath
$mp4Item = Get-Item -LiteralPath $mp4Path

[ordered]@{
    schemaVersion = 1
    packageId = $lecture.packageId
    renderEngine = 'ffmpeg'
    archiveRoot = $archiveRoot
    sourceAudio = [ordered]@{
        assetId = $renderedMedia.assetId
        path = $renderedMedia.path
        sha256 = $renderedMedia.sha256
    }
    media = @(
        [ordered]@{
            assetId = 'lecture-audio-m4a'
            type = 'audio/mp4'
            path = ConvertTo-RepoRelativePath -Path $m4aPath
            sha256 = Get-Sha256File -Path $m4aPath
            length = $m4aItem.Length
            status = 'archived'
            requiredForPublish = $true
        },
        [ordered]@{
            assetId = 'lecture-video-mp4'
            type = 'video/mp4'
            path = ConvertTo-RepoRelativePath -Path $mp4Path
            sha256 = Get-Sha256File -Path $mp4Path
            length = $mp4Item.Length
            status = 'archived'
            requiredForPublish = $true
        }
    )
} | ConvertTo-Json -Depth 8

exit 0

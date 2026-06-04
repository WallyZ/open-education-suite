Set-StrictMode -Version Latest

function Test-LectureHasText {
    param([object]$Value)
    return -not [string]::IsNullOrWhiteSpace([string]$Value)
}

function ConvertTo-LectureSafePathSegment {
    param([string]$Value)
    if (-not (Test-LectureHasText $Value)) {
        return 'unnamed'
    }
    return ($Value -replace '[^A-Za-z0-9._-]', '_')
}

function Resolve-LecturePath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path -Path (Get-Location).Path -ChildPath $Path))
}

function Get-LectureContentRoot {
    param([string]$ManifestPath)

    $current = Split-Path -Parent (Resolve-LecturePath -Path $ManifestPath)
    while (Test-LectureHasText $current) {
        if (Test-Path -LiteralPath (Join-Path -Path $current -ChildPath 'content-repo.json') -PathType Leaf) {
            return [System.IO.Path]::GetFullPath($current)
        }

        $parent = Split-Path -Parent $current
        if ($parent -eq $current) {
            break
        }
        $current = $parent
    }

    return [System.IO.Path]::GetFullPath((Get-Location).Path)
}

function ConvertTo-LectureRelativePath {
    param(
        [string]$BasePath,
        [string]$FullPath
    )

    $baseUri = [System.Uri](([System.IO.Path]::GetFullPath($BasePath)).TrimEnd('\') + '\')
    $fileUri = [System.Uri]([System.IO.Path]::GetFullPath($FullPath))
    return [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($fileUri).ToString()).Replace('/', '\')
}

function Resolve-LectureContentPath {
    param(
        [string]$ContentRoot,
        [string]$Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path -Path $ContentRoot -ChildPath $Path))
}

function Get-LectureAssetRoot {
    param(
        [object]$Lecture,
        [string]$ManifestPath
    )

    $contentRoot = Get-LectureContentRoot -ManifestPath $ManifestPath
    $assetRoot = [string]$Lecture.subjectOwnedAssetRoot
    if (-not (Test-LectureHasText $assetRoot)) {
        $sourceId = [string]$Lecture.contentSource.sourceId
        $safePackageId = ConvertTo-LectureSafePathSegment -Value ([string]$Lecture.packageId)
        $assetRoot = "var\lecture-media\$sourceId\$safePackageId"
        $contentRoot = [System.IO.Path]::GetFullPath((Get-Location).Path)
    }

    [ordered]@{
        contentRoot = $contentRoot
        relativePath = $assetRoot
        fullPath = Resolve-LectureContentPath -ContentRoot $contentRoot -Path $assetRoot
    }
}

function Get-LectureMediaDirectory {
    param(
        [object]$AssetRoot,
        [string]$Kind
    )

    if ([string]$AssetRoot.relativePath -like 'var\lecture-media\*') {
        return Join-Path -Path ([string]$AssetRoot.fullPath) -ChildPath $Kind
    }

    return Join-Path -Path ([string]$AssetRoot.fullPath) -ChildPath "media\$Kind"
}

function Get-LectureMediaRelativeDirectory {
    param(
        [object]$AssetRoot,
        [string]$Kind
    )

    if ([string]$AssetRoot.relativePath -like 'var\lecture-media\*') {
        return "$($AssetRoot.relativePath)\$Kind"
    }

    return "$($AssetRoot.relativePath)\media\$Kind"
}

function ConvertTo-LectureContentRelativePath {
    param(
        [string]$ContentRoot,
        [string]$Path
    )

    $fullPath = Resolve-LectureContentPath -ContentRoot $ContentRoot -Path $Path
    if (-not $fullPath.StartsWith(([System.IO.Path]::GetFullPath($ContentRoot)).TrimEnd('\'), [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside the lecture content root: $Path"
    }

    return ConvertTo-LectureRelativePath -BasePath $ContentRoot -FullPath $fullPath
}

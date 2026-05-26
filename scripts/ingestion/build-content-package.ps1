[CmdletBinding()]
param(
    [string]$OutputRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RepoCommit {
    param([string]$Path)
    try {
        $commit = (& git -C $Path rev-parse HEAD 2>$null)
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($commit)) {
            return $commit.Trim()
        }
    }
    catch {
    }
    return $null
}

$repo = (& git -C . rev-parse --show-toplevel).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repo)) {
    throw 'Unable to resolve repository root with git.'
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path (Join-Path (Join-Path $repo '.codex-cache') 'tmp') ('content-package-{0}' -f [Guid]::NewGuid().ToString('N'))
}

[void](New-Item -ItemType Directory -Force -Path $OutputRoot)
[void](New-Item -ItemType Directory -Force -Path (Join-Path $OutputRoot 'sources'))

$scan = (& .\scripts\ingestion\scan-content-sources.ps1 | Out-String) | ConvertFrom-Json
if (@($scan.validationErrors).Count -gt 0) {
    throw 'Cannot build content package while validation errors exist.'
}

$objectsPath = Join-Path $OutputRoot 'objects.jsonl'
if (Test-Path -LiteralPath $objectsPath) {
    Remove-Item -LiteralPath $objectsPath -Force
}

$sourceSummaries = @()
foreach ($source in @($scan.sources)) {
    $sourcePackageRoot = Join-Path (Join-Path $OutputRoot 'sources') $source.id
    [void](New-Item -ItemType Directory -Force -Path $sourcePackageRoot)
    $sourceCommit = Get-RepoCommit -Path $source.resolvedPath

    foreach ($object in @($source.objects)) {
        $sourceFile = Join-Path $source.resolvedPath $object.sourcePath
        $destFile = Join-Path $sourcePackageRoot $object.sourcePath
        $destParent = Split-Path -Parent $destFile
        if (-not [string]::IsNullOrWhiteSpace($destParent)) {
            [void](New-Item -ItemType Directory -Force -Path $destParent)
        }
        Copy-Item -LiteralPath $sourceFile -Destination $destFile -Force

        $packageObject = [ordered]@{
            id = $object.id
            sourceId = $object.sourceId
            sourceRepo = $object.sourceRepo
            sourcePath = $object.sourcePath
            sourceCommit = $sourceCommit
            type = $object.type
            title = $object.title
            license = $object.license
            attribution = $object.attribution
        }
        Add-Content -LiteralPath $objectsPath -Value ($packageObject | ConvertTo-Json -Compress)
    }

    $sourceSummaries += [ordered]@{
        id = $source.id
        title = $source.title
        resolvedPath = $source.resolvedPath
        manifestPath = $source.manifestPath
        sourceCommit = $sourceCommit
        objectCount = $source.objectCount
    }
}

$package = [ordered]@{
    schemaVersion = 1
    generatedAt = (Get-Date).ToString('o')
    registryPath = $scan.registryPath
    sourceCount = $scan.sourceCount
    objectCount = $scan.objectCount
    sources = $sourceSummaries
    objectsPath = 'objects.jsonl'
    sourcesPath = 'sources'
}
$packagePath = Join-Path $OutputRoot 'package.json'
$package | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $packagePath

[ordered]@{
    schemaVersion = 1
    outputRoot = (Resolve-Path -LiteralPath $OutputRoot).Path
    packagePath = $packagePath
    objectsPath = $objectsPath
    sourceCount = $scan.sourceCount
    objectCount = $scan.objectCount
} | ConvertTo-Json -Depth 8

exit 0

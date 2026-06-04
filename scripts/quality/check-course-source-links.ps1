[CmdletBinding()]
param(
    [string]$RegistryPath = '.\content-sources.json',
    [string]$SourceId = '',
    [switch]$FailOnWarnings
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Add-AuditMessage {
    param(
        [System.Collections.Generic.List[string]]$List,
        [string]$Message
    )
    $List.Add($Message)
}

function ConvertTo-RepoPath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $Path))
}

function ConvertTo-RelativePath {
    param(
        [string]$Root,
        [string]$Path
    )

    $rootPath = [System.IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if ($fullPath.StartsWith($rootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $fullPath.Substring($rootPath.Length)
    }
    return $fullPath
}

function Split-MarkdownTableRow {
    param([string]$Line)

    $trimmed = $Line.Trim()
    if (-not $trimmed.StartsWith('|')) {
        return @()
    }
    $trimmed = $trimmed.Trim('|')
    return @($trimmed -split '\|' | ForEach-Object { $_.Trim() })
}

function ConvertTo-NormalizedColumnName {
    param([string]$Value)

    return (($Value.ToLowerInvariant() -replace '[^a-z0-9]+', '')).Trim()
}

function Get-UrlFromCell {
    param([string]$Cell)

    $markdownLink = [regex]::Match($Cell, '\[[^\]]+\]\((https?://[^)]+)\)')
    if ($markdownLink.Success) {
        return $markdownLink.Groups[1].Value.Trim()
    }
    $bareUrl = [regex]::Match($Cell, 'https?://\S+')
    if ($bareUrl.Success) {
        return $bareUrl.Value.Trim().TrimEnd('.', ',', ';')
    }
    return $Cell.Trim()
}

function Test-SeparatorRow {
    param([string[]]$Cells)

    if ($Cells.Count -eq 0) {
        return $false
    }
    foreach ($cell in $Cells) {
        if ($cell -notmatch '^:?-{3,}:?$') {
            return $false
        }
    }
    return $true
}

function Read-ExternalSourceLinkRows {
    param(
        [string]$Path,
        [string]$RelativePath,
        [System.Collections.Generic.List[string]]$Errors,
        [System.Collections.Generic.List[string]]$Warnings
    )

    $lines = Get-Content -LiteralPath $Path
    $sectionStart = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^#{2,4}\s+External Source Links\s*$') {
            $sectionStart = $i
            break
        }
    }

    if ($sectionStart -lt 0) {
        Add-AuditMessage $Warnings "Missing External Source Links section: $RelativePath"
        return @()
    }

    $tableLines = [System.Collections.Generic.List[string]]::new()
    for ($i = $sectionStart + 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^#{1,4}\s+') {
            break
        }
        if ($lines[$i].Trim().StartsWith('|')) {
            $tableLines.Add($lines[$i])
        }
    }

    if ($tableLines.Count -lt 3) {
        Add-AuditMessage $Errors "External Source Links section has no Markdown table rows: $RelativePath"
        return @()
    }

    $headers = Split-MarkdownTableRow -Line $tableLines[0]
    $separator = Split-MarkdownTableRow -Line $tableLines[1]
    if (-not (Test-SeparatorRow -Cells $separator)) {
        Add-AuditMessage $Errors "External Source Links table is missing a separator row: $RelativePath"
        return @()
    }

    $columnMap = @{}
    for ($i = 0; $i -lt $headers.Count; $i++) {
        $columnMap[(ConvertTo-NormalizedColumnName -Value $headers[$i])] = $i
    }

    $requiredColumns = @(
        'provider',
        'title',
        'url',
        'sourcetype',
        'borrowedpattern',
        'licenseuseboundary',
        'lastreviewed',
        'brokenlinkstatus'
    )
    foreach ($column in $requiredColumns) {
        if (-not $columnMap.ContainsKey($column)) {
            Add-AuditMessage $Errors "External Source Links table missing column '$column': $RelativePath"
        }
    }
    if ($Errors.Count -gt 0) {
        return @()
    }

    $rows = @()
    for ($i = 2; $i -lt $tableLines.Count; $i++) {
        $cells = Split-MarkdownTableRow -Line $tableLines[$i]
        if ($cells.Count -lt $headers.Count) {
            Add-AuditMessage $Errors "External Source Links row has too few cells: $RelativePath line $($sectionStart + $i + 1)"
            continue
        }

        $row = [ordered]@{
            provider = $cells[$columnMap.provider]
            title = $cells[$columnMap.title]
            url = Get-UrlFromCell -Cell $cells[$columnMap.url]
            sourceType = $cells[$columnMap.sourcetype]
            borrowedPattern = $cells[$columnMap.borrowedpattern]
            licenseUseBoundary = $cells[$columnMap.licenseuseboundary]
            lastReviewed = $cells[$columnMap.lastreviewed]
            brokenLinkStatus = $cells[$columnMap.brokenlinkstatus]
            sourcePath = $RelativePath
            line = $sectionStart + $i + 1
        }
        $rows += [pscustomobject]$row
    }

    return $rows
}

function Test-SourceLinkRow {
    param(
        [object]$Row,
        [System.Collections.Generic.List[string]]$Errors
    )

    $context = "$($Row.sourcePath):$($Row.line)"
    if ([string]::IsNullOrWhiteSpace($Row.provider)) {
        Add-AuditMessage $Errors "Source link missing provider: $context"
    }
    if ([string]::IsNullOrWhiteSpace($Row.title)) {
        Add-AuditMessage $Errors "Source link missing title: $context"
    }
    if ([string]::IsNullOrWhiteSpace($Row.url) -or $Row.url -notmatch '^https?://') {
        Add-AuditMessage $Errors "Source link must use an http or https URL without local asset download: $context"
    }
    if ([string]::IsNullOrWhiteSpace($Row.sourceType)) {
        Add-AuditMessage $Errors "Source link missing source type: $context"
    }
    if ([string]::IsNullOrWhiteSpace($Row.borrowedPattern)) {
        Add-AuditMessage $Errors "Source link missing borrowed pattern: $context"
    }
    if ([string]::IsNullOrWhiteSpace($Row.licenseUseBoundary) -or $Row.licenseUseBoundary -match '^(tbd|unknown)$') {
        Add-AuditMessage $Errors "Source link missing license/use-boundary note: $context"
    }
    if ($Row.lastReviewed -notmatch '^\d{4}-\d{2}-\d{2}$') {
        Add-AuditMessage $Errors "Source link last-reviewed date must be YYYY-MM-DD: $context"
    }
    $allowedBrokenLinkStatus = @('unknown', 'unchecked', 'not-checked', 'ok', 'broken', 'redirect')
    if ([string]::IsNullOrWhiteSpace($Row.brokenLinkStatus) -or -not ($allowedBrokenLinkStatus -contains $Row.brokenLinkStatus.ToLowerInvariant())) {
        Add-AuditMessage $Errors "Source link broken-link status must be one of: $($allowedBrokenLinkStatus -join ', '): $context"
    }
}

$errors = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
$registryFullPath = ConvertTo-RepoPath -Path $RegistryPath

if (-not (Test-Path -LiteralPath $registryFullPath -PathType Leaf)) {
    throw "Missing content source registry: $RegistryPath"
}

$registry = Get-Content -LiteralPath $registryFullPath -Raw | ConvertFrom-Json
$sourceReports = @()
$totalFiles = 0
$totalLinks = 0

foreach ($source in @($registry.contentSources)) {
    if (-not [string]::IsNullOrWhiteSpace($SourceId) -and $source.id -ne $SourceId) {
        continue
    }

    $sourceRoot = ConvertTo-RepoPath -Path ([string]$source.localPath)
    $manifestPath = Join-Path $sourceRoot ([string]$source.contentManifest)
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        Add-AuditMessage $errors "Missing content manifest for source '$($source.id)': $manifestPath"
        continue
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $studyPlanRoot = Join-Path $sourceRoot ([string]$manifest.paths.studyPlans)
    $courseRoot = Join-Path $studyPlanRoot 'courses'
    $scanRoot = if (Test-Path -LiteralPath $courseRoot -PathType Container) { $courseRoot } else { $studyPlanRoot }
    if (-not (Test-Path -LiteralPath $scanRoot -PathType Container)) {
        Add-AuditMessage $warnings "No study-plan scan root for source '$($source.id)': $scanRoot"
        continue
    }

    $fileReports = @()
    foreach ($file in Get-ChildItem -LiteralPath $scanRoot -Recurse -File -Filter '*.md') {
        $relativePath = ConvertTo-RelativePath -Root $sourceRoot -Path $file.FullName
        $rows = @(Read-ExternalSourceLinkRows -Path $file.FullName -RelativePath $relativePath -Errors $errors -Warnings $warnings)
        foreach ($row in $rows) {
            Test-SourceLinkRow -Row $row -Errors $errors
        }

        $fileReports += [pscustomobject][ordered]@{
            path = $relativePath
            externalSourceLinkCount = $rows.Count
            hasExternalSourceLinksSection = ($rows.Count -gt 0)
        }
        $totalFiles++
        $totalLinks += $rows.Count
    }

    $sourceLinkCount = 0
    foreach ($fileReport in @($fileReports)) {
        $sourceLinkCount += [int]$fileReport.externalSourceLinkCount
    }

    $sourceReports += [ordered]@{
        sourceId = $source.id
        sourceRepo = Split-Path -Leaf $sourceRoot
        scanRoot = ConvertTo-RelativePath -Root $sourceRoot -Path $scanRoot
        fileCount = $fileReports.Count
        externalSourceLinkCount = $sourceLinkCount
        files = @($fileReports)
    }
}

if ($FailOnWarnings) {
    foreach ($warning in @($warnings)) {
        Add-AuditMessage $errors "Warning promoted to error: $warning"
    }
}

[ordered]@{
    schemaVersion = 1
    checkedAt = (Get-Date).ToString('o')
    registryPath = $registryFullPath
    readOnly = $true
    networkAccess = 'none'
    assetDownloadPolicy = 'never-download-course-assets'
    sourceCount = $sourceReports.Count
    courseFileCount = $totalFiles
    externalSourceLinkCount = $totalLinks
    errorCount = $errors.Count
    warningCount = $warnings.Count
    errors = @($errors)
    warnings = @($warnings)
    sources = @($sourceReports)
} | ConvertTo-Json -Depth 12

if ($errors.Count -gt 0) {
    exit 1
}

exit 0

[CmdletBinding()]
param(
    [string]$RegistryPath = '.\content-sources.json',
    [string]$OutputPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Add-ValidationError {
    param(
        [System.Collections.Generic.List[string]]$Errors,
        [string]$Message
    )
    $Errors.Add($Message)
}

function Get-MarkdownTitle {
    param([string]$Path)

    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^\s*#\s+(.+?)\s*$') {
            return $Matches[1]
        }
    }

    return [System.IO.Path]::GetFileNameWithoutExtension($Path)
}

function Get-JsonTitle {
    param([string]$Path)

    try {
        $json = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        if (-not [string]::IsNullOrWhiteSpace([string]$json.title)) {
            return [string]$json.title
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$json.packageId)) {
            return [string]$json.packageId
        }
    }
    catch {
        return [System.IO.Path]::GetFileNameWithoutExtension($Path)
    }

    return [System.IO.Path]::GetFileNameWithoutExtension($Path)
}

function Get-RelativePath {
    param(
        [string]$BasePath,
        [string]$FullPath
    )

    $baseUri = [System.Uri]((Resolve-Path -LiteralPath $BasePath).Path.TrimEnd('\') + '\')
    $fileUri = [System.Uri]((Resolve-Path -LiteralPath $FullPath).Path)
    return [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($fileUri).ToString()).Replace('/', '\')
}

$registryFullPath = (Resolve-Path -LiteralPath $RegistryPath).Path
$registryRoot = Split-Path -Parent $registryFullPath
$errors = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
$sources = @()

$registry = Get-Content -LiteralPath $registryFullPath -Raw | ConvertFrom-Json
if ($registry.schemaVersion -ne 1) {
    Add-ValidationError $errors "Registry schemaVersion must be 1."
}
if (-not $registry.contentSources) {
    Add-ValidationError $errors "Registry must include contentSources."
}

$seenIds = @{}
foreach ($source in $registry.contentSources) {
    $sourceErrors = [System.Collections.Generic.List[string]]::new()
    $sourceWarnings = [System.Collections.Generic.List[string]]::new()
    $objects = @()

    if ([string]::IsNullOrWhiteSpace($source.id)) {
        Add-ValidationError $sourceErrors 'Content source is missing id.'
    }
    elseif ($seenIds.ContainsKey($source.id)) {
        Add-ValidationError $sourceErrors "Duplicate content source id '$($source.id)'."
    }
    else {
        $seenIds[$source.id] = $true
    }

    if ([string]::IsNullOrWhiteSpace($source.localPath)) {
        Add-ValidationError $sourceErrors "Content source '$($source.id)' is missing localPath."
    }
    if ([string]::IsNullOrWhiteSpace($source.contentManifest)) {
        Add-ValidationError $sourceErrors "Content source '$($source.id)' is missing contentManifest."
    }

    $sourceRoot = $null
    if ($sourceErrors.Count -eq 0) {
        $candidateRoot = Join-Path $registryRoot $source.localPath
        if (-not (Test-Path -LiteralPath $candidateRoot -PathType Container)) {
            Add-ValidationError $sourceErrors "Content source '$($source.id)' path does not exist: $candidateRoot"
        }
        else {
            $sourceRoot = (Resolve-Path -LiteralPath $candidateRoot).Path
        }
    }

    $manifest = $null
    $manifestPath = $null
    if ($sourceRoot) {
        $manifestPath = Join-Path $sourceRoot $source.contentManifest
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            Add-ValidationError $sourceErrors "Content source '$($source.id)' manifest does not exist: $manifestPath"
        }
        else {
            try {
                $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            }
            catch {
                Add-ValidationError $sourceErrors "Content source '$($source.id)' manifest is not valid JSON: $manifestPath"
            }
        }
    }

    if ($manifest) {
        if ($manifest.schemaVersion -ne 1) {
            Add-ValidationError $sourceErrors "Content source '$($source.id)' manifest schemaVersion must be 1."
        }
        if ($manifest.id -ne $source.id) {
            Add-ValidationError $sourceErrors "Content source '$($source.id)' manifest id '$($manifest.id)' does not match registry id."
        }
        if ($manifest.role -ne 'content-repository') {
            Add-ValidationError $sourceErrors "Content source '$($source.id)' manifest role must be content-repository."
        }
        if (-not $manifest.paths.studyPlans) {
            Add-ValidationError $sourceErrors "Content source '$($source.id)' manifest is missing paths.studyPlans."
        }
        if (-not $manifest.paths.resources) {
            Add-ValidationError $sourceErrors "Content source '$($source.id)' manifest is missing paths.resources."
        }
        if (-not $manifest.license) {
            $sourceWarnings.Add("Content source '$($source.id)' manifest is missing license.")
        }
        if (-not $manifest.attribution) {
            $sourceWarnings.Add("Content source '$($source.id)' manifest is missing attribution.")
        }
    }

    if ($sourceRoot -and $manifest -and $sourceErrors.Count -eq 0) {
        $declaredFolders = @(
            @{ Type = 'study-plan'; Path = $manifest.paths.studyPlans; Filter = '*.md'; TitleKind = 'markdown' },
            @{ Type = 'resource'; Path = $manifest.paths.resources; Filter = '*.md'; TitleKind = 'markdown' }
        )
        if ($manifest.paths.objectives) {
            $declaredFolders += @{ Type = 'objective'; Path = $manifest.paths.objectives; Filter = '*.md'; TitleKind = 'markdown' }
        }
        if ($manifest.paths.assessments) {
            $declaredFolders += @{ Type = 'assessment'; Path = $manifest.paths.assessments; Filter = '*.md'; TitleKind = 'markdown' }
        }
        if (($manifest.paths.PSObject.Properties.Name -contains 'generatedLectures') -and $manifest.paths.generatedLectures) {
            $declaredFolders += @{ Type = 'generated-lecture'; Path = $manifest.paths.generatedLectures; Filter = 'lecture-video.json'; TitleKind = 'json' }
        }

        foreach ($folder in $declaredFolders) {
            $folderPath = Join-Path $sourceRoot $folder.Path
            if (-not (Test-Path -LiteralPath $folderPath -PathType Container)) {
                Add-ValidationError $sourceErrors "Content source '$($source.id)' declared folder missing: $folderPath"
                continue
            }

            foreach ($file in Get-ChildItem -LiteralPath $folderPath -Recurse -File -Filter $folder.Filter | Sort-Object FullName) {
                $relativePath = Get-RelativePath -BasePath $sourceRoot -FullPath $file.FullName
                $title = if ($folder.TitleKind -eq 'json') {
                    Get-JsonTitle -Path $file.FullName
                }
                else {
                    Get-MarkdownTitle -Path $file.FullName
                }
                $objects += [ordered]@{
                    id = ('{0}:{1}' -f $source.id, $relativePath.Replace('\', '/'))
                    sourceId = $source.id
                    sourceRepo = Split-Path -Leaf $sourceRoot
                    sourcePath = $relativePath
                    type = $folder.Type
                    title = $title
                    license = if ($manifest.license) { $manifest.license } else { 'UNSPECIFIED' }
                    attribution = if ($manifest.attribution) { $manifest.attribution } else { $manifest.title }
                }
            }
        }
    }

    foreach ($errorMessage in $sourceErrors) {
        $errors.Add($errorMessage)
    }
    foreach ($warningMessage in $sourceWarnings) {
        $warnings.Add($warningMessage)
    }

    $sources += [ordered]@{
        id = $source.id
        title = $source.title
        localPath = $source.localPath
        resolvedPath = $sourceRoot
        manifestPath = $manifestPath
        objectCount = $objects.Count
        validationErrors = @($sourceErrors)
        validationWarnings = @($sourceWarnings)
        objects = $objects
    }
}

$report = [ordered]@{
    schemaVersion = 1
    generatedAt = (Get-Date).ToString('o')
    registryPath = $registryFullPath
    sourceCount = $sources.Count
    objectCount = ($sources | ForEach-Object { $_.objectCount } | Measure-Object -Sum).Sum
    validationErrors = @($errors)
    validationWarnings = @($warnings)
    sources = $sources
}

$json = $report | ConvertTo-Json -Depth 10
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $outputParent = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($outputParent)) {
        [void](New-Item -ItemType Directory -Force -Path $outputParent)
    }
    Set-Content -LiteralPath $OutputPath -Value $json
}

Write-Output $json

if ($errors.Count -gt 0) {
    exit 1
}

exit 0

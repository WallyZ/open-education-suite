[CmdletBinding()]
param(
    [string]$RegistryPath = '.\content-sources.json',
    [string]$SourceId = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Add-QualityMessage {
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

function Test-CoursePattern {
    param(
        [string]$Content,
        [string]$Pattern
    )

    $options = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Multiline
    return [regex]::IsMatch($Content, $Pattern, $options)
}

function New-RequirementResult {
    param(
        [string]$Id,
        [string]$Label,
        [bool]$Passed,
        [string]$Evidence,
        [string]$Failure
    )

    return [pscustomobject][ordered]@{
        id = $Id
        label = $Label
        passed = $Passed
        evidence = $Evidence
        failure = $Failure
    }
}

function Test-CourseDesign {
    param(
        [string]$Path,
        [string]$RelativePath,
        [System.Collections.Generic.List[string]]$Errors
    )

    $content = Get-Content -LiteralPath $Path -Raw
    $results = @()

    $hasObjectives = (Test-CoursePattern -Content $content -Pattern '^##\s+Learning Outcomes\s*$') -and
        (Test-CoursePattern -Content $content -Pattern ':objectives/course/')
    $results += New-RequirementResult -Id 'objectives' -Label 'Objectives' -Passed $hasObjectives -Evidence 'Learning Outcomes section with objective IDs' -Failure 'Missing Learning Outcomes section with objective IDs.'

    $hasPractice = (Test-CoursePattern -Content $content -Pattern '^##\s+(Weekly Plan|Practice)\s*$') -and
        (Test-CoursePattern -Content $content -Pattern '(studio work|practice|exercise|checkpoint)')
    $results += New-RequirementResult -Id 'practice' -Label 'Practice' -Passed $hasPractice -Evidence 'Weekly Plan or Practice section with practice evidence' -Failure 'Missing practice or weekly studio-work evidence.'

    $hasAssessment = (Test-CoursePattern -Content $content -Pattern '^##\s+Quizzes\s*$') -and
        (Test-CoursePattern -Content $content -Pattern '^##\s+(Tests?|Practical Test)\s*$')
    $results += New-RequirementResult -Id 'assessment' -Label 'Assessment' -Passed $hasAssessment -Evidence 'Quiz and test assessment sections' -Failure 'Missing quiz and test assessment sections.'

    $hasProjectWork = (Test-CoursePattern -Content $content -Pattern '^##\s+(Projects?|Final Project|Required Launch Artifacts)\s*$') -and
        (Test-CoursePattern -Content $content -Pattern '^##\s+Portfolio Evidence\s*$')
    $results += New-RequirementResult -Id 'project-work' -Label 'Project work' -Passed $hasProjectWork -Evidence 'Project work and Portfolio Evidence sections' -Failure 'Missing project work or portfolio evidence.'

    $hasSourceLinks = (Test-CoursePattern -Content $content -Pattern '\[[^\]]+\]\([^)]+\)') -and
        ((Test-CoursePattern -Content $content -Pattern 'Shared references') -or (Test-CoursePattern -Content $content -Pattern '^##\s+External Source Links\s*$'))
    $results += New-RequirementResult -Id 'citations-source-links' -Label 'Citations/source links' -Passed $hasSourceLinks -Evidence 'Shared references or External Source Links with Markdown links' -Failure 'Missing citations or source links.'

    $hasAccessibility = (Test-CoursePattern -Content $content -Pattern 'accessibility') -and
        (Test-CoursePattern -Content $content -Pattern '(captions?|transcripts?|text alternatives?|equivalent|accessible)')
    $results += New-RequirementResult -Id 'accessibility-notes' -Label 'Accessibility notes' -Passed $hasAccessibility -Evidence 'Accessibility note with learner-access support' -Failure 'Missing accessibility notes.'

    $hasAdaptiveRemediation = (Test-CoursePattern -Content $content -Pattern '(adaptive|remediation)') -and
        (Test-CoursePattern -Content $content -Pattern '(objective IDs?|assessment bank|quiz|test|project evidence|practice variants?|review)')
    $results += New-RequirementResult -Id 'adaptive-remediation-metadata' -Label 'Adaptive remediation metadata' -Passed $hasAdaptiveRemediation -Evidence 'Adaptive remediation note tied to objectives, assessments, practice, and review' -Failure 'Missing adaptive remediation metadata.'

    foreach ($result in @($results | Where-Object { -not $_.passed })) {
        Add-QualityMessage $Errors "Course design quality failure in ${RelativePath}: $($result.failure)"
    }

    return [pscustomobject][ordered]@{
        path = $RelativePath
        title = if (Test-CoursePattern -Content $content -Pattern '^#\s+(.+)$') { ([regex]::Match($content, '^#\s+(.+)$', [System.Text.RegularExpressions.RegexOptions]::Multiline)).Groups[1].Value.Trim() } else { [System.IO.Path]::GetFileNameWithoutExtension($Path) }
        passed = @($results | Where-Object { -not $_.passed }).Count -eq 0
        requirements = @($results)
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
$totalCourses = 0

foreach ($source in @($registry.contentSources)) {
    if (-not [string]::IsNullOrWhiteSpace($SourceId) -and $source.id -ne $SourceId) {
        continue
    }

    $sourceRoot = ConvertTo-RepoPath -Path ([string]$source.localPath)
    $manifestPath = Join-Path $sourceRoot ([string]$source.contentManifest)
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        Add-QualityMessage $errors "Missing content manifest for source '$($source.id)': $manifestPath"
        continue
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $studyPlanRoot = Join-Path $sourceRoot ([string]$manifest.paths.studyPlans)
    $courseRoot = Join-Path $studyPlanRoot 'courses'
    if (-not (Test-Path -LiteralPath $courseRoot -PathType Container)) {
        Add-QualityMessage $warnings "No course directory for source '$($source.id)': $courseRoot"
        continue
    }

    $courseReports = @()
    foreach ($file in Get-ChildItem -LiteralPath $courseRoot -Recurse -File -Filter '*.md') {
        $relativePath = ConvertTo-RelativePath -Root $sourceRoot -Path $file.FullName
        $courseReports += Test-CourseDesign -Path $file.FullName -RelativePath $relativePath -Errors $errors
        $totalCourses++
    }

    $sourceReports += [ordered]@{
        sourceId = $source.id
        sourceRepo = Split-Path -Leaf $sourceRoot
        courseCount = $courseReports.Count
        courses = @($courseReports)
    }
}

[ordered]@{
    schemaVersion = 1
    checkedAt = (Get-Date).ToString('o')
    registryPath = $registryFullPath
    readOnly = $true
    networkAccess = 'none'
    courseCount = $totalCourses
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

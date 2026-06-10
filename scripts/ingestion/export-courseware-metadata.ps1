[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PackageRoot,

    [string]$OutputPath = '',
    [string]$CourseId = 'open-education-suite-package',
    [string]$Title = 'Open Education Suite Content Package',
    [string]$Summary = 'Public-safe metadata handoff for a local Open Education Suite content package.'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-SafeId {
    param(
        [object]$Value,
        [string]$Fallback
    )

    $raw = ([string]$Value).Trim().ToLowerInvariant()
    $clean = [regex]::Replace($raw, '[^a-z0-9._-]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($clean)) {
        $clean = $Fallback
    }
    if ($clean -notmatch '^[a-z0-9]') {
        $clean = "id-$clean"
    }
    return $clean
}

function Assert-PublicSafeJson {
    param([string]$Json)

    if ($Json -match '[A-Za-z]:\\\\') {
        throw 'Courseware metadata contract must not contain absolute Windows paths.'
    }
    if ($Json -match '\\\\[^"]+') {
        throw 'Courseware metadata contract must not contain UNC paths.'
    }
}

$packagePath = Join-Path $PackageRoot 'package.json'
$objectsPath = Join-Path $PackageRoot 'objects.jsonl'

if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
    throw "Missing package.json: $packagePath"
}
if (-not (Test-Path -LiteralPath $objectsPath -PathType Leaf)) {
    throw "Missing objects.jsonl: $objectsPath"
}

$package = Get-Content -LiteralPath $packagePath -Raw | ConvertFrom-Json
$objects = @()
foreach ($line in @(Get-Content -LiteralPath $objectsPath)) {
    if (-not [string]::IsNullOrWhiteSpace($line)) {
        $objects += ($line | ConvertFrom-Json)
    }
}

if ($objects.Count -lt 1) {
    throw 'Courseware metadata export requires at least one packaged object.'
}

$outcomeObjects = @($objects | Where-Object { $_.type -eq 'objective' } | Select-Object -First 12)
if ($outcomeObjects.Count -lt 1) {
    $outcomeObjects = @($objects | Select-Object -First 1)
}

$learningOutcomes = @()
foreach ($object in $outcomeObjects) {
    $outcomeId = ConvertTo-SafeId -Value $object.id -Fallback 'outcome-1'
    $learningOutcomes += [ordered]@{
        outcome_id = $outcomeId
        description = "Understand and apply: $($object.title)"
        mastery_evidence = "Explain and apply '$($object.title)' in an essay, project, or practical artifact."
    }
}

$modules = @()
foreach ($source in @($package.sources)) {
    $sourceObjects = @($objects | Where-Object { $_.sourceId -eq $source.id })
    if ($sourceObjects.Count -lt 1) {
        continue
    }

    $lessonRefs = @()
    foreach ($object in @($sourceObjects | Select-Object -First 50)) {
        $lessonRefs += (ConvertTo-SafeId -Value $object.id -Fallback 'lesson-ref')
    }

    $modules += [ordered]@{
        module_id = ConvertTo-SafeId -Value $source.id -Fallback 'module'
        title = [string]$source.title
        lesson_refs = $lessonRefs
    }
}

if ($modules.Count -lt 1) {
    $modules += [ordered]@{
        module_id = 'package-overview'
        title = 'Package Overview'
        lesson_refs = @($learningOutcomes | ForEach-Object { $_.outcome_id })
    }
}

$payload = [ordered]@{
    schema_version = 'content-courseware/course/v1'
    course_id = ConvertTo-SafeId -Value $CourseId -Fallback 'open-education-suite-package'
    title = $Title
    summary = $Summary
    audience = [ordered]@{
        learner_level = 'mixed'
        prerequisites = @()
    }
    learning_outcomes = $learningOutcomes
    modules = $modules
    assessment_policy = [ordered]@{
        summative_default = 'essay'
        mastery_threshold_percent = 85
        rubric_ref = 'docs/teaching-quality-rubric.md'
    }
    packaging = [ordered]@{
        export_targets = @('learner_ui', 'json_manifest')
        learner_ui_profile = 'adaptive-local'
    }
    privacy_boundary = [ordered]@{
        contains_learner_pii = $false
        contains_private_course_content = $false
        contains_generated_media = $false
        consumer_content_required = $true
        allowed_artifact_refs = @($package.sources | ForEach-Object { ConvertTo-SafeId -Value $_.id -Fallback 'source' })
    }
}

$json = $payload | ConvertTo-Json -Depth 20
Assert-PublicSafeJson -Json $json

if ($OutputPath) {
    $parent = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        [void](New-Item -ItemType Directory -Force -Path $parent)
    }
    $json | Set-Content -LiteralPath $OutputPath
}

$json

exit 0

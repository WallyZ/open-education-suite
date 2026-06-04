[CmdletBinding()]
param(
    [string]$ObjectiveId = 'game-development:objectives/course/gdev-101/design-vocabulary',
    [string]$PackageRoot = '',
    [string]$OutputPath = '',
    [int]$DurationSeconds = 300
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ObjectiveSourceId {
    param([string]$Value)
    return ($Value -split ':')[0]
}

function Get-ObjectiveCourseCode {
    param([string]$Value)
    if ($Value -match ':objectives/course/([^/]+)/') {
        return $Matches[1]
    }
    return ''
}

function Convert-SlugToTitle {
    param([string]$Value)

    $leaf = ($Value -split '/')[-1]
    $words = @($leaf -split '[-_]' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($words.Count -eq 0) {
        return $Value
    }

    return (($words | ForEach-Object {
        if ($_.Length -le 1) {
            $_.ToUpperInvariant()
        }
        else {
            $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1)
        }
    }) -join ' ')
}

function Get-SourceExcerpt {
    param(
        [string]$Text,
        [int]$MaxLength = 900
    )

    $normalized = ($Text -replace "`r`n", "`n") -replace '\s+', ' '
    $normalized = $normalized.Trim()
    if ($normalized.Length -le $MaxLength) {
        return $normalized
    }

    return $normalized.Substring(0, $MaxLength).Trim() + '...'
}

function Select-ContentObjectForObjective {
    param(
        [object[]]$Objects,
        [string]$TargetObjectiveId
    )

    $sourceId = Get-ObjectiveSourceId -Value $TargetObjectiveId
    $courseCode = Get-ObjectiveCourseCode -Value $TargetObjectiveId
    $sourceObjects = @($Objects | Where-Object { $_.sourceId -eq $sourceId })

    if (-not [string]::IsNullOrWhiteSpace($courseCode)) {
        $courseMatches = @($sourceObjects | Where-Object {
            $_.sourcePath -like "*$courseCode*" -or $_.title -like "*$courseCode*"
        })
        if ($courseMatches.Count -gt 0) {
            return @($courseMatches | Sort-Object @{ Expression = {
                if ($_.type -eq 'study-plan' -and $_.sourcePath -like 'study-plans\courses\*') { 0 } else { 1 }
            } }, sourcePath | Select-Object -First 1)[0]
        }
    }

    $studyPlan = @($sourceObjects | Where-Object { $_.type -eq 'study-plan' } | Sort-Object sourcePath | Select-Object -First 1)
    if ($studyPlan.Count -gt 0) {
        return $studyPlan[0]
    }

    $fallback = @($sourceObjects | Sort-Object sourcePath | Select-Object -First 1)
    if ($fallback.Count -gt 0) {
        return $fallback[0]
    }

    throw "No content object found for objective source: $sourceId"
}

function Get-PackageObjects {
    param([string]$Root)

    $objectsPath = Join-Path $Root 'objects.jsonl'
    if (-not (Test-Path -LiteralPath $objectsPath -PathType Leaf)) {
        throw "Content package is missing objects.jsonl: $objectsPath"
    }

    $objects = @()
    foreach ($line in Get-Content -LiteralPath $objectsPath) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            $objects += ($line | ConvertFrom-Json)
        }
    }

    return $objects
}

function Get-LiveObjects {
    $scan = (& .\scripts\ingestion\scan-content-sources.ps1 | Out-String) | ConvertFrom-Json
    if (@($scan.validationErrors).Count -gt 0) {
        throw 'Cannot build a lecture plan while content source validation errors exist.'
    }

    $objects = @()
    foreach ($source in @($scan.sources)) {
        foreach ($object in @($source.objects)) {
            $object | Add-Member -NotePropertyName resolvedSourceRoot -NotePropertyValue $source.resolvedPath -Force
            $objects += $object
        }
    }

    return $objects
}

function Resolve-SourceFilePath {
    param(
        [object]$ContentObject,
        [string]$Root
    )

    if (-not [string]::IsNullOrWhiteSpace($Root)) {
        return Join-Path (Join-Path (Join-Path $Root 'sources') $ContentObject.sourceId) $ContentObject.sourcePath
    }

    return Join-Path $ContentObject.resolvedSourceRoot $ContentObject.sourcePath
}

if ($DurationSeconds -lt 120 -or $DurationSeconds -gt 1800) {
    throw 'DurationSeconds must be between 120 and 1800.'
}

$objects = if ([string]::IsNullOrWhiteSpace($PackageRoot)) {
    Get-LiveObjects
}
else {
    Get-PackageObjects -Root $PackageRoot
}

$contentObject = Select-ContentObjectForObjective -Objects $objects -TargetObjectiveId $ObjectiveId
$sourceFilePath = Resolve-SourceFilePath -ContentObject $contentObject -Root $PackageRoot
if (-not (Test-Path -LiteralPath $sourceFilePath -PathType Leaf)) {
    throw "Selected source file does not exist: $sourceFilePath"
}

$sourceText = Get-Content -LiteralPath $sourceFilePath -Raw
$objectiveTitle = Convert-SlugToTitle -Value $ObjectiveId
$citationId = 'source-1'
$courseCode = Get-ObjectiveCourseCode -Value $ObjectiveId
$shortCourse = if ([string]::IsNullOrWhiteSpace($courseCode)) { $contentObject.title } else { $courseCode.ToUpperInvariant() }

$plan = [ordered]@{
    schemaVersion = 1
    objectiveId = $ObjectiveId
    lecturePlanId = ('lecture-plan:{0}' -f (($ObjectiveId -replace '[^A-Za-z0-9]+', '-').Trim('-').ToLowerInvariant()))
    title = ('Original Lecture Plan: {0}' -f $objectiveTitle)
    durationSeconds = $DurationSeconds
    contentSource = [ordered]@{
        sourceId = $contentObject.sourceId
        sourceRepo = $contentObject.sourceRepo
        sourcePath = $contentObject.sourcePath
        title = $contentObject.title
        license = $contentObject.license
        attribution = $contentObject.attribution
    }
    citations = @(
        [ordered]@{
            citationId = $citationId
            sourceId = $contentObject.sourceId
            sourceRepo = $contentObject.sourceRepo
            sourcePath = $contentObject.sourcePath
            claim = ('The selected content object grounds the objective "{0}" for this original lecture plan.' -f $ObjectiveId)
        }
    )
    sourceExcerpt = Get-SourceExcerpt -Text $sourceText
    script = [ordered]@{
        format = 'markdown'
        text = @"
# $objectiveTitle

Open with a concrete learner problem: how can we explain this objective in a way that leads to evidence, not passive familiarity? For $shortCourse, the source material frames this objective inside a course plan with practice, readings, assessment handoff, and portfolio evidence. [$citationId]

Define the key vocabulary in learner-safe language, then immediately apply it to a small example. Keep the example original and avoid copying source prose. Ask the learner to predict the next step before revealing the answer.

Common misconception check: if the learner describes the topic with vague preference words, redirect them toward observable behavior, constraints, evidence, and the course objective. Tie the correction back to the cited source object. [$citationId]

Close with a short practice handoff: the learner should produce one piece of evidence that can be reviewed by the adaptive teacher without treating video completion as mastery.
"@
    }
    storyboard = @(
        [ordered]@{
            sceneId = 'opening-problem'
            startSecond = 0
            endSecond = [Math]::Floor($DurationSeconds * 0.20)
            visual = 'Generated instructor introduces an original problem statement beside the objective title.'
            narrationCue = 'Name the objective, why it matters, and what evidence the learner will create.'
            activeRecallPrompt = 'What would count as evidence that you understand this objective?'
            citationIds = @($citationId)
        },
        [ordered]@{
            sceneId = 'worked-example'
            startSecond = [Math]::Floor($DurationSeconds * 0.20)
            endSecond = [Math]::Floor($DurationSeconds * 0.55)
            visual = 'Original board or slide example with labels revealed in stages.'
            narrationCue = 'Apply the objective to a small original example and narrate the reasoning.'
            activeRecallPrompt = 'Pause before the reveal and predict the next label or decision.'
            citationIds = @($citationId)
        },
        [ordered]@{
            sceneId = 'misconception-check'
            startSecond = [Math]::Floor($DurationSeconds * 0.55)
            endSecond = [Math]::Floor($DurationSeconds * 0.78)
            visual = 'Two-column contrast between a weak answer and an evidence-grounded answer.'
            narrationCue = 'Correct one likely misconception without copying source text or external lectures.'
            activeRecallPrompt = 'Which answer gives observable evidence, and which only gives an opinion?'
            citationIds = @($citationId)
        },
        [ordered]@{
            sceneId = 'practice-handoff'
            startSecond = [Math]::Floor($DurationSeconds * 0.78)
            endSecond = $DurationSeconds
            visual = 'Checklist for the learner artifact the adaptive teacher should review next.'
            narrationCue = 'Assign one short artifact and state that checkpoint evidence, not watch completion, drives mastery.'
            activeRecallPrompt = 'Write the artifact you will submit for feedback.'
            citationIds = @($citationId)
        }
    )
    licenseBoundaries = [ordered]@{
        originalScriptRequired = $true
        copyPolicy = 'Do not copy source prose, transcripts, slides, hosted media, instructor voice, likeness, or branded style.'
        archivePolicy = 'Generated lecture assets need checksums and a license audit before becoming required course media.'
    }
    qaExpectations = @(
        'source-grounding',
        'license-safety',
        'accessibility',
        'active-recall',
        'assessment-handoff'
    )
}

$json = $plan | ConvertTo-Json -Depth 12
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $outputParent = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($outputParent)) {
        [void](New-Item -ItemType Directory -Force -Path $outputParent)
    }
    Set-Content -LiteralPath $OutputPath -Value $json
}

Write-Output $json
exit 0

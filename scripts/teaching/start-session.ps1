[CmdletBinding()]
param(
    [string]$StatePath = '.\fixtures\learner-state.valid.json',
    [string]$Response = '',
    [int]$HintsUsed = 0,
    [string]$OutputStatePath = '',
    [datetime]$Now = '2026-05-25T12:00:00Z',
    [switch]$NonInteractive,
    [switch]$KeepArtifacts
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-SessionTempRoot {
    $repo = (& git -C . rev-parse --show-toplevel).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repo)) {
        throw 'Unable to resolve repository root with git.'
    }
    $runId = ('session_{0:yyyyMMdd_HHmmss}_{1}' -f (Get-Date), [Guid]::NewGuid().ToString('N').Substring(0, 8))
    $tmpRoot = Join-Path (Join-Path (Join-Path $repo '.codex-cache') 'tmp') $runId
    [void](New-Item -ItemType Directory -Force -Path $tmpRoot)
    return $tmpRoot
}

function Convert-StateToScenario {
    param([object]$State)
    [ordered]@{
        schemaVersion = 1
        learners = @(
            [ordered]@{
                learnerId = $State.learnerId
                profile = $State.profile
                objectiveMastery = @($State.mastery)
                misconceptions = @($State.misconceptions)
                learningEvents = @($State.learningEvents)
            }
        )
    }
}

function Get-ObjectiveCourseCode {
    param([string]$ObjectiveId)

    if ($ObjectiveId -match ':objectives/course/([^/]+)/') {
        return $Matches[1]
    }

    return ''
}

function Select-SourceObjectsForObjective {
    param(
        [object[]]$SourceObjects,
        [string]$ObjectiveId
    )

    $courseCode = Get-ObjectiveCourseCode -ObjectiveId $ObjectiveId
    if (-not [string]::IsNullOrWhiteSpace($courseCode)) {
        $courseMatches = @($SourceObjects | Where-Object {
            $_.sourcePath -like "*$courseCode*" -or $_.title -like "*$courseCode*"
        })
        if ($courseMatches.Count -gt 0) {
            return $courseMatches
        }
    }

    return @($SourceObjects)
}

$tmpRoot = New-SessionTempRoot
try {
    $scanReport = (& .\scripts\ingestion\scan-content-sources.ps1 | Out-String) | ConvertFrom-Json
    if (@($scanReport.validationErrors).Count -gt 0) {
        throw 'Cannot start session while content source validation errors exist.'
    }

    $state = (& .\scripts\state\read-learner-state.ps1 -Path $StatePath | Out-String) | ConvertFrom-Json
    $scenarioPath = Join-Path $tmpRoot 'session-learner-scenario.json'
    (Convert-StateToScenario -State $state | ConvertTo-Json -Depth 14) | Set-Content -LiteralPath $scenarioPath

    $decisionReport = (& .\scripts\teaching\select-next-action.ps1 -LearnerPath $scenarioPath -LearnerId $state.learnerId -Now $Now | Out-String) | ConvertFrom-Json
    $decision = @($decisionReport.decisions)[0]

    $sourceId = ($decision.objectiveId -split ':')[0]
    $source = @($scanReport.sources | Where-Object { $_.id -eq $sourceId } | Select-Object -First 1)
    $sourceObject = $null
    if ($source.Count -gt 0) {
        $sourceObjects = @($source[0].objects | Where-Object { $_.sourceId -eq $sourceId })
        $sourceObject = @(Select-SourceObjectsForObjective -SourceObjects $sourceObjects -ObjectiveId $decision.objectiveId | Select-Object -First 1)
        if ($sourceObject.Count -gt 0) {
            $sourceObject = $sourceObject[0]
        }
        else {
            $sourceObject = $null
        }
    }

    $assessment = Get-Content -LiteralPath '.\fixtures\assessment-items.json' -Raw | ConvertFrom-Json
    $assessmentItem = @($assessment.items | Where-Object { $_.objectiveId -eq $decision.objectiveId } | Select-Object -First 1)
    if ($assessmentItem.Count -gt 0) {
        $assessmentItem = $assessmentItem[0]
    }
    else {
        $assessmentItem = $null
    }

    $prompt = if ($assessmentItem) {
        $assessmentItem.prompt
    }
    else {
        'Study the next source item and summarize what you learned.'
    }

    if ([string]::IsNullOrWhiteSpace($Response) -and $assessmentItem) {
        if ($NonInteractive) {
            $answers = @($assessmentItem.acceptedAnswers)
            $Response = if ($answers.Count -gt 0) { $answers[0] } else { 'completed' }
        }
        else {
            $Response = Read-Host $prompt
        }
    }

    $assessmentResult = $null
    $updatedStatePath = $null
    if ($assessmentItem) {
        $assessmentOutput = (& .\scripts\assessment\evaluate-answer.ps1 -ItemId $assessmentItem.itemId -Answer $Response -HintsUsed $HintsUsed | Out-String)
        $assessmentResult = $assessmentOutput | ConvertFrom-Json
        $resultPath = Join-Path $tmpRoot 'assessment-result.json'
        $assessmentOutput | Set-Content -LiteralPath $resultPath

        if ([string]::IsNullOrWhiteSpace($OutputStatePath)) {
            $updatedStatePath = Join-Path (Split-Path -Parent $tmpRoot) 'learner-state.last-session.json'
        }
        else {
            $updatedStatePath = $OutputStatePath
        }
        [void](& .\scripts\state\update-learner-state.ps1 -StatePath $StatePath -AssessmentResultPath $resultPath -OutputPath $updatedStatePath -Now $Now)
    }

    [ordered]@{
        schemaVersion = 1
        sessionAt = $Now.ToUniversalTime().ToString('o')
        learnerId = $state.learnerId
        action = $decision
        prompt = $prompt
        hintOptions = if ($assessmentItem) { @($assessmentItem.scaffolds) } else { @() }
        learnerProfile = $state.profile
        mastery = @($state.mastery)
        reviewQueue = @($state.reviewQueue)
        responseAccepted = -not [string]::IsNullOrWhiteSpace($Response)
        assessmentItemId = if ($assessmentItem) { $assessmentItem.itemId } else { $null }
        feedback = if ($assessmentResult) { $assessmentResult.feedback } else { 'Read the source item and continue when ready.' }
        sourceProvenance = if ($sourceObject) {
            [ordered]@{
                sourceId = $sourceObject.sourceId
                sourceRepo = $sourceObject.sourceRepo
                sourcePath = $sourceObject.sourcePath
                title = $sourceObject.title
                license = $sourceObject.license
                attribution = $sourceObject.attribution
            }
        }
        else {
            $null
        }
        updatedStatePath = $updatedStatePath
    } | ConvertTo-Json -Depth 12
}
finally {
    if (-not $KeepArtifacts -and (Test-Path -LiteralPath $tmpRoot)) {
        Remove-Item -LiteralPath $tmpRoot -Recurse -Force
    }
}

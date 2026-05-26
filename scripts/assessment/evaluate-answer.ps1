[CmdletBinding()]
param(
    [string]$AssessmentPath = '.\fixtures\assessment-items.json',
    [string]$ItemId = 'debugging-mcq-001',
    [string]$Answer = 'step into',
    [int]$HintsUsed = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Normalize-Answer {
    param([string]$Value)
    return $Value.Trim().ToLowerInvariant()
}

$assessmentFile = (Resolve-Path -LiteralPath $AssessmentPath).Path
$assessment = Get-Content -LiteralPath $assessmentFile -Raw | ConvertFrom-Json
if ($assessment.schemaVersion -ne 1) {
    throw 'Assessment fixtures schemaVersion must be 1.'
}

$item = @($assessment.items | Where-Object { $_.itemId -eq $ItemId } | Select-Object -First 1)
if ($item.Count -eq 0) {
    throw "No assessment item found for '$ItemId'."
}
$item = $item[0]

$status = 'uncertain'
$score = 0.0

if ($item.type -in @('multiple-choice', 'short-answer', 'recall')) {
    $normalizedAnswer = Normalize-Answer -Value $Answer
    $accepted = @($item.acceptedAnswers | ForEach-Object { Normalize-Answer -Value $_ })
    if ($accepted -contains $normalizedAnswer) {
        $status = 'correct'
        $score = 1.0
    }
    elseif ($accepted | Where-Object { $normalizedAnswer.Contains($_) -or $_.Contains($normalizedAnswer) }) {
        $status = 'partial'
        $score = 0.5
    }
    else {
        $status = 'incorrect'
        $score = 0.0
    }
}
elseif ($item.type -eq 'project-checkpoint') {
    $status = 'uncertain'
    $score = 0.0
}
elseif ($item.type -eq 'interactive') {
    $status = 'uncertain'
    $score = 0.0
}

$hintPenalty = [Math]::Min($HintsUsed * 0.02, 0.08)
$confidenceDelta = [double]$item.masteryEvidence.confidenceDelta
if ($status -eq 'correct') {
    $confidenceDelta = [Math]::Max($confidenceDelta - $hintPenalty, 0)
}
elseif ($status -eq 'partial') {
    $confidenceDelta = [Math]::Max(($confidenceDelta / 2) - $hintPenalty, 0)
}
else {
    $confidenceDelta = 0
}

[ordered]@{
    schemaVersion = 1
    itemId = $item.itemId
    objectiveId = $item.objectiveId
    status = $status
    score = $score
    feedback = $item.feedbackTemplates.$status
    hintUsage = $HintsUsed
    masteryEvidence = [ordered]@{
        objectiveId = $item.objectiveId
        evidenceType = $item.masteryEvidence.evidenceType
        sourceItemId = $item.itemId
        status = $status
        score = $score
        hintUsage = $HintsUsed
        confidenceDelta = $confidenceDelta
    }
} | ConvertTo-Json -Depth 8

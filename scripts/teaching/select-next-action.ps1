[CmdletBinding()]
param(
    [string]$LearnerPath = '.\fixtures\learner-scenarios.json',
    [string]$LearnerId = '',
    [datetime]$Now = '2026-05-25T12:00:00Z'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ReviewDueAt {
    param(
        [AllowNull()][object]$LastEvidenceAt,
        [double]$Confidence
    )

    if ($null -eq $LastEvidenceAt) {
        return $null
    }

    $last = [datetime]$LastEvidenceAt
    if ($Confidence -lt 0.50) {
        return $last.AddDays(1)
    }
    if ($Confidence -lt 0.70) {
        return $last.AddDays(3)
    }
    if ($Confidence -lt 0.85) {
        return $last.AddDays(7)
    }

    return $last.AddDays(14)
}

function Select-ActionForLearner {
    param(
        [object]$Learner,
        [datetime]$DecisionTime
    )

    $unresolved = @($Learner.misconceptions | Where-Object { $_.status -eq 'unresolved' } | Select-Object -First 1)
    if ($unresolved.Count -gt 0) {
        return [ordered]@{
            learnerId = $Learner.learnerId
            actionType = 'remediation'
            objectiveId = $unresolved[0].objectiveId
            reason = 'unresolved-misconception'
            nextReviewAt = $null
            evidence = $unresolved[0].misconceptionId
        }
    }

    foreach ($mastery in @($Learner.objectiveMastery)) {
        $reviewDueAt = Get-ReviewDueAt -LastEvidenceAt $mastery.lastEvidenceAt -Confidence $mastery.confidence

        if ($mastery.evidenceCount -eq 0) {
            return [ordered]@{
                learnerId = $Learner.learnerId
                actionType = 'lesson'
                objectiveId = $mastery.objectiveId
                reason = 'no-mastery-evidence'
                nextReviewAt = $reviewDueAt
                evidence = 'none'
            }
        }

        if ($mastery.confidence -lt 0.60) {
            return [ordered]@{
                learnerId = $Learner.learnerId
                actionType = 'practice'
                objectiveId = $mastery.objectiveId
                reason = 'low-confidence'
                nextReviewAt = $reviewDueAt
                evidence = ('count:{0}' -f $mastery.evidenceCount)
            }
        }

        if ($reviewDueAt -and $reviewDueAt -le $DecisionTime) {
            return [ordered]@{
                learnerId = $Learner.learnerId
                actionType = 'review'
                objectiveId = $mastery.objectiveId
                reason = 'spaced-review-due'
                nextReviewAt = $reviewDueAt.ToString('o')
                evidence = ('last:{0}' -f $mastery.lastEvidenceAt)
            }
        }

        if ($mastery.confidence -ge 0.85) {
            return [ordered]@{
                learnerId = $Learner.learnerId
                actionType = 'project'
                objectiveId = $mastery.objectiveId
                reason = 'ready-to-advance'
                nextReviewAt = $reviewDueAt.ToString('o')
                evidence = ('confidence:{0}' -f $mastery.confidence)
            }
        }

        return [ordered]@{
            learnerId = $Learner.learnerId
            actionType = 'quiz'
            objectiveId = $mastery.objectiveId
            reason = 'needs-mastery-check'
            nextReviewAt = $reviewDueAt.ToString('o')
            evidence = ('confidence:{0}' -f $mastery.confidence)
        }
    }

    return [ordered]@{
        learnerId = $Learner.learnerId
        actionType = 'lesson'
        objectiveId = $Learner.profile.goals[0]
        reason = 'no-objectives-found'
        nextReviewAt = $null
        evidence = 'none'
    }
}

$fixturePath = (Resolve-Path -LiteralPath $LearnerPath).Path
$fixtures = Get-Content -LiteralPath $fixturePath -Raw | ConvertFrom-Json
if ($fixtures.schemaVersion -ne 1) {
    throw 'Learner fixtures schemaVersion must be 1.'
}

$learners = @($fixtures.learners)
if (-not [string]::IsNullOrWhiteSpace($LearnerId)) {
    $learners = @($learners | Where-Object { $_.learnerId -eq $LearnerId })
    if ($learners.Count -eq 0) {
        throw "No learner fixture found for '$LearnerId'."
    }
}

$decisions = foreach ($learner in $learners) {
    Select-ActionForLearner -Learner $learner -DecisionTime $Now
}

[ordered]@{
    schemaVersion = 1
    decidedAt = $Now.ToString('o')
    decisionCount = @($decisions).Count
    decisions = @($decisions)
} | ConvertTo-Json -Depth 8

[CmdletBinding()]
param(
    [string]$StatePath = '.\fixtures\learner-state.gdev-101.json',
    [string]$LecturePath = '.\fixtures\lecture-video.gdev-101-design-vocabulary.json',
    [string]$RulesPath = '.\fixtures\lecture-selection-rules.json',
    [switch]$SelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Copy-JsonObject {
    param([object]$Value)
    return (($Value | ConvertTo-Json -Depth 20) | ConvertFrom-Json)
}

function Set-ArrayProperty {
    param(
        [object]$Object,
        [string]$Name,
        [object[]]$Value
    )
    $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value -Force
}

function Get-ObjectiveMastery {
    param(
        [object]$State,
        [string]$ObjectiveId
    )

    $match = @($State.mastery | Where-Object { $_.objectiveId -eq $ObjectiveId } | Select-Object -First 1)
    if ($match.Count -eq 1) {
        return $match[0]
    }

    return [pscustomobject]@{
        objectiveId = $ObjectiveId
        confidence = 0.0
        evidenceCount = 0
        evidenceSources = @()
    }
}

function Select-LectureChapter {
    param(
        [object]$Lecture,
        [string]$Kind
    )

    $chapters = @($Lecture.chapters)
    if ($Kind -eq 'misconception') {
        $match = @($chapters | Where-Object { $_.title -match '(?i)misconception|check' } | Select-Object -First 1)
        if ($match.Count -eq 1) { return $match[0] }
    }
    if ($Kind -eq 'handoff') {
        $match = @($chapters | Where-Object { $_.title -match '(?i)practice|handoff' } | Select-Object -First 1)
        if ($match.Count -eq 1) { return $match[0] }
    }
    if ($chapters.Count -gt 1) { return $chapters[1] }
    if ($chapters.Count -eq 1) { return $chapters[0] }
    return $null
}

function New-Recommendation {
    param(
        [string]$Mode,
        [string]$Reason,
        [object]$State,
        [object]$Lecture,
        [object]$Chapter = $null
    )

    $objectiveId = @($Lecture.objectiveIds)[0]
    return [ordered]@{
        mode = $Mode
        reason = $Reason
        objectiveId = $objectiveId
        packageId = $Lecture.packageId
        masteryImpact = 'selection-only'
        segment = if ($Chapter) {
            [ordered]@{
                title = $Chapter.title
                startSecond = $Chapter.startSecond
            }
        }
        else {
            $null
        }
        evidenceUsed = [ordered]@{
            learnerId = $State.learnerId
            confidence = (Get-ObjectiveMastery -State $State -ObjectiveId $objectiveId).confidence
            evidenceCount = (Get-ObjectiveMastery -State $State -ObjectiveId $objectiveId).evidenceCount
        }
    }
}

function Select-LectureMode {
    param(
        [object]$State,
        [object]$Lecture,
        [object]$Rules
    )

    $objectiveId = @($Lecture.objectiveIds)[0]
    $mastery = Get-ObjectiveMastery -State $State -ObjectiveId $objectiveId
    $misconceptions = @($State.misconceptions | Where-Object { $_.objectiveId -eq $objectiveId -and $_.status -eq 'unresolved' })
    $failedCheckpoint = @($State.learningEvents | Where-Object {
        $_.verb -eq 'lecture_checkpoint_submitted' -and
        $_.objectId -eq $objectiveId -and
        $_.result.success -eq $false
    })
    $accommodations = @($State.profile.accommodations)
    $preferences = $State.profile.preferences

    if ($misconceptions.Count -gt 0 -or $failedCheckpoint.Count -gt 0) {
        return New-Recommendation -Mode 'remediation-clip' -Reason 'unresolved-misconception-or-failed-checkpoint' -State $State -Lecture $Lecture -Chapter (Select-LectureChapter -Lecture $Lecture -Kind 'misconception')
    }

    if ([int]$mastery.evidenceCount -eq 0 -or [double]$mastery.confidence -lt 0.20) {
        return New-Recommendation -Mode 'full-lecture' -Reason 'no-mastery-evidence' -State $State -Lecture $Lecture
    }

    if ($accommodations -contains 'low-distraction-output' -or $preferences.explanationStyle -eq 'transcript-first') {
        return New-Recommendation -Mode 'transcript' -Reason 'text-first-review-preferred' -State $State -Lecture $Lecture
    }

    return New-Recommendation -Mode 'short-segment' -Reason 'focused-review' -State $State -Lecture $Lecture -Chapter (Select-LectureChapter -Lecture $Lecture -Kind 'handoff')
}

if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) {
    throw "Missing learner state: $StatePath"
}
if (-not (Test-Path -LiteralPath $LecturePath -PathType Leaf)) {
    throw "Missing lecture package: $LecturePath"
}
if (-not (Test-Path -LiteralPath $RulesPath -PathType Leaf)) {
    throw "Missing lecture selection rules: $RulesPath"
}

$state = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
$lecture = Get-Content -LiteralPath $LecturePath -Raw | ConvertFrom-Json
$rules = Get-Content -LiteralPath $RulesPath -Raw | ConvertFrom-Json

if ($rules.schemaVersion -ne 1) {
    throw 'Lecture selection rules schemaVersion must be 1.'
}

$recommendation = Select-LectureMode -State $state -Lecture $lecture -Rules $rules
$selfTestResults = @()
if ($SelfTest) {
    $objectiveId = @($lecture.objectiveIds)[0]
    $cases = @(
        @{ name = 'full-lecture'; expected = 'full-lecture'; mutate = { param($s) } },
        @{ name = 'transcript'; expected = 'transcript'; mutate = { param($s) $s.mastery[0].confidence = 0.45; $s.mastery[0].evidenceCount = 2 } },
        @{ name = 'short-segment'; expected = 'short-segment'; mutate = { param($s) $s.mastery[0].confidence = 0.45; $s.mastery[0].evidenceCount = 2; $s.profile.accommodations = @() } },
        @{ name = 'remediation-clip'; expected = 'remediation-clip'; mutate = { param($s) $s.misconceptions = @([pscustomobject]@{ misconceptionId = 'mis-gdev-101-vgf'; objectiveId = $objectiveId; status = 'unresolved' }) } }
    )

    foreach ($case in $cases) {
        $copy = Copy-JsonObject -Value $state
        & $case.mutate $copy
        $caseRecommendation = Select-LectureMode -State $copy -Lecture $lecture -Rules $rules
        $selfTestResults += [ordered]@{
            name = $case.name
            expected = $case.expected
            actual = $caseRecommendation.mode
            passed = ($caseRecommendation.mode -eq $case.expected)
        }
    }
}

$failedCases = @($selfTestResults | Where-Object { $_.passed -ne $true })
[ordered]@{
    schemaVersion = 1
    recommendation = $recommendation
    selfTestResults = @($selfTestResults)
    passedCaseCount = @($selfTestResults | Where-Object { $_.passed -eq $true }).Count
    errorCount = $failedCases.Count
    errors = @($failedCases | ForEach-Object { "Self-test failed for $($_.name): expected $($_.expected), actual $($_.actual)" })
} | ConvertTo-Json -Depth 10

if ($failedCases.Count -gt 0) {
    exit 1
}

exit 0

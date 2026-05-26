[CmdletBinding()]
param(
    [string]$WorkingRoot = '',
    [switch]$KeepArtifacts
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($WorkingRoot)) {
    $repo = (& git -C . rev-parse --show-toplevel).Trim()
    $WorkingRoot = Join-Path (Join-Path $repo '.codex-cache') 'tmp'
}

$runRoot = Join-Path $WorkingRoot ('gdev-course-session-{0}' -f [Guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Force -Path $runRoot)

$exitCode = 1
try {
    $statePath = Join-Path $runRoot 'gdev-101-learner-state.json'
    $objectiveId = 'game-development:objectives/course/gdev-101/design-vocabulary'
    $expectedTitle = 'GDEV-101 Game Design Foundations'
    $expectedPath = 'study-plans\courses\GDEV-101-game-design-foundations.md'

    [ordered]@{
        schemaVersion = 1
        learnerId = 'gdev-101-test-learner'
        profile = [ordered]@{
            learnerId = 'gdev-101-test-learner'
            goals = @($objectiveId)
            constraints = @('short-evening-sessions')
            preferences = [ordered]@{
                explanationStyle = 'worked-example'
                practiceMode = 'scaffolded'
            }
            accommodations = @('low-distraction-output')
            priorExperience = @('played-games-but-new-to-design')
        }
        mastery = @(
            [ordered]@{
                objectiveId = $objectiveId
                confidence = 0.0
                lastEvidenceAt = $null
                evidenceCount = 0
                evidenceSources = @()
            }
        )
        misconceptions = @()
        reviewQueue = @()
        learningEvents = @()
        auditLog = @()
        privacy = [ordered]@{
            piiPolicy = 'fixtures-use-non-identifying-ids'
            redactionFields = @('profile.accommodations', 'profile.constraints')
            localOnly = $true
        }
        sync = [ordered]@{
            mode = 'local'
            lastSyncedAt = $null
            conflictPolicy = 'append-events-and-recompute-mastery'
        }
    } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $statePath

    $session = (& .\scripts\teaching\start-session.ps1 -StatePath $statePath -NonInteractive | Out-String) | ConvertFrom-Json
    $prompt = (& .\scripts\ai\build-teaching-prompt.ps1 -StatePath $statePath -Mode socratic | Out-String) | ConvertFrom-Json
    $errors = [System.Collections.Generic.List[string]]::new()

    if ($session.action.objectiveId -ne $objectiveId) {
        $errors.Add("Expected session objective '$objectiveId' but got '$($session.action.objectiveId)'.")
    }
    if ($session.action.actionType -ne 'lesson') {
        $errors.Add("Expected lesson action but got '$($session.action.actionType)'.")
    }
    if ($session.action.reason -ne 'no-mastery-evidence') {
        $errors.Add("Expected no-mastery-evidence reason but got '$($session.action.reason)'.")
    }
    if (-not $session.sourceProvenance) {
        $errors.Add('Expected session source provenance.')
    }
    elseif ($session.sourceProvenance.title -ne $expectedTitle -or $session.sourceProvenance.sourcePath -ne $expectedPath) {
        $errors.Add("Expected session source '$expectedTitle' at '$expectedPath' but got '$($session.sourceProvenance.title)' at '$($session.sourceProvenance.sourcePath)'.")
    }

    $firstPromptSource = @($prompt.sourceSnippets | Select-Object -First 1)
    if ($firstPromptSource.Count -eq 0) {
        $errors.Add('Expected AI teacher prompt to include source snippets.')
    }
    elseif ($firstPromptSource[0].title -ne $expectedTitle -or $firstPromptSource[0].sourcePath -ne $expectedPath) {
        $errors.Add("Expected first AI prompt source '$expectedTitle' at '$expectedPath' but got '$($firstPromptSource[0].title)' at '$($firstPromptSource[0].sourcePath)'.")
    }

    if ($prompt.objectiveId -ne $objectiveId) {
        $errors.Add("Expected prompt objective '$objectiveId' but got '$($prompt.objectiveId)'.")
    }
    if ($prompt.nextAction.actionType -ne 'lesson') {
        $errors.Add("Expected prompt next action lesson but got '$($prompt.nextAction.actionType)'.")
    }
    if ($prompt.learnerStateSummary.preferences.explanationStyle -ne 'worked-example') {
        $errors.Add('Expected prompt to preserve learner explanation preference.')
    }
    if (@($prompt.learnerStateSummary.accommodations) -notcontains 'low-distraction-output') {
        $errors.Add('Expected prompt to preserve learner accommodation.')
    }

    [ordered]@{
        schemaVersion = 1
        checkedAt = (Get-Date).ToString('o')
        errorCount = $errors.Count
        errors = @($errors)
        expectedCourse = [ordered]@{
            title = $expectedTitle
            sourcePath = $expectedPath
            objectiveId = $objectiveId
        }
        session = $session
        promptSourceSnippets = @($prompt.sourceSnippets)
        adaptationEvidence = [ordered]@{
            actionType = $prompt.nextAction.actionType
            actionReason = $prompt.nextAction.reason
            explanationStyle = $prompt.learnerStateSummary.preferences.explanationStyle
            accommodations = @($prompt.learnerStateSummary.accommodations)
        }
    } | ConvertTo-Json -Depth 14

    $exitCode = if ($errors.Count -gt 0) { 1 } else { 0 }
}
finally {
    if (-not $KeepArtifacts -and (Test-Path -LiteralPath $runRoot)) {
        Remove-Item -LiteralPath $runRoot -Recurse -Force
    }
}

exit $exitCode

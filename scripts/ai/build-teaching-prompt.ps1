[CmdletBinding()]
param(
    [string]$StatePath = '.\fixtures\learner-state.valid.json',
    [ValidateSet('socratic', 'direct', 'worked-example')]
    [string]$Mode = 'socratic',
    [datetime]$Now = '2026-05-25T12:00:00Z'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-TempScenario {
    param([object]$State)
    $repo = (& git -C . rev-parse --show-toplevel).Trim()
    $tmpRoot = Join-Path (Join-Path (Join-Path $repo '.codex-cache') 'tmp') ('ai-prompt-{0}' -f [Guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Force -Path $tmpRoot)
    $path = Join-Path $tmpRoot 'scenario.json'
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
    } | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $path
    return [pscustomobject]@{ Root = $tmpRoot; Path = $path }
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

function Get-SourceExcerpt {
    param(
        [string]$SourceRoot,
        [string]$SourcePath,
        [int]$MaxChars = 6000
    )

    if ([string]::IsNullOrWhiteSpace($SourceRoot) -or [string]::IsNullOrWhiteSpace($SourcePath)) {
        return ''
    }

    $fullPath = Join-Path $SourceRoot $SourcePath
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        return ''
    }

    $text = Get-Content -LiteralPath $fullPath -Raw
    if ($text.Length -le $MaxChars) {
        return $text
    }

    return $text.Substring(0, $MaxChars)
}

$temp = $null
try {
    $state = (& .\scripts\state\read-learner-state.ps1 -Path $StatePath | Out-String) | ConvertFrom-Json
    $temp = New-TempScenario -State $state
    $decisionReport = (& .\scripts\teaching\select-next-action.ps1 -LearnerPath $temp.Path -LearnerId $state.learnerId -Now $Now | Out-String) | ConvertFrom-Json
    $decision = @($decisionReport.decisions)[0]
    $scanReport = (& .\scripts\ingestion\scan-content-sources.ps1 | Out-String) | ConvertFrom-Json
    $sourceId = ($decision.objectiveId -split ':')[0]
    $sourceEntry = @($scanReport.sources | Where-Object { $_.id -eq $sourceId } | Select-Object -First 1)
    $sourceRoot = ''
    $candidateSourceObjects = @()
    if ($sourceEntry.Count -gt 0) {
        $sourceRoot = $sourceEntry[0].resolvedPath
        $candidateSourceObjects = @($sourceEntry[0].objects)
    }
    $sourceObjects = @(Select-SourceObjectsForObjective -SourceObjects $candidateSourceObjects -ObjectiveId $decision.objectiveId | Select-Object -First 3)

    [ordered]@{
        schemaVersion = 1
        role = 'Expert adaptive teacher'
        mode = $Mode
        objectiveId = $decision.objectiveId
        learnerStateSummary = [ordered]@{
            learnerId = $state.learnerId
            goals = @($state.profile.goals)
            constraints = @($state.profile.constraints)
            preferences = $state.profile.preferences
            accommodations = @($state.profile.accommodations)
            mastery = @($state.mastery | ForEach-Object {
                [ordered]@{
                    objectiveId = $_.objectiveId
                    confidence = $_.confidence
                    evidenceCount = $_.evidenceCount
                    lastEvidenceAt = $_.lastEvidenceAt
                }
            })
            unresolvedMisconceptions = @($state.misconceptions | Where-Object { $_.status -eq 'unresolved' })
        }
        nextAction = $decision
        sourceSnippets = @($sourceObjects | ForEach-Object {
            [ordered]@{
                sourceId = $_.sourceId
                sourceRepo = $_.sourceRepo
                sourcePath = $_.sourcePath
                title = $_.title
                excerpt = Get-SourceExcerpt -SourceRoot $sourceRoot -SourcePath $_.sourcePath
                citationRequired = $true
            }
        })
        constraints = @(
            'Use only provided source snippets for content claims.',
            'Separate observed evidence from diagnosis.',
            'Ask a calibrated question before revealing the answer in Socratic mode.',
            'Do not directly mutate learner state.'
        )
        desiredOutputShape = [ordered]@{
            response = 'learner-facing text'
            citations = 'array of sourceId/sourcePath citations'
            observedEvidence = 'array'
            diagnosis = 'object with confidence and rationale'
            nextStep = 'question, practice, review, or project'
            stateUpdateProposal = 'proposal only'
            selfCheck = 'grounded/objectiveAligned/accessible/tone/unsupportedClaims/directStateMutation'
        }
        guardrails = @(
            'If source content is missing, ask for clarification or use a source lookup.',
            'No unsupported claims.',
            'No false praise.',
            'Maintain rigor while preserving learner agency.'
        )
        tools = @('content.lookup', 'learner_state.read', 'next_action.read', 'assessment.read', 'state_update.propose')
    } | ConvertTo-Json -Depth 14
}
finally {
    if ($temp -and (Test-Path -LiteralPath $temp.Root)) {
        Remove-Item -LiteralPath $temp.Root -Recurse -Force
    }
}

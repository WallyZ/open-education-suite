[CmdletBinding()]
param(
    [string]$StatePath = '.\fixtures\learner-state.valid.json',
    [string]$SubjectBrainResultsPath = '',
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

function Read-SubjectBrainContext {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }
    $resolved = Resolve-Path -LiteralPath $Path
    $payload = Get-Content -LiteralPath $resolved.Path -Raw | ConvertFrom-Json
    if ($payload.schemaVersion -ne 'open-education/subject-brain-query-result/v1') {
        throw 'Subject-brain query result uses an unsupported schemaVersion.'
    }
    if ($payload.retrievalOnly -ne $true -or -not [string]::IsNullOrWhiteSpace([string]$payload.generatedAnswer)) {
        throw 'Subject-brain context must be retrieval-only and must not contain a generated answer.'
    }

    $results = @($payload.results | Select-Object -First 8 | ForEach-Object {
        foreach ($field in @('sourceId', 'sourceRepo', 'sourcePath', 'title', 'locator', 'excerpt', 'licenseId', 'sha256')) {
            if ([string]::IsNullOrWhiteSpace([string]$_.$field)) {
                throw "Subject-brain result is missing $field."
            }
        }
        if ($_.citationRequired -ne $true) {
            throw 'Subject-brain results must require citations.'
        }
        if ([System.IO.Path]::IsPathRooted([string]$_.sourcePath) -or [string]$_.sourcePath -match '^[A-Za-z]:') {
            throw 'Subject-brain sourcePath must remain repo-relative.'
        }
        [ordered]@{
            sourceId = $_.sourceId
            sourceRepo = $_.sourceRepo
            sourcePath = $_.sourcePath
            title = $_.title
            locator = $_.locator
            excerpt = $_.excerpt
            canonicalUrl = $_.canonicalUrl
            licenseId = $_.licenseId
            sha256 = $_.sha256
            citationRequired = $true
        }
    })

    return [ordered]@{
        brainId = $payload.brainId
        query = $payload.query
        gradeBand = $payload.gradeBand
        retrievalOnly = $true
        results = $results
        teacherPolicy = $payload.teacherPolicy
    }
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
    $subjectBrainContext = Read-SubjectBrainContext -Path $SubjectBrainResultsPath

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
        subjectBrainContext = $subjectBrainContext
        constraints = @(
            'Use only provided source snippets and subject-brain excerpts for content claims.',
            'Treat subject-brain evidence as supplemental to the scheduled objective and reviewed lesson content.',
            'Cite the exact source repo, source path, and locator for each subject-brain excerpt used.',
            'Disclose conflicting sources and state when the retrieved evidence is insufficient.',
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
        tools = @('content.lookup', 'subject_brain.query', 'learner_state.read', 'next_action.read', 'assessment.read', 'state_update.propose')
    } | ConvertTo-Json -Depth 14
}
finally {
    if ($temp -and (Test-Path -LiteralPath $temp.Root)) {
        Remove-Item -LiteralPath $temp.Root -Recurse -Force
    }
}

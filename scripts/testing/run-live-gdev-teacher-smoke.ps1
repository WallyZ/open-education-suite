[CmdletBinding()]
param(
    [string]$Model = '',
    [string]$WorkingRoot = '',
    [string]$LogPath = '',
    [switch]$KeepArtifacts
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-RepoRoot {
    $repo = (& git -C . rev-parse --show-toplevel).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repo)) {
        throw 'Unable to resolve repository root with git.'
    }
    return $repo
}

if ([string]::IsNullOrWhiteSpace($env:OPENAI_API_KEY)) {
    throw 'OPENAI_API_KEY is required for the live GDEV teacher smoke test.'
}

$repoRoot = Resolve-RepoRoot
$runId = ('live-gdev-teacher-smoke_{0:yyyyMMdd_HHmmss}_{1}' -f (Get-Date), [Guid]::NewGuid().ToString('N').Substring(0, 8))
if ([string]::IsNullOrWhiteSpace($WorkingRoot)) {
    $WorkingRoot = Join-Path (Join-Path $repoRoot '.codex-cache') 'tmp'
}
if ([string]::IsNullOrWhiteSpace($LogPath)) {
    $LogPath = Join-Path (Join-Path (Join-Path $repoRoot '.codex-cache') 'logs') "$runId.json"
}

$runRoot = Join-Path $WorkingRoot $runId
[void](New-Item -ItemType Directory -Force -Path $runRoot)
[void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogPath))

$statePath = Join-Path $runRoot 'gdev-101-live-learner-state.json'
$promptPath = Join-Path $runRoot 'gdev-101-live-prompt.json'
$outputPath = Join-Path $runRoot 'gdev-101-live-output.json'
$objectiveId = 'game-development:objectives/course/gdev-101/design-vocabulary'
$expectedPath = 'study-plans\courses\GDEV-101-game-design-foundations.md'
$errors = [System.Collections.Generic.List[string]]::new()
$exitCode = 1

try {
    [ordered]@{
        schemaVersion = 1
        learnerId = 'gdev-101-live-smoke-learner'
        profile = [ordered]@{
            learnerId = 'gdev-101-live-smoke-learner'
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

    $invokeArgs = @{
        StatePath = $statePath
        Mode = 'socratic'
        OutputPath = $outputPath
        PromptPath = $promptPath
    }
    if (-not [string]::IsNullOrWhiteSpace($Model)) {
        $invokeArgs.Model = $Model
    }

    $invokeResult = (& .\scripts\ai\invoke-openai-teacher.ps1 @invokeArgs | Out-String) | ConvertFrom-Json
    $evaluation = (& .\scripts\ai\evaluate-model-output.ps1 -OutputPath $outputPath | Out-String) | ConvertFrom-Json
    if ($evaluation.errorCount -ne 0) {
        foreach ($errorMessage in @($evaluation.errors)) {
            $errors.Add("Model output validation: $errorMessage")
        }
    }

    $prompt = Get-Content -LiteralPath $promptPath -Raw | ConvertFrom-Json
    $output = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json

    if ($output.objectiveId -ne $objectiveId) {
        $errors.Add("Expected output objective '$objectiveId' but got '$($output.objectiveId)'.")
    }
    if (@($output.citations | Where-Object { $_.sourceId -eq 'game-development' -and $_.sourcePath -eq $expectedPath }).Count -lt 1) {
        $errors.Add("Expected a game-development citation for '$expectedPath'.")
    }
    if ($output.stateUpdateProposal.type -ne 'none' -and $output.stateUpdateProposal.type -ne 'proposal') {
        $errors.Add("Expected state update proposal type none or proposal but got '$($output.stateUpdateProposal.type)'.")
    }

    $observedEvidenceText = (@($output.observedEvidence) -join ' ')
    if ($observedEvidenceText -notmatch 'worked' -or $observedEvidenceText -notmatch 'low-distraction') {
        $errors.Add('Expected observedEvidence to reflect worked-example preference and low-distraction accommodation.')
    }
    if (@($prompt.sourceSnippets | Where-Object { $_.sourcePath -eq $expectedPath -and -not [string]::IsNullOrWhiteSpace($_.excerpt) }).Count -lt 1) {
        $errors.Add('Expected prompt to include a non-empty GDEV-101 source excerpt.')
    }

    $summary = [ordered]@{
        schemaVersion = 1
        checkedAt = (Get-Date).ToString('o')
        runId = $runId
        errorCount = $errors.Count
        errors = @($errors)
        invokeResult = $invokeResult
        evaluation = $evaluation
        expectedObjectiveId = $objectiveId
        expectedCitationPath = $expectedPath
        promptSourceSnippets = @($prompt.sourceSnippets | ForEach-Object {
            [ordered]@{
                title = $_.title
                sourcePath = $_.sourcePath
                hasExcerpt = -not [string]::IsNullOrWhiteSpace($_.excerpt)
            }
        })
        modelOutput = $output
    }
    $summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $LogPath
    $summary | ConvertTo-Json -Depth 20

    $exitCode = if ($errors.Count -gt 0) { 1 } else { 0 }
}
finally {
    if (-not $KeepArtifacts -and (Test-Path -LiteralPath $runRoot)) {
        Remove-Item -LiteralPath $runRoot -Recurse -Force
    }
}

exit $exitCode

[CmdletBinding()]
param(
    [string]$OutputPath = '.\ui\learner\session-data.js',
    [string]$StatePath = '',
    [string]$LecturePackagePath = '..\open-education-game-development\generated-lectures\gdev-101-design-vocabulary\publish\lecture-video.publish-ready.json',
    [datetime]$Now = '2026-05-25T12:00:00Z',
    [switch]$KeepArtifacts
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. .\scripts\teaching\lecture-paths.ps1

function New-UiSessionTempRoot {
    $repo = (& git -C . rev-parse --show-toplevel).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repo)) {
        throw 'Unable to resolve repository root with git.'
    }

    $runId = ('learner-ui-session_{0:yyyyMMdd_HHmmss}_{1}' -f (Get-Date), [Guid]::NewGuid().ToString('N').Substring(0, 8))
    $tmpRoot = Join-Path (Join-Path (Join-Path $repo '.codex-cache') 'tmp') $runId
    [void](New-Item -ItemType Directory -Force -Path $tmpRoot)
    return $tmpRoot
}

function New-GdevLearnerState {
    param([string]$Path)

    $objectiveId = 'game-development:objectives/course/gdev-101/design-vocabulary'
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
    } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path
}

function Invoke-ContentCatalogAdapter {
    param([string]$RepoRoot)

    $adapterPath = Join-Path $RepoRoot 'scripts\teaching\content_catalog_adapter.py'
    if (-not (Test-Path -LiteralPath $adapterPath -PathType Leaf)) {
        throw "Learner content catalog adapter not found: $adapterPath"
    }

    $python = Get-Command py -ErrorAction SilentlyContinue
    if ($python) {
        $catalogJson = (& $python.Source -3 -B $adapterPath --repo-root $RepoRoot | Out-String)
    }
    else {
        $python = Get-Command python -ErrorAction SilentlyContinue
        if (-not $python) {
            throw 'Python is required to build the learner content catalog.'
        }
        $catalogJson = (& $python.Source -B $adapterPath --repo-root $RepoRoot | Out-String)
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Learner content catalog adapter failed with exit code $LASTEXITCODE."
    }

    return ($catalogJson | ConvertFrom-Json)
}

$repo = (& git -C . rev-parse --show-toplevel).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repo)) {
    throw 'Unable to resolve repository root with git.'
}

$tmpRoot = New-UiSessionTempRoot
$createdState = $false
try {
    if ([string]::IsNullOrWhiteSpace($StatePath)) {
        $StatePath = Join-Path $tmpRoot 'gdev-101-learner-state.json'
        New-GdevLearnerState -Path $StatePath
        $createdState = $true
    }

    $resolvedOutputPath = if ([System.IO.Path]::IsPathRooted($OutputPath)) {
        $OutputPath
    }
    else {
        Join-Path $repo $OutputPath
    }
    $resolvedLecturePath = if ([System.IO.Path]::IsPathRooted($LecturePackagePath)) {
        $LecturePackagePath
    }
    else {
        Join-Path $repo $LecturePackagePath
    }

    $session = (& .\scripts\teaching\start-session.ps1 -StatePath $StatePath -NonInteractive -Now $Now | Out-String) | ConvertFrom-Json
    $lecturePackage = Get-Content -LiteralPath $resolvedLecturePath -Raw | ConvertFrom-Json
    $lectureContentRoot = Get-LectureContentRoot -ManifestPath $resolvedLecturePath
    $lectureContentRootUri = [System.Uri](([System.IO.Path]::GetFullPath($lectureContentRoot)).TrimEnd('\') + '\')
    $lecturePackage | Add-Member -MemberType NoteProperty -Name contentRepoRoot -Value $lectureContentRoot -Force
    $lecturePackage | Add-Member -MemberType NoteProperty -Name contentRepoWebRoot -Value $lectureContentRootUri.AbsoluteUri -Force
    $lecturePackage | Add-Member -MemberType NoteProperty -Name contentRepoHttpRoot -Value '/content-repos/open-education-game-development/' -Force
    $lecturePackage | Add-Member -MemberType NoteProperty -Name sourcePackagePath -Value (ConvertTo-LectureContentRelativePath -ContentRoot $lectureContentRoot -Path $resolvedLecturePath) -Force
    $contentCatalog = Invoke-ContentCatalogAdapter -RepoRoot $repo

    $payload = @(
        '// Generated by scripts/teaching/export-learner-ui-session.ps1.'
        '// Do not edit by hand; update the source scripts or fixtures, then regenerate.'
        'window.openEducationSessionOutput = '
        ($session | ConvertTo-Json -Depth 20)
        ';'
        'window.openEducationLecturePackage = '
        ($lecturePackage | ConvertTo-Json -Depth 20)
        ';'
        'window.openEducationContentCatalog = '
        ($contentCatalog | ConvertTo-Json -Depth 20)
        ';'
        ''
    ) -join "`n"

    $outputDirectory = Split-Path -Parent $resolvedOutputPath
    if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) {
        [void](New-Item -ItemType Directory -Force -Path $outputDirectory)
    }
    Set-Content -LiteralPath $resolvedOutputPath -Value $payload

    [ordered]@{
        schemaVersion = 1
        outputPath = $resolvedOutputPath
        sessionLearnerId = $session.learnerId
        objectiveId = $session.action.objectiveId
        sourcePath = if ($session.sourceProvenance) { $session.sourceProvenance.sourcePath } else { $null }
        lecturePackageId = $lecturePackage.packageId
        createdTemporaryState = $createdState
    } | ConvertTo-Json -Depth 8
}
finally {
    if (-not $KeepArtifacts -and (Test-Path -LiteralPath $tmpRoot)) {
        Remove-Item -LiteralPath $tmpRoot -Recurse -Force
    }
}

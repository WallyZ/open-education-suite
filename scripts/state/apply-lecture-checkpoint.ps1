[CmdletBinding()]
param(
    [string]$StatePath = '.\fixtures\learner-state.gdev-101.json',
    [string]$CheckpointEvidencePath = '.\fixtures\lecture-checkpoint-evidence.gdev-101.json',
    [string]$OutputPath = '',
    [datetime]$Now = '2026-05-25T12:00:00Z'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-HasText {
    param(
        [object]$Value,
        [string]$Message
    )
    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        throw $Message
    }
}

function Set-ArrayProperty {
    param(
        [object]$Object,
        [string]$Name,
        [object[]]$Value
    )
    $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value -Force
}

function Get-SafeIdPart {
    param([string]$Value)
    return (($Value -replace '[^A-Za-z0-9]+', '-').Trim('-').ToLowerInvariant())
}

$state = (& .\scripts\state\read-learner-state.ps1 -Path $StatePath | Out-String) | ConvertFrom-Json
$evidence = Get-Content -LiteralPath (Resolve-Path -LiteralPath $CheckpointEvidencePath).Path -Raw | ConvertFrom-Json

if ($evidence.schemaVersion -ne 1) {
    throw 'Lecture checkpoint evidence schemaVersion must be 1.'
}
if ($evidence.learnerId -ne $state.learnerId) {
    throw 'Lecture checkpoint evidence learnerId must match learner state learnerId.'
}
foreach ($field in @('packageId', 'objectiveId', 'checkpointId', 'prompt', 'response', 'evidenceType', 'masteryImpact')) {
    Assert-HasText -Value $evidence.$field -Message "Lecture checkpoint evidence missing $field."
}
if ($evidence.evidenceType -ne 'lecture-checkpoint') {
    throw 'Lecture checkpoint evidenceType must be lecture-checkpoint.'
}
if ($evidence.masteryImpact -ne 'proposal-only') {
    throw 'Lecture checkpoint masteryImpact must be proposal-only.'
}

$occurredAt = if ([string]::IsNullOrWhiteSpace([string]$evidence.submittedAt)) {
    $Now.ToUniversalTime()
}
else {
    ([datetime]$evidence.submittedAt).ToUniversalTime()
}

$masteryRecords = @($state.mastery)
$mastery = @($masteryRecords | Where-Object { $_.objectiveId -eq $evidence.objectiveId } | Select-Object -First 1)
if ($mastery.Count -eq 0) {
    $mastery = [pscustomobject]@{
        objectiveId = $evidence.objectiveId
        confidence = 0.0
        lastEvidenceAt = $null
        evidenceCount = 0
        evidenceSources = @()
    }
    $masteryRecords += $mastery
}
else {
    $mastery = $mastery[0]
}
$oldConfidence = [double]$mastery.confidence
Set-ArrayProperty -Object $state -Name 'mastery' -Value $masteryRecords

$eventId = ('evt-{0}-{1}' -f $occurredAt.ToString('yyyyMMddHHmmss'), (Get-SafeIdPart -Value $evidence.checkpointId))
$event = [pscustomobject]@{
    eventId = $eventId
    learnerId = $state.learnerId
    verb = 'lecture_checkpoint_submitted'
    objectId = $evidence.objectiveId
    occurredAt = $occurredAt.ToString('o')
    result = [pscustomobject]@{
        success = $null
        score = $null
        evidenceType = $evidence.evidenceType
        masteryImpact = $evidence.masteryImpact
        responseLength = ([string]$evidence.response).Length
    }
    xapiCandidate = [pscustomobject]@{
        actor = $state.learnerId
        verb = 'answered'
        object = $evidence.checkpointId
        result = [pscustomobject]@{
            response = 'stored-locally'
            masteryImpact = $evidence.masteryImpact
        }
        context = [pscustomobject]@{
            packageId = $evidence.packageId
            objectiveId = $evidence.objectiveId
        }
    }
}
Set-ArrayProperty -Object $state -Name 'learningEvents' -Value (@($state.learningEvents) + $event)

$auditEntry = [pscustomobject]@{
    at = $occurredAt.ToString('o')
    objectiveId = $evidence.objectiveId
    oldConfidence = $oldConfidence
    newConfidence = $oldConfidence
    evidenceSource = 'lecture-checkpoint'
    reason = ('lecture-checkpoint:{0}:{1}:proposal-only' -f $evidence.packageId, $evidence.checkpointId)
}
Set-ArrayProperty -Object $state -Name 'auditLog' -Value (@($state.auditLog) + $auditEntry)

$json = $state | ConvertTo-Json -Depth 14
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $parent = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        [void](New-Item -ItemType Directory -Force -Path $parent)
    }
    Set-Content -LiteralPath $OutputPath -Value $json
}

$json

[CmdletBinding()]
param(
    [string]$StatePath = '.\fixtures\learner-state.valid.json',
    [string]$AssessmentResultPath = '.\fixtures\assessment-result.correct.json',
    [string]$OutputPath = '',
    [datetime]$Now = '2026-05-25T12:00:00Z'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ReviewDueAt {
    param(
        [datetime]$EvidenceAt,
        [double]$Confidence
    )
    if ($Confidence -lt 0.50) { return $EvidenceAt.AddDays(1) }
    if ($Confidence -lt 0.70) { return $EvidenceAt.AddDays(3) }
    if ($Confidence -lt 0.85) { return $EvidenceAt.AddDays(7) }
    return $EvidenceAt.AddDays(14)
}

function Set-ArrayProperty {
    param(
        [object]$Object,
        [string]$Name,
        [object[]]$Value
    )
    $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value -Force
}

$state = (& .\scripts\state\read-learner-state.ps1 -Path $StatePath | Out-String) | ConvertFrom-Json
$resultPath = (Resolve-Path -LiteralPath $AssessmentResultPath).Path
$result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
if ($result.schemaVersion -ne 1) {
    throw 'Assessment result schemaVersion must be 1.'
}

$objectiveId = $result.masteryEvidence.objectiveId
$masteryRecords = @($state.mastery)
$mastery = @($masteryRecords | Where-Object { $_.objectiveId -eq $objectiveId } | Select-Object -First 1)
if ($mastery.Count -eq 0) {
    $mastery = [pscustomobject]@{
        objectiveId = $objectiveId
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
$delta = [double]$result.masteryEvidence.confidenceDelta
$newConfidence = [Math]::Min([Math]::Max($oldConfidence + $delta, 0), 1)
$mastery.confidence = [Math]::Round($newConfidence, 4)
$mastery.lastEvidenceAt = $Now.ToUniversalTime().ToString('o')
$mastery.evidenceCount = [int]$mastery.evidenceCount + 1
$sources = @($mastery.evidenceSources)
if ($sources -notcontains $result.masteryEvidence.evidenceType) {
    $sources += $result.masteryEvidence.evidenceType
}
Set-ArrayProperty -Object $mastery -Name 'evidenceSources' -Value $sources
Set-ArrayProperty -Object $state -Name 'mastery' -Value $masteryRecords

$misconceptions = @($state.misconceptions)
if ($result.status -eq 'incorrect') {
    $existing = @($misconceptions | Where-Object { $_.objectiveId -eq $objectiveId -and $_.status -eq 'unresolved' } | Select-Object -First 1)
    if ($existing.Count -eq 0) {
        $misconceptions += [pscustomobject]@{
            misconceptionId = ('mis-{0}-{1}' -f ($objectiveId -replace '[^A-Za-z0-9]+', '-').Trim('-'), $result.itemId)
            objectiveId = $objectiveId
            status = 'unresolved'
            observedAt = $Now.ToUniversalTime().ToString('o')
            remediationPath = @('hint', 'worked-example', 'micro-practice')
        }
    }
}
elseif ($result.status -eq 'correct') {
    foreach ($misconception in $misconceptions | Where-Object { $_.objectiveId -eq $objectiveId -and $_.status -eq 'unresolved' }) {
        $misconception.status = 'resolved'
        $misconception | Add-Member -MemberType NoteProperty -Name 'resolvedAt' -Value $Now.ToUniversalTime().ToString('o') -Force
    }
}
Set-ArrayProperty -Object $state -Name 'misconceptions' -Value $misconceptions

$event = [pscustomobject]@{
    eventId = ('evt-{0}-{1}' -f $Now.ToUniversalTime().ToString('yyyyMMddHHmmss'), $result.itemId)
    learnerId = $state.learnerId
    verb = 'quiz_answered'
    objectId = $objectiveId
    occurredAt = $Now.ToUniversalTime().ToString('o')
    result = [pscustomobject]@{
        success = ($result.status -eq 'correct')
        score = $result.score
        hintUsage = $result.hintUsage
    }
    xapiCandidate = [pscustomobject]@{
        actor = $state.learnerId
        verb = 'answered'
        object = $objectiveId
        result = [pscustomobject]@{
            success = ($result.status -eq 'correct')
            score = $result.score
        }
    }
}
$events = @($state.learningEvents) + $event
Set-ArrayProperty -Object $state -Name 'learningEvents' -Value $events

$reviewDueAt = Get-ReviewDueAt -EvidenceAt $Now.ToUniversalTime() -Confidence $mastery.confidence
$reviewQueue = @($state.reviewQueue | Where-Object { $_.objectiveId -ne $objectiveId })
$reviewQueue += [pscustomobject]@{
    objectiveId = $objectiveId
    dueAt = $reviewDueAt.ToString('o')
    reason = if ($mastery.confidence -lt 0.70) { 'low-confidence' } else { 'spaced-review' }
}
Set-ArrayProperty -Object $state -Name 'reviewQueue' -Value $reviewQueue

$auditEntry = [pscustomobject]@{
    at = $Now.ToUniversalTime().ToString('o')
    objectiveId = $objectiveId
    oldConfidence = $oldConfidence
    newConfidence = $mastery.confidence
    evidenceSource = $result.masteryEvidence.evidenceType
    reason = ('assessment:{0}:{1}' -f $result.itemId, $result.status)
}
$auditLog = @($state.auditLog) + $auditEntry
Set-ArrayProperty -Object $state -Name 'auditLog' -Value $auditLog

$json = $state | ConvertTo-Json -Depth 14
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $parent = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        [void](New-Item -ItemType Directory -Force -Path $parent)
    }
    Set-Content -LiteralPath $OutputPath -Value $json
}

$json

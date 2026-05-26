[CmdletBinding()]
param(
    [string]$Path = '.\fixtures\learner-state.valid.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Field {
    param(
        [object]$Object,
        [string]$Name,
        [string]$Context
    )
    if (-not ($Object.PSObject.Properties.Name -contains $Name)) {
        throw "$Context is missing '$Name'."
    }
}

$statePath = (Resolve-Path -LiteralPath $Path).Path
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json

if ($state.schemaVersion -ne 1) {
    throw 'Learner state schemaVersion must be 1.'
}
foreach ($field in @('learnerId', 'profile', 'mastery', 'misconceptions', 'reviewQueue', 'learningEvents', 'auditLog', 'privacy', 'sync')) {
    Assert-Field -Object $state -Name $field -Context 'Learner state'
}
if ([string]::IsNullOrWhiteSpace($state.learnerId)) {
    throw 'Learner state learnerId is required.'
}
if ($state.profile.learnerId -ne $state.learnerId) {
    throw 'Learner state profile.learnerId must match learnerId.'
}
foreach ($mastery in @($state.mastery)) {
    foreach ($field in @('objectiveId', 'confidence', 'lastEvidenceAt', 'evidenceCount', 'evidenceSources')) {
        Assert-Field -Object $mastery -Name $field -Context 'Mastery record'
    }
    if ($mastery.confidence -lt 0 -or $mastery.confidence -gt 1) {
        throw "Mastery confidence out of range for $($mastery.objectiveId)."
    }
}
foreach ($event in @($state.learningEvents)) {
    foreach ($field in @('eventId', 'learnerId', 'verb', 'objectId', 'occurredAt', 'result', 'xapiCandidate')) {
        Assert-Field -Object $event -Name $field -Context 'Learning event'
    }
}
foreach ($field in @('piiPolicy', 'redactionFields', 'localOnly')) {
    Assert-Field -Object $state.privacy -Name $field -Context 'Privacy policy'
}
foreach ($field in @('mode', 'lastSyncedAt', 'conflictPolicy')) {
    Assert-Field -Object $state.sync -Name $field -Context 'Sync policy'
}

$state | ConvertTo-Json -Depth 12

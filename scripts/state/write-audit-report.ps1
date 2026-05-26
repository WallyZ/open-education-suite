[CmdletBinding()]
param(
    [string]$StatePath = '.\fixtures\learner-state.valid.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$state = (& .\scripts\state\read-learner-state.ps1 -Path $StatePath | Out-String) | ConvertFrom-Json
[ordered]@{
    schemaVersion = 1
    learnerId = $state.learnerId
    auditCount = @($state.auditLog).Count
    mastery = @($state.mastery | ForEach-Object {
        [ordered]@{
            objectiveId = $_.objectiveId
            confidence = $_.confidence
            lastEvidenceAt = $_.lastEvidenceAt
            evidenceCount = $_.evidenceCount
            evidenceSources = @($_.evidenceSources)
        }
    })
    auditLog = @($state.auditLog)
} | ConvertTo-Json -Depth 10

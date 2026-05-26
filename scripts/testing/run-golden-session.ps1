[CmdletBinding()]
param(
    [string]$OutputStatePath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($OutputStatePath)) {
    $repo = (& git -C . rev-parse --show-toplevel).Trim()
    $OutputStatePath = Join-Path (Join-Path (Join-Path $repo '.codex-cache') 'tmp') ('golden-session-state-{0}.json' -f [Guid]::NewGuid().ToString('N'))
}

$session = (& .\scripts\teaching\start-session.ps1 -StatePath '.\fixtures\learner-state.valid.json' -Response 'step into' -HintsUsed 1 -OutputStatePath $OutputStatePath -NonInteractive | Out-String) | ConvertFrom-Json
$errors = [System.Collections.Generic.List[string]]::new()

if ($session.action.actionType -ne 'practice') {
    $errors.Add("Expected practice action but got '$($session.action.actionType)'.")
}
if ($session.assessmentItemId -ne 'debugging-mcq-001') {
    $errors.Add("Expected debugging-mcq-001 but got '$($session.assessmentItemId)'.")
}
if (-not (Test-Path -LiteralPath $OutputStatePath -PathType Leaf)) {
    $errors.Add("Updated state file was not written: $OutputStatePath")
}
else {
    $updated = (& .\scripts\state\read-learner-state.ps1 -Path $OutputStatePath | Out-String) | ConvertFrom-Json
    $mastery = @($updated.mastery | Where-Object { $_.objectiveId -eq 'software-development:objectives/debugging' } | Select-Object -First 1)
    if ($mastery.Count -eq 0 -or $mastery[0].confidence -le 0.42) {
        $errors.Add('Expected updated mastery confidence to increase.')
    }
}

[ordered]@{
    schemaVersion = 1
    checkedAt = (Get-Date).ToString('o')
    errorCount = $errors.Count
    errors = @($errors)
    session = $session
} | ConvertTo-Json -Depth 12

if ($errors.Count -gt 0) {
    exit 1
}

exit 0

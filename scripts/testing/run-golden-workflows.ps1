[CmdletBinding()]
param(
    [string]$FixturePath = '.\fixtures\learner-scenarios.json',
    [string]$ExpectedPath = '.\fixtures\golden-workflows.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$expectedFile = (Resolve-Path -LiteralPath $ExpectedPath).Path
$expected = Get-Content -LiteralPath $expectedFile -Raw | ConvertFrom-Json
if ($expected.schemaVersion -ne 1) {
    throw 'Golden workflow fixture schemaVersion must be 1.'
}

$selector = Join-Path (Get-Location) 'scripts\teaching\select-next-action.ps1'
$decisionOutput = & $selector -LearnerPath $FixturePath -Now ([datetime]$expected.now)
if ($LASTEXITCODE -ne 0) {
    throw "Teaching selector failed with exit code $LASTEXITCODE."
}
$decisions = ($decisionOutput | Out-String) | ConvertFrom-Json

$errors = [System.Collections.Generic.List[string]]::new()
foreach ($expectation in $expected.expectations) {
    $actual = @($decisions.decisions | Where-Object { $_.learnerId -eq $expectation.learnerId } | Select-Object -First 1)
    if ($actual.Count -eq 0) {
        $errors.Add("Missing decision for learner '$($expectation.learnerId)'.")
        continue
    }
    if ($actual[0].actionType -ne $expectation.actionType) {
        $errors.Add("Learner '$($expectation.learnerId)' actionType expected '$($expectation.actionType)' but got '$($actual[0].actionType)'.")
    }
    if ($actual[0].reason -ne $expectation.reason) {
        $errors.Add("Learner '$($expectation.learnerId)' reason expected '$($expectation.reason)' but got '$($actual[0].reason)'.")
    }
}

[ordered]@{
    schemaVersion = 1
    checkedAt = (Get-Date).ToString('o')
    expectationCount = @($expected.expectations).Count
    errorCount = $errors.Count
    errors = @($errors)
} | ConvertTo-Json -Depth 6

if ($errors.Count -gt 0) {
    exit 1
}

exit 0

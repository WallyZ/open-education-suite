[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$errors = [System.Collections.Generic.List[string]]::new()

$rubric = Get-Content -LiteralPath '.\docs\teaching-quality-rubric.md' -Raw
foreach ($category in @('Clarity', 'Correctness', 'Diagnosis', 'Scaffolding', 'Feedback', 'Motivation', 'Rigor', 'Accessibility', 'Learner Agency')) {
    if ($rubric -notmatch [regex]::Escape($category)) {
        $errors.Add("Teaching quality rubric missing category: $category")
    }
}
foreach ($requiredPhrase in @('Adaptive Difficulty Rules', 'Deliberate Practice Loop', 'Metacognitive Coaching', 'Human Review Workflow')) {
    if ($rubric -notmatch [regex]::Escape($requiredPhrase)) {
        $errors.Add("Teaching quality rubric missing section: $requiredPhrase")
    }
}

$benchmarks = Get-Content -LiteralPath '.\fixtures\teaching-quality-benchmarks.json' -Raw | ConvertFrom-Json
if ($benchmarks.schemaVersion -ne 1) {
    $errors.Add('Teaching quality benchmarks schemaVersion must be 1.')
}
foreach ($learnerId in @('bored', 'anxious', 'overconfident', 'confused', 'advanced', 'returning', 'time-constrained')) {
    if (@($benchmarks.benchmarks | Where-Object { $_.learnerId -eq $learnerId }).Count -ne 1) {
        $errors.Add("Missing benchmark learner: $learnerId")
    }
}

$calibration = Get-Content -LiteralPath '.\fixtures\mastery-calibration.json' -Raw | ConvertFrom-Json
foreach ($check in @($calibration.checks)) {
    $difference = [Math]::Abs([double]$check.predictedConfidence - [double]$check.laterEvidenceScore)
    if ($difference -gt [double]$check.tolerance) {
        $errors.Add("Mastery calibration outside tolerance for $($check.objectiveId).")
    }
}

$aiEval = (& .\scripts\ai\evaluate-model-output.ps1 | Out-String) | ConvertFrom-Json
if ($aiEval.errorCount -ne 0) {
    $errors.Add('AI teacher output evaluation failed.')
}

$registry = Get-Content -LiteralPath '.\content-sources.json' -Raw | ConvertFrom-Json
foreach ($source in @($registry.contentSources)) {
    $sourceRoot = (Resolve-Path -LiteralPath $source.localPath).Path
    $misconceptionPath = Join-Path $sourceRoot 'misconceptions\misconceptions.md'
    if (-not (Test-Path -LiteralPath $misconceptionPath -PathType Leaf)) {
        $errors.Add("Content source '$($source.id)' is missing misconception library.")
    }
}

[ordered]@{
    schemaVersion = 1
    checkedAt = (Get-Date).ToString('o')
    errorCount = $errors.Count
    errors = @($errors)
} | ConvertTo-Json -Depth 8

if ($errors.Count -gt 0) {
    exit 1
}

exit 0

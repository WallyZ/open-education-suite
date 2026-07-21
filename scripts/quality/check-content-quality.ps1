[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Add-Error {
    param(
        [System.Collections.Generic.List[string]]$Errors,
        [string]$Message
    )
    $Errors.Add($Message)
}

function Test-LocalMarkdownLinks {
    param(
        [System.Collections.Generic.List[string]]$Errors,
        [string[]]$Roots
    )

    foreach ($root in $Roots) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) {
            continue
        }
        foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.md') {
            $lineNumber = 0
            foreach ($line in Get-Content -LiteralPath $file.FullName) {
                $lineNumber++
                $matches = [regex]::Matches($line, '\[[^\]]+\]\(([^)]+)\)')
                foreach ($match in $matches) {
                    $target = $match.Groups[1].Value.Trim()
                    if ([string]::IsNullOrWhiteSpace($target)) {
                        continue
                    }
                    if ($target -match '^(https?|guide|content|mailto):') {
                        continue
                    }
                    if ($target.StartsWith('#')) {
                        continue
                    }

                    $withoutAnchor = ($target -split '#')[0]
                    if ([string]::IsNullOrWhiteSpace($withoutAnchor)) {
                        continue
                    }
                    if ($withoutAnchor.StartsWith('/')) {
                        continue
                    }
                    $withoutAnchor = $withoutAnchor.Replace('/', '\')

                    if ([System.IO.Path]::IsPathRooted($withoutAnchor)) {
                        $candidate = $withoutAnchor
                    }
                    else {
                        $candidate = Join-Path $file.DirectoryName $withoutAnchor
                    }

                    if (-not (Test-Path -LiteralPath $candidate)) {
                        Add-Error $Errors "Broken local Markdown link in $($file.FullName):$lineNumber -> $target"
                    }
                }
            }
        }
    }
}

$errors = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

$scanOutput = & .\scripts\ingestion\scan-content-sources.ps1
if ($LASTEXITCODE -ne 0) {
    Add-Error $errors "Content source scanner failed with exit code $LASTEXITCODE."
}
$scanReport = ($scanOutput | Out-String) | ConvertFrom-Json
foreach ($scanError in @($scanReport.validationErrors)) {
    Add-Error $errors "Content source validation error: $scanError"
}
foreach ($source in @($scanReport.sources)) {
    $manifest = Get-Content -LiteralPath $source.manifestPath -Raw | ConvertFrom-Json
    foreach ($pathField in @('studyPlans', 'resources', 'objectives', 'assessments')) {
        if (-not $manifest.paths.$pathField) {
            Add-Error $errors "Content manifest '$($source.id)' is missing paths.$pathField."
        }
    }
    if ([string]::IsNullOrWhiteSpace($manifest.license) -or $manifest.license -eq 'TBD') {
        Add-Error $errors "Content manifest '$($source.id)' must declare an explicit license."
    }
    foreach ($object in @($source.objects)) {
        if ([string]::IsNullOrWhiteSpace($object.attribution)) {
            Add-Error $errors "Imported object missing attribution: $($object.id)"
        }
        if ([string]::IsNullOrWhiteSpace($object.license) -or $object.license -eq 'UNSPECIFIED' -or $object.license -eq 'TBD') {
            Add-Error $errors "Imported object missing license: $($object.id)"
        }
    }
    foreach ($requiredType in @('study-plan', 'resource', 'objective', 'assessment')) {
        $realObjects = @($source.objects | Where-Object { $_.type -eq $requiredType -and $_.sourcePath -notmatch 'README\.md$' })
        if ($realObjects.Count -lt 1) {
            Add-Error $errors "Content source '$($source.id)' has no non-README $requiredType objects."
        }
    }
}

$assessment = Get-Content -LiteralPath '.\fixtures\assessment-items.json' -Raw | ConvertFrom-Json
if ($assessment.schemaVersion -ne 1) {
    Add-Error $errors 'Assessment fixture schemaVersion must be 1.'
}
foreach ($item in @($assessment.items)) {
    if ([string]::IsNullOrWhiteSpace($item.itemId)) {
        Add-Error $errors 'Assessment item missing itemId.'
    }
    if ([string]::IsNullOrWhiteSpace($item.objectiveId) -or $item.objectiveId -notmatch ':objectives/') {
        Add-Error $errors "Assessment item '$($item.itemId)' has malformed objectiveId."
    }
    if (-not $item.feedbackTemplates.correct -or -not $item.feedbackTemplates.partial -or -not $item.feedbackTemplates.incorrect -or -not $item.feedbackTemplates.uncertain) {
        Add-Error $errors "Assessment item '$($item.itemId)' has incomplete feedback templates."
    }
}

$learners = Get-Content -LiteralPath '.\fixtures\learner-scenarios.json' -Raw | ConvertFrom-Json
foreach ($learner in @($learners.learners)) {
    foreach ($mastery in @($learner.objectiveMastery)) {
        if ([string]::IsNullOrWhiteSpace($mastery.objectiveId) -or $mastery.objectiveId -notmatch ':objectives/') {
            Add-Error $errors "Learner '$($learner.learnerId)' has malformed mastery objectiveId."
        }
    }
    foreach ($event in @($learner.learningEvents)) {
        if (-not $event.xapiCandidate) {
            Add-Error $errors "Learning event '$($event.eventId)' is missing xapiCandidate."
        }
    }
}

$contentRoots = @('.\docs', '.\study-plans', '.\resources')
foreach ($source in @($scanReport.sources)) {
    if ($source.resolvedPath) {
        $contentRoots += $source.resolvedPath
    }
}
Test-LocalMarkdownLinks -Errors $errors -Roots $contentRoots

[ordered]@{
    schemaVersion = 1
    checkedAt = (Get-Date).ToString('o')
    errorCount = $errors.Count
    warningCount = $warnings.Count
    errors = @($errors)
    warnings = @($warnings)
} | ConvertTo-Json -Depth 8

if ($errors.Count -gt 0) {
    exit 1
}

exit 0

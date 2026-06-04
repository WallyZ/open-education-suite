[CmdletBinding()]
param(
    [string]$PatternPath = '.\fixtures\information-presentation-patterns.json',
    [string]$TodoPath = '.\docs\todo\TODO_20_information_presentation_strategy.md'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Add-CheckError {
    param(
        [System.Collections.Generic.List[string]]$Errors,
        [string]$Message
    )

    $Errors.Add($Message)
}

function Test-HasText {
    param([object]$Value)

    return -not [string]::IsNullOrWhiteSpace([string]$Value)
}

$errors = [System.Collections.Generic.List[string]]::new()

if (-not (Test-Path -LiteralPath $PatternPath -PathType Leaf)) {
    Add-CheckError $errors "Missing information presentation patterns fixture: $PatternPath"
}
if (-not (Test-Path -LiteralPath $TodoPath -PathType Leaf)) {
    Add-CheckError $errors "Missing information presentation TODO lane: $TodoPath"
}

if ($errors.Count -eq 0) {
    $patterns = Get-Content -LiteralPath $PatternPath -Raw | ConvertFrom-Json
    $todoText = Get-Content -LiteralPath $TodoPath -Raw

    if ($patterns.schemaVersion -ne 1) {
        Add-CheckError $errors 'Information presentation patterns fixture must use schemaVersion 1.'
    }
    if ($patterns.strategyId -ne 'information-presentation-patterns-v1') {
        Add-CheckError $errors 'Information presentation patterns fixture must use the approved strategyId.'
    }

    foreach ($typeId in @('fact', 'concept', 'procedure', 'process', 'causal-system', 'spatial-structure', 'quantitative-data', 'code-or-system', 'design-critique', 'lab-workflow', 'case-or-argument', 'creative-work')) {
        $type = @($patterns.informationTypes | Where-Object { $_.id -eq $typeId })
        if ($type.Count -ne 1) {
            Add-CheckError $errors "Missing information type: $typeId"
            continue
        }
        if (@($type[0].presentationModes | Where-Object { Test-HasText $_ }).Count -lt 4) {
            Add-CheckError $errors "Information type must define at least four presentation modes: $typeId"
        }
        if (@($type[0].practiceEvidence | Where-Object { Test-HasText $_ }).Count -lt 2) {
            Add-CheckError $errors "Information type must define practice evidence: $typeId"
        }
    }

    foreach ($subjectId in @('math', 'science', 'programming', 'game-development', 'cybersecurity', 'data-science', 'humanities', 'language', 'art-design', 'professional-practice')) {
        $subject = @($patterns.subjectProfiles | Where-Object { $_.id -eq $subjectId })
        if ($subject.Count -ne 1) {
            Add-CheckError $errors "Missing subject presentation profile: $subjectId"
            continue
        }
        if (@($subject[0].primaryPatterns | Where-Object { Test-HasText $_ }).Count -lt 3) {
            Add-CheckError $errors "Subject profile must define at least three primary patterns: $subjectId"
        }
        if (@($subject[0].avoid | Where-Object { Test-HasText $_ }).Count -lt 1) {
            Add-CheckError $errors "Subject profile must define at least one anti-pattern: $subjectId"
        }
    }

    foreach ($ruleId in @('novice-start', 'misconception-repair', 'procedure-fluency', 'advanced-transfer', 'accessibility-adaptation')) {
        $rule = @($patterns.adaptiveSelectionRules | Where-Object { $_.id -eq $ruleId })
        if ($rule.Count -ne 1) {
            Add-CheckError $errors "Missing adaptive presentation selection rule: $ruleId"
            continue
        }
        if (@($rule[0].when | Where-Object { Test-HasText $_ }).Count -lt 1 -or @($rule[0].choose | Where-Object { Test-HasText $_ }).Count -lt 2 -or @($rule[0].mustInclude | Where-Object { Test-HasText $_ }).Count -lt 1) {
            Add-CheckError $errors "Adaptive selection rule is incomplete: $ruleId"
        }
    }

    if ([int]$patterns.qualityRequirements.minimumModesPerComplexObjective -lt 3) {
        Add-CheckError $errors 'Complex objectives must require at least three presentation modes.'
    }
    foreach ($move in @('explain', 'show-example', 'ask-retrieval', 'provide-practice', 'collect-evidence')) {
        if (@($patterns.qualityRequirements.requiredLearningMoves | Where-Object { $_ -eq $move }).Count -ne 1) {
            Add-CheckError $errors "Missing required learning move: $move"
        }
    }
    foreach ($alternate in @('caption-or-transcript', 'alt-text-for-visuals', 'keyboard-path-for-interactives')) {
        if (@($patterns.qualityRequirements.requiredAccessibleAlternates | Where-Object { $_ -eq $alternate }).Count -ne 1) {
            Add-CheckError $errors "Missing accessible alternate requirement: $alternate"
        }
    }
    if ($patterns.qualityRequirements.readOnlyAgainstContentRepos -ne $true) {
        Add-CheckError $errors 'Presentation strategy must remain read-only against content repos.'
    }
    foreach ($forbidden in @('lecture-only-for-everything', 'passive-watch-time-as-mastery', 'subject-content-inside-core-repo')) {
        if (@($patterns.qualityRequirements.forbiddenDefaults | Where-Object { $_ -eq $forbidden }).Count -ne 1) {
            Add-CheckError $errors "Missing forbidden default: $forbidden"
        }
    }

    foreach ($todoToken in @(
        '[x] Add an information-type pattern library',
        '[x] Add subject-aware presentation profiles',
        '[x] Add adaptive presentation selection rules',
        '[x] Add modality quality requirements',
        '[x] Add a verification gate'
    )) {
        if ($todoText.IndexOf($todoToken, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
            Add-CheckError $errors "Information presentation TODO item is not complete: $todoToken"
        }
    }
}

[ordered]@{
    schemaVersion = 1
    checkedAt = (Get-Date).ToString('o')
    strategyId = $(if ($errors.Count -eq 0) { $patterns.strategyId } else { $null })
    readOnly = $true
    networkAccess = 'none'
    errorCount = $errors.Count
    errors = @($errors)
} | ConvertTo-Json -Depth 8

if ($errors.Count -gt 0) {
    exit 1
}

exit 0

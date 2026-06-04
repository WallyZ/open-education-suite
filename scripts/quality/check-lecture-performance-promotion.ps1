[CmdletBinding()]
param(
    [string]$PolicyPath = '.\fixtures\lecture-performance-promotion-policy.json',
    [string]$RendererPath = '.\scripts\teaching\render-lecture-publish-fixture.ps1',
    [string]$TodoPath = '.\docs\todo\TODO_19_publish_grade_classroom_video_realism.md'
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

function Test-HasProperty {
    param(
        [object]$Value,
        [string]$Name
    )

    return $null -ne $Value -and $null -ne $Value.PSObject.Properties[$Name]
}

function Test-ContainsToken {
    param(
        [string]$Text,
        [string]$Token
    )

    return $Text.IndexOf($Token, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
}

$errors = [System.Collections.Generic.List[string]]::new()

if (-not (Test-Path -LiteralPath $PolicyPath -PathType Leaf)) {
    Add-CheckError $errors "Missing lecture performance promotion policy: $PolicyPath"
}
if (-not (Test-Path -LiteralPath $RendererPath -PathType Leaf)) {
    Add-CheckError $errors "Missing lecture publish renderer: $RendererPath"
}
if (-not (Test-Path -LiteralPath $TodoPath -PathType Leaf)) {
    Add-CheckError $errors "Missing publish-grade realism TODO lane: $TodoPath"
}

$policy = $null
$rendererText = ''
$todoText = ''

if ($errors.Count -eq 0) {
    $policy = Get-Content -LiteralPath $PolicyPath -Raw | ConvertFrom-Json
    $rendererText = Get-Content -LiteralPath $RendererPath -Raw
    $todoText = Get-Content -LiteralPath $TodoPath -Raw

    if ($policy.schemaVersion -ne 1) {
        Add-CheckError $errors 'Lecture performance promotion policy must use schemaVersion 1.'
    }
    if (-not (Test-HasText $policy.policyId) -or $policy.policyId -ne 'lecture-performance-promotion-v1') {
        Add-CheckError $errors 'Lecture performance promotion policy must use the approved policyId.'
    }
    foreach ($sectionName in @('deterministicPreviewPolicy', 'modelBackedCandidatePolicy')) {
        if (-not (Test-HasProperty -Value $policy -Name $sectionName)) {
            Add-CheckError $errors "Lecture performance promotion policy missing section: $sectionName"
        }
    }
    foreach ($sectionName in @('gesturePlanningPolicy', 'sceneRealismPolicy', 'physicalChalkWritingPolicy', 'automatedVisualComparisonPolicy', 'shotDirectorPolicy', 'promotionGate')) {
        if (-not (Test-HasProperty -Value $policy -Name $sectionName)) {
            Add-CheckError $errors "Lecture performance promotion policy missing section: $sectionName"
        }
    }
}

if ($null -ne $policy -and $errors.Count -eq 0) {
    $previewPolicy = $policy.deterministicPreviewPolicy
    if ($previewPolicy.canReplacePublishVideo -ne $false) {
        Add-CheckError $errors 'Deterministic instructor previews must not replace publish video.'
    }
    if ($previewPolicy.requiredPublishPromotion -ne 'blocked-pending-operator-visual-qa') {
        Add-CheckError $errors 'Deterministic preview promotion must stay blocked pending operator visual QA.'
    }
    if ($previewPolicy.requiredVisualQaStatus -ne 'pending-operator-review') {
        Add-CheckError $errors 'Deterministic preview visual QA status must remain pending operator review.'
    }
    if ($previewPolicy.requiredPreviewRenderIncluded -ne $true -or $previewPolicy.requiredModelRenderIncluded -ne $false) {
        Add-CheckError $errors 'Deterministic previews must be marked as preview renders, not model-backed renders.'
    }
    foreach ($fieldName in @('assetId', 'path', 'sha256', 'sourceAssetIds', 'previewRenderIncluded', 'modelRenderIncluded', 'publishPromotion', 'visualQaStatus')) {
        if (@($previewPolicy.requiredPreviewFields | Where-Object { $_ -eq $fieldName }).Count -ne 1) {
            Add-CheckError $errors "Deterministic preview policy missing required field: $fieldName"
        }
    }

    $modelPolicy = $policy.modelBackedCandidatePolicy
    foreach ($fieldName in @('providerId', 'workflowPath', 'sourceAssetIds', 'seed', 'configHash', 'durationSeconds', 'operatorReviewStatus')) {
        if (@($modelPolicy.requiredRenderFields | Where-Object { $_ -eq $fieldName }).Count -ne 1) {
            Add-CheckError $errors "Model-backed candidate policy missing required render field: $fieldName"
        }
    }
    foreach ($gateId in @('subject-owned-path', 'checksum-verified', 'archive-manifest-refreshed', 'automated-visual-qa-passed', 'operator-visual-qa-approved', 'operator-publish-gate-approved')) {
        if (@($modelPolicy.requiredBeforePromotion | Where-Object { $_ -eq $gateId }).Count -ne 1) {
            Add-CheckError $errors "Model-backed candidate policy missing promotion gate: $gateId"
        }
    }
    foreach ($qaId in @('lip-sync-timing', 'gaze-direction', 'head-hand-motion-naturalness', 'board-writing-gesture-synchronization')) {
        if (@($modelPolicy.requiredQaEvidence | Where-Object { $_ -eq $qaId }).Count -ne 1) {
            Add-CheckError $errors "Model-backed candidate policy missing QA evidence: $qaId"
        }
    }
    foreach ($gestureAction in @('pointing', 'writing', 'gaze-shift', 'pause-posture', 'board-occlusion-avoidance')) {
        if (@($policy.gesturePlanningPolicy.requiredActions | Where-Object { $_ -eq $gestureAction }).Count -ne 1) {
            Add-CheckError $errors "Gesture planning policy missing required action: $gestureAction"
        }
    }
    foreach ($sceneTarget in @('lighting', 'contact-shadows', 'board-surface-integration', 'camera-depth', 'lens-motion', 'compositing-artifacts')) {
        if (@($policy.sceneRealismPolicy.requiredTargets | Where-Object { $_ -eq $sceneTarget }).Count -ne 1) {
            Add-CheckError $errors "Scene realism policy missing target: $sceneTarget"
        }
    }
    foreach ($chalkTarget in @('chalk-texture', 'stroke-timing', 'erasing', 'hand-alignment', 'board-residue')) {
        if (@($policy.physicalChalkWritingPolicy.requiredTargets | Where-Object { $_ -eq $chalkTarget }).Count -ne 1) {
            Add-CheckError $errors "Physical chalk-writing policy missing target: $chalkTarget"
        }
    }
    foreach ($evidenceType in @('board-readability', 'mouth-open-timing', 'gaze-direction', 'instructor-occlusion', 'board-crop-correctness', 'shot-selection')) {
        if (@($policy.automatedVisualComparisonPolicy.requiredEvidenceTypes | Where-Object { $_ -eq $evidenceType }).Count -ne 1) {
            Add-CheckError $errors "Automated visual comparison policy missing evidence type: $evidenceType"
        }
    }
    foreach ($shot in @('front-row', 'board-close-up', 'instructor-close-up')) {
        if (@($policy.shotDirectorPolicy.requiredShots | Where-Object { $_ -eq $shot }).Count -ne 1) {
            Add-CheckError $errors "Shot-director policy missing shot: $shot"
        }
    }
}

if ($errors.Count -eq 0) {
    foreach ($rendererToken in @(
        'motionAndLipSync',
        'motionPreviewRender',
        'lipSyncPreviewRender',
        'modelBackedOutputRequirements',
        'gesturePlan',
        'boardStateActions',
        'pausePostures',
        'board-occlusion-avoidance',
        'visualSync.boardSurface',
        'sceneRealismTargets',
        'contactShadows',
        'boardSurfaceIntegration',
        'physicalChalkTargets',
        'chalkTexture',
        'boardResidue',
        'automatedVisualComparisonEvidence',
        'mouth-open-timing',
        'board-crop-correctness',
        'shotDirectorPlan',
        'instructor-close-up',
        'operator publish gate approval',
        'model-backed-publish-candidate',
        'operatorReviewStatus',
        'archive-manifest-refreshed',
        'previewRenderIncluded = $true',
        'modelRenderIncluded = $false',
        "publishPromotion = 'blocked-pending-operator-visual-qa'",
        "visualQaStatus = 'pending-operator-review'"
    )) {
        if (-not (Test-ContainsToken -Text $rendererText -Token $rendererToken)) {
            Add-CheckError $errors "Lecture publish renderer missing deterministic preview promotion token: $rendererToken"
        }
    }

    if (Test-ContainsToken -Text $rendererText -Token 'modelRenderIncluded = $true') {
        foreach ($rendererToken in @('providerId', 'workflowPath', 'seed', 'configHash', 'operatorReviewStatus', 'model-backed-publish-candidate')) {
            if (-not (Test-ContainsToken -Text $rendererText -Token $rendererToken)) {
                Add-CheckError $errors "Model-backed render candidates must include required promotion metadata before modelRenderIncluded can be true: $rendererToken"
            }
        }
    }

    foreach ($todoToken in @(
        'Publish-Grade Classroom Video Realism',
        '[x] Add a publish-grade instructor performance manifest and gate',
        '[x] Require model-backed motion and lip-sync outputs',
        '[x] Add instructor gesture planning metadata',
        '[x] Add classroom scene realism targets',
        '[x] Add physical chalk-writing targets',
        '[x] Add automated visual comparison evidence',
        '[x] Add a shot-director plan',
        '[x] Promote a model-backed instructor performance candidate'
    )) {
        if (-not (Test-ContainsToken -Text $todoText -Token $todoToken)) {
            Add-CheckError $errors "Publish-grade realism TODO lane missing token: $todoToken"
        }
    }
}

[ordered]@{
    schemaVersion = 1
    checkedAt = (Get-Date).ToString('o')
    policyId = $(if ($null -ne $policy) { $policy.policyId } else { $null })
    deterministicPreviewsCanReplacePublishVideo = $false
    modelBackedCandidateGate = 'required-before-promotion'
    readOnly = $true
    networkAccess = 'none'
    errorCount = $errors.Count
    errors = @($errors)
} | ConvertTo-Json -Depth 8

if ($errors.Count -gt 0) {
    exit 1
}

exit 0

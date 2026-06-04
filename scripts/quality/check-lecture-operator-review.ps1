[CmdletBinding()]
param(
    [string]$ManifestPath = '..\open-education-game-development\generated-lectures\gdev-101-design-vocabulary\lecture-video.json',
    [string]$WorkflowPath = '.\fixtures\lecture-operator-review-workflow.json',
    [switch]$SelfTest,
    [switch]$RequirePublishReady
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Add-ReviewError {
    param(
        [System.Collections.Generic.List[string]]$Errors,
        [string]$Message
    )
    $Errors.Add($Message)
}

function Test-HasProperty {
    param(
        [object]$Value,
        [string]$Name
    )

    return $null -ne $Value -and @($Value.PSObject.Properties.Name | Where-Object { $_ -eq $Name }).Count -eq 1
}

function Test-HasText {
    param([object]$Value)
    return -not [string]::IsNullOrWhiteSpace([string]$Value)
}

function Copy-JsonObject {
    param([object]$Value)
    return (($Value | ConvertTo-Json -Depth 30) | ConvertFrom-Json)
}

function Test-ReviewerAllowed {
    param(
        [object]$Workflow,
        [string]$Reviewer
    )

    if (-not (Test-HasText $Reviewer)) {
        return $false
    }

    return @($Workflow.prohibitedReviewers | Where-Object { $_ -eq $Reviewer }).Count -eq 0
}

function Test-TextContainsAll {
    param(
        [string]$Text,
        [string[]]$Tokens
    )

    foreach ($token in $Tokens) {
        if (-not $Text.Contains($token)) {
            return $false
        }
    }
    return $true
}

function Test-RealismReviewEvidence {
    param(
        [object]$Package,
        [object]$Stage,
        [System.Collections.Generic.List[string]]$Errors
    )

    $evidenceText = (@($Stage.evidence) -join ' ').ToLowerInvariant()
    $requirements = @(
        @{ label = 'face/body consistency'; tokens = @('face', 'body', 'consistency') },
        @{ label = 'front-row framing'; tokens = @('front-row', 'framing') },
        @{ label = 'board readability'; tokens = @('board', 'readability') },
        @{ label = 'board occlusion'; tokens = @('board', 'occlusion') },
        @{ label = 'board close-up usefulness'; tokens = @('board', 'close-up') },
        @{ label = 'gesture timing'; tokens = @('gesture', 'timing') },
        @{ label = 'lip-sync timing'; tokens = @('lip-sync', 'timing') },
        @{ label = 'gaze direction'; tokens = @('gaze', 'direction') },
        @{ label = 'head and hand motion naturalness'; tokens = @('head', 'hand', 'naturalness') },
        @{ label = 'board-writing gesture synchronization'; tokens = @('board-writing', 'gesture', 'synchronization') },
        @{ label = 'absence of whole-frame teaching text overlays'; tokens = @('whole-frame', 'overlay') },
        @{ label = 'generated instructor disclosure'; tokens = @('disclosure') }
    )

    foreach ($requirement in $requirements) {
        if (-not (Test-TextContainsAll -Text $evidenceText -Tokens ([string[]]$requirement.tokens))) {
            Add-ReviewError $Errors "Instructor realism review evidence must cover $($requirement.label)."
        }
    }

    if (-not (Test-HasProperty -Value $Package -Name 'generatedInstructor') -or -not (Test-HasText $Package.generatedInstructor.disclosure)) {
        Add-ReviewError $Errors 'Instructor realism review requires generated instructor disclosure before publish.'
    }
    elseif (-not (Test-HasProperty -Value $Package.generatedInstructor -Name 'realismProfile')) {
        Add-ReviewError $Errors 'Instructor realism review requires a generated instructor realismProfile.'
    }
}

function Test-LectureOperatorReview {
    param(
        [object]$Package,
        [object]$Workflow,
        [switch]$RequirePublishReady
    )

    $errors = [System.Collections.Generic.List[string]]::new()

    if ($Workflow.schemaVersion -ne 1) {
        Add-ReviewError $errors 'Operator review workflow schemaVersion must be 1.'
    }
    if (-not (Test-HasText $Workflow.workflowId)) {
        Add-ReviewError $errors 'Operator review workflow must declare workflowId.'
    }
    foreach ($statusValue in @('pending', 'approved', 'changes-requested', 'rejected')) {
        if (@($Workflow.allowedStatuses | Where-Object { $_ -eq $statusValue }).Count -ne 1) {
            Add-ReviewError $errors "Operator review workflow missing allowed status: $statusValue"
        }
    }

    if (-not (Test-HasProperty -Value $Package -Name 'operatorReview')) {
        Add-ReviewError $errors 'Lecture package must include operatorReview before publish review.'
        return [ordered]@{
            passed = $false
            publishReady = $false
            errorCount = $errors.Count
            errors = @($errors)
        }
    }

    $review = $Package.operatorReview
    if ($review.workflowId -ne $Workflow.workflowId) {
        Add-ReviewError $errors 'Lecture package operatorReview workflowId must match the approved workflow.'
    }
    if (@($Workflow.allowedPublishStatuses | Where-Object { $_ -eq $review.publishStatus }).Count -ne 1) {
        Add-ReviewError $errors "Operator review publishStatus is not allowed: $($review.publishStatus)"
    }

    $stageMap = @{}
    foreach ($stage in @($review.stages)) {
        if (-not (Test-HasText $stage.stageId)) {
            Add-ReviewError $errors 'Operator review stage is missing stageId.'
            continue
        }
        if ($stageMap.ContainsKey($stage.stageId)) {
            Add-ReviewError $errors "Operator review stage is duplicated: $($stage.stageId)"
            continue
        }
        $stageMap[$stage.stageId] = $stage
    }

    $allRequiredStagesApproved = $true
    foreach ($requiredStage in @($Workflow.requiredStages)) {
        if (-not $stageMap.ContainsKey($requiredStage.stageId)) {
            Add-ReviewError $errors "Operator review missing required stage: $($requiredStage.stageId)"
            $allRequiredStagesApproved = $false
            continue
        }

        $stage = $stageMap[$requiredStage.stageId]
        if (@($Workflow.allowedStatuses | Where-Object { $_ -eq $stage.status }).Count -ne 1) {
            Add-ReviewError $errors "Operator review stage has invalid status: $($stage.stageId)"
            $allRequiredStagesApproved = $false
            continue
        }

        if ($stage.status -eq 'approved') {
            if (-not (Test-ReviewerAllowed -Workflow $Workflow -Reviewer ([string]$stage.reviewer))) {
                Add-ReviewError $errors "Operator review stage lacks an allowed human reviewer: $($stage.stageId)"
            }
            if (-not (Test-HasText $stage.reviewedAt)) {
                Add-ReviewError $errors "Operator review approved stage is missing reviewedAt: $($stage.stageId)"
            }
            if (@($stage.evidence).Count -lt 1) {
                Add-ReviewError $errors "Operator review approved stage is missing evidence: $($stage.stageId)"
            }
            if ($stage.stageId -eq 'instructor-realism') {
                Test-RealismReviewEvidence -Package $Package -Stage $stage -Errors $errors
            }
        }
        else {
            $allRequiredStagesApproved = $false
        }
    }

    $publishRequested = $RequirePublishReady -or $review.publishStatus -eq 'approved-for-publish'
    if ($publishRequested) {
        if (-not $allRequiredStagesApproved) {
            Add-ReviewError $errors 'All required operator review stages must be approved before publish.'
        }
        if (-not (Test-HasProperty -Value $review -Name 'finalApproval')) {
            Add-ReviewError $errors 'Final package approval is required before publish.'
        }
        elseif ($review.finalApproval.status -ne 'approved') {
            Add-ReviewError $errors 'Final package approval must be approved before publish.'
        }
        else {
            if (-not (Test-ReviewerAllowed -Workflow $Workflow -Reviewer ([string]$review.finalApproval.reviewer))) {
                Add-ReviewError $errors 'Final package approval lacks an allowed human reviewer.'
            }
            if (-not (Test-HasText $review.finalApproval.reviewedAt)) {
                Add-ReviewError $errors 'Final package approval is missing reviewedAt.'
            }
        }

        foreach ($media in @($Package.media | Where-Object { $_.requiredForPublish -eq $true })) {
            if (@('rendered', 'archived') -notcontains $media.status) {
                Add-ReviewError $errors "Required media must be rendered or archived before publish: $($media.assetId)"
            }
            if ([string]$media.sha256 -notmatch '^[a-fA-F0-9]{64}$') {
                Add-ReviewError $errors "Required media must have a 64-character sha256 before publish: $($media.assetId)"
            }
        }
    }

    return [ordered]@{
        passed = ($errors.Count -eq 0)
        publishReady = ($publishRequested -and $errors.Count -eq 0)
        errorCount = $errors.Count
        errors = @($errors)
    }
}

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Missing lecture video manifest: $ManifestPath"
}
if (-not (Test-Path -LiteralPath $WorkflowPath -PathType Leaf)) {
    throw "Missing lecture operator review workflow: $WorkflowPath"
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$workflow = Get-Content -LiteralPath $WorkflowPath -Raw | ConvertFrom-Json
$reviewResult = Test-LectureOperatorReview -Package $manifest -Workflow $workflow -RequirePublishReady:$RequirePublishReady
$selfTestResults = @()
$errors = [System.Collections.Generic.List[string]]::new()

if ($reviewResult.errorCount -gt 0) {
    foreach ($message in @($reviewResult.errors)) {
        Add-ReviewError $errors $message
    }
}

if ($SelfTest) {
    $publishable = Copy-JsonObject -Value $manifest
    $publishable.operatorReview.publishStatus = 'approved-for-publish'
    foreach ($stage in @($publishable.operatorReview.stages)) {
        $stage.status = 'approved'
        $stage.reviewer = 'operator-fixture'
        $stage.reviewedAt = '2026-05-25T12:00:00Z'
        if ($stage.stageId -eq 'instructor-realism') {
            $stage.evidence = @(
                'Face/body consistency reviewed against the local ComfyUI avatar keyframe and realismProfile.',
                'Front-row framing reviewed so the learner has an easy view of the instructor and chalkboard.',
                'Board readability reviewed for the board-local writing layer and chalkboard contrast.',
                'Board occlusion reviewed so the instructor does not cover high-priority board text and board close-up remains available.',
                'Board close-up usefulness reviewed against the recorded board surface crop.',
                'Gesture timing reviewed against storyboard board moments, narration cues, and active-recall pauses.',
                'Lip-sync timing reviewed against final instructor audio and active-recall pause silence.',
                'Gaze direction reviewed for learner-facing explanation, board-facing writing, and return-to-learner cues.',
                'Head and hand motion naturalness reviewed for subtle classroom movement without distracting jitter.',
                'Board-writing gesture synchronization reviewed so pointing and writing gestures align to board-local chalk marks.',
                'No whole-frame teaching text overlays are used; instructional writing is constrained to the board surface.',
                "Generated instructor disclosure reviewed: $($publishable.generatedInstructor.disclosure)"
            )
        }
        else {
            $stage.evidence = @("approved-$($stage.stageId)")
        }
    }
    $publishable.operatorReview.finalApproval.status = 'approved'
    $publishable.operatorReview.finalApproval.reviewer = 'operator-fixture'
    $publishable.operatorReview.finalApproval.reviewedAt = '2026-05-25T12:05:00Z'
    foreach ($media in @($publishable.media | Where-Object { $_.requiredForPublish -eq $true })) {
        $media.status = 'rendered'
        $media.sha256 = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    }

    $publishableResult = Test-LectureOperatorReview -Package $publishable -Workflow $workflow -RequirePublishReady
    if (-not $publishableResult.publishReady) {
        Add-ReviewError $errors 'Operator review self-test publishable case did not pass.'
    }

    $cases = @(
        @{
            name = 'script-not-approved'
            mutate = {
                param([object]$Package)
                (@($Package.operatorReview.stages | Where-Object { $_.stageId -eq 'script' } | Select-Object -First 1))[0].status = 'changes-requested'
            }
        },
        @{
            name = 'visuals-auto-approved'
            mutate = {
                param([object]$Package)
                (@($Package.operatorReview.stages | Where-Object { $_.stageId -eq 'visuals' } | Select-Object -First 1))[0].reviewer = 'ai-system'
            }
        },
        @{
            name = 'planned-required-media'
            mutate = {
                param([object]$Package)
                $Package.media[0].status = 'planned'
                $Package.media[0].sha256 = 'pending-render'
            }
        },
        @{
            name = 'missing-final-approval'
            mutate = {
                param([object]$Package)
                $Package.operatorReview.finalApproval.status = 'pending'
            }
        },
        @{
            name = 'instructor-realism-missing-evidence'
            mutate = {
                param([object]$Package)
                $realismStage = (@($Package.operatorReview.stages | Where-Object { $_.stageId -eq 'instructor-realism' } | Select-Object -First 1))[0]
                $realismStage.evidence = @('Approved without specific realism evidence.')
            }
        },
        @{
            name = 'missing-generated-instructor-disclosure'
            mutate = {
                param([object]$Package)
                $Package.generatedInstructor.disclosure = ''
            }
        }
    )

    foreach ($case in $cases) {
        $copy = Copy-JsonObject -Value $publishable
        & $case.mutate $copy
        $caseResult = Test-LectureOperatorReview -Package $copy -Workflow $workflow -RequirePublishReady
        $blocked = $caseResult.errorCount -gt 0
        if (-not $blocked) {
            Add-ReviewError $errors "Operator review self-test did not block: $($case.name)"
        }

        $selfTestResults += [ordered]@{
            name = $case.name
            blocked = $blocked
            errors = @($caseResult.errors)
        }
    }
}

$blockedCaseCount = @($selfTestResults | Where-Object { $_.blocked -eq $true }).Count
[ordered]@{
    schemaVersion = 1
    checkedAt = (Get-Date).ToString('o')
    manifestPath = $ManifestPath
    workflowPath = $WorkflowPath
    passed = ($errors.Count -eq 0)
    errorCount = $errors.Count
    errors = @($errors)
    publishReady = $reviewResult.publishReady
    baseReviewErrors = @($reviewResult.errors)
    selfTestResults = @($selfTestResults)
    blockedCaseCount = $blockedCaseCount
} | ConvertTo-Json -Depth 12

if ($errors.Count -gt 0) {
    exit 1
}

exit 0

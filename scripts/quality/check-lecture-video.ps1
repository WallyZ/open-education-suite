[CmdletBinding()]
param(
    [string]$SchemaPath = '.\schemas\lecture-video.schema.json',
    [string]$FixturePath = '..\open-education-game-development\generated-lectures\gdev-101-design-vocabulary\lecture-video.json',
    [string]$DocumentPath = '.\docs\generated-lecture-video.md',
    [string]$PersonaPath = '.\fixtures\generated-instructor-persona.default.json',
    [string]$ArchivePolicyPath = '.\fixtures\lecture-media-archive-policy.json',
    [string]$AccessibilityPolicyPath = '.\fixtures\lecture-accessibility-policy.json',
    [string]$QualityRubricPath = '.\fixtures\lecture-video-quality-rubric.json',
    [string]$SelectionRulesPath = '.\fixtures\lecture-selection-rules.json',
    [string]$OperatorReviewWorkflowPath = '.\fixtures\lecture-operator-review-workflow.json',
    [string]$ProductionProvidersPath = '.\fixtures\lecture-production-providers.json',
    [string]$RenderedMediaPath = '..\open-education-game-development\generated-lectures\gdev-101-design-vocabulary\lecture-rendered-media.json',
    [string]$NeuralTtsRenderedMediaPath = '..\open-education-game-development\generated-lectures\gdev-101-design-vocabulary\lecture-neural-tts-rendered-media.json',
    [string]$AvatarRenderedMediaPath = '..\open-education-game-development\generated-lectures\gdev-101-design-vocabulary\lecture-avatar-rendered-media.json',
    [string]$RenderComparisonPath = '..\open-education-game-development\generated-lectures\gdev-101-design-vocabulary\lecture-render-comparison.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. .\scripts\teaching\lecture-paths.ps1

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

function Get-PropertyValue {
    param(
        [object]$InputObject,
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Get-ExpectedInstructorVoiceGender {
    param([string]$InstructorGender)

    switch ($InstructorGender.ToLowerInvariant()) {
        'male' { return 'masculine' }
        'female' { return 'feminine' }
        default { return 'neutral' }
    }
}

function Get-ExpectedInstructorVoiceTokens {
    param([string]$InstructorGender)

    switch ($InstructorGender.ToLowerInvariant()) {
        'male' { return @('masculine', 'lower', 'deeper') }
        'female' { return @('feminine', 'higher', 'warm') }
        default { return @('neutral', 'adult') }
    }
}

function Get-Sha256File {
    param([string]$Path)

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $hashBytes = $sha.ComputeHash($stream)
            return ([System.BitConverter]::ToString($hashBytes) -replace '-', '').ToLowerInvariant()
        }
        finally {
            $sha.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Test-DeterministicStageMetadata {
    param(
        [System.Collections.Generic.List[string]]$Errors,
        [object]$Metadata,
        [string]$Stage,
        [string]$ProviderId,
        [string]$SelectedPipelineId,
        [string]$ExpectedSourceFrameSha256,
        [string]$ExpectedSourceAudioSha256,
        [string]$ArchiveRoot
    )

    if ($null -eq $Metadata) {
        Add-CheckError $Errors "Local ComfyUI $Stage adapter must include deterministic stage metadata."
        return
    }

    $sourceFrame = Get-PropertyValue $Metadata 'sourceFrame'
    $sourceAudio = Get-PropertyValue $Metadata 'sourceAudio'
    $model = Get-PropertyValue $Metadata 'model'
    $renderConfig = Get-PropertyValue $Metadata 'renderConfig'
    $outputArchive = Get-PropertyValue $Metadata 'outputArchive'

    if ((Get-PropertyValue $sourceFrame 'sha256') -ne $ExpectedSourceFrameSha256) {
        Add-CheckError $Errors "Local ComfyUI $Stage metadata must include the rendered avatar source-frame checksum."
    }
    if ((Get-PropertyValue $sourceAudio 'sha256') -ne $ExpectedSourceAudioSha256) {
        Add-CheckError $Errors "Local ComfyUI $Stage metadata must include the rendered audio source checksum."
    }
    if ((Get-PropertyValue $model 'providerId') -ne $ProviderId -or (Get-PropertyValue $model 'selectedPipelineId') -ne $SelectedPipelineId) {
        Add-CheckError $Errors "Local ComfyUI $Stage metadata must identify the selected provider and model pipeline."
    }
    $seed = 0
    if (-not [int]::TryParse([string](Get-PropertyValue $renderConfig 'seed'), [ref]$seed) -or $seed -le 0) {
        Add-CheckError $Errors "Local ComfyUI $Stage metadata must include a deterministic positive seed."
    }
    if ((Get-PropertyValue $renderConfig 'deterministic') -ne $true) {
        Add-CheckError $Errors "Local ComfyUI $Stage metadata must mark the render config deterministic."
    }
    $archivePath = [string](Get-PropertyValue $outputArchive 'path')
    if (-not (Test-HasText $archivePath) -or -not $archivePath.StartsWith($ArchiveRoot)) {
        Add-CheckError $Errors "Local ComfyUI $Stage metadata must include the subject-owned archived output path."
    }
    if ((Get-PropertyValue $outputArchive 'checksumAlgorithm') -ne 'sha256' -or (Get-PropertyValue $outputArchive 'checksumStatus') -ne 'pending-real-render') {
        Add-CheckError $Errors "Local ComfyUI $Stage metadata must declare the SHA-256 archive checksum policy."
    }
    if (-not ([string](Get-PropertyValue $Metadata 'renderPlanSha256') -match '^[a-f0-9]{64}$')) {
        Add-CheckError $Errors "Local ComfyUI $Stage metadata must include a deterministic render-plan SHA-256 checksum."
    }
}

$errors = [System.Collections.Generic.List[string]]::new()

if (-not (Test-Path -LiteralPath $SchemaPath -PathType Leaf)) {
    Add-CheckError $errors "Missing lecture video schema: $SchemaPath"
}
if (-not (Test-Path -LiteralPath $FixturePath -PathType Leaf)) {
    Add-CheckError $errors "Missing lecture video fixture: $FixturePath"
}
if (-not (Test-Path -LiteralPath $DocumentPath -PathType Leaf)) {
    Add-CheckError $errors "Missing generated lecture video document: $DocumentPath"
}
if (-not (Test-Path -LiteralPath $PersonaPath -PathType Leaf)) {
    Add-CheckError $errors "Missing generated instructor persona policy: $PersonaPath"
}
if (-not (Test-Path -LiteralPath $ArchivePolicyPath -PathType Leaf)) {
    Add-CheckError $errors "Missing lecture media archive policy: $ArchivePolicyPath"
}
if (-not (Test-Path -LiteralPath $AccessibilityPolicyPath -PathType Leaf)) {
    Add-CheckError $errors "Missing lecture accessibility policy: $AccessibilityPolicyPath"
}
if (-not (Test-Path -LiteralPath $QualityRubricPath -PathType Leaf)) {
    Add-CheckError $errors "Missing lecture video quality rubric: $QualityRubricPath"
}
if (-not (Test-Path -LiteralPath $SelectionRulesPath -PathType Leaf)) {
    Add-CheckError $errors "Missing lecture selection rules: $SelectionRulesPath"
}
if (-not (Test-Path -LiteralPath $OperatorReviewWorkflowPath -PathType Leaf)) {
    Add-CheckError $errors "Missing lecture operator review workflow: $OperatorReviewWorkflowPath"
}
if (-not (Test-Path -LiteralPath $ProductionProvidersPath -PathType Leaf)) {
    Add-CheckError $errors "Missing lecture production providers: $ProductionProvidersPath"
}
if (-not (Test-Path -LiteralPath $RenderedMediaPath -PathType Leaf)) {
    Add-CheckError $errors "Missing rendered lecture media metadata: $RenderedMediaPath"
}
if (-not (Test-Path -LiteralPath $NeuralTtsRenderedMediaPath -PathType Leaf)) {
    Add-CheckError $errors "Missing neural TTS rendered media metadata: $NeuralTtsRenderedMediaPath"
}
if (-not (Test-Path -LiteralPath $AvatarRenderedMediaPath -PathType Leaf)) {
    Add-CheckError $errors "Missing rendered lecture avatar metadata: $AvatarRenderedMediaPath"
}
if (-not (Test-Path -LiteralPath $RenderComparisonPath -PathType Leaf)) {
    Add-CheckError $errors "Missing rendered lecture comparison metadata: $RenderComparisonPath"
}
if (-not (Test-Path -LiteralPath '.\scripts\teaching\build-lecture-plan.ps1' -PathType Leaf)) {
    Add-CheckError $errors 'Missing lecture plan generator: .\scripts\teaching\build-lecture-plan.ps1'
}
if (-not (Test-Path -LiteralPath '.\scripts\quality\check-lecture-license-gate.ps1' -PathType Leaf)) {
    Add-CheckError $errors 'Missing lecture license gate: .\scripts\quality\check-lecture-license-gate.ps1'
}
if (-not (Test-Path -LiteralPath '.\scripts\state\apply-lecture-checkpoint.ps1' -PathType Leaf)) {
    Add-CheckError $errors 'Missing lecture checkpoint state bridge: .\scripts\state\apply-lecture-checkpoint.ps1'
}
if (-not (Test-Path -LiteralPath '.\scripts\teaching\select-lecture-mode.ps1' -PathType Leaf)) {
    Add-CheckError $errors 'Missing adaptive lecture mode selector: .\scripts\teaching\select-lecture-mode.ps1'
}
if (-not (Test-Path -LiteralPath '.\scripts\quality\check-lecture-operator-review.ps1' -PathType Leaf)) {
    Add-CheckError $errors 'Missing lecture operator review gate: .\scripts\quality\check-lecture-operator-review.ps1'
}
if (-not (Test-Path -LiteralPath '.\scripts\quality\check-lecture-production-providers.ps1' -PathType Leaf)) {
    Add-CheckError $errors 'Missing lecture production provider check: .\scripts\quality\check-lecture-production-providers.ps1'
}
if (-not (Test-Path -LiteralPath '.\scripts\quality\check-comfyui-tts-readiness.ps1' -PathType Leaf)) {
    Add-CheckError $errors 'Missing local ComfyUI TTS readiness gate: .\scripts\quality\check-comfyui-tts-readiness.ps1'
}
if (-not (Test-Path -LiteralPath '.\scripts\teaching\build-lecture-production-job.ps1' -PathType Leaf)) {
    Add-CheckError $errors 'Missing lecture production job builder: .\scripts\teaching\build-lecture-production-job.ps1'
}
if (-not (Test-Path -LiteralPath '.\scripts\teaching\invoke-comfyui-production-adapter.ps1' -PathType Leaf)) {
    Add-CheckError $errors 'Missing local ComfyUI lecture production adapter: .\scripts\teaching\invoke-comfyui-production-adapter.ps1'
}
if (-not (Test-Path -LiteralPath '.\scripts\teaching\invoke-cloud-production-adapter.ps1' -PathType Leaf)) {
    Add-CheckError $errors 'Missing cloud lecture production adapter contracts: .\scripts\teaching\invoke-cloud-production-adapter.ps1'
}
if (-not (Test-Path -LiteralPath '.\scripts\teaching\render-lecture-audio-fixture.ps1' -PathType Leaf)) {
    Add-CheckError $errors 'Missing lecture audio fixture renderer: .\scripts\teaching\render-lecture-audio-fixture.ps1'
}
if (-not (Test-Path -LiteralPath '.\scripts\teaching\render-lecture-avatar-comfyui.ps1' -PathType Leaf)) {
    Add-CheckError $errors 'Missing lecture avatar ComfyUI renderer: .\scripts\teaching\render-lecture-avatar-comfyui.ps1'
}
if (-not (Test-Path -LiteralPath '.\scripts\quality\check-lecture-rendered-media.ps1' -PathType Leaf)) {
    Add-CheckError $errors 'Missing rendered lecture media check: .\scripts\quality\check-lecture-rendered-media.ps1'
}
if (-not (Test-Path -LiteralPath '.\scripts\teaching\build-lecture-archive-manifest.ps1' -PathType Leaf)) {
    Add-CheckError $errors 'Missing lecture archive manifest builder: .\scripts\teaching\build-lecture-archive-manifest.ps1'
}
if (-not (Test-Path -LiteralPath '.\scripts\teaching\render-lecture-publish-fixture.ps1' -PathType Leaf)) {
    Add-CheckError $errors 'Missing lecture publish fixture renderer: .\scripts\teaching\render-lecture-publish-fixture.ps1'
}
if (-not (Test-Path -LiteralPath '.\scripts\teaching\run-lecture-publish-gate.ps1' -PathType Leaf)) {
    Add-CheckError $errors 'Missing lecture publish gate runner: .\scripts\teaching\run-lecture-publish-gate.ps1'
}

if ($errors.Count -eq 0) {
    $schema = Get-Content -LiteralPath $SchemaPath -Raw | ConvertFrom-Json
    $fixture = Get-Content -LiteralPath $FixturePath -Raw | ConvertFrom-Json
    $document = Get-Content -LiteralPath $DocumentPath -Raw
    $persona = Get-Content -LiteralPath $PersonaPath -Raw | ConvertFrom-Json
    $archivePolicy = Get-Content -LiteralPath $ArchivePolicyPath -Raw | ConvertFrom-Json
    $accessibilityPolicy = Get-Content -LiteralPath $AccessibilityPolicyPath -Raw | ConvertFrom-Json
    $qualityRubric = Get-Content -LiteralPath $QualityRubricPath -Raw | ConvertFrom-Json
    $selectionRules = Get-Content -LiteralPath $SelectionRulesPath -Raw | ConvertFrom-Json
    $operatorReviewWorkflow = Get-Content -LiteralPath $OperatorReviewWorkflowPath -Raw | ConvertFrom-Json
    $productionProviders = Get-Content -LiteralPath $ProductionProvidersPath -Raw | ConvertFrom-Json
    $renderedMedia = Get-Content -LiteralPath $RenderedMediaPath -Raw | ConvertFrom-Json
    $neuralTtsRenderedMedia = Get-Content -LiteralPath $NeuralTtsRenderedMediaPath -Raw | ConvertFrom-Json
    $avatarRenderedMedia = Get-Content -LiteralPath $AvatarRenderedMediaPath -Raw | ConvertFrom-Json
    $renderComparison = Get-Content -LiteralPath $RenderComparisonPath -Raw | ConvertFrom-Json
    $publishRendererScript = Get-Content -LiteralPath '.\scripts\teaching\render-lecture-publish-fixture.ps1' -Raw
    $fixturePathResolved = Resolve-LecturePath -Path $FixturePath
    $fixtureContentRoot = Get-LectureContentRoot -ManifestPath $fixturePathResolved
    $fixtureAssetRoot = [string]$fixture.subjectOwnedAssetRoot
    $subjectGitignorePath = Join-Path $fixtureContentRoot '.gitignore'
    $gitignore = if (Test-Path -LiteralPath $subjectGitignorePath -PathType Leaf) {
        Get-Content -LiteralPath $subjectGitignorePath -Raw
    }
    else {
        ''
    }
    $planOutput = & .\scripts\teaching\build-lecture-plan.ps1 -ObjectiveId 'game-development:objectives/course/gdev-101/design-vocabulary' 2>&1
    if ($LASTEXITCODE -ne 0) {
        Add-CheckError $errors "Lecture plan generator failed: $planOutput"
    }
    else {
        $lecturePlan = ($planOutput | Out-String) | ConvertFrom-Json
        if ($lecturePlan.objectiveId -ne 'game-development:objectives/course/gdev-101/design-vocabulary') {
            Add-CheckError $errors 'Lecture plan generator returned the wrong objectiveId.'
        }
        if ($lecturePlan.contentSource.sourcePath -ne 'study-plans\courses\GDEV-101-game-design-foundations.md') {
            Add-CheckError $errors 'Lecture plan generator did not select the GDEV-101 source file.'
        }
        if (@($lecturePlan.citations).Count -lt 1) {
            Add-CheckError $errors 'Lecture plan generator must include at least one citation.'
        }
        if (-not ([string]$lecturePlan.script.text).Contains('[source-1]')) {
            Add-CheckError $errors 'Lecture plan script must include a deterministic citation marker.'
        }
        if (@($lecturePlan.storyboard).Count -lt 4) {
            Add-CheckError $errors 'Lecture plan storyboard must include at least four scenes.'
        }
        if (@($lecturePlan.storyboard | Where-Object { Test-HasText $_.activeRecallPrompt }).Count -lt 3) {
            Add-CheckError $errors 'Lecture plan storyboard must include active recall prompts.'
        }
        if ($lecturePlan.licenseBoundaries.originalScriptRequired -ne $true) {
            Add-CheckError $errors 'Lecture plan must require original scripts.'
        }
        foreach ($qaExpectation in @('source-grounding', 'license-safety', 'accessibility', 'active-recall', 'assessment-handoff')) {
            if (@($lecturePlan.qaExpectations | Where-Object { $_ -eq $qaExpectation }).Count -ne 1) {
                Add-CheckError $errors "Lecture plan missing QA expectation: $qaExpectation"
            }
        }
    }
    $licenseGateOutput = & .\scripts\quality\check-lecture-license-gate.ps1 -ManifestPath $FixturePath -SelfTest 2>&1
    if ($LASTEXITCODE -ne 0) {
        Add-CheckError $errors "Lecture license gate failed: $licenseGateOutput"
    }
    else {
        $licenseGate = ($licenseGateOutput | Out-String) | ConvertFrom-Json
        if ($licenseGate.errorCount -ne 0) {
            Add-CheckError $errors 'Lecture license gate reported errors.'
        }
        if ($licenseGate.blockedCaseCount -ne 4) {
            Add-CheckError $errors 'Lecture license gate must block copied transcripts, unlicensed slides, unauthorized likenesses, and host-only required media.'
        }
    }
    $checkpointStateOutput = & .\scripts\state\apply-lecture-checkpoint.ps1 -StatePath '.\fixtures\learner-state.gdev-101.json' -CheckpointEvidencePath '.\fixtures\lecture-checkpoint-evidence.gdev-101.json' 2>&1
    if ($LASTEXITCODE -ne 0) {
        Add-CheckError $errors "Lecture checkpoint state bridge failed: $checkpointStateOutput"
    }
    else {
        $checkpointState = ($checkpointStateOutput | Out-String) | ConvertFrom-Json
        $checkpointMastery = @($checkpointState.mastery | Where-Object { $_.objectiveId -eq 'game-development:objectives/course/gdev-101/design-vocabulary' } | Select-Object -First 1)
        if ($checkpointMastery.Count -ne 1) {
            Add-CheckError $errors 'Lecture checkpoint state bridge must preserve the target mastery record.'
        }
        else {
            if ([double]$checkpointMastery[0].confidence -ne 0.0) {
                Add-CheckError $errors 'Lecture checkpoint evidence must not increase mastery confidence.'
            }
            if ([int]$checkpointMastery[0].evidenceCount -ne 0) {
                Add-CheckError $errors 'Lecture checkpoint evidence must not increment mastery evidenceCount.'
            }
            if (@($checkpointMastery[0].evidenceSources | Where-Object { $_ -eq 'lecture-checkpoint' }).Count -ne 0) {
                Add-CheckError $errors 'Lecture checkpoint evidence must not become a direct mastery evidence source.'
            }
        }
        if (@($checkpointState.learningEvents | Where-Object { $_.verb -eq 'lecture_checkpoint_submitted' -and $_.result.masteryImpact -eq 'proposal-only' }).Count -ne 1) {
            Add-CheckError $errors 'Lecture checkpoint state bridge must append a proposal-only learning event.'
        }
        if (@($checkpointState.auditLog | Where-Object { $_.evidenceSource -eq 'lecture-checkpoint' -and $_.oldConfidence -eq $_.newConfidence }).Count -ne 1) {
            Add-CheckError $errors 'Lecture checkpoint state bridge must audit the checkpoint without changing confidence.'
        }
    }
    $selectionOutput = & .\scripts\teaching\select-lecture-mode.ps1 -StatePath '.\fixtures\learner-state.gdev-101.json' -LecturePath $FixturePath -RulesPath $SelectionRulesPath -SelfTest 2>&1
    if ($LASTEXITCODE -ne 0) {
        Add-CheckError $errors "Adaptive lecture mode selector failed: $selectionOutput"
    }
    else {
        $selectionResult = ($selectionOutput | Out-String) | ConvertFrom-Json
        if ($selectionResult.recommendation.mode -ne 'full-lecture') {
            Add-CheckError $errors 'Adaptive lecture mode selector should choose full lecture for the no-evidence fixture.'
        }
        if ($selectionResult.passedCaseCount -ne 4) {
            Add-CheckError $errors 'Adaptive lecture mode selector must pass full lecture, short segment, transcript, and remediation clip self-tests.'
        }
    }
    $operatorReviewOutput = & .\scripts\quality\check-lecture-operator-review.ps1 -ManifestPath $FixturePath -WorkflowPath $OperatorReviewWorkflowPath -SelfTest 2>&1
    if ($LASTEXITCODE -ne 0) {
        Add-CheckError $errors "Lecture operator review gate failed: $operatorReviewOutput"
    }
    else {
        $operatorReviewResult = ($operatorReviewOutput | Out-String) | ConvertFrom-Json
        if ($operatorReviewResult.errorCount -ne 0) {
            Add-CheckError $errors 'Lecture operator review gate reported errors.'
        }
        if ($operatorReviewResult.publishReady -ne $false) {
            Add-CheckError $errors 'Deterministic lecture fixture should remain not publish-ready until media is rendered and final approval is complete.'
        }
        if ($operatorReviewResult.blockedCaseCount -ne 6) {
            Add-CheckError $errors 'Lecture operator review gate must block missing stage approval, automated approval, planned required media, missing final approval, missing realism evidence, and missing generated instructor disclosure.'
        }
    }
    $productionProviderOutput = & .\scripts\quality\check-lecture-production-providers.ps1 -ProviderPath $ProductionProvidersPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        Add-CheckError $errors "Lecture production provider check failed: $productionProviderOutput"
    }
    else {
        $productionProviderResult = ($productionProviderOutput | Out-String) | ConvertFrom-Json
        if ($productionProviderResult.errorCount -ne 0) {
            Add-CheckError $errors 'Lecture production provider check reported errors.'
        }
    }
    $productionJobOutput = & .\scripts\teaching\build-lecture-production-job.ps1 -ManifestPath $FixturePath -ProviderPath $ProductionProvidersPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        Add-CheckError $errors "Lecture production job builder failed: $productionJobOutput"
    }
    else {
        $productionJob = ($productionJobOutput | Out-String) | ConvertFrom-Json
        if ($productionJob.schemaVersion -ne 1) {
            Add-CheckError $errors 'Lecture production job must use schemaVersion 1.'
        }
        if ($productionJob.dryRun -ne $true) {
            Add-CheckError $errors 'Lecture production job builder must be deterministic dry-run only at this stage.'
        }
        if ($productionJob.packageId -ne $fixture.packageId) {
            Add-CheckError $errors 'Lecture production job packageId must match the lecture fixture.'
        }
        if ([string]$productionJob.archiveRoot -ne $fixtureAssetRoot -or -not ([string]$productionJob.archiveRoot).StartsWith('generated-lectures\')) {
            Add-CheckError $errors 'Lecture production job archiveRoot must use the subject repo generated-lectures asset root.'
        }
        foreach ($stage in @('tts', 'visuals', 'avatar', 'motion', 'lipsync', 'assembly', 'archive', 'qa')) {
            if (@($productionJob.stages | Where-Object { $_.stage -eq $stage }).Count -ne 1) {
                Add-CheckError $errors "Lecture production job missing stage: $stage"
            }
        }
        foreach ($stage in @($productionJob.stages | Where-Object { $_.stage -in @('tts', 'visuals', 'avatar', 'motion', 'lipsync', 'assembly') })) {
            if (-not ([string]$stage.output.path).StartsWith($fixtureAssetRoot)) {
                Add-CheckError $errors "Lecture production job stage output is outside the subject-owned lecture archive: $($stage.stage)"
            }
            if ($stage.output.checksumAlgorithm -ne 'sha256') {
                Add-CheckError $errors "Lecture production job stage must require sha256: $($stage.stage)"
            }
        }
        $productionStageRequirements = @{
            tts = @('performancePlan.audioProfile', 'performancePlan.pausePrompts')
            visuals = @('performancePlan.visualSync', 'performancePlan.pausePrompts')
            avatar = @('performancePlan.visualSync', 'generatedInstructor.realismProfile')
            motion = @('performancePlan.visualSync', 'generatedInstructor.realismProfile', 'lecture-avatar-rendered-media.json', 'rendered-audio-timing-reference')
            lipsync = @('performancePlan.audioProfile', 'performancePlan.pausePrompts', 'generatedInstructor.realismProfile', 'lecture-avatar-rendered-media.json', 'rendered-audio-final')
            assembly = @('performancePlan.audioProfile', 'performancePlan.pausePrompts', 'performancePlan.visualSync')
        }
        foreach ($stageName in $productionStageRequirements.Keys) {
            $jobStage = @($productionJob.stages | Where-Object { $_.stage -eq $stageName })
            if ($jobStage.Count -eq 1) {
                foreach ($inputRef in $productionStageRequirements[$stageName]) {
                    if (@($jobStage[0].inputRefs | Where-Object { $_ -eq $inputRef }).Count -ne 1) {
                        Add-CheckError $errors "Lecture production job stage must include performance input $inputRef`: $stageName"
                    }
                }
            }
        }
        $motionJobStage = @($productionJob.stages | Where-Object { $_.stage -eq 'motion' })
        if ($motionJobStage.Count -ne 1) {
            Add-CheckError $errors 'Lecture production job must include a local instructor motion spike stage.'
        }
        else {
            if ($motionJobStage[0].providerId -ne 'local-comfyui-motion') {
                Add-CheckError $errors 'Lecture motion stage must use local-comfyui-motion.'
            }
            if ($motionJobStage[0].output.assetId -ne 'lecture-instructor-motion-preview' -or $motionJobStage[0].output.requiredForPublish -ne $false) {
                Add-CheckError $errors 'Lecture motion stage must output a non-publish-blocking instructor motion preview.'
            }
        }
        $lipSyncJobStage = @($productionJob.stages | Where-Object { $_.stage -eq 'lipsync' })
        if ($lipSyncJobStage.Count -ne 1) {
            Add-CheckError $errors 'Lecture production job must include a local instructor lip-sync spike stage.'
        }
        else {
            if ($lipSyncJobStage[0].providerId -ne 'local-comfyui-lipsync') {
                Add-CheckError $errors 'Lecture lip-sync stage must use local-comfyui-lipsync.'
            }
            if ($lipSyncJobStage[0].output.assetId -ne 'lecture-instructor-lipsync-preview' -or $lipSyncJobStage[0].output.requiredForPublish -ne $false) {
                Add-CheckError $errors 'Lecture lip-sync stage must output a non-publish-blocking instructor lip-sync preview.'
            }
        }
        if (@($productionJob.publishGates | Where-Object { $_ -eq 'operator-review' }).Count -ne 1) {
            Add-CheckError $errors 'Lecture production job must keep operator review as a publish gate.'
        }
        if ($productionJob.requiresRealRenderBeforePublish -ne $true) {
            Add-CheckError $errors 'Lecture production job must block publish until a real render exists.'
        }
    }
    $comfyAdapterOutput = & .\scripts\teaching\invoke-comfyui-production-adapter.ps1 -ManifestPath $FixturePath -ProviderPath $ProductionProvidersPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        Add-CheckError $errors "Local ComfyUI production adapter failed: $comfyAdapterOutput"
    }
    else {
        $comfyAdapter = ($comfyAdapterOutput | Out-String) | ConvertFrom-Json
        if ($comfyAdapter.adapterId -ne 'local-comfyui-adapter-v1') {
            Add-CheckError $errors 'Local ComfyUI production adapter returned the wrong adapterId.'
        }
        if ($comfyAdapter.mode -ne 'dry-run') {
            Add-CheckError $errors 'Local ComfyUI production adapter must run dry-run during verification.'
        }
        if ($comfyAdapter.wroteHandoff -ne $false) {
            Add-CheckError $errors 'Local ComfyUI production adapter must not write handoff files during verification.'
        }
        foreach ($stage in @('visuals', 'avatar', 'assembly')) {
            $binding = @($comfyAdapter.workflowBindings | Where-Object { $_.stage -eq $stage })
            if ($binding.Count -ne 1) {
                Add-CheckError $errors "Local ComfyUI adapter missing workflow binding: $stage"
            }
            elseif ($binding[0].workflowExists -ne $true) {
                Add-CheckError $errors "Local ComfyUI adapter workflow does not exist: $stage"
            }
        }
        $motionBinding = @($comfyAdapter.workflowBindings | Where-Object { $_.stage -eq 'motion' -and $_.providerId -eq 'local-comfyui-motion' })
        if ($motionBinding.Count -ne 1) {
            Add-CheckError $errors 'Local ComfyUI adapter must expose a motion adapter spike binding.'
        }
        else {
            if ($motionBinding[0].adapterId -ne 'local-comfyui-motion-adapter-spike-v1' -or $motionBinding[0].workflowExists -ne $true) {
                Add-CheckError $errors 'Local ComfyUI motion binding must point at the motion adapter spike script.'
            }
            if ($motionBinding[0].preLipSyncMotionOnly -ne $true -or $motionBinding[0].lipSyncIncluded -ne $false) {
                Add-CheckError $errors 'Local ComfyUI motion binding must be pre-lip-sync motion only.'
            }
        }
        $lipSyncBinding = @($comfyAdapter.workflowBindings | Where-Object { $_.stage -eq 'lipsync' -and $_.providerId -eq 'local-comfyui-lipsync' })
        if ($lipSyncBinding.Count -ne 1) {
            Add-CheckError $errors 'Local ComfyUI adapter must expose a lip-sync adapter spike binding.'
        }
        else {
            if ($lipSyncBinding[0].adapterId -ne 'local-comfyui-lipsync-adapter-spike-v1' -or $lipSyncBinding[0].workflowExists -ne $true) {
                Add-CheckError $errors 'Local ComfyUI lip-sync binding must point at the lip-sync adapter spike script.'
            }
            if ($lipSyncBinding[0].audioDrivenMouthMovement -ne $true -or $lipSyncBinding[0].realRenderIncluded -ne $false) {
                Add-CheckError $errors 'Local ComfyUI lip-sync binding must be an audio-driven non-rendered spike.'
            }
        }
        foreach ($spikeStage in @('motion', 'lipsync')) {
            if (@($comfyAdapter.spikeStages | Where-Object { $_ -eq $spikeStage }).Count -ne 1) {
                Add-CheckError $errors "Local ComfyUI adapter must mark $spikeStage as a spike stage."
            }
        }
        if ($comfyAdapter.motionAdapter.adapterId -ne 'local-comfyui-motion-adapter-spike-v1') {
            Add-CheckError $errors 'Local ComfyUI adapter must include the motion adapter spike metadata.'
        }
        if ($comfyAdapter.motionAdapter.selectedPipelineId -ne 'liveportrait' -or $comfyAdapter.motionAdapter.fallbackPipelineId -ne 'sadtalker') {
            Add-CheckError $errors 'Local ComfyUI motion adapter must prefer LivePortrait and keep SadTalker as fallback.'
        }
        if ($comfyAdapter.motionAdapter.sourceAvatar.sha256 -ne $avatarRenderedMedia.sha256 -or $comfyAdapter.motionAdapter.sourceAudio.sha256 -ne $renderedMedia.sha256) {
            Add-CheckError $errors 'Local ComfyUI motion adapter must cite the rendered avatar and audio timing source checksums.'
        }
        if ($comfyAdapter.motionAdapter.output.requiredForPublish -ne $false -or -not ([string]$comfyAdapter.motionAdapter.output.path).StartsWith($fixtureAssetRoot)) {
            Add-CheckError $errors 'Local ComfyUI motion adapter output must be a non-required subject-owned preview asset.'
        }
        if (@($comfyAdapter.motionAdapter.motionPlan).Count -lt @($fixture.performancePlan.visualSync.boardStates).Count) {
            Add-CheckError $errors 'Local ComfyUI motion adapter must create a motion plan for every board state.'
        }
        $motionSafeguards = (@($comfyAdapter.motionAdapter.safeguards) -join ' ').ToLowerInvariant()
        foreach ($token in @('pre-lip-sync', 'board readability', 'occlusion')) {
            if (-not $motionSafeguards.Contains($token)) {
                Add-CheckError $errors "Local ComfyUI motion adapter safeguards missing: $token"
            }
        }
        Test-DeterministicStageMetadata -Errors $errors -Metadata $comfyAdapter.motionAdapter.deterministicMetadata -Stage 'motion' -ProviderId 'local-comfyui-motion' -SelectedPipelineId 'liveportrait' -ExpectedSourceFrameSha256 $avatarRenderedMedia.sha256 -ExpectedSourceAudioSha256 $renderedMedia.sha256 -ArchiveRoot $fixtureAssetRoot
        if ($comfyAdapter.lipSyncAdapter.adapterId -ne 'local-comfyui-lipsync-adapter-spike-v1') {
            Add-CheckError $errors 'Local ComfyUI adapter must include the lip-sync adapter spike metadata.'
        }
        if ($comfyAdapter.lipSyncAdapter.selectedPipelineId -ne 'musetalk' -or $comfyAdapter.lipSyncAdapter.fallbackPipelineId -ne 'wav2lip') {
            Add-CheckError $errors 'Local ComfyUI lip-sync adapter must prefer MuseTalk and keep Wav2Lip as fallback.'
        }
        if ($comfyAdapter.lipSyncAdapter.sourceAvatar.sha256 -ne $avatarRenderedMedia.sha256 -or $comfyAdapter.lipSyncAdapter.sourceAudio.sha256 -ne $renderedMedia.sha256) {
            Add-CheckError $errors 'Local ComfyUI lip-sync adapter must cite the rendered avatar and final audio checksums.'
        }
        if ($comfyAdapter.lipSyncAdapter.output.requiredForPublish -ne $false -or -not ([string]$comfyAdapter.lipSyncAdapter.output.path).StartsWith($fixtureAssetRoot)) {
            Add-CheckError $errors 'Local ComfyUI lip-sync adapter output must be a non-required subject-owned preview asset.'
        }
        if (@($comfyAdapter.lipSyncAdapter.syncPlan).Count -lt 2) {
            Add-CheckError $errors 'Local ComfyUI lip-sync adapter must create a sync plan for speech and active-recall pauses.'
        }
        $lipSyncSafeguards = (@($comfyAdapter.lipSyncAdapter.safeguards) -join ' ').ToLowerInvariant()
        foreach ($token in @('audio-driven', 'pause silence', 'face identity')) {
            if (-not $lipSyncSafeguards.Contains($token)) {
                Add-CheckError $errors "Local ComfyUI lip-sync adapter safeguards missing: $token"
            }
        }
        Test-DeterministicStageMetadata -Errors $errors -Metadata $comfyAdapter.lipSyncAdapter.deterministicMetadata -Stage 'lip-sync' -ProviderId 'local-comfyui-lipsync' -SelectedPipelineId 'musetalk' -ExpectedSourceFrameSha256 $avatarRenderedMedia.sha256 -ExpectedSourceAudioSha256 $renderedMedia.sha256 -ArchiveRoot $fixtureAssetRoot
        $ttsCandidateBinding = @($comfyAdapter.workflowBindings | Where-Object { $_.stage -eq 'tts' -and $_.providerId -eq 'local-comfyui-tts' })
        if ($ttsCandidateBinding.Count -ne 1) {
            Add-CheckError $errors 'Local ComfyUI adapter must expose a local-comfyui-tts workflow binding.'
        }
        elseif ($ttsCandidateBinding[0].workflowExists -ne $true -or $ttsCandidateBinding[0].routingRole -ne 'preferred') {
            Add-CheckError $errors 'Local ComfyUI TTS binding must be an existing preferred workflow after operator listening review passes.'
        }
        if (@($comfyAdapter.acceptedStages | Where-Object { $_ -eq 'tts' }).Count -ne 1) {
            Add-CheckError $errors 'Local ComfyUI adapter must mark TTS as an accepted stage after promotion.'
        }
        if (@($comfyAdapter.candidateStages | Where-Object { $_ -eq 'tts' }).Count -ne 0) {
            Add-CheckError $errors 'Local ComfyUI adapter must no longer mark TTS as a candidate stage after promotion.'
        }
        foreach ($unsupportedStage in @('archive', 'qa')) {
            if (@($comfyAdapter.unsupportedStages | Where-Object { $_ -eq $unsupportedStage }).Count -ne 1) {
                Add-CheckError $errors "Local ComfyUI adapter must explicitly leave stage to another provider/gate: $unsupportedStage"
            }
        }
    }
    $comfyTtsReadinessOutput = & .\scripts\quality\check-comfyui-tts-readiness.ps1 -ProviderPath $ProductionProvidersPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        Add-CheckError $errors "Local ComfyUI TTS readiness gate failed: $comfyTtsReadinessOutput"
    }
    else {
        $comfyTtsReadiness = ($comfyTtsReadinessOutput | Out-String) | ConvertFrom-Json
        if ($comfyTtsReadiness.schemaVersion -ne 1 -or $comfyTtsReadiness.providerId -ne 'local-comfyui-tts') {
            Add-CheckError $errors 'Local ComfyUI TTS readiness gate returned the wrong provider metadata.'
        }
        if ($comfyTtsReadiness.approvedWorkflowMode -ne 'generic-voice-design-non-clone') {
            Add-CheckError $errors 'Local ComfyUI TTS readiness must use the approved generic non-clone workflow mode.'
        }
        foreach ($requiredClass in @('FB_Qwen3TTSVoiceDesign', 'SaveAudio')) {
            if (@($comfyTtsReadiness.requiredNodeClasses | Where-Object { $_ -eq $requiredClass }).Count -ne 1) {
                Add-CheckError $errors "Local ComfyUI TTS readiness missing required node class: $requiredClass"
            }
            if (@($comfyTtsReadiness.workflowNodeClasses | Where-Object { $_ -eq $requiredClass }).Count -ne 1) {
                Add-CheckError $errors "Local ComfyUI TTS workflow missing required node class: $requiredClass"
            }
        }
        foreach ($disallowedClass in @('FB_Qwen3TTSVoiceClone', 'FB_Qwen3TTSVoiceClonePrompt', 'FB_Qwen3TTSCustomVoice')) {
            if (@($comfyTtsReadiness.workflowNodeClasses | Where-Object { $_ -eq $disallowedClass }).Count -gt 0) {
                Add-CheckError $errors "Local ComfyUI TTS workflow must not use disallowed node class: $disallowedClass"
            }
        }
    }
    $cloudAdapterOutput = & .\scripts\teaching\invoke-cloud-production-adapter.ps1 -ProviderPath $ProductionProvidersPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        Add-CheckError $errors "Cloud production adapter contract check failed: $cloudAdapterOutput"
    }
    else {
        $cloudAdapter = ($cloudAdapterOutput | Out-String) | ConvertFrom-Json
        if ($cloudAdapter.adapterId -ne 'cloud-production-adapter-contracts-v1') {
            Add-CheckError $errors 'Cloud production adapter returned the wrong adapterId.'
        }
        if ($cloudAdapter.mode -ne 'contract-check') {
            Add-CheckError $errors 'Cloud production adapter must use contract-check mode during verification.'
        }
        if (-not ([string]$cloudAdapter.secretPolicy).Contains('never printed')) {
            Add-CheckError $errors 'Cloud production adapter must document redacted secret handling.'
        }
        if (@($cloudAdapter.supportedRenderModes | Where-Object { $_ -eq 'neural-tts-openai-compatible-binary' }).Count -ne 1) {
            Add-CheckError $errors 'Cloud production adapter must expose the neural TTS render mode.'
        }
        foreach ($stage in @('tts', 'avatar', 'assembly')) {
            $contract = @($cloudAdapter.contracts | Where-Object { $_.stage -eq $stage })
            if ($contract.Count -ne 1) {
                Add-CheckError $errors "Cloud production adapter missing contract stage: $stage"
                continue
            }
            if ($contract[0].outputPolicy -ne 'download-to-local-archive-and-checksum') {
                Add-CheckError $errors "Cloud production adapter must require local archive download and checksum: $stage"
            }
            foreach ($envVar in @($contract[0].credentialEnvVars)) {
                if ($envVar.value -ne '<redacted>') {
                    Add-CheckError $errors "Cloud production adapter leaked an environment value for: $($envVar.name)"
                }
            }
            if ($stage -eq 'tts') {
                if (@($contract[0].capabilities | Where-Object { $_ -eq 'neural-tts' }).Count -ne 1) {
                    Add-CheckError $errors 'Cloud TTS adapter contract must expose neural-tts capability.'
                }
                foreach ($requiredTtsEnvVar in @('LECTURE_TTS_ENDPOINT', 'LECTURE_TTS_MODEL', 'LECTURE_TTS_VOICE')) {
                    if (@($contract[0].credentialEnvVars | Where-Object { $_.name -eq $requiredTtsEnvVar -and $_.value -eq '<redacted>' }).Count -ne 1) {
                        Add-CheckError $errors "Cloud TTS adapter contract missing redacted env var: $requiredTtsEnvVar"
                    }
                }
                if (-not ([string]$contract[0].publishRequirement).Contains('downloaded to the subject content repo')) {
                    Add-CheckError $errors 'Cloud TTS adapter contract must archive neural audio in the subject content repo.'
                }
            }
        }
    }
    $renderedMediaOutput = & .\scripts\quality\check-lecture-rendered-media.ps1 -RenderedMediaPath $RenderedMediaPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        Add-CheckError $errors "Rendered lecture media check failed: $renderedMediaOutput"
    }
    else {
        $renderedMediaResult = ($renderedMediaOutput | Out-String) | ConvertFrom-Json
        if ($renderedMediaResult.errorCount -ne 0) {
            Add-CheckError $errors 'Rendered lecture media check reported errors.'
        }
    }
    if ($neuralTtsRenderedMedia.schemaVersion -ne 1) {
        Add-CheckError $errors 'Neural TTS rendered media metadata schemaVersion must be 1.'
    }
    if ($neuralTtsRenderedMedia.packageId -ne $fixture.packageId) {
        Add-CheckError $errors 'Neural TTS rendered media metadata packageId must match the lecture fixture.'
    }
    if ($neuralTtsRenderedMedia.assetId -ne 'lecture-audio-neural-tts') {
        Add-CheckError $errors 'Neural TTS rendered media metadata must declare the neural TTS audio asset.'
    }
    if ($neuralTtsRenderedMedia.type -ne 'audio/mpeg') {
        Add-CheckError $errors 'Neural TTS rendered media must be audio/mpeg.'
    }
    if ($neuralTtsRenderedMedia.providerId -ne 'cloud-tts' -or $neuralTtsRenderedMedia.renderEngine -ne 'neural-tts-openai-compatible-binary') {
        Add-CheckError $errors 'Neural TTS rendered media must come from the cloud-tts neural speech adapter.'
    }
    foreach ($field in @('providerName', 'model', 'voice')) {
        if (-not (Test-HasText (Get-PropertyValue -InputObject $neuralTtsRenderedMedia -Name $field))) {
            Add-CheckError $errors "Neural TTS rendered media missing $field."
        }
    }
    if ($neuralTtsRenderedMedia.status -ne 'archived' -or $neuralTtsRenderedMedia.requiredForPublish -ne $false) {
        Add-CheckError $errors 'Neural TTS rendered media must be archived as an operator-review candidate, not final publish media.'
    }
    if ([string]$neuralTtsRenderedMedia.sha256 -notmatch '^[a-f0-9]{64}$') {
        Add-CheckError $errors 'Neural TTS rendered media must record a lowercase SHA-256 checksum.'
    }
    if (-not ([string]$neuralTtsRenderedMedia.path).StartsWith($fixtureAssetRoot)) {
        Add-CheckError $errors 'Neural TTS rendered media must live under the subject-owned lecture folder.'
    }
    $resolvedNeuralTtsPath = Resolve-LectureContentPath -ContentRoot $fixtureContentRoot -Path ([string]$neuralTtsRenderedMedia.path)
    if (-not (Test-Path -LiteralPath $resolvedNeuralTtsPath -PathType Leaf)) {
        Add-CheckError $errors "Neural TTS rendered audio file does not exist: $($neuralTtsRenderedMedia.path)"
    }
    else {
        if ((Get-Item -LiteralPath $resolvedNeuralTtsPath).Length -lt 10000) {
            Add-CheckError $errors 'Neural TTS rendered audio is too small to be useful.'
        }
        if ((Get-Sha256File -Path $resolvedNeuralTtsPath) -ne $neuralTtsRenderedMedia.sha256) {
            Add-CheckError $errors 'Neural TTS rendered audio SHA-256 does not match metadata.'
        }
    }
    if ($avatarRenderedMedia.schemaVersion -ne 1) {
        Add-CheckError $errors 'Rendered lecture avatar metadata schemaVersion must be 1.'
    }
    if ($avatarRenderedMedia.packageId -ne $fixture.packageId) {
        Add-CheckError $errors 'Rendered lecture avatar metadata packageId must match the lecture fixture.'
    }
    if ($avatarRenderedMedia.assetId -ne 'lecture-avatar-comfyui-png') {
        Add-CheckError $errors 'Rendered lecture avatar metadata must declare the ComfyUI avatar PNG asset.'
    }
    if ($avatarRenderedMedia.type -ne 'image/png') {
        Add-CheckError $errors 'Rendered lecture avatar must be image/png.'
    }
    if ($avatarRenderedMedia.renderEngine -ne 'local-comfyui' -or $avatarRenderedMedia.providerId -ne 'local-comfyui') {
        Add-CheckError $errors 'Rendered lecture avatar must come from the local ComfyUI provider.'
    }
    $fixtureInstructorGenderForAvatar = ([string](Get-PropertyValue -InputObject $fixture.generatedInstructor -Name 'gender')).ToLowerInvariant()
    if (-not (Test-HasText $fixtureInstructorGenderForAvatar)) {
        Add-CheckError $errors 'Generated instructor must declare a gender before avatar rendering.'
    }
    elseif ([string](Get-PropertyValue -InputObject $avatarRenderedMedia -Name 'instructorGender') -ne $fixtureInstructorGenderForAvatar) {
        Add-CheckError $errors 'Rendered lecture avatar gender metadata must match the generated instructor.'
    }
    if (-not (Test-HasText (Get-PropertyValue -InputObject $avatarRenderedMedia -Name 'visualGenderCue'))) {
        Add-CheckError $errors 'Rendered lecture avatar must record the visual gender cue used in the ComfyUI prompt.'
    }
    if (-not ([string]$avatarRenderedMedia.path).StartsWith($fixtureAssetRoot)) {
        Add-CheckError $errors 'Rendered lecture avatar must live under the subject-owned lecture folder.'
    }
    if ([string]$avatarRenderedMedia.sha256 -notmatch '^[a-f0-9]{64}$') {
        Add-CheckError $errors 'Rendered lecture avatar must record a lowercase SHA-256 checksum.'
    }
    $resolvedAvatarPath = Resolve-LectureContentPath -ContentRoot $fixtureContentRoot -Path ([string]$avatarRenderedMedia.path)
    if (-not (Test-Path -LiteralPath $resolvedAvatarPath -PathType Leaf)) {
        Add-CheckError $errors "Rendered lecture avatar file does not exist: $($avatarRenderedMedia.path)"
    }
    else {
        if ((Get-Item -LiteralPath $resolvedAvatarPath).Length -lt 100000) {
            Add-CheckError $errors 'Rendered lecture avatar image is too small to be a useful local ComfyUI render.'
        }
        if ((Get-Sha256File -Path $resolvedAvatarPath) -ne $avatarRenderedMedia.sha256) {
            Add-CheckError $errors 'Rendered lecture avatar SHA-256 does not match metadata.'
        }
    }
    if (-not $publishRendererScript.Contains('render-lecture-avatar-comfyui.ps1') -or -not $publishRendererScript.Contains('local-comfyui+ffmpeg')) {
        Add-CheckError $errors 'Lecture publish renderer must assemble video from the local ComfyUI avatar render.'
    }
    foreach ($rendererMarker in @('performancePlan.visualSync', 'performancePlan.pausePrompts', 'lecture-board-writing.ass', 'board-local-writing-layer', 'globalOverlayTextUsed', 'subtitles=filename', 'stroke-based-progressive-chalk-ass', 'progressive-left-to-right-clipped-strokes', 'frameQaEvidence', 'New-LectureQaFrameEvidence', 'lecture-comfyui-tts-rendered-media-full.json', 'frontRowFocusCropFilter', 'cleanBoardFilter', 'front-row straight-on learner view')) {
        if (-not $publishRendererScript.Contains($rendererMarker)) {
            Add-CheckError $errors "Lecture publish renderer missing board-local writing marker: $rendererMarker"
        }
    }
    if ($publishRendererScript.Contains('burned-in-board-state-and-pause-overlays') -or $publishRendererScript.Contains('lecture-board-sync.ass')) {
        Add-CheckError $errors 'Lecture publish renderer must not use the old whole-video board-sync overlay mode.'
    }
    if ($publishRendererScript.Contains('Generated instructor') -or $publishRendererScript.Contains('drawbox=x=992')) {
        Add-CheckError $errors 'Lecture publish renderer still contains the deterministic ffmpeg instructor block.'
    }
    $archiveManifestOutput = & .\scripts\teaching\build-lecture-archive-manifest.ps1 -ManifestPath $FixturePath -RenderedMediaPath $RenderedMediaPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        Add-CheckError $errors "Lecture archive manifest builder failed: $archiveManifestOutput"
    }
    else {
        $archiveManifest = ($archiveManifestOutput | Out-String) | ConvertFrom-Json
        if ($archiveManifest.schemaVersion -ne 1) {
            Add-CheckError $errors 'Lecture archive manifest must use schemaVersion 1.'
        }
        if ($archiveManifest.dryRun -ne $true) {
            Add-CheckError $errors 'Lecture archive manifest builder must default to dry-run output.'
        }
        if ($archiveManifest.packageId -ne $fixture.packageId) {
            Add-CheckError $errors 'Lecture archive manifest packageId must match the lecture fixture.'
        }
        if ([string]$archiveManifest.archiveRoot -ne $fixtureAssetRoot -or -not ([string]$archiveManifest.archiveRoot).StartsWith('generated-lectures\')) {
            Add-CheckError $errors 'Lecture archive manifest archiveRoot must use the subject repo generated-lectures asset root.'
        }
        $archivedAudio = @($archiveManifest.assets.media | Where-Object { $_.assetId -eq $renderedMedia.assetId })
        if ($archivedAudio.Count -ne 1) {
            Add-CheckError $errors 'Lecture archive manifest must include the rendered WAV audio fixture.'
        }
        else {
            if ($archivedAudio[0].kind -ne 'audio' -or $archivedAudio[0].archiveStatus -ne 'archived') {
                Add-CheckError $errors 'Lecture archive manifest must mark the rendered WAV as archived audio.'
            }
            if ($archivedAudio[0].manifestSha256 -ne $renderedMedia.sha256 -or $archivedAudio[0].actualSha256 -ne $renderedMedia.sha256) {
                Add-CheckError $errors 'Lecture archive manifest rendered WAV checksums must match rendered media metadata.'
            }
        }
        $archivedAvatar = @($archiveManifest.assets.media | Where-Object { $_.assetId -eq $avatarRenderedMedia.assetId })
        if ($archivedAvatar.Count -ne 1) {
            Add-CheckError $errors 'Lecture archive manifest must include the rendered ComfyUI avatar image.'
        }
        else {
            if ($archivedAvatar[0].kind -ne 'other' -or $archivedAvatar[0].archiveStatus -ne 'archived') {
                Add-CheckError $errors 'Lecture archive manifest must mark the ComfyUI avatar image as archived media.'
            }
            if ($archivedAvatar[0].manifestSha256 -ne $avatarRenderedMedia.sha256 -or $archivedAvatar[0].actualSha256 -ne $avatarRenderedMedia.sha256) {
                Add-CheckError $errors 'Lecture archive manifest ComfyUI avatar checksums must match rendered avatar metadata.'
            }
        }
        $plannedVideo = @($archiveManifest.assets.media | Where-Object { $_.assetId -eq 'lecture-video-mp4' })
        if ($plannedVideo.Count -ne 1) {
            Add-CheckError $errors 'Lecture archive manifest must include the planned MP4 video asset.'
        }
        else {
            if ($plannedVideo[0].kind -ne 'video' -or $plannedVideo[0].archiveStatus -ne 'planned' -or $plannedVideo[0].requiredForPublish -ne $true) {
                Add-CheckError $errors 'Lecture archive manifest must keep the required MP4 video as a planned publish blocker.'
            }
            if (@($plannedVideo[0].blockers).Count -lt 1) {
                Add-CheckError $errors 'Lecture archive manifest must record a blocker for the planned MP4 video.'
            }
        }
        $plannedAudio = @($archiveManifest.assets.media | Where-Object { $_.assetId -eq 'lecture-audio-m4a' })
        if ($plannedAudio.Count -ne 1) {
            Add-CheckError $errors 'Lecture archive manifest must include the planned M4A audio asset.'
        }
        else {
            if ($plannedAudio[0].kind -ne 'audio' -or $plannedAudio[0].archiveStatus -ne 'planned' -or $plannedAudio[0].requiredForPublish -ne $true) {
                Add-CheckError $errors 'Lecture archive manifest must keep the required M4A audio as a planned publish blocker.'
            }
            if (@($plannedAudio[0].blockers).Count -lt 1) {
                Add-CheckError $errors 'Lecture archive manifest must record a blocker for the planned M4A audio.'
            }
        }
        $captionsEntry = @($archiveManifest.assets.captions | Where-Object { $_.assetId -eq 'captions-webvtt-inline' })
        if ($captionsEntry.Count -ne 1) {
            Add-CheckError $errors 'Lecture archive manifest must include a captions checksum entry.'
        }
        else {
            if ($captionsEntry[0].type -ne 'text/vtt' -or $captionsEntry[0].sha256 -notmatch '^[a-f0-9]{64}$' -or $captionsEntry[0].length -lt 20) {
                Add-CheckError $errors 'Lecture archive manifest captions entry must include a WebVTT SHA-256 checksum.'
            }
        }
        $packageMetadataEntry = @($archiveManifest.assets.packageMetadata | Where-Object { $_.assetId -eq 'lecture-video-json' })
        if ($packageMetadataEntry.Count -ne 1) {
            Add-CheckError $errors 'Lecture archive manifest must include a package metadata checksum entry.'
        }
        else {
            if ($packageMetadataEntry[0].type -ne 'application/json' -or $packageMetadataEntry[0].sha256 -notmatch '^[a-f0-9]{64}$' -or $packageMetadataEntry[0].length -lt 100) {
                Add-CheckError $errors 'Lecture archive manifest package metadata entry must include a JSON SHA-256 checksum.'
            }
        }
        if ($archiveManifest.summary.archivedMediaAssetCount -lt 2) {
            Add-CheckError $errors 'Lecture archive manifest summary must count archived rendered audio and avatar media.'
        }
        if ($archiveManifest.summary.plannedRequiredMediaAssetCount -lt 2) {
            Add-CheckError $errors 'Lecture archive manifest summary must count planned required audio and video blockers.'
        }
        if ($archiveManifest.publishReady -ne $false) {
            Add-CheckError $errors 'Lecture archive manifest must not be publish-ready while required media remains planned.'
        }
        if ($archiveManifest.requiresOperatorPublishGate -ne $true) {
            Add-CheckError $errors 'Lecture archive manifest must require the operator publish gate.'
        }
        foreach ($assetId in @('lecture-video-mp4', 'lecture-audio-m4a')) {
            if (@($archiveManifest.publishBlockers | Where-Object { [string]$_ -like "*$assetId*" }).Count -lt 1) {
                Add-CheckError $errors "Lecture archive manifest missing publish blocker for: $assetId"
            }
        }
    }
    $publishRenderOk = $false
    $publishRenderOutput = & .\scripts\teaching\render-lecture-publish-fixture.ps1 -ManifestPath $FixturePath -RenderedMediaPath $RenderedMediaPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        Add-CheckError $errors "Lecture publish fixture renderer failed: $publishRenderOutput"
    }
    else {
        $publishRenderOk = $true
        $publishRender = ($publishRenderOutput | Out-String) | ConvertFrom-Json
        if ($publishRender.schemaVersion -ne 1) {
            Add-CheckError $errors 'Lecture publish fixture renderer must use schemaVersion 1.'
        }
        if ($publishRender.packageId -ne $fixture.packageId) {
            Add-CheckError $errors 'Lecture publish fixture packageId must match the lecture fixture.'
        }
        if ($publishRender.renderEngine -ne 'local-comfyui+ffmpeg') {
            Add-CheckError $errors 'Lecture publish fixture renderer must use the local ComfyUI avatar render and ffmpeg assembly.'
        }
        if ($publishRender.sourceAvatar.assetId -ne $avatarRenderedMedia.assetId -or $publishRender.sourceAvatar.sha256 -ne $avatarRenderedMedia.sha256) {
            Add-CheckError $errors 'Lecture publish fixture renderer must cite the rendered ComfyUI avatar source.'
        }
        if ([string]$publishRender.sourceAudio.providerId -ne 'local-comfyui-tts' -or [string]$publishRender.sourceAudio.renderEngine -notlike 'local-comfyui-*') {
            Add-CheckError $errors 'Lecture publish fixture renderer must prefer the reviewed local ComfyUI TTS audio instead of the robotic Windows SAPI fixture.'
        }
        if ([string]$publishRender.sourceAudio.assetId -notlike 'lecture-audio-comfyui-tts-*') {
            Add-CheckError $errors 'Lecture publish fixture source audio must be a full local ComfyUI TTS lecture render.'
        }
        $fixtureInstructorGenderForPublish = ([string](Get-PropertyValue -InputObject $fixture.generatedInstructor -Name 'gender')).ToLowerInvariant()
        $expectedVoiceGenderForPublish = Get-ExpectedInstructorVoiceGender -InstructorGender $fixtureInstructorGenderForPublish
        if ([string](Get-PropertyValue -InputObject $publishRender.sourceAudio -Name 'voiceMatchPolicy') -ne 'match-generated-instructor-gender') {
            Add-CheckError $errors 'Lecture publish fixture source audio must declare the gender-to-voice match policy.'
        }
        if ([string](Get-PropertyValue -InputObject $publishRender.sourceAudio -Name 'instructorGender') -ne $fixtureInstructorGenderForPublish) {
            Add-CheckError $errors 'Lecture publish fixture source audio instructorGender must match the generated instructor.'
        }
        if ([string](Get-PropertyValue -InputObject $publishRender.sourceAudio -Name 'voiceGender') -ne $expectedVoiceGenderForPublish) {
            Add-CheckError $errors 'Lecture publish fixture source audio voiceGender must match the generated instructor gender.'
        }
        $publishVoiceText = (@(
            (Get-PropertyValue -InputObject $publishRender.sourceAudio -Name 'voiceGender'),
            (Get-PropertyValue -InputObject $publishRender.sourceAudio -Name 'pitchRange'),
            (Get-PropertyValue -InputObject $publishRender.sourceAudio -Name 'timbre')
        ) -join ' ').ToLowerInvariant()
        foreach ($voiceToken in @(Get-ExpectedInstructorVoiceTokens -InstructorGender $fixtureInstructorGenderForPublish)) {
            if (-not $publishVoiceText.Contains($voiceToken)) {
                Add-CheckError $errors "Lecture publish fixture source audio missing expected voice token: $voiceToken"
            }
        }
        if ([string](Get-PropertyValue -InputObject $publishRender.sourceAvatar -Name 'instructorGender') -ne $fixtureInstructorGenderForPublish) {
            Add-CheckError $errors 'Lecture publish fixture source avatar gender metadata must match the generated instructor.'
        }
        if (-not (Test-HasProperty -Value $publishRender -Name 'visualSync')) {
            Add-CheckError $errors 'Lecture publish fixture renderer must emit visualSync metadata.'
        }
        else {
            if ($publishRender.visualSync.mode -ne 'board-local-writing-layer') {
                Add-CheckError $errors 'Lecture publish fixture renderer must use board-local chalk writing instead of whole-frame instructional overlays.'
            }
            if ($publishRender.visualSync.globalOverlayTextUsed -ne $false) {
                Add-CheckError $errors 'Lecture publish fixture renderer must declare that global instructional overlay text is not used.'
            }
            if ($publishRender.visualSync.pauseSilenceInserted -ne $true) {
                Add-CheckError $errors 'Lecture publish fixture renderer must insert active-recall pause silence into the final timed audio.'
            }
            if (-not ([string]$publishRender.visualSync.staticFrameReplacement).Contains('cleaned empty chalkboard surface')) {
                Add-CheckError $errors 'Lecture publish fixture renderer must clean the board before adding board-local chalk writing.'
            }
            $compositionText = (@($publishRender.visualSync.classroomComposition.cameraPosition, $publishRender.visualSync.classroomComposition.teacherVisibility, $publishRender.visualSync.classroomComposition.boardVisibility) -join ' ').ToLowerInvariant()
            foreach ($compositionToken in @('straight-on', 'right side', 'clean empty board')) {
                if (-not $compositionText.Contains($compositionToken)) {
                    Add-CheckError $errors "Lecture classroom composition metadata missing token: $compositionToken"
                }
            }
            if (-not (Test-HasProperty -Value $publishRender.visualSync -Name 'boardSurface')) {
                Add-CheckError $errors 'Lecture publish fixture renderer must emit board surface coordinates.'
            }
            else {
                if ($publishRender.visualSync.boardSurface.coordinateSpace -ne '1280x720') {
                    Add-CheckError $errors 'Lecture board surface metadata must use the 1280x720 render coordinate space.'
                }
                if (-not ([string]$publishRender.visualSync.boardSurface.label).Contains('cleaned chalkboard')) {
                    Add-CheckError $errors 'Lecture board surface metadata must identify the cleaned chalkboard writing surface.'
                }
                foreach ($field in @('x', 'y', 'width', 'height')) {
                    if ([int](Get-PropertyValue -InputObject $publishRender.visualSync.boardSurface -Name $field) -le 0) {
                        Add-CheckError $errors "Lecture board surface metadata must include a positive $field value."
                    }
                }
                if (-not (Test-HasProperty -Value $publishRender.visualSync.boardSurface -Name 'closeUpCrop')) {
                    Add-CheckError $errors 'Lecture board surface metadata must include a close-up crop.'
                }
                else {
                    $boardCloseUpCrop = Get-PropertyValue -InputObject $publishRender.visualSync.boardSurface -Name 'closeUpCrop'
                    foreach ($field in @('x', 'y', 'width', 'height')) {
                        if ([int](Get-PropertyValue -InputObject $boardCloseUpCrop -Name $field) -le 0) {
                            Add-CheckError $errors "Lecture board close-up crop metadata must include a positive $field value."
                        }
                    }
                    $boardX = [int](Get-PropertyValue -InputObject $publishRender.visualSync.boardSurface -Name 'x')
                    $boardY = [int](Get-PropertyValue -InputObject $publishRender.visualSync.boardSurface -Name 'y')
                    $boardWidth = [int](Get-PropertyValue -InputObject $publishRender.visualSync.boardSurface -Name 'width')
                    $boardHeight = [int](Get-PropertyValue -InputObject $publishRender.visualSync.boardSurface -Name 'height')
                    $cropX = [int](Get-PropertyValue -InputObject $boardCloseUpCrop -Name 'x')
                    $cropY = [int](Get-PropertyValue -InputObject $boardCloseUpCrop -Name 'y')
                    $cropWidth = [int](Get-PropertyValue -InputObject $boardCloseUpCrop -Name 'width')
                    $cropHeight = [int](Get-PropertyValue -InputObject $boardCloseUpCrop -Name 'height')
                    if ($cropX + $cropWidth -gt 1280 -or $cropY + $cropHeight -gt 720) {
                        Add-CheckError $errors 'Lecture board close-up crop must stay inside the 1280x720 classroom render.'
                    }
                    if ($cropX -gt $boardX -or $cropY -gt $boardY -or ($cropX + $cropWidth) -lt ($boardX + $boardWidth) -or ($cropY + $cropHeight) -lt ($boardY + $boardHeight)) {
                        Add-CheckError $errors 'Lecture board close-up crop must fully include the board writing surface.'
                    }
                }
            }
            if ([int]$publishRender.visualSync.boardStateCount -lt @($fixture.performancePlan.visualSync.boardStates).Count) {
                Add-CheckError $errors 'Lecture publish fixture renderer must include every performancePlan board state.'
            }
            if ([int]$publishRender.visualSync.pauseOverlayCount -lt @($fixture.performancePlan.pausePrompts).Count) {
                Add-CheckError $errors 'Lecture publish fixture renderer must include every pause prompt overlay.'
            }
            if (-not ([string]$publishRender.visualSync.source).Contains('performancePlan.visualSync') -or -not ([string]$publishRender.visualSync.source).Contains('performancePlan.pausePrompts')) {
                Add-CheckError $errors 'Lecture publish fixture visualSync metadata must cite performancePlan visual and pause sources.'
            }

            $boardWritingAsset = $publishRender.visualSync.boardWritingAsset
            if ($boardWritingAsset.assetId -ne 'lecture-board-writing-ass' -or $boardWritingAsset.type -ne 'text/x-ass') {
                Add-CheckError $errors 'Lecture publish fixture renderer must archive the board-local writing ASS asset.'
            }
            elseif ($boardWritingAsset.renderMode -ne 'stroke-based-progressive-chalk-ass' -or $boardWritingAsset.progressiveReveal -ne $true -or $boardWritingAsset.strokeLayer -ne $true -or $boardWritingAsset.globalSubtitleMode -ne $false) {
                Add-CheckError $errors 'Lecture board-local writing asset must be stroke-based, progressively revealed, and not a subtitle-style global layer.'
            }
            elseif (-not ([string]$boardWritingAsset.path).StartsWith($fixtureAssetRoot)) {
                Add-CheckError $errors 'Lecture board-local writing asset must live under the subject-owned lecture archive.'
            }
            else {
                $resolvedBoardWritingPath = Resolve-LectureContentPath -ContentRoot $fixtureContentRoot -Path ([string]$boardWritingAsset.path)
                if (-not (Test-Path -LiteralPath $resolvedBoardWritingPath -PathType Leaf)) {
                    Add-CheckError $errors "Lecture board-local writing asset does not exist: $($boardWritingAsset.path)"
                }
                elseif ((Get-Sha256File -Path $resolvedBoardWritingPath) -ne $boardWritingAsset.sha256) {
                    Add-CheckError $errors 'Lecture board-local writing SHA-256 does not match metadata.'
                }
                else {
                    $boardWritingText = Get-Content -LiteralPath $resolvedBoardWritingPath -Raw
                    if (-not $boardWritingText.Contains('\clip(')) {
                        Add-CheckError $errors 'Lecture board-local writing asset must clip all writing to the board surface.'
                    }
                    if ($boardWritingText.Contains('{\an2}')) {
                        Add-CheckError $errors 'Lecture board-local writing asset must not use bottom-of-frame prompt overlays.'
                    }
                    foreach ($strokeMarker in @('layer-mode: stroke-based-chalk-writing', 'reveal-mode: progressive-left-to-right-clipped-strokes', 'Style: BoardStroke', '\p1', 'BoardWriting')) {
                        if (-not $boardWritingText.Contains($strokeMarker)) {
                            Add-CheckError $errors "Lecture board-local writing asset missing stroke-based reveal marker: $strokeMarker"
                        }
                    }
                    if (@([regex]::Matches($boardWritingText, 'Dialogue: 1,')).Count -lt 8) {
                        Add-CheckError $errors 'Lecture board-local writing asset must use multiple progressive text reveal events instead of one static line event.'
                    }
                }
            }
            $boardCloseUpRender = Get-PropertyValue -InputObject $publishRender.visualSync -Name 'boardCloseUpRender'
            if ($null -eq $boardCloseUpRender) {
                Add-CheckError $errors 'Lecture publish fixture renderer must emit a board close-up render asset.'
            }
            else {
                if ($boardCloseUpRender.assetId -ne 'lecture-board-close-up-mp4' -or $boardCloseUpRender.type -ne 'video/mp4') {
                    Add-CheckError $errors 'Lecture board close-up render must be a video/mp4 media asset.'
                }
                if ($boardCloseUpRender.status -ne 'archived' -or $boardCloseUpRender.requiredForPublish -ne $false) {
                    Add-CheckError $errors 'Lecture board close-up render must be archived as a non-required support asset.'
                }
                if ($boardCloseUpRender.sourceAssetId -ne 'lecture-video-mp4') {
                    Add-CheckError $errors 'Lecture board close-up render must derive from the full classroom MP4.'
                }
                if (-not ([string]$boardCloseUpRender.path).StartsWith($fixtureAssetRoot)) {
                    Add-CheckError $errors 'Lecture board close-up render must live under the subject-owned lecture archive.'
                }
                else {
                    $resolvedBoardCloseUpPath = Resolve-LectureContentPath -ContentRoot $fixtureContentRoot -Path ([string]$boardCloseUpRender.path)
                    if (-not (Test-Path -LiteralPath $resolvedBoardCloseUpPath -PathType Leaf)) {
                        Add-CheckError $errors "Lecture board close-up render does not exist: $($boardCloseUpRender.path)"
                    }
                    elseif ((Get-Sha256File -Path $resolvedBoardCloseUpPath) -ne $boardCloseUpRender.sha256) {
                        Add-CheckError $errors 'Lecture board close-up render SHA-256 does not match metadata.'
                    }
                    elseif ([int64](Get-Item -LiteralPath $resolvedBoardCloseUpPath).Length -ne [int64]$boardCloseUpRender.length) {
                        Add-CheckError $errors 'Lecture board close-up render length does not match metadata.'
                    }
                }
                if (-not ([string]$boardCloseUpRender.cropSource).Contains('closeUpCrop')) {
                    Add-CheckError $errors 'Lecture board close-up render must cite the board surface close-up crop source.'
                }
                foreach ($preservationFlag in @('audioPreserved', 'transcriptPreserved', 'checkpointContextPreserved', 'classroomContextPreserved')) {
                    if ((Get-PropertyValue -InputObject $boardCloseUpRender -Name $preservationFlag) -ne $true) {
                        Add-CheckError $errors "Lecture board close-up render must preserve context flag: $preservationFlag"
                    }
                }
                if (-not ([string]$boardCloseUpRender.transcriptSource).Contains('transcript')) {
                    Add-CheckError $errors 'Lecture board close-up render must cite the transcript source it preserves.'
                }
                if (-not ([string]$boardCloseUpRender.checkpointSource).Contains('adaptiveHooks.checkpoints')) {
                    Add-CheckError $errors 'Lecture board close-up render must cite the checkpoint source it preserves.'
                }
                if (-not ([string]$boardCloseUpRender.contextSource).Contains('front-row classroom')) {
                    Add-CheckError $errors 'Lecture board close-up render must preserve front-row classroom context.'
                }
            }
            $cameraPlan = Get-PropertyValue -InputObject $publishRender.visualSync -Name 'cameraPlan'
            if ($null -eq $cameraPlan) {
                Add-CheckError $errors 'Lecture publish fixture renderer must emit a guided camera plan.'
            }
            else {
                if ($cameraPlan.mode -ne 'front-row-and-board-close-up-cut-plan') {
                    Add-CheckError $errors 'Lecture guided camera plan must declare the front-row and board close-up mode.'
                }
                if (-not ([string]$cameraPlan.source).Contains('performancePlan.visualSync') -or -not ([string]$cameraPlan.source).Contains('performancePlan.pausePrompts')) {
                    Add-CheckError $errors 'Lecture guided camera plan must cite board state and pause prompt sources.'
                }
                $cameraCuts = @($cameraPlan.cuts | Where-Object { $null -ne $_ })
                if ($cameraCuts.Count -lt 3) {
                    Add-CheckError $errors 'Lecture guided camera plan must include at least three cuts.'
                }
                if (@($cameraCuts | Where-Object { $_.view -eq 'board-close-up' }).Count -lt 1) {
                    Add-CheckError $errors 'Lecture guided camera plan must include at least one board close-up cut.'
                }
                if (@($cameraCuts | Where-Object { $_.view -eq 'front-row-classroom' }).Count -lt 1) {
                    Add-CheckError $errors 'Lecture guided camera plan must include at least one front-row classroom cut.'
                }
                $previousEnd = $null
                foreach ($cameraCut in $cameraCuts) {
                    if (@('front-row-classroom', 'board-close-up') -notcontains [string]$cameraCut.view) {
                        Add-CheckError $errors "Lecture guided camera plan has unsupported view: $($cameraCut.view)"
                    }
                    if ([double]$cameraCut.endSecond -le [double]$cameraCut.startSecond) {
                        Add-CheckError $errors 'Lecture guided camera plan cuts must have positive duration.'
                    }
                    if (-not (Test-HasText $cameraCut.reason)) {
                        Add-CheckError $errors 'Lecture guided camera plan cuts must explain why the shot is selected.'
                    }
                    if ($null -ne $previousEnd -and [Math]::Abs([double]$cameraCut.startSecond - [double]$previousEnd) -gt 0.01) {
                        Add-CheckError $errors 'Lecture guided camera plan cuts must be contiguous.'
                    }
                    $previousEnd = [double]$cameraCut.endSecond
                }
                if ($cameraCuts.Count -ge 1) {
                    if ([double]$cameraCuts[0].startSecond -ne 0.0) {
                        Add-CheckError $errors 'Lecture guided camera plan must start at 0 seconds.'
                    }
                    if ([Math]::Abs([double]$cameraCuts[$cameraCuts.Count - 1].endSecond - [double]$fixture.durationSeconds) -gt 0.01) {
                        Add-CheckError $errors 'Lecture guided camera plan must cover the full lecture duration.'
                    }
                }
            }
            $guidedCameraRender = Get-PropertyValue -InputObject $publishRender.visualSync -Name 'guidedCameraRender'
            if ($null -eq $guidedCameraRender) {
                Add-CheckError $errors 'Lecture publish fixture renderer must emit a guided camera render asset.'
            }
            else {
                if ($guidedCameraRender.assetId -ne 'lecture-guided-camera-mp4' -or $guidedCameraRender.type -ne 'video/mp4') {
                    Add-CheckError $errors 'Lecture guided camera render must be a video/mp4 media asset.'
                }
                if ($guidedCameraRender.status -ne 'archived' -or $guidedCameraRender.requiredForPublish -ne $false) {
                    Add-CheckError $errors 'Lecture guided camera render must be archived as a non-required support asset.'
                }
                if ($guidedCameraRender.visualSyncMode -ne 'board-close-up-guided-camera') {
                    Add-CheckError $errors 'Lecture guided camera render must declare the board-close-up guided-camera visual sync mode.'
                }
                $guidedSourceAssetIds = @($guidedCameraRender.sourceAssetIds | Where-Object { Test-HasText $_ })
                foreach ($sourceAssetId in @('lecture-video-mp4', 'lecture-board-close-up-mp4')) {
                    if (@($guidedSourceAssetIds | Where-Object { $_ -eq $sourceAssetId }).Count -ne 1) {
                        Add-CheckError $errors "Lecture guided camera render missing source asset: $sourceAssetId"
                    }
                }
                if ([int]$guidedCameraRender.cutCount -lt 3 -or [int]$guidedCameraRender.boardCloseUpCutCount -lt 1 -or [int]$guidedCameraRender.frontRowCutCount -lt 1) {
                    Add-CheckError $errors 'Lecture guided camera render must summarize front-row and board close-up cuts.'
                }
                if (-not ([string]$guidedCameraRender.path).StartsWith($fixtureAssetRoot)) {
                    Add-CheckError $errors 'Lecture guided camera render must live under the subject-owned lecture archive.'
                }
                else {
                    $resolvedGuidedCameraPath = Resolve-LectureContentPath -ContentRoot $fixtureContentRoot -Path ([string]$guidedCameraRender.path)
                    if (-not (Test-Path -LiteralPath $resolvedGuidedCameraPath -PathType Leaf)) {
                        Add-CheckError $errors "Lecture guided camera render does not exist: $($guidedCameraRender.path)"
                    }
                    elseif ((Get-Sha256File -Path $resolvedGuidedCameraPath) -ne $guidedCameraRender.sha256) {
                        Add-CheckError $errors 'Lecture guided camera render SHA-256 does not match metadata.'
                    }
                    elseif ([int64](Get-Item -LiteralPath $resolvedGuidedCameraPath).Length -ne [int64]$guidedCameraRender.length) {
                        Add-CheckError $errors 'Lecture guided camera render length does not match metadata.'
                    }
                }
                if (-not ([string]$guidedCameraRender.cameraPlanSource).Contains('visualSync.cameraPlan')) {
                    Add-CheckError $errors 'Lecture guided camera render must cite the camera plan source.'
                }
                foreach ($preservationFlag in @('audioPreserved', 'transcriptPreserved', 'checkpointContextPreserved', 'classroomContextPreserved')) {
                    if ((Get-PropertyValue -InputObject $guidedCameraRender -Name $preservationFlag) -ne $true) {
                        Add-CheckError $errors "Lecture guided camera render must preserve context flag: $preservationFlag"
                    }
                }
            }
            $frameQaEvidence = Get-PropertyValue -InputObject $publishRender.visualSync -Name 'frameQaEvidence'
            if ($null -eq $frameQaEvidence) {
                Add-CheckError $errors 'Lecture publish fixture renderer must emit extracted-frame QA evidence.'
            }
            else {
                if ($frameQaEvidence.status -ne 'archived-pending-operator-review') {
                    Add-CheckError $errors 'Lecture extracted-frame QA evidence must remain archived pending operator review.'
                }
                if (-not ([string]$frameQaEvidence.source).Contains('ffmpeg') -or -not ([string]$frameQaEvidence.source).Contains('guided-camera')) {
                    Add-CheckError $errors 'Lecture extracted-frame QA evidence must cite the ffmpeg extraction source and guided-camera render.'
                }
                $qaFrames = @($frameQaEvidence.frames | Where-Object { $null -ne $_ })
                if ([int]$frameQaEvidence.evidenceCount -ne $qaFrames.Count -or $qaFrames.Count -lt 4) {
                    Add-CheckError $errors 'Lecture extracted-frame QA evidence must include at least four frame assets.'
                }
                foreach ($requiredEvidenceType in @('board-readability', 'instructor-occlusion', 'camera-shot-selection', 'board-surface-alignment')) {
                    if (@($frameQaEvidence.requiredEvidenceTypes | Where-Object { $_ -eq $requiredEvidenceType }).Count -ne 1) {
                        Add-CheckError $errors "Lecture extracted-frame QA metadata missing required evidence type: $requiredEvidenceType"
                    }
                    $frame = @($qaFrames | Where-Object { $_.evidenceType -eq $requiredEvidenceType })
                    if ($frame.Count -ne 1) {
                        Add-CheckError $errors "Lecture extracted-frame QA asset missing evidence type: $requiredEvidenceType"
                        continue
                    }
                    $frame = $frame[0]
                    if ($frame.type -ne 'image/png' -or $frame.status -ne 'archived' -or $frame.requiredForPublish -ne $false) {
                        Add-CheckError $errors "Lecture extracted-frame QA asset must be archived non-required PNG evidence: $requiredEvidenceType"
                    }
                    if ($frame.reviewStatus -ne 'pending-operator-review') {
                        Add-CheckError $errors "Lecture extracted-frame QA asset must remain pending operator review: $requiredEvidenceType"
                    }
                    if ($frame.coordinateSpace -ne '1280x720' -or $frame.boardSurfaceReference -ne 'visualSync.boardSurface') {
                        Add-CheckError $errors "Lecture extracted-frame QA asset must cite board coordinate metadata: $requiredEvidenceType"
                    }
                    if (-not (Test-HasText $frame.expectedView) -or -not (Test-HasText $frame.visualCheck) -or [double]$frame.capturedSecond -le 0) {
                        Add-CheckError $errors "Lecture extracted-frame QA asset must include timestamped review context: $requiredEvidenceType"
                    }
                    if (-not ([string]$frame.path).StartsWith($fixtureAssetRoot)) {
                        Add-CheckError $errors "Lecture extracted-frame QA asset must live under the subject-owned lecture archive: $requiredEvidenceType"
                    }
                    else {
                        $resolvedQaFramePath = Resolve-LectureContentPath -ContentRoot $fixtureContentRoot -Path ([string]$frame.path)
                        if (-not (Test-Path -LiteralPath $resolvedQaFramePath -PathType Leaf)) {
                            Add-CheckError $errors "Lecture extracted-frame QA asset does not exist: $($frame.path)"
                        }
                        elseif ((Get-Sha256File -Path $resolvedQaFramePath) -ne $frame.sha256) {
                            Add-CheckError $errors "Lecture extracted-frame QA asset SHA-256 does not match metadata: $requiredEvidenceType"
                        }
                        elseif ([int64](Get-Item -LiteralPath $resolvedQaFramePath).Length -ne [int64]$frame.length -or [int64]$frame.length -lt 1000) {
                            Add-CheckError $errors "Lecture extracted-frame QA asset length is invalid: $requiredEvidenceType"
                        }
                    }
                    $mediaFrame = @($publishRender.media | Where-Object { $_.assetId -eq $frame.assetId })
                    if ($mediaFrame.Count -ne 1 -or $mediaFrame[0].sha256 -ne $frame.sha256 -or $mediaFrame[0].path -ne $frame.path) {
                        Add-CheckError $errors "Lecture extracted-frame QA asset must also appear in publish media: $requiredEvidenceType"
                    }
                }
            }
            $motionAndLipSync = Get-PropertyValue -InputObject $publishRender.visualSync -Name 'motionAndLipSync'
            if ($null -eq $motionAndLipSync) {
                Add-CheckError $errors 'Lecture publish fixture renderer must emit motion and lip-sync visual QA metadata.'
            }
            else {
                $visualQaChecks = @((Get-PropertyValue -InputObject $motionAndLipSync -Name 'visualQaChecks') | Where-Object { $null -ne $_ })
                $requiredVisualQaChecks = @(
                    @{ checkId = 'lip-sync-timing'; tokens = @('audio', 'mouth', 'pause') },
                    @{ checkId = 'gaze-direction'; tokens = @('gaze', 'learner', 'board') },
                    @{ checkId = 'head-hand-motion-naturalness'; tokens = @('head', 'hand', 'natural') },
                    @{ checkId = 'board-writing-gesture-synchronization'; tokens = @('board-local', 'gesture', 'writing') }
                )
                foreach ($requiredVisualQaCheck in $requiredVisualQaChecks) {
                    $qaCheck = @($visualQaChecks | Where-Object { $_.checkId -eq $requiredVisualQaCheck.checkId })
                    if ($qaCheck.Count -ne 1) {
                        Add-CheckError $errors "Lecture visual QA metadata missing check: $($requiredVisualQaCheck.checkId)"
                        continue
                    }
                    if ($qaCheck[0].status -ne 'required-before-publish-promotion' -or $qaCheck[0].failureAction -ne 'changes-requested') {
                        Add-CheckError $errors "Lecture visual QA check must block publish promotion until reviewed: $($requiredVisualQaCheck.checkId)"
                    }
                    if (@($qaCheck[0].requiredEvidence).Count -lt 2) {
                        Add-CheckError $errors "Lecture visual QA check must name concrete evidence: $($requiredVisualQaCheck.checkId)"
                    }
                    $qaText = (@($qaCheck[0].target, $qaCheck[0].passCriteria, $qaCheck[0].requiredEvidence) -join ' ').ToLowerInvariant()
                    foreach ($token in @($requiredVisualQaCheck.tokens)) {
                        if (-not $qaText.Contains($token)) {
                            Add-CheckError $errors "Lecture visual QA check missing token $token`: $($requiredVisualQaCheck.checkId)"
                        }
                    }
                }
                if ($motionAndLipSync.status -ne 'local-preview-renders-archived-pending-visual-qa') {
                    Add-CheckError $errors 'Lecture motion/lip-sync metadata must record archived local previews pending visual QA.'
                }
                $previewPromotionPolicy = Get-PropertyValue -InputObject $motionAndLipSync -Name 'previewPromotionPolicy'
                if ($null -eq $previewPromotionPolicy) {
                    Add-CheckError $errors 'Lecture motion/lip-sync metadata must include a preview promotion policy.'
                }
                else {
                    if ($previewPromotionPolicy.publishPromotion -ne 'blocked-pending-operator-visual-qa' -or $previewPromotionPolicy.visualQaStatus -ne 'pending-operator-review' -or $previewPromotionPolicy.canReplacePublishVideo -ne $false) {
                        Add-CheckError $errors 'Lecture motion/lip-sync preview promotion must stay blocked until operator visual QA passes.'
                    }
                    foreach ($requiredReviewCheckId in @('lip-sync-timing', 'gaze-direction', 'head-hand-motion-naturalness', 'board-writing-gesture-synchronization')) {
                        if (@($previewPromotionPolicy.requiredBeforePromotion | Where-Object { $_ -eq $requiredReviewCheckId }).Count -ne 1) {
                            Add-CheckError $errors "Lecture motion/lip-sync preview promotion policy missing QA check: $requiredReviewCheckId"
                        }
                    }
                }
                $previewRenderChecks = @(
                    @{
                        propertyName = 'motionPreviewRender'
                        assetId = 'lecture-instructor-motion-preview-mp4'
                        visualSyncMode = 'deterministic-motion-preview'
                        renderEngineToken = 'motion-preview'
                        requiredFlag = 'preLipSyncMotionOnly'
                        blockedFlag = 'lipSyncIncluded'
                    },
                    @{
                        propertyName = 'lipSyncPreviewRender'
                        assetId = 'lecture-instructor-lipsync-preview-mp4'
                        visualSyncMode = 'deterministic-audio-reactive-lipsync-preview'
                        renderEngineToken = 'lipsync-preview'
                        requiredFlag = 'audioDrivenMouthMovement'
                        blockedFlag = $null
                    }
                )
                foreach ($previewRenderCheck in $previewRenderChecks) {
                    $previewRender = Get-PropertyValue -InputObject $motionAndLipSync -Name $previewRenderCheck.propertyName
                    if ($null -eq $previewRender) {
                        Add-CheckError $errors "Lecture motion/lip-sync metadata missing preview render: $($previewRenderCheck.propertyName)"
                        continue
                    }
                    if ($previewRender.assetId -ne $previewRenderCheck.assetId -or $previewRender.type -ne 'video/mp4') {
                        Add-CheckError $errors "Lecture preview render must be a video/mp4 asset: $($previewRenderCheck.assetId)"
                    }
                    if ($previewRender.status -ne 'archived' -or $previewRender.requiredForPublish -ne $false) {
                        Add-CheckError $errors "Lecture preview render must be archived and non-required: $($previewRenderCheck.assetId)"
                    }
                    if (-not ([string]$previewRender.renderEngine).Contains($previewRenderCheck.renderEngineToken)) {
                        Add-CheckError $errors "Lecture preview render must declare its local render engine: $($previewRenderCheck.assetId)"
                    }
                    if ([int]$previewRender.previewDurationSeconds -lt 3) {
                        Add-CheckError $errors "Lecture preview render must include a useful preview duration: $($previewRenderCheck.assetId)"
                    }
                    if ($previewRender.previewRenderIncluded -ne $true -or $previewRender.modelRenderIncluded -ne $false) {
                        Add-CheckError $errors "Lecture preview render must be a real local preview while clearly not claiming model-backed output: $($previewRenderCheck.assetId)"
                    }
                    if ($previewRender.publishPromotion -ne 'blocked-pending-operator-visual-qa' -or $previewRender.visualQaStatus -ne 'pending-operator-review') {
                        Add-CheckError $errors "Lecture preview render must remain blocked until visual QA: $($previewRenderCheck.assetId)"
                    }
                    if ((Get-PropertyValue -InputObject $previewRender -Name $previewRenderCheck.requiredFlag) -ne $true) {
                        Add-CheckError $errors "Lecture preview render missing required stage flag: $($previewRenderCheck.requiredFlag)"
                    }
                    if ($null -ne $previewRenderCheck.blockedFlag -and (Get-PropertyValue -InputObject $previewRender -Name $previewRenderCheck.blockedFlag) -ne $false) {
                        Add-CheckError $errors "Lecture motion preview must keep lip sync disabled until the lip-sync stage."
                    }
                    $previewSourceAssetIds = @($previewRender.sourceAssetIds | Where-Object { Test-HasText $_ })
                    foreach ($sourceAssetId in @($avatarRenderedMedia.assetId, 'lecture-audio-m4a')) {
                        if (@($previewSourceAssetIds | Where-Object { $_ -eq $sourceAssetId }).Count -ne 1) {
                            Add-CheckError $errors "Lecture preview render missing source asset $sourceAssetId`: $($previewRenderCheck.assetId)"
                        }
                    }
                    if (-not ([string]$previewRender.path).StartsWith($fixtureAssetRoot)) {
                        Add-CheckError $errors "Lecture preview render must live under the subject-owned lecture archive: $($previewRenderCheck.assetId)"
                    }
                    else {
                        $resolvedPreviewPath = Resolve-LectureContentPath -ContentRoot $fixtureContentRoot -Path ([string]$previewRender.path)
                        if (-not (Test-Path -LiteralPath $resolvedPreviewPath -PathType Leaf)) {
                            Add-CheckError $errors "Lecture preview render does not exist: $($previewRender.path)"
                        }
                        elseif ((Get-Sha256File -Path $resolvedPreviewPath) -ne $previewRender.sha256) {
                            Add-CheckError $errors "Lecture preview render SHA-256 does not match metadata: $($previewRenderCheck.assetId)"
                        }
                        elseif ([int64](Get-Item -LiteralPath $resolvedPreviewPath).Length -ne [int64]$previewRender.length) {
                            Add-CheckError $errors "Lecture preview render length does not match metadata: $($previewRenderCheck.assetId)"
                        }
                    }
                    if ($previewRenderCheck.assetId -eq 'lecture-instructor-lipsync-preview-mp4' -and -not ([string]$previewRender.pausePromptMouthState).Contains('neutral')) {
                        Add-CheckError $errors 'Lecture lip-sync preview must keep pause-prompt mouth state neutral.'
                    }
                }
            }
        }
        $boardCloseUpPublishMedia = @($publishRender.media | Where-Object { $_.assetId -eq 'lecture-board-close-up-mp4' })
        if ($boardCloseUpPublishMedia.Count -ne 1) {
            Add-CheckError $errors 'Lecture publish fixture renderer missing media asset: lecture-board-close-up-mp4'
        }
        else {
            if ($boardCloseUpPublishMedia[0].status -ne 'archived' -or $boardCloseUpPublishMedia[0].requiredForPublish -ne $false) {
                Add-CheckError $errors 'Lecture board close-up media must be archived as non-required support media.'
            }
            if (-not ([string]$boardCloseUpPublishMedia[0].path).StartsWith($fixtureAssetRoot)) {
                Add-CheckError $errors 'Lecture board close-up media must be under the subject-owned lecture archive.'
            }
            if ($boardCloseUpPublishMedia[0].sha256 -notmatch '^[a-f0-9]{64}$') {
                Add-CheckError $errors 'Lecture board close-up media must include a lowercase SHA-256 checksum.'
            }
            if ([int64]$boardCloseUpPublishMedia[0].length -lt 1000) {
                Add-CheckError $errors 'Lecture board close-up media file is too small.'
            }
            if ($boardCloseUpPublishMedia[0].visualSyncMode -ne 'board-close-up-crop' -or $boardCloseUpPublishMedia[0].sourceAssetId -ne 'lecture-video-mp4') {
                Add-CheckError $errors 'Lecture board close-up media must declare its crop mode and source classroom video.'
            }
            foreach ($preservationFlag in @('audioPreserved', 'transcriptPreserved', 'checkpointContextPreserved', 'classroomContextPreserved')) {
                if ((Get-PropertyValue -InputObject $boardCloseUpPublishMedia[0] -Name $preservationFlag) -ne $true) {
                    Add-CheckError $errors "Lecture board close-up media must preserve context flag: $preservationFlag"
                }
            }
        }
        $guidedCameraPublishMedia = @($publishRender.media | Where-Object { $_.assetId -eq 'lecture-guided-camera-mp4' })
        if ($guidedCameraPublishMedia.Count -ne 1) {
            Add-CheckError $errors 'Lecture publish fixture renderer missing media asset: lecture-guided-camera-mp4'
        }
        else {
            if ($guidedCameraPublishMedia[0].status -ne 'archived' -or $guidedCameraPublishMedia[0].requiredForPublish -ne $false) {
                Add-CheckError $errors 'Lecture guided camera media must be archived as non-required support media.'
            }
            if (-not ([string]$guidedCameraPublishMedia[0].path).StartsWith($fixtureAssetRoot)) {
                Add-CheckError $errors 'Lecture guided camera media must be under the subject-owned lecture archive.'
            }
            if ($guidedCameraPublishMedia[0].sha256 -notmatch '^[a-f0-9]{64}$') {
                Add-CheckError $errors 'Lecture guided camera media must include a lowercase SHA-256 checksum.'
            }
            if ([int64]$guidedCameraPublishMedia[0].length -lt 1000) {
                Add-CheckError $errors 'Lecture guided camera media file is too small.'
            }
            if ($guidedCameraPublishMedia[0].visualSyncMode -ne 'board-close-up-guided-camera') {
                Add-CheckError $errors 'Lecture guided camera media must declare the guided-camera visual sync mode.'
            }
            $guidedMediaSourceAssetIds = @($guidedCameraPublishMedia[0].sourceAssetIds | Where-Object { Test-HasText $_ })
            foreach ($sourceAssetId in @('lecture-video-mp4', 'lecture-board-close-up-mp4')) {
                if (@($guidedMediaSourceAssetIds | Where-Object { $_ -eq $sourceAssetId }).Count -ne 1) {
                    Add-CheckError $errors "Lecture guided camera media missing source asset: $sourceAssetId"
                }
            }
            foreach ($preservationFlag in @('audioPreserved', 'transcriptPreserved', 'checkpointContextPreserved', 'classroomContextPreserved')) {
                if ((Get-PropertyValue -InputObject $guidedCameraPublishMedia[0] -Name $preservationFlag) -ne $true) {
                    Add-CheckError $errors "Lecture guided camera media must preserve context flag: $preservationFlag"
                }
            }
        }
        foreach ($previewMediaCheck in @(
            @{
                assetId = 'lecture-instructor-motion-preview-mp4'
                visualSyncMode = 'deterministic-motion-preview'
            },
            @{
                assetId = 'lecture-instructor-lipsync-preview-mp4'
                visualSyncMode = 'deterministic-audio-reactive-lipsync-preview'
            }
        )) {
            $previewPublishMedia = @($publishRender.media | Where-Object { $_.assetId -eq $previewMediaCheck.assetId })
            if ($previewPublishMedia.Count -ne 1) {
                Add-CheckError $errors "Lecture publish fixture renderer missing media asset: $($previewMediaCheck.assetId)"
                continue
            }
            if ($previewPublishMedia[0].status -ne 'archived' -or $previewPublishMedia[0].requiredForPublish -ne $false) {
                Add-CheckError $errors "Lecture preview media must be archived as non-required support media: $($previewMediaCheck.assetId)"
            }
            if (-not ([string]$previewPublishMedia[0].path).StartsWith($fixtureAssetRoot)) {
                Add-CheckError $errors "Lecture preview media must be under the subject-owned lecture archive: $($previewMediaCheck.assetId)"
            }
            if ($previewPublishMedia[0].sha256 -notmatch '^[a-f0-9]{64}$') {
                Add-CheckError $errors "Lecture preview media must include a lowercase SHA-256 checksum: $($previewMediaCheck.assetId)"
            }
            if ([int64]$previewPublishMedia[0].length -lt 1000) {
                Add-CheckError $errors "Lecture preview media file is too small: $($previewMediaCheck.assetId)"
            }
            if ($previewPublishMedia[0].visualSyncMode -ne $previewMediaCheck.visualSyncMode) {
                Add-CheckError $errors "Lecture preview media must declare the expected visual sync mode: $($previewMediaCheck.assetId)"
            }
            if ($previewPublishMedia[0].publishPromotion -ne 'blocked-pending-operator-visual-qa' -or $previewPublishMedia[0].visualQaStatus -ne 'pending-operator-review') {
                Add-CheckError $errors "Lecture preview media must remain blocked until operator visual QA: $($previewMediaCheck.assetId)"
            }
            $previewMediaSourceAssetIds = @($previewPublishMedia[0].sourceAssetIds | Where-Object { Test-HasText $_ })
            foreach ($sourceAssetId in @($avatarRenderedMedia.assetId, 'lecture-audio-m4a')) {
                if (@($previewMediaSourceAssetIds | Where-Object { $_ -eq $sourceAssetId }).Count -ne 1) {
                    Add-CheckError $errors "Lecture preview media missing source asset $sourceAssetId`: $($previewMediaCheck.assetId)"
                }
            }
        }
        foreach ($assetId in @('lecture-video-mp4', 'lecture-audio-m4a')) {
            $renderedPublishMedia = @($publishRender.media | Where-Object { $_.assetId -eq $assetId })
            if ($renderedPublishMedia.Count -ne 1) {
                Add-CheckError $errors "Lecture publish fixture renderer missing media asset: $assetId"
            }
            else {
                if ($renderedPublishMedia[0].status -ne 'archived' -or $renderedPublishMedia[0].requiredForPublish -ne $true) {
                    Add-CheckError $errors "Lecture publish fixture media must be archived and required: $assetId"
                }
                if (-not ([string]$renderedPublishMedia[0].path).StartsWith($fixtureAssetRoot)) {
                    Add-CheckError $errors "Lecture publish fixture media must be under the subject-owned lecture archive: $assetId"
                }
                if ($renderedPublishMedia[0].sha256 -notmatch '^[a-f0-9]{64}$') {
                    Add-CheckError $errors "Lecture publish fixture media must include a lowercase SHA-256 checksum: $assetId"
                }
                if ([int64]$renderedPublishMedia[0].length -lt 1000) {
                    Add-CheckError $errors "Lecture publish fixture media file is too small: $assetId"
                }
                if ($assetId -eq 'lecture-audio-m4a' -and ($renderedPublishMedia[0].sourceAssetId -notlike 'lecture-audio-comfyui-tts-*' -or $renderedPublishMedia[0].pauseSilenceInserted -ne $true)) {
                    Add-CheckError $errors 'Lecture publish fixture audio must derive from local ComfyUI TTS and include inserted active-recall pause silence.'
                }
                if ($assetId -eq 'lecture-video-mp4' -and $renderedPublishMedia[0].visualSyncMode -ne 'board-local-writing-layer') {
                    Add-CheckError $errors 'Lecture publish fixture video must declare the board-local writing visual sync mode.'
                }
            }
        }
        $renderedAvatarPublishMedia = @($publishRender.media | Where-Object { $_.assetId -eq $avatarRenderedMedia.assetId })
        if ($renderedAvatarPublishMedia.Count -ne 1) {
            Add-CheckError $errors 'Lecture publish fixture renderer must include the ComfyUI avatar source media.'
        }
        elseif ($renderedAvatarPublishMedia[0].sha256 -ne $avatarRenderedMedia.sha256 -or $renderedAvatarPublishMedia[0].requiredForPublish -ne $false) {
            Add-CheckError $errors 'Lecture publish fixture renderer must preserve the ComfyUI avatar checksum as non-required source media.'
        }

        if ($renderComparison.schemaVersion -ne 1 -or $renderComparison.packageId -ne $fixture.packageId) {
            Add-CheckError $errors 'Lecture render comparison metadata must reference the GDEV lecture fixture.'
        }
        if ($renderComparison.previousStaticFixture.renderMode -ne 'single-static-avatar-loop') {
            Add-CheckError $errors 'Lecture render comparison must preserve the previous static fixture baseline.'
        }
        if ($renderComparison.updatedSceneAwareRender.renderMode -ne 'board-local-writing-layer') {
            Add-CheckError $errors 'Lecture render comparison must record the updated board-local writing render mode.'
        }
        $comparisonVideo = @($publishRender.media | Where-Object { $_.assetId -eq 'lecture-video-mp4' } | Select-Object -First 1)
        if ($comparisonVideo.Count -eq 1) {
            if ($renderComparison.updatedSceneAwareRender.sha256 -ne $comparisonVideo[0].sha256) {
                Add-CheckError $errors 'Lecture render comparison updated video checksum must match the rendered MP4.'
            }
            if ([int64]$renderComparison.updatedSceneAwareRender.length -ne [int64]$comparisonVideo[0].length) {
                Add-CheckError $errors 'Lecture render comparison updated video length must match the rendered MP4.'
            }
            if ($renderComparison.previousStaticFixture.sha256 -eq $comparisonVideo[0].sha256) {
                Add-CheckError $errors 'Lecture render comparison must prove the updated video differs from the static fixture.'
            }
        }
        if ([int]$renderComparison.updatedSceneAwareRender.boardStateCount -lt @($fixture.performancePlan.visualSync.boardStates).Count) {
            Add-CheckError $errors 'Lecture render comparison must include all board states from the performance plan.'
        }
        if ([int]$renderComparison.updatedSceneAwareRender.pauseOverlayCount -lt @($fixture.performancePlan.pausePrompts).Count) {
            Add-CheckError $errors 'Lecture render comparison must include all pause overlays from the performance plan.'
        }
        if ($renderComparison.updatedSceneAwareRender.boardWritingAsset.sha256 -ne $publishRender.visualSync.boardWritingAsset.sha256) {
            Add-CheckError $errors 'Lecture render comparison board writing checksum must match the archived board-local writing asset.'
        }
        foreach ($resultFlag in @('hashChanged', 'lengthChanged', 'boardVisualsMatchPerformancePlan', 'pauseOverlayMatchesPerformancePlan', 'readyForOperatorVisualReview')) {
            if ((Get-PropertyValue -InputObject $renderComparison.result -Name $resultFlag) -ne $true) {
                Add-CheckError $errors "Lecture render comparison result flag must be true: $resultFlag"
            }
        }
    }
    if ($publishRenderOk) {
        $publishGateOutput = & .\scripts\teaching\run-lecture-publish-gate.ps1 -ManifestPath $FixturePath -WorkflowPath $OperatorReviewWorkflowPath 2>&1
        if ($LASTEXITCODE -ne 0) {
            Add-CheckError $errors "Lecture publish gate runner failed: $publishGateOutput"
        }
        else {
            $publishGate = ($publishGateOutput | Out-String) | ConvertFrom-Json
            if ($publishGate.schemaVersion -ne 1) {
                Add-CheckError $errors 'Lecture publish gate runner must use schemaVersion 1.'
            }
            if ($publishGate.packageId -ne $fixture.packageId) {
                Add-CheckError $errors 'Lecture publish gate packageId must match the lecture fixture.'
            }
            if ($publishGate.mode -ne 'dry-run') {
                Add-CheckError $errors 'Lecture publish gate verification must run in dry-run mode.'
            }
            if ($publishGate.publishReady -ne $true) {
                Add-CheckError $errors 'Lecture publish gate must approve the rendered deterministic package candidate.'
            }
            if ($publishGate.wrotePublishReadyPath -ne $false) {
                Add-CheckError $errors 'Lecture publish gate dry-run must not write the publish-ready package.'
            }
            if (-not ([string]$publishGate.publishReadyPath).StartsWith($fixtureAssetRoot) -or -not ([string]$publishGate.publishReadyPath).EndsWith('publish\lecture-video.publish-ready.json')) {
                Add-CheckError $errors 'Lecture publish gate must record the archive publish-ready path.'
            }
            if ($publishGate.operatorGate.exitCode -ne 0 -or $publishGate.operatorGate.publishReady -ne $true -or $publishGate.operatorGate.errorCount -ne 0) {
                Add-CheckError $errors 'Lecture publish gate must pass the operator review publish gate.'
            }
            foreach ($assetId in @('lecture-video-mp4', 'lecture-audio-m4a')) {
                $gateMedia = @($publishGate.media | Where-Object { $_.assetId -eq $assetId })
                if ($gateMedia.Count -ne 1) {
                    Add-CheckError $errors "Lecture publish gate result missing media asset: $assetId"
                }
                elseif ($gateMedia[0].sha256 -notmatch '^[a-f0-9]{64}$' -or $gateMedia[0].status -ne 'archived') {
                    Add-CheckError $errors "Lecture publish gate media result must be archived with SHA-256: $assetId"
                }
            }
        }
    }

    if ($schema.schemaVersion -ne 1) {
        Add-CheckError $errors 'Lecture video schemaVersion must be 1.'
    }

    foreach ($marker in @(
        '## Source Review Matrix',
        'Open courseware',
        'University course',
        'Educator channel',
        'Professional talk',
        'Transferable teaching moves',
        'Reuse boundary',
        'do not copy transcript',
        'do not archive talks',
        '## Copyright And Licensing Gate',
        'check-lecture-license-gate.ps1',
        'copied transcripts',
        'unlicensed slides',
        'unauthorized likenesses',
        'host-only media',
        '## Local Archive Conventions',
        'lecture-media-archive-policy.json',
        'generated-lectures',
        'SHA-256',
        'do not commit rendered media',
        '## Lecture Accessibility Requirements',
        'lecture-accessibility-policy.json',
        'Captions and transcripts are required package assets',
        'Slides must be understandable from alt text',
        'transcript-first, audio-first, and video-first',
        '## Video Teaching-Quality Rubric',
        'lecture-video-quality-rubric.json',
        'Video Pacing',
        'Worked Examples',
        'Assessment Handoff',
        '## Checkpoint Evidence',
        'lecture_checkpoint_submitted',
        'does not increment mastery `evidenceCount`',
        'passive video watch completion',
        '## Adaptive Lecture Selection',
        'lecture-selection-rules.json',
        'full lecture, short segment, transcript, or remediation clip',
        'selection-only',
        '## Operator Review Workflow',
        'lecture-operator-review-workflow.json',
        'check-lecture-operator-review.ps1',
        'approved-for-publish',
        'Generated systems, generated instructors, and automated checks cannot approve',
        'media is rendered',
        'Instructor realism',
        'face/body consistency',
        'board occlusion',
        'gesture timing',
        'generated instructor disclosure',
        'Final package approval',
        '## Lecture Media Production Providers',
        'lecture-production-providers.json',
        'ComfyUI-automation',
        'Cloud providers',
        'downloaded, archived, and checksummed',
        'check-lecture-production-providers.ps1',
        '## Dry-Run Production Job',
        'build-lecture-production-job.ps1',
        'TTS, visuals, avatar, assembly, archive, and QA stages',
        'requires `sha256`',
        '## Local ComfyUI Adapter',
        'invoke-comfyui-production-adapter.ps1',
        'visuals, avatar, and assembly stages',
        'planned handoff path',
        'dry-run mode only',
        '## Rendered ComfyUI Avatar Fixture',
        'render-lecture-avatar-comfyui.ps1',
        'lecture-avatar-rendered-media.json',
        'local-comfyui+ffmpeg',
        '## Cloud Production Adapter Contracts',
        'invoke-cloud-production-adapter.ps1',
        'TTS, avatar, and video assembly',
        'values are always redacted',
        'downloaded to the subject content repo',
        'LECTURE_TTS_ENDPOINT',
        'lecture-audio-neural-tts.mp3',
        '## Rendered Audio Fixture',
        'render-lecture-audio-fixture.ps1',
        'lecture-rendered-media.json',
        'real short local WAV file',
        'not the final publishable lecture video',
        '## Generic Baseline And Single-Learner Adaptation',
        'shareable baseline lecture',
        'adapt the teaching session around one learner',
        '## Lecture Duration And Cadence',
        '`3000` seconds',
        '`2700` to `3300` seconds',
        '5-12 minute concept segments',
        'Short deterministic fixtures can remain 1-10 minutes',
        '## Chalkboard And Board Close-Up',
        'board close-up mode',
        '## Learning Environment And Note-Taking',
        'paper notebook and pen',
        'Rewrite notes after the lecture',
        '## Archive Manifest Update Tooling',
        'build-lecture-archive-manifest.ps1',
        'audio, video, captions, and package metadata',
        'planned required media stays a publish blocker',
        'requiresOperatorPublishGate',
        '## Operator Publish Gate Run',
        'render-lecture-publish-fixture.ps1',
        'run-lecture-publish-gate.ps1',
        'publish-ready path',
        'approved-for-publish',
        'required media is archived'
    )) {
        if (-not $document.Contains($marker)) {
            Add-CheckError $errors "Generated lecture video document missing source review marker: $marker"
        }
    }

    if ($persona.schemaVersion -ne 1) {
        Add-CheckError $errors 'Generated instructor persona policy schemaVersion must be 1.'
    }
    foreach ($field in @(
        'personaId',
        'disclosureLanguage',
        'voiceConsentRule',
        'likenessConsentRule',
        'allowedConsentValues',
        'toneRequirements',
        'prohibitedUses',
        'learnerFacingTransparency',
        'operatorReview'
    )) {
        if (-not (Test-HasText $persona.$field)) {
            Add-CheckError $errors "Generated instructor persona policy missing $field."
        }
    }
    if ($fixture.generatedInstructor.personaId -ne $persona.personaId) {
        Add-CheckError $errors 'Lecture fixture generated instructor personaId must match the approved persona policy.'
    }
    if ($fixture.generatedInstructor.disclosure -ne $persona.disclosureLanguage) {
        Add-CheckError $errors 'Lecture fixture generated instructor disclosure must match the approved persona policy.'
    }
    foreach ($consentValue in @($fixture.generatedInstructor.voiceConsent, $fixture.generatedInstructor.likenessConsent)) {
        if (@($persona.allowedConsentValues | Where-Object { $_ -eq $consentValue }).Count -ne 1) {
            Add-CheckError $errors "Lecture fixture uses unapproved generated instructor consent value: $consentValue"
        }
    }
    foreach ($requiredTone in @('clear', 'rigorous', 'supportive without false praise', 'specific about evidence')) {
        if (@($persona.toneRequirements | Where-Object { $_ -eq $requiredTone }).Count -ne 1) {
            Add-CheckError $errors "Generated instructor persona policy missing tone requirement: $requiredTone"
        }
    }
    foreach ($blockedUse in @('real-person voice cloning without explicit consent', 'real-person likeness cloning without explicit consent', 'undisclosed generated instruction')) {
        if (@($persona.prohibitedUses | Where-Object { $_ -eq $blockedUse }).Count -ne 1) {
            Add-CheckError $errors "Generated instructor persona policy missing prohibited use: $blockedUse"
        }
    }
    if ($archivePolicy.schemaVersion -ne 1) {
        Add-CheckError $errors 'Lecture media archive policy schemaVersion must be 1.'
    }
    if ($archivePolicy.localArchiveRoot -ne 'generated-lectures') {
        Add-CheckError $errors 'Lecture media archive policy must use generated-lectures as the subject repo archive root.'
    }
    if ($archivePolicy.checksumAlgorithm -ne 'sha256') {
        Add-CheckError $errors 'Lecture media archive policy must require sha256 checksums.'
    }
    if ($archivePolicy.renderedMediaGitPolicy -ne 'do-not-commit-rendered-media') {
        Add-CheckError $errors 'Lecture media archive policy must keep rendered media out of Git.'
    }
    if (-not ([string]$archivePolicy.largeFileStorageDecision).Contains('defer Git LFS or object storage')) {
        Add-CheckError $errors 'Lecture media archive policy must record the large-file storage decision.'
    }
    foreach ($statusValue in @('planned', 'rendered', 'archived')) {
        if (@($archivePolicy.allowedStatuses | Where-Object { $_ -eq $statusValue }).Count -ne 1) {
            Add-CheckError $errors "Lecture media archive policy missing allowed status: $statusValue"
        }
    }
    foreach ($fieldName in @('media[].assetId', 'media[].path', 'media[].sha256', 'media[].requiredForPublish')) {
        if (@($archivePolicy.requiredManifestFields | Where-Object { $_ -eq $fieldName }).Count -ne 1) {
            Add-CheckError $errors "Lecture media archive policy missing required manifest field: $fieldName"
        }
    }
    if (-not $gitignore.Contains('generated-lectures/**/media/')) {
        Add-CheckError $errors 'The subject repo .gitignore must exclude generated lecture media binaries.'
    }
    if ($accessibilityPolicy.schemaVersion -ne 1) {
        Add-CheckError $errors 'Lecture accessibility policy schemaVersion must be 1.'
    }
    foreach ($assetName in @('captions', 'transcript', 'chapters', 'slides', 'slideAltText')) {
        if (@($accessibilityPolicy.requiredAssets | Where-Object { $_ -eq $assetName }).Count -ne 1) {
            Add-CheckError $errors "Lecture accessibility policy missing required asset: $assetName"
        }
    }
    if ($accessibilityPolicy.captionRequirements.format -ne 'webvtt') {
        Add-CheckError $errors 'Lecture accessibility policy must require WebVTT captions.'
    }
    if ($accessibilityPolicy.transcriptRequirements.mustBeReadableWithoutVideo -ne $true) {
        Add-CheckError $errors 'Lecture accessibility policy must require transcripts readable without video.'
    }
    if ($accessibilityPolicy.chapterRequirements.firstChapterStartSecond -ne 0) {
        Add-CheckError $errors 'Lecture accessibility policy must require chapters to start at second 0.'
    }
    if ($accessibilityPolicy.slideRequirements.minimumAltTextCharacters -lt 20) {
        Add-CheckError $errors 'Lecture accessibility policy must require meaningful slide alt text.'
    }
    if ($qualityRubric.schemaVersion -ne 1) {
        Add-CheckError $errors 'Lecture video quality rubric schemaVersion must be 1.'
    }
    if ($qualityRubric.minimumPublishScore -lt 3) {
        Add-CheckError $errors 'Lecture video quality rubric must require a publishable baseline score.'
    }
    if ($selectionRules.schemaVersion -ne 1) {
        Add-CheckError $errors 'Lecture selection rules schemaVersion must be 1.'
    }
    if (-not ([string]$selectionRules.passiveWatchPolicy).Contains('Never select or mark mastery from watch completion alone')) {
        Add-CheckError $errors 'Lecture selection rules must forbid passive watch completion as mastery.'
    }
    foreach ($mode in @('full-lecture', 'short-segment', 'transcript', 'remediation-clip')) {
        if (@($selectionRules.allowedModes | Where-Object { $_ -eq $mode }).Count -ne 1) {
            Add-CheckError $errors "Lecture selection rules missing allowed mode: $mode"
        }
        if (@($selectionRules.modes | Where-Object { $_.mode -eq $mode }).Count -ne 1) {
            Add-CheckError $errors "Lecture selection rules missing mode definition: $mode"
        }
    }
    if ($operatorReviewWorkflow.schemaVersion -ne 1) {
        Add-CheckError $errors 'Lecture operator review workflow schemaVersion must be 1.'
    }
    if ($operatorReviewWorkflow.workflowId -ne 'lecture-operator-review-v1') {
        Add-CheckError $errors 'Lecture operator review workflow must use the approved workflowId.'
    }
    if (-not ([string]$operatorReviewWorkflow.selfApprovalPolicy).Contains('cannot approve')) {
        Add-CheckError $errors 'Lecture operator review workflow must block generated-system self approval.'
    }
    foreach ($statusValue in @('pending', 'approved', 'changes-requested', 'rejected')) {
        if (@($operatorReviewWorkflow.allowedStatuses | Where-Object { $_ -eq $statusValue }).Count -ne 1) {
            Add-CheckError $errors "Lecture operator review workflow missing allowed status: $statusValue"
        }
    }
    foreach ($publishStatus in @('not-ready', 'approved-for-publish', 'changes-requested', 'rejected')) {
        if (@($operatorReviewWorkflow.allowedPublishStatuses | Where-Object { $_ -eq $publishStatus }).Count -ne 1) {
            Add-CheckError $errors "Lecture operator review workflow missing publish status: $publishStatus"
        }
    }
    foreach ($stageId in @('script', 'visuals', 'media', 'accessibility', 'license-persona', 'instructor-realism', 'final-package')) {
        $workflowStage = @($operatorReviewWorkflow.requiredStages | Where-Object { $_.stageId -eq $stageId })
        if ($workflowStage.Count -ne 1) {
            Add-CheckError $errors "Lecture operator review workflow missing required stage: $stageId"
        }
        elseif (@($workflowStage[0].requiredEvidence).Count -lt 2) {
            Add-CheckError $errors "Lecture operator review workflow stage needs evidence requirements: $stageId"
        }
    }
    $realismWorkflowStage = @($operatorReviewWorkflow.requiredStages | Where-Object { $_.stageId -eq 'instructor-realism' })
    if ($realismWorkflowStage.Count -eq 1) {
        foreach ($requiredEvidence in @('face/body consistency', 'front-row framing', 'board readability', 'board occlusion check', 'board close-up usefulness', 'gesture timing', 'no whole-frame teaching text overlays', 'generated instructor disclosure', 'human emotional delivery check')) {
            if (@($realismWorkflowStage[0].requiredEvidence | Where-Object { $_ -eq $requiredEvidence }).Count -ne 1) {
                Add-CheckError $errors "Lecture operator review realism stage missing evidence requirement: $requiredEvidence"
            }
        }
    }
    $workflowEvidenceRequirements = @{
        visuals = @('board-content synchronization')
        media = @('audio naturalness check', 'board-local pause prompt timing')
        'final-package' = @('learner usefulness review')
    }
    foreach ($stageName in $workflowEvidenceRequirements.Keys) {
        $workflowStage = @($operatorReviewWorkflow.requiredStages | Where-Object { $_.stageId -eq $stageName })
        if ($workflowStage.Count -eq 1) {
            foreach ($requiredEvidence in $workflowEvidenceRequirements[$stageName]) {
                if (@($workflowStage[0].requiredEvidence | Where-Object { $_ -eq $requiredEvidence }).Count -ne 1) {
                    Add-CheckError $errors "Lecture operator review stage missing evidence requirement $requiredEvidence`: $stageName"
                }
            }
        }
    }
    if ($productionProviders.schemaVersion -ne 1) {
        Add-CheckError $errors 'Lecture production providers schemaVersion must be 1.'
    }
    if ($productionProviders.defaultProviderId -ne 'local-comfyui') {
        Add-CheckError $errors 'Lecture production providers should default to local ComfyUI production.'
    }
    if (-not ([string]$productionProviders.credentialPolicy).Contains('No provider credentials')) {
        Add-CheckError $errors 'Lecture production providers must forbid committed credentials.'
    }
    if (-not ([string]$productionProviders.artifactPolicy).Contains('generated-lectures') -or -not ([string]$productionProviders.artifactPolicy).Contains('SHA-256')) {
        Add-CheckError $errors 'Lecture production providers must require subject repo archive and SHA-256 checksums.'
    }
    $localComfyProvider = @($productionProviders.providers | Where-Object { $_.providerId -eq 'local-comfyui' })
    if ($localComfyProvider.Count -ne 1) {
        Add-CheckError $errors 'Lecture production providers missing local-comfyui profile.'
    }
    else {
        if ($localComfyProvider[0].integrationRepo -ne 'ComfyUI-automation') {
            Add-CheckError $errors 'local-comfyui profile must reference ComfyUI-automation.'
        }
        foreach ($capability in @('visual-render', 'avatar-render', 'video-assembly')) {
            if (@($localComfyProvider[0].capabilities | Where-Object { $_ -eq $capability }).Count -ne 1) {
                Add-CheckError $errors "local-comfyui profile missing capability: $capability"
            }
        }
        foreach ($stage in @('visuals', 'avatar', 'assembly')) {
            if (@($localComfyProvider[0].workflowMappings | Where-Object { $_.stage -eq $stage -and (Test-HasText $_.workflowPath) }).Count -ne 1) {
                Add-CheckError $errors "local-comfyui profile missing workflow mapping: $stage"
            }
        }
    }
    $localComfyTtsProvider = @($productionProviders.providers | Where-Object { $_.providerId -eq 'local-comfyui-tts' })
    if ($localComfyTtsProvider.Count -ne 1) {
        Add-CheckError $errors 'Lecture production providers missing local-comfyui-tts profile.'
    }
    else {
        if ($localComfyTtsProvider[0].type -ne 'local' -or $localComfyTtsProvider[0].enabledByDefault -ne $false) {
            Add-CheckError $errors 'local-comfyui-tts must be a disabled local provider until readiness passes.'
        }
        foreach ($capability in @('tts', 'neural-tts', 'voice-design')) {
            if (@($localComfyTtsProvider[0].capabilities | Where-Object { $_ -eq $capability }).Count -ne 1) {
                Add-CheckError $errors "local-comfyui-tts profile missing capability: $capability"
            }
        }
        if (@($localComfyTtsProvider[0].credentialEnvVars).Count -ne 0) {
            Add-CheckError $errors 'local-comfyui-tts must not require cloud credentials.'
        }
        if (@($localComfyTtsProvider[0].workflowMappings | Where-Object { $_.stage -eq 'tts' -and (Test-HasText $_.workflowPath) }).Count -ne 1) {
            Add-CheckError $errors 'local-comfyui-tts profile missing workflow mapping: tts'
        }
        if ($localComfyTtsProvider[0].readiness.approvedWorkflowMode -ne 'generic-voice-design-non-clone') {
            Add-CheckError $errors 'local-comfyui-tts profile must require generic non-clone voice design.'
        }
        foreach ($disallowedClass in @('FB_Qwen3TTSVoiceClone', 'FB_Qwen3TTSVoiceClonePrompt', 'FB_Qwen3TTSCustomVoice')) {
            if (@($localComfyTtsProvider[0].readiness.disallowedNodeClasses | Where-Object { $_ -eq $disallowedClass }).Count -ne 1) {
                Add-CheckError $errors "local-comfyui-tts profile missing disallowed node class: $disallowedClass"
            }
        }
        if (@($localComfyTtsProvider[0].readiness.disallowedNodeClasses | Where-Object { $_ -like '*VoiceClone*' }).Count -lt 1) {
            Add-CheckError $errors 'local-comfyui-tts profile must disallow voice clone nodes.'
        }
    }
    $localComfyMotionProvider = @($productionProviders.providers | Where-Object { $_.providerId -eq 'local-comfyui-motion' })
    if ($localComfyMotionProvider.Count -ne 1) {
        Add-CheckError $errors 'Lecture production providers missing local-comfyui-motion profile.'
    }
    else {
        if ($localComfyMotionProvider[0].type -ne 'local' -or $localComfyMotionProvider[0].enabledByDefault -ne $false) {
            Add-CheckError $errors 'local-comfyui-motion must be a disabled local provider while it is a spike.'
        }
        foreach ($capability in @('instructor-motion', 'portrait-animation', 'pre-lip-sync-motion')) {
            if (@($localComfyMotionProvider[0].capabilities | Where-Object { $_ -eq $capability }).Count -ne 1) {
                Add-CheckError $errors "local-comfyui-motion profile missing capability: $capability"
            }
        }
        if ($localComfyMotionProvider[0].readiness.approvedWorkflowMode -ne 'pre-lip-sync-subtle-motion-spike') {
            Add-CheckError $errors 'local-comfyui-motion profile must declare the pre-lip-sync subtle motion spike mode.'
        }
        foreach ($pipelineId in @('liveportrait', 'sadtalker')) {
            if (@($localComfyMotionProvider[0].readiness.candidatePipelines | Where-Object { $_.pipelineId -eq $pipelineId }).Count -ne 1) {
                Add-CheckError $errors "local-comfyui-motion profile missing candidate pipeline: $pipelineId"
            }
        }
    }
    $localComfyLipSyncProvider = @($productionProviders.providers | Where-Object { $_.providerId -eq 'local-comfyui-lipsync' })
    if ($localComfyLipSyncProvider.Count -ne 1) {
        Add-CheckError $errors 'Lecture production providers missing local-comfyui-lipsync profile.'
    }
    else {
        if ($localComfyLipSyncProvider[0].type -ne 'local' -or $localComfyLipSyncProvider[0].enabledByDefault -ne $false) {
            Add-CheckError $errors 'local-comfyui-lipsync must be a disabled local provider while it is a spike.'
        }
        foreach ($capability in @('lip-sync', 'audio-driven-mouth', 'face-crop-sync')) {
            if (@($localComfyLipSyncProvider[0].capabilities | Where-Object { $_ -eq $capability }).Count -ne 1) {
                Add-CheckError $errors "local-comfyui-lipsync profile missing capability: $capability"
            }
        }
        if ($localComfyLipSyncProvider[0].readiness.approvedWorkflowMode -ne 'audio-driven-lip-sync-spike') {
            Add-CheckError $errors 'local-comfyui-lipsync profile must declare the audio-driven lip-sync spike mode.'
        }
        foreach ($pipelineId in @('musetalk', 'wav2lip')) {
            if (@($localComfyLipSyncProvider[0].readiness.candidatePipelines | Where-Object { $_.pipelineId -eq $pipelineId }).Count -ne 1) {
                Add-CheckError $errors "local-comfyui-lipsync profile missing candidate pipeline: $pipelineId"
            }
        }
    }
    foreach ($cloudProviderId in @('cloud-tts', 'cloud-avatar', 'cloud-video-assembly')) {
        $cloudProvider = @($productionProviders.providers | Where-Object { $_.providerId -eq $cloudProviderId -and $_.type -eq 'cloud' })
        if ($cloudProvider.Count -ne 1) {
            Add-CheckError $errors "Lecture production providers missing cloud profile: $cloudProviderId"
        }
        elseif ($cloudProvider[0].enabledByDefault -ne $false) {
            Add-CheckError $errors "Cloud production provider must be opt-in: $cloudProviderId"
        }
    }
    foreach ($stage in @('tts', 'visuals', 'avatar', 'motion', 'lipsync', 'assembly')) {
        if (@($productionProviders.routing | Where-Object { $_.stage -eq $stage }).Count -ne 1) {
            Add-CheckError $errors "Lecture production providers missing route: $stage"
        }
    }
    $ttsRoute = @($productionProviders.routing | Where-Object { $_.stage -eq 'tts' } | Select-Object -First 1)
    if ($ttsRoute.Count -eq 1 -and $ttsRoute[0].preferredProviderId -ne 'local-comfyui-tts') {
        Add-CheckError $errors 'TTS production route must prefer local-comfyui-tts after operator listening review.'
    }
    if ($ttsRoute.Count -eq 1 -and @($ttsRoute[0].fallbackProviderIds | Where-Object { $_ -eq 'cloud-tts' }).Count -ne 1) {
        Add-CheckError $errors 'TTS production route must keep cloud-tts as the fallback provider.'
    }
    $motionRoute = @($productionProviders.routing | Where-Object { $_.stage -eq 'motion' } | Select-Object -First 1)
    if ($motionRoute.Count -eq 1 -and $motionRoute[0].preferredProviderId -ne 'local-comfyui-motion') {
        Add-CheckError $errors 'Motion production route must prefer local-comfyui-motion.'
    }
    $lipSyncRoute = @($productionProviders.routing | Where-Object { $_.stage -eq 'lipsync' } | Select-Object -First 1)
    if ($lipSyncRoute.Count -eq 1 -and $lipSyncRoute[0].preferredProviderId -ne 'local-comfyui-lipsync') {
        Add-CheckError $errors 'Lip-sync production route must prefer local-comfyui-lipsync.'
    }
    if ($renderedMedia.schemaVersion -ne 1) {
        Add-CheckError $errors 'Rendered lecture media metadata schemaVersion must be 1.'
    }
    if ($renderedMedia.packageId -ne $fixture.packageId) {
        Add-CheckError $errors 'Rendered lecture media metadata packageId must match the lecture fixture.'
    }
    if ($renderedMedia.assetId -ne 'lecture-audio-wav-fixture') {
        Add-CheckError $errors 'Rendered lecture media metadata must describe the WAV audio fixture.'
    }
    if ($renderedMedia.status -ne 'archived') {
        Add-CheckError $errors 'Rendered lecture media metadata must be archived.'
    }
    if ($renderedMedia.sha256 -notmatch '^[a-f0-9]{64}$') {
        Add-CheckError $errors 'Rendered lecture media metadata must include a lowercase SHA-256 checksum.'
    }
    foreach ($dimensionId in @('video-pacing', 'worked-examples', 'active-recall', 'misconception-checks', 'accessibility', 'assessment-handoff', 'learning-environment', 'board-clarity', 'instructor-realism', 'motion-lipsync-qa', 'adaptive-continuity')) {
        $dimension = @($qualityRubric.dimensions | Where-Object { $_.dimensionId -eq $dimensionId })
        if ($dimension.Count -ne 1) {
            Add-CheckError $errors "Lecture video quality rubric missing dimension: $dimensionId"
        }
        elseif (-not (Test-HasText $dimension[0].publishExpectation)) {
            Add-CheckError $errors "Lecture video quality rubric dimension missing publish expectation: $dimensionId"
        }
    }
    $motionLipSyncDimension = @($qualityRubric.dimensions | Where-Object { $_.dimensionId -eq 'motion-lipsync-qa' })
    if ($motionLipSyncDimension.Count -eq 1) {
        $motionLipSyncExpectation = ([string]$motionLipSyncDimension[0].publishExpectation).ToLowerInvariant()
        foreach ($token in @('lip-sync timing', 'gaze direction', 'head and hand motion naturalness', 'board-writing gesture synchronization')) {
            if (-not $motionLipSyncExpectation.Contains($token)) {
                Add-CheckError $errors "Lecture motion-lipsync QA rubric missing expectation token: $token"
            }
        }
    }
    $fixtureScore = @($qualityRubric.fixtureScores | Where-Object { $_.packageId -eq $fixture.packageId })
    if ($fixtureScore.Count -ne 1) {
        Add-CheckError $errors 'Lecture video quality rubric must include scores for the deterministic fixture.'
    }
    else {
        foreach ($dimensionId in @('video-pacing', 'worked-examples', 'active-recall', 'misconception-checks', 'accessibility', 'assessment-handoff', 'learning-environment', 'board-clarity', 'instructor-realism', 'motion-lipsync-qa', 'adaptive-continuity')) {
            if ($fixtureScore[0].scores.$dimensionId -lt $qualityRubric.minimumPublishScore) {
                Add-CheckError $errors "Lecture fixture score is below publish baseline for: $dimensionId"
            }
        }
    }

    foreach ($field in @(
        'packageId',
        'subjectOwnedAssetRoot',
        'contentSource',
        'objectiveIds',
        'deliveryPlan',
        'performancePlan',
        'transcript',
        'captions',
        'media',
        'licenseAudit',
        'qaStatus',
        'operatorReview'
    )) {
        if (@($schema.lecturePackage.required | Where-Object { $_ -eq $field }).Count -ne 1) {
            Add-CheckError $errors "Lecture video schema missing required field: $field"
        }
    }

    if ($fixture.schemaVersion -ne 1) {
        Add-CheckError $errors 'Lecture video fixture schemaVersion must be 1.'
    }
    if (-not (Test-HasText $fixture.packageId)) {
        Add-CheckError $errors 'Lecture video fixture missing packageId.'
    }
    if ($fixture.durationSeconds -lt 60 -or $fixture.durationSeconds -gt 600) {
        Add-CheckError $errors 'Lecture video fixture should be a short deterministic lesson between 60 and 600 seconds.'
    }
    if ($fixture.deliveryPlan.audienceMode -ne 'shareable-baseline-with-single-learner-adaptation') {
        Add-CheckError $errors 'Lecture fixture must distinguish the shareable baseline from single-learner adaptation.'
    }
    if ($fixture.deliveryPlan.fullLectureDuration.targetSeconds -ne 3000 -or $fixture.deliveryPlan.fullLectureDuration.minimumSeconds -ne 2700 -or $fixture.deliveryPlan.fullLectureDuration.maximumSeconds -ne 3300) {
        Add-CheckError $errors 'Lecture fixture must encode the 45-55 minute full-lecture duration target.'
    }
    if ($fixture.deliveryPlan.segmentCadence.minimumSegmentSeconds -lt 300 -or $fixture.deliveryPlan.segmentCadence.maximumSegmentSeconds -gt 720) {
        Add-CheckError $errors 'Lecture fixture segment cadence must keep full lectures in 5-12 minute active segments.'
    }
    if ($fixture.deliveryPlan.segmentCadence.checkpointEverySeconds -lt 360 -or $fixture.deliveryPlan.segmentCadence.checkpointEverySeconds -gt 600) {
        Add-CheckError $errors 'Lecture fixture must schedule active recall roughly every 6-10 minutes.'
    }
    foreach ($requiredStep in @('intro-lecture', 'diagnostic-check', 'materials-and-curriculum', 'guided-practice', 'progress-assessment', 'next-lecture-plan')) {
        if (@($fixture.deliveryPlan.sequence | Where-Object { $_ -eq $requiredStep }).Count -ne 1) {
            Add-CheckError $errors "Lecture fixture missing teaching sequence step: $requiredStep"
        }
    }
    foreach ($requiredPrompt in @('quiet', 'paper notebook', 'pen', 'pause', 'rewrite')) {
        if (-not ((@($fixture.deliveryPlan.learningEnvironmentPrompts) -join ' ').ToLowerInvariant().Contains($requiredPrompt))) {
            Add-CheckError $errors "Lecture fixture learning environment prompts must include: $requiredPrompt"
        }
    }
    foreach ($requiredAdaptation in @('cover every required objective', 'Adapt examples', 'Do not treat watch time', 'plan the next lecture')) {
        if (-not ((@($fixture.deliveryPlan.adaptationRequirements) -join ' ').Contains($requiredAdaptation))) {
            Add-CheckError $errors "Lecture fixture adaptation requirements must include: $requiredAdaptation"
        }
    }
    if ($fixture.deliveryPlan.boardPlan.closeUpAvailable -ne $true) {
        Add-CheckError $errors 'Lecture fixture must make board close-up available.'
    }
    if (-not ([string]$fixture.deliveryPlan.boardPlan.defaultView).Contains('chalkboard')) {
        Add-CheckError $errors 'Lecture fixture board plan must use a chalkboard-style default view.'
    }
    if (@($fixture.deliveryPlan.boardPlan.moments).Count -lt 3) {
        Add-CheckError $errors 'Lecture fixture board plan must include multiple board moments.'
    }
    $performancePlan = Get-PropertyValue $fixture 'performancePlan'
    $audioProfile = Get-PropertyValue $performancePlan 'audioProfile'
    $voiceStyle = [string](Get-PropertyValue $audioProfile 'voiceStyle')
    if (-not (Test-HasText $voiceStyle) -or -not $voiceStyle.ToLowerInvariant().Contains('human')) {
        Add-CheckError $errors 'Lecture performance plan must require human-sounding instructor audio.'
    }
    $instructorGender = ([string](Get-PropertyValue -InputObject $fixture.generatedInstructor -Name 'gender')).ToLowerInvariant()
    if (@('male', 'female', 'neutral', 'nonbinary') -notcontains $instructorGender) {
        Add-CheckError $errors 'Generated instructor must declare a supported gender for voice matching.'
    }
    $expectedVoiceGender = Get-ExpectedInstructorVoiceGender -InstructorGender $instructorGender
    if ([string](Get-PropertyValue -InputObject $fixture.generatedInstructor -Name 'voiceMatchPolicy') -ne 'match-generated-instructor-gender') {
        Add-CheckError $errors 'Generated instructor must declare the gender-to-voice match policy.'
    }
    if ([string](Get-PropertyValue -InputObject $audioProfile -Name 'voiceMatchPolicy') -ne 'match-generated-instructor-gender') {
        Add-CheckError $errors 'Lecture audio profile must declare the gender-to-voice match policy.'
    }
    if ([string](Get-PropertyValue -InputObject $audioProfile -Name 'targetInstructorGender') -ne $instructorGender) {
        Add-CheckError $errors 'Lecture audio profile targetInstructorGender must match the generated instructor gender.'
    }
    if ([string](Get-PropertyValue -InputObject $audioProfile -Name 'targetVoiceGender') -ne $expectedVoiceGender) {
        Add-CheckError $errors 'Lecture audio profile targetVoiceGender must match the generated instructor gender.'
    }
    $targetVoiceText = (@(
        (Get-PropertyValue -InputObject $audioProfile -Name 'voiceStyle'),
        (Get-PropertyValue -InputObject $audioProfile -Name 'targetVoiceRegister')
    ) -join ' ').ToLowerInvariant()
    foreach ($voiceToken in @(Get-ExpectedInstructorVoiceTokens -InstructorGender $instructorGender)) {
        if (-not $targetVoiceText.Contains($voiceToken)) {
            Add-CheckError $errors "Lecture audio profile missing expected voice token: $voiceToken"
        }
    }
    if (@((Get-PropertyValue $audioProfile 'emotionTargets') | Where-Object { Test-HasText $_ }).Count -lt 3) {
        Add-CheckError $errors 'Lecture performance plan must include at least three emotional delivery targets.'
    }
    if (@((Get-PropertyValue $audioProfile 'prosodyDirectives') | Where-Object { Test-HasText $_ }).Count -lt 3) {
        Add-CheckError $errors 'Lecture performance plan must include at least three prosody directives.'
    }
    $ttsRequirements = @((Get-PropertyValue $audioProfile 'ttsRequirements') | Where-Object { Test-HasText $_ })
    if ($ttsRequirements.Count -lt 3 -or -not (($ttsRequirements -join ' ').ToLowerInvariant().Contains('local archive'))) {
        Add-CheckError $errors 'Lecture performance plan must describe TTS requirements and local audio archival.'
    }
    $pausePrompts = @((Get-PropertyValue $performancePlan 'pausePrompts') | Where-Object { $null -ne $_ })
    if ($pausePrompts.Count -lt 1) {
        Add-CheckError $errors 'Lecture performance plan must include at least one timed pause prompt.'
    }
    $pauseMatchedRecall = $false
    foreach ($pausePrompt in $pausePrompts) {
        $pauseId = [string](Get-PropertyValue $pausePrompt 'promptId')
        if (-not (Test-HasText $pauseId)) {
            Add-CheckError $errors 'Lecture pause prompt is missing promptId.'
        }
        if ([int](Get-PropertyValue $pausePrompt 'durationSeconds') -lt 5) {
            Add-CheckError $errors "Lecture pause prompt must give the learner at least five seconds: $pauseId"
        }
        foreach ($field in @('prompt', 'overlayText', 'resumeCue', 'boardState')) {
            if (-not (Test-HasText (Get-PropertyValue $pausePrompt $field))) {
                Add-CheckError $errors "Lecture pause prompt missing $field`: $pauseId"
            }
        }

        $pauseSecond = [int](Get-PropertyValue $pausePrompt 'timeSecond')
        foreach ($scene in @($fixture.storyboard)) {
            if (
                (Test-HasText $scene.activeRecallPrompt) -and
                $pauseSecond -ge [int]$scene.startSecond -and
                $pauseSecond -lt [int]$scene.endSecond
            ) {
                $pauseMatchedRecall = $true
            }
        }
    }
    if (-not $pauseMatchedRecall) {
        Add-CheckError $errors 'Lecture pause prompts must align with an active-recall storyboard scene.'
    }
    $visualSync = Get-PropertyValue $performancePlan 'visualSync'
    $boardStates = @((Get-PropertyValue $visualSync 'boardStates') | Where-Object { $null -ne $_ })
    if ($boardStates.Count -lt @($fixture.storyboard).Count) {
        Add-CheckError $errors 'Lecture visual sync must include board states for each storyboard scene.'
    }
    foreach ($boardState in $boardStates) {
        $stateId = [string](Get-PropertyValue $boardState 'stateId')
        if (-not (Test-HasText $stateId)) {
            Add-CheckError $errors 'Lecture visual sync board state is missing stateId.'
        }
        if (@((Get-PropertyValue $boardState 'boardText') | Where-Object { Test-HasText $_ }).Count -lt 1) {
            Add-CheckError $errors "Lecture visual sync board state must include board text: $stateId"
        }
        if (-not (Test-HasText (Get-PropertyValue $boardState 'instructorAction'))) {
            Add-CheckError $errors "Lecture visual sync board state must describe instructor action: $stateId"
        }
    }
    foreach ($scene in @($fixture.storyboard)) {
        $covered = @($boardStates | Where-Object {
            [int](Get-PropertyValue $_ 'startSecond') -le [int]$scene.startSecond -and
            [int](Get-PropertyValue $_ 'endSecond') -ge [int]$scene.endSecond
        })
        if ($covered.Count -lt 1) {
            Add-CheckError $errors "Lecture visual sync must cover storyboard scene: $($scene.sceneId)"
        }
    }
    if (-not ([string](Get-PropertyValue $visualSync 'minimumBoardStateCoverage')).ToLowerInvariant().Contains('storyboard')) {
        Add-CheckError $errors 'Lecture visual sync must state storyboard coverage expectations.'
    }
    $staticFramePolicy = [string](Get-PropertyValue $visualSync 'staticFramePolicy')
    if (-not $staticFramePolicy.ToLowerInvariant().Contains('static') -or -not $staticFramePolicy.ToLowerInvariant().Contains('placeholder')) {
        Add-CheckError $errors 'Lecture visual sync must reject static placeholder video as publish-ready.'
    }
    if ($fixture.contentSource.sourceId -ne 'game-development') {
        Add-CheckError $errors 'Lecture video fixture must use the game-development content source.'
    }
    if ($fixture.contentSource.sourcePath -ne 'study-plans\courses\GDEV-101-game-design-foundations.md') {
        Add-CheckError $errors 'Lecture video fixture must cite the GDEV-101 course source path.'
    }
    if ((Split-Path -Leaf $fixtureContentRoot) -ne 'open-education-game-development') {
        Add-CheckError $errors 'Lecture video fixture must be loaded from the open-education-game-development content repo.'
    }
    if ($fixture.subjectOwnedAssetRoot -ne 'generated-lectures\gdev-101-design-vocabulary') {
        Add-CheckError $errors 'Lecture video fixture must declare the subject-owned generated lecture asset root.'
    }
    if (@($fixture.objectiveIds | Where-Object { $_ -eq 'game-development:objectives/course/gdev-101/design-vocabulary' }).Count -ne 1) {
        Add-CheckError $errors 'Lecture video fixture must target the GDEV-101 design vocabulary objective.'
    }
    if ($fixture.generatedInstructor.realPersonClone -ne $false) {
        Add-CheckError $errors 'Generated instructor must not clone a real person.'
    }
    foreach ($field in @('gender', 'disclosure', 'voiceConsent', 'likenessConsent', 'voiceMatchPolicy', 'tone')) {
        if (-not (Test-HasText (Get-PropertyValue -InputObject $fixture.generatedInstructor -Name $field))) {
            Add-CheckError $errors "Generated instructor missing $field."
        }
    }
    foreach ($field in @('presentationStyle', 'renderReadiness')) {
        if (-not (Test-HasText $fixture.generatedInstructor.realismProfile.$field)) {
            Add-CheckError $errors "Generated instructor realism profile missing $field."
        }
    }
    if ($fixture.generatedInstructor.realismProfile.renderReadiness -ne 'local-comfyui-avatar-keyframe') {
        Add-CheckError $errors 'Generated instructor realism profile must point at the local ComfyUI avatar keyframe render.'
    }
    foreach ($listField in @('visualFidelityTargets', 'movementPlan', 'boardInteractionPlan')) {
        if (@($fixture.generatedInstructor.realismProfile.$listField).Count -lt 3) {
            Add-CheckError $errors "Generated instructor realism profile needs at least three entries for $listField."
        }
    }

    if (@($fixture.citations).Count -lt 1) {
        Add-CheckError $errors 'Lecture video fixture must include at least one citation.'
    }
    foreach ($citation in @($fixture.citations)) {
        foreach ($field in @('citationId', 'sourceId', 'sourceRepo', 'sourcePath', 'claim')) {
            if (-not (Test-HasText $citation.$field)) {
                Add-CheckError $errors "Citation missing $field."
            }
        }
    }
    if (-not ([string]$fixture.script.text).Contains('[course-gdev-101]')) {
        Add-CheckError $errors 'Lecture script must include the deterministic course citation marker.'
    }
    if (@($fixture.storyboard).Count -lt 3) {
        Add-CheckError $errors 'Lecture storyboard must include at least three scenes.'
    }
    if (@($fixture.storyboard | Where-Object { Test-HasText $_.activeRecallPrompt }).Count -lt 1) {
        Add-CheckError $errors 'Lecture storyboard must include at least one active recall prompt.'
    }
    if (-not (Test-HasText $fixture.transcript.text)) {
        Add-CheckError $errors 'Lecture fixture must include transcript text.'
    }
    if ($fixture.transcript.format -ne $accessibilityPolicy.transcriptRequirements.format) {
        Add-CheckError $errors 'Lecture fixture transcript format must match the accessibility policy.'
    }
    if (-not (Test-HasText $fixture.transcript.language)) {
        Add-CheckError $errors 'Lecture fixture transcript must declare a language.'
    }
    if ($fixture.captions.format -ne 'webvtt' -or $fixture.captions.text -notlike 'WEBVTT*') {
        Add-CheckError $errors 'Lecture fixture captions must be WebVTT.'
    }
    if (-not (Test-HasText $fixture.captions.language)) {
        Add-CheckError $errors 'Lecture fixture captions must declare a language.'
    }
    if ($fixture.captions.text -notmatch '\d\d:\d\d:\d\d\.\d\d\d\s+-->\s+\d\d:\d\d:\d\d\.\d\d\d') {
        Add-CheckError $errors 'Lecture fixture captions must include WebVTT timestamps.'
    }
    if (@($fixture.chapters).Count -lt 2) {
        Add-CheckError $errors 'Lecture fixture must include chapters.'
    }
    if (@($fixture.chapters | Where-Object { $_.startSecond -eq 0 }).Count -lt 1) {
        Add-CheckError $errors 'Lecture fixture chapters must include a chapter starting at second 0.'
    }
    foreach ($chapter in @($fixture.chapters)) {
        if (-not (Test-HasText $chapter.title)) {
            Add-CheckError $errors 'Lecture fixture chapter is missing title.'
        }
        if ($chapter.startSecond -lt 0 -or $chapter.startSecond -ge $fixture.durationSeconds) {
            Add-CheckError $errors "Lecture fixture chapter is outside the lecture duration: $($chapter.title)"
        }
    }
    foreach ($slide in @($fixture.slides)) {
        foreach ($field in @('slideId', 'title', 'path', 'altText', 'attribution')) {
            if (-not (Test-HasText $slide.$field)) {
                Add-CheckError $errors "Slide missing $field."
            }
        }
        if (([string]$slide.altText).Length -lt $accessibilityPolicy.slideRequirements.minimumAltTextCharacters) {
            Add-CheckError $errors "Slide alt text is too short to be meaningful: $($slide.slideId)"
        }
    }
    if (@($fixture.media).Count -lt 1) {
        Add-CheckError $errors 'Lecture fixture must declare planned or rendered media assets.'
    }
    foreach ($media in @($fixture.media)) {
        foreach ($field in @('assetId', 'type', 'path', 'sha256', 'status')) {
            if (-not (Test-HasText $media.$field)) {
                Add-CheckError $errors "Media asset missing $field."
            }
        }
        if (@('planned', 'rendered', 'archived') -notcontains $media.status) {
            Add-CheckError $errors "Media asset has invalid status: $($media.status)"
        }
        if (-not ([string]$media.path).StartsWith($fixtureAssetRoot)) {
            Add-CheckError $errors "Media asset must be stored under the subject-owned lecture folder: $($media.assetId)"
        }
        if ($media.status -ne 'planned' -and $media.sha256 -notmatch '^[a-fA-F0-9]{64}$') {
            Add-CheckError $errors "Rendered or archived media asset must use a 64-character sha256: $($media.assetId)"
        }
    }
    $audioFixtureMedia = @($fixture.media | Where-Object { $_.assetId -eq $renderedMedia.assetId })
    if ($audioFixtureMedia.Count -ne 1) {
        Add-CheckError $errors 'Lecture fixture media array must include the rendered WAV audio fixture.'
    }
    else {
        if ($audioFixtureMedia[0].path -ne $renderedMedia.path) {
            Add-CheckError $errors 'Lecture fixture rendered WAV path must match rendered media metadata.'
        }
        if ($audioFixtureMedia[0].sha256 -ne $renderedMedia.sha256) {
            Add-CheckError $errors 'Lecture fixture rendered WAV sha256 must match rendered media metadata.'
        }
        if ($audioFixtureMedia[0].requiredForPublish -ne $false) {
            Add-CheckError $errors 'Rendered WAV fixture must not be treated as final required publish media.'
        }
    }
    $neuralTtsFixtureMedia = @($fixture.media | Where-Object { $_.assetId -eq $neuralTtsRenderedMedia.assetId })
    if ($neuralTtsFixtureMedia.Count -ne 1) {
        Add-CheckError $errors 'Lecture fixture media array must include the archived neural TTS candidate.'
    }
    else {
        if ($neuralTtsFixtureMedia[0].path -ne $neuralTtsRenderedMedia.path) {
            Add-CheckError $errors 'Lecture fixture neural TTS path must match neural TTS metadata.'
        }
        if ($neuralTtsFixtureMedia[0].sha256 -ne $neuralTtsRenderedMedia.sha256) {
            Add-CheckError $errors 'Lecture fixture neural TTS sha256 must match neural TTS metadata.'
        }
        if ($neuralTtsFixtureMedia[0].requiredForPublish -ne $false) {
            Add-CheckError $errors 'Neural TTS candidate must remain blocked from final publish until operator listening review passes.'
        }
    }
    $avatarFixtureMedia = @($fixture.media | Where-Object { $_.assetId -eq $avatarRenderedMedia.assetId })
    if ($avatarFixtureMedia.Count -ne 1) {
        Add-CheckError $errors 'Lecture fixture media array must include the rendered local ComfyUI avatar image.'
    }
    else {
        if ($avatarFixtureMedia[0].path -ne $avatarRenderedMedia.path) {
            Add-CheckError $errors 'Lecture fixture avatar path must match rendered avatar metadata.'
        }
        if ($avatarFixtureMedia[0].sha256 -ne $avatarRenderedMedia.sha256) {
            Add-CheckError $errors 'Lecture fixture avatar sha256 must match rendered avatar metadata.'
        }
        if ($avatarFixtureMedia[0].requiredForPublish -ne $false) {
            Add-CheckError $errors 'Rendered ComfyUI avatar keyframe should not be treated as final required publish media.'
        }
    }
    if ($fixture.licenseAudit.status -ne 'pass') {
        Add-CheckError $errors 'Lecture fixture license audit must pass.'
    }
    if ($fixture.licenseAudit.externalHostDependency -ne $false) {
        Add-CheckError $errors 'Lecture fixture must not depend on an external video host.'
    }
    if (@($fixture.licenseAudit.blockedMaterials).Count -ne 0) {
        Add-CheckError $errors 'Lecture fixture must not include blocked materials.'
    }
    foreach ($checkId in @('source-grounding', 'license-safety', 'accessibility', 'active-recall', 'assessment-handoff')) {
        if (@($fixture.qaStatus.checks | Where-Object { $_.checkId -eq $checkId -and $_.status -eq 'pass' }).Count -ne 1) {
            Add-CheckError $errors "Lecture fixture missing passing QA check: $checkId"
        }
    }
    if ($fixture.operatorReview.workflowId -ne $operatorReviewWorkflow.workflowId) {
        Add-CheckError $errors 'Lecture fixture operatorReview must use the approved workflow.'
    }
    if ($fixture.operatorReview.publishStatus -ne 'not-ready') {
        Add-CheckError $errors 'Lecture fixture must remain not-ready until rendered media and final package approval are complete.'
    }
    foreach ($stageId in @('script', 'visuals', 'media', 'accessibility', 'license-persona', 'instructor-realism', 'final-package')) {
        $reviewStage = @($fixture.operatorReview.stages | Where-Object { $_.stageId -eq $stageId })
        if ($reviewStage.Count -ne 1) {
            Add-CheckError $errors "Lecture fixture operatorReview missing stage: $stageId"
        }
    }
    foreach ($approvedStageId in @('script', 'visuals', 'accessibility', 'license-persona')) {
        $approvedStage = @($fixture.operatorReview.stages | Where-Object { $_.stageId -eq $approvedStageId -and $_.status -eq 'approved' })
        if ($approvedStage.Count -ne 1) {
            Add-CheckError $errors "Lecture fixture operatorReview expected approved stage: $approvedStageId"
        }
        elseif (-not (Test-HasText $approvedStage[0].reviewer) -or @($approvedStage[0].evidence).Count -lt 1) {
            Add-CheckError $errors "Lecture fixture operatorReview approved stage must include reviewer and evidence: $approvedStageId"
        }
    }
    foreach ($pendingStageId in @('media', 'instructor-realism', 'final-package')) {
        if (@($fixture.operatorReview.stages | Where-Object { $_.stageId -eq $pendingStageId -and $_.status -eq 'pending' }).Count -ne 1) {
            Add-CheckError $errors "Lecture fixture operatorReview expected pending stage: $pendingStageId"
        }
    }
    if ($fixture.operatorReview.finalApproval.status -ne 'pending') {
        Add-CheckError $errors 'Lecture fixture final package approval must stay pending until the media package is rendered and checksummed.'
    }
    if ($fixture.adaptiveHooks.checkpointPolicy -ne 'checkpoint-evidence-only') {
        Add-CheckError $errors 'Lecture fixture must avoid treating passive video completion as mastery.'
    }
    if (@($fixture.adaptiveHooks.checkpoints).Count -lt 1) {
        Add-CheckError $errors 'Lecture fixture must include at least one adaptive checkpoint.'
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

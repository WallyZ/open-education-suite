[CmdletBinding()]
param(
    [string]$SchemaPath = '.\schemas\lecture-video.schema.json',
    [string]$FixturePath = '.\fixtures\lecture-video.gdev-101-design-vocabulary.json',
    [string]$DocumentPath = '.\docs\generated-lecture-video.md',
    [string]$PersonaPath = '.\fixtures\generated-instructor-persona.default.json',
    [string]$ArchivePolicyPath = '.\fixtures\lecture-media-archive-policy.json',
    [string]$AccessibilityPolicyPath = '.\fixtures\lecture-accessibility-policy.json',
    [string]$QualityRubricPath = '.\fixtures\lecture-video-quality-rubric.json',
    [string]$SelectionRulesPath = '.\fixtures\lecture-selection-rules.json',
    [string]$OperatorReviewWorkflowPath = '.\fixtures\lecture-operator-review-workflow.json',
    [string]$ProductionProvidersPath = '.\fixtures\lecture-production-providers.json',
    [string]$RenderedMediaPath = '.\fixtures\lecture-rendered-media.gdev-101.json'
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
    $gitignore = Get-Content -LiteralPath '.\.gitignore' -Raw
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
        if ($operatorReviewResult.blockedCaseCount -ne 4) {
            Add-CheckError $errors 'Lecture operator review gate must block missing stage approval, automated approval, planned required media, and missing final approval.'
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
        if (-not ([string]$productionJob.archiveRoot).StartsWith('var\lecture-media\')) {
            Add-CheckError $errors 'Lecture production job archiveRoot must be under var\lecture-media.'
        }
        foreach ($stage in @('tts', 'visuals', 'avatar', 'assembly', 'archive', 'qa')) {
            if (@($productionJob.stages | Where-Object { $_.stage -eq $stage }).Count -ne 1) {
                Add-CheckError $errors "Lecture production job missing stage: $stage"
            }
        }
        foreach ($stage in @($productionJob.stages | Where-Object { $_.stage -in @('tts', 'visuals', 'avatar', 'assembly') })) {
            if (-not ([string]$stage.output.path).StartsWith('var\lecture-media\')) {
                Add-CheckError $errors "Lecture production job stage output is outside local archive: $($stage.stage)"
            }
            if ($stage.output.checksumAlgorithm -ne 'sha256') {
                Add-CheckError $errors "Lecture production job stage must require sha256: $($stage.stage)"
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
        foreach ($unsupportedStage in @('tts', 'archive', 'qa')) {
            if (@($comfyAdapter.unsupportedStages | Where-Object { $_ -eq $unsupportedStage }).Count -ne 1) {
                Add-CheckError $errors "Local ComfyUI adapter must explicitly leave stage to another provider/gate: $unsupportedStage"
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
        foreach ($stage in @('tts', 'avatar', 'assembly')) {
            $contract = @($cloudAdapter.contracts | Where-Object { $_.stage -eq $stage })
            if ($contract.Count -ne 1) {
                Add-CheckError $errors "Cloud production adapter missing contract stage: $stage"
            }
            elseif ($contract[0].outputPolicy -ne 'download-to-local-archive-and-checksum') {
                Add-CheckError $errors "Cloud production adapter must require local archive download and checksum: $stage"
            }
            foreach ($envVar in @($contract[0].credentialEnvVars)) {
                if ($envVar.value -ne '<redacted>') {
                    Add-CheckError $errors "Cloud production adapter leaked an environment value for: $($envVar.name)"
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
        if (-not ([string]$archiveManifest.archiveRoot).StartsWith('var\lecture-media\')) {
            Add-CheckError $errors 'Lecture archive manifest archiveRoot must be under var\lecture-media.'
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
        if ($archiveManifest.summary.archivedMediaAssetCount -lt 1) {
            Add-CheckError $errors 'Lecture archive manifest summary must count archived rendered media.'
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
        if ($publishRender.renderEngine -ne 'ffmpeg') {
            Add-CheckError $errors 'Lecture publish fixture renderer must use the local ffmpeg encoder.'
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
                if (-not ([string]$renderedPublishMedia[0].path).StartsWith('var\lecture-media\')) {
                    Add-CheckError $errors "Lecture publish fixture media must be under var\lecture-media: $assetId"
                }
                if ($renderedPublishMedia[0].sha256 -notmatch '^[a-f0-9]{64}$') {
                    Add-CheckError $errors "Lecture publish fixture media must include a lowercase SHA-256 checksum: $assetId"
                }
                if ([int64]$renderedPublishMedia[0].length -lt 1000) {
                    Add-CheckError $errors "Lecture publish fixture media file is too small: $assetId"
                }
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
            if (-not ([string]$publishGate.publishReadyPath).StartsWith('var\lecture-media\') -or -not ([string]$publishGate.publishReadyPath).EndsWith('publish\lecture-video.publish-ready.json')) {
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
        'var\lecture-media',
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
        '## Cloud Production Adapter Contracts',
        'invoke-cloud-production-adapter.ps1',
        'TTS, avatar, and video assembly',
        'values are always redacted',
        'downloaded to `var\lecture-media`',
        '## Rendered Audio Fixture',
        'render-lecture-audio-fixture.ps1',
        'lecture-rendered-media.gdev-101.json',
        'real short local WAV file',
        'not the final publishable lecture video',
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
    if ($archivePolicy.localArchiveRoot -ne 'var\lecture-media') {
        Add-CheckError $errors 'Lecture media archive policy must use var\lecture-media as the local archive root.'
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
    if (-not $gitignore.Contains('var/lecture-media/')) {
        Add-CheckError $errors '.gitignore must exclude the local lecture media archive.'
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
    foreach ($stageId in @('script', 'visuals', 'media', 'accessibility', 'license-persona', 'final-package')) {
        $workflowStage = @($operatorReviewWorkflow.requiredStages | Where-Object { $_.stageId -eq $stageId })
        if ($workflowStage.Count -ne 1) {
            Add-CheckError $errors "Lecture operator review workflow missing required stage: $stageId"
        }
        elseif (@($workflowStage[0].requiredEvidence).Count -lt 2) {
            Add-CheckError $errors "Lecture operator review workflow stage needs evidence requirements: $stageId"
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
    if (-not ([string]$productionProviders.artifactPolicy).Contains('var\lecture-media') -or -not ([string]$productionProviders.artifactPolicy).Contains('SHA-256')) {
        Add-CheckError $errors 'Lecture production providers must require local archive and SHA-256 checksums.'
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
    foreach ($cloudProviderId in @('cloud-tts', 'cloud-avatar', 'cloud-video-assembly')) {
        $cloudProvider = @($productionProviders.providers | Where-Object { $_.providerId -eq $cloudProviderId -and $_.type -eq 'cloud' })
        if ($cloudProvider.Count -ne 1) {
            Add-CheckError $errors "Lecture production providers missing cloud profile: $cloudProviderId"
        }
        elseif ($cloudProvider[0].enabledByDefault -ne $false) {
            Add-CheckError $errors "Cloud production provider must be opt-in: $cloudProviderId"
        }
    }
    foreach ($stage in @('tts', 'visuals', 'avatar', 'assembly')) {
        if (@($productionProviders.routing | Where-Object { $_.stage -eq $stage }).Count -ne 1) {
            Add-CheckError $errors "Lecture production providers missing route: $stage"
        }
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
    foreach ($dimensionId in @('video-pacing', 'worked-examples', 'active-recall', 'misconception-checks', 'accessibility', 'assessment-handoff')) {
        $dimension = @($qualityRubric.dimensions | Where-Object { $_.dimensionId -eq $dimensionId })
        if ($dimension.Count -ne 1) {
            Add-CheckError $errors "Lecture video quality rubric missing dimension: $dimensionId"
        }
        elseif (-not (Test-HasText $dimension[0].publishExpectation)) {
            Add-CheckError $errors "Lecture video quality rubric dimension missing publish expectation: $dimensionId"
        }
    }
    $fixtureScore = @($qualityRubric.fixtureScores | Where-Object { $_.packageId -eq $fixture.packageId })
    if ($fixtureScore.Count -ne 1) {
        Add-CheckError $errors 'Lecture video quality rubric must include scores for the deterministic fixture.'
    }
    else {
        foreach ($dimensionId in @('video-pacing', 'worked-examples', 'active-recall', 'misconception-checks', 'accessibility', 'assessment-handoff')) {
            if ($fixtureScore[0].scores.$dimensionId -lt $qualityRubric.minimumPublishScore) {
                Add-CheckError $errors "Lecture fixture score is below publish baseline for: $dimensionId"
            }
        }
    }

    foreach ($field in @(
        'packageId',
        'contentSource',
        'objectiveIds',
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
    if ($fixture.contentSource.sourceId -ne 'game-development') {
        Add-CheckError $errors 'Lecture video fixture must use the game-development content source.'
    }
    if ($fixture.contentSource.sourcePath -ne 'study-plans\courses\GDEV-101-game-design-foundations.md') {
        Add-CheckError $errors 'Lecture video fixture must cite the GDEV-101 course source path.'
    }
    if (@($fixture.objectiveIds | Where-Object { $_ -eq 'game-development:objectives/course/gdev-101/design-vocabulary' }).Count -ne 1) {
        Add-CheckError $errors 'Lecture video fixture must target the GDEV-101 design vocabulary objective.'
    }
    if ($fixture.generatedInstructor.realPersonClone -ne $false) {
        Add-CheckError $errors 'Generated instructor must not clone a real person.'
    }
    foreach ($field in @('disclosure', 'voiceConsent', 'likenessConsent', 'tone')) {
        if (-not (Test-HasText $fixture.generatedInstructor.$field)) {
            Add-CheckError $errors "Generated instructor missing $field."
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
    foreach ($stageId in @('script', 'visuals', 'media', 'accessibility', 'license-persona', 'final-package')) {
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
    foreach ($pendingStageId in @('media', 'final-package')) {
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

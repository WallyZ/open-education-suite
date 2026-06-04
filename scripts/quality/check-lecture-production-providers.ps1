[CmdletBinding()]
param(
    [string]$ProviderPath = '.\fixtures\lecture-production-providers.json',
    [string]$RepoRoot = '.'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Add-ProviderError {
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

function Resolve-RepoRelativePath {
    param(
        [string]$Root,
        [string]$Path
    )

    $rootPath = (Resolve-Path -LiteralPath $Root).Path
    return [System.IO.Path]::GetFullPath((Join-Path -Path $rootPath -ChildPath $Path))
}

$errors = [System.Collections.Generic.List[string]]::new()

if (-not (Test-Path -LiteralPath $ProviderPath -PathType Leaf)) {
    Add-ProviderError $errors "Missing lecture production provider fixture: $ProviderPath"
}

if ($errors.Count -eq 0) {
    $providers = Get-Content -LiteralPath $ProviderPath -Raw | ConvertFrom-Json

    if ($providers.schemaVersion -ne 1) {
        Add-ProviderError $errors 'Lecture production providers schemaVersion must be 1.'
    }
    if (-not (Test-HasText $providers.providerSetId)) {
        Add-ProviderError $errors 'Lecture production providers must declare providerSetId.'
    }
    if (-not ([string]$providers.credentialPolicy).Contains('No provider credentials')) {
        Add-ProviderError $errors 'Lecture production providers must forbid committed credentials.'
    }
    if (-not ([string]$providers.artifactPolicy).Contains('generated-lectures') -or -not ([string]$providers.artifactPolicy).Contains('SHA-256')) {
        Add-ProviderError $errors 'Lecture production providers must require subject repo archive and SHA-256 checksums.'
    }

    $providerList = @($providers.providers)
    $defaultProvider = @($providerList | Where-Object { $_.providerId -eq $providers.defaultProviderId })
    if ($defaultProvider.Count -ne 1) {
        Add-ProviderError $errors 'Lecture production providers must include exactly one default provider.'
    }
    elseif ($defaultProvider[0].type -ne 'local') {
        Add-ProviderError $errors 'Default lecture production provider should be local.'
    }

    $localComfy = @($providerList | Where-Object { $_.providerId -eq 'local-comfyui' })
    if ($localComfy.Count -ne 1) {
        Add-ProviderError $errors 'Lecture production providers must include local-comfyui.'
    }
    else {
        $localProvider = $localComfy[0]
        if ($localProvider.integrationRepo -ne 'ComfyUI-automation') {
            Add-ProviderError $errors 'local-comfyui must point at the ComfyUI-automation repo.'
        }
        foreach ($capability in @('visual-render', 'avatar-render', 'video-assembly')) {
            if (@($localProvider.capabilities | Where-Object { $_ -eq $capability }).Count -ne 1) {
                Add-ProviderError $errors "local-comfyui missing capability: $capability"
            }
        }
        if (@($localProvider.credentialEnvVars).Count -ne 0) {
            Add-ProviderError $errors 'local-comfyui must not require cloud credentials.'
        }
        if ($localProvider.outputPolicy -ne 'copy-to-local-archive-and-checksum') {
            Add-ProviderError $errors 'local-comfyui output policy must copy artifacts into the local archive and checksum them.'
        }
        $localPath = Resolve-RepoRelativePath -Root $RepoRoot -Path ([string]$localProvider.localPath)
        if (-not (Test-Path -LiteralPath $localPath -PathType Container)) {
            Add-ProviderError $errors "local-comfyui path not found: $localPath"
        }
        else {
            foreach ($requiredPath in @('AGENTS.md', 'workflows')) {
                if (-not (Test-Path -LiteralPath (Join-Path -Path $localPath -ChildPath $requiredPath))) {
                    Add-ProviderError $errors "ComfyUI-automation repo missing expected path: $requiredPath"
                }
            }
            foreach ($stage in @('visuals', 'avatar', 'assembly')) {
                $mapping = @($localProvider.workflowMappings | Where-Object { $_.stage -eq $stage })
                if ($mapping.Count -ne 1) {
                    Add-ProviderError $errors "local-comfyui missing workflow mapping: $stage"
                    continue
                }
                $workflowPath = Join-Path -Path $localPath -ChildPath ([string]$mapping[0].workflowPath)
                if (-not (Test-Path -LiteralPath $workflowPath -PathType Leaf)) {
                    Add-ProviderError $errors "local-comfyui workflow mapping path not found: $($mapping[0].workflowPath)"
                }
            }
        }
    }

    $localComfyTts = @($providerList | Where-Object { $_.providerId -eq 'local-comfyui-tts' })
    if ($localComfyTts.Count -ne 1) {
        Add-ProviderError $errors 'Lecture production providers must include local-comfyui-tts.'
    }
    else {
        $localTtsProvider = $localComfyTts[0]
        if ($localTtsProvider.type -ne 'local') {
            Add-ProviderError $errors 'local-comfyui-tts must use type local.'
        }
        if ($localTtsProvider.enabledByDefault -ne $false) {
            Add-ProviderError $errors 'local-comfyui-tts must stay disabled by default until readiness and operator review pass.'
        }
        foreach ($capability in @('tts', 'neural-tts', 'voice-design')) {
            if (@($localTtsProvider.capabilities | Where-Object { $_ -eq $capability }).Count -ne 1) {
                Add-ProviderError $errors "local-comfyui-tts missing capability: $capability"
            }
        }
        if (@($localTtsProvider.credentialEnvVars).Count -ne 0) {
            Add-ProviderError $errors 'local-comfyui-tts must not require cloud credentials.'
        }
        if ($localTtsProvider.outputPolicy -ne 'copy-to-local-archive-and-checksum') {
            Add-ProviderError $errors 'local-comfyui-tts output policy must copy artifacts into the local archive and checksum them.'
        }
        if ($localTtsProvider.integrationRepo -ne 'ComfyUI-automation') {
            Add-ProviderError $errors 'local-comfyui-tts must point at the ComfyUI-automation repo.'
        }
        $qualityText = (@($localTtsProvider.qualityRequirements) -join ' ').ToLowerInvariant()
        foreach ($requiredQualityText in @('human-like', 'generic synthetic', 'no real-person voice cloning', 'pause')) {
            if (-not $qualityText.Contains($requiredQualityText)) {
                Add-ProviderError $errors "local-comfyui-tts quality requirements missing: $requiredQualityText"
            }
        }
        if ($localTtsProvider.readiness.approvedWorkflowMode -ne 'generic-voice-design-non-clone') {
            Add-ProviderError $errors 'local-comfyui-tts must use a generic non-clone voice design workflow mode.'
        }
        foreach ($requiredClass in @('FB_Qwen3TTSVoiceDesign', 'SaveAudio')) {
            if (@($localTtsProvider.readiness.requiredNodeClasses | Where-Object { $_ -eq $requiredClass }).Count -ne 1) {
                Add-ProviderError $errors "local-comfyui-tts readiness missing required node class: $requiredClass"
            }
        }
        foreach ($disallowedClass in @('FB_Qwen3TTSVoiceClone', 'FB_Qwen3TTSVoiceClonePrompt', 'FB_Qwen3TTSCustomVoice')) {
            if (@($localTtsProvider.readiness.disallowedNodeClasses | Where-Object { $_ -eq $disallowedClass }).Count -ne 1) {
                Add-ProviderError $errors "local-comfyui-tts readiness missing disallowed node class: $disallowedClass"
            }
        }
        if (@($localTtsProvider.readiness.disallowedNodeClasses | Where-Object { $_ -like '*VoiceClone*' }).Count -lt 1) {
            Add-ProviderError $errors 'local-comfyui-tts readiness must disallow voice clone nodes.'
        }
        if ($localTtsProvider.readiness.requireOperatorListeningReview -ne $true) {
            Add-ProviderError $errors 'local-comfyui-tts must require operator listening review.'
        }

        $localTtsPath = Resolve-RepoRelativePath -Root $RepoRoot -Path ([string]$localTtsProvider.localPath)
        if (-not (Test-Path -LiteralPath $localTtsPath -PathType Container)) {
            Add-ProviderError $errors "local-comfyui-tts path not found: $localTtsPath"
        }
        else {
            $mapping = @($localTtsProvider.workflowMappings | Where-Object { $_.stage -eq 'tts' })
            if ($mapping.Count -ne 1) {
                Add-ProviderError $errors 'local-comfyui-tts missing workflow mapping: tts'
            }
            else {
                $workflowPath = Join-Path -Path $localTtsPath -ChildPath ([string]$mapping[0].workflowPath)
                if (-not (Test-Path -LiteralPath $workflowPath -PathType Leaf)) {
                    Add-ProviderError $errors "local-comfyui-tts workflow mapping path not found: $($mapping[0].workflowPath)"
                }
            }
        }
    }

    $localComfyMotion = @($providerList | Where-Object { $_.providerId -eq 'local-comfyui-motion' })
    if ($localComfyMotion.Count -ne 1) {
        Add-ProviderError $errors 'Lecture production providers must include local-comfyui-motion.'
    }
    else {
        $localMotionProvider = $localComfyMotion[0]
        if ($localMotionProvider.type -ne 'local') {
            Add-ProviderError $errors 'local-comfyui-motion must use type local.'
        }
        if ($localMotionProvider.enabledByDefault -ne $false) {
            Add-ProviderError $errors 'local-comfyui-motion must stay disabled by default until the motion spike is promoted.'
        }
        foreach ($capability in @('instructor-motion', 'portrait-animation', 'pre-lip-sync-motion')) {
            if (@($localMotionProvider.capabilities | Where-Object { $_ -eq $capability }).Count -ne 1) {
                Add-ProviderError $errors "local-comfyui-motion missing capability: $capability"
            }
        }
        if (@($localMotionProvider.credentialEnvVars).Count -ne 0) {
            Add-ProviderError $errors 'local-comfyui-motion must not require cloud credentials.'
        }
        if ($localMotionProvider.outputPolicy -ne 'copy-to-local-archive-and-checksum') {
            Add-ProviderError $errors 'local-comfyui-motion output policy must copy artifacts into the local archive and checksum them.'
        }
        if ($localMotionProvider.integrationRepo -ne 'ComfyUI-automation') {
            Add-ProviderError $errors 'local-comfyui-motion must point at the ComfyUI-automation repo.'
        }
        if ($localMotionProvider.readiness.approvedWorkflowMode -ne 'pre-lip-sync-subtle-motion-spike') {
            Add-ProviderError $errors 'local-comfyui-motion must use the pre-lip-sync subtle motion spike workflow mode.'
        }
        if ($localMotionProvider.readiness.requireOperatorMotionReview -ne $true) {
            Add-ProviderError $errors 'local-comfyui-motion must require operator motion review.'
        }
        foreach ($pipelineId in @('liveportrait', 'sadtalker')) {
            if (@($localMotionProvider.readiness.candidatePipelines | Where-Object { $_.pipelineId -eq $pipelineId }).Count -ne 1) {
                Add-ProviderError $errors "local-comfyui-motion missing candidate pipeline: $pipelineId"
            }
        }
        $preferredPipeline = @($localMotionProvider.readiness.candidatePipelines | Where-Object { $_.pipelineId -eq 'liveportrait' -and $_.routingRole -eq 'preferred' })
        if ($preferredPipeline.Count -ne 1) {
            Add-ProviderError $errors 'local-comfyui-motion must prefer LivePortrait for subtle motion.'
        }
        $fallbackPipeline = @($localMotionProvider.readiness.candidatePipelines | Where-Object { $_.pipelineId -eq 'sadtalker' -and $_.routingRole -eq 'fallback' })
        if ($fallbackPipeline.Count -ne 1) {
            Add-ProviderError $errors 'local-comfyui-motion must keep SadTalker as the fallback motion candidate.'
        }
        $adapterScriptPath = Resolve-RepoRelativePath -Root $RepoRoot -Path ([string]$localMotionProvider.adapterScript)
        if (-not (Test-Path -LiteralPath $adapterScriptPath -PathType Leaf)) {
            Add-ProviderError $errors "local-comfyui-motion adapter script not found: $($localMotionProvider.adapterScript)"
        }
    }

    $localComfyLipSync = @($providerList | Where-Object { $_.providerId -eq 'local-comfyui-lipsync' })
    if ($localComfyLipSync.Count -ne 1) {
        Add-ProviderError $errors 'Lecture production providers must include local-comfyui-lipsync.'
    }
    else {
        $localLipSyncProvider = $localComfyLipSync[0]
        if ($localLipSyncProvider.type -ne 'local') {
            Add-ProviderError $errors 'local-comfyui-lipsync must use type local.'
        }
        if ($localLipSyncProvider.enabledByDefault -ne $false) {
            Add-ProviderError $errors 'local-comfyui-lipsync must stay disabled by default until the lip-sync spike is promoted.'
        }
        foreach ($capability in @('lip-sync', 'audio-driven-mouth', 'face-crop-sync')) {
            if (@($localLipSyncProvider.capabilities | Where-Object { $_ -eq $capability }).Count -ne 1) {
                Add-ProviderError $errors "local-comfyui-lipsync missing capability: $capability"
            }
        }
        if (@($localLipSyncProvider.credentialEnvVars).Count -ne 0) {
            Add-ProviderError $errors 'local-comfyui-lipsync must not require cloud credentials.'
        }
        if ($localLipSyncProvider.outputPolicy -ne 'copy-to-local-archive-and-checksum') {
            Add-ProviderError $errors 'local-comfyui-lipsync output policy must copy artifacts into the local archive and checksum them.'
        }
        if ($localLipSyncProvider.integrationRepo -ne 'ComfyUI-automation') {
            Add-ProviderError $errors 'local-comfyui-lipsync must point at the ComfyUI-automation repo.'
        }
        if ($localLipSyncProvider.readiness.approvedWorkflowMode -ne 'audio-driven-lip-sync-spike') {
            Add-ProviderError $errors 'local-comfyui-lipsync must use the audio-driven lip-sync spike workflow mode.'
        }
        if ($localLipSyncProvider.readiness.requireOperatorLipSyncReview -ne $true) {
            Add-ProviderError $errors 'local-comfyui-lipsync must require operator lip-sync review.'
        }
        foreach ($pipelineId in @('musetalk', 'wav2lip')) {
            if (@($localLipSyncProvider.readiness.candidatePipelines | Where-Object { $_.pipelineId -eq $pipelineId }).Count -ne 1) {
                Add-ProviderError $errors "local-comfyui-lipsync missing candidate pipeline: $pipelineId"
            }
        }
        $preferredPipeline = @($localLipSyncProvider.readiness.candidatePipelines | Where-Object { $_.pipelineId -eq 'musetalk' -and $_.routingRole -eq 'preferred' })
        if ($preferredPipeline.Count -ne 1) {
            Add-ProviderError $errors 'local-comfyui-lipsync must prefer MuseTalk for audio-driven mouth movement.'
        }
        $fallbackPipeline = @($localLipSyncProvider.readiness.candidatePipelines | Where-Object { $_.pipelineId -eq 'wav2lip' -and $_.routingRole -eq 'fallback' })
        if ($fallbackPipeline.Count -ne 1) {
            Add-ProviderError $errors 'local-comfyui-lipsync must keep Wav2Lip as the fallback lip-sync candidate.'
        }
        $adapterScriptPath = Resolve-RepoRelativePath -Root $RepoRoot -Path ([string]$localLipSyncProvider.adapterScript)
        if (-not (Test-Path -LiteralPath $adapterScriptPath -PathType Leaf)) {
            Add-ProviderError $errors "local-comfyui-lipsync adapter script not found: $($localLipSyncProvider.adapterScript)"
        }
    }

    foreach ($cloudProviderId in @('cloud-tts', 'cloud-avatar', 'cloud-video-assembly')) {
        $cloudProvider = @($providerList | Where-Object { $_.providerId -eq $cloudProviderId })
        if ($cloudProvider.Count -ne 1) {
            Add-ProviderError $errors "Lecture production providers missing cloud profile: $cloudProviderId"
            continue
        }
        if ($cloudProvider[0].type -ne 'cloud') {
            Add-ProviderError $errors "Cloud profile must use type cloud: $cloudProviderId"
        }
        if ($cloudProvider[0].enabledByDefault -ne $false) {
            Add-ProviderError $errors "Cloud profile must be opt-in, not enabled by default: $cloudProviderId"
        }
        if (@($cloudProvider[0].credentialEnvVars).Count -lt 2) {
            Add-ProviderError $errors "Cloud profile must declare provider and API key env vars without values: $cloudProviderId"
        }
        if ($cloudProvider[0].outputPolicy -ne 'download-to-local-archive-and-checksum') {
            Add-ProviderError $errors "Cloud output must be downloaded into the local archive and checksummed: $cloudProviderId"
        }
        if ($cloudProviderId -eq 'cloud-tts') {
            if (@($cloudProvider[0].capabilities | Where-Object { $_ -eq 'neural-tts' }).Count -ne 1) {
                Add-ProviderError $errors 'cloud-tts must declare neural-tts capability.'
            }
            foreach ($requiredTtsEnvVar in @('LECTURE_TTS_ENDPOINT', 'LECTURE_TTS_MODEL', 'LECTURE_TTS_VOICE')) {
                if (@($cloudProvider[0].credentialEnvVars | Where-Object { $_ -eq $requiredTtsEnvVar }).Count -ne 1) {
                    Add-ProviderError $errors "cloud-tts missing required neural TTS env var: $requiredTtsEnvVar"
                }
            }
            $qualityText = (@($cloudProvider[0].qualityRequirements) -join ' ').ToLowerInvariant()
            if (-not $qualityText.Contains('natural') -or -not $qualityText.Contains('pause')) {
                Add-ProviderError $errors 'cloud-tts must record natural voice and pause-preservation quality requirements.'
            }
        }
    }

    foreach ($route in @($providers.routing)) {
        if (-not (Test-HasText $route.stage)) {
            Add-ProviderError $errors 'Provider route missing stage.'
        }
        if (@($providerList | Where-Object { $_.providerId -eq $route.preferredProviderId }).Count -ne 1) {
            Add-ProviderError $errors "Provider route points at an unknown preferred provider: $($route.stage)"
        }
        foreach ($fallbackProviderId in @($route.fallbackProviderIds)) {
            if (@($providerList | Where-Object { $_.providerId -eq $fallbackProviderId }).Count -ne 1) {
                Add-ProviderError $errors "Provider route points at an unknown fallback provider: $($route.stage)"
            }
        }
        if (-not ([string]$route.publishRequirement).Contains('checksum') -and -not ([string]$route.publishRequirement).Contains('SHA-256')) {
            Add-ProviderError $errors "Provider route publish requirement must mention checksum: $($route.stage)"
        }
        if ($route.stage -eq 'tts' -and -not ([string]$route.publishRequirement).Contains('natural neural audio')) {
            Add-ProviderError $errors 'TTS provider route must require natural neural audio.'
        }
        if ($route.stage -eq 'tts' -and $route.preferredProviderId -ne 'local-comfyui-tts') {
            Add-ProviderError $errors 'TTS provider route must prefer local-comfyui-tts after operator listening review.'
        }
        if ($route.stage -eq 'tts' -and @($route.fallbackProviderIds | Where-Object { $_ -eq 'cloud-tts' }).Count -ne 1) {
            Add-ProviderError $errors 'TTS provider route must keep cloud-tts as the fallback provider.'
        }
        if ($route.stage -eq 'motion' -and $route.preferredProviderId -ne 'local-comfyui-motion') {
            Add-ProviderError $errors 'Motion provider route must prefer local-comfyui-motion.'
        }
        if ($route.stage -eq 'motion' -and (-not ([string]$route.publishRequirement).Contains('pre-lip-sync') -or -not ([string]$route.publishRequirement).Contains('board readability'))) {
            Add-ProviderError $errors 'Motion provider route must require pre-lip-sync motion and board readability.'
        }
        if ($route.stage -eq 'lipsync' -and $route.preferredProviderId -ne 'local-comfyui-lipsync') {
            Add-ProviderError $errors 'Lip-sync provider route must prefer local-comfyui-lipsync.'
        }
        if ($route.stage -eq 'lipsync' -and (-not ([string]$route.publishRequirement).Contains('audio-driven') -or -not ([string]$route.publishRequirement).Contains('pause silence') -or -not ([string]$route.publishRequirement).Contains('face identity'))) {
            Add-ProviderError $errors 'Lip-sync provider route must require audio-driven mouth movement, pause silence, and face identity.'
        }
    }

    foreach ($stage in @('tts', 'visuals', 'avatar', 'motion', 'lipsync', 'assembly')) {
        if (@($providers.routing | Where-Object { $_.stage -eq $stage }).Count -ne 1) {
            Add-ProviderError $errors "Lecture production routing missing stage: $stage"
        }
    }
}

[ordered]@{
    schemaVersion = 1
    checkedAt = (Get-Date).ToString('o')
    providerPath = $ProviderPath
    errorCount = $errors.Count
    errors = @($errors)
} | ConvertTo-Json -Depth 8

if ($errors.Count -gt 0) {
    exit 1
}

exit 0

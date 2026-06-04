[CmdletBinding()]
param(
    [string]$ProviderPath = '.\fixtures\lecture-production-providers.json',
    [string]$RepoRoot = '.',
    [string]$Endpoint = '',
    [switch]$RequireReady
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Add-ReadinessError {
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

function Get-WorkflowNodeClasses {
    param([string]$WorkflowPath)

    $workflow = Get-Content -LiteralPath $WorkflowPath -Raw | ConvertFrom-Json
    $classes = [System.Collections.Generic.List[string]]::new()

    if ($workflow.PSObject.Properties.Name -contains 'nodes') {
        foreach ($node in @($workflow.nodes)) {
            if ($node.PSObject.Properties.Name -contains 'class_type' -and (Test-HasText $node.class_type)) {
                $classes.Add([string]$node.class_type)
            }
            elseif ($node.PSObject.Properties.Name -contains 'type' -and (Test-HasText $node.type)) {
                $classes.Add([string]$node.type)
            }
        }
    }
    else {
        foreach ($property in $workflow.PSObject.Properties) {
            $node = $property.Value
            if ($null -ne $node -and $node.PSObject.Properties.Name -contains 'class_type' -and (Test-HasText $node.class_type)) {
                $classes.Add([string]$node.class_type)
            }
        }
    }

    return @($classes | Sort-Object -Unique)
}

function Get-RuntimeNodeClasses {
    param([string]$ComfyEndpoint)

    try {
        $response = Invoke-WebRequest -Uri "$ComfyEndpoint/object_info" -TimeoutSec 30
        $objectInfo = $response.Content | ConvertFrom-Json -AsHashtable
        return [ordered]@{
            reachable = $true
            classes = @($objectInfo.Keys | Sort-Object -Unique)
            error = ''
        }
    }
    catch {
        return [ordered]@{
            reachable = $false
            classes = @()
            error = $_.Exception.Message
        }
    }
}

$errors = [System.Collections.Generic.List[string]]::new()

if (-not (Test-Path -LiteralPath $ProviderPath -PathType Leaf)) {
    Add-ReadinessError $errors "Missing lecture production providers: $ProviderPath"
}

$provider = $null
$workflowPath = ''
$workflowExists = $false
$workflowClasses = @()
$requiredNodeClasses = @()
$disallowedNodeClasses = @()
$runtime = [ordered]@{
    reachable = $false
    classes = @()
    error = ''
}

if ($errors.Count -eq 0) {
    $providers = Get-Content -LiteralPath $ProviderPath -Raw | ConvertFrom-Json
    $providerMatches = @($providers.providers | Where-Object { $_.providerId -eq 'local-comfyui-tts' })
    if ($providerMatches.Count -ne 1) {
        Add-ReadinessError $errors 'Lecture production providers must include one local-comfyui-tts profile.'
    }
    else {
        $provider = $providerMatches[0]
        $requiredNodeClasses = @($provider.readiness.requiredNodeClasses | Where-Object { Test-HasText $_ })
        $disallowedNodeClasses = @($provider.readiness.disallowedNodeClasses | Where-Object { Test-HasText $_ })

        if ($provider.type -ne 'local') {
            Add-ReadinessError $errors 'local-comfyui-tts must be a local provider.'
        }
        if ($provider.enabledByDefault -ne $false) {
            Add-ReadinessError $errors 'local-comfyui-tts must stay disabled by default until readiness and operator review pass.'
        }
        foreach ($capability in @('tts', 'neural-tts', 'voice-design')) {
            if (@($provider.capabilities | Where-Object { $_ -eq $capability }).Count -ne 1) {
                Add-ReadinessError $errors "local-comfyui-tts missing capability: $capability"
            }
        }
        if (@($provider.credentialEnvVars).Count -ne 0) {
            Add-ReadinessError $errors 'local-comfyui-tts must not require cloud credentials.'
        }
        if ($provider.outputPolicy -ne 'copy-to-local-archive-and-checksum') {
            Add-ReadinessError $errors 'local-comfyui-tts must copy rendered audio into the local archive and checksum it.'
        }
        if ($provider.integrationRepo -ne 'ComfyUI-automation') {
            Add-ReadinessError $errors 'local-comfyui-tts must point at ComfyUI-automation.'
        }
        if ($provider.readiness.approvedWorkflowMode -ne 'generic-voice-design-non-clone') {
            Add-ReadinessError $errors 'local-comfyui-tts must use the generic non-clone voice design workflow mode.'
        }
        if ($provider.readiness.requireOperatorListeningReview -ne $true) {
            Add-ReadinessError $errors 'local-comfyui-tts must require operator listening review.'
        }
        foreach ($requiredClass in @('FB_Qwen3TTSVoiceDesign', 'SaveAudio')) {
            if (@($requiredNodeClasses | Where-Object { $_ -eq $requiredClass }).Count -ne 1) {
                Add-ReadinessError $errors "local-comfyui-tts readiness missing required node class: $requiredClass"
            }
        }
        foreach ($disallowedClass in @('FB_Qwen3TTSVoiceClone', 'FB_Qwen3TTSVoiceClonePrompt', 'FB_Qwen3TTSCustomVoice')) {
            if (@($disallowedNodeClasses | Where-Object { $_ -eq $disallowedClass }).Count -ne 1) {
                Add-ReadinessError $errors "local-comfyui-tts readiness missing disallowed node class: $disallowedClass"
            }
        }
        if (@($disallowedNodeClasses | Where-Object { $_ -like '*VoiceClone*' }).Count -lt 1) {
            Add-ReadinessError $errors 'local-comfyui-tts readiness must disallow voice clone nodes.'
        }

        $localPath = Resolve-RepoRelativePath -Root $RepoRoot -Path ([string]$provider.localPath)
        if (-not (Test-Path -LiteralPath $localPath -PathType Container)) {
            Add-ReadinessError $errors "ComfyUI-automation repo not found: $localPath"
        }
        else {
            $mapping = @($provider.workflowMappings | Where-Object { $_.stage -eq 'tts' } | Select-Object -First 1)
            if ($mapping.Count -ne 1) {
                Add-ReadinessError $errors 'local-comfyui-tts must declare a TTS workflow mapping.'
            }
            else {
                $workflowPath = Join-Path -Path $localPath -ChildPath ([string]$mapping[0].workflowPath)
                $workflowExists = Test-Path -LiteralPath $workflowPath -PathType Leaf
                if (-not $workflowExists) {
                    Add-ReadinessError $errors "local-comfyui-tts workflow mapping path not found: $($mapping[0].workflowPath)"
                }
                else {
                    $workflowClasses = @(Get-WorkflowNodeClasses -WorkflowPath $workflowPath)
                    foreach ($requiredClass in $requiredNodeClasses) {
                        if (@($workflowClasses | Where-Object { $_ -eq $requiredClass }).Count -ne 1) {
                            Add-ReadinessError $errors "local-comfyui-tts workflow missing required node class: $requiredClass"
                        }
                    }
                    foreach ($disallowedClass in $disallowedNodeClasses) {
                        if (@($workflowClasses | Where-Object { $_ -eq $disallowedClass }).Count -gt 0) {
                            Add-ReadinessError $errors "local-comfyui-tts workflow must not use disallowed node class: $disallowedClass"
                        }
                    }
                }
            }
        }

        $resolvedEndpoint = $Endpoint
        if (-not (Test-HasText $resolvedEndpoint) -and (Test-HasText $provider.readiness.endpointEnvVar)) {
            $envValue = [Environment]::GetEnvironmentVariable([string]$provider.readiness.endpointEnvVar)
            if (Test-HasText $envValue) {
                $resolvedEndpoint = $envValue
            }
        }
        if (-not (Test-HasText $resolvedEndpoint)) {
            $resolvedEndpoint = [string]$provider.readiness.defaultEndpoint
        }
        $runtime = Get-RuntimeNodeClasses -ComfyEndpoint $resolvedEndpoint
    }
}

$missingRuntimeNodeClasses = @()
if ($runtime.reachable) {
    foreach ($requiredClass in $requiredNodeClasses) {
        if (@($runtime.classes | Where-Object { $_ -eq $requiredClass }).Count -ne 1) {
            $missingRuntimeNodeClasses += $requiredClass
        }
    }
}
else {
    $missingRuntimeNodeClasses = @($requiredNodeClasses)
}

$ready = (
    $errors.Count -eq 0 -and
    $workflowExists -and
    [bool]$runtime.reachable -and
    @($missingRuntimeNodeClasses).Count -eq 0
)

if ($RequireReady -and -not $ready) {
    foreach ($missingClass in $missingRuntimeNodeClasses) {
        Add-ReadinessError $errors "ComfyUI runtime missing required TTS node class: $missingClass"
    }
    if (-not [bool]$runtime.reachable) {
        Add-ReadinessError $errors "ComfyUI runtime is not reachable: $($runtime.error)"
    }
}

[ordered]@{
    schemaVersion = 1
    checkedAt = (Get-Date).ToString('o')
    providerId = 'local-comfyui-tts'
    ready = $ready
    requireReady = [bool]$RequireReady
    workflowPath = $workflowPath
    workflowExists = $workflowExists
    approvedWorkflowMode = if ($null -ne $provider) { [string]$provider.readiness.approvedWorkflowMode } else { '' }
    requiredNodeClasses = @($requiredNodeClasses)
    disallowedNodeClasses = @($disallowedNodeClasses)
    workflowNodeClasses = @($workflowClasses)
    endpointReachable = [bool]$runtime.reachable
    endpointError = [string]$runtime.error
    missingRuntimeNodeClasses = @($missingRuntimeNodeClasses)
    errorCount = $errors.Count
    errors = @($errors)
} | ConvertTo-Json -Depth 8

if ($errors.Count -gt 0) {
    exit 1
}

exit 0

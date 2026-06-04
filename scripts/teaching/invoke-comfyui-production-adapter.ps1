[CmdletBinding()]
param(
    [string]$ManifestPath = '..\open-education-game-development\generated-lectures\gdev-101-design-vocabulary\lecture-video.json',
    [string]$ProviderPath = '.\fixtures\lecture-production-providers.json',
    [string]$CompletedOutputRoot = '',
    [switch]$Submit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-HasText {
    param([object]$Value)
    return -not [string]::IsNullOrWhiteSpace([string]$Value)
}

function Resolve-RepoRelativePath {
    param([string]$Path)

    $rootPath = (Resolve-Path -LiteralPath '.').Path
    return [System.IO.Path]::GetFullPath((Join-Path -Path $rootPath -ChildPath $Path))
}

function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Missing lecture manifest: $ManifestPath"
}
if (-not (Test-Path -LiteralPath $ProviderPath -PathType Leaf)) {
    throw "Missing lecture production providers: $ProviderPath"
}

$lecture = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$providers = Get-Content -LiteralPath $ProviderPath -Raw | ConvertFrom-Json
$localProvider = @($providers.providers | Where-Object { $_.providerId -eq 'local-comfyui' } | Select-Object -First 1)
if ($localProvider.Count -ne 1) {
    throw 'Missing local-comfyui provider profile.'
}
$localTtsProvider = @($providers.providers | Where-Object { $_.providerId -eq 'local-comfyui-tts' } | Select-Object -First 1)
if ($localTtsProvider.Count -ne 1) {
    throw 'Missing local-comfyui-tts provider profile.'
}
$localMotionProvider = @($providers.providers | Where-Object { $_.providerId -eq 'local-comfyui-motion' } | Select-Object -First 1)
if ($localMotionProvider.Count -ne 1) {
    throw 'Missing local-comfyui-motion provider profile.'
}
$localLipSyncProvider = @($providers.providers | Where-Object { $_.providerId -eq 'local-comfyui-lipsync' } | Select-Object -First 1)
if ($localLipSyncProvider.Count -ne 1) {
    throw 'Missing local-comfyui-lipsync provider profile.'
}

$comfyRepoPath = Resolve-RepoRelativePath -Path ([string]$localProvider[0].localPath)
if (-not (Test-Path -LiteralPath $comfyRepoPath -PathType Container)) {
    throw "ComfyUI-automation repo not found: $comfyRepoPath"
}

$jobOutput = & .\scripts\teaching\build-lecture-production-job.ps1 -ManifestPath $ManifestPath -ProviderPath $ProviderPath 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Unable to build lecture production job: $jobOutput"
}
$job = ($jobOutput | Out-String) | ConvertFrom-Json

$ttsRoute = @($providers.routing | Where-Object { $_.stage -eq 'tts' } | Select-Object -First 1)
$ttsRoutingRole = if ($ttsRoute.Count -eq 1 -and $ttsRoute[0].preferredProviderId -eq 'local-comfyui-tts') { 'preferred' } else { 'candidate' }
$acceptedStages = @('visuals', 'avatar', 'assembly')
$candidateStages = @()
if ($ttsRoutingRole -eq 'preferred') {
    $acceptedStages = @('tts') + $acceptedStages
}
else {
    $candidateStages = @('tts')
}

$workflowBindings = @()
$localStages = @(
    [ordered]@{ stage = 'tts'; provider = $localTtsProvider[0]; routingRole = $ttsRoutingRole },
    [ordered]@{ stage = 'visuals'; provider = $localProvider[0]; routingRole = 'preferred' },
    [ordered]@{ stage = 'avatar'; provider = $localProvider[0]; routingRole = 'preferred' },
    [ordered]@{ stage = 'assembly'; provider = $localProvider[0]; routingRole = 'preferred' }
)
foreach ($stageInfo in $localStages) {
    $stage = [string]$stageInfo.stage
    $stageProvider = $stageInfo.provider
    $mapping = @($stageProvider.workflowMappings | Where-Object { $_.stage -eq $stage } | Select-Object -First 1)
    if ($mapping.Count -ne 1) {
        throw "Missing local ComfyUI workflow mapping: $stage"
    }
    $workflowPath = Join-Path -Path $comfyRepoPath -ChildPath ([string]$mapping[0].workflowPath)
    $workflowBindings += [ordered]@{
        stage = $stage
        providerId = $stageProvider.providerId
        routingRole = $stageInfo.routingRole
        workflowPath = $workflowPath
        workflowExists = (Test-Path -LiteralPath $workflowPath -PathType Leaf)
        jobStage = @($job.stages | Where-Object { $_.stage -eq $stage } | Select-Object -First 1)
    }
}

$motionAdapterOutput = & .\scripts\teaching\invoke-comfyui-motion-adapter.ps1 -ManifestPath $ManifestPath -ProviderPath $ProviderPath 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Unable to build local ComfyUI motion adapter spike: $motionAdapterOutput"
}
$motionAdapter = ($motionAdapterOutput | Out-String) | ConvertFrom-Json
$workflowBindings += [ordered]@{
    stage = 'motion'
    providerId = $localMotionProvider[0].providerId
    routingRole = 'spike'
    adapterId = $motionAdapter.adapterId
    workflowPath = $motionAdapter.adapterScriptPath
    workflowExists = (Test-Path -LiteralPath ([string]$motionAdapter.adapterScriptPath) -PathType Leaf)
    spikeReady = $motionAdapter.spikeReady
    runtimeReady = $motionAdapter.runtimeReady
    preLipSyncMotionOnly = $motionAdapter.preLipSyncMotionOnly
    lipSyncIncluded = $motionAdapter.lipSyncIncluded
    jobStage = @($job.stages | Where-Object { $_.stage -eq 'motion' } | Select-Object -First 1)
}

$lipSyncAdapterOutput = & .\scripts\teaching\invoke-comfyui-lipsync-adapter.ps1 -ManifestPath $ManifestPath -ProviderPath $ProviderPath 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Unable to build local ComfyUI lip-sync adapter spike: $lipSyncAdapterOutput"
}
$lipSyncAdapter = ($lipSyncAdapterOutput | Out-String) | ConvertFrom-Json
$workflowBindings += [ordered]@{
    stage = 'lipsync'
    providerId = $localLipSyncProvider[0].providerId
    routingRole = 'spike'
    adapterId = $lipSyncAdapter.adapterId
    workflowPath = $lipSyncAdapter.adapterScriptPath
    workflowExists = (Test-Path -LiteralPath ([string]$lipSyncAdapter.adapterScriptPath) -PathType Leaf)
    spikeReady = $lipSyncAdapter.spikeReady
    runtimeReady = $lipSyncAdapter.runtimeReady
    audioDrivenMouthMovement = $lipSyncAdapter.audioDrivenMouthMovement
    realRenderIncluded = $lipSyncAdapter.realRenderIncluded
    jobStage = @($job.stages | Where-Object { $_.stage -eq 'lipsync' } | Select-Object -First 1)
}

$completedOutputs = @()
if (Test-HasText $CompletedOutputRoot) {
    $outputRoot = Resolve-RepoRelativePath -Path $CompletedOutputRoot
    if (-not (Test-Path -LiteralPath $outputRoot -PathType Container)) {
        throw "Completed output root not found: $outputRoot"
    }
    foreach ($file in Get-ChildItem -LiteralPath $outputRoot -File) {
        $completedOutputs += [ordered]@{
            path = $file.FullName
            length = $file.Length
            sha256 = Get-Sha256 -Path $file.FullName
        }
    }
}

$handoffPath = Join-Path -Path $comfyRepoPath -ChildPath ('.codex-cache\tmp\open-education-suite-lecture-handoff\{0}.json' -f ($job.jobId -replace '[^A-Za-z0-9._-]', '_'))
if ($Submit) {
    $handoffDir = Split-Path -Parent $handoffPath
    $createdDirectory = New-Item -ItemType Directory -Force -Path $handoffDir
    $job | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $handoffPath -Encoding UTF8
}

[ordered]@{
    schemaVersion = 1
    adapterId = 'local-comfyui-adapter-v1'
    mode = $(if ($Submit) { 'submitted' } else { 'dry-run' })
    packageId = $lecture.packageId
    jobId = $job.jobId
    comfyRepoPath = $comfyRepoPath
    handoffPath = $handoffPath
    wroteHandoff = [bool]$Submit
    acceptedStages = @($acceptedStages)
    candidateStages = @($candidateStages)
    spikeStages = @('motion', 'lipsync')
    unsupportedStages = @('archive', 'qa')
    workflowBindings = @($workflowBindings)
    motionAdapter = $motionAdapter
    lipSyncAdapter = $lipSyncAdapter
    completedOutputs = @($completedOutputs)
} | ConvertTo-Json -Depth 20

exit 0

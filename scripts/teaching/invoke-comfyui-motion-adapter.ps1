[CmdletBinding()]
param(
    [string]$ManifestPath = '..\open-education-game-development\generated-lectures\gdev-101-design-vocabulary\lecture-video.json',
    [string]$RenderedMediaPath = '..\open-education-game-development\generated-lectures\gdev-101-design-vocabulary\lecture-rendered-media.json',
    [string]$AvatarMetadataPath = '..\open-education-game-development\generated-lectures\gdev-101-design-vocabulary\lecture-avatar-rendered-media.json',
    [string]$ProviderPath = '.\fixtures\lecture-production-providers.json',
    [switch]$Submit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. .\scripts\teaching\lecture-paths.ps1

function Test-HasText {
    param([object]$Value)
    return -not [string]::IsNullOrWhiteSpace([string]$Value)
}

function ConvertTo-SafePathSegment {
    param([string]$Value)
    if (-not (Test-HasText $Value)) {
        return 'unnamed'
    }
    return ($Value -replace '[^A-Za-z0-9._-]', '_')
}

function Resolve-RepoRelativePath {
    param([string]$Path)

    $rootPath = (Resolve-Path -LiteralPath '.').Path
    return [System.IO.Path]::GetFullPath((Join-Path -Path $rootPath -ChildPath $Path))
}

function Get-Sha256Text {
    param([string]$Text)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $hashBytes = $sha.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($hashBytes) -replace '-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-InstalledCustomNodeNames {
    param([string]$ComfyRepoPath)

    $customNodesRoot = Join-Path -Path $ComfyRepoPath -ChildPath 'ComfyUI-Easy-Install\ComfyUI\custom_nodes'
    if (-not (Test-Path -LiteralPath $customNodesRoot -PathType Container)) {
        return @()
    }

    return @(Get-ChildItem -LiteralPath $customNodesRoot -Directory | ForEach-Object { $_.Name } | Sort-Object -Unique)
}

function Select-MatchingNodeNames {
    param(
        [string[]]$InstalledNodeNames,
        [string[]]$Patterns
    )

    $matches = [System.Collections.Generic.List[string]]::new()
    foreach ($nodeName in @($InstalledNodeNames)) {
        foreach ($pattern in @($Patterns)) {
            if ($nodeName -like $pattern) {
                $matches.Add($nodeName)
                break
            }
        }
    }
    return @($matches | Sort-Object -Unique)
}

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Missing lecture manifest: $ManifestPath"
}
if (-not (Test-Path -LiteralPath $RenderedMediaPath -PathType Leaf)) {
    throw "Missing rendered media metadata: $RenderedMediaPath"
}
if (-not (Test-Path -LiteralPath $AvatarMetadataPath -PathType Leaf)) {
    throw "Missing avatar rendered media metadata: $AvatarMetadataPath"
}
if (-not (Test-Path -LiteralPath $ProviderPath -PathType Leaf)) {
    throw "Missing lecture production providers: $ProviderPath"
}

$resolvedManifestPath = Resolve-LecturePath -Path $ManifestPath
$lecture = Get-Content -LiteralPath $resolvedManifestPath -Raw | ConvertFrom-Json
$renderedMedia = Get-Content -LiteralPath (Resolve-LecturePath -Path $RenderedMediaPath) -Raw | ConvertFrom-Json
$avatarMedia = Get-Content -LiteralPath (Resolve-LecturePath -Path $AvatarMetadataPath) -Raw | ConvertFrom-Json
$providers = Get-Content -LiteralPath $ProviderPath -Raw | ConvertFrom-Json

$motionProvider = @($providers.providers | Where-Object { $_.providerId -eq 'local-comfyui-motion' } | Select-Object -First 1)
if ($motionProvider.Count -ne 1) {
    throw 'Missing local-comfyui-motion provider profile.'
}

$assetRoot = Get-LectureAssetRoot -Lecture $lecture -ManifestPath $resolvedManifestPath
$videoRoot = Get-LectureMediaRelativeDirectory -AssetRoot $assetRoot -Kind 'video'
$comfyRepoPath = Resolve-RepoRelativePath -Path ([string]$motionProvider[0].localPath)
if (-not (Test-Path -LiteralPath $comfyRepoPath -PathType Container)) {
    throw "ComfyUI-automation repo not found: $comfyRepoPath"
}

$sourceAudioPath = Resolve-LectureContentPath -ContentRoot ([string]$assetRoot.contentRoot) -Path ([string]$renderedMedia.path)
$sourceAvatarPath = Resolve-LectureContentPath -ContentRoot ([string]$assetRoot.contentRoot) -Path ([string]$avatarMedia.path)
if (-not (Test-Path -LiteralPath $sourceAudioPath -PathType Leaf)) {
    throw "Rendered source audio does not exist: $($renderedMedia.path)"
}
if (-not (Test-Path -LiteralPath $sourceAvatarPath -PathType Leaf)) {
    throw "Rendered source avatar does not exist: $($avatarMedia.path)"
}

$installedNodeNames = @(Get-InstalledCustomNodeNames -ComfyRepoPath $comfyRepoPath)
$candidatePipelines = @()
foreach ($candidate in @($motionProvider[0].readiness.candidatePipelines)) {
    $patterns = @($candidate.customNodeNamePatterns | Where-Object { Test-HasText $_ })
    $installedMatches = @(Select-MatchingNodeNames -InstalledNodeNames $installedNodeNames -Patterns $patterns)
    $candidatePipelines += [ordered]@{
        pipelineId = $candidate.pipelineId
        label = $candidate.label
        routingRole = $candidate.routingRole
        purpose = $candidate.purpose
        customNodeNamePatterns = @($patterns)
        installedCustomNodes = @($installedMatches)
        installStatus = $(if ($installedMatches.Count -gt 0) { 'available' } else { 'not-installed' })
    }
}

$preferredPipeline = @($candidatePipelines | Where-Object { $_.routingRole -eq 'preferred' } | Select-Object -First 1)
$fallbackPipeline = @($candidatePipelines | Where-Object { $_.routingRole -eq 'fallback' } | Select-Object -First 1)
$runtimeReady = ($preferredPipeline.Count -eq 1 -and @($preferredPipeline[0].installedCustomNodes).Count -gt 0)
$selectedPipelineId = if ($preferredPipeline.Count -eq 1) { $preferredPipeline[0].pipelineId } else { 'liveportrait' }
$fallbackPipelineId = if ($fallbackPipeline.Count -eq 1) { $fallbackPipeline[0].pipelineId } else { 'sadtalker' }

$motionPlan = @()
foreach ($boardState in @($lecture.performancePlan.visualSync.boardStates)) {
    $stateId = [string]$boardState.stateId
    $movement = switch -Wildcard ($stateId) {
        '*setup*' { 'subtle breathing, teacher-facing gaze, small notebook shift' }
        '*verb*' { 'small head turn from learner to board and pointer-hand emphasis' }
        '*theme*' { 'brief board-facing glance, then return gaze toward learner' }
        '*practice*' { 'step-aside framing cue for board close-up and calm handoff posture' }
        default { 'small natural head motion without mouth animation' }
    }

    $motionPlan += [ordered]@{
        segmentId = $stateId
        startSecond = [int]$boardState.startSecond
        endSecond = [int]$boardState.endSecond
        movement = $movement
        lipSync = $false
        boardOcclusionPolicy = 'keep instructor motion outside high-priority board text and close-up crop'
    }
}

$safePackageId = ConvertTo-SafePathSegment -Value ([string]$lecture.packageId)
$handoffPath = Join-Path -Path $comfyRepoPath -ChildPath ('.codex-cache\tmp\open-education-suite-motion-handoff\{0}.json' -f $safePackageId)
$adapterScriptPath = Resolve-RepoRelativePath -Path '.\scripts\teaching\invoke-comfyui-motion-adapter.ps1'
$sourceFrameMetadata = [ordered]@{
    assetId = $avatarMedia.assetId
    path = $avatarMedia.path
    sha256 = $avatarMedia.sha256
    role = 'source-frame'
}
$sourceAudioMetadata = [ordered]@{
    assetId = $renderedMedia.assetId
    path = $renderedMedia.path
    sha256 = $renderedMedia.sha256
    role = 'timing-reference-only-not-lip-sync'
}
$modelMetadata = [ordered]@{
    providerId = 'local-comfyui-motion'
    providerType = $motionProvider[0].type
    integrationRepo = $motionProvider[0].integrationRepo
    selectedPipelineId = $selectedPipelineId
    selectedModelFamily = 'LivePortrait'
    fallbackPipelineId = $fallbackPipelineId
}
$renderConfig = [ordered]@{
    seed = 170101
    deterministic = $true
    outputFps = 24
    movementStrength = 'subtle-front-row-classroom'
    mouthAnimation = 'disabled-until-lip-sync-stage'
    boardOcclusionPolicy = 'preserve-board-text-and-close-up-crop'
}
$outputArchive = [ordered]@{
    assetId = 'lecture-instructor-motion-preview-mp4'
    type = 'video/mp4'
    path = "$videoRoot\lecture-instructor-motion-preview.mp4"
    status = 'planned-spike'
    requiredForPublish = $false
    checksumAlgorithm = 'sha256'
    checksumStatus = 'pending-real-render'
}
$renderPlanForChecksum = [ordered]@{
    stage = 'motion'
    model = $modelMetadata
    sourceFrame = $sourceFrameMetadata
    sourceAudio = $sourceAudioMetadata
    renderConfig = $renderConfig
    outputArchive = $outputArchive
}
$renderPlanSha256 = Get-Sha256Text -Text ($renderPlanForChecksum | ConvertTo-Json -Depth 20 -Compress)
$deterministicMetadata = [ordered]@{
    schemaVersion = 1
    stage = 'motion'
    sourceFrame = $sourceFrameMetadata
    sourceAudio = $sourceAudioMetadata
    model = $modelMetadata
    renderConfig = $renderConfig
    outputArchive = $outputArchive
    renderPlanSha256 = $renderPlanSha256
}

$result = [ordered]@{
    schemaVersion = 1
    adapterId = 'local-comfyui-motion-adapter-spike-v1'
    mode = $(if ($Submit) { 'submitted' } else { 'dry-run' })
    packageId = $lecture.packageId
    providerId = 'local-comfyui-motion'
    stage = 'motion'
    spikeReady = $true
    runtimeReady = [bool]$runtimeReady
    preLipSyncMotionOnly = $true
    lipSyncIncluded = $false
    selectedPipelineId = $selectedPipelineId
    fallbackPipelineId = $fallbackPipelineId
    comfyRepoPath = $comfyRepoPath
    adapterScriptPath = $adapterScriptPath
    handoffPath = $handoffPath
    wroteHandoff = [bool]$Submit
    sourceAvatar = $sourceFrameMetadata
    sourceAudio = $sourceAudioMetadata
    candidatePipelines = @($candidatePipelines)
    deterministicMetadata = $deterministicMetadata
    motionPlan = @($motionPlan)
    safeguards = @(
        'pre-lip-sync motion only',
        'no mouth phoneme animation in this spike',
        'preserve generated instructor disclosure',
        'preserve board readability and close-up crop',
        'avoid high-priority board occlusion'
    )
    output = $outputArchive
}

if ($Submit) {
    $handoffDir = Split-Path -Parent $handoffPath
    New-Item -ItemType Directory -Force -Path $handoffDir | Out-Null
    $result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $handoffPath -Encoding UTF8
}

$result | ConvertTo-Json -Depth 20

exit 0

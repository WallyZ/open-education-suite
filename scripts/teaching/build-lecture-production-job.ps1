[CmdletBinding()]
param(
    [string]$ManifestPath = '..\open-education-game-development\generated-lectures\gdev-101-design-vocabulary\lecture-video.json',
    [string]$ProviderPath = '.\fixtures\lecture-production-providers.json'
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

function Get-Provider {
    param(
        [object]$Providers,
        [string]$ProviderId
    )

    $matches = @($Providers.providers | Where-Object { $_.providerId -eq $ProviderId })
    if ($matches.Count -ne 1) {
        throw "Provider not found: $ProviderId"
    }
    return $matches[0]
}

function Get-Route {
    param(
        [object]$Providers,
        [string]$Stage
    )

    $matches = @($Providers.routing | Where-Object { $_.stage -eq $Stage })
    if ($matches.Count -ne 1) {
        throw "Production route not found: $Stage"
    }
    return $matches[0]
}

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Missing lecture manifest: $ManifestPath"
}
if (-not (Test-Path -LiteralPath $ProviderPath -PathType Leaf)) {
    throw "Missing lecture production providers: $ProviderPath"
}

$resolvedManifestPath = Resolve-LecturePath -Path $ManifestPath
$lecture = Get-Content -LiteralPath $resolvedManifestPath -Raw | ConvertFrom-Json
$providers = Get-Content -LiteralPath $ProviderPath -Raw | ConvertFrom-Json

$safePackageId = ConvertTo-SafePathSegment -Value ([string]$lecture.packageId)
$assetRoot = Get-LectureAssetRoot -Lecture $lecture -ManifestPath $resolvedManifestPath
$archiveRoot = [string]$assetRoot.relativePath

$stages = @()
foreach ($stageName in @('tts', 'visuals', 'avatar', 'motion', 'lipsync', 'assembly')) {
    $route = Get-Route -Providers $providers -Stage $stageName
    $provider = Get-Provider -Providers $providers -ProviderId ([string]$route.preferredProviderId)
    $performanceRefs = switch ($stageName) {
        'tts' { @('performancePlan.audioProfile', 'performancePlan.pausePrompts') }
        'visuals' { @('performancePlan.visualSync', 'performancePlan.pausePrompts') }
        'avatar' { @('performancePlan.visualSync', 'generatedInstructor.realismProfile') }
        'motion' { @('performancePlan.visualSync', 'generatedInstructor.realismProfile', 'lecture-avatar-rendered-media.json', 'rendered-audio-timing-reference') }
        'lipsync' { @('performancePlan.audioProfile', 'performancePlan.pausePrompts', 'generatedInstructor.realismProfile', 'lecture-avatar-rendered-media.json', 'rendered-audio-final') }
        'assembly' { @('performancePlan.audioProfile', 'performancePlan.pausePrompts', 'performancePlan.visualSync') }
        default { @('performancePlan') }
    }
    $extension = switch ($stageName) {
        'tts' { 'm4a' }
        'visuals' { 'png' }
        'avatar' { 'mp4' }
        'motion' { 'mp4' }
        'lipsync' { 'mp4' }
        'assembly' { 'mp4' }
        default { 'bin' }
    }
    $assetId = if ($stageName -eq 'motion') { 'lecture-instructor-motion-preview' } elseif ($stageName -eq 'lipsync') { 'lecture-instructor-lipsync-preview' } else { "lecture-$stageName" }
    $mediaKind = if ($stageName -eq 'visuals') { 'visuals' } elseif ($stageName -eq 'tts') { 'audio' } else { 'video' }
    $outputRoot = Get-LectureMediaRelativeDirectory -AssetRoot $assetRoot -Kind $mediaKind
    $stages += [ordered]@{
        stage = $stageName
        providerId = $provider.providerId
        providerType = $provider.type
        capability = @($provider.capabilities)[0]
        dryRun = $true
        inputRefs = @(
            'lecture-video.json',
            'script.text',
            'storyboard',
            'generatedInstructor',
            'slides'
        ) + $performanceRefs
        output = [ordered]@{
            assetId = $assetId
            path = "$outputRoot\$assetId.$extension"
            requiredForPublish = ($stageName -notin @('motion', 'lipsync'))
            checksumAlgorithm = 'sha256'
        }
        publishRequirement = $route.publishRequirement
    }
}

$stages += [ordered]@{
    stage = 'archive'
    providerId = 'local-archive'
    providerType = 'local'
    capability = 'archive-and-checksum'
    dryRun = $true
    inputRefs = @(
        'rendered-audio',
        'rendered-visuals',
        'rendered-avatar',
        'assembled-video',
        'captions',
        'transcript'
    )
    output = [ordered]@{
        path = $archiveRoot
        manifestUpdate = 'media[].status=archived; media[].sha256=<computed-sha256>'
        checksumAlgorithm = 'sha256'
    }
    publishRequirement = 'all required artifacts must be present under the subject content repo generated-lectures archive and have SHA-256 checksums'
}

$stages += [ordered]@{
    stage = 'qa'
    providerId = 'quality-gates'
    providerType = 'local'
    capability = 'license-accessibility-quality-operator-review'
    dryRun = $true
    inputRefs = @(
        'lecture-video.json',
        'rendered-media',
        'checksums',
        'operatorReview'
    )
    output = [ordered]@{
        path = "$archiveRoot\qa\production-qa-report.json"
        publishStatus = 'blocked-until-real-render-and-operator-approval'
    }
    publishRequirement = 'license gate, accessibility checks, media checksums, quality rubric, and operator review must pass before publish'
}

[ordered]@{
    schemaVersion = 1
    jobId = "lecture-production-job:$($safePackageId):dry-run"
    dryRun = $true
    packageId = $lecture.packageId
    providerSetId = $providers.providerSetId
    defaultProviderId = $providers.defaultProviderId
    archiveRoot = $archiveRoot
    stages = @($stages)
    publishGates = @(
        'license-gate',
        'accessibility',
        'checksum-archive',
        'teaching-quality-rubric',
        'operator-review'
    )
    requiresRealRenderBeforePublish = $true
} | ConvertTo-Json -Depth 12

exit 0

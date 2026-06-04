[CmdletBinding()]
param(
    [string]$ProviderPath = '.\fixtures\lecture-production-providers.json',
    [string]$ManifestPath = '..\open-education-game-development\generated-lectures\gdev-101-design-vocabulary\lecture-video.json',
    [string]$MetadataPath = '',
    [switch]$RequireConfigured,
    [switch]$RenderTts
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. .\scripts\teaching\lecture-paths.ps1

function Add-CloudError {
    param(
        [System.Collections.Generic.List[string]]$Errors,
        [string]$Message
    )
    $Errors.Add($Message)
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

function ConvertTo-SpokenLectureText {
    param([object]$Lecture)

    $text = [string]$Lecture.transcript.text
    if ([string]::IsNullOrWhiteSpace($text)) {
        $text = [string]$Lecture.script.text
    }
    if ([string]::IsNullOrWhiteSpace($text)) {
        return 'Open Education Suite generated lecture.'
    }

    $text = $text -replace '\[[^\]]+\]', ''
    $text = $text -replace '#+', ''
    $text = $text -replace '\s+', ' '
    return $text.Trim()
}

function Get-ProviderById {
    param(
        [object]$Providers,
        [string]$ProviderId
    )

    $provider = @($Providers.providers | Where-Object { $_.providerId -eq $ProviderId } | Select-Object -First 1)
    if ($provider.Count -ne 1) {
        return $null
    }

    return $provider[0]
}

if (-not (Test-Path -LiteralPath $ProviderPath -PathType Leaf)) {
    throw "Missing lecture production providers: $ProviderPath"
}

$providers = Get-Content -LiteralPath $ProviderPath -Raw | ConvertFrom-Json
$cloudContracts = @()
$errors = [System.Collections.Generic.List[string]]::new()

foreach ($providerId in @('cloud-tts', 'cloud-avatar', 'cloud-video-assembly')) {
    $provider = @($providers.providers | Where-Object { $_.providerId -eq $providerId } | Select-Object -First 1)
    if ($provider.Count -ne 1) {
        $errors.Add("Missing cloud provider profile: $providerId")
        continue
    }

    $envVars = @()
    $shouldRequireProviderConfig = $RequireConfigured -and ((-not $RenderTts) -or $providerId -eq 'cloud-tts')
    foreach ($envVarName in @($provider[0].credentialEnvVars)) {
        $value = [Environment]::GetEnvironmentVariable([string]$envVarName)
        $present = -not [string]::IsNullOrWhiteSpace($value)
        if ($shouldRequireProviderConfig -and -not $present) {
            $errors.Add("Missing required environment variable for ${providerId}: $envVarName")
        }
        $envVars += [ordered]@{
            name = $envVarName
            present = $present
            value = '<redacted>'
        }
    }

    $stage = switch ($providerId) {
        'cloud-tts' { 'tts' }
        'cloud-avatar' { 'avatar' }
        'cloud-video-assembly' { 'assembly' }
        default { 'unknown' }
    }

    $cloudContracts += [ordered]@{
        providerId = $provider[0].providerId
        stage = $stage
        type = $provider[0].type
        enabledByDefault = $provider[0].enabledByDefault
        capabilities = @($provider[0].capabilities)
        credentialEnvVars = @($envVars)
        outputPolicy = $provider[0].outputPolicy
        publishRequirement = 'cloud outputs must be downloaded to the subject content repo generated-lectures archive, checksummed, and operator-approved before publish'
    }
}

$renderedTts = $null
if ($RenderTts) {
    $RequireConfigured = $true
    $ttsProvider = Get-ProviderById -Providers $providers -ProviderId 'cloud-tts'
    if ($null -eq $ttsProvider) {
        Add-CloudError $errors 'Missing cloud-tts provider profile.'
    }

    $providerName = [Environment]::GetEnvironmentVariable('LECTURE_TTS_PROVIDER')
    $apiKey = [Environment]::GetEnvironmentVariable('LECTURE_TTS_API_KEY')
    $endpoint = [Environment]::GetEnvironmentVariable('LECTURE_TTS_ENDPOINT')
    $model = [Environment]::GetEnvironmentVariable('LECTURE_TTS_MODEL')
    $voice = [Environment]::GetEnvironmentVariable('LECTURE_TTS_VOICE')
    foreach ($requiredEnvVar in @('LECTURE_TTS_PROVIDER', 'LECTURE_TTS_API_KEY', 'LECTURE_TTS_ENDPOINT', 'LECTURE_TTS_MODEL', 'LECTURE_TTS_VOICE')) {
        if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($requiredEnvVar))) {
            Add-CloudError $errors "Missing required environment variable for neural TTS render: $requiredEnvVar"
        }
    }

    if ($errors.Count -eq 0) {
        $resolvedManifestPath = Resolve-LecturePath -Path $ManifestPath
        if (-not (Test-Path -LiteralPath $resolvedManifestPath -PathType Leaf)) {
            Add-CloudError $errors "Missing lecture manifest for neural TTS render: $ManifestPath"
        }
        else {
            $lecture = Get-Content -LiteralPath $resolvedManifestPath -Raw | ConvertFrom-Json
            $assetRoot = Get-LectureAssetRoot -Lecture $lecture -ManifestPath $resolvedManifestPath
            $outputDir = Get-LectureMediaDirectory -AssetRoot $assetRoot -Kind 'audio'
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
            $outputPath = Join-Path -Path $outputDir -ChildPath 'lecture-audio-neural-tts.mp3'
            $spokenText = ConvertTo-SpokenLectureText -Lecture $lecture
            $payload = [ordered]@{
                model = $model
                voice = $voice
                input = $spokenText
                response_format = 'mp3'
            } | ConvertTo-Json -Depth 5
            $headers = @{
                Authorization = "Bearer $apiKey"
            }

            Invoke-WebRequest -Uri $endpoint -Method Post -Headers $headers -ContentType 'application/json' -Body $payload -OutFile $outputPath | Out-Null
            $outputItem = Get-Item -LiteralPath $outputPath
            if ($outputItem.Length -lt 10000) {
                Add-CloudError $errors 'Neural TTS provider returned an audio file that is too small to be useful.'
            }
            else {
                $relativeOutputPath = ConvertTo-LectureContentRelativePath -ContentRoot ([string]$assetRoot.contentRoot) -Path $outputPath
                $renderedTts = [ordered]@{
                    schemaVersion = 1
                    packageId = $lecture.packageId
                    assetId = 'lecture-audio-neural-tts'
                    type = 'audio/mpeg'
                    path = $relativeOutputPath
                    sha256 = Get-Sha256File -Path $outputPath
                    status = 'archived'
                    requiredForPublish = $false
                    providerId = 'cloud-tts'
                    providerName = $providerName
                    renderEngine = 'neural-tts-openai-compatible-binary'
                    model = $model
                    voice = $voice
                    length = $outputItem.Length
                    notes = 'Publish-grade neural TTS candidate archived from an opt-in cloud speech endpoint. Credentials were read from environment variables and were not written to metadata.'
                }

                $resolvedMetadataPath = if ([string]::IsNullOrWhiteSpace($MetadataPath)) {
                    Join-Path -Path (Split-Path -Parent $resolvedManifestPath) -ChildPath 'lecture-neural-tts-rendered-media.json'
                }
                else {
                    Resolve-LecturePath -Path $MetadataPath
                }
                $metadataDirectory = Split-Path -Parent $resolvedMetadataPath
                if (-not (Test-Path -LiteralPath $metadataDirectory -PathType Container)) {
                    New-Item -ItemType Directory -Path $metadataDirectory -Force | Out-Null
                }
                $metadataJson = $renderedTts | ConvertTo-Json -Depth 8
                [System.IO.File]::WriteAllText($resolvedMetadataPath, $metadataJson, [System.Text.UTF8Encoding]::new($false))
            }
        }
    }
}

[ordered]@{
    schemaVersion = 1
    adapterId = 'cloud-production-adapter-contracts-v1'
    mode = $(if ($RenderTts) { 'neural-tts-render' } elseif ($RequireConfigured) { 'environment-required' } else { 'contract-check' })
    secretPolicy = 'Environment variable values are never printed; presence is reported with redacted values only.'
    supportedRenderModes = @('neural-tts-openai-compatible-binary')
    errorCount = $errors.Count
    errors = @($errors)
    contracts = @($cloudContracts)
    renderedTts = $renderedTts
} | ConvertTo-Json -Depth 10

if ($errors.Count -gt 0) {
    exit 1
}

exit 0

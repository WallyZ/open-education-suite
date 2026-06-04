[CmdletBinding()]
param(
    [string]$ManifestPath = '..\open-education-game-development\generated-lectures\gdev-101-design-vocabulary\lecture-video.json',
    [string]$ProviderPath = '.\fixtures\lecture-production-providers.json',
    [string]$MetadataPath = '',
    [string]$Endpoint = 'http://127.0.0.1:8188',
    [string]$SampleId = 'sample-001',
    [int]$Seed = 101021,
    [int]$TextLimitChars = 700,
    [int]$TimeoutSeconds = 1200,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. .\scripts\teaching\lecture-paths.ps1

function Test-HasText {
    param([object]$Value)
    return -not [string]::IsNullOrWhiteSpace([string]$Value)
}

function Resolve-RepoRelativePath {
    param([string]$Path)

    $rootPath = (Resolve-Path -LiteralPath '.').Path
    return [System.IO.Path]::GetFullPath((Join-Path -Path $rootPath -ChildPath $Path))
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
    param(
        [object]$Lecture,
        [int]$MaxChars
    )

    $text = ''
    if ($Lecture.PSObject.Properties.Name -contains 'transcript' -and $null -ne $Lecture.transcript -and $Lecture.transcript.PSObject.Properties.Name -contains 'text') {
        $text = [string]$Lecture.transcript.text
    }
    if (-not (Test-HasText $text) -and $Lecture.PSObject.Properties.Name -contains 'script' -and $null -ne $Lecture.script -and $Lecture.script.PSObject.Properties.Name -contains 'text') {
        $text = [string]$Lecture.script.text
    }
    if (-not (Test-HasText $text)) {
        $text = 'Open Education Suite generated lecture. Define the design goal, connect it to player feedback, and pause to practice applying the idea.'
    }

    $text = $text -replace '\[[^\]]+\]', ' '
    $text = $text -replace '#+', ' '
    $text = $text -replace '\s+', ' '
    $text = $text.Trim()
    if ($MaxChars -gt 0 -and $text.Length -gt $MaxChars) {
        $end = [Math]::Min($MaxChars, $text.Length)
        $slice = $text.Substring(0, $end)
        $lastSentence = [Math]::Max($slice.LastIndexOf('.'), [Math]::Max($slice.LastIndexOf('?'), $slice.LastIndexOf('!')))
        if ($lastSentence -gt 160) {
            $slice = $slice.Substring(0, $lastSentence + 1)
        }
        $text = $slice.Trim()
    }

    return $text
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

function Get-InstructorVoiceProfile {
    param([object]$Lecture)

    $gender = 'neutral'
    if (
        $Lecture.PSObject.Properties.Name -contains 'generatedInstructor' -and
        $null -ne $Lecture.generatedInstructor -and
        $Lecture.generatedInstructor.PSObject.Properties.Name -contains 'gender' -and
        (Test-HasText $Lecture.generatedInstructor.gender)
    ) {
        $gender = ([string]$Lecture.generatedInstructor.gender).ToLowerInvariant()
    }

    switch ($gender) {
        'male' {
            return [ordered]@{
                instructorGender = 'male'
                voiceGender = 'masculine'
                pitchRange = 'lower adult register'
                timbre = 'warm, resonant, deeper masculine classroom voice'
                instruction = 'Use a masculine adult instructor voice with naturally lower pitch, deeper resonance, and calm classroom authority. Avoid a light, feminine, childlike, or robotic voice.'
            }
        }
        'female' {
            return [ordered]@{
                instructorGender = 'female'
                voiceGender = 'feminine'
                pitchRange = 'higher adult register'
                timbre = 'warm, clear feminine classroom voice'
                instruction = 'Use a feminine adult instructor voice with a naturally higher adult register, clear warmth, and calm classroom authority. Avoid a deep masculine, childlike, or robotic voice.'
            }
        }
        default {
            return [ordered]@{
                instructorGender = $gender
                voiceGender = 'neutral'
                pitchRange = 'adult neutral register'
                timbre = 'warm, clear adult classroom voice'
                instruction = 'Use a neutral adult instructor voice with clear warmth and calm classroom authority. Avoid a strongly masculine, strongly feminine, childlike, or robotic voice.'
            }
        }
    }
}

function Get-WorkflowFromMapping {
    param(
        [string]$ComfyRepoPath,
        [string]$MappingPath
    )

    $workflowPath = Join-Path -Path $ComfyRepoPath -ChildPath $MappingPath
    if (-not (Test-Path -LiteralPath $workflowPath -PathType Leaf)) {
        throw "ComfyUI TTS workflow mapping does not exist: $MappingPath"
    }

    return [ordered]@{
        path = $workflowPath
        relativePath = $MappingPath
    }
}

function Set-ComfyTtsWorkflowForLecture {
    param(
        [object]$Workflow,
        [object]$Lecture,
        [string]$Text,
        [string]$FilenamePrefix,
        [int]$SeedValue,
        [object]$VoiceProfile
    )

    $ttsNode = @($Workflow.PSObject.Properties | Where-Object { $_.Value.class_type -eq 'FB_Qwen3TTSVoiceDesign' } | Select-Object -First 1)
    if ($ttsNode.Count -ne 1) {
        throw 'ComfyUI workflow does not contain FB_Qwen3TTSVoiceDesign.'
    }

    $saveNode = @($Workflow.PSObject.Properties | Where-Object { $_.Value.class_type -eq 'SaveAudio' } | Select-Object -First 1)
    if ($saveNode.Count -ne 1) {
        throw 'ComfyUI workflow does not contain SaveAudio.'
    }

    $title = if ($Lecture.PSObject.Properties.Name -contains 'title' -and (Test-HasText $Lecture.title)) { [string]$Lecture.title } else { 'the current lesson' }
    $instruction = "A generic synthetic $($VoiceProfile['voiceGender']) adult classroom instructor voice for $title. $($VoiceProfile['instruction']) Natural American English. Emotionally present and encouraging without sounding theatrical. Moderate lecture pacing, gentle emphasis on key terms, brief natural pauses before practice prompts. Do not imitate any real person."

    $ttsNode[0].Value.inputs.text = $Text
    $ttsNode[0].Value.inputs.instruct = $instruction
    $ttsNode[0].Value.inputs.model_choice = '1.7B'
    $ttsNode[0].Value.inputs.device = 'auto'
    $ttsNode[0].Value.inputs.precision = 'bf16'
    $ttsNode[0].Value.inputs.language = 'English'
    $ttsNode[0].Value.inputs.seed = $SeedValue
    $ttsNode[0].Value.inputs.max_new_tokens = 2048
    $ttsNode[0].Value.inputs.top_p = 0.8
    $ttsNode[0].Value.inputs.top_k = 20
    $ttsNode[0].Value.inputs.temperature = 0.9
    $ttsNode[0].Value.inputs.repetition_penalty = 1.05
    $ttsNode[0].Value.inputs.attention = 'sdpa'
    $ttsNode[0].Value.inputs.unload_model_after_generate = $false

    $saveNode[0].Value.inputs.filename_prefix = $FilenamePrefix
}

function Get-ComfyOutputAudio {
    param(
        [string]$PromptId,
        [string]$Endpoint,
        [int]$TimeoutSeconds
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        Start-Sleep -Seconds 5
        $response = Invoke-WebRequest -Uri "$Endpoint/history/$PromptId" -TimeoutSec 30
        $history = $response.Content | ConvertFrom-Json -AsHashtable
        if ($history.ContainsKey($PromptId)) {
            $entry = $history[$PromptId]
            if ($entry.ContainsKey('outputs')) {
                foreach ($output in $entry['outputs'].Values) {
                    foreach ($key in @('audio', 'audios', 'files')) {
                        if ($output.ContainsKey($key) -and @($output[$key]).Count -gt 0) {
                            return @($output[$key])[0]
                        }
                    }
                }
            }
        }
    } while ((Get-Date) -lt $deadline)

    throw "ComfyUI did not return an audio file for prompt $PromptId within $TimeoutSeconds seconds."
}

function Test-ExistingTtsMetadata {
    param(
        [string]$Path,
        [string]$ContentRoot,
        [object]$ExpectedVoiceProfile
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    $metadata = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $mediaPath = Resolve-LectureContentPath -ContentRoot $ContentRoot -Path ([string]$metadata.path)
    if (-not (Test-Path -LiteralPath $mediaPath -PathType Leaf)) {
        return $null
    }

    $actualSha = Get-Sha256File -Path $mediaPath
    if ($actualSha -ne [string]$metadata.sha256) {
        return $null
    }
    foreach ($field in @('instructorGender', 'voiceGender', 'pitchRange', 'timbre', 'voiceMatchPolicy')) {
        if (-not ($metadata.PSObject.Properties.Name -contains $field)) {
            return $null
        }
    }
    if (
        [string]$metadata.instructorGender -ne [string]$ExpectedVoiceProfile['instructorGender'] -or
        [string]$metadata.voiceGender -ne [string]$ExpectedVoiceProfile['voiceGender'] -or
        [string]$metadata.pitchRange -ne [string]$ExpectedVoiceProfile['pitchRange'] -or
        [string]$metadata.timbre -ne [string]$ExpectedVoiceProfile['timbre'] -or
        [string]$metadata.voiceMatchPolicy -ne 'match-generated-instructor-gender'
    ) {
        return $null
    }

    return $metadata
}

$resolvedManifestPath = Resolve-LecturePath -Path $ManifestPath
if (-not (Test-Path -LiteralPath $resolvedManifestPath -PathType Leaf)) {
    throw "Missing lecture manifest: $ManifestPath"
}
if (-not (Test-Path -LiteralPath $ProviderPath -PathType Leaf)) {
    throw "Missing lecture production providers: $ProviderPath"
}

$lecture = Get-Content -LiteralPath $resolvedManifestPath -Raw | ConvertFrom-Json
$assetRoot = Get-LectureAssetRoot -Lecture $lecture -ManifestPath $resolvedManifestPath
$voiceProfile = Get-InstructorVoiceProfile -Lecture $lecture
$safeSampleId = ConvertTo-LectureSafePathSegment -Value $SampleId
$resolvedMetadataPath = if (Test-HasText $MetadataPath) {
    Resolve-LecturePath -Path $MetadataPath
}
else {
    Join-Path -Path (Split-Path -Parent $resolvedManifestPath) -ChildPath ("lecture-comfyui-tts-rendered-media-$safeSampleId.json")
}

if (-not $Force) {
    $existing = Test-ExistingTtsMetadata -Path $resolvedMetadataPath -ContentRoot ([string]$assetRoot.contentRoot) -ExpectedVoiceProfile $voiceProfile
    if ($null -ne $existing) {
        $existing | ConvertTo-Json -Depth 12
        exit 0
    }
}

$providers = Get-Content -LiteralPath $ProviderPath -Raw | ConvertFrom-Json
$ttsProvider = Get-ProviderById -Providers $providers -ProviderId 'local-comfyui-tts'
if ($null -eq $ttsProvider) {
    throw 'Missing local-comfyui-tts provider profile.'
}

$comfyRepoPath = Resolve-RepoRelativePath -Path ([string]$ttsProvider.localPath)
$ttsMapping = @($ttsProvider.workflowMappings | Where-Object { $_.stage -eq 'tts' } | Select-Object -First 1)
if ($ttsMapping.Count -ne 1) {
    throw 'Missing local-comfyui-tts workflow mapping.'
}

$workflowInfo = Get-WorkflowFromMapping -ComfyRepoPath $comfyRepoPath -MappingPath ([string]$ttsMapping[0].workflowPath)
$workflow = Get-Content -LiteralPath ([string]$workflowInfo.path) -Raw | ConvertFrom-Json
$safePackageId = ConvertTo-LectureSafePathSegment -Value ([string]$lecture.packageId)
$filenamePrefix = "audio/oes_$safePackageId`_tts_$safeSampleId"
$spokenText = ConvertTo-SpokenLectureText -Lecture $lecture -MaxChars $TextLimitChars
Set-ComfyTtsWorkflowForLecture -Workflow $workflow -Lecture $lecture -Text $spokenText -FilenamePrefix $filenamePrefix -SeedValue $Seed -VoiceProfile $voiceProfile

try {
    [void](Invoke-RestMethod -Uri "$Endpoint/system_stats" -TimeoutSec 10)
}
catch {
    throw "ComfyUI API is not reachable at $Endpoint. Start the local ComfyUI service before rendering TTS."
}

$body = @{
    prompt = $workflow
    client_id = [guid]::NewGuid().ToString()
} | ConvertTo-Json -Depth 40

$promptResult = Invoke-RestMethod -Method Post -Uri "$Endpoint/prompt" -Body $body -ContentType 'application/json' -TimeoutSec 30
$promptId = [string]$promptResult.prompt_id
$audio = Get-ComfyOutputAudio -PromptId $promptId -Endpoint $Endpoint -TimeoutSeconds $TimeoutSeconds

$audioDirectory = Get-LectureMediaDirectory -AssetRoot $assetRoot -Kind 'audio'
New-Item -ItemType Directory -Path $audioDirectory -Force | Out-Null

$sourceFilename = [string]$audio['filename']
$extension = [System.IO.Path]::GetExtension($sourceFilename)
if (-not (Test-HasText $extension)) {
    $extension = '.wav'
}
$audioPath = Join-Path -Path $audioDirectory -ChildPath ("lecture-audio-comfyui-tts-$safeSampleId$extension")

$query = 'filename={0}&subfolder={1}&type={2}' -f [uri]::EscapeDataString($sourceFilename), [uri]::EscapeDataString([string]$audio['subfolder']), [uri]::EscapeDataString([string]$audio['type'])
Invoke-WebRequest -Uri "$Endpoint/view?$query" -OutFile $audioPath -TimeoutSec 120

$audioItem = Get-Item -LiteralPath $audioPath
if ($audioItem.Length -lt 10000) {
    throw "ComfyUI TTS output is too small to be useful: $audioPath"
}

$mimeType = switch ($extension.ToLowerInvariant()) {
    '.flac' { 'audio/flac' }
    '.mp3' { 'audio/mpeg' }
    '.ogg' { 'audio/ogg' }
    default { 'audio/wav' }
}

$metadata = [ordered]@{
    schemaVersion = 1
    packageId = $lecture.packageId
    assetId = "lecture-audio-comfyui-tts-$safeSampleId"
    sampleId = $SampleId
    type = $mimeType
    path = ConvertTo-LectureContentRelativePath -ContentRoot ([string]$assetRoot.contentRoot) -Path $audioPath
    sha256 = Get-Sha256File -Path $audioPath
    status = 'archived'
    requiredForPublish = $false
    providerId = 'local-comfyui-tts'
    renderEngine = 'local-comfyui-qwen3-tts-voice-design'
    workflowPath = [string]$workflowInfo.relativePath
    promptId = $promptId
    seed = $Seed
    textLimitChars = $TextLimitChars
    instructorGender = $voiceProfile['instructorGender']
    voiceGender = $voiceProfile['voiceGender']
    pitchRange = $voiceProfile['pitchRange']
    timbre = $voiceProfile['timbre']
    voiceMatchPolicy = 'match-generated-instructor-gender'
    sourceFilename = $sourceFilename
    length = $audioItem.Length
    qualityGate = 'operator-listening-review-required-before-route-promotion'
    notes = 'Generic synthetic instructor voice-design sample rendered locally through ComfyUI. This is not a real-person voice clone and is not promoted for production routing until operator review passes.'
}

$metadataDirectory = Split-Path -Parent $resolvedMetadataPath
if (-not (Test-Path -LiteralPath $metadataDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $metadataDirectory -Force | Out-Null
}
$metadataJson = $metadata | ConvertTo-Json -Depth 12
[System.IO.File]::WriteAllText($resolvedMetadataPath, $metadataJson, [System.Text.UTF8Encoding]::new($false))
$metadataJson

exit 0

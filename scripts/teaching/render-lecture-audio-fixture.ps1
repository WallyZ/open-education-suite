[CmdletBinding()]
param(
    [string]$ManifestPath = '..\open-education-game-development\generated-lectures\gdev-101-design-vocabulary\lecture-video.json',
    [string]$MetadataPath = '..\open-education-game-development\generated-lectures\gdev-101-design-vocabulary\lecture-rendered-media.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. .\scripts\teaching\lecture-paths.ps1

function ConvertTo-SafePathSegment {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return 'unnamed'
    }
    return ($Value -replace '[^A-Za-z0-9._-]', '_')
}

function Write-FallbackWave {
    param(
        [string]$Path,
        [int]$Seconds = 4
    )

    $sampleRate = 16000
    $channels = 1
    $bitsPerSample = 16
    $sampleCount = $sampleRate * $Seconds
    $dataLength = $sampleCount * 2
    $writer = [System.IO.BinaryWriter]::new([System.IO.File]::Open($Path, [System.IO.FileMode]::Create))
    try {
        $writer.Write([System.Text.Encoding]::ASCII.GetBytes('RIFF'))
        $writer.Write([int](36 + $dataLength))
        $writer.Write([System.Text.Encoding]::ASCII.GetBytes('WAVE'))
        $writer.Write([System.Text.Encoding]::ASCII.GetBytes('fmt '))
        $writer.Write([int]16)
        $writer.Write([short]1)
        $writer.Write([short]$channels)
        $writer.Write([int]$sampleRate)
        $writer.Write([int]($sampleRate * $channels * ($bitsPerSample / 8)))
        $writer.Write([short]($channels * ($bitsPerSample / 8)))
        $writer.Write([short]$bitsPerSample)
        $writer.Write([System.Text.Encoding]::ASCII.GetBytes('data'))
        $writer.Write([int]$dataLength)
        for ($i = 0; $i -lt $sampleCount; $i++) {
            $frequency = if (($i / $sampleRate) % 1 -lt 0.5) { 440 } else { 660 }
            $sample = [Math]::Sin((2 * [Math]::PI * $frequency * $i) / $sampleRate)
            $writer.Write([short]($sample * 9000))
        }
    }
    finally {
        $writer.Dispose()
    }
}

function ConvertTo-SpokenLectureText {
    param([object]$Lecture)

    $text = [string]$Lecture.transcript.text
    if ([string]::IsNullOrWhiteSpace($text)) {
        $text = [string]$Lecture.script.text
    }
    if ([string]::IsNullOrWhiteSpace($text)) {
        return 'Open Education Suite generated lecture fixture.'
    }

    $text = $text -replace '\[[^\]]+\]', ''
    $text = $text -replace '#+', ''
    $text = $text -replace '\s+', ' '
    return $text.Trim()
}

function Get-PreferredVoiceInfo {
    param([object]$Synthesizer)

    $preferredVoiceNames = @(
        'Microsoft Zira',
        'Microsoft Zira Desktop',
        'Microsoft Mark',
        'Microsoft David',
        'Microsoft David Desktop'
    )
    $availableVoices = @($Synthesizer.GetInstalledVoices() | Where-Object { $_.Enabled } | ForEach-Object { $_.VoiceInfo })
    foreach ($preferredVoiceName in $preferredVoiceNames) {
        $matchedVoice = @($availableVoices | Where-Object { $_.Name -eq $preferredVoiceName } | Select-Object -First 1)
        if ($matchedVoice.Count -eq 1) {
            return $matchedVoice[0]
        }
    }

    $englishVoice = @($availableVoices | Where-Object { $_.Culture.Name -eq 'en-US' } | Select-Object -First 1)
    if ($englishVoice.Count -eq 1) {
        return $englishVoice[0]
    }

    if ($availableVoices.Count -gt 0) {
        return $availableVoices[0]
    }

    return $null
}

function Split-LectureSentences {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return @()
    }

    $normalizedText = $Text -replace '\s+', ' '
    return @([regex]::Split($normalizedText.Trim(), '(?<=[.!?])\s+') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function ConvertTo-NormalizedPromptText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ''
    }

    return (($Text.ToLowerInvariant() -replace '[^a-z0-9 ]', ' ') -replace '\s+', ' ').Trim()
}

function Get-PauseDurationForSentence {
    param(
        [string]$Sentence,
        [object[]]$PausePrompts
    )

    $normalizedSentence = ConvertTo-NormalizedPromptText -Text $Sentence
    foreach ($pausePrompt in @($PausePrompts)) {
        $prompt = [string]$pausePrompt.prompt
        $normalizedPrompt = ConvertTo-NormalizedPromptText -Text $prompt
        if (
            -not [string]::IsNullOrWhiteSpace($normalizedPrompt) -and
            ($normalizedSentence.Contains($normalizedPrompt) -or $normalizedPrompt.Contains($normalizedSentence))
        ) {
            return [Math]::Max(5, [int]$pausePrompt.durationSeconds)
        }
    }

    if ($normalizedSentence.StartsWith('pause here')) {
        return 8
    }

    return 0
}

function Add-SsmlEmphasis {
    param([string]$EscapedText)

    $result = $EscapedText
    foreach ($term in @('verb', 'goal', 'feedback', 'pause', 'rewrite', 'pen and paper')) {
        $pattern = "(?i)\b$([regex]::Escape($term))\b"
        $result = [regex]::Replace($result, $pattern, '<emphasis level="moderate">$0</emphasis>')
    }

    return $result
}

function New-LectureSsml {
    param(
        [string[]]$Sentences,
        [object[]]$PausePrompts
    )

    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.AppendLine('<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="en-US">')
    [void]$builder.AppendLine('  <p>')
    foreach ($sentence in @($Sentences)) {
        $escapedSentence = [System.Security.SecurityElement]::Escape($sentence)
        $emphasizedSentence = Add-SsmlEmphasis -EscapedText $escapedSentence
        $pauseDuration = Get-PauseDurationForSentence -Sentence $sentence -PausePrompts $PausePrompts
        $breakMarkup = if ($pauseDuration -gt 0) {
            "<break time=`"$($pauseDuration)s`"/>"
        }
        elseif ($sentence -match '^(Before we start|Today we will|After the video)') {
            '<break time="550ms"/>'
        }
        else {
            '<break time="300ms"/>'
        }

        [void]$builder.AppendLine("    <s>$emphasizedSentence</s>$breakMarkup")
    }
    [void]$builder.AppendLine('  </p>')
    [void]$builder.AppendLine('</speak>')

    return $builder.ToString()
}

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Missing lecture manifest: $ManifestPath"
}

$resolvedManifestPath = Resolve-LecturePath -Path $ManifestPath
$lecture = Get-Content -LiteralPath $resolvedManifestPath -Raw | ConvertFrom-Json
$assetRoot = Get-LectureAssetRoot -Lecture $lecture -ManifestPath $resolvedManifestPath
$outputDir = Get-LectureMediaDirectory -AssetRoot $assetRoot -Kind 'audio'
$createdDirectory = [System.IO.Directory]::CreateDirectory($outputDir)
$outputPath = Join-Path -Path $outputDir -ChildPath 'lecture-audio-wav.wav'

$spokenText = ConvertTo-SpokenLectureText -Lecture $lecture
$sentences = Split-LectureSentences -Text $spokenText
$pausePrompts = @($lecture.performancePlan.pausePrompts)
$pauseDurations = @($pausePrompts | ForEach-Object { [Math]::Max(5, [int]$_.durationSeconds) })
$insertedPauseSeconds = if ($pauseDurations.Count -gt 0) {
    [int]($pauseDurations | Measure-Object -Sum).Sum
}
else {
    0
}
$engine = 'windows-sapi-ssml'
$voiceProfile = [ordered]@{
    providerId = 'local-windows-sapi'
    selectedVoice = $null
    selectedVoiceCulture = $null
    availableVoices = @()
    preferredVoiceOrder = @(
        'Microsoft Zira',
        'Microsoft Zira Desktop',
        'Microsoft Mark',
        'Microsoft David',
        'Microsoft David Desktop'
    )
    synthRate = -1
    synthVolume = 92
    prosodyMode = 'ssml-sentence-breaks-emphasis-and-pause-silence'
    emphasizedTerms = @('verb', 'goal', 'feedback', 'pause', 'rewrite', 'pen and paper')
    sentenceBreakCount = $sentences.Count
    pausePromptCount = $pausePrompts.Count
    insertedPauseSeconds = $insertedPauseSeconds
    naturalnessTarget = 'Natural classroom delivery with human pacing, emphasis, and deliberate active-recall silence; neural TTS is still required for final publish-grade voice.'
}
try {
    Add-Type -AssemblyName System.Speech
    $synth = [System.Speech.Synthesis.SpeechSynthesizer]::new()
    try {
        $availableVoiceInfos = @($synth.GetInstalledVoices() | Where-Object { $_.Enabled } | ForEach-Object { $_.VoiceInfo })
        $voiceProfile.availableVoices = @($availableVoiceInfos | ForEach-Object { $_.Name })
        $selectedVoice = Get-PreferredVoiceInfo -Synthesizer $synth
        if ($null -eq $selectedVoice) {
            throw 'No enabled System.Speech voices are installed.'
        }

        $synth.SelectVoice($selectedVoice.Name)
        $voiceProfile.selectedVoice = $selectedVoice.Name
        $voiceProfile.selectedVoiceCulture = $selectedVoice.Culture.Name
        $synth.Rate = [int]$voiceProfile.synthRate
        $synth.Volume = [int]$voiceProfile.synthVolume
        $synth.SetOutputToWaveFile($outputPath)
        $ssml = New-LectureSsml -Sentences $sentences -PausePrompts $pausePrompts
        $synth.SpeakSsml($ssml)
    }
    finally {
        $synth.Dispose()
    }
}
catch {
    $engine = 'deterministic-tone-fallback'
    Write-FallbackWave -Path $outputPath
}

$file = Get-Item -LiteralPath $outputPath
$hash = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash.ToLowerInvariant()
$relativeOutputPath = ConvertTo-LectureContentRelativePath -ContentRoot ([string]$assetRoot.contentRoot) -Path $outputPath

$metadata = [ordered]@{
    schemaVersion = 1
    packageId = $lecture.packageId
    assetId = 'lecture-audio-wav-fixture'
    type = 'audio/wav'
    path = $relativeOutputPath
    sha256 = $hash
    status = 'archived'
    requiredForPublish = $false
    renderEngine = $engine
    voiceProfile = $voiceProfile
    length = $file.Length
    notes = 'Expressive local WAV fixture rendered from the GDEV-101 lecture package with selected installed voice, SSML sentence pacing, vocabulary emphasis, and active-recall pause silence. This is better than flat SAPI output but neural TTS is still required for final publish-grade natural voice.'
}

$json = $metadata | ConvertTo-Json -Depth 6
if (-not [string]::IsNullOrWhiteSpace($MetadataPath)) {
    $resolvedMetadataPath = Resolve-LecturePath -Path $MetadataPath
    $metadataDirectory = Split-Path -Parent $resolvedMetadataPath
    if (-not (Test-Path -LiteralPath $metadataDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $metadataDirectory -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($resolvedMetadataPath, $json, [System.Text.UTF8Encoding]::new($false))
}

$json

exit 0

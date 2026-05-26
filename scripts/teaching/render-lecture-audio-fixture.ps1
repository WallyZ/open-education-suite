[CmdletBinding()]
param(
    [string]$ManifestPath = '.\fixtures\lecture-video.gdev-101-design-vocabulary.json',
    [string]$OutputRoot = '.\var\lecture-media'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Missing lecture manifest: $ManifestPath"
}

$lecture = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$sourceId = [string]$lecture.contentSource.sourceId
$safePackageId = ConvertTo-SafePathSegment -Value ([string]$lecture.packageId)
$outputDir = Join-Path -Path $OutputRoot -ChildPath "$sourceId\$safePackageId\audio"
$createdDirectory = [System.IO.Directory]::CreateDirectory($outputDir)
$outputPath = Join-Path -Path $outputDir -ChildPath 'lecture-audio-wav.wav'

$spokenText = 'Open Education Suite generated lecture fixture. Today we use three design words precisely: verb, goal, and feedback. A verb is what the player can do. A goal is what the player is trying to accomplish. Feedback is how the game tells the player what changed.'
$engine = 'windows-sapi'
try {
    Add-Type -AssemblyName System.Speech
    $synth = [System.Speech.Synthesis.SpeechSynthesizer]::new()
    try {
        $synth.Rate = 0
        $synth.Volume = 85
        $synth.SetOutputToWaveFile($outputPath)
        $synth.Speak($spokenText)
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

[ordered]@{
    schemaVersion = 1
    packageId = $lecture.packageId
    assetId = 'lecture-audio-wav-fixture'
    type = 'audio/wav'
    path = $outputPath
    sha256 = $hash
    status = 'archived'
    renderEngine = $engine
    length = $file.Length
} | ConvertTo-Json -Depth 6

exit 0

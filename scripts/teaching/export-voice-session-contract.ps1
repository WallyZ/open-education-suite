[CmdletBinding()]
param(
    [string]$ManifestPath = '..\open-education-game-development\generated-lectures\gdev-101-design-vocabulary\lecture-video.json',
    [string]$AudioMetadataPath = '..\open-education-game-development\generated-lectures\gdev-101-design-vocabulary\lecture-rendered-media.json',
    [string]$OutputPath = '',
    [ValidateSet('teleprompter', 'practice', 'corpus_capture')]
    [string]$Mode = 'practice',
    [ValidateRange(80, 220)]
    [int]$TargetWpm = 145
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. .\scripts\teaching\lecture-paths.ps1

function ConvertTo-SafeContractId {
    param([string]$Value)

    $text = ([string]$Value).ToLowerInvariant()
    $text = $text -replace '[^a-z0-9._-]+', '-'
    $text = $text.Trim('-_.')
    if ([string]::IsNullOrWhiteSpace($text)) {
        return 'unnamed'
    }
    if ($text -notmatch '^[a-z0-9]') {
        $text = "id-$text"
    }
    return $text
}

function Test-HasText {
    param([object]$Value)
    return -not [string]::IsNullOrWhiteSpace([string]$Value)
}

function Get-ObjectPropertyValue {
    param(
        [object]$InputObject,
        [string]$Name,
        [object]$Default = $null
    )

    if ($null -ne $InputObject -and $InputObject.PSObject.Properties.Name -contains $Name) {
        return $InputObject.$Name
    }
    return $Default
}

function Get-SegmentPurpose {
    param(
        [int]$Index,
        [int]$Count,
        [string]$Label
    )

    if ($Index -eq 0) {
        return 'hook'
    }
    if ($Index -eq ($Count - 1)) {
        return 'closing'
    }
    if ($Label -match '(?i)practice|checkpoint|pause') {
        return 'practice_drill'
    }
    return 'body'
}

function Get-SpeakerRef {
    param([object]$Lecture)

    $gender = [string](Get-ObjectPropertyValue -InputObject (Get-ObjectPropertyValue -InputObject $Lecture -Name 'generatedInstructor') -Name 'gender' -Default 'synthetic')
    if (-not (Test-HasText $gender)) {
        $gender = 'synthetic'
    }
    return ConvertTo-SafeContractId -Value "oes-generated-instructor-$gender-synthetic"
}

function Get-SafeSessionId {
    param([object]$Lecture)

    $packageId = [string](Get-ObjectPropertyValue -InputObject $Lecture -Name 'packageId' -Default 'lecture')
    return ConvertTo-SafeContractId -Value "$packageId-voice-session"
}

function New-VoiceSessionSegments {
    param(
        [object]$Lecture,
        [string]$ScriptRef
    )

    $segments = @()
    $boardStates = @($Lecture.performancePlan.visualSync.boardStates)
    for ($index = 0; $index -lt $boardStates.Count; $index++) {
        $state = $boardStates[$index]
        $stateId = ConvertTo-SafeContractId -Value ([string](Get-ObjectPropertyValue -InputObject $state -Name 'stateId' -Default "board-$($index + 1)"))
        $label = [string](Get-ObjectPropertyValue -InputObject $state -Name 'label' -Default $stateId)
        $startSecond = [double](Get-ObjectPropertyValue -InputObject $state -Name 'startSecond' -Default 0)
        $endSecond = [double](Get-ObjectPropertyValue -InputObject $state -Name 'endSecond' -Default ($startSecond + 30))
        $estimatedSeconds = [Math]::Max(1, [Math]::Round($endSecond - $startSecond, 2))
        $segments += [ordered]@{
            segment_id = $stateId
            purpose = Get-SegmentPurpose -Index $index -Count $boardStates.Count -Label $label
            text_ref = "$ScriptRef#$stateId"
            estimated_seconds = $estimatedSeconds
            delivery_notes = "Lecture section ref only; no raw script text or audio path is included."
        }
    }

    foreach ($pausePrompt in @($Lecture.performancePlan.pausePrompts)) {
        $promptId = ConvertTo-SafeContractId -Value ([string](Get-ObjectPropertyValue -InputObject $pausePrompt -Name 'promptId' -Default 'pause-prompt'))
        $durationSeconds = [double](Get-ObjectPropertyValue -InputObject $pausePrompt -Name 'durationSeconds' -Default 10)
        $segments += [ordered]@{
            segment_id = "pause-$promptId"
            purpose = 'practice_drill'
            text_ref = "$ScriptRef#pause-$promptId"
            estimated_seconds = [Math]::Max(1, [Math]::Round($durationSeconds, 2))
            delivery_notes = "Active-recall pause segment; prompt text is resolved only by the consumer lecture package."
        }
    }

    if ($segments.Count -lt 1) {
        $segments += [ordered]@{
            segment_id = 'lecture-body'
            purpose = 'body'
            text_ref = "$ScriptRef#body"
            estimated_seconds = [Math]::Max(1, [double](Get-ObjectPropertyValue -InputObject $Lecture -Name 'durationSeconds' -Default 60))
            delivery_notes = 'Fallback lecture body segment.'
        }
    }

    return $segments
}

function Get-AllowedArtifactRefs {
    param([object]$AudioMetadata)

    $refs = @()
    $assetId = [string](Get-ObjectPropertyValue -InputObject $AudioMetadata -Name 'assetId' -Default '')
    if (Test-HasText $assetId) {
        $refs += (ConvertTo-SafeContractId -Value $assetId)
    }
    $renderEngine = [string](Get-ObjectPropertyValue -InputObject $AudioMetadata -Name 'renderEngine' -Default '')
    if (Test-HasText $renderEngine) {
        $refs += (ConvertTo-SafeContractId -Value "render-engine-$renderEngine")
    }
    if ($refs.Count -lt 1) {
        $refs += 'lecture-audio-metadata-logical-ref'
    }
    return @($refs)
}

function Write-Utf8NoBomText {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Text
    )

    $fullPath = Resolve-LecturePath -Path $Path
    $parent = Split-Path -Parent $fullPath
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        [void][System.IO.Directory]::CreateDirectory($parent)
    }
    [System.IO.File]::WriteAllText($fullPath, $Text, [System.Text.UTF8Encoding]::new($false))
}

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Missing lecture manifest: $ManifestPath"
}

$resolvedManifestPath = Resolve-LecturePath -Path $ManifestPath
$lecture = Get-Content -LiteralPath $resolvedManifestPath -Raw | ConvertFrom-Json
$audioMetadata = $null
if (Test-Path -LiteralPath $AudioMetadataPath -PathType Leaf) {
    $audioMetadata = Get-Content -LiteralPath (Resolve-LecturePath -Path $AudioMetadataPath) -Raw | ConvertFrom-Json
}

$sessionId = Get-SafeSessionId -Lecture $lecture
$sourceId = [string](Get-ObjectPropertyValue -InputObject (Get-ObjectPropertyValue -InputObject $lecture -Name 'contentSource') -Name 'sourceId' -Default 'open-education')
$scriptRef = ConvertTo-SafeContractId -Value "$($lecture.packageId)-lecture-script"
$speakerRef = Get-SpeakerRef -Lecture $lecture
$segments = New-VoiceSessionSegments -Lecture $lecture -ScriptRef $scriptRef
$allowedArtifactRefs = Get-AllowedArtifactRefs -AudioMetadata $audioMetadata

$payload = [ordered]@{
    schema_version = 'voice-studio/session/v1'
    session_id = $sessionId
    channel_ref = ConvertTo-SafeContractId -Value $sourceId
    speaker_ref = $speakerRef
    script_ref = $scriptRef
    recording_plan = [ordered]@{
        mode = $Mode
        target_wpm = $TargetWpm
        environment_notes = 'Synthetic classroom lecture/practice session metadata only; raw audio and generated media stay in the owning consumer/content repo.'
        segments = $segments
    }
    privacy_boundary = [ordered]@{
        contains_raw_audio = $false
        contains_voiceprint = $false
        contains_model_artifact = $false
        private_artifacts_required = $false
        allowed_artifact_refs = $allowedArtifactRefs
    }
    qa_targets = [ordered]@{
        sample_rate_hz = 48000
        channels = 1
        max_peak_dbfs = -1.0
        max_noise_floor_dbfs = -60.0
        target_breath_seconds = 12.0
        max_monotony_score = 0.35
    }
    outputs = [ordered]@{
        metadata_ref = "open-education-suite:voice-session:${sessionId}:metadata"
        qa_report_ref = "open-education-suite:voice-session:${sessionId}:qa"
        consumer_handoff_ref = "open-education-suite:lecture:$scriptRef"
    }
}

$json = $payload | ConvertTo-Json -Depth 12
if (Test-HasText $OutputPath) {
    Write-Utf8NoBomText -Path $OutputPath -Text ($json + [Environment]::NewLine)
}

$json

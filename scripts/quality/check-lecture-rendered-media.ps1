[CmdletBinding()]
param(
    [string]$RenderedMediaPath = '..\open-education-game-development\generated-lectures\gdev-101-design-vocabulary\lecture-rendered-media.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. .\scripts\teaching\lecture-paths.ps1

function Add-MediaError {
    param(
        [System.Collections.Generic.List[string]]$Errors,
        [string]$Message
    )
    $Errors.Add($Message)
}

function Get-PropertyValue {
    param(
        [object]$InputObject,
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Get-Sha256 {
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

$errors = [System.Collections.Generic.List[string]]::new()

$resolvedRenderedMediaPath = Resolve-LecturePath -Path $RenderedMediaPath
if (-not (Test-Path -LiteralPath $resolvedRenderedMediaPath -PathType Leaf)) {
    Add-MediaError $errors "Missing rendered lecture media metadata: $RenderedMediaPath"
}

if ($errors.Count -eq 0) {
    $metadata = Get-Content -LiteralPath $resolvedRenderedMediaPath -Raw | ConvertFrom-Json
    $contentRoot = Get-LectureContentRoot -ManifestPath $resolvedRenderedMediaPath
    if ($metadata.schemaVersion -ne 1) {
        Add-MediaError $errors 'Rendered lecture media metadata schemaVersion must be 1.'
    }
    if ($metadata.packageId -ne 'lecture-video:gdev-101-design-vocabulary-short') {
        Add-MediaError $errors 'Rendered lecture media metadata must reference the GDEV lecture fixture.'
    }
    if ($metadata.assetId -ne 'lecture-audio-wav-fixture') {
        Add-MediaError $errors 'Rendered lecture media metadata must declare the deterministic audio fixture asset.'
    }
    if ($metadata.type -ne 'audio/wav') {
        Add-MediaError $errors 'Rendered lecture media fixture must be audio/wav.'
    }
    if (-not ([string]$metadata.path).StartsWith('generated-lectures\')) {
        Add-MediaError $errors 'Rendered lecture media fixture must live under the subject repo generated-lectures folder.'
    }
    if ($metadata.status -ne 'archived') {
        Add-MediaError $errors 'Rendered lecture media fixture must be archived.'
    }
    if ($metadata.renderEngine -ne 'windows-sapi-ssml') {
        Add-MediaError $errors 'Rendered lecture audio must use the expressive SSML SAPI renderer, not flat plain speech output.'
    }
    $voiceProfile = Get-PropertyValue -InputObject $metadata -Name 'voiceProfile'
    if ($null -eq $voiceProfile) {
        Add-MediaError $errors 'Rendered lecture audio metadata must include the voice profile used for the render.'
    }
    else {
        $selectedVoice = [string](Get-PropertyValue -InputObject $voiceProfile -Name 'selectedVoice')
        $availableVoices = @((Get-PropertyValue -InputObject $voiceProfile -Name 'availableVoices') | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        $prosodyMode = [string](Get-PropertyValue -InputObject $voiceProfile -Name 'prosodyMode')
        $naturalnessTarget = [string](Get-PropertyValue -InputObject $voiceProfile -Name 'naturalnessTarget')
        if ([string]::IsNullOrWhiteSpace($selectedVoice)) {
            Add-MediaError $errors 'Rendered lecture audio voice profile must record the selected installed voice.'
        }
        elseif (@($availableVoices | Where-Object { $_ -eq $selectedVoice }).Count -ne 1) {
            Add-MediaError $errors 'Rendered lecture audio selected voice must appear in the available voice list.'
        }
        if (-not $prosodyMode.Contains('ssml') -or -not $prosodyMode.Contains('pause-silence')) {
            Add-MediaError $errors 'Rendered lecture audio voice profile must record SSML prosody and pause-silence handling.'
        }
        if ([int](Get-PropertyValue -InputObject $voiceProfile -Name 'sentenceBreakCount') -lt 8) {
            Add-MediaError $errors 'Rendered lecture audio must be paced with sentence-level breaks.'
        }
        if ([int](Get-PropertyValue -InputObject $voiceProfile -Name 'pausePromptCount') -lt 1) {
            Add-MediaError $errors 'Rendered lecture audio must include at least one active-recall pause prompt.'
        }
        if ([int](Get-PropertyValue -InputObject $voiceProfile -Name 'insertedPauseSeconds') -lt 5) {
            Add-MediaError $errors 'Rendered lecture audio must insert real silence for active-recall pause prompts.'
        }
        if (-not $naturalnessTarget.ToLowerInvariant().Contains('natural classroom delivery')) {
            Add-MediaError $errors 'Rendered lecture audio voice profile must state the natural classroom delivery target.'
        }
    }
    if ([string]$metadata.sha256 -notmatch '^[a-f0-9]{64}$') {
        Add-MediaError $errors 'Rendered lecture media fixture must record a lowercase 64-character SHA-256 checksum.'
    }
    $resolvedMediaPath = Resolve-LectureContentPath -ContentRoot $contentRoot -Path ([string]$metadata.path)
    if (-not (Test-Path -LiteralPath $resolvedMediaPath -PathType Leaf)) {
        Add-MediaError $errors "Rendered lecture media file does not exist: $($metadata.path)"
    }
    else {
        $file = Get-Item -LiteralPath $resolvedMediaPath
        if ($file.Length -lt 10000) {
            Add-MediaError $errors 'Rendered lecture media file is too small to be a useful audio fixture.'
        }
        $actualHash = Get-Sha256 -Path $resolvedMediaPath
        if ($actualHash -ne $metadata.sha256) {
            Add-MediaError $errors 'Rendered lecture media SHA-256 does not match metadata.'
        }
        $bytes = [System.IO.File]::ReadAllBytes($resolvedMediaPath)
        $riff = [System.Text.Encoding]::ASCII.GetString($bytes, 0, 4)
        $wave = [System.Text.Encoding]::ASCII.GetString($bytes, 8, 4)
        if ($riff -ne 'RIFF' -or $wave -ne 'WAVE') {
            Add-MediaError $errors 'Rendered lecture media file must be a valid RIFF/WAVE file.'
        }
    }
}

[ordered]@{
    schemaVersion = 1
    checkedAt = (Get-Date).ToString('o')
    errorCount = $errors.Count
    errors = @($errors)
} | ConvertTo-Json -Depth 6

if ($errors.Count -gt 0) {
    exit 1
}

exit 0

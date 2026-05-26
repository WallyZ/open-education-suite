[CmdletBinding()]
param(
    [string]$RenderedMediaPath = '.\fixtures\lecture-rendered-media.gdev-101.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Add-MediaError {
    param(
        [System.Collections.Generic.List[string]]$Errors,
        [string]$Message
    )
    $Errors.Add($Message)
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

if (-not (Test-Path -LiteralPath $RenderedMediaPath -PathType Leaf)) {
    Add-MediaError $errors "Missing rendered lecture media metadata: $RenderedMediaPath"
}

if ($errors.Count -eq 0) {
    $metadata = Get-Content -LiteralPath $RenderedMediaPath -Raw | ConvertFrom-Json
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
    if (-not ([string]$metadata.path).Contains('var\lecture-media')) {
        Add-MediaError $errors 'Rendered lecture media fixture must live under var\lecture-media.'
    }
    if ($metadata.status -ne 'archived') {
        Add-MediaError $errors 'Rendered lecture media fixture must be archived.'
    }
    if ([string]$metadata.sha256 -notmatch '^[a-f0-9]{64}$') {
        Add-MediaError $errors 'Rendered lecture media fixture must record a lowercase 64-character SHA-256 checksum.'
    }
    if (-not (Test-Path -LiteralPath $metadata.path -PathType Leaf)) {
        Add-MediaError $errors "Rendered lecture media file does not exist: $($metadata.path)"
    }
    else {
        $file = Get-Item -LiteralPath $metadata.path
        if ($file.Length -lt 10000) {
            Add-MediaError $errors 'Rendered lecture media file is too small to be a useful audio fixture.'
        }
        $actualHash = Get-Sha256 -Path $metadata.path
        if ($actualHash -ne $metadata.sha256) {
            Add-MediaError $errors 'Rendered lecture media SHA-256 does not match metadata.'
        }
        $bytes = [System.IO.File]::ReadAllBytes($metadata.path)
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

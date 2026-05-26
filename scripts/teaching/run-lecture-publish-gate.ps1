[CmdletBinding()]
param(
    [string]$ManifestPath = '.\fixtures\lecture-video.gdev-101-design-vocabulary.json',
    [string]$WorkflowPath = '.\fixtures\lecture-operator-review-workflow.json',
    [string]$OperatorId = 'operator-fixture',
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

function Resolve-RepoPath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path -Path (Get-Location).Path -ChildPath $Path))
}

function ConvertTo-RepoRelativePath {
    param([string]$Path)

    $repoRoot = [System.IO.Path]::GetFullPath((Get-Location).Path)
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if (-not $fullPath.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside the repo: $Path"
    }

    return $fullPath.Substring($repoRoot.Length).TrimStart('\')
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

function Copy-JsonObject {
    param([object]$Value)
    return (($Value | ConvertTo-Json -Depth 40) | ConvertFrom-Json)
}

function Set-ReviewStageApproved {
    param(
        [object]$Stage,
        [string]$Reviewer,
        [string[]]$Evidence,
        [string]$Notes
    )

    $Stage.status = 'approved'
    $Stage.reviewer = $Reviewer
    $Stage.reviewedAt = '2026-05-26T12:00:00Z'
    $Stage.evidence = @($Evidence)
    $Stage.notes = $Notes
}

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Missing lecture manifest: $ManifestPath"
}
if (-not (Test-Path -LiteralPath $WorkflowPath -PathType Leaf)) {
    throw "Missing operator review workflow: $WorkflowPath"
}

$lecture = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$candidate = Copy-JsonObject -Value $lecture
$sourceId = [string]$lecture.contentSource.sourceId
$safePackageId = ConvertTo-SafePathSegment -Value ([string]$lecture.packageId)
$archiveRoot = "var\lecture-media\$sourceId\$safePackageId"
$publishReadyPath = "$archiveRoot\publish\lecture-video.publish-ready.json"
$requiredMedia = @(
    [ordered]@{
        assetId = 'lecture-audio-m4a'
        type = 'audio/mp4'
        path = "$archiveRoot\audio\lecture-audio-m4a.m4a"
    },
    [ordered]@{
        assetId = 'lecture-video-mp4'
        type = 'video/mp4'
        path = "$archiveRoot\video\lecture-video-mp4.mp4"
    }
)

foreach ($media in $requiredMedia) {
    $resolvedPath = Resolve-RepoPath -Path ([string]$media.path)
    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
        throw "Missing rendered publish media: $($media.path)"
    }
    $packageMedia = @($candidate.media | Where-Object { $_.assetId -eq $media.assetId })
    if ($packageMedia.Count -ne 1) {
        throw "Lecture package is missing required media asset: $($media.assetId)"
    }

    $packageMedia[0].type = $media.type
    $packageMedia[0].path = ConvertTo-RepoRelativePath -Path $resolvedPath
    $packageMedia[0].sha256 = Get-Sha256File -Path $resolvedPath
    $packageMedia[0].status = 'archived'
    $packageMedia[0].requiredForPublish = $true
}

$candidate.renderStatus = 'rendered-fixture'
$candidate.licenseAudit.requiredInstructionArchive = $publishReadyPath
$candidate.operatorReview.publishStatus = 'approved-for-publish'

foreach ($stage in @($candidate.operatorReview.stages)) {
    switch ($stage.stageId) {
        'media' {
            Set-ReviewStageApproved -Stage $stage -Reviewer $OperatorId -Evidence @(
                "Required media archived under $archiveRoot.",
                'SHA-256 checksums recorded for lecture-video-mp4 and lecture-audio-m4a.'
            ) -Notes 'Approved for deterministic rendered publish fixture.'
        }
        'final-package' {
            Set-ReviewStageApproved -Stage $stage -Reviewer $OperatorId -Evidence @(
                'All required review stages are approved.',
                "Publish-ready path recorded: $publishReadyPath"
            ) -Notes 'Approved for deterministic publish gate fixture.'
        }
        default {
            if ($stage.status -ne 'approved') {
                Set-ReviewStageApproved -Stage $stage -Reviewer $OperatorId -Evidence @("approved-$($stage.stageId)") -Notes 'Approved for deterministic publish gate fixture.'
            }
        }
    }
}

$candidate.operatorReview.finalApproval.status = 'approved'
$candidate.operatorReview.finalApproval.reviewer = $OperatorId
$candidate.operatorReview.finalApproval.reviewedAt = '2026-05-26T12:05:00Z'
$candidate.operatorReview.finalApproval.notes = "Final package approval recorded for $publishReadyPath."

$candidateJson = $candidate | ConvertTo-Json -Depth 40
$tempRoot = $null
$gateManifestPath = $null

try {
    if ($Apply) {
        $gateManifestPath = Resolve-RepoPath -Path $publishReadyPath
        $publishDirectory = Split-Path -Parent $gateManifestPath
        if (-not (Test-Path -LiteralPath $publishDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $publishDirectory -Force | Out-Null
        }
    }
    else {
        $tempRoot = Resolve-RepoPath -Path (".codex-cache\tmp\lecture-publish-gate_$([System.Guid]::NewGuid().ToString('N'))")
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
        $gateManifestPath = Join-Path -Path $tempRoot -ChildPath 'lecture-video.publish-ready.json'
    }

    Set-Content -LiteralPath $gateManifestPath -Value $candidateJson -Encoding UTF8

    $gateOutput = & .\scripts\quality\check-lecture-operator-review.ps1 -ManifestPath $gateManifestPath -WorkflowPath $WorkflowPath -RequirePublishReady 2>&1
    $gateExitCode = $LASTEXITCODE
    $gateResult = ($gateOutput | Out-String) | ConvertFrom-Json

    [ordered]@{
        schemaVersion = 1
        packageId = $candidate.packageId
        mode = $(if ($Apply) { 'apply' } else { 'dry-run' })
        publishReady = ($gateExitCode -eq 0 -and $gateResult.publishReady -eq $true)
        publishReadyPath = $publishReadyPath
        wrotePublishReadyPath = [bool]$Apply
        gateManifestPath = ConvertTo-RepoRelativePath -Path $gateManifestPath
        operatorGate = [ordered]@{
            exitCode = $gateExitCode
            publishReady = $gateResult.publishReady
            errorCount = $gateResult.errorCount
            errors = @($gateResult.errors)
        }
        media = @($requiredMedia | ForEach-Object {
            $path = Resolve-RepoPath -Path ([string]$_.path)
            [ordered]@{
                assetId = $_.assetId
                type = $_.type
                path = ConvertTo-RepoRelativePath -Path $path
                sha256 = Get-Sha256File -Path $path
                length = (Get-Item -LiteralPath $path).Length
                status = 'archived'
                requiredForPublish = $true
            }
        })
    } | ConvertTo-Json -Depth 10

    if ($gateExitCode -ne 0) {
        exit $gateExitCode
    }
}
finally {
    if ((-not $Apply) -and (Test-HasText $tempRoot) -and (Test-Path -LiteralPath $tempRoot -PathType Container)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

exit 0

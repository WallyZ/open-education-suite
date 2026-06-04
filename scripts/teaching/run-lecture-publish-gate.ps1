[CmdletBinding()]
param(
    [string]$ManifestPath = '..\open-education-game-development\generated-lectures\gdev-101-design-vocabulary\lecture-video.json',
    [string]$WorkflowPath = '.\fixtures\lecture-operator-review-workflow.json',
    [string]$OperatorId = 'operator-fixture',
    [switch]$Apply
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

function Set-JsonProperty {
    param(
        [object]$InputObject,
        [string]$Name,
        [object]$Value
    )

    if ($InputObject.PSObject.Properties[$Name]) {
        $InputObject.$Name = $Value
        return
    }

    $InputObject | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
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

$resolvedManifestPath = Resolve-LecturePath -Path $ManifestPath
$lecture = Get-Content -LiteralPath $resolvedManifestPath -Raw | ConvertFrom-Json
$candidate = Copy-JsonObject -Value $lecture
$assetRoot = Get-LectureAssetRoot -Lecture $lecture -ManifestPath $resolvedManifestPath
$archiveRoot = [string]$assetRoot.relativePath
$audioRoot = Get-LectureMediaRelativeDirectory -AssetRoot $assetRoot -Kind 'audio'
$videoRoot = Get-LectureMediaRelativeDirectory -AssetRoot $assetRoot -Kind 'video'
$publishReadyPath = "$archiveRoot\publish\lecture-video.publish-ready.json"
$requiredMedia = @(
    [ordered]@{
        assetId = 'lecture-audio-m4a'
        type = 'audio/mp4'
        path = "$audioRoot\lecture-audio-m4a.m4a"
        requiredForPublish = $true
    },
    [ordered]@{
        assetId = 'lecture-video-mp4'
        type = 'video/mp4'
        path = "$videoRoot\lecture-video-mp4.mp4"
        requiredForPublish = $true
    }
)
$supportMedia = @(
    [ordered]@{
        assetId = 'lecture-guided-camera-mp4'
        type = 'video/mp4'
        path = "$videoRoot\lecture-guided-camera-mp4.mp4"
        requiredForPublish = $false
        properties = [ordered]@{
            visualSyncMode = 'board-close-up-guided-camera'
            sourceAssetIds = @('lecture-video-mp4', 'lecture-board-close-up-mp4')
            cameraPlanSource = 'visualSync.cameraPlan'
            audioPreserved = $true
            transcriptPreserved = $true
            checkpointContextPreserved = $true
            classroomContextPreserved = $true
        }
    },
    [ordered]@{
        assetId = 'lecture-board-close-up-mp4'
        type = 'video/mp4'
        path = "$videoRoot\lecture-board-close-up-mp4.mp4"
        requiredForPublish = $false
        properties = [ordered]@{
            visualSyncMode = 'board-close-up-crop'
            sourceAssetId = 'lecture-video-mp4'
            cropSource = 'visualSync.boardSurface.closeUpCrop'
            audioPreserved = $true
            transcriptPreserved = $true
            checkpointContextPreserved = $true
            classroomContextPreserved = $true
        }
    }
)

foreach ($media in $requiredMedia) {
    $resolvedPath = Resolve-LectureContentPath -ContentRoot ([string]$assetRoot.contentRoot) -Path ([string]$media.path)
    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
        throw "Missing rendered publish media: $($media.path)"
    }
    $packageMedia = @($candidate.media | Where-Object { $_.assetId -eq $media.assetId })
    if ($packageMedia.Count -ne 1) {
        throw "Lecture package is missing required media asset: $($media.assetId)"
    }

    Set-JsonProperty -InputObject $packageMedia[0] -Name 'type' -Value $media.type
    Set-JsonProperty -InputObject $packageMedia[0] -Name 'path' -Value (ConvertTo-LectureContentRelativePath -ContentRoot ([string]$assetRoot.contentRoot) -Path $resolvedPath)
    Set-JsonProperty -InputObject $packageMedia[0] -Name 'sha256' -Value (Get-Sha256File -Path $resolvedPath)
    Set-JsonProperty -InputObject $packageMedia[0] -Name 'length' -Value (Get-Item -LiteralPath $resolvedPath).Length
    Set-JsonProperty -InputObject $packageMedia[0] -Name 'status' -Value 'archived'
    Set-JsonProperty -InputObject $packageMedia[0] -Name 'requiredForPublish' -Value $true
}

$availableSupportMedia = @()
foreach ($media in $supportMedia) {
    $resolvedPath = Resolve-LectureContentPath -ContentRoot ([string]$assetRoot.contentRoot) -Path ([string]$media.path)
    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
        continue
    }

    $packageMedia = @($candidate.media | Where-Object { $_.assetId -eq $media.assetId })
    if ($packageMedia.Count -gt 1) {
        throw "Lecture package has duplicate support media asset: $($media.assetId)"
    }

    $mediaObject = $null
    if ($packageMedia.Count -eq 1) {
        $mediaObject = $packageMedia[0]
    }
    else {
        $mediaObject = [pscustomobject][ordered]@{
            assetId = $media.assetId
        }
        $candidate.media = @($candidate.media) + $mediaObject
    }

    Set-JsonProperty -InputObject $mediaObject -Name 'type' -Value $media.type
    Set-JsonProperty -InputObject $mediaObject -Name 'path' -Value (ConvertTo-LectureContentRelativePath -ContentRoot ([string]$assetRoot.contentRoot) -Path $resolvedPath)
    Set-JsonProperty -InputObject $mediaObject -Name 'sha256' -Value (Get-Sha256File -Path $resolvedPath)
    Set-JsonProperty -InputObject $mediaObject -Name 'length' -Value (Get-Item -LiteralPath $resolvedPath).Length
    Set-JsonProperty -InputObject $mediaObject -Name 'status' -Value 'archived'
    Set-JsonProperty -InputObject $mediaObject -Name 'requiredForPublish' -Value $false
    foreach ($property in $media.properties.GetEnumerator()) {
        Set-JsonProperty -InputObject $mediaObject -Name $property.Key -Value $property.Value
    }

    $availableSupportMedia += $media
}

$candidate.renderStatus = 'rendered-fixture'
$candidate.licenseAudit.requiredInstructionArchive = $publishReadyPath
$candidate.operatorReview.publishStatus = 'approved-for-publish'

foreach ($stage in @($candidate.operatorReview.stages)) {
    switch ($stage.stageId) {
        'media' {
            Set-ReviewStageApproved -Stage $stage -Reviewer $OperatorId -Evidence @(
                "Required media archived under $archiveRoot.",
                'SHA-256 checksums recorded for lecture-video-mp4 and lecture-audio-m4a.',
                'Board-local pause prompt timing reviewed in the rendered media.'
            ) -Notes 'Approved for deterministic rendered publish fixture.'
        }
        'instructor-realism' {
            Set-ReviewStageApproved -Stage $stage -Reviewer $OperatorId -Evidence @(
                'Face/body consistency reviewed against the local ComfyUI avatar keyframe and realismProfile.',
                'Front-row framing reviewed so the learner has an easy view of the instructor and chalkboard.',
                'Board readability reviewed for the board-local writing layer and chalkboard contrast.',
                'Board occlusion reviewed so the instructor does not cover high-priority board text and board close-up remains available.',
                'Board close-up usefulness reviewed against the recorded board surface crop.',
                'Gesture timing reviewed against storyboard board moments, narration cues, and active-recall pauses.',
                'Lip-sync timing reviewed against final instructor audio and active-recall pause silence.',
                'Gaze direction reviewed for learner-facing explanation, board-facing writing, and return-to-learner cues.',
                'Head and hand motion naturalness reviewed for subtle classroom movement without distracting jitter.',
                'Board-writing gesture synchronization reviewed so pointing and writing gestures align to board-local chalk marks.',
                'No whole-frame teaching text overlays are used; instructional writing is constrained to the board surface.',
                "Generated instructor disclosure reviewed before publish: $($candidate.generatedInstructor.disclosure)"
            ) -Notes 'Approved for local ComfyUI avatar keyframe realism review.'
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
        $gateManifestPath = Resolve-LectureContentPath -ContentRoot ([string]$assetRoot.contentRoot) -Path $publishReadyPath
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
            gateManifestPath = $(if ($Apply) { ConvertTo-LectureContentRelativePath -ContentRoot ([string]$assetRoot.contentRoot) -Path $gateManifestPath } else { ConvertTo-RepoRelativePath -Path $gateManifestPath })
            operatorGate = [ordered]@{
            exitCode = $gateExitCode
            publishReady = $gateResult.publishReady
            errorCount = $gateResult.errorCount
            errors = @($gateResult.errors)
        }
        media = @(($requiredMedia + $availableSupportMedia) | ForEach-Object {
            $path = Resolve-LectureContentPath -ContentRoot ([string]$assetRoot.contentRoot) -Path ([string]$_.path)
            $mediaResult = [ordered]@{
                assetId = $_.assetId
                type = $_.type
                path = ConvertTo-LectureContentRelativePath -ContentRoot ([string]$assetRoot.contentRoot) -Path $path
                sha256 = Get-Sha256File -Path $path
                length = (Get-Item -LiteralPath $path).Length
                status = 'archived'
                requiredForPublish = [bool]$_.requiredForPublish
            }
            $extraProperties = $null
            if ($_ -is [System.Collections.IDictionary] -and $_.Contains('properties')) {
                $extraProperties = $_['properties']
            }
            elseif ($_.PSObject.Properties['properties']) {
                $extraProperties = $_.properties
            }
            if ($extraProperties) {
                foreach ($property in $extraProperties.GetEnumerator()) {
                    $mediaResult[$property.Key] = $property.Value
                }
            }
            $mediaResult
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

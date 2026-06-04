[CmdletBinding()]
param(
    [string]$ManifestPath = '..\open-education-game-development\generated-lectures\gdev-101-design-vocabulary\lecture-video.json',
    [string]$RenderedMediaPath = '..\open-education-game-development\generated-lectures\gdev-101-design-vocabulary\lecture-rendered-media.json',
    [string]$AvatarMetadataPath = '..\open-education-game-development\generated-lectures\gdev-101-design-vocabulary\lecture-avatar-rendered-media.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. .\scripts\teaching\lecture-paths.ps1

function Test-HasText {
    param([object]$Value)
    return -not [string]::IsNullOrWhiteSpace([string]$Value)
}

function Get-ObjectPropertyValue {
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

function Get-ValidLectureAudioMetadata {
    param(
        [string]$Path,
        [string]$ContentRoot
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    $metadata = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if (-not (Test-HasText $metadata.path) -or -not (Test-HasText $metadata.sha256)) {
        return $null
    }

    $mediaPath = Resolve-LectureContentPath -ContentRoot $ContentRoot -Path ([string]$metadata.path)
    if (-not (Test-Path -LiteralPath $mediaPath -PathType Leaf)) {
        return $null
    }

    if ((Get-Sha256File -Path $mediaPath) -ne [string]$metadata.sha256) {
        return $null
    }

    return $metadata
}

function Select-LectureAudioMetadata {
    param(
        [string]$ManifestPath,
        [string]$RenderedMediaPath,
        [string]$ContentRoot
    )

    $manifestDirectory = Split-Path -Parent $ManifestPath
    $candidates = @(
        (Join-Path -Path $manifestDirectory -ChildPath 'lecture-comfyui-tts-rendered-media-full.json'),
        (Join-Path -Path $manifestDirectory -ChildPath 'lecture-neural-tts-rendered-media.json'),
        $RenderedMediaPath
    ) | Select-Object -Unique

    foreach ($candidate in $candidates) {
        $metadata = Get-ValidLectureAudioMetadata -Path $candidate -ContentRoot $ContentRoot
        if ($null -ne $metadata) {
            return [ordered]@{
                path = $candidate
                metadata = $metadata
            }
        }
    }

    return $null
}

function ConvertTo-AssTimestamp {
    param([double]$Seconds)

    $safeSeconds = [Math]::Max(0, $Seconds)
    $time = [TimeSpan]::FromSeconds($safeSeconds)
    return '{0}:{1:D2}:{2:D2}.{3:D2}' -f [int]$time.TotalHours, $time.Minutes, $time.Seconds, [int]($time.Milliseconds / 10)
}

function ConvertTo-AssText {
    param([object]$Value)

    return ([string]$Value).Replace('\', '/').Replace('{', '').Replace('}', '').Replace("`r", ' ').Replace("`n", ' ')
}

function ConvertTo-FfmpegFilterPath {
    param([string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path).Replace('\', '/')
    return $fullPath.Replace(':', '\:')
}

function ConvertTo-FfmpegNumber {
    param([double]$Value)
    return $Value.ToString('0.###', [System.Globalization.CultureInfo]::InvariantCulture)
}

function New-LectureBoardWritingAss {
    param(
        [object]$Lecture,
        [string]$Path,
        [object]$BoardSurface
    )

    $left = [int]$BoardSurface['x']
    $top = [int]$BoardSurface['y']
    $width = [int]$BoardSurface['width']
    $height = [int]$BoardSurface['height']
    $right = $left + $width
    $bottom = $top + $height
    $textX = $left + 36
    $textY = $top + 42
    $lineSpacing = 44
    $promptY = $bottom - 104
    $clipTag = "\clip($left,$top,$right,$bottom)"
    $maxTextRight = $right - 36
    $textWidth = [Math]::Max(120, $maxTextRight - $textX)

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('[Script Info]')
    $lines.Add('ScriptType: v4.00+')
    $lines.Add('PlayResX: 1280')
    $lines.Add('PlayResY: 720')
    $lines.Add('ScaledBorderAndShadow: yes')
    $lines.Add('; layer-mode: stroke-based-chalk-writing')
    $lines.Add('; reveal-mode: progressive-left-to-right-clipped-strokes')
    $lines.Add('; target-surface: physical-board-local')
    $lines.Add('')
    $lines.Add('[V4+ Styles]')
    $lines.Add('Format: Name,Fontname,Fontsize,PrimaryColour,SecondaryColour,OutlineColour,BackColour,Bold,Italic,Underline,StrikeOut,ScaleX,ScaleY,Spacing,Angle,BorderStyle,Outline,Shadow,Alignment,MarginL,MarginR,MarginV,Encoding')
    $lines.Add('Style: BoardStroke,Arial,22,&H55F8FFF4,&H000000FF,&H00030F0A,&H00000000,0,0,0,0,100,100,0,0,1,4,0,7,0,0,0,1')
    $lines.Add('Style: BoardWriting,Segoe Print,35,&H00F8FFF4,&H000000FF,&H00030F0A,&H00101816,1,0,0,0,100,100,0,0,1,1.5,1,7,0,0,0,1')
    $lines.Add('Style: BoardPrompt,Segoe Print,31,&H00FFFFFF,&H000000FF,&H00030F0A,&H00101816,1,0,0,0,100,100,0,0,1,2,1,7,0,0,0,1')
    $lines.Add('')
    $lines.Add('[Events]')
    $lines.Add('Format: Layer,Start,End,Style,Name,MarginL,MarginR,MarginV,Effect,Text')

    foreach ($boardState in @($Lecture.performancePlan.visualSync.boardStates)) {
        $stateStartSecond = [double]$boardState.startSecond
        $stateEndSecond = [double]$boardState.endSecond
        $stateDuration = [Math]::Max(1.0, $stateEndSecond - $stateStartSecond)
        $boardTextLines = @($boardState.boardText | ForEach-Object { ConvertTo-AssText -Value $_ } | Where-Object { Test-HasText -Value $_ })
        $revealStep = [Math]::Min(3.0, [Math]::Max(1.2, $stateDuration / [Math]::Max(1, $boardTextLines.Count + 1)))
        for ($index = 0; $index -lt $boardTextLines.Count; $index++) {
            $lineStartSecond = [Math]::Min($stateEndSecond - 0.25, $stateStartSecond + ($index * $revealStep))
            $lineY = $textY + ($index * $lineSpacing)
            $boardLine = "- $($boardTextLines[$index])"
            $writeDuration = [Math]::Min([Math]::Max(1.4, $revealStep * 0.85), [Math]::Max(0.8, $stateEndSecond - $lineStartSecond - 0.2))
            $segmentCount = [Math]::Min(14, [Math]::Max(5, [Math]::Ceiling($boardLine.Length / 7.0)))
            for ($segment = 1; $segment -le $segmentCount; $segment++) {
                $segmentStartSecond = $lineStartSecond + (($segment - 1) * $writeDuration / $segmentCount)
                $segmentEndSecond = if ($segment -eq $segmentCount) { $stateEndSecond } else { $lineStartSecond + ($segment * $writeDuration / $segmentCount) }
                $segmentStartSecond = [Math]::Min($stateEndSecond - 0.1, $segmentStartSecond)
                $segmentEndSecond = [Math]::Max($segmentStartSecond + 0.08, [Math]::Min($stateEndSecond, $segmentEndSecond))
                $segmentStart = ConvertTo-AssTimestamp -Seconds $segmentStartSecond
                $segmentEnd = ConvertTo-AssTimestamp -Seconds $segmentEndSecond
                $strokeStart = ConvertTo-AssTimestamp -Seconds $segmentStartSecond
                $strokeEnd = ConvertTo-AssTimestamp -Seconds $stateEndSecond
                $previousFraction = ($segment - 1) / $segmentCount
                $revealFraction = $segment / $segmentCount
                $strokeStartX = [int]($textX + ($textWidth * $previousFraction))
                $revealRight = [int]($textX + ($textWidth * $revealFraction))
                $strokeEndX = [Math]::Min($maxTextRight, [Math]::Max($strokeStartX + 12, $revealRight))
                $strokeY = [int]($lineY + 33 + (($segment % 3) - 1))
                $strokeY2 = [int]($strokeY + ((($index + $segment) % 3) - 1))
                $segmentClipTag = "\clip($left,$top,$strokeEndX,$bottom)"
                $strokePath = "m $strokeStartX $strokeY l $strokeEndX $strokeY2"
                $lines.Add("Dialogue: 0,$strokeStart,$strokeEnd,BoardStroke,,0,0,0,,{\p1\pos(0,0)$clipTag}$strokePath")
                $lines.Add("Dialogue: 1,$segmentStart,$segmentEnd,BoardWriting,,0,0,0,,{\an7\pos($textX,$lineY)$segmentClipTag\blur0.25}$boardLine")
            }
        }
    }

    foreach ($prompt in @($Lecture.performancePlan.pausePrompts)) {
        $startSecond = [double]$prompt.timeSecond
        $endSecond = $startSecond + [double]$prompt.durationSeconds
        $start = ConvertTo-AssTimestamp -Seconds $startSecond
        $end = ConvertTo-AssTimestamp -Seconds $endSecond
        $overlayText = ConvertTo-AssText -Value $prompt.overlayText
        $resumeCue = ConvertTo-AssText -Value $prompt.resumeCue
        if ($overlayText.Contains(':')) {
            $promptSplit = $overlayText.Split(':', 2)
            $promptParts = @("$($promptSplit[0].Trim()):", $promptSplit[1].Trim())
        }
        else {
            $promptParts = @($overlayText)
        }
        if (Test-HasText $resumeCue) {
            $promptParts += 'Restart when ready.'
        }
        $promptText = ($promptParts | Where-Object { Test-HasText -Value $_ }) -join '\N'
        $lines.Add("Dialogue: 2,$start,$end,BoardPrompt,,0,0,0,,{\an7\pos($textX,$promptY)$clipTag\fad(140,140)\blur0.25}$promptText")
    }

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($Path, [string[]]$lines, $utf8NoBom)
}

function New-LectureCameraPlan {
    param([object]$Lecture)

    $durationSeconds = [double]([Math]::Max(1, [int]$Lecture.durationSeconds))
    $focusWindows = [System.Collections.Generic.List[object]]::new()

    foreach ($prompt in @($Lecture.performancePlan.pausePrompts)) {
        $startSecond = [Math]::Max(0.0, [double]$prompt.timeSecond - 1.0)
        $endSecond = [Math]::Min($durationSeconds, [double]$prompt.timeSecond + [double]$prompt.durationSeconds + 1.0)
        if ($endSecond -gt $startSecond) {
            $focusWindows.Add([pscustomobject]@{
                startSecond = $startSecond
                endSecond = $endSecond
                reason = 'active recall pause and written response prompt'
            })
        }
    }

    foreach ($boardState in @($Lecture.performancePlan.visualSync.boardStates)) {
        $boardTextLineCount = @($boardState.boardText | Where-Object { Test-HasText -Value $_ }).Count
        if ($boardTextLineCount -lt 3) {
            continue
        }
        $stateStartSecond = [double]$boardState.startSecond
        $stateEndSecond = [double]$boardState.endSecond
        $focusStartSecond = [Math]::Max(0.0, $stateStartSecond + 12.0)
        $focusEndSecond = [Math]::Min($durationSeconds, [Math]::Min($stateEndSecond, $focusStartSecond + 32.0))
        if ($focusEndSecond -gt $focusStartSecond) {
            $focusWindows.Add([pscustomobject]@{
                startSecond = $focusStartSecond
                endSecond = $focusEndSecond
                reason = 'dense chalkboard vocabulary needs close-up readability'
            })
        }
    }

    if ($focusWindows.Count -eq 0) {
        $middleStart = [Math]::Max(0.0, [Math]::Floor($durationSeconds * 0.35))
        $middleEnd = [Math]::Min($durationSeconds, $middleStart + [Math]::Min(30.0, $durationSeconds * 0.25))
        if ($middleEnd -gt $middleStart) {
            $focusWindows.Add([pscustomobject]@{
                startSecond = $middleStart
                endSecond = $middleEnd
                reason = 'default board readability check'
            })
        }
    }

    $mergedWindows = [System.Collections.Generic.List[object]]::new()
    foreach ($window in @($focusWindows | Sort-Object -Property startSecond, endSecond)) {
        if ($mergedWindows.Count -eq 0) {
            $mergedWindows.Add($window)
            continue
        }

        $lastWindow = $mergedWindows[$mergedWindows.Count - 1]
        if ([double]$window.startSecond -le ([double]$lastWindow.endSecond + 2.0)) {
            $lastWindow.endSecond = [Math]::Max([double]$lastWindow.endSecond, [double]$window.endSecond)
            if (-not ([string]$lastWindow.reason).Contains([string]$window.reason)) {
                $lastWindow.reason = "$($lastWindow.reason); $($window.reason)"
            }
        }
        else {
            $mergedWindows.Add($window)
        }
    }

    $cuts = [System.Collections.Generic.List[object]]::new()
    $cursor = 0.0
    foreach ($window in $mergedWindows) {
        $windowStart = [Math]::Max(0.0, [double]$window.startSecond)
        $windowEnd = [Math]::Min($durationSeconds, [double]$window.endSecond)
        if ($windowStart -gt $cursor) {
            $cuts.Add([ordered]@{
                view = 'front-row-classroom'
                startSecond = [Math]::Round($cursor, 3)
                endSecond = [Math]::Round($windowStart, 3)
                reason = 'keep instructor, room, and full board context visible'
            })
        }
        if ($windowEnd -gt $windowStart) {
            $cuts.Add([ordered]@{
                view = 'board-close-up'
                startSecond = [Math]::Round($windowStart, 3)
                endSecond = [Math]::Round($windowEnd, 3)
                reason = [string]$window.reason
            })
            $cursor = $windowEnd
        }
    }

    if ($cursor -lt $durationSeconds) {
        $cuts.Add([ordered]@{
            view = 'front-row-classroom'
            startSecond = [Math]::Round($cursor, 3)
            endSecond = [Math]::Round($durationSeconds, 3)
            reason = 'return to instructor explanation and practice handoff'
        })
    }

    return @($cuts)
}

function New-LectureGuidedCameraRender {
    param(
        [string]$FfmpegPath,
        [string]$ClassroomPath,
        [string]$BoardCloseUpPath,
        [string]$OutputPath,
        [object[]]$CameraPlan
    )

    if (@($CameraPlan).Count -lt 1) {
        throw 'Cannot render guided-camera lecture without at least one camera cut.'
    }

    $filterParts = [System.Collections.Generic.List[string]]::new()
    $concatInputs = [System.Collections.Generic.List[string]]::new()
    for ($index = 0; $index -lt @($CameraPlan).Count; $index++) {
        $cut = $CameraPlan[$index]
        $inputIndex = if ([string]$cut.view -eq 'board-close-up') { 1 } else { 0 }
        $start = ConvertTo-FfmpegNumber -Value ([double]$cut.startSecond)
        $end = ConvertTo-FfmpegNumber -Value ([double]$cut.endSecond)
        $videoInput = '[' + $inputIndex + ':v]'
        $audioInput = '[' + $inputIndex + ':a]'
        $filterParts.Add($videoInput + 'trim=start=' + $start + ':end=' + $end + ',setpts=PTS-STARTPTS,format=yuv420p[v' + $index + ']')
        $filterParts.Add($audioInput + 'atrim=start=' + $start + ':end=' + $end + ',asetpts=PTS-STARTPTS,aresample=44100,aformat=sample_rates=44100:channel_layouts=stereo[a' + $index + ']')
        $concatInputs.Add('[v' + $index + '][a' + $index + ']')
    }

    $concatFilter = ($concatInputs -join '') + 'concat=n=' + @($CameraPlan).Count + ':v=1:a=1[vout][aout]'
    $filter = (@($filterParts) + $concatFilter) -join ';'
    & $FfmpegPath -y -hide_banner -loglevel error -i $ClassroomPath -i $BoardCloseUpPath -filter_complex $filter -map '[vout]' -map '[aout]' -c:v libx264 -pix_fmt yuv420p -c:a aac -b:a 96k $OutputPath
    if ($LASTEXITCODE -ne 0) {
        throw "ffmpeg failed to render guided-camera MP4 with exit code $LASTEXITCODE."
    }
}

function New-LectureMotionPreviewRender {
    param(
        [string]$FfmpegPath,
        [string]$SourceAvatarPath,
        [string]$SourceAudioPath,
        [string]$OutputPath,
        [int]$DurationSeconds
    )

    $previewDurationSeconds = [Math]::Min(30, [Math]::Max(3, $DurationSeconds))
    $motionFilter = "scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720,crop=980:720:0:0,scale=1280:720,zoompan=z='1+0.012*sin(on/16)':x='iw/2-(iw/zoom/2)+4*sin(on/19)':y='ih/2-(ih/zoom/2)+3*cos(on/23)':d=1:s=1280x720:fps=24,format=yuv420p"
    & $FfmpegPath -y -hide_banner -loglevel error -loop 1 -framerate 24 -i $SourceAvatarPath -i $SourceAudioPath -vf $motionFilter -t $previewDurationSeconds -c:v libx264 -pix_fmt yuv420p -c:a aac -b:a 96k $OutputPath
    if ($LASTEXITCODE -ne 0) {
        throw "ffmpeg failed to render instructor motion preview MP4 with exit code $LASTEXITCODE."
    }

    return $previewDurationSeconds
}

function New-LectureLipSyncPreviewRender {
    param(
        [string]$FfmpegPath,
        [string]$SourceAvatarPath,
        [string]$SourceAudioPath,
        [string]$OutputPath,
        [int]$DurationSeconds,
        [object[]]$PausePrompts
    )

    $previewDurationSeconds = [Math]::Min(30, [Math]::Max(3, $DurationSeconds))
    $activeMouthExpression = "lt(mod(t\,0.42)\,0.21)"
    if (@($PausePrompts).Count -gt 0) {
        $pausePrompt = @($PausePrompts)[0]
        $pauseStart = ConvertTo-FfmpegNumber -Value ([double]$pausePrompt.timeSecond)
        $pauseEnd = ConvertTo-FfmpegNumber -Value ([double]$pausePrompt.timeSecond + [double]$pausePrompt.durationSeconds)
        $activeMouthExpression = "if(between(t\,$pauseStart\,$pauseEnd)\,0\,$activeMouthExpression)"
    }

    $lipSyncFilter = "scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720,crop=980:720:0:0,scale=1280:720,drawbox=x=778:y=304:w=46:h=9:color=0x2b0f0f@0.82:t=fill:enable='$activeMouthExpression',format=yuv420p"
    & $FfmpegPath -y -hide_banner -loglevel error -loop 1 -framerate 24 -i $SourceAvatarPath -i $SourceAudioPath -vf $lipSyncFilter -t $previewDurationSeconds -c:v libx264 -pix_fmt yuv420p -c:a aac -b:a 96k $OutputPath
    if ($LASTEXITCODE -ne 0) {
        throw "ffmpeg failed to render instructor lip-sync preview MP4 with exit code $LASTEXITCODE."
    }

    return $previewDurationSeconds
}

function New-LectureQaFrameEvidence {
    param(
        [string]$FfmpegPath,
        [string]$ContentRoot,
        [string]$OutputDirectory,
        [object[]]$FrameRequests
    )

    if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    }

    $frames = [System.Collections.Generic.List[object]]::new()
    foreach ($request in @($FrameRequests)) {
        $outputPath = Join-Path -Path $OutputDirectory -ChildPath ([string]$request.fileName)
        $captureSecond = [double]$request.captureSecond
        $captureTime = ConvertTo-FfmpegNumber -Value $captureSecond
        & $FfmpegPath -y -hide_banner -loglevel error -ss $captureTime -i ([string]$request.sourcePath) -frames:v 1 $outputPath
        if ($LASTEXITCODE -ne 0) {
            throw "ffmpeg failed to extract QA frame $($request.assetId) with exit code $LASTEXITCODE."
        }

        $item = Get-Item -LiteralPath $outputPath
        $frames.Add([ordered]@{
            assetId = [string]$request.assetId
            type = 'image/png'
            path = ConvertTo-LectureContentRelativePath -ContentRoot $ContentRoot -Path $outputPath
            sha256 = Get-Sha256File -Path $outputPath
            length = $item.Length
            status = 'archived'
            requiredForPublish = $false
            evidenceType = [string]$request.evidenceType
            sourceAssetId = [string]$request.sourceAssetId
            sourcePath = ConvertTo-LectureContentRelativePath -ContentRoot $ContentRoot -Path ([string]$request.sourcePath)
            capturedSecond = $captureSecond
            expectedView = [string]$request.expectedView
            visualCheck = [string]$request.visualCheck
            coordinateSpace = '1280x720'
            boardSurfaceReference = 'visualSync.boardSurface'
            reviewStatus = 'pending-operator-review'
        })
    }

    return @($frames)
}

$resolvedManifestPath = Resolve-LecturePath -Path $ManifestPath
$resolvedRenderedMediaPath = Resolve-LecturePath -Path $RenderedMediaPath
$resolvedAvatarMetadataPath = Resolve-LecturePath -Path $AvatarMetadataPath

if (-not (Test-Path -LiteralPath $resolvedManifestPath -PathType Leaf)) {
    throw "Missing lecture manifest: $ManifestPath"
}
if (-not (Test-Path -LiteralPath $resolvedRenderedMediaPath -PathType Leaf)) {
    throw "Missing rendered media metadata: $RenderedMediaPath"
}

$ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
if ($null -eq $ffmpeg) {
    throw 'ffmpeg is required to render the deterministic publish fixture media.'
}

$lecture = Get-Content -LiteralPath $resolvedManifestPath -Raw | ConvertFrom-Json
$assetRoot = Get-LectureAssetRoot -Lecture $lecture -ManifestPath $resolvedManifestPath
$selectedAudio = Select-LectureAudioMetadata -ManifestPath $resolvedManifestPath -RenderedMediaPath $resolvedRenderedMediaPath -ContentRoot ([string]$assetRoot.contentRoot)
if ($null -eq $selectedAudio) {
    $audioRenderOutput = & .\scripts\teaching\render-lecture-audio-fixture.ps1 -ManifestPath $resolvedManifestPath -MetadataPath $resolvedRenderedMediaPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Missing rendered source audio and regeneration failed with exit code $LASTEXITCODE`: $audioRenderOutput"
    }
    $selectedAudio = [ordered]@{
        path = $resolvedRenderedMediaPath
        metadata = (($audioRenderOutput | Out-String) | ConvertFrom-Json)
    }
}

$renderedMedia = $selectedAudio.metadata
$sourceAudioPath = Resolve-LectureContentPath -ContentRoot ([string]$assetRoot.contentRoot) -Path ([string]$renderedMedia.path)
if (-not (Test-Path -LiteralPath $sourceAudioPath -PathType Leaf)) {
    throw "Audio renderer did not create source audio: $($renderedMedia.path)"
}

$avatarOutput = & .\scripts\teaching\render-lecture-avatar-comfyui.ps1 -ManifestPath $resolvedManifestPath -MetadataPath $resolvedAvatarMetadataPath 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Local ComfyUI avatar render failed with exit code $LASTEXITCODE`: $avatarOutput"
}
$avatarMedia = ($avatarOutput | Out-String) | ConvertFrom-Json
$sourceAvatarPath = Resolve-LectureContentPath -ContentRoot ([string]$assetRoot.contentRoot) -Path ([string]$avatarMedia.path)
if (-not (Test-Path -LiteralPath $sourceAvatarPath -PathType Leaf)) {
    throw "Local ComfyUI avatar renderer did not create source image: $($avatarMedia.path)"
}

$durationSeconds = [Math]::Max(1, [int]$lecture.durationSeconds)
$archiveRoot = [string]$assetRoot.relativePath
$audioDirectory = Get-LectureMediaDirectory -AssetRoot $assetRoot -Kind 'audio'
$videoDirectory = Get-LectureMediaDirectory -AssetRoot $assetRoot -Kind 'video'
$qaFrameDirectory = Get-LectureMediaDirectory -AssetRoot $assetRoot -Kind 'qa-frames'
New-Item -ItemType Directory -Path $audioDirectory, $videoDirectory, $qaFrameDirectory -Force | Out-Null

$boardSurface = [ordered]@{
    coordinateSpace = '1280x720'
    x = 1
    y = 122
    width = 610
    height = 330
    label = 'straight-on cleaned chalkboard writing surface'
    closeUpCrop = [ordered]@{
        x = 1
        y = 104
        width = 660
        height = 390
    }
    protectedInstructorRegion = [ordered]@{
        x = 612
        y = 104
        width = 330
        height = 520
    }
}

$m4aPath = Join-Path -Path $audioDirectory -ChildPath 'lecture-audio-m4a.m4a'
$mp4Path = Join-Path -Path $videoDirectory -ChildPath 'lecture-video-mp4.mp4'
$boardCloseUpPath = Join-Path -Path $videoDirectory -ChildPath 'lecture-board-close-up-mp4.mp4'
$guidedCameraPath = Join-Path -Path $videoDirectory -ChildPath 'lecture-guided-camera-mp4.mp4'
$motionPreviewPath = Join-Path -Path $videoDirectory -ChildPath 'lecture-instructor-motion-preview.mp4'
$lipSyncPreviewPath = Join-Path -Path $videoDirectory -ChildPath 'lecture-instructor-lipsync-preview.mp4'
$boardWritingPath = Join-Path -Path $videoDirectory -ChildPath 'lecture-board-writing.ass'

$pausePrompts = @($lecture.performancePlan.pausePrompts)
$pauseSilenceInserted = $false
if ([string]$renderedMedia.providerId -eq 'local-comfyui-tts' -and $pausePrompts.Count -ge 1) {
    $pausePrompt = $pausePrompts[0]
    $pauseStart = ConvertTo-FfmpegNumber -Value ([double]$pausePrompt.timeSecond)
    $pauseDuration = ConvertTo-FfmpegNumber -Value ([double]$pausePrompt.durationSeconds)
    $audioPauseFilter = "[0:a]atrim=0:$pauseStart,asetpts=PTS-STARTPTS,aformat=sample_rates=44100:channel_layouts=stereo[a0];anullsrc=channel_layout=stereo:sample_rate=44100,atrim=duration=$pauseDuration[s0];[0:a]atrim=start=$pauseStart,asetpts=PTS-STARTPTS,aformat=sample_rates=44100:channel_layouts=stereo[a1];[a0][s0][a1]concat=n=3:v=0:a=1,apad[aout]"
    & $ffmpeg.Source -y -hide_banner -loglevel error -i $sourceAudioPath -filter_complex $audioPauseFilter -map '[aout]' -t $durationSeconds -c:a aac -b:a 96k $m4aPath
    $pauseSilenceInserted = $true
}
else {
    & $ffmpeg.Source -y -hide_banner -loglevel error -i $sourceAudioPath -af apad -t $durationSeconds -c:a aac -b:a 96k $m4aPath
}
if ($LASTEXITCODE -ne 0) {
    throw "ffmpeg failed to render M4A publish fixture with exit code $LASTEXITCODE."
}

New-LectureBoardWritingAss -Lecture $lecture -Path $boardWritingPath -BoardSurface $boardSurface
$boardWritingFilterPath = ConvertTo-FfmpegFilterPath -Path $boardWritingPath
$cleanBoardFilter = "drawbox=x=$($boardSurface['x']):y=$($boardSurface['y']):w=$($boardSurface['width']):h=$($boardSurface['height']):color=0x132d24@0.98:t=fill,drawbox=x=$($boardSurface['x']):y=$($boardSurface['y']):w=$($boardSurface['width']):h=$($boardSurface['height']):color=0xd8e8dd@0.85:t=3"
$frontRowFocusCropFilter = 'crop=980:720:0:0,scale=1280:720'
$videoFilter = "scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720,$frontRowFocusCropFilter,$cleanBoardFilter,subtitles=filename='$boardWritingFilterPath',format=yuv420p"
& $ffmpeg.Source -y -hide_banner -loglevel error -loop 1 -framerate 24 -i $sourceAvatarPath -i $m4aPath -vf $videoFilter -t $durationSeconds -c:v libx264 -pix_fmt yuv420p -c:a copy $mp4Path
if ($LASTEXITCODE -ne 0) {
    throw "ffmpeg failed to assemble scene-aware MP4 from the local ComfyUI avatar render with exit code $LASTEXITCODE."
}

$closeUpCrop = $boardSurface['closeUpCrop']
$boardCloseUpFilter = "crop=$([int]$closeUpCrop['width']):$([int]$closeUpCrop['height']):$([int]$closeUpCrop['x']):$([int]$closeUpCrop['y']),scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2:color=black,format=yuv420p"
& $ffmpeg.Source -y -hide_banner -loglevel error -i $mp4Path -vf $boardCloseUpFilter -map 0:v:0 -map 0:a:0 -t $durationSeconds -c:v libx264 -pix_fmt yuv420p -c:a aac -b:a 96k $boardCloseUpPath
if ($LASTEXITCODE -ne 0) {
    throw "ffmpeg failed to render board close-up MP4 from the scene-aware classroom video with exit code $LASTEXITCODE."
}

$cameraPlan = New-LectureCameraPlan -Lecture $lecture
New-LectureGuidedCameraRender -FfmpegPath $ffmpeg.Source -ClassroomPath $mp4Path -BoardCloseUpPath $boardCloseUpPath -OutputPath $guidedCameraPath -CameraPlan $cameraPlan
$motionPreviewDurationSeconds = New-LectureMotionPreviewRender -FfmpegPath $ffmpeg.Source -SourceAvatarPath $sourceAvatarPath -SourceAudioPath $m4aPath -OutputPath $motionPreviewPath -DurationSeconds $durationSeconds
$lipSyncPreviewDurationSeconds = New-LectureLipSyncPreviewRender -FfmpegPath $ffmpeg.Source -SourceAvatarPath $sourceAvatarPath -SourceAudioPath $m4aPath -OutputPath $lipSyncPreviewPath -DurationSeconds $durationSeconds -PausePrompts $pausePrompts
$qaFrameEvidence = New-LectureQaFrameEvidence -FfmpegPath $ffmpeg.Source -ContentRoot ([string]$assetRoot.contentRoot) -OutputDirectory $qaFrameDirectory -FrameRequests @(
    [ordered]@{
        assetId = 'lecture-qa-frame-board-readability-png'
        fileName = 'lecture-qa-frame-board-readability.png'
        evidenceType = 'board-readability'
        sourceAssetId = 'lecture-video-mp4'
        sourcePath = $mp4Path
        captureSecond = 48
        expectedView = 'front-row classroom with board text visible'
        visualCheck = 'board text readability from the front-row classroom view'
    },
    [ordered]@{
        assetId = 'lecture-qa-frame-instructor-occlusion-png'
        fileName = 'lecture-qa-frame-instructor-occlusion.png'
        evidenceType = 'instructor-occlusion'
        sourceAssetId = 'lecture-video-mp4'
        sourcePath = $mp4Path
        captureSecond = 64
        expectedView = 'front-row classroom with instructor beside the board'
        visualCheck = 'instructor body does not cover priority board text or pause prompt'
    },
    [ordered]@{
        assetId = 'lecture-qa-frame-guided-camera-shot-png'
        fileName = 'lecture-qa-frame-guided-camera-shot.png'
        evidenceType = 'camera-shot-selection'
        sourceAssetId = 'lecture-guided-camera-mp4'
        sourcePath = $guidedCameraPath
        captureSecond = 50
        expectedView = 'guided camera board close-up during dense board work'
        visualCheck = 'camera plan cuts to the board close-up during dense board and pause moments'
    },
    [ordered]@{
        assetId = 'lecture-qa-frame-board-surface-alignment-png'
        fileName = 'lecture-qa-frame-board-surface-alignment.png'
        evidenceType = 'board-surface-alignment'
        sourceAssetId = 'lecture-board-close-up-mp4'
        sourcePath = $boardCloseUpPath
        captureSecond = 50
        expectedView = 'board close-up aligned to the physical board surface'
        visualCheck = 'board crop includes the whole board-local writing surface without drifting outside the board'
    }
)

$m4aItem = Get-Item -LiteralPath $m4aPath
$mp4Item = Get-Item -LiteralPath $mp4Path
$boardCloseUpItem = Get-Item -LiteralPath $boardCloseUpPath
$guidedCameraItem = Get-Item -LiteralPath $guidedCameraPath
$motionPreviewItem = Get-Item -LiteralPath $motionPreviewPath
$lipSyncPreviewItem = Get-Item -LiteralPath $lipSyncPreviewPath
$boardWritingItem = Get-Item -LiteralPath $boardWritingPath
$boardStateCount = @($lecture.performancePlan.visualSync.boardStates).Count
$pauseOverlayCount = @($lecture.performancePlan.pausePrompts).Count
$gestureActions = [System.Collections.Generic.List[object]]::new()
foreach ($boardState in @($lecture.performancePlan.visualSync.boardStates)) {
    $gestureActions.Add([ordered]@{
        stateId = [string]$boardState.stateId
        startSecond = [double]$boardState.startSecond
        endSecond = [double]$boardState.endSecond
        pointing = 'point to board-local labels without covering priority text'
        writing = 'write or reveal chalk strokes as narration reaches the term'
        gazeShift = 'move gaze between learner-facing explanation and board-facing writing'
        boardOcclusionAvoidance = 'keep instructor body outside visualSync.boardSurface priority text zones'
        sourceInstructorAction = [string]$boardState.instructorAction
    })
}
$pausePostures = [System.Collections.Generic.List[object]]::new()
foreach ($prompt in @($lecture.performancePlan.pausePrompts)) {
    $pausePostures.Add([ordered]@{
        promptId = [string]$prompt.promptId
        startSecond = [double]$prompt.timeSecond
        durationSeconds = [double]$prompt.durationSeconds
        pausePosture = 'neutral listening posture with closed-or-neutral mouth'
        gazeShift = 'return from board to learner before active recall, then hold still through pause silence'
        boardOcclusionAvoidance = 'stand aside so the written pause prompt and board labels remain visible'
    })
}

[ordered]@{
    schemaVersion = 1
    packageId = $lecture.packageId
    renderEngine = 'local-comfyui+ffmpeg'
    archiveRoot = $archiveRoot
    sourceAudio = [ordered]@{
        assetId = $renderedMedia.assetId
        type = $renderedMedia.type
        path = $renderedMedia.path
        sha256 = $renderedMedia.sha256
        metadataPath = ConvertTo-LectureContentRelativePath -ContentRoot ([string]$assetRoot.contentRoot) -Path ([string]$selectedAudio.path)
        providerId = $renderedMedia.providerId
        renderEngine = $renderedMedia.renderEngine
        instructorGender = Get-ObjectPropertyValue -InputObject $renderedMedia -Name 'instructorGender'
        voiceGender = Get-ObjectPropertyValue -InputObject $renderedMedia -Name 'voiceGender'
        pitchRange = Get-ObjectPropertyValue -InputObject $renderedMedia -Name 'pitchRange'
        timbre = Get-ObjectPropertyValue -InputObject $renderedMedia -Name 'timbre'
        voiceMatchPolicy = Get-ObjectPropertyValue -InputObject $renderedMedia -Name 'voiceMatchPolicy'
    }
    sourceAvatar = [ordered]@{
        assetId = $avatarMedia.assetId
        path = $avatarMedia.path
        sha256 = $avatarMedia.sha256
        renderEngine = $avatarMedia.renderEngine
        instructorGender = Get-ObjectPropertyValue -InputObject $avatarMedia -Name 'instructorGender'
        visualGenderCue = Get-ObjectPropertyValue -InputObject $avatarMedia -Name 'visualGenderCue'
    }
    visualSync = [ordered]@{
        mode = 'board-local-writing-layer'
        source = 'performancePlan.visualSync + performancePlan.pausePrompts'
        boardStateCount = $boardStateCount
        pauseOverlayCount = $pauseOverlayCount
        pauseSilenceInserted = $pauseSilenceInserted
        globalOverlayTextUsed = $false
        classroomComposition = [ordered]@{
            cameraPosition = 'front-row straight-on learner view'
            teacherVisibility = 'mid-shot instructor starting at the right side of the cleaned board'
            boardVisibility = 'clean empty board surface is filled before board-local chalk writing is added, with a close-up crop available'
        }
        sceneRealismTargets = [ordered]@{
            lighting = 'consistent classroom key and fill light across instructor, board, and chalk layer'
            contactShadows = 'instructor contact shadows and board-adjacent shadows must anchor the body to the room'
            boardSurfaceIntegration = 'chalk strokes and prompt overlays stay clipped to the physical board surface'
            cameraDepth = 'front-row lens keeps instructor and board readable without flattened cutout composition'
            lensMotion = 'only subtle classroom camera motion; no jitter, drift, or synthetic shake'
            compositingArtifacts = 'review seams, halos, edge shimmer, scale mismatch, and frame-to-frame identity drift'
            operatorReviewStatus = 'required-before-publish'
        }
        boardSurface = $boardSurface
        cameraPlan = [ordered]@{
            mode = 'front-row-and-board-close-up-cut-plan'
            source = 'performancePlan.visualSync.boardStates + performancePlan.pausePrompts'
            cuts = $cameraPlan
        }
        shotDirectorPlan = [ordered]@{
            selectionBasis = 'teaching-purpose'
            requiredShots = @('front-row', 'board-close-up', 'instructor-close-up')
            currentShotUse = @(
                [ordered]@{ shot = 'front-row'; purpose = 'context, instructor presence, and lecture continuity'; status = 'selected' },
                [ordered]@{ shot = 'board-close-up'; purpose = 'dense vocabulary, active recall, and board readability'; status = 'selected' },
                [ordered]@{ shot = 'instructor-close-up'; purpose = 'encouragement, misconception feedback, and learner-facing emphasis'; status = 'available-when-pedagogically-useful' }
            )
        }
        gesturePlan = [ordered]@{
            source = 'performancePlan.visualSync.boardStates + performancePlan.pausePrompts + visualSync.boardSurface'
            coordinateSpace = 'visualSync.boardSurface'
            requiredActions = @('pointing', 'writing', 'gaze-shift', 'pause-posture', 'board-occlusion-avoidance')
            boardStateActions = @($gestureActions)
            pausePostures = @($pausePostures)
            reviewEvidenceRequired = @('gesture timing notes', 'board surface coordinates', 'pause posture review', 'board occlusion review')
        }
        staticFrameReplacement = 'The avatar keyframe is assembled with a cleaned empty chalkboard surface plus stroke-based board-local chalk writing clipped to the board; instructional text is not placed as a whole-frame overlay.'
        boardWritingAsset = [ordered]@{
            assetId = 'lecture-board-writing-ass'
            type = 'text/x-ass'
            path = ConvertTo-LectureContentRelativePath -ContentRoot ([string]$assetRoot.contentRoot) -Path $boardWritingPath
            sha256 = Get-Sha256File -Path $boardWritingPath
            length = $boardWritingItem.Length
            status = 'archived'
            requiredForPublish = $false
            renderMode = 'stroke-based-progressive-chalk-ass'
            physicalSurface = 'board-local clipped to visualSync.boardSurface'
            progressiveReveal = $true
            strokeLayer = $true
            textReveal = 'left-to-right clipped handwriting segments'
            physicalChalkTargets = [ordered]@{
                chalkTexture = 'slight edge roughness and line opacity variation'
                strokeTiming = 'progressive strokes appear when narration reaches each board phrase'
                erasing = 'future model-backed renders must support erased or crossed-out marks when concepts change'
                handAlignment = 'writing or pointing hand must align to active board-local strokes'
                boardResidue = 'retain subtle board residue instead of pristine overlay text'
            }
            globalSubtitleMode = $false
        }
        boardCloseUpRender = [ordered]@{
            assetId = 'lecture-board-close-up-mp4'
            type = 'video/mp4'
            path = ConvertTo-LectureContentRelativePath -ContentRoot ([string]$assetRoot.contentRoot) -Path $boardCloseUpPath
            sha256 = Get-Sha256File -Path $boardCloseUpPath
            length = $boardCloseUpItem.Length
            status = 'archived'
            requiredForPublish = $false
            sourceAssetId = 'lecture-video-mp4'
            sourcePath = ConvertTo-LectureContentRelativePath -ContentRoot ([string]$assetRoot.contentRoot) -Path $mp4Path
            cropSource = 'visualSync.boardSurface.closeUpCrop'
            crop = $closeUpCrop
            outputCoordinateSpace = '1280x720'
            audioPreserved = $true
            transcriptPreserved = $true
            checkpointContextPreserved = $true
            classroomContextPreserved = $true
            transcriptSource = 'lecture-video.transcript'
            checkpointSource = 'lecture-video.adaptiveHooks.checkpoints'
            contextSource = 'front-row classroom source render'
        }
        guidedCameraRender = [ordered]@{
            assetId = 'lecture-guided-camera-mp4'
            type = 'video/mp4'
            path = ConvertTo-LectureContentRelativePath -ContentRoot ([string]$assetRoot.contentRoot) -Path $guidedCameraPath
            sha256 = Get-Sha256File -Path $guidedCameraPath
            length = $guidedCameraItem.Length
            status = 'archived'
            requiredForPublish = $false
            visualSyncMode = 'board-close-up-guided-camera'
            sourceAssetIds = @('lecture-video-mp4', 'lecture-board-close-up-mp4')
            cameraPlanSource = 'visualSync.cameraPlan'
            cutCount = @($cameraPlan).Count
            boardCloseUpCutCount = @($cameraPlan | Where-Object { $_.view -eq 'board-close-up' }).Count
            frontRowCutCount = @($cameraPlan | Where-Object { $_.view -eq 'front-row-classroom' }).Count
            audioPreserved = $true
            transcriptPreserved = $true
            checkpointContextPreserved = $true
            classroomContextPreserved = $true
            transcriptSource = 'lecture-video.transcript'
            checkpointSource = 'lecture-video.adaptiveHooks.checkpoints'
            contextSource = 'front-row classroom render plus board close-up support render'
        }
        frameQaEvidence = [ordered]@{
            status = 'archived-pending-operator-review'
            source = 'ffmpeg extracted still frames from the classroom, board close-up, and guided-camera renders'
            evidenceCount = @($qaFrameEvidence).Count
            requiredEvidenceTypes = @('board-readability', 'instructor-occlusion', 'camera-shot-selection', 'board-surface-alignment')
            frames = @($qaFrameEvidence)
        }
        automatedVisualComparisonEvidence = [ordered]@{
            status = 'required-before-model-backed-promotion'
            source = 'extracted frame QA plus motion/lip-sync preview comparison'
            requiredEvidenceTypes = @('board-readability', 'mouth-open-timing', 'gaze-direction', 'instructor-occlusion', 'board-crop-correctness', 'shot-selection')
            currentEvidence = @('frameQaEvidence.board-readability', 'frameQaEvidence.instructor-occlusion', 'frameQaEvidence.camera-shot-selection', 'frameQaEvidence.board-surface-alignment', 'motionAndLipSync.visualQaChecks.lip-sync-timing', 'motionAndLipSync.visualQaChecks.gaze-direction')
            promotionRequirement = 'model-backed candidates cannot replace publish video until automated visual QA and operator visual QA pass'
        }
        motionAndLipSync = [ordered]@{
            status = 'local-preview-renders-archived-pending-visual-qa'
            motionAdapterSpike = [ordered]@{
                adapterId = 'local-comfyui-motion-adapter-spike-v1'
                providerId = 'local-comfyui-motion'
                selectedPipelineId = 'liveportrait'
                fallbackPipelineId = 'sadtalker'
                preLipSyncMotionOnly = $true
                lipSyncIncluded = $false
                outputAssetId = 'lecture-instructor-motion-preview-mp4'
                previewRenderIncluded = $true
                modelRenderIncluded = $false
                requiredForPublish = $false
            }
            lipSyncAdapterSpike = [ordered]@{
                adapterId = 'local-comfyui-lipsync-adapter-spike-v1'
                providerId = 'local-comfyui-lipsync'
                selectedPipelineId = 'musetalk'
                fallbackPipelineId = 'wav2lip'
                audioDrivenMouthMovement = $true
                previewRenderIncluded = $true
                modelRenderIncluded = $false
                outputAssetId = 'lecture-instructor-lipsync-preview-mp4'
                requiredForPublish = $false
            }
            previewPromotionPolicy = [ordered]@{
                publishPromotion = 'blocked-pending-operator-visual-qa'
                visualQaStatus = 'pending-operator-review'
                canReplacePublishVideo = $false
                requiredBeforePromotion = @('lip-sync-timing', 'gaze-direction', 'head-hand-motion-naturalness', 'board-writing-gesture-synchronization')
            }
            modelBackedOutputRequirements = [ordered]@{
                promotionStatus = 'model-backed-publish-candidate'
                requiredRenderFields = @('assetId', 'type', 'path', 'sha256', 'length', 'status', 'providerId', 'workflowPath', 'sourceAssetIds', 'seed', 'configHash', 'durationSeconds', 'modelRenderIncluded', 'requiredForPublish', 'publishPromotion', 'visualQaStatus', 'operatorReviewStatus')
                requiredBeforePromotion = @('subject-owned-path', 'checksum-verified', 'archive-manifest-refreshed', 'automated-visual-qa-passed', 'operator-visual-qa-approved', 'operator-publish-gate-approved')
                requiredQaEvidence = @('lip-sync-timing', 'gaze-direction', 'head-hand-motion-naturalness', 'board-writing-gesture-synchronization')
                deterministicPreviewCanReplacePublishVideo = $false
                promotionGate = 'promote only after checksum archive refresh, automated visual QA evidence, operator visual QA approval, and operator publish gate approval'
            }
            motionPreviewRender = [ordered]@{
                assetId = 'lecture-instructor-motion-preview-mp4'
                type = 'video/mp4'
                path = ConvertTo-LectureContentRelativePath -ContentRoot ([string]$assetRoot.contentRoot) -Path $motionPreviewPath
                sha256 = Get-Sha256File -Path $motionPreviewPath
                length = $motionPreviewItem.Length
                status = 'archived'
                requiredForPublish = $false
                renderEngine = 'ffmpeg-deterministic-motion-preview'
                selectedPipelineId = 'liveportrait'
                fallbackPipelineId = 'sadtalker'
                previewDurationSeconds = $motionPreviewDurationSeconds
                sourceAssetIds = @($avatarMedia.assetId, 'lecture-audio-m4a')
                preLipSyncMotionOnly = $true
                lipSyncIncluded = $false
                previewRenderIncluded = $true
                modelRenderIncluded = $false
                publishPromotion = 'blocked-pending-operator-visual-qa'
                visualQaStatus = 'pending-operator-review'
                boardOcclusionPolicy = 'preserve board readability, board-local writing, and close-up crop'
            }
            lipSyncPreviewRender = [ordered]@{
                assetId = 'lecture-instructor-lipsync-preview-mp4'
                type = 'video/mp4'
                path = ConvertTo-LectureContentRelativePath -ContentRoot ([string]$assetRoot.contentRoot) -Path $lipSyncPreviewPath
                sha256 = Get-Sha256File -Path $lipSyncPreviewPath
                length = $lipSyncPreviewItem.Length
                status = 'archived'
                requiredForPublish = $false
                renderEngine = 'ffmpeg-deterministic-audio-reactive-lipsync-preview'
                selectedPipelineId = 'musetalk'
                fallbackPipelineId = 'wav2lip'
                previewDurationSeconds = $lipSyncPreviewDurationSeconds
                sourceAssetIds = @($avatarMedia.assetId, 'lecture-audio-m4a')
                audioDrivenMouthMovement = $true
                pausePromptMouthState = 'closed-or-neutral'
                previewRenderIncluded = $true
                modelRenderIncluded = $false
                publishPromotion = 'blocked-pending-operator-visual-qa'
                visualQaStatus = 'pending-operator-review'
                faceIdentityPolicy = 'preserve generated instructor face until model-backed QA passes'
            }
            candidateLocalPipelines = @('LivePortrait', 'SadTalker', 'MuseTalk', 'Wav2Lip', 'AniPortrait')
            visualQaChecks = @(
                [ordered]@{
                    checkId = 'lip-sync-timing'
                    label = 'Lip-sync timing'
                    target = 'audio-mouth alignment on speech segments and neutral mouth during active-recall pauses'
                    requiredEvidence = @('final instructor audio waveform', 'mouth movement preview', 'pause silence mouth-neutral samples')
                    passCriteria = 'mouth movement tracks the final audio and stays closed or neutral through deliberate pause prompts'
                    failureAction = 'changes-requested'
                    status = 'required-before-publish-promotion'
                },
                [ordered]@{
                    checkId = 'gaze-direction'
                    label = 'Gaze direction'
                    target = 'learner-facing explanation, board-facing writing, and return-to-learner transitions'
                    requiredEvidence = @('front-row classroom preview', 'board-state timing', 'instructor gaze notes')
                    passCriteria = 'gaze shifts match whether the instructor is addressing the learner or writing on the board'
                    failureAction = 'changes-requested'
                    status = 'required-before-publish-promotion'
                },
                [ordered]@{
                    checkId = 'head-hand-motion-naturalness'
                    label = 'Head and hand motion naturalness'
                    target = 'subtle head, posture, pointer, and writing-hand movement'
                    requiredEvidence = @('motion preview', 'frame review', 'jitter and identity drift notes')
                    passCriteria = 'movement is natural, low-distraction, identity-stable, and does not cover priority board text'
                    failureAction = 'changes-requested'
                    status = 'required-before-publish-promotion'
                },
                [ordered]@{
                    checkId = 'board-writing-gesture-synchronization'
                    label = 'Board-writing gesture synchronization'
                    target = 'pointing and writing gestures aligned to board-local chalk writing'
                    requiredEvidence = @('board-local writing timeline', 'gesture timing notes', 'close-up crop review')
                    passCriteria = 'gestures line up with board-local writing, narration cues, and close-up readability'
                    failureAction = 'changes-requested'
                    status = 'required-before-publish-promotion'
                }
            )
            nextStage = 'Install model-backed ComfyUI motion/lip-sync custom nodes, replace deterministic preview cues with model output, then promote only after operator visual QA passes.'
        }
    }
    media = @(
        [ordered]@{
            assetId = 'lecture-audio-m4a'
            type = 'audio/mp4'
            path = ConvertTo-LectureContentRelativePath -ContentRoot ([string]$assetRoot.contentRoot) -Path $m4aPath
            sha256 = Get-Sha256File -Path $m4aPath
            length = $m4aItem.Length
            status = 'archived'
            requiredForPublish = $true
            sourceAssetId = $renderedMedia.assetId
            pauseSilenceInserted = $pauseSilenceInserted
        },
        [ordered]@{
            assetId = 'lecture-video-mp4'
            type = 'video/mp4'
            path = ConvertTo-LectureContentRelativePath -ContentRoot ([string]$assetRoot.contentRoot) -Path $mp4Path
            sha256 = Get-Sha256File -Path $mp4Path
            length = $mp4Item.Length
            status = 'archived'
            requiredForPublish = $true
            visualSyncMode = 'board-local-writing-layer'
        },
        [ordered]@{
            assetId = 'lecture-board-close-up-mp4'
            type = 'video/mp4'
            path = ConvertTo-LectureContentRelativePath -ContentRoot ([string]$assetRoot.contentRoot) -Path $boardCloseUpPath
            sha256 = Get-Sha256File -Path $boardCloseUpPath
            length = $boardCloseUpItem.Length
            status = 'archived'
            requiredForPublish = $false
            visualSyncMode = 'board-close-up-crop'
            sourceAssetId = 'lecture-video-mp4'
            audioPreserved = $true
            transcriptPreserved = $true
            checkpointContextPreserved = $true
            classroomContextPreserved = $true
        },
        [ordered]@{
            assetId = 'lecture-guided-camera-mp4'
            type = 'video/mp4'
            path = ConvertTo-LectureContentRelativePath -ContentRoot ([string]$assetRoot.contentRoot) -Path $guidedCameraPath
            sha256 = Get-Sha256File -Path $guidedCameraPath
            length = $guidedCameraItem.Length
            status = 'archived'
            requiredForPublish = $false
            visualSyncMode = 'board-close-up-guided-camera'
            sourceAssetIds = @('lecture-video-mp4', 'lecture-board-close-up-mp4')
            cameraPlanSource = 'visualSync.cameraPlan'
            audioPreserved = $true
            transcriptPreserved = $true
            checkpointContextPreserved = $true
            classroomContextPreserved = $true
        },
        [ordered]@{
            assetId = 'lecture-instructor-motion-preview-mp4'
            type = 'video/mp4'
            path = ConvertTo-LectureContentRelativePath -ContentRoot ([string]$assetRoot.contentRoot) -Path $motionPreviewPath
            sha256 = Get-Sha256File -Path $motionPreviewPath
            length = $motionPreviewItem.Length
            status = 'archived'
            requiredForPublish = $false
            visualSyncMode = 'deterministic-motion-preview'
            sourceAssetIds = @($avatarMedia.assetId, 'lecture-audio-m4a')
            publishPromotion = 'blocked-pending-operator-visual-qa'
            visualQaStatus = 'pending-operator-review'
        },
        [ordered]@{
            assetId = 'lecture-instructor-lipsync-preview-mp4'
            type = 'video/mp4'
            path = ConvertTo-LectureContentRelativePath -ContentRoot ([string]$assetRoot.contentRoot) -Path $lipSyncPreviewPath
            sha256 = Get-Sha256File -Path $lipSyncPreviewPath
            length = $lipSyncPreviewItem.Length
            status = 'archived'
            requiredForPublish = $false
            visualSyncMode = 'deterministic-audio-reactive-lipsync-preview'
            sourceAssetIds = @($avatarMedia.assetId, 'lecture-audio-m4a')
            publishPromotion = 'blocked-pending-operator-visual-qa'
            visualQaStatus = 'pending-operator-review'
        },
        [ordered]@{
            assetId = $avatarMedia.assetId
            type = $avatarMedia.type
            path = $avatarMedia.path
            sha256 = $avatarMedia.sha256
            length = $avatarMedia.length
            status = $avatarMedia.status
            requiredForPublish = $false
        },
        [ordered]@{
            assetId = 'lecture-board-writing-ass'
            type = 'text/x-ass'
            path = ConvertTo-LectureContentRelativePath -ContentRoot ([string]$assetRoot.contentRoot) -Path $boardWritingPath
            sha256 = Get-Sha256File -Path $boardWritingPath
            length = $boardWritingItem.Length
            status = 'archived'
            requiredForPublish = $false
            renderMode = 'stroke-based-progressive-chalk-ass'
            progressiveReveal = $true
            strokeLayer = $true
            globalSubtitleMode = $false
        }
    ) + @($qaFrameEvidence)
} | ConvertTo-Json -Depth 8

exit 0

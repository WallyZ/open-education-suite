[CmdletBinding()]
param(
    [string]$ManifestPath = '..\open-education-game-development\generated-lectures\gdev-101-design-vocabulary\lecture-video.json',
    [string]$ProviderPath = '.\fixtures\lecture-production-providers.json',
    [string]$MetadataPath = '..\open-education-game-development\generated-lectures\gdev-101-design-vocabulary\lecture-avatar-rendered-media.json',
    [string]$Endpoint = 'http://127.0.0.1:8188',
    [int]$TimeoutSeconds = 600,
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

function Get-InstructorVisualProfile {
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
                visualGenderCue = 'masculine adult male instructor'
            }
        }
        'female' {
            return [ordered]@{
                instructorGender = 'female'
                visualGenderCue = 'feminine adult female instructor'
            }
        }
        default {
            return [ordered]@{
                instructorGender = $gender
                visualGenderCue = 'androgynous adult instructor'
            }
        }
    }
}

function Test-ExistingAvatarMetadata {
    param(
        [string]$Path,
        [string]$ContentRoot,
        [object]$ExpectedVisualProfile
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
    if (
        -not ($metadata.PSObject.Properties.Name -contains 'instructorGender') -or
        [string]$metadata.instructorGender -ne [string]$ExpectedVisualProfile['instructorGender'] -or
        -not ($metadata.PSObject.Properties.Name -contains 'visualGenderCue') -or
        [string]$metadata.visualGenderCue -ne [string]$ExpectedVisualProfile['visualGenderCue']
    ) {
        return $null
    }

    return $metadata
}

function Get-WorkflowFromMapping {
    param(
        [string]$ComfyRepoPath,
        [string]$MappingPath
    )

    $mappingFullPath = Join-Path -Path $ComfyRepoPath -ChildPath $MappingPath
    if (-not (Test-Path -LiteralPath $mappingFullPath -PathType Leaf)) {
        throw "ComfyUI workflow mapping does not exist: $MappingPath"
    }

    $mappingJson = Get-Content -LiteralPath $mappingFullPath -Raw | ConvertFrom-Json
    if ($mappingJson.PSObject.Properties.Name -contains 'workflows') {
        $candidate = @($mappingJson.workflows | Where-Object { $_.expected_output_class -eq 'single_image_text_to_image' } | Select-Object -First 1)
        if ($candidate.Count -ne 1) {
            throw "ComfyUI workflow pack has no single_image_text_to_image workflow: $MappingPath"
        }

        $workflowPath = [string]$candidate[0].workflow_path
        $workflowFullPath = Join-Path -Path $ComfyRepoPath -ChildPath $workflowPath
        if (-not (Test-Path -LiteralPath $workflowFullPath -PathType Leaf)) {
            throw "ComfyUI packed workflow does not exist: $workflowPath"
        }
        return [ordered]@{
            path = $workflowFullPath
            relativePath = $workflowPath
        }
    }

    return [ordered]@{
        path = $mappingFullPath
        relativePath = $MappingPath
    }
}

function Set-ComfyTextEncode {
    param(
        [object]$Workflow,
        [string]$NodeId,
        [string]$Text
    )

    if ($Workflow.PSObject.Properties.Name -contains $NodeId) {
        $Workflow.$NodeId.inputs.text = $Text
        return
    }

    $textNode = @($Workflow.PSObject.Properties | Where-Object { $_.Value.class_type -eq 'CLIPTextEncode' } | Select-Object -First 1)
    if ($textNode.Count -ne 1) {
        throw 'ComfyUI workflow does not contain a CLIPTextEncode node.'
    }
    $textNode[0].Value.inputs.text = $Text
}

function Set-ComfyWorkflowForLecture {
    param(
        [object]$Workflow,
        [object]$Lecture,
        [string]$FilenamePrefix,
        [object]$VisualProfile
    )

    $title = [string]$Lecture.title
    $boardSummary = (@($Lecture.deliveryPlan.boardPlan.moments | ForEach-Object { $_.summary }) -join ' ')
    $positivePrompt = "photorealistic original synthetic $($VisualProfile['visualGenderCue']) alone in a classroom, exactly one instructor, front-row straight-on learner view, camera square to a single clean empty dark green chalkboard occupying the left two thirds of the frame, instructor standing at the far right side of the board, teaching $title, professional university lecture video still, clear face, natural hands holding chalk at rest, readable empty board surface reserved for later generated chalk writing, medium wide shot, soft classroom lighting, high quality photo, no real person likeness"
    if (Test-HasText $boardSummary) {
        $positivePrompt = "$positivePrompt, board plan: $boardSummary"
    }
    $negativePrompt = 'two people, three people, crowd, students, duplicate person, duplicate body, extra arms, extra fingers, deformed face, deformed hands, blurry, low quality, watermark, logo, celebrity, real person likeness, unsafe content, prewritten chalk text, chalk diagram, equations on board, busy board, second chalkboard, angled room, side-wall view'

    if ($Workflow.PSObject.Properties.Name -contains '1' -and $Workflow.'1'.class_type -eq 'CheckpointLoaderSimple') {
        $Workflow.'1'.inputs.ckpt_name = 'Realistic_Vision_V7.0.safetensors'
    }
    if ($Workflow.PSObject.Properties.Name -contains '5' -and $Workflow.'5'.class_type -eq 'EmptyLatentImage') {
        $Workflow.'5'.inputs.width = 768
        $Workflow.'5'.inputs.height = 512
        $Workflow.'5'.inputs.batch_size = 1
    }
    if ($Workflow.PSObject.Properties.Name -contains '3' -and $Workflow.'3'.class_type -eq 'KSampler') {
        $Workflow.'3'.inputs.seed = 101021
        $Workflow.'3'.inputs.steps = 24
        $Workflow.'3'.inputs.cfg = 7.0
    }
    if ($Workflow.PSObject.Properties.Name -contains '8' -and $Workflow.'8'.class_type -eq 'SaveImage') {
        $Workflow.'8'.inputs.filename_prefix = $FilenamePrefix
    }

    Set-ComfyTextEncode -Workflow $Workflow -NodeId '6' -Text $positivePrompt
    if ($Workflow.PSObject.Properties.Name -contains '7') {
        $Workflow.'7'.inputs.text = $negativePrompt
    }
}

function Get-ComfyOutputImage {
    param(
        [string]$PromptId,
        [string]$Endpoint,
        [int]$TimeoutSeconds
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        Start-Sleep -Seconds 3
        $history = Invoke-RestMethod -Uri "$Endpoint/history/$PromptId" -TimeoutSec 30
        $entryProperty = $history.PSObject.Properties[$PromptId]
        $entry = if ($null -ne $entryProperty) { $entryProperty.Value } else { $null }
        if ($entry -and $entry.outputs) {
            foreach ($property in $entry.outputs.PSObject.Properties) {
                if ($property.Value.images -and @($property.Value.images).Count -gt 0) {
                    return @($property.Value.images)[0]
                }
            }
        }
    } while ((Get-Date) -lt $deadline)

    throw "ComfyUI did not return an image for prompt $PromptId within $TimeoutSeconds seconds."
}

$resolvedManifestPath = Resolve-LecturePath -Path $ManifestPath
$resolvedMetadataPath = Resolve-LecturePath -Path $MetadataPath

if (-not (Test-Path -LiteralPath $resolvedManifestPath -PathType Leaf)) {
    throw "Missing lecture manifest: $ManifestPath"
}
if (-not (Test-Path -LiteralPath $ProviderPath -PathType Leaf)) {
    throw "Missing lecture production providers: $ProviderPath"
}

$lecture = Get-Content -LiteralPath $resolvedManifestPath -Raw | ConvertFrom-Json
$assetRoot = Get-LectureAssetRoot -Lecture $lecture -ManifestPath $resolvedManifestPath
$visualProfile = Get-InstructorVisualProfile -Lecture $lecture

if (-not $Force) {
    $existing = Test-ExistingAvatarMetadata -Path $resolvedMetadataPath -ContentRoot ([string]$assetRoot.contentRoot) -ExpectedVisualProfile $visualProfile
    if ($null -ne $existing) {
        $existing | ConvertTo-Json -Depth 12
        exit 0
    }
}

$providers = Get-Content -LiteralPath $ProviderPath -Raw | ConvertFrom-Json
$localProvider = @($providers.providers | Where-Object { $_.providerId -eq 'local-comfyui' } | Select-Object -First 1)
if ($localProvider.Count -ne 1) {
    throw 'Missing local-comfyui provider profile.'
}

$comfyRepoPath = Resolve-RepoRelativePath -Path ([string]$localProvider[0].localPath)
$avatarMapping = @($localProvider[0].workflowMappings | Where-Object { $_.stage -eq 'avatar' } | Select-Object -First 1)
if ($avatarMapping.Count -ne 1) {
    throw 'Missing local-comfyui avatar workflow mapping.'
}

$workflowInfo = Get-WorkflowFromMapping -ComfyRepoPath $comfyRepoPath -MappingPath ([string]$avatarMapping[0].workflowPath)
$workflow = Get-Content -LiteralPath ([string]$workflowInfo.path) -Raw | ConvertFrom-Json
$safePackageId = ConvertTo-LectureSafePathSegment -Value ([string]$lecture.packageId)
$filenamePrefix = "oes_$safePackageId`_avatar"
Set-ComfyWorkflowForLecture -Workflow $workflow -Lecture $lecture -FilenamePrefix $filenamePrefix -VisualProfile $visualProfile

try {
    [void](Invoke-RestMethod -Uri "$Endpoint/system_stats" -TimeoutSec 10)
}
catch {
    throw "ComfyUI API is not reachable at $Endpoint. Start the local ComfyUI service before rendering the avatar."
}

$body = @{
    prompt = $workflow
    client_id = [guid]::NewGuid().ToString()
} | ConvertTo-Json -Depth 40

$promptResult = Invoke-RestMethod -Method Post -Uri "$Endpoint/prompt" -Body $body -ContentType 'application/json' -TimeoutSec 30
$promptId = [string]$promptResult.prompt_id
$image = Get-ComfyOutputImage -PromptId $promptId -Endpoint $Endpoint -TimeoutSeconds $TimeoutSeconds

$visualDirectory = Get-LectureMediaDirectory -AssetRoot $assetRoot -Kind 'visuals'
New-Item -ItemType Directory -Path $visualDirectory -Force | Out-Null
$avatarPath = Join-Path -Path $visualDirectory -ChildPath 'lecture-avatar-comfyui.png'

$query = 'filename={0}&subfolder={1}&type={2}' -f [uri]::EscapeDataString([string]$image.filename), [uri]::EscapeDataString([string]$image.subfolder), [uri]::EscapeDataString([string]$image.type)
Invoke-WebRequest -Uri "$Endpoint/view?$query" -OutFile $avatarPath -TimeoutSec 60

$avatarItem = Get-Item -LiteralPath $avatarPath
$metadata = [ordered]@{
    schemaVersion = 1
    packageId = $lecture.packageId
    assetId = 'lecture-avatar-comfyui-png'
    type = 'image/png'
    path = ConvertTo-LectureContentRelativePath -ContentRoot ([string]$assetRoot.contentRoot) -Path $avatarPath
    sha256 = Get-Sha256File -Path $avatarPath
    status = 'archived'
    requiredForPublish = $false
    renderEngine = 'local-comfyui'
    providerId = 'local-comfyui'
    workflowPath = [string]$workflowInfo.relativePath
    promptId = $promptId
    instructorGender = $visualProfile['instructorGender']
    visualGenderCue = $visualProfile['visualGenderCue']
    length = $avatarItem.Length
    notes = 'Local ComfyUI keyframe render for the generated synthetic instructor at the chalkboard. Final video assembly uses this image instead of an ffmpeg-drawn instructor block, and the visual gender cue must match the selected instructor voice profile.'
}

$metadataDirectory = Split-Path -Parent $resolvedMetadataPath
if (-not (Test-Path -LiteralPath $metadataDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $metadataDirectory -Force | Out-Null
}
$metadataJson = $metadata | ConvertTo-Json -Depth 12
Set-Content -LiteralPath $resolvedMetadataPath -Value $metadataJson -Encoding UTF8
$metadataJson

exit 0

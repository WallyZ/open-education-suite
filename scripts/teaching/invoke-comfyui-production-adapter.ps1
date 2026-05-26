[CmdletBinding()]
param(
    [string]$ManifestPath = '.\fixtures\lecture-video.gdev-101-design-vocabulary.json',
    [string]$ProviderPath = '.\fixtures\lecture-production-providers.json',
    [string]$CompletedOutputRoot = '',
    [switch]$Submit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-HasText {
    param([object]$Value)
    return -not [string]::IsNullOrWhiteSpace([string]$Value)
}

function Resolve-RepoRelativePath {
    param([string]$Path)

    $rootPath = (Resolve-Path -LiteralPath '.').Path
    return [System.IO.Path]::GetFullPath((Join-Path -Path $rootPath -ChildPath $Path))
}

function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Missing lecture manifest: $ManifestPath"
}
if (-not (Test-Path -LiteralPath $ProviderPath -PathType Leaf)) {
    throw "Missing lecture production providers: $ProviderPath"
}

$lecture = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$providers = Get-Content -LiteralPath $ProviderPath -Raw | ConvertFrom-Json
$localProvider = @($providers.providers | Where-Object { $_.providerId -eq 'local-comfyui' } | Select-Object -First 1)
if ($localProvider.Count -ne 1) {
    throw 'Missing local-comfyui provider profile.'
}

$comfyRepoPath = Resolve-RepoRelativePath -Path ([string]$localProvider[0].localPath)
if (-not (Test-Path -LiteralPath $comfyRepoPath -PathType Container)) {
    throw "ComfyUI-automation repo not found: $comfyRepoPath"
}

$jobOutput = & .\scripts\teaching\build-lecture-production-job.ps1 -ManifestPath $ManifestPath -ProviderPath $ProviderPath 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Unable to build lecture production job: $jobOutput"
}
$job = ($jobOutput | Out-String) | ConvertFrom-Json

$workflowBindings = @()
foreach ($stage in @('visuals', 'avatar', 'assembly')) {
    $mapping = @($localProvider[0].workflowMappings | Where-Object { $_.stage -eq $stage } | Select-Object -First 1)
    if ($mapping.Count -ne 1) {
        throw "Missing local ComfyUI workflow mapping: $stage"
    }
    $workflowPath = Join-Path -Path $comfyRepoPath -ChildPath ([string]$mapping[0].workflowPath)
    $workflowBindings += [ordered]@{
        stage = $stage
        workflowPath = $workflowPath
        workflowExists = (Test-Path -LiteralPath $workflowPath -PathType Leaf)
        jobStage = @($job.stages | Where-Object { $_.stage -eq $stage } | Select-Object -First 1)
    }
}

$completedOutputs = @()
if (Test-HasText $CompletedOutputRoot) {
    $outputRoot = Resolve-RepoRelativePath -Path $CompletedOutputRoot
    if (-not (Test-Path -LiteralPath $outputRoot -PathType Container)) {
        throw "Completed output root not found: $outputRoot"
    }
    foreach ($file in Get-ChildItem -LiteralPath $outputRoot -File) {
        $completedOutputs += [ordered]@{
            path = $file.FullName
            length = $file.Length
            sha256 = Get-Sha256 -Path $file.FullName
        }
    }
}

$handoffPath = Join-Path -Path $comfyRepoPath -ChildPath ('.codex-cache\tmp\open-education-suite-lecture-handoff\{0}.json' -f ($job.jobId -replace '[^A-Za-z0-9._-]', '_'))
if ($Submit) {
    $handoffDir = Split-Path -Parent $handoffPath
    $createdDirectory = New-Item -ItemType Directory -Force -Path $handoffDir
    $job | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $handoffPath -Encoding UTF8
}

[ordered]@{
    schemaVersion = 1
    adapterId = 'local-comfyui-adapter-v1'
    mode = $(if ($Submit) { 'submitted' } else { 'dry-run' })
    packageId = $lecture.packageId
    jobId = $job.jobId
    comfyRepoPath = $comfyRepoPath
    handoffPath = $handoffPath
    wroteHandoff = [bool]$Submit
    acceptedStages = @('visuals', 'avatar', 'assembly')
    unsupportedStages = @('tts', 'archive', 'qa')
    workflowBindings = @($workflowBindings)
    completedOutputs = @($completedOutputs)
} | ConvertTo-Json -Depth 20

exit 0

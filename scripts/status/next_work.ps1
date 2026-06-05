[CmdletBinding()]
param(
    [string]$RepoRoot = '.',
    [string]$TodoRoot = 'docs/todo',
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-RepoRoot {
    param([string]$Path)

    $resolved = Resolve-Path -LiteralPath $Path -ErrorAction Stop
    return $resolved.Path
}

function Get-GitDirtyFiles {
    param([string]$Root)

    $original = Get-Location
    try {
        Set-Location -LiteralPath $Root
        $output = & git status --short 2>$null
        if ($LASTEXITCODE -ne 0) {
            return @()
        }
        return @($output | Where-Object { $_ -and $_.Trim() })
    }
    finally {
        Set-Location -LiteralPath $original
    }
}

function Get-NextTodo {
    param(
        [string]$Root,
        [string]$TodoRootValue
    )

    $todoRootPath = Join-Path $Root $TodoRootValue
    $candidateFiles = @()
    if (Test-Path -LiteralPath $todoRootPath) {
        $candidateFiles += Get-ChildItem -LiteralPath $todoRootPath -Filter '*.md' -File | Sort-Object Name
    }
    $todoHub = Join-Path $Root 'docs/TODO.md'
    if (Test-Path -LiteralPath $todoHub) {
        $candidateFiles += Get-Item -LiteralPath $todoHub
    }

    foreach ($file in $candidateFiles) {
        $lines = @(Get-Content -LiteralPath $file.FullName)
        for ($index = 0; $index -lt $lines.Count; $index++) {
            $line = [string]$lines[$index]
            if ($line -match '^\s*-\s+\[\s\]\s+(.+)$') {
                return [pscustomobject]@{
                    path = Resolve-PathRelative -Root $Root -Path $file.FullName
                    line = $index + 1
                    text = $Matches[1].Trim()
                }
            }
        }
    }

    return $null
}

function Resolve-PathRelative {
    param(
        [string]$Root,
        [string]$Path
    )

    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $pathFull = [System.IO.Path]::GetFullPath($Path)
    if ($pathFull.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $pathFull.Substring($rootFull.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) -replace '\\', '/'
    }
    return $pathFull
}

function Get-LatestVerifyLog {
    param([string]$Root)

    $logRoot = Join-Path $Root '.codex-cache/logs'
    if (-not (Test-Path -LiteralPath $logRoot)) {
        return $null
    }

    $latest = Get-ChildItem -LiteralPath $logRoot -Filter 'codex-verify*.log' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $latest) {
        return $null
    }

    return [pscustomobject]@{
        path = Resolve-PathRelative -Root $Root -Path $latest.FullName
        updated = $latest.LastWriteTime.ToString('s')
    }
}

function Get-LatestQaLiveStatus {
    param([string]$Root)

    $searchRoots = @(
        (Join-Path $Root '.codex-cache/tmp'),
        (Join-Path $Root 'archive/local-reports')
    ) | Where-Object { Test-Path -LiteralPath $_ }

    $candidates = @()
    foreach ($searchRoot in $searchRoots) {
        $candidates += Get-ChildItem -LiteralPath $searchRoot -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object {
                ($_.Extension -eq '.json') -and (
                    ($_.FullName -match 'qa[-_]?live') -or
                    ($_.Name -match 'qa[-_]?live.*\.json$') -or
                    (($_.Name -eq 'summary.json') -and ($_.DirectoryName -match 'qa[-_]?live'))
                )
            }
    }

    $latest = $candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $latest) {
        return [pscustomobject]@{
            status = 'not-found'
            path = $null
            updated = $null
        }
    }

    $status = 'found'
    try {
        $payload = Get-Content -LiteralPath $latest.FullName -Raw | ConvertFrom-Json
        foreach ($field in @('status', 'result', 'outcome')) {
            if ($payload.PSObject.Properties.Name -contains $field) {
                $status = [string]$payload.$field
                break
            }
        }
        if (($status -eq 'found') -and ($payload.PSObject.Properties.Name -contains 'passed')) {
            $status = if ([bool]$payload.passed) { 'passed' } else { 'failed' }
        }
        if (($status -eq 'found') -and ($payload.PSObject.Properties.Name -contains 'success')) {
            $status = if ([bool]$payload.success) { 'passed' } else { 'failed' }
        }
    }
    catch {
        $status = 'unreadable'
    }

    return [pscustomobject]@{
        status = $status
        path = Resolve-PathRelative -Root $Root -Path $latest.FullName
        updated = $latest.LastWriteTime.ToString('s')
    }
}

$root = Resolve-RepoRoot -Path $RepoRoot
$nextTodo = Get-NextTodo -Root $root -TodoRootValue $TodoRoot
$dirtyFiles = Get-GitDirtyFiles -Root $root
$lastVerify = Get-LatestVerifyLog -Root $root
$qaLive = Get-LatestQaLiveStatus -Root $root

$report = [pscustomobject]@{
    repo_root = $root
    next_todo = $nextTodo
    dirty_count = @($dirtyFiles).Count
    dirty_files = @($dirtyFiles)
    last_verify_log = $lastVerify
    latest_qa_live = $qaLive
}

if ($Json) {
    $report | ConvertTo-Json -Depth 8
    exit 0
}

Write-Output "Repo: $root"
if ($nextTodo) {
    Write-Output ("Next TODO: {0}:{1} - {2}" -f $nextTodo.path, $nextTodo.line, $nextTodo.text)
}
else {
    Write-Output 'Next TODO: none found'
}

Write-Output ("Dirty files: {0}" -f @($dirtyFiles).Count)
foreach ($dirtyFile in @($dirtyFiles | Select-Object -First 20)) {
    Write-Output ("- {0}" -f $dirtyFile)
}
if (@($dirtyFiles).Count -gt 20) {
    Write-Output ("- ... {0} more" -f (@($dirtyFiles).Count - 20))
}

if ($lastVerify) {
    Write-Output ("Last verify log: {0} ({1})" -f $lastVerify.path, $lastVerify.updated)
}
else {
    Write-Output 'Last verify log: not found'
}

if ($qaLive.path) {
    Write-Output ("Latest QA Live: {0} at {1} ({2})" -f $qaLive.status, $qaLive.path, $qaLive.updated)
}
else {
    Write-Output ("Latest QA Live: {0}" -f $qaLive.status)
}

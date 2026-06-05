[CmdletBinding()]
param(
    [string]$RepoRoot = '.',
    [switch]$AutoRefresh,
    [switch]$SkipContextPack,
    [switch]$Enforce
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RepoRootPath {
    param([string]$Start)

    $resolved = (Resolve-Path $Start).Path
    try {
        $top = git -C $resolved rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0 -and $top) {
            return $top.Trim()
        }
    }
    catch {
    }
    return $resolved
}

function Get-ChangedFiles {
    param([string]$Repo)

    $lines = @(git -C $Repo status --porcelain)
    $paths = New-Object System.Collections.Generic.List[string]

    foreach ($line in $lines) {
        if (-not $line) {
            continue
        }

        $payload = $line.Substring([Math]::Min(3, $line.Length)).Trim()
        if (-not $payload) {
            continue
        }

        if ($payload.Contains(' -> ')) {
            $parts = $payload.Split(' -> ')
            $payload = $parts[$parts.Length - 1]
        }

        $payload = $payload.Replace('\\', '/').Trim()
        if ($payload) {
            $paths.Add($payload)
        }
    }

    return @($paths | Sort-Object -Unique)
}

$repo = Get-RepoRootPath -Start $RepoRoot
$changed = Get-ChangedFiles -Repo $repo
if ($changed.Count -eq 0) {
    Write-Output 'Post-tool hook: no working tree changes detected.'
    exit 0
}

$changedOutsideMemory = @()
$memoryTouched = @()

foreach ($p in $changed) {
    if ($p.StartsWith('memory-bank/', [System.StringComparison]::OrdinalIgnoreCase)) {
        $memoryTouched += $p
        continue
    }
    if ($p.StartsWith('docs/wavekit/_archive/', [System.StringComparison]::OrdinalIgnoreCase)) {
        continue
    }
    if ($p.StartsWith('archive/lifecycle/', [System.StringComparison]::OrdinalIgnoreCase)) {
        continue
    }
    $changedOutsideMemory += $p
}

if ($changedOutsideMemory.Count -eq 0) {
    Write-Output 'Post-tool hook: only memory/archive files changed; no refresh reminder needed.'
    exit 0
}

if ($memoryTouched.Count -gt 0) {
    Write-Output 'Post-tool hook: memory-bank files already changed in this wave.'
    exit 0
}

$message = 'Changes detected outside memory-bank without memory updates. Run scripts/memory/refresh_memory_bank.ps1.'

if ($AutoRefresh) {
    $refresh = Join-Path $repo 'scripts/memory/refresh_memory_bank.ps1'
    if (-not (Test-Path -LiteralPath $refresh)) {
        if ($Enforce) {
            Write-Error "$message (refresh script not found)."
            exit 3
        }
        Write-Warning "$message (refresh script not found)."
        exit 0
    }

    Write-Output 'Post-tool hook: running memory refresh automation...'
    if ($SkipContextPack) {
        & $refresh -RepoRoot $repo -SkipContextPack
    }
    else {
        & $refresh -RepoRoot $repo
    }

    if ($LASTEXITCODE -ne 0) {
        if ($Enforce) {
            Write-Error 'Post-tool hook: memory refresh failed and enforcement is enabled.'
            exit 3
        }
        Write-Warning 'Post-tool hook: memory refresh failed; continuing because enforcement is disabled.'
        exit 0
    }

    Write-Output 'Post-tool hook: memory refresh completed.'
    exit 0
}

if ($Enforce) {
    Write-Error $message
    exit 3
}

Write-Warning $message
exit 0

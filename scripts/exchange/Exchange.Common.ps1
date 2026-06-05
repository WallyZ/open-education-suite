Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ExchangeRepoRoot {
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

function Resolve-ExchangePath {
    param(
        [string]$PathValue,
        [string]$BasePath
    )

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return $BasePath
    }

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $BasePath $PathValue))
}

function Get-ExchangeRelativePath {
    param(
        [string]$BasePath,
        [string]$PathValue
    )

    $baseFull = [System.IO.Path]::GetFullPath($BasePath)
    $pathFull = [System.IO.Path]::GetFullPath($PathValue)
    $baseUri = [Uri]($baseFull.TrimEnd([char]92, [char]47) + [System.IO.Path]::DirectorySeparatorChar)
    $pathUri = [Uri]$pathFull
    return [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString()).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
}

function Get-ExchangeFileHash {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return ''
    }

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Read-ExchangeJsonFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $null
    }

    return $raw | ConvertFrom-Json
}

function Write-ExchangeJsonFile {
    param(
        [string]$Path,
        [object]$Payload
    )

    $dir = Split-Path -Parent $Path
    if ($dir) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }

    $json = $Payload | ConvertTo-Json -Depth 20
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, $enc)
}

function Write-ExchangeTextFile {
    param(
        [string]$Path,
        [string]$Content
    )

    $dir = Split-Path -Parent $Path
    if ($dir) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }

    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $enc)
}

function Get-ExchangeManifestPath {
    param([string]$RepoRoot)

    return Join-Path $RepoRoot '.repo-kit/exchange.json'
}

function Read-ExchangeManifest {
    param([string]$RepoRoot)

    return Read-ExchangeJsonFile -Path (Get-ExchangeManifestPath -RepoRoot $RepoRoot)
}

function Get-ExchangeArray {
    param([object]$Value)

    if ($null -eq $Value) {
        return @()
    }

    if ($Value -is [System.Array]) {
        return @($Value)
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = New-Object System.Collections.Generic.List[object]
        foreach ($item in $Value) {
            $items.Add($item) | Out-Null
        }
        return $items.ToArray()
    }

    return @($Value)
}

function Test-ExchangeGlobMatch {
    param(
        [string]$PathValue,
        [string[]]$Globs
    )

    $normalized = ($PathValue -replace '\\', '/')
    foreach ($glob in $Globs) {
        if ([string]::IsNullOrWhiteSpace($glob)) {
            continue
        }
        $pattern = ($glob -replace '\\', '/')
        if ($normalized -like $pattern) {
            return $true
        }
    }

    return $false
}

function Get-ExchangeGitStatus {
    param([string]$RepoRoot)

    $rows = @(git -C $RepoRoot status --porcelain 2>$null)
    if ($LASTEXITCODE -ne 0) {
        return @()
    }

    $items = New-Object System.Collections.Generic.List[object]
    foreach ($row in $rows) {
        if ([string]::IsNullOrWhiteSpace($row) -or $row.Length -lt 4) {
            continue
        }

        $status = $row.Substring(0, 2)
        $path = $row.Substring(3).Trim()
        $indexStatus = [string]$status[0]
        $items.Add([pscustomobject]@{
            status = $status
            path = $path
            staged = ($indexStatus -ne ' ' -and $indexStatus -ne '?')
        }) | Out-Null
    }

    return $items.ToArray()
}

function Test-ExchangeRepoIdle {
    param(
        [string]$RepoRoot,
        [string[]]$AllowedDirtyGlobs = @()
    )

    $statusItems = @(Get-ExchangeGitStatus -RepoRoot $RepoRoot)
    $unallowed = @($statusItems | Where-Object { -not (Test-ExchangeGlobMatch -PathValue $_.path -Globs $AllowedDirtyGlobs) })
    $staged = @($statusItems | Where-Object { $_.staged })
    $lockPaths = @(
        '.repo-kit/exchange.lock',
        '.codex-cache/task-pack.lock',
        '.codex-cache/exchange.lock'
    )
    $locks = New-Object System.Collections.Generic.List[string]
    foreach ($rel in $lockPaths) {
        $lockPath = Join-Path $RepoRoot $rel
        if (Test-Path -LiteralPath $lockPath) {
            $locks.Add($rel) | Out-Null
        }
    }

    $idle = ($unallowed.Count -eq 0 -and $staged.Count -eq 0 -and $locks.Count -eq 0)
    return [pscustomobject]@{
        idle = $idle
        changed_count = $statusItems.Count
        unallowed_changed_count = $unallowed.Count
        staged_count = $staged.Count
        lock_count = $locks.Count
        locks = $locks.ToArray()
        changed = $statusItems
    }
}

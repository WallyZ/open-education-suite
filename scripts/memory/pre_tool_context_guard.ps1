[CmdletBinding()]
param(
    [string]$RepoRoot = '.',
    [ValidateSet('auto', '32k', '64k', 'cloud')]
    [string]$ContextProfile = 'auto',
    [int]$MaxTaskDocLines = 220,
    [int]$MaxTaskDocBytes = 50000,
    [int]$MaxActiveContextLines = 0,
    [int]$MaxProgressLines = 0,
    [int]$MaxContextPackLines = 0,
    [switch]$RequireMemoryFiles,
    [switch]$RequireClineIgnoreAllowlist
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

function Get-ResolvedContextProfile {
    param([string]$RequestedProfile)

    $req = $RequestedProfile.ToLowerInvariant()
    if ($req -eq '32k' -or $req -eq '64k' -or $req -eq 'cloud') {
        return [pscustomobject]@{
            Profile = $req
            Resolution = 'explicit -ContextProfile parameter'
            Runtime = if ($req -eq 'cloud') { 'cloud' } else { 'local' }
        }
    }

    $envProfile = [string]$env:CLINE_CONTEXT_PROFILE
    if (-not [string]::IsNullOrWhiteSpace($envProfile)) {
        $ep = $envProfile.Trim().ToLowerInvariant()
        if ($ep -eq '32k' -or $ep -eq '64k' -or $ep -eq 'cloud') {
            return [pscustomobject]@{
                Profile = $ep
                Resolution = "CLINE_CONTEXT_PROFILE=$ep"
                Runtime = if ($ep -eq 'cloud') { 'cloud' } else { 'local' }
            }
        }
    }

    $runtime = [string]$env:CLINE_MODEL_RUNTIME
    if (-not [string]::IsNullOrWhiteSpace($runtime)) {
        $rt = $runtime.Trim().ToLowerInvariant()
        if (@('local', 'ondevice', 'on-device') -contains $rt) {
            return [pscustomobject]@{
                Profile = '32k'
                Resolution = "CLINE_MODEL_RUNTIME=$rt"
                Runtime = 'local'
            }
        }
        if (@('hosted', 'cloud', 'remote') -contains $rt) {
            return [pscustomobject]@{
                Profile = 'cloud'
                Resolution = "CLINE_MODEL_RUNTIME=$rt"
                Runtime = 'cloud'
            }
        }
    }

    $signals = New-Object System.Collections.Generic.List[string]
    if ($env:OLLAMA_HOST -or $env:OLLAMA_MODELS) {
        $signals.Add('OLLAMA_*') | Out-Null
    }
    if ($env:LM_STUDIO_URL -or $env:LM_STUDIO_HOST -or $env:LMSTUDIO_URL) {
        $signals.Add('LM_STUDIO_*') | Out-Null
    }
    if ($env:LOCALAI_HOST -or $env:LOCALAI_API_BASE) {
        $signals.Add('LOCALAI_*') | Out-Null
    }
    $provider = [string]$env:CLINE_PROVIDER
    if (-not [string]::IsNullOrWhiteSpace($provider) -and $provider -match '(?i)(ollama|lmstudio|localai|local)') {
        $signals.Add("CLINE_PROVIDER=$provider") | Out-Null
    }

    if ($signals.Count -gt 0) {
        return [pscustomobject]@{
            Profile = '32k'
            Resolution = ('auto-detected local runtime from {0}' -f ($signals -join ', '))
            Runtime = 'local'
        }
    }

    return [pscustomobject]@{
        Profile = 'cloud'
        Resolution = 'auto default (no local-runtime indicators found; using cloud profile)'
        Runtime = 'cloud'
    }
}

function Get-ProfileLineBudgets {
    param([string]$Profile)

    if ($Profile -eq '32k') {
        return [pscustomobject]@{
            Active = 90
            Progress = 120
            ContextPack = 60
        }
    }

    if ($Profile -eq '64k') {
        return [pscustomobject]@{
            Active = 120
            Progress = 160
            ContextPack = 80
        }
    }

    return [pscustomobject]@{
        Active = 200
        Progress = 280
        ContextPack = 140
    }
}

function Get-FileLineCount {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return 0
    }
    return @(Get-Content -LiteralPath $Path).Count
}

$resolvedProfile = Get-ResolvedContextProfile -RequestedProfile $ContextProfile
$effectiveProfile = $resolvedProfile.Profile
$budget = Get-ProfileLineBudgets -Profile $effectiveProfile
if (-not $PSBoundParameters.ContainsKey('MaxActiveContextLines') -or $MaxActiveContextLines -le 0) {
    $MaxActiveContextLines = $budget.Active
}
if (-not $PSBoundParameters.ContainsKey('MaxProgressLines') -or $MaxProgressLines -le 0) {
    $MaxProgressLines = $budget.Progress
}
if (-not $PSBoundParameters.ContainsKey('MaxContextPackLines') -or $MaxContextPackLines -le 0) {
    $MaxContextPackLines = $budget.ContextPack
}

$repo = Get-RepoRootPath -Start $RepoRoot
$violations = New-Object System.Collections.Generic.List[string]

$taskPath = Join-Path $repo 'docs/CLINE_TASK_CURRENT.md'
if (-not (Test-Path -LiteralPath $taskPath)) {
    $violations.Add('Missing docs/CLINE_TASK_CURRENT.md pointer file.')
}
else {
    $taskLines = Get-FileLineCount -Path $taskPath
    $taskBytes = (Get-Item -LiteralPath $taskPath).Length
    $taskText = Get-Content -LiteralPath $taskPath -Raw

    if ($taskLines -gt $MaxTaskDocLines) {
        $violations.Add("docs/CLINE_TASK_CURRENT.md exceeds line budget ($taskLines > $MaxTaskDocLines).")
    }
    if ($taskBytes -gt $MaxTaskDocBytes) {
        $violations.Add("docs/CLINE_TASK_CURRENT.md exceeds byte budget ($taskBytes > $MaxTaskDocBytes).")
    }
    if ($taskText -match '(?im)^\s*-\s*\[[ xX]\]') {
        $violations.Add('docs/CLINE_TASK_CURRENT.md is not pointer-only (contains checklist items).')
    }
    if ($taskText -match '```') {
        $violations.Add('docs/CLINE_TASK_CURRENT.md should stay pointer-only and avoid code fences.')
    }
    if ($taskText -match '(?i)(full\s+log|raw\s+transcript|terminal\s+dump)') {
        $violations.Add('docs/CLINE_TASK_CURRENT.md contains log/transcript anti-pattern text.')
    }
}

$memoryChecks = @(
    @{ path = 'memory-bank/activeContext.md'; max = $MaxActiveContextLines },
    @{ path = 'memory-bank/progress.md'; max = $MaxProgressLines },
    @{ path = 'memory-bank/context-pack.md'; max = $MaxContextPackLines }
)

foreach ($check in $memoryChecks) {
    $full = Join-Path $repo $check.path
    if (-not (Test-Path -LiteralPath $full)) {
        if ($RequireMemoryFiles) {
            $violations.Add("Missing required memory file: $($check.path)")
        }
        continue
    }

    $lines = Get-FileLineCount -Path $full
    if ($lines -gt $check.max) {
        $violations.Add("$($check.path) exceeds line budget ($lines > $($check.max)).")
    }
}

$clineIgnorePath = Join-Path $repo '.clineignore'
if ((Test-Path -LiteralPath $clineIgnorePath)) {
    $ignoreText = Get-Content -LiteralPath $clineIgnorePath -Raw
    $requiredAllow = @(
        '!docs/CLINE_TASK_CURRENT.md',
        '!memory-bank/activeContext.md',
        '!memory-bank/progress.md'
    )

    foreach ($needle in $requiredAllow) {
        if ($ignoreText -notmatch [regex]::Escape($needle)) {
            $violations.Add(".clineignore missing required allowlist entry: $needle")
        }
    }
}
elseif ($RequireClineIgnoreAllowlist) {
    $violations.Add('Missing .clineignore file for context-allowlist enforcement.')
}

if ($violations.Count -gt 0) {
    Write-Output 'Pre-tool context guard FAILED:'
    foreach ($v in $violations) {
        Write-Output "- $v"
    }
    exit 2
}

Write-Output ("Pre-tool context guard passed (repo={0}, profile={1}, requested={2}, runtime={3}, resolution={4})." -f $repo, $effectiveProfile, $ContextProfile, $resolvedProfile.Runtime, $resolvedProfile.Resolution)

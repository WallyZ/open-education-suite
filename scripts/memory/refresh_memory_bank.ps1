[CmdletBinding()]
param(
    [string]$RepoRoot = '.',
    [string]$MemoryBankDir = 'memory-bank',
    [string]$TodoFile = 'docs/TODO.md',
    [string]$TodoRoot = 'docs/todo',
    [ValidateSet('auto', '32k', '64k', 'cloud')]
    [string]$ContextProfile = 'auto',
    [int]$RecentCommitCount = 8,
    [int]$MaxListItems = 0,
    [int]$MaxLineLength = 0,
    [int]$MaxActiveContextLines = 0,
    [int]$MaxProgressLines = 0,
    [int]$MaxContextPackLines = 0,
    [switch]$SkipContextPack,
    [switch]$DryRun
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

function Get-ProfileDefaults {
    param([string]$Profile)

    if ($Profile -eq '32k') {
        return [pscustomobject]@{
            MaxListItems = 3
            MaxLineLength = 120
            MaxActiveContextLines = 90
            MaxProgressLines = 120
            MaxContextPackLines = 60
            TargetBudgetNote = 'Local AI 32k profile: extremely aggressive compression/cutting to stay within tight windows.'
        }
    }

    if ($Profile -eq '64k') {
        return [pscustomobject]@{
            MaxListItems = 4
            MaxLineLength = 140
            MaxActiveContextLines = 120
            MaxProgressLines = 160
            MaxContextPackLines = 80
            TargetBudgetNote = 'Local AI 64k profile: still aggressive compression for reliability on constrained local windows.'
        }
    }

    return [pscustomobject]@{
        MaxListItems = 8
        MaxLineLength = 200
        MaxActiveContextLines = 200
        MaxProgressLines = 280
        MaxContextPackLines = 140
        TargetBudgetNote = 'Cloud profile: keep richer context for speed/quality, but remain bounded to control token cost.'
    }
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

function Truncate-Text {
    param(
        [string]$Text,
        [int]$Limit
    )

    $value = ($Text -replace '\s+', ' ').Trim()
    if ($value.Length -le $Limit) {
        return $value
    }
    return ($value.Substring(0, [Math]::Max(0, $Limit - 3))).Trim() + '...'
}

function Normalize-TaskText {
    param([string]$Line)

    $v = $Line
    $v = $v -replace '^\s*-\s*\[[xX\s]\]\s*', ''
    $v = $v -replace '<!--.*?-->', ''
    $v = $v.Trim(' -`"''')
    return $v.Trim()
}

function Limit-Items {
    param(
        [string[]]$Items,
        [int]$MaxItems,
        [int]$MaxLength
    )

    $clean = @()
    foreach ($item in $Items) {
        if (-not $item) {
            continue
        }
        $trimmed = Truncate-Text -Text $item -Limit $MaxLength
        if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
            $clean += $trimmed
        }
        if ($clean.Count -ge $MaxItems) {
            break
        }
    }
    return $clean
}

function Limit-Lines {
    param(
        [string[]]$Lines,
        [int]$MaxLines,
        [string]$Label
    )

    if ($Lines.Count -le $MaxLines) {
        return $Lines
    }

    $trimCount = [Math]::Max(1, $MaxLines - 1)
    $head = $Lines[0..($trimCount - 1)]
    $head += "- [truncated by refresh_memory_bank: $Label budget $MaxLines lines]"
    return $head
}

function Get-TodoStatsFromFile {
    param(
        [string]$Path,
        [int]$MaxItems,
        [int]$MaxLength
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{
            exists = $false
            checked = 0
            unchecked = 0
            top_unchecked = @()
        }
    }

    $lines = Get-Content -LiteralPath $Path
    $checked = @($lines | Where-Object { $_ -match '^\s*-\s*\[[xX]\]\s+' }).Count
    $unchecked = @($lines | Where-Object { $_ -match '^\s*-\s*\[\s\]\s+' }).Count
    $topUncheckedRaw = @($lines | Where-Object { $_ -match '^-\s*\[\s\]\s+' })

    $topUnchecked = @()
    foreach ($ln in $topUncheckedRaw) {
        $topUnchecked += (Normalize-TaskText -Line $ln)
    }
    $topUnchecked = Limit-Items -Items $topUnchecked -MaxItems $MaxItems -MaxLength $MaxLength

    return [pscustomobject]@{
        exists = $true
        checked = $checked
        unchecked = $unchecked
        top_unchecked = $topUnchecked
    }
}

function Get-TodoSummary {
    param(
        [string]$Repo,
        [string]$TodoRelative,
        [string]$TodoRootRelative,
        [int]$MaxItems,
        [int]$MaxLength
    )

    $todoPath = Join-Path $Repo $TodoRelative
    $hub = Get-TodoStatsFromFile -Path $todoPath -MaxItems $MaxItems -MaxLength $MaxLength

    $todoRootPath = Join-Path $Repo $TodoRootRelative
    $splitFiles = @()
    if (Test-Path -LiteralPath $todoRootPath) {
        $splitFiles = @(Get-ChildItem -LiteralPath $todoRootPath -File -Filter '*.md' |
            Where-Object { $_.Name -match '^[0-9]{2}[._-].*\.md$' } |
            Sort-Object Name)
    }

    if ($splitFiles.Count -eq 0) {
        return [pscustomobject]@{
            exists = $hub.exists
            path = $todoPath
            checked = $hub.checked
            unchecked = $hub.unchecked
            top_unchecked = $hub.top_unchecked
            source = 'hub'
            scanned = @($TodoRelative)
        }
    }

    $sumChecked = 0
    $sumUnchecked = 0
    $candidates = @()
    $scanned = @()

    foreach ($file in $splitFiles) {
        $stats = Get-TodoStatsFromFile -Path $file.FullName -MaxItems $MaxItems -MaxLength $MaxLength
        $sumChecked += $stats.checked
        $sumUnchecked += $stats.unchecked
        $candidates += $stats.top_unchecked
        $rel = $file.FullName.Substring($Repo.Length).TrimStart('\', '/') -replace '\\', '/'
        $scanned += $rel
    }

    $dedup = New-Object System.Collections.Generic.List[string]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($item in $candidates) {
        if (-not $item) {
            continue
        }
        if ($seen.Add($item)) {
            $dedup.Add($item) | Out-Null
        }
    }

    $top = Limit-Items -Items $dedup.ToArray() -MaxItems $MaxItems -MaxLength $MaxLength

    return [pscustomobject]@{
        exists = $true
        path = $todoPath
        checked = $sumChecked
        unchecked = $sumUnchecked
        top_unchecked = $top
        source = 'split'
        scanned = $scanned
    }
}

function Get-RecentCommits {
    param(
        [string]$Repo,
        [int]$Count,
        [int]$MaxLength
    )

    try {
        $null = git -C $Repo rev-parse --verify HEAD 2>$null
        if ($LASTEXITCODE -ne 0) {
            return @()
        }
    }
    catch {
        return @()
    }

    $raw = @(git -C $Repo log -n $Count --pretty=format:'%h|%cs|%s' 2>$null)
    $items = @()
    foreach ($line in $raw) {
        if (-not $line) {
            continue
        }
        $parts = $line.Split('|', 3)
        if ($parts.Count -lt 3) {
            continue
        }
        $hash = $parts[0].Trim()
        $date = $parts[1].Trim()
        $subject = Truncate-Text -Text $parts[2].Trim() -Limit $MaxLength
        $items += [pscustomobject]@{
            hash = $hash
            date = $date
            subject = $subject
        }
    }
    return $items
}

function Ensure-File {
    param(
        [string]$Path,
        [string]$InitialContent
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Set-Content -LiteralPath $Path -Encoding utf8 -Value $InitialContent
    }
}

function Write-OrPreview {
    param(
        [string]$Path,
        [string]$Content,
        [switch]$PreviewOnly
    )

    if ($PreviewOnly) {
        Write-Output "--- $Path ---"
        Write-Output $Content
        return
    }

    Set-Content -LiteralPath $Path -Encoding utf8 -Value $Content
}

$repo = Get-RepoRootPath -Start $RepoRoot
$today = Get-Date -Format 'yyyy-MM-dd'
$resolvedProfile = Get-ResolvedContextProfile -RequestedProfile $ContextProfile
$effectiveProfile = $resolvedProfile.Profile
$profileDefaults = Get-ProfileDefaults -Profile $effectiveProfile

if (-not $PSBoundParameters.ContainsKey('MaxListItems') -or $MaxListItems -le 0) {
    $MaxListItems = $profileDefaults.MaxListItems
}
if (-not $PSBoundParameters.ContainsKey('MaxLineLength') -or $MaxLineLength -le 0) {
    $MaxLineLength = $profileDefaults.MaxLineLength
}
if (-not $PSBoundParameters.ContainsKey('MaxActiveContextLines') -or $MaxActiveContextLines -le 0) {
    $MaxActiveContextLines = $profileDefaults.MaxActiveContextLines
}
if (-not $PSBoundParameters.ContainsKey('MaxProgressLines') -or $MaxProgressLines -le 0) {
    $MaxProgressLines = $profileDefaults.MaxProgressLines
}
if (-not $PSBoundParameters.ContainsKey('MaxContextPackLines') -or $MaxContextPackLines -le 0) {
    $MaxContextPackLines = $profileDefaults.MaxContextPackLines
}

$memoryRoot = Join-Path $repo $MemoryBankDir
if (-not (Test-Path -LiteralPath $memoryRoot) -and -not $DryRun) {
    New-Item -ItemType Directory -Path $memoryRoot -Force | Out-Null
}

$activePath = Join-Path $memoryRoot 'activeContext.md'
$progressPath = Join-Path $memoryRoot 'progress.md'
$contextPackPath = Join-Path $memoryRoot 'context-pack.md'
$statePath = Join-Path $memoryRoot '.refresh_state.json'

if (-not $DryRun) {
    Ensure-File -Path $activePath -InitialContent "# Active Context`n"
    Ensure-File -Path $progressPath -InitialContent "# Progress`n"
}

$todo = Get-TodoSummary -Repo $repo -TodoRelative $TodoFile -TodoRootRelative $TodoRoot -MaxItems $MaxListItems -MaxLength $MaxLineLength
$commits = Get-RecentCommits -Repo $repo -Count $RecentCommitCount -MaxLength $MaxLineLength

$prev = $null
if (Test-Path -LiteralPath $statePath) {
    try {
        $prev = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    }
    catch {
        $prev = $null
    }
}

$deltaCheckedText = 'baseline unavailable'
$deltaUncheckedText = 'baseline unavailable'
if ($null -ne $prev -and $null -ne $prev.checked -and $null -ne $prev.unchecked) {
    $deltaChecked = [int]$todo.checked - [int]$prev.checked
    $deltaUnchecked = [int]$todo.unchecked - [int]$prev.unchecked
    $deltaCheckedText = ('{0:+#;-#;0}' -f $deltaChecked)
    $deltaUncheckedText = ('{0:+#;-#;0}' -f $deltaUnchecked)
}

$topUncheckedItems = @()
foreach ($item in @($todo.top_unchecked)) {
    if (-not [string]::IsNullOrWhiteSpace([string]$item)) {
        $topUncheckedItems += [string]$item
    }
}

$objective = if ($topUncheckedItems.Count -gt 0) {
    $topUncheckedItems[0]
}
else {
    'No unchecked TODO items were detected.'
}

$nextActions = if ($topUncheckedItems.Count -gt 0) {
    Limit-Items -Items $topUncheckedItems -MaxItems 3 -MaxLength $MaxLineLength
}
else {
    @('Review backlog and add the next actionable TODO item.')
}

$inProgress = if ($topUncheckedItems.Count -gt 0) {
    Limit-Items -Items $topUncheckedItems -MaxItems 3 -MaxLength $MaxLineLength
}
else {
    @('No active TODO item detected.')
}

$riskItems = @()
if (-not $todo.exists) {
    $riskItems += "TODO source missing: $TodoFile"
}
if (@($commits).Count -eq 0) {
    $riskItems += 'No git commit history available for summary.'
}
if ($riskItems.Count -eq 0) {
    $riskItems += 'No major blockers captured during refresh.'
}
$riskItems = Limit-Items -Items $riskItems -MaxItems $MaxListItems -MaxLength $MaxLineLength

$commitLines = @()
foreach ($c in (Limit-Items -Items @($commits | ForEach-Object { "[$($_.hash)] $($_.subject)" }) -MaxItems $MaxListItems -MaxLength $MaxLineLength)) {
    $commitLines += "- ${today}: $c"
}
if ($commitLines.Count -eq 0) {
    $commitLines += '- No recent commits available.'
}

$todoDeltaLine = if ($todo.exists) {
    "- ${today}: TODO status checked=$($todo.checked) ($deltaCheckedText), unchecked=$($todo.unchecked) ($deltaUncheckedText)."
}
else {
    "- ${today}: TODO status unavailable because source TODO files were not found."
}

$activeLines = @(
    '# Active Context',
    '',
    "Last updated: $today",
    '',
    '## Current objective',
    "- $objective",
    '',
    '## Active wave/task',
    "- Primary TODO target: $objective",
    '',
    '## Allowed scope',
    '- Files directly related to the active wave and required verification updates.',
    '- `memory-bank/activeContext.md` and `memory-bank/progress.md` maintenance.',
    '',
    '## Risks/blockers'
)
$activeLines += @($riskItems | ForEach-Object { "- $_" })
$activeLines += @(
    '',
    '## Next 3 actions'
)
$activeLines += @($nextActions | ForEach-Object { "- $_" })
$activeLines += ''
$activeLines = Limit-Lines -Lines $activeLines -MaxLines $MaxActiveContextLines -Label 'activeContext'
$activeContent = $activeLines -join "`n"

$progressLines = @(
    '# Progress',
    '',
    '## Completed'
)
$progressLines += $commitLines
$progressLines += $todoDeltaLine
$progressLines += @(
    '',
    '## In progress'
)
$progressLines += @($inProgress | ForEach-Object { "- $_" })
$progressLines += @(
    '',
    '## Next'
)
$progressLines += @($nextActions | ForEach-Object { "- $_" })
$progressLines += @(
    '',
    '## Verification notes',
    '- Refresh script: `scripts/memory/refresh_memory_bank.ps1`',
    "- Inputs: todo=$TodoFile, todo_root=$TodoRoot, commits=$RecentCommitCount, profile=$effectiveProfile",
    "- Profile resolution: $($resolvedProfile.Resolution)",
    "- TODO source: $($todo.source)",
    "- Generated on: ${today}",
    ''
)
$progressLines = Limit-Lines -Lines $progressLines -MaxLines $MaxProgressLines -Label 'progress'
$progressContent = $progressLines -join "`n"

Write-OrPreview -Path $activePath -Content $activeContent -PreviewOnly:$DryRun
Write-OrPreview -Path $progressPath -Content $progressContent -PreviewOnly:$DryRun

if (-not $SkipContextPack) {
    $mustRead = @(
        'memory-bank/activeContext.md',
        'memory-bank/progress.md'
    )
    $taskDoc = Join-Path $repo 'docs/CLINE_TASK_CURRENT.md'
    if (Test-Path -LiteralPath $taskDoc) {
        $mustRead += 'docs/CLINE_TASK_CURRENT.md'
    }
    if ($todo.exists) {
        $mustRead += $TodoFile.Replace('\\', '/')
    }

    $scannedList = @($todo.scanned | ForEach-Object { "- $_" })

    $contextPackLines = @(
        '# Context Pack',
        '',
        'Use this compact context for a single focused wave.',
        '',
        "Generated: $today",
        '',
        '## Context profile',
        "- Profile: $effectiveProfile (requested: $ContextProfile)",
        "- Profile note: $($profileDefaults.TargetBudgetNote)",
        "- Line budgets: activeContext<=$MaxActiveContextLines, progress<=$MaxProgressLines, context-pack<=$MaxContextPackLines",
        "- Text caps: max_items=$MaxListItems, max_line_length=$MaxLineLength",
        '',
        '## Objective',
        "- $objective",
        '',
        '## TODO source files scanned'
    )
    $contextPackLines += $scannedList
    $contextPackLines += @(
        '',
        '## Must-read files'
    )
    $contextPackLines += @($mustRead | ForEach-Object { "- $_" })
    $contextPackLines += @(
        '',
        '## Constraints',
        '- Keep scope limited to the active TODO/wave objective.',
        '- Keep notes compact; avoid raw logs and long transcripts.',
        '- Prefer links over pasted dumps for large context.',
        '',
        '## Acceptance criteria',
        '- Active context and progress reflect current objective and TODO deltas.',
        '- Context remains concise and action-oriented within profile budgets.',
        '',
        '## Verification commands',
        '- `git status --short`',
        '- `pwsh -File .\scripts\memory\refresh_memory_bank.ps1 -DryRun`',
        ('- python scripts/lifecycle/check_memory_bank.py --repo-root . --profile {0}' -f $effectiveProfile),
        ''
    )

    $contextPackLines = Limit-Lines -Lines $contextPackLines -MaxLines $MaxContextPackLines -Label 'context-pack'
    $contextPackContent = $contextPackLines -join "`n"

    Write-OrPreview -Path $contextPackPath -Content $contextPackContent -PreviewOnly:$DryRun
}

if (-not $DryRun) {
    $stateObj = [pscustomobject]@{
        updated_on = $today
        checked = $todo.checked
        unchecked = $todo.unchecked
        todo_file = $TodoFile
        todo_root = $TodoRoot
        todo_source = $todo.source
        profile = $effectiveProfile
        requested_profile = $ContextProfile
        profile_runtime = $resolvedProfile.Runtime
        profile_resolution = $resolvedProfile.Resolution
        max_list_items = $MaxListItems
        max_line_length = $MaxLineLength
        max_active_context_lines = $MaxActiveContextLines
        max_progress_lines = $MaxProgressLines
        max_context_pack_lines = $MaxContextPackLines
        repo_root = $repo
    }
    $stateObj | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $statePath -Encoding utf8
}

$global:LASTEXITCODE = 0
Write-Output "refresh_memory_bank completed (dry_run=$DryRun, repo_root=${repo}, memory_bank=${memoryRoot}, requested_profile=$ContextProfile, effective_profile=$effectiveProfile, runtime=$($resolvedProfile.Runtime), todo_source=$($todo.source))"

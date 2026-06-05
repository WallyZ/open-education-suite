[CmdletBinding()]
param(
    [string[]]$RepoRoot = @('.'),
    [string]$RepoListPath = '',
    [string]$RepoKitRoot = 'F:\dev\00-repo-kit',
    [string]$ReportPath = '',
    [switch]$Prompt,
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'Exchange.Common.ps1')

function Get-WatchRepoList {
    param(
        [string[]]$InlineRoots,
        [string]$ListPath,
        [string]$BaseRoot
    )

    $items = New-Object System.Collections.Generic.List[string]
    foreach ($root in $InlineRoots) {
        if (-not [string]::IsNullOrWhiteSpace($root)) {
            $items.Add($root) | Out-Null
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($ListPath)) {
        $resolvedList = Resolve-ExchangePath -PathValue $ListPath -BasePath $BaseRoot
        if (-not (Test-Path -LiteralPath $resolvedList -PathType Leaf)) {
            throw "Repo list not found: $resolvedList"
        }

        foreach ($line in (Get-Content -LiteralPath $resolvedList)) {
            $trimmed = $line.Trim()
            if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) {
                continue
            }
            $items.Add($trimmed) | Out-Null
        }
    }

    return @($items.ToArray() | Sort-Object -Unique)
}

function Invoke-DueCheckJson {
    param(
        [string]$Root,
        [string]$KitRoot
    )

    $checkScript = Join-Path $scriptDir 'check_due.ps1'
    $output = & $checkScript -RepoRoot $Root -RepoKitRoot $KitRoot -Json
    if ($LASTEXITCODE -ne 0) {
        throw "check_due failed for repo: $Root"
    }

    return ($output | ConvertFrom-Json)
}

function Get-ReviewCommands {
    param(
        [string]$Root,
        [string]$KitRoot
    )

    return @(
        ("pwsh -NoProfile -ExecutionPolicy Bypass -File `"{0}`" -RepoRoot `"{1}`"" -f (Join-Path $scriptDir 'catalog_repo.ps1'), $Root),
        ("pwsh -NoProfile -ExecutionPolicy Bypass -File `"{0}`" -RepoRoot `"{1}`" -RepoKitRoot `"{2}`"" -f (Join-Path $scriptDir 'propose_imports.ps1'), $Root, $KitRoot),
        ("pwsh -NoProfile -ExecutionPolicy Bypass -File `"{0}`" -RepoRoot `"{1}`"" -f (Join-Path $scriptDir 'propose_exports.ps1'), $Root),
        ("pwsh -NoProfile -ExecutionPolicy Bypass -File `"{0}`" -RepoRoot `"{1}`" -RepoKitRoot `"{2}`"" -f (Join-Path $scriptDir 'check_drift.ps1'), $Root, $KitRoot)
    )
}

$baseRoot = Get-ExchangeRepoRoot -Start '.'
$repos = Get-WatchRepoList -InlineRoots $RepoRoot -ListPath $RepoListPath -BaseRoot $baseRoot
$results = New-Object System.Collections.Generic.List[object]
$responses = New-Object System.Collections.Generic.List[object]

foreach ($repoItem in $repos) {
    $check = Invoke-DueCheckJson -Root $repoItem -KitRoot $RepoKitRoot
    $commands = @()
    if ($check.can_prompt) {
        $commands = Get-ReviewCommands -Root ([string]$check.repo_root) -KitRoot $RepoKitRoot
    }

    $results.Add([pscustomobject]@{
        repo_root = [string]$check.repo_root
        manifest_path = [string]$check.manifest_path
        manifest_exists = [bool]$check.manifest_exists
        due = [bool]$check.due
        idle = [bool]$check.idle
        can_prompt = [bool]$check.can_prompt
        changed_count = [int]$check.changed_count
        unallowed_changed_count = [int]$check.unallowed_changed_count
        staged_count = [int]$check.staged_count
        lock_count = [int]$check.lock_count
        review_commands = $commands
    }) | Out-Null
}

if ($Prompt) {
    foreach ($item in @($results.ToArray() | Where-Object { $_.can_prompt })) {
        Write-Output ''
        Write-Output ("Repo-kit exchange is due for: {0}" -f $item.repo_root)
        Write-Output 'Choices: review, postpone, skip'
        $answer = Read-Host 'Response'
        if ($answer -eq 'review') {
            Write-Output 'Run these review commands:'
            foreach ($cmd in $item.review_commands) {
                Write-Output ("- {0}" -f $cmd)
            }
        }
        elseif ($answer -eq 'postpone') {
            Write-Output 'Postponed by operator response. No files changed.'
        }
        elseif ($answer -eq 'skip') {
            Write-Output 'Skipped this cycle by operator response. No files changed.'
        }
        else {
            Write-Output 'Unrecognized response; no files changed.'
        }

        $responses.Add([pscustomobject]@{
            repo_root = $item.repo_root
            response = $answer
            responded_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        }) | Out-Null
    }
}

$dueCount = @($results.ToArray() | Where-Object { $_.due }).Count
$promptCount = @($results.ToArray() | Where-Object { $_.can_prompt }).Count
$blockedCount = @($results.ToArray() | Where-Object { $_.due -and -not $_.can_prompt }).Count
$report = [pscustomobject]@{
    schema_version = 1
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    repo_kit_root = $RepoKitRoot
    repo_count = $results.Count
    due_count = $dueCount
    can_prompt_count = $promptCount
    blocked_due_count = $blockedCount
    prompt_enabled = [bool]$Prompt
    results = $results.ToArray()
    responses = $responses.ToArray()
}

if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
    $resolvedReport = Resolve-ExchangePath -PathValue $ReportPath -BasePath $baseRoot
    Write-ExchangeJsonFile -Path $resolvedReport -Payload $report
    Write-Output ("Wrote exchange watchdog report: {0}" -f $resolvedReport)
}

if ($Json) {
    $report | ConvertTo-Json -Depth 12
}
else {
    Write-Output ("repo-kit exchange watchdog: repos={0} due={1} can_prompt={2} blocked_due={3}" -f $report.repo_count, $report.due_count, $report.can_prompt_count, $report.blocked_due_count)
    foreach ($item in $report.results) {
        Write-Output ("- {0}: due={1} idle={2} can_prompt={3}" -f $item.repo_root, $item.due, $item.idle, $item.can_prompt)
    }
}

exit 0

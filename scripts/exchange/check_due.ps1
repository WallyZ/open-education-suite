[CmdletBinding()]
param(
    [string]$RepoRoot = '.',
    [string]$RepoKitRoot = '',
    [int]$DefaultIntervalDays = 7,
    [switch]$Json,
    [switch]$Prompt
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'Exchange.Common.ps1')

$repo = Get-ExchangeRepoRoot -Start $RepoRoot
$manifestPath = Get-ExchangeManifestPath -RepoRoot $repo
$manifest = Read-ExchangeManifest -RepoRoot $repo

$intervalDays = $DefaultIntervalDays
$lastPrompt = ''
$allowedDirty = @()
$idleRequired = $true

if ($null -ne $manifest) {
    if ($null -ne $manifest.cadence) {
        if ($manifest.cadence.interval_days) {
            $intervalDays = [int]$manifest.cadence.interval_days
        }
        $lastPrompt = [string]$manifest.cadence.last_prompt_utc
        if ($null -ne $manifest.cadence.idle_required) {
            $idleRequired = [bool]$manifest.cadence.idle_required
        }
        $allowedDirty = @(Get-ExchangeArray -Value $manifest.cadence.allowed_dirty_globs)
    }
}

$now = (Get-Date).ToUniversalTime()
$due = $true
$lastPromptUtc = $null
if (-not [string]::IsNullOrWhiteSpace($lastPrompt)) {
    try {
        $lastPromptUtc = [datetime]::Parse($lastPrompt).ToUniversalTime()
        $due = (($now - $lastPromptUtc).TotalDays -ge $intervalDays)
    }
    catch {
        $due = $true
    }
}

$idle = Test-ExchangeRepoIdle -RepoRoot $repo -AllowedDirtyGlobs $allowedDirty
$canPrompt = $due -and ((-not $idleRequired) -or $idle.idle)

$result = [pscustomobject]@{
    repo_root = $repo
    repo_kit_root = $RepoKitRoot
    manifest_path = $manifestPath
    manifest_exists = (Test-Path -LiteralPath $manifestPath -PathType Leaf)
    interval_days = $intervalDays
    last_prompt_utc = $lastPrompt
    due = $due
    idle_required = $idleRequired
    idle = $idle.idle
    can_prompt = $canPrompt
    changed_count = $idle.changed_count
    unallowed_changed_count = $idle.unallowed_changed_count
    staged_count = $idle.staged_count
    lock_count = $idle.lock_count
    locks = $idle.locks
}

if ($Json) {
    $result | ConvertTo-Json -Depth 10
}
else {
    Write-Output ("repo-kit exchange due check: due={0} idle={1} can_prompt={2} manifest={3}" -f $result.due, $result.idle, $result.can_prompt, $result.manifest_exists)
    Write-Output ("repo={0}" -f $repo)
    Write-Output ("manifest={0}" -f $manifestPath)
    if (-not $result.idle) {
        Write-Output ("not idle: changed={0} unallowed={1} staged={2} locks={3}" -f $result.changed_count, $result.unallowed_changed_count, $result.staged_count, $result.lock_count)
    }
}

if ($Prompt -and $canPrompt) {
    $answer = Read-Host 'Repo-kit exchange is due. Review proposals now? [yes/no/postpone]'
    Write-Output ("operator_response={0}" -f $answer)
}

exit 0

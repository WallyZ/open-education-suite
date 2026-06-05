[CmdletBinding()]
param(
    [string]$RepoRoot = '.',
    [string]$RepoKitRoot = 'F:\dev\00-repo-kit',
    [string]$OutputJson = '',
    [string]$OutputMarkdown = '',
    [switch]$NoWrite
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'Exchange.Common.ps1')

$repo = Get-ExchangeRepoRoot -Start $RepoRoot
$repoKit = Resolve-ExchangePath -PathValue $RepoKitRoot -BasePath $repo
$itemsPath = Join-Path $repoKit 'repo-standards/exchange/default_items.json'
if (-not (Test-Path -LiteralPath $itemsPath -PathType Leaf)) {
    throw "Missing repo-kit exchange defaults: $itemsPath"
}

$defaults = Read-ExchangeJsonFile -Path $itemsPath
$manifest = Read-ExchangeManifest -RepoRoot $repo
$tracked = @{}
if ($null -ne $manifest) {
    foreach ($item in (Get-ExchangeArray -Value $manifest.imports)) {
        if ($null -ne $item -and -not [string]::IsNullOrWhiteSpace([string]$item.id)) {
            $tracked[[string]$item.id] = $item
        }
    }
}

$proposals = New-Object System.Collections.Generic.List[object]
foreach ($item in (Get-ExchangeArray -Value $defaults.items)) {
    $sourcePath = Join-Path $repoKit ([string]$item.source_path)
    $targetPath = Join-Path $repo ([string]$item.target_path)
    $sourceExists = Test-Path -LiteralPath $sourcePath
    $targetExists = Test-Path -LiteralPath $targetPath
    $sourceHash = if (Test-Path -LiteralPath $sourcePath -PathType Leaf) { Get-ExchangeFileHash -Path $sourcePath } else { '' }
    $targetHash = if (Test-Path -LiteralPath $targetPath -PathType Leaf) { Get-ExchangeFileHash -Path $targetPath } else { '' }
    $trackedItem = if ($tracked.ContainsKey([string]$item.id)) { $tracked[[string]$item.id] } else { $null }
    $trackedStatus = if ($null -ne $trackedItem) { [string]$trackedItem.status } else { '' }
    $trackedSourceHash = if ($null -ne $trackedItem) { [string]$trackedItem.source_hash } else { '' }
    $sourceChangedSinceDecision = ($sourceHash -and $trackedSourceHash -and $sourceHash -ne $trackedSourceHash)

    if ($trackedStatus -eq 'rejected' -and -not $sourceChangedSinceDecision) {
        continue
    }

    $status = 'missing'
    if ($targetExists) {
        if ($sourceHash -and $targetHash -and $sourceHash -eq $targetHash) {
            $status = 'current'
        }
        elseif ($trackedStatus -eq 'local_override') {
            if (-not $sourceChangedSinceDecision) {
                continue
            }
            $status = 'local_override'
        }
        else {
            $status = 'review_existing'
        }
    }

    if ($status -ne 'current') {
        $proposals.Add([pscustomobject]@{
            id = [string]$item.id
            category = [string]$item.category
            source_path = [string]$item.source_path
            target_path = [string]$item.target_path
            source_exists = $sourceExists
            target_exists = $targetExists
            status = $status
            source_hash = $sourceHash
            target_hash = $targetHash
            description = [string]$item.description
        }) | Out-Null
    }
}

$payload = [pscustomobject]@{
    version = 1
    repo_root = $repo
    repo_kit_root = $repoKit
    generated_utc = (Get-Date).ToUniversalTime().ToString('o')
    proposal_count = $proposals.Count
    proposals = $proposals.ToArray()
}

if ([string]::IsNullOrWhiteSpace($OutputJson)) { $OutputJson = Join-Path $repo '.repo-kit/proposals/import_proposal.json' }
if ([string]::IsNullOrWhiteSpace($OutputMarkdown)) { $OutputMarkdown = Join-Path $repo '.repo-kit/proposals/import_proposal.md' }

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# Repo-Kit Import Proposal') | Out-Null
$lines.Add('') | Out-Null
$lines.Add(('Generated UTC: `{0}`' -f $payload.generated_utc)) | Out-Null
$lines.Add('') | Out-Null
$lines.Add(('Proposal count: `{0}`' -f $payload.proposal_count)) | Out-Null
$lines.Add('') | Out-Null
$lines.Add('| ID | Status | Source | Target |') | Out-Null
$lines.Add('| --- | --- | --- | --- |') | Out-Null
foreach ($proposal in $payload.proposals) {
    $lines.Add(('| `{0}` | {1} | `{2}` | `{3}` |' -f $proposal.id, $proposal.status, $proposal.source_path, $proposal.target_path)) | Out-Null
}
$markdown = ($lines -join [Environment]::NewLine) + [Environment]::NewLine

if (-not $NoWrite) {
    Write-ExchangeJsonFile -Path $OutputJson -Payload $payload
    Write-ExchangeTextFile -Path $OutputMarkdown -Content $markdown
    Write-Output ("Wrote import proposal: {0}" -f $OutputJson)
    Write-Output ("Wrote import proposal markdown: {0}" -f $OutputMarkdown)
}
else {
    Write-Output ("repo-kit import proposal: proposals={0} nowrite=true" -f $payload.proposal_count)
}

exit 0

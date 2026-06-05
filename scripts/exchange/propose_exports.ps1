[CmdletBinding()]
param(
    [string]$RepoRoot = '.',
    [string]$CatalogJson = '',
    [string]$OutputJson = '',
    [string]$OutputMarkdown = '',
    [switch]$IncludeZeroByte,
    [switch]$NoWrite
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'Exchange.Common.ps1')

$repo = Get-ExchangeRepoRoot -Start $RepoRoot
if ([string]::IsNullOrWhiteSpace($CatalogJson)) { $CatalogJson = Join-Path $repo '.repo-kit/catalog.json' }

if (-not (Test-Path -LiteralPath $CatalogJson -PathType Leaf)) {
    & (Join-Path $scriptDir 'catalog_repo.ps1') -RepoRoot $repo -NoWrite | Out-Null
    throw "Missing catalog file: $CatalogJson. Run catalog_repo.ps1 without -NoWrite before proposing exports."
}

$catalog = Read-ExchangeJsonFile -Path $CatalogJson
$manifest = Read-ExchangeManifest -RepoRoot $repo
$trackedExportPaths = @{}
$excludeGlobs = @()
if ($null -ne $manifest) {
    foreach ($item in (Get-ExchangeArray -Value $manifest.exports)) {
        if ($null -ne $item -and -not [string]::IsNullOrWhiteSpace([string]$item.local_path)) {
            $trackedExportPaths[[string]$item.local_path] = $item
        }
    }
    foreach ($item in (Get-ExchangeArray -Value $manifest.exclusions)) {
        if ($null -ne $item -and -not [string]::IsNullOrWhiteSpace([string]$item.glob)) {
            $excludeGlobs += [string]$item.glob
        }
    }
}

$proposals = New-Object System.Collections.Generic.List[object]
foreach ($candidate in (Get-ExchangeArray -Value $catalog.candidates)) {
    $path = [string]$candidate.path
    if ([string]::IsNullOrWhiteSpace($path)) {
        continue
    }
    if ($path -like '*/.gitkeep' -or $path -eq '.gitkeep') {
        continue
    }
    if ($trackedExportPaths.ContainsKey($path)) {
        continue
    }
    if (Test-ExchangeGlobMatch -PathValue $path -Globs $excludeGlobs) {
        continue
    }
    if ([string]$candidate.privacy_classification -in @('private', 'secret', 'local_only')) {
        continue
    }
    if (-not $IncludeZeroByte -and $null -ne $candidate.PSObject.Properties['bytes']) {
        $candidateBytes = [int64]$candidate.bytes
        if ($candidateBytes -eq 0) {
            continue
        }
    }

    $proposals.Add([pscustomobject]@{
        id = (($path -replace '[^A-Za-z0-9]+', '-').Trim('-')).ToLowerInvariant()
        local_path = $path
        proposed_destination = $path
        category = [string]$candidate.category
        privacy_classification = [string]$candidate.privacy_classification
        status = 'candidate'
        sha256 = [string]$candidate.sha256
    }) | Out-Null
}

$payload = [pscustomobject]@{
    version = 1
    repo_root = $repo
    generated_utc = (Get-Date).ToUniversalTime().ToString('o')
    proposal_count = $proposals.Count
    proposals = @($proposals.ToArray() | Sort-Object local_path)
}

if ([string]::IsNullOrWhiteSpace($OutputJson)) { $OutputJson = Join-Path $repo '.repo-kit/proposals/export_proposal.json' }
if ([string]::IsNullOrWhiteSpace($OutputMarkdown)) { $OutputMarkdown = Join-Path $repo '.repo-kit/proposals/export_proposal.md' }

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# Repo-Kit Export Proposal') | Out-Null
$lines.Add('') | Out-Null
$lines.Add(('Generated UTC: `{0}`' -f $payload.generated_utc)) | Out-Null
$lines.Add('') | Out-Null
$lines.Add(('Proposal count: `{0}`' -f $payload.proposal_count)) | Out-Null
$lines.Add('') | Out-Null
$lines.Add('| ID | Category | Local path | Proposed destination |') | Out-Null
$lines.Add('| --- | --- | --- | --- |') | Out-Null
foreach ($proposal in $payload.proposals) {
    $lines.Add(('| `{0}` | {1} | `{2}` | `{3}` |' -f $proposal.id, $proposal.category, $proposal.local_path, $proposal.proposed_destination)) | Out-Null
}
$markdown = ($lines -join [Environment]::NewLine) + [Environment]::NewLine

if (-not $NoWrite) {
    Write-ExchangeJsonFile -Path $OutputJson -Payload $payload
    Write-ExchangeTextFile -Path $OutputMarkdown -Content $markdown
    Write-Output ("Wrote export proposal: {0}" -f $OutputJson)
    Write-Output ("Wrote export proposal markdown: {0}" -f $OutputMarkdown)
}
else {
    Write-Output ("repo-kit export proposal: proposals={0} nowrite=true" -f $payload.proposal_count)
}

exit 0

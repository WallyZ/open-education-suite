[CmdletBinding()]
param(
    [string]$RepoRoot = '.',
    [string]$RepoKitRoot = 'F:\dev\00-repo-kit',
    [Parameter(Mandatory = $true)]
    [string]$ProposalPath,
    [ValidateSet('auto', 'import', 'export')]
    [string]$ProposalType = 'auto',
    [string[]]$ItemId = @(),
    [string]$ReportPath = '',
    [string]$MarkdownPath = '',
    [string]$LedgerPath = '',
    [switch]$Execute,
    [string]$ApprovalToken = '',
    [switch]$AllowOverwrite
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'Exchange.Common.ps1')

function Get-GitHeadRef {
    param([string]$Root)

    try {
        $head = git -C $Root rev-parse HEAD 2>$null
        if ($LASTEXITCODE -eq 0 -and $head) {
            return $head.Trim()
        }
    }
    catch {
    }

    return ''
}

function Get-ExchangePathHash {
    param([string]$Path)

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return Get-ExchangeFileHash -Path $Path
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return ''
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $files = @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue | Sort-Object FullName)
    foreach ($file in $files) {
        $rel = (Get-ExchangeRelativePath -BasePath $Path -PathValue $file.FullName) -replace '\\', '/'
        $hash = Get-ExchangeFileHash -Path $file.FullName
        $lines.Add(('{0}|{1}' -f $rel, $hash)) | Out-Null
    }

    $content = ($lines.ToArray() -join "`n")
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($content)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Copy-ExchangePath {
    param(
        [string]$Source,
        [string]$Target
    )

    if (Test-Path -LiteralPath $Source -PathType Leaf) {
        $parent = Split-Path -Parent $Target
        if ($parent) {
            New-Item -ItemType Directory -Force -Path $parent | Out-Null
        }
        Copy-Item -LiteralPath $Source -Destination $Target -Force
        return
    }

    if (Test-Path -LiteralPath $Source -PathType Container) {
        New-Item -ItemType Directory -Force -Path $Target | Out-Null
        $children = @(Get-ChildItem -LiteralPath $Source -Force -ErrorAction SilentlyContinue)
        foreach ($child in $children) {
            Copy-Item -LiteralPath $child.FullName -Destination $Target -Recurse -Force
        }
        return
    }

    throw "Source path does not exist: $Source"
}

function Get-ProposalKind {
    param(
        [object]$Proposal,
        [string]$RequestedType
    )

    if ($RequestedType -ne 'auto') {
        return $RequestedType
    }

    $first = $null
    foreach ($item in (Get-ExchangeArray -Value $Proposal.proposals)) {
        $first = $item
        break
    }

    if ($null -eq $first) {
        throw 'Proposal contains no items and cannot be auto-detected. Pass -ProposalType import or export.'
    }

    if ($null -ne $first.source_path -and $null -ne $first.target_path) {
        return 'import'
    }

    if ($null -ne $first.local_path -and $null -ne $first.proposed_destination) {
        return 'export'
    }

    throw 'Could not auto-detect proposal type. Pass -ProposalType import or export.'
}

function Render-ExchangeApplyMarkdown {
    param([object]$Report)

    $out = New-Object System.Collections.Generic.List[string]
    $out.Add('# Repo-Kit Exchange Apply Report') | Out-Null
    $out.Add('') | Out-Null
    $out.Add(('- generated_at: `{0}`' -f $Report.generated_at_utc)) | Out-Null
    $out.Add(('- mode: `{0}`' -f $Report.mode)) | Out-Null
    $out.Add(('- proposal_type: `{0}`' -f $Report.proposal_type)) | Out-Null
    $out.Add(('- proposal_path: `{0}`' -f $Report.proposal_path)) | Out-Null
    $out.Add(('- approval_gate_required: **{0}**' -f $Report.approval_gate_required)) | Out-Null
    $out.Add(('- approval_token_provided: **{0}**' -f $Report.approval_token_provided)) | Out-Null
    $out.Add(('- allow_overwrite: **{0}**' -f $Report.allow_overwrite)) | Out-Null
    $out.Add('') | Out-Null
    $out.Add('## Summary') | Out-Null
    $out.Add('') | Out-Null
    $out.Add(('- items_considered: **{0}**' -f $Report.summary.items_considered)) | Out-Null
    $out.Add(('- planned: **{0}**' -f $Report.summary.planned)) | Out-Null
    $out.Add(('- applied: **{0}**' -f $Report.summary.applied)) | Out-Null
    $out.Add(('- skipped: **{0}**' -f $Report.summary.skipped)) | Out-Null
    $out.Add(('- blocked: **{0}**' -f $Report.summary.blocked)) | Out-Null
    $out.Add(('- ledger_entries_written: **{0}**' -f $Report.summary.ledger_entries_written)) | Out-Null
    $out.Add('') | Out-Null
    $out.Add('## Items') | Out-Null
    $out.Add('') | Out-Null
    $out.Add('| ID | Direction | Status | Source | Target |') | Out-Null
    $out.Add('| --- | --- | --- | --- | --- |') | Out-Null
    foreach ($item in (Get-ExchangeArray -Value $Report.items)) {
        $out.Add(('| `{0}` | {1} | {2} | `{3}` | `{4}` |' -f $item.id, $item.direction, $item.status, $item.source_path, $item.target_path)) | Out-Null
    }

    return ($out.ToArray() -join [Environment]::NewLine) + [Environment]::NewLine
}

$repo = Get-ExchangeRepoRoot -Start $RepoRoot
$repoKit = Resolve-ExchangePath -PathValue $RepoKitRoot -BasePath $repo
$resolvedProposalPath = Resolve-ExchangePath -PathValue $ProposalPath -BasePath $repo
if (-not (Test-Path -LiteralPath $resolvedProposalPath -PathType Leaf)) {
    throw "Proposal file not found: $resolvedProposalPath"
}

if ($Execute -and $ApprovalToken -ne 'APPROVED') {
    throw 'Execute mode requires -ApprovalToken APPROVED.'
}

$proposal = Read-ExchangeJsonFile -Path $resolvedProposalPath
if ($null -eq $proposal -or $null -eq $proposal.proposals) {
    throw "Proposal file missing proposals array: $resolvedProposalPath"
}

$kind = Get-ProposalKind -Proposal $proposal -RequestedType $ProposalType
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = Join-Path $repo ('.repo-kit/proposals/exchange_apply_report_{0}.json' -f $timestamp)
}
else {
    $ReportPath = Resolve-ExchangePath -PathValue $ReportPath -BasePath $repo
}
if ([string]::IsNullOrWhiteSpace($MarkdownPath)) {
    $MarkdownPath = [System.IO.Path]::ChangeExtension($ReportPath, '.md')
}
else {
    $MarkdownPath = Resolve-ExchangePath -PathValue $MarkdownPath -BasePath $repo
}

$manifest = Read-ExchangeManifest -RepoRoot $repo
if ([string]::IsNullOrWhiteSpace($LedgerPath)) {
    if ($null -ne $manifest -and $null -ne $manifest.ledger -and -not [string]::IsNullOrWhiteSpace([string]$manifest.ledger.path)) {
        $LedgerPath = Resolve-ExchangePath -PathValue ([string]$manifest.ledger.path) -BasePath $repo
    }
    else {
        $LedgerPath = Join-Path $repo '.repo-kit/exchange-ledger.jsonl'
    }
}
else {
    $LedgerPath = Resolve-ExchangePath -PathValue $LedgerPath -BasePath $repo
}

$selectedIds = @{}
foreach ($id in $ItemId) {
    if (-not [string]::IsNullOrWhiteSpace($id)) {
        $selectedIds[$id] = $true
    }
}

$results = New-Object System.Collections.Generic.List[object]
$ledgerLines = New-Object System.Collections.Generic.List[string]
$items = @(Get-ExchangeArray -Value $proposal.proposals)
foreach ($entry in $items) {
    $id = [string]$entry.id
    if ([string]::IsNullOrWhiteSpace($id)) {
        $id = [Guid]::NewGuid().ToString('N')
    }
    if ($selectedIds.Count -gt 0 -and -not $selectedIds.ContainsKey($id)) {
        continue
    }

    if ($kind -eq 'import') {
        $sourceRel = [string]$entry.source_path
        $targetRel = [string]$entry.target_path
        $sourcePath = Resolve-ExchangePath -PathValue $sourceRel -BasePath $repoKit
        $targetPath = Resolve-ExchangePath -PathValue $targetRel -BasePath $repo
    }
    else {
        $sourceRel = [string]$entry.local_path
        $targetRel = [string]$entry.proposed_destination
        $sourcePath = Resolve-ExchangePath -PathValue $sourceRel -BasePath $repo
        $targetPath = Resolve-ExchangePath -PathValue $targetRel -BasePath $repoKit
    }

    $sourceExists = Test-Path -LiteralPath $sourcePath
    $targetExistsBefore = Test-Path -LiteralPath $targetPath
    $sourceHashBefore = Get-ExchangePathHash -Path $sourcePath
    $targetHashBefore = Get-ExchangePathHash -Path $targetPath
    $status = if ($Execute) { 'applied' } else { 'planned' }
    $reason = ''
    $copied = $false
    $ledgerWritten = $false

    if (-not $sourceExists) {
        $status = 'blocked'
        $reason = 'source_missing'
    }
    elseif ($targetExistsBefore -and -not $AllowOverwrite) {
        $status = 'blocked'
        $reason = 'target_exists_without_allow_overwrite'
    }
    elseif ($Execute) {
        Copy-ExchangePath -Source $sourcePath -Target $targetPath
        $copied = $true
    }

    $targetExistsAfter = Test-Path -LiteralPath $targetPath
    $targetHashAfter = Get-ExchangePathHash -Path $targetPath

    $result = [ordered]@{
        id = $id
        direction = $kind
        status = $status
        reason = $reason
        source_path = $sourcePath
        target_path = $targetPath
        source_relative_path = $sourceRel
        target_relative_path = $targetRel
        source_exists = $sourceExists
        target_exists_before = $targetExistsBefore
        target_exists_after = $targetExistsAfter
        source_hash_before = $sourceHashBefore
        target_hash_before = $targetHashBefore
        target_hash_after = $targetHashAfter
        copied = $copied
        ledger_written = $false
    }

    if ($Execute -and $copied) {
        $ledger = [ordered]@{
            schema_version = 1
            recorded_at_utc = (Get-Date).ToUniversalTime().ToString('o')
            action = 'exchange_apply'
            direction = $kind
            item_id = $id
            approval_token = 'APPROVED'
            repo_root = $repo
            repo_kit_root = $repoKit
            proposal_path = $resolvedProposalPath
            source_path = $sourcePath
            target_path = $targetPath
            source_hash = $sourceHashBefore
            target_hash_before = $targetHashBefore
            target_hash_after = $targetHashAfter
            repo_head = Get-GitHeadRef -Root $repo
            repo_kit_head = Get-GitHeadRef -Root $repoKit
        }
        $ledgerLines.Add(($ledger | ConvertTo-Json -Depth 12 -Compress)) | Out-Null
        $ledgerWritten = $true
        $result.ledger_written = $true
    }

    $results.Add([pscustomobject]$result) | Out-Null
}

if ($Execute -and $ledgerLines.Count -gt 0) {
    $ledgerDir = Split-Path -Parent $LedgerPath
    if ($ledgerDir) {
        New-Item -ItemType Directory -Force -Path $ledgerDir | Out-Null
    }
    Add-Content -LiteralPath $LedgerPath -Value $ledgerLines.ToArray() -Encoding utf8
}

$planned = @($results.ToArray() | Where-Object { $_.status -eq 'planned' }).Count
$applied = @($results.ToArray() | Where-Object { $_.status -eq 'applied' }).Count
$blocked = @($results.ToArray() | Where-Object { $_.status -eq 'blocked' }).Count
$skipped = [Math]::Max(0, $items.Count - $results.Count)
$ledgerWrittenCount = @($results.ToArray() | Where-Object { $_.ledger_written }).Count

$report = [ordered]@{
    schema_version = 1
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    mode = if ($Execute) { 'execute' } else { 'plan' }
    approval_gate_required = $true
    approval_token_provided = (-not [string]::IsNullOrWhiteSpace($ApprovalToken))
    proposal_type = $kind
    proposal_path = $resolvedProposalPath
    repo_root = $repo
    repo_kit_root = $repoKit
    allow_overwrite = [bool]$AllowOverwrite
    ledger_path = $LedgerPath
    summary = [ordered]@{
        items_considered = $items.Count
        planned = $planned
        applied = $applied
        skipped = $skipped
        blocked = $blocked
        ledger_entries_written = $ledgerWrittenCount
    }
    items = $results.ToArray()
}

Write-ExchangeJsonFile -Path $ReportPath -Payload ([pscustomobject]$report)
Write-ExchangeTextFile -Path $MarkdownPath -Content (Render-ExchangeApplyMarkdown -Report ([pscustomobject]$report))

Write-Output ("exchange apply mode: {0}" -f $report.mode)
Write-Output ("proposal type: {0}" -f $kind)
Write-Output ("planned={0} applied={1} blocked={2} skipped={3}" -f $planned, $applied, $blocked, $skipped)
Write-Output ("report json: {0}" -f $ReportPath)
Write-Output ("report md: {0}" -f $MarkdownPath)
if ($Execute) {
    Write-Output ("ledger: {0}" -f $LedgerPath)
}

if ($Execute -and $blocked -gt 0) {
    exit 2
}

exit 0

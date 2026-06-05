[CmdletBinding()]
param(
    [string]$DevRoot = 'F:\dev',
    [string]$RepoKitRoot = 'F:\dev\00-repo-kit',
    [string]$RepoListPath = '',
    [string]$OutputJson = '',
    [string]$OutputMarkdown = '',
    [string]$LatestAliasPrefix = 'reuse_intake_wave',
    [int]$DuplicateMinRepos = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'Exchange.Common.ps1')

function Get-IntakeRepoList {
    param(
        [string]$DevRootPath,
        [string]$RepoListFile,
        [string]$RepoKitPath
    )

    $items = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($RepoListFile)) {
        $resolvedList = Resolve-ExchangePath -PathValue $RepoListFile -BasePath $RepoKitPath
        if (-not (Test-Path -LiteralPath $resolvedList -PathType Leaf)) {
            throw "Repo list not found: $resolvedList"
        }

        foreach ($line in (Get-Content -LiteralPath $resolvedList)) {
            $trimmed = $line.Trim()
            if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) {
                continue
            }
            $items.Add((Resolve-ExchangePath -PathValue $trimmed -BasePath $RepoKitPath)) | Out-Null
        }
    }
    else {
        $resolvedDevRoot = Resolve-ExchangePath -PathValue $DevRootPath -BasePath $RepoKitPath
        if (-not (Test-Path -LiteralPath $resolvedDevRoot -PathType Container)) {
            throw "Dev root not found: $resolvedDevRoot"
        }

        foreach ($dir in (Get-ChildItem -LiteralPath $resolvedDevRoot -Directory -ErrorAction SilentlyContinue)) {
            $gitDir = Join-Path $dir.FullName '.git'
            if (-not (Test-Path -LiteralPath $gitDir)) {
                continue
            }
            $items.Add($dir.FullName) | Out-Null
        }
    }

    $resolvedRepoKit = [System.IO.Path]::GetFullPath($RepoKitPath)
    return @(
        $items.ToArray() |
            Sort-Object -Unique |
            ForEach-Object { [System.IO.Path]::GetFullPath($_) } |
            Where-Object { $_ -ne $resolvedRepoKit }
    )
}

function Invoke-ExchangeScript {
    param(
        [string]$ScriptPath,
        [hashtable]$Arguments
    )

    $output = & $ScriptPath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Script failed: $ScriptPath"
    }
    return $output
}

function Render-IntakeMarkdown {
    param([object]$Report)

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# Cross-Repo Reuse Intake Wave') | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add(('- generated_at: `{0}`' -f $Report.generated_at_utc)) | Out-Null
    $lines.Add(('- dev_root: `{0}`' -f $Report.dev_root)) | Out-Null
    $lines.Add(('- repo_kit_root: `{0}`' -f $Report.repo_kit_root)) | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('| Metric | Value |') | Out-Null
    $lines.Add('| --- | ---: |') | Out-Null
    $lines.Add(('| Repos scanned | {0} |' -f $Report.summary.repo_count)) | Out-Null
    $lines.Add(('| Repos succeeded | {0} |' -f $Report.summary.repo_success_count)) | Out-Null
    $lines.Add(('| Repos failed | {0} |' -f $Report.summary.repo_error_count)) | Out-Null
    $lines.Add(('| Catalog candidates | {0} |' -f $Report.summary.total_catalog_candidates)) | Out-Null
    $lines.Add(('| Import proposals | {0} |' -f $Report.summary.total_import_proposals)) | Out-Null
    $lines.Add(('| Export proposals | {0} |' -f $Report.summary.total_export_proposals)) | Out-Null
    $lines.Add(('| Drift blocking findings | {0} |' -f $Report.summary.total_drift_blocking)) | Out-Null
    $lines.Add(('| Due repos | {0} |' -f $Report.summary.due_count)) | Out-Null
    $lines.Add(('| Promptable repos | {0} |' -f $Report.summary.promptable_count)) | Out-Null
    $lines.Add(('| Duplicate groups | {0} |' -f $Report.summary.duplicate_groups)) | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('## Repo Results') | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('| Repo | Catalog | Imports | Exports | Drift blocking | Due | Promptable |') | Out-Null
    $lines.Add('| --- | ---: | ---: | ---: | ---: | --- | --- |') | Out-Null
    foreach ($repo in (Get-ExchangeArray -Value $Report.repos)) {
        $lines.Add(('| `{0}` | {1} | {2} | {3} | {4} | {5} | {6} |' -f $repo.repo_root, $repo.catalog_candidates, $repo.import_proposals, $repo.export_proposals, $repo.drift_blocking_count, $repo.due, $repo.can_prompt)) | Out-Null
    }

    $lines.Add('') | Out-Null
    $lines.Add('## Duplicate Candidates') | Out-Null
    $lines.Add('') | Out-Null
    if (@($Report.duplicate_candidates).Count -eq 0) {
        $lines.Add('_(none)_') | Out-Null
    }
    else {
        $lines.Add('| SHA256 | Category | Repo count | Reuse suggestions |') | Out-Null
        $lines.Add('| --- | --- | ---: | --- |') | Out-Null
        foreach ($dup in (Get-ExchangeArray -Value $Report.duplicate_candidates)) {
            $suggestions = (($dup.instances | ForEach-Object { '{0}:{1}' -f $_.repo_root, $_.path }) -join '<br>')
            $lines.Add(('| `{0}` | {1} | {2} | {3} |' -f $dup.sha256, $dup.category, $dup.repo_count, $suggestions)) | Out-Null
        }
    }

    if (@($Report.failures).Count -gt 0) {
        $lines.Add('') | Out-Null
        $lines.Add('## Failures') | Out-Null
        $lines.Add('') | Out-Null
        foreach ($failure in (Get-ExchangeArray -Value $Report.failures)) {
            $lines.Add(('- `{0}`: {1}' -f $failure.repo_root, $failure.error)) | Out-Null
        }
    }

    return ($lines.ToArray() -join [Environment]::NewLine) + [Environment]::NewLine
}

function Get-IntakeSum {
    param(
        [object[]]$Rows,
        [string]$PropertyName
    )

    $total = 0
    foreach ($row in (Get-ExchangeArray -Value $Rows)) {
        if ($null -eq $row) {
            continue
        }
        if ($null -eq $row.PSObject.Properties[$PropertyName]) {
            continue
        }
        $value = 0
        try {
            $value = [int]$row.$PropertyName
        }
        catch {
            $value = 0
        }
        $total += $value
    }

    return $total
}

$repoKit = Resolve-ExchangePath -PathValue $RepoKitRoot -BasePath '.'
$repos = @(Get-IntakeRepoList -DevRootPath $DevRoot -RepoListFile $RepoListPath -RepoKitPath $repoKit)
$runStamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd_HHmmss')
if ([string]::IsNullOrWhiteSpace($OutputJson)) {
    $OutputJson = Join-Path $repoKit ('archive/local-reports/reuse_intake_wave_{0}.json' -f $runStamp)
}
if ([string]::IsNullOrWhiteSpace($OutputMarkdown)) {
    $OutputMarkdown = Join-Path $repoKit ('archive/local-reports/reuse_intake_wave_{0}.md' -f $runStamp)
}

$outputJsonResolved = Resolve-ExchangePath -PathValue $OutputJson -BasePath $repoKit
$outputMarkdownResolved = Resolve-ExchangePath -PathValue $OutputMarkdown -BasePath $repoKit
$latestBaseName = if ([string]::IsNullOrWhiteSpace($LatestAliasPrefix)) { 'reuse_intake_wave' } else { $LatestAliasPrefix.Trim() }
$latestJson = Join-Path (Split-Path -Parent $outputJsonResolved) ('{0}_latest.json' -f $latestBaseName)
$latestMarkdown = Join-Path (Split-Path -Parent $outputMarkdownResolved) ('{0}_latest.md' -f $latestBaseName)

$tmpRoot = Join-Path $env:TEMP ('exchange_intake_{0}' -f [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null

$repoRows = New-Object System.Collections.Generic.List[object]
$catalogRows = New-Object System.Collections.Generic.List[object]
$failures = New-Object System.Collections.Generic.List[object]

try {
    foreach ($repoPath in $repos) {
        $repoRoot = Get-ExchangeRepoRoot -Start $repoPath
        $safeName = (($repoRoot -replace '[^A-Za-z0-9]+', '_').Trim('_'))
        $catalogJson = Join-Path $tmpRoot ('{0}_catalog.json' -f $safeName)
        $catalogMarkdown = Join-Path $tmpRoot ('{0}_catalog.md' -f $safeName)
        $importJson = Join-Path $tmpRoot ('{0}_import.json' -f $safeName)
        $importMarkdown = Join-Path $tmpRoot ('{0}_import.md' -f $safeName)
        $exportJson = Join-Path $tmpRoot ('{0}_export.json' -f $safeName)
        $exportMarkdown = Join-Path $tmpRoot ('{0}_export.md' -f $safeName)
        $driftJson = Join-Path $tmpRoot ('{0}_drift.json' -f $safeName)

        try {
            Invoke-ExchangeScript -ScriptPath (Join-Path $scriptDir 'catalog_repo.ps1') -Arguments @{
                RepoRoot = $repoRoot
                OutputJson = $catalogJson
                OutputMarkdown = $catalogMarkdown
            } | Out-Null

            Invoke-ExchangeScript -ScriptPath (Join-Path $scriptDir 'propose_imports.ps1') -Arguments @{
                RepoRoot = $repoRoot
                RepoKitRoot = $repoKit
                OutputJson = $importJson
                OutputMarkdown = $importMarkdown
            } | Out-Null

            Invoke-ExchangeScript -ScriptPath (Join-Path $scriptDir 'propose_exports.ps1') -Arguments @{
                RepoRoot = $repoRoot
                CatalogJson = $catalogJson
                OutputJson = $exportJson
                OutputMarkdown = $exportMarkdown
            } | Out-Null

            Invoke-ExchangeScript -ScriptPath (Join-Path $scriptDir 'check_drift.ps1') -Arguments @{
                RepoRoot = $repoRoot
                RepoKitRoot = $repoKit
                OutputJson = $driftJson
            } | Out-Null

            $dueOutput = Invoke-ExchangeScript -ScriptPath (Join-Path $scriptDir 'check_due.ps1') -Arguments @{
                RepoRoot = $repoRoot
                RepoKitRoot = $repoKit
                Json = $true
            }
            $due = $dueOutput | ConvertFrom-Json

            $catalog = Read-ExchangeJsonFile -Path $catalogJson
            $imports = Read-ExchangeJsonFile -Path $importJson
            $exports = Read-ExchangeJsonFile -Path $exportJson
            $drift = Read-ExchangeJsonFile -Path $driftJson

            foreach ($candidate in (Get-ExchangeArray -Value $catalog.candidates)) {
                $sha = [string]$candidate.sha256
                if ([string]::IsNullOrWhiteSpace($sha)) {
                    continue
                }
                $catalogRows.Add([pscustomobject]@{
                    repo_root = $repoRoot
                    path = [string]$candidate.path
                    category = [string]$candidate.category
                    sha256 = $sha
                }) | Out-Null
            }

            $driftBlocking = @(
                Get-ExchangeArray -Value $drift.findings |
                    Where-Object { [string]$_.status -in @('missing', 'stale', 'local_drift') }
            )
            $repoRows.Add([pscustomobject]@{
                repo_root = $repoRoot
                catalog_candidates = [int]$catalog.candidate_count
                import_proposals = [int]$imports.proposal_count
                export_proposals = [int]$exports.proposal_count
                drift_blocking_count = $driftBlocking.Count
                due = [bool]$due.due
                can_prompt = [bool]$due.can_prompt
            }) | Out-Null
        }
        catch {
            $failures.Add([pscustomobject]@{
                repo_root = $repoRoot
                error = $_.Exception.Message
            }) | Out-Null
        }
    }

    $duplicates = New-Object System.Collections.Generic.List[object]
    $grouped = $catalogRows.ToArray() | Group-Object -Property sha256, category
    foreach ($group in $grouped) {
        $rows = @($group.Group)
        $repoCount = @($rows | Select-Object -ExpandProperty repo_root -Unique).Count
        if ($repoCount -lt $DuplicateMinRepos) {
            continue
        }
        $duplicates.Add([pscustomobject]@{
            sha256 = [string]$rows[0].sha256
            category = [string]$rows[0].category
            repo_count = $repoCount
            instances = $rows
        }) | Out-Null
    }

    $repoArray = @($repoRows.ToArray() | Sort-Object repo_root)
    $failureArray = @($failures.ToArray() | Sort-Object repo_root)
    $report = [pscustomobject]@{
        schema_version = 1
        generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        dev_root = Resolve-ExchangePath -PathValue $DevRoot -BasePath $repoKit
        repo_kit_root = $repoKit
        summary = [pscustomobject]@{
            repo_count = @($repos).Count
            repo_success_count = $repoArray.Count
            repo_error_count = $failureArray.Count
            total_catalog_candidates = Get-IntakeSum -Rows $repoArray -PropertyName 'catalog_candidates'
            total_import_proposals = Get-IntakeSum -Rows $repoArray -PropertyName 'import_proposals'
            total_export_proposals = Get-IntakeSum -Rows $repoArray -PropertyName 'export_proposals'
            total_drift_blocking = Get-IntakeSum -Rows $repoArray -PropertyName 'drift_blocking_count'
            due_count = @($repoArray | Where-Object { $_.due }).Count
            promptable_count = @($repoArray | Where-Object { $_.can_prompt }).Count
            duplicate_groups = $duplicates.Count
        }
        repos = $repoArray
        duplicate_candidates = @($duplicates.ToArray() | Sort-Object repo_count -Descending)
        failures = $failureArray
    }

    Write-ExchangeJsonFile -Path $outputJsonResolved -Payload $report
    Write-ExchangeTextFile -Path $outputMarkdownResolved -Content (Render-IntakeMarkdown -Report $report)
    Write-ExchangeJsonFile -Path $latestJson -Payload $report
    Write-ExchangeTextFile -Path $latestMarkdown -Content (Render-IntakeMarkdown -Report $report)

    Write-Output ("reuse intake wave: repos={0} success={1} failed={2} duplicates={3}" -f $report.summary.repo_count, $report.summary.repo_success_count, $report.summary.repo_error_count, $report.summary.duplicate_groups)
    Write-Output ("report json: {0}" -f $outputJsonResolved)
    Write-Output ("report md: {0}" -f $outputMarkdownResolved)
    Write-Output ("latest json: {0}" -f $latestJson)
    Write-Output ("latest md: {0}" -f $latestMarkdown)
}
finally {
    Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
}

exit 0

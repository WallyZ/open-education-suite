[CmdletBinding()]
param(
    [string[]]$RepoRoot = @('.'),
    [string]$RepoListPath = '',
    [string]$RepoKitRoot = 'F:\dev\00-repo-kit',
    [string]$OutputJson = 'archive/local-reports/exchange_dashboard_report.json',
    [string]$OutputMarkdown = 'archive/local-reports/exchange_dashboard_report.md',
    [int]$DuplicateMinRepos = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'Exchange.Common.ps1')

function Get-DashboardRepoList {
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

function Invoke-JsonScript {
    param(
        [string]$ScriptPath,
        [hashtable]$Arguments
    )

    $scriptArgs = @{}
    foreach ($key in $Arguments.Keys) {
        $value = $Arguments[$key]
        if ($value -is [bool]) {
            if ($value) {
                $scriptArgs[$key] = $true
            }
            continue
        }
        if ($null -eq $value) {
            continue
        }
        $scriptArgs[$key] = $value
    }

    $output = & $ScriptPath @scriptArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Script failed: $ScriptPath"
    }

    return ($output | ConvertFrom-Json)
}

function Count-Status {
    param(
        [object[]]$Items,
        [string]$Status
    )

    return @($Items | Where-Object { [string]$_.status -eq $Status }).Count
}

function Render-DashboardMarkdown {
    param([object]$Report)

    $out = New-Object System.Collections.Generic.List[string]
    $out.Add('# Repo-Kit Exchange Dashboard') | Out-Null
    $out.Add('') | Out-Null
    $out.Add(('- generated_at: `{0}`' -f $Report.generated_at_utc)) | Out-Null
    $out.Add(('- repo_count: **{0}**' -f $Report.summary.repo_count)) | Out-Null
    $out.Add(('- manifests_missing: **{0}**' -f $Report.summary.manifests_missing)) | Out-Null
    $out.Add(('- due_count: **{0}**' -f $Report.summary.due_count)) | Out-Null
    $out.Add(('- drift_findings: **{0}**' -f $Report.summary.drift_findings)) | Out-Null
    $out.Add(('- duplicate_groups: **{0}**' -f $Report.summary.duplicate_groups)) | Out-Null
    $out.Add('') | Out-Null
    $out.Add('## Repos') | Out-Null
    $out.Add('') | Out-Null
    $out.Add('| Repo | Manifest | Imports | Exports | Due | Idle | Drift findings |') | Out-Null
    $out.Add('| --- | --- | ---: | ---: | --- | --- | ---: |') | Out-Null
    foreach ($repo in (Get-ExchangeArray -Value $Report.repos)) {
        $out.Add(('| `{0}` | {1} | {2} | {3} | {4} | {5} | {6} |' -f $repo.repo_root, $repo.manifest_exists, $repo.import_count, $repo.export_count, $repo.due, $repo.idle, $repo.drift_finding_count)) | Out-Null
    }
    $out.Add('') | Out-Null
    $out.Add('## Duplicate Candidates') | Out-Null
    $out.Add('') | Out-Null
    if ($Report.duplicate_candidates.Count -eq 0) {
        $out.Add('_(none)_') | Out-Null
    }
    else {
        $out.Add('| SHA256 | Category | Repo count | Paths |') | Out-Null
        $out.Add('| --- | --- | ---: | --- |') | Out-Null
        foreach ($dup in (Get-ExchangeArray -Value $Report.duplicate_candidates)) {
            $paths = (($dup.instances | ForEach-Object { ('{0}:{1}' -f $_.repo_root, $_.path) }) -join '<br>')
            $out.Add(('| `{0}` | {1} | {2} | {3} |' -f $dup.sha256, $dup.category, $dup.repo_count, $paths)) | Out-Null
        }
    }

    return ($out.ToArray() -join [Environment]::NewLine) + [Environment]::NewLine
}

$baseRoot = Get-ExchangeRepoRoot -Start '.'
$repoKit = Resolve-ExchangePath -PathValue $RepoKitRoot -BasePath $baseRoot
$repos = Get-DashboardRepoList -InlineRoots $RepoRoot -ListPath $RepoListPath -BaseRoot $baseRoot
$tmpRoot = Join-Path $env:TEMP ('exchange_dashboard_{0}' -f [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null

$repoReports = New-Object System.Collections.Generic.List[object]
$catalogRows = New-Object System.Collections.Generic.List[object]

try {
    foreach ($repoItem in $repos) {
        $repo = Get-ExchangeRepoRoot -Start $repoItem
        $manifest = Read-ExchangeManifest -RepoRoot $repo
        $manifestExists = ($null -ne $manifest)
        $imports = @()
        $exports = @()
        if ($manifestExists) {
            $imports = @(Get-ExchangeArray -Value $manifest.imports)
            $exports = @(Get-ExchangeArray -Value $manifest.exports)
        }

        $due = Invoke-JsonScript -ScriptPath (Join-Path $scriptDir 'check_due.ps1') -Arguments @{ RepoRoot = $repo; RepoKitRoot = $repoKit; Json = $true }
        $driftPath = Join-Path $tmpRoot ((($repo -replace '[^A-Za-z0-9]+', '_').Trim('_')) + '_drift.json')
        & (Join-Path $scriptDir 'check_drift.ps1') -RepoRoot $repo -RepoKitRoot $repoKit -OutputJson $driftPath | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Drift check failed for repo: $repo"
        }
        $drift = Read-ExchangeJsonFile -Path $driftPath
        $driftFindings = @()
        if ($null -ne $drift) {
            $driftFindings = @(Get-ExchangeArray -Value $drift.findings | Where-Object { [string]$_.status -ne 'current' })
        }

        $catalogPath = Join-Path $tmpRoot ((($repo -replace '[^A-Za-z0-9]+', '_').Trim('_')) + '_catalog.json')
        $catalogMarkdownPath = [System.IO.Path]::ChangeExtension($catalogPath, '.md')
        & (Join-Path $scriptDir 'catalog_repo.ps1') -RepoRoot $repo -OutputJson $catalogPath -OutputMarkdown $catalogMarkdownPath | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Catalog failed for repo: $repo"
        }
        $catalog = Read-ExchangeJsonFile -Path $catalogPath
        if ($null -ne $catalog) {
            foreach ($candidate in (Get-ExchangeArray -Value $catalog.candidates)) {
                $sha = [string]$candidate.sha256
                if ([string]::IsNullOrWhiteSpace($sha)) {
                    continue
                }
                $catalogRows.Add([pscustomobject]@{
                    repo_root = $repo
                    path = [string]$candidate.path
                    category = [string]$candidate.category
                    privacy_classification = [string]$candidate.privacy_classification
                    sha256 = $sha
                }) | Out-Null
            }
        }

        $repoReports.Add([pscustomobject]@{
            repo_root = $repo
            manifest_exists = $manifestExists
            import_count = $imports.Count
            import_current = Count-Status -Items $imports -Status 'current'
            import_stale = Count-Status -Items $imports -Status 'stale'
            import_local_override = Count-Status -Items $imports -Status 'local_override'
            export_count = $exports.Count
            export_candidates = Count-Status -Items $exports -Status 'candidate'
            export_proposed = Count-Status -Items $exports -Status 'proposed'
            export_exported = Count-Status -Items $exports -Status 'exported'
            due = [bool]$due.due
            idle = [bool]$due.idle
            can_prompt = [bool]$due.can_prompt
            drift_finding_count = $driftFindings.Count
            drift_findings = $driftFindings
        }) | Out-Null
    }

    $duplicates = New-Object System.Collections.Generic.List[object]
    $groups = $catalogRows.ToArray() | Group-Object -Property sha256, category
    foreach ($group in $groups) {
        $rows = @($group.Group)
        $repoCount = @($rows | Select-Object -ExpandProperty repo_root -Unique).Count
        if ($repoCount -lt $DuplicateMinRepos) {
            continue
        }
        $duplicates.Add([pscustomobject]@{
            sha256 = [string]$rows[0].sha256
            category = [string]$rows[0].category
            repo_count = $repoCount
            instance_count = $rows.Count
            instances = $rows
        }) | Out-Null
    }

    $reposArray = $repoReports.ToArray()
    $driftCount = 0
    foreach ($repoReport in $reposArray) {
        $driftCount += [int]$repoReport.drift_finding_count
    }

    $report = [pscustomobject]@{
        schema_version = 1
        generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        repo_kit_root = $repoKit
        summary = [pscustomobject]@{
            repo_count = $reposArray.Count
            manifests_missing = @($reposArray | Where-Object { -not $_.manifest_exists }).Count
            due_count = @($reposArray | Where-Object { $_.due }).Count
            can_prompt_count = @($reposArray | Where-Object { $_.can_prompt }).Count
            drift_findings = $driftCount
            duplicate_groups = $duplicates.Count
        }
        repos = $reposArray
        duplicate_candidates = @($duplicates.ToArray() | Sort-Object -Property repo_count, instance_count -Descending)
    }

    $resolvedJson = Resolve-ExchangePath -PathValue $OutputJson -BasePath $baseRoot
    $resolvedMarkdown = Resolve-ExchangePath -PathValue $OutputMarkdown -BasePath $baseRoot
    Write-ExchangeJsonFile -Path $resolvedJson -Payload $report
    Write-ExchangeTextFile -Path $resolvedMarkdown -Content (Render-DashboardMarkdown -Report $report)

    Write-Output ("exchange dashboard repos={0} due={1} drift_findings={2} duplicate_groups={3}" -f $report.summary.repo_count, $report.summary.due_count, $report.summary.drift_findings, $report.summary.duplicate_groups)
    Write-Output ("report json: {0}" -f $resolvedJson)
    Write-Output ("report md: {0}" -f $resolvedMarkdown)
}
finally {
    Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
}

exit 0

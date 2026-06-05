[CmdletBinding()]
param(
    [string]$RepoRoot = '.',
    [string]$OutputJson = '',
    [string]$OutputMarkdown = '',
    [switch]$IncludeZeroByte,
    [switch]$IncludeGitKeep,
    [switch]$NoWrite
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'Exchange.Common.ps1')

$repo = Get-ExchangeRepoRoot -Start $RepoRoot
$manifest = Read-ExchangeManifest -RepoRoot $repo
$excludeGlobs = @('.git/**', '.codex-cache/**', 'archive/**', '**/__pycache__/**', '*.pyc', 'docs/wavekit/_archive/**', '**/.gitkeep')
if ($null -ne $manifest) {
    foreach ($item in (Get-ExchangeArray -Value $manifest.exclusions)) {
        if ($null -ne $item -and -not [string]::IsNullOrWhiteSpace([string]$item.glob)) {
            $excludeGlobs += [string]$item.glob
        }
    }
}

$scanRoots = @('AGENTS.md', 'docs', 'scripts', 'repo-standards', 'templates', '.github/workflows')
$files = New-Object System.Collections.Generic.List[object]
foreach ($rootRel in $scanRoots) {
    $rootPath = Join-Path $repo $rootRel
    if (-not (Test-Path -LiteralPath $rootPath)) {
        continue
    }

    $items = @()
    if (Test-Path -LiteralPath $rootPath -PathType Leaf) {
        $items = @(Get-Item -LiteralPath $rootPath)
    }
    else {
        $items = @(Get-ChildItem -LiteralPath $rootPath -Recurse -File -ErrorAction SilentlyContinue)
    }

    foreach ($item in $items) {
        $rel = (Get-ExchangeRelativePath -BasePath $repo -PathValue $item.FullName) -replace '\\', '/'
        if (Test-ExchangeGlobMatch -PathValue $rel -Globs $excludeGlobs) {
            continue
        }
        if (-not $IncludeGitKeep -and [string]$item.Name -eq '.gitkeep') {
            continue
        }
        if (-not $IncludeZeroByte -and [int64]$item.Length -eq 0) {
            continue
        }

        $category = if ($rel -like 'scripts/*') { 'scripts' } elseif ($rel -like 'docs/templates/*') { 'template' } elseif ($rel -like 'docs/*') { 'docs' } elseif ($rel -like 'repo-standards/*') { 'standards' } elseif ($rel -like '.github/*') { 'github' } else { 'root' }
        $privacy = if ($rel -like 'docs/templates/*' -or $rel -like 'scripts/*' -or $rel -like 'repo-standards/*' -or $rel -like '.github/*') { 'internal' } else { 'internal' }
        $files.Add([pscustomobject]@{
            path = $rel
            category = $category
            privacy_classification = $privacy
            sha256 = Get-ExchangeFileHash -Path $item.FullName
            bytes = $item.Length
            last_write_utc = $item.LastWriteTimeUtc.ToString('o')
        }) | Out-Null
    }
}

$payload = [pscustomobject]@{
    version = 1
    repo_root = $repo
    generated_utc = (Get-Date).ToUniversalTime().ToString('o')
    candidate_count = $files.Count
    candidates = @($files.ToArray() | Sort-Object path)
}

$defaultJson = Join-Path $repo '.repo-kit/catalog.json'
$defaultMd = Join-Path $repo 'docs/repo-kit/CATALOG.md'
if ([string]::IsNullOrWhiteSpace($OutputJson)) { $OutputJson = $defaultJson }
if ([string]::IsNullOrWhiteSpace($OutputMarkdown)) { $OutputMarkdown = $defaultMd }

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# Repo-Kit Exchange Catalog') | Out-Null
$lines.Add('') | Out-Null
$lines.Add(('Generated UTC: `{0}`' -f $payload.generated_utc)) | Out-Null
$lines.Add('') | Out-Null
$lines.Add(('Candidate count: `{0}`' -f $payload.candidate_count)) | Out-Null
$lines.Add('') | Out-Null
$lines.Add('| Path | Category | Privacy | SHA256 |') | Out-Null
$lines.Add('| --- | --- | --- | --- |') | Out-Null
foreach ($candidate in $payload.candidates) {
    $lines.Add(('| `{0}` | {1} | {2} | `{3}` |' -f $candidate.path, $candidate.category, $candidate.privacy_classification, $candidate.sha256)) | Out-Null
}
$markdown = ($lines -join [Environment]::NewLine) + [Environment]::NewLine

if (-not $NoWrite) {
    Write-ExchangeJsonFile -Path $OutputJson -Payload $payload
    Write-ExchangeTextFile -Path $OutputMarkdown -Content $markdown
    Write-Output ("Wrote exchange catalog: {0}" -f $OutputJson)
    Write-Output ("Wrote exchange catalog markdown: {0}" -f $OutputMarkdown)
}
else {
    Write-Output ("repo-kit exchange catalog: candidates={0} nowrite=true" -f $payload.candidate_count)
}

exit 0

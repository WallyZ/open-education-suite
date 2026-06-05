[CmdletBinding()]
param(
    [string]$RepoRoot = '.',
    [string]$RepoKitRoot = 'F:\dev\00-repo-kit',
    [string]$OutputJson = '',
    [switch]$NoWrite
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'Exchange.Common.ps1')

$repo = Get-ExchangeRepoRoot -Start $RepoRoot
$repoKit = Resolve-ExchangePath -PathValue $RepoKitRoot -BasePath $repo
$manifest = Read-ExchangeManifest -RepoRoot $repo
$results = New-Object System.Collections.Generic.List[object]

if ($null -ne $manifest) {
    foreach ($item in (Get-ExchangeArray -Value $manifest.imports)) {
        if ($null -eq $item) {
            continue
        }

        $sourcePath = Join-Path $repoKit ([string]$item.source_path)
        $targetPath = Join-Path $repo ([string]$item.target_path)
        $sourceHash = if (Test-Path -LiteralPath $sourcePath -PathType Leaf) { Get-ExchangeFileHash -Path $sourcePath } else { '' }
        $targetHash = if (Test-Path -LiteralPath $targetPath -PathType Leaf) { Get-ExchangeFileHash -Path $targetPath } else { '' }
        $recordedHash = [string]$item.source_hash
        $itemStatus = [string]$item.status
        $overrideReason = ''
        if ($null -ne $item.PSObject.Properties['override_reason']) {
            $overrideReason = [string]$item.override_reason
        }
        $status = 'current'
        if ($itemStatus -eq 'rejected') {
            $status = 'rejected'
        }
        elseif (-not (Test-Path -LiteralPath $targetPath)) {
            $status = 'missing'
        }
        elseif ($sourceHash -and $recordedHash -and $sourceHash -ne $recordedHash) {
            $status = 'stale'
        }
        elseif ($targetHash -and $recordedHash -and $targetHash -ne $recordedHash) {
            if ($itemStatus -eq 'local_override' -and -not [string]::IsNullOrWhiteSpace($overrideReason)) {
                $status = 'local_override'
            }
            else {
                $status = 'local_drift'
            }
        }

        $results.Add([pscustomobject]@{
            id = [string]$item.id
            source_path = [string]$item.source_path
            target_path = [string]$item.target_path
            status = $status
            recorded_source_hash = $recordedHash
            current_source_hash = $sourceHash
            current_target_hash = $targetHash
            override_reason = $overrideReason
        }) | Out-Null
    }
}

$payload = [pscustomobject]@{
    version = 1
    repo_root = $repo
    repo_kit_root = $repoKit
    generated_utc = (Get-Date).ToUniversalTime().ToString('o')
    checked_count = $results.Count
    findings = $results.ToArray()
}

if ([string]::IsNullOrWhiteSpace($OutputJson)) { $OutputJson = Join-Path $repo '.repo-kit/proposals/drift_report.json' }

if (-not $NoWrite) {
    Write-ExchangeJsonFile -Path $OutputJson -Payload $payload
    Write-Output ("Wrote drift report: {0}" -f $OutputJson)
}
else {
    Write-Output ("repo-kit drift check: checked={0} nowrite=true" -f $payload.checked_count)
}

$blocking = @($payload.findings | Where-Object { $_.status -in @('missing', 'stale', 'local_drift') })
if ($blocking.Count -gt 0) {
    Write-Output ("repo-kit drift findings: {0}" -f $blocking.Count)
}
else {
    Write-Output 'repo-kit drift findings: 0'
}

exit 0

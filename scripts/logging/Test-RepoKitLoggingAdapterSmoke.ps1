[CmdletBinding()]
param(
    [string]$ModulePath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedModulePath = if (-not [string]::IsNullOrWhiteSpace($ModulePath)) {
    $ModulePath
}
else {
    Join-Path $PSScriptRoot 'RepoKit.LoggingAdapter.psm1'
}

if (-not (Test-Path -LiteralPath $resolvedModulePath)) {
    throw "Missing module path: $resolvedModulePath"
}

Import-Module $resolvedModulePath -Force

$seedSecret = 'SEED_SECRET_PS_456'
$envMap = @{
    LOG_LEVEL = 'INFO'
    LOG_LEVEL_ASSET_PIPELINE = 'DEBUG'
}

$ctx = New-RepoKitLogContext -RunId 'run-smoke-powershell' -TraceId 'trace-smoke-powershell' -Source 'tool:smoke'

$lineDebug = Write-RepoKitStructuredLog -Level 'DEBUG' `
    -Component 'asset_pipeline' `
    -Event 'asset.import.debug' `
    -Message "apikey=$seedSecret importing" `
    -Context $ctx `
    -Environment $envMap `
    -SecretValues @($seedSecret)

if ([string]::IsNullOrWhiteSpace($lineDebug)) {
    throw 'Expected DEBUG line to emit for component override'
}

$lineSuppressed = Write-RepoKitStructuredLog -Level 'DEBUG' `
    -Component 'gameplay' `
    -Event 'gameplay.debug' `
    -Message 'should not emit' `
    -Context $ctx `
    -Environment $envMap `
    -SecretValues @($seedSecret)

if (-not [string]::IsNullOrWhiteSpace($lineSuppressed)) {
    throw 'Expected DEBUG line to be suppressed without component override'
}

$payload = $lineDebug | ConvertFrom-Json -AsHashtable
if ($payload.level -ne 'DEBUG') {
    throw "Expected DEBUG level, got $($payload.level)"
}
if ($payload.run_id -ne 'run-smoke-powershell') {
    throw 'run_id missing from emitted payload'
}
if ($payload.trace_id -ne 'trace-smoke-powershell') {
    throw 'trace_id missing from emitted payload'
}
if ($payload.msg -like "*$seedSecret*") {
    throw 'Seeded secret leaked in PowerShell log output'
}
if ($payload.msg -notlike '*[REDACTED]*') {
    throw 'Expected redacted marker in PowerShell log output'
}

Write-Output 'PowerShell logging adapter smoke passed.'

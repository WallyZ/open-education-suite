[CmdletBinding()]
param(
    [ValidateSet('ollama', 'lm-studio')]
    [string]$Provider = 'ollama',
    [string]$OutputRoot = '.\.codex-cache\tmp\offline-ai-knowledge-store',
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (& git -C . rev-parse --show-toplevel).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repo)) {
    throw 'Unable to resolve repository root with git.'
}

$scriptPath = Join-Path $PSScriptRoot 'build_offline_knowledge_store.py'
if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    throw "Missing offline knowledge-store builder: $scriptPath"
}

$python = Get-Command py -ErrorAction SilentlyContinue
$pythonArgs = @()
if ($python) {
    $pythonExe = $python.Source
    $pythonArgs += '-3'
}
else {
    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) {
        throw 'Python is required to build the SQLite offline knowledge store.'
    }
    $pythonExe = $python.Source
}

$pythonArgs += @(
    '-B',
    $scriptPath,
    '--repo-root',
    $repo,
    '--output-root',
    $OutputRoot,
    '--provider',
    $Provider
)

if ($Check) {
    $pythonArgs += '--check'
}

& $pythonExe @pythonArgs
exit $LASTEXITCODE

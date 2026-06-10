[CmdletBinding()]
param(
    [string]$RepoRoot = ".",
    [string]$HostName = "127.0.0.1",
    [int]$Port = 0,
    [switch]$EnableLiveAi
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-RepoRoot {
    param([string]$Path)

    $candidate = if ([System.IO.Path]::IsPathRooted($Path)) {
        $Path
    }
    else {
        Join-Path (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path $Path
    }

    return (Resolve-Path -LiteralPath $candidate).Path
}

function Get-SelectedPort {
    param([int]$RequestedPort)

    if ($RequestedPort -gt 0) {
        return $RequestedPort
    }

    if ($env:LOCAL_APP_LAUNCHER_SELECTED_PORT -match '^\d+$') {
        return [int]$env:LOCAL_APP_LAUNCHER_SELECTED_PORT
    }

    return 8786
}

function Get-PythonCommand {
    param([string]$ResolvedRepoRoot)

    $venvPython = Join-Path $ResolvedRepoRoot ".venv\Scripts\python.exe"
    if (Test-Path -LiteralPath $venvPython -PathType Leaf) {
        return [pscustomobject]@{
            File = $venvPython
            Args = @("-B")
        }
    }

    $py = Get-Command py -ErrorAction SilentlyContinue
    if ($py) {
        return [pscustomobject]@{
            File = $py.Source
            Args = @("-3", "-B")
        }
    }

    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) {
        throw "Python is required to start the learner UI bridge."
    }

    return [pscustomobject]@{
        File = $python.Source
        Args = @("-B")
    }
}

$resolvedRepoRoot = Get-RepoRoot -Path $RepoRoot
$selectedPort = Get-SelectedPort -RequestedPort $Port
$bridgeScript = Join-Path $resolvedRepoRoot "scripts\teaching\learner_ui_bridge_server.py"
if (-not (Test-Path -LiteralPath $bridgeScript -PathType Leaf)) {
    throw "Learner UI bridge server not found: $bridgeScript"
}

$python = Get-PythonCommand -ResolvedRepoRoot $resolvedRepoRoot
$bridgeArgs = @(
    $bridgeScript,
    "--repo-root",
    $resolvedRepoRoot,
    "--host",
    $HostName,
    "--port",
    [string]$selectedPort
)
if ($EnableLiveAi) {
    $bridgeArgs += "--enable-live-ai"
}

& $python.File @($python.Args + $bridgeArgs)
if ($LASTEXITCODE -ne $null) {
    exit $LASTEXITCODE
}

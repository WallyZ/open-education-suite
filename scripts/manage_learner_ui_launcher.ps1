[CmdletBinding()]
param(
    [ValidateSet("Validate", "SelectPort", "Start", "Stop", "Restart", "Status", "Watchdog", "InstallStartup", "UninstallStartup", "EnableStartup", "DisableStartup")]
    [string]$Action = "Status",
    [ValidateSet("live", "test")]
    [string]$PortMode = "live",
    [string]$ManifestPath = ".codex-cache\launcher\open-education-learner-ui-bridge.json",
    [string]$LauncherKitRoot = "",
    [switch]$Json,
    [switch]$Once,
    [ValidateRange(1, 3600)]
    [int]$WatchdogIntervalSeconds = 15
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-RepoRoot {
    return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
}

function Resolve-RepoPath {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $candidate = if ([System.IO.Path]::IsPathRooted($Path)) {
        $Path
    }
    else {
        Join-Path $RepoRoot $Path
    }

    $parent = Split-Path -Parent $candidate
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        $null = [System.IO.Directory]::CreateDirectory($parent)
    }

    return [System.IO.Path]::GetFullPath($candidate)
}

function Resolve-LauncherKitRoot {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [string]$RequestedRoot
    )

    $candidate = $RequestedRoot
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        $candidate = $env:LOCAL_APP_LAUNCHER_KIT_ROOT
    }
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        $candidate = Join-Path (Split-Path -Parent $RepoRoot) "local-app-launcher-kit"
    }
    if (-not [System.IO.Path]::IsPathRooted($candidate)) {
        $candidate = Join-Path $RepoRoot $candidate
    }

    $resolved = Resolve-Path -LiteralPath $candidate -ErrorAction Stop
    return $resolved.Path
}

function Convert-ActionName {
    param([string]$Name)

    switch ($Name) {
        "Validate" { return "validate" }
        "SelectPort" { return "select-port" }
        "Start" { return "start" }
        "Stop" { return "stop" }
        "Restart" { return "restart" }
        "Status" { return "status" }
        "Watchdog" { return "watchdog" }
        "InstallStartup" { return "install-startup" }
        "UninstallStartup" { return "uninstall-startup" }
        "EnableStartup" { return "enable-startup" }
        "DisableStartup" { return "disable-startup" }
        default { throw "Unsupported launcher action: $Name" }
    }
}

$repoRoot = Get-RepoRoot
$resolvedManifestPath = Resolve-RepoPath -RepoRoot $repoRoot -Path $ManifestPath

& (Join-Path $repoRoot "scripts\export_local_app_launcher_manifest.ps1") -OutputPath $resolvedManifestPath | Write-Verbose

$resolvedLauncherKitRoot = Resolve-LauncherKitRoot -RepoRoot $repoRoot -RequestedRoot $LauncherKitRoot
$launcherScript = Join-Path $resolvedLauncherKitRoot "scripts\launcher\local_app_launcher.ps1"
if (-not (Test-Path -LiteralPath $launcherScript -PathType Leaf)) {
    throw "Local App Launcher Kit controller not found: $launcherScript"
}

$launcherArgs = @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $launcherScript,
    "-Action",
    (Convert-ActionName -Name $Action),
    "-ManifestPath",
    $resolvedManifestPath,
    "-PortMode",
    $PortMode,
    "-WatchdogIntervalSeconds",
    [string]$WatchdogIntervalSeconds
)
if ($Json) {
    $launcherArgs += "-Json"
}
if ($Once) {
    $launcherArgs += "-Once"
}

& powershell.exe @launcherArgs
exit $LASTEXITCODE

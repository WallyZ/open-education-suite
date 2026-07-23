[CmdletBinding()]
param(
    [string]$OutputPath = "",
    [string]$ReviewedAtUtc = "2026-07-22T00:00:00Z",
    [string]$HostName = "127.0.0.1",
    [int]$LivePort = 8786,
    [int]$TestPort = 8787,
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-RepoRoot {
    if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        throw "Unable to resolve script root."
    }

    return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
}

function Get-FallbackEnd {
    param([Parameter(Mandatory = $true)][int]$Port)

    return [Math]::Min(65535, $Port + 99)
}

function Write-Utf8NoBomText {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [AllowEmptyString()]
        [Parameter(Mandatory = $true)][string]$Text
    )

    $encoding = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Text, $encoding)
}

function Resolve-OutputPath {
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

    $fullPath = [System.IO.Path]::GetFullPath($candidate)
    $parent = Split-Path -Parent $fullPath
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        $null = [System.IO.Directory]::CreateDirectory($parent)
    }
    return $fullPath
}

if ($LivePort -eq $TestPort) {
    $TestPort = if ($LivePort -lt 65535) { $LivePort + 1 } else { $LivePort - 1 }
}

$repoRoot = Get-RepoRoot
$manifest = [ordered]@{
    schema_version = "local-app-launcher/v1"
    launcher_id = "open-education-learner-ui-bridge"
    app = [ordered]@{
        repo_id = "open-education-suite"
        display_name = "Open Education Learner UI Bridge"
        description = "Consumer adapter for the local learner UI bridge server."
        privacy_boundary = [ordered]@{
            contains_private_paths = $false
            contains_credentials = $false
            notes = "Manifest uses repo-relative commands and ignored runtime paths only; live AI remains opt-in outside this adapter."
        }
    }
    runtime = [ordered]@{
        cwd = "."
        command = @(
            "powershell.exe",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            "scripts/start_learner_ui_bridge.ps1"
        )
        environment = [ordered]@{
            OPEN_EDUCATION_LOCAL_APP_LAUNCHER = "1"
        }
        pid_file = ".codex-cache/learner-ui/local_app_launcher.pid"
    }
    ports = [ordered]@{
        live = [ordered]@{
            name = "learner_ui_bridge_live"
            host = $HostName
            preferred_port = [int]$LivePort
            fallback_start = [int]$LivePort
            fallback_end = Get-FallbackEnd -Port ([int]$LivePort)
        }
        test = [ordered]@{
            name = "learner_ui_bridge_test"
            host = $HostName
            preferred_port = [int]$TestPort
            fallback_start = [int]$TestPort
            fallback_end = Get-FallbackEnd -Port ([int]$TestPort)
        }
        reserved = @([int]$LivePort, [int]$TestPort)
    }
    health = [ordered]@{
        url_template = "http://127.0.0.1:{port}/ui/learner/index.html"
        timeout_seconds = 10
        expected_status = 200
    }
    watchdog = [ordered]@{
        enabled = $true
        restart_on_exit = $true
        restart_on_unhealthy = $true
        restart_on_file_change = $false
        max_restarts_per_hour = 6
        status_log_path = ".codex-cache/learner-ui/local_app_launcher_status.jsonl"
        exit_log_path = ".codex-cache/learner-ui/local_app_launcher_exit.jsonl"
    }
    windows_startup = [ordered]@{
        supported = $true
        autostart_default = $false
        task_name = "open-education-learner-ui-bridge"
        run_level = "least_privilege"
    }
    operations = [ordered]@{
        start = [ordered]@{
            command = @("powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "scripts/manage_learner_ui_launcher.ps1", "-Action", "Start")
            requires_elevation = $false
            description = "Start the learner UI bridge through Local App Launcher Kit."
        }
        stop = [ordered]@{
            command = @("powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "scripts/manage_learner_ui_launcher.ps1", "-Action", "Stop")
            requires_elevation = $false
            description = "Stop the learner UI bridge process tracked by Local App Launcher Kit."
        }
        restart = [ordered]@{
            command = @("powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "scripts/manage_learner_ui_launcher.ps1", "-Action", "Restart")
            requires_elevation = $false
            description = "Restart the learner UI bridge through Local App Launcher Kit."
        }
        status = [ordered]@{
            command = @("powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "scripts/manage_learner_ui_launcher.ps1", "-Action", "Status")
            requires_elevation = $false
            description = "Show process, port, health, and launcher log status."
        }
        monitor = [ordered]@{
            command = @("powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "scripts/manage_learner_ui_launcher.ps1", "-Action", "Watchdog", "-Once")
            requires_elevation = $false
            description = "Run one watchdog health/restart pass for the learner UI bridge."
        }
    }
    provenance = [ordered]@{
        source_repos = @("open-education-suite", "local-app-launcher-kit")
        reviewed_at_utc = $ReviewedAtUtc
        notes = "Generated from the learner UI bridge server defaults and QA Live workflow port."
    }
}

$manifestJson = $manifest | ConvertTo-Json -Depth 12
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $resolvedOutputPath = Resolve-OutputPath -RepoRoot $repoRoot -Path $OutputPath
    Write-Utf8NoBomText -Path $resolvedOutputPath -Text ($manifestJson + [Environment]::NewLine)
    if (-not $Json) {
        Write-Host ("[local-app-launcher] Manifest written: {0}" -f $resolvedOutputPath)
    }
}

if ($Json -or [string]::IsNullOrWhiteSpace($OutputPath)) {
    Write-Output $manifestJson
}

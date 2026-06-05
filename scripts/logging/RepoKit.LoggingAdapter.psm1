Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RepoKitLevelOrder = [ordered]@{
    TRACE = 0
    DEBUG = 1
    INFO  = 2
    WARN  = 3
    ERROR = 4
    FATAL = 5
}

$script:RepoKitDefaultSecretKeys = @(
    'token',
    'secret',
    'password',
    'apikey',
    'cookie',
    'session',
    'credential'
)

function Resolve-RepoKitLevelName {
    param(
        [string]$Level,
        [string]$Default = 'INFO'
    )

    $candidate = ($Level ?? '').Trim().ToUpperInvariant()
    if (-not $script:RepoKitLevelOrder.Contains($candidate)) {
        return $Default.ToUpperInvariant()
    }

    return $candidate
}

function Get-RepoKitEnvironment {
    $out = @{}
    Get-ChildItem Env:* | ForEach-Object {
        $out[$_.Name] = $_.Value
    }
    return $out
}

function Get-RepoKitEffectiveLogLevel {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Component,
        [hashtable]$Environment
    )

    $envMap = if ($null -ne $Environment) { $Environment } else { Get-RepoKitEnvironment }
    $componentKey = ($Component -replace '[^A-Za-z0-9]+', '_').Trim('_').ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($componentKey)) {
        $componentKey = 'DEFAULT'
    }

    $componentVar = "LOG_LEVEL_$componentKey"
    if ($envMap.ContainsKey($componentVar) -and -not [string]::IsNullOrWhiteSpace($envMap[$componentVar])) {
        return Resolve-RepoKitLevelName -Level $envMap[$componentVar]
    }

    if ($envMap.ContainsKey('LOG_LEVEL') -and -not [string]::IsNullOrWhiteSpace($envMap.LOG_LEVEL)) {
        return Resolve-RepoKitLevelName -Level $envMap.LOG_LEVEL
    }

    return 'INFO'
}

function Test-RepoKitLogEnabled {
    param(
        [Parameter(Mandatory = $true)]
        [string]$MessageLevel,
        [Parameter(Mandatory = $true)]
        [string]$EffectiveLevel
    )

    $msgLevel = Resolve-RepoKitLevelName -Level $MessageLevel
    $effective = Resolve-RepoKitLevelName -Level $EffectiveLevel
    return ($script:RepoKitLevelOrder[$msgLevel] -ge $script:RepoKitLevelOrder[$effective])
}

function New-RepoKitLogContext {
    param(
        [string]$RunId = '',
        [string]$TraceId = '',
        [string]$Source = 'app',
        [string]$Tool = 'powershell'
    )

    $resolvedRunId = if ([string]::IsNullOrWhiteSpace($RunId)) {
        "run-$([Guid]::NewGuid().ToString('N').Substring(0, 12))"
    }
    else {
        $RunId
    }

    $resolvedTraceId = if ([string]::IsNullOrWhiteSpace($TraceId)) {
        "trace-$([Guid]::NewGuid().ToString('N').Substring(0, 16))"
    }
    else {
        $TraceId
    }

    return [ordered]@{
        run_id = $resolvedRunId
        trace_id = $resolvedTraceId
        source = $Source
        tool = $Tool
    }
}

function ConvertTo-RepoKitRedactedText {
    param(
        [AllowNull()]
        [string]$Text,
        [string[]]$SecretValues = @(),
        [string[]]$SecretKeys = $script:RepoKitDefaultSecretKeys
    )

    if ($null -eq $Text) {
        return $Text
    }

    $out = $Text
    foreach ($value in $SecretValues) {
        if (-not [string]::IsNullOrEmpty($value)) {
            $out = $out.Replace($value, '[REDACTED]')
        }
    }

    foreach ($key in $SecretKeys) {
        if ([string]::IsNullOrWhiteSpace($key)) {
            continue
        }
        $pattern = ('(?i)\b{0}\b\s*[:=]\s*[^\s,;]+' -f [regex]::Escape($key))
        $out = [regex]::Replace($out, $pattern, ('{0}=[REDACTED]' -f $key))
    }

    return $out
}

function Write-RepoKitStructuredLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('TRACE', 'DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL')]
        [string]$Level,
        [Parameter(Mandatory = $true)]
        [string]$Component,
        [Parameter(Mandatory = $true)]
        [string]$Event,
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [hashtable]$Context,
        [hashtable]$AdditionalFields,
        [hashtable]$Environment,
        [string[]]$SecretValues = @(),
        [string[]]$SecretKeys = $script:RepoKitDefaultSecretKeys,
        [string]$LogPath = ''
    )

    $ctx = if ($null -ne $Context) { $Context } else { New-RepoKitLogContext }
    $envMap = if ($null -ne $Environment) { $Environment } else { Get-RepoKitEnvironment }
    $effectiveLevel = Get-RepoKitEffectiveLogLevel -Component $Component -Environment $envMap

    if (-not (Test-RepoKitLogEnabled -MessageLevel $Level -EffectiveLevel $effectiveLevel)) {
        return $null
    }

    $msg = ConvertTo-RepoKitRedactedText -Text $Message -SecretValues $SecretValues -SecretKeys $SecretKeys

    $payload = [ordered]@{
        ts = (Get-Date).ToUniversalTime().ToString('o')
        level = Resolve-RepoKitLevelName -Level $Level
        component = $Component
        event = $Event
        msg = $msg
        run_id = $ctx.run_id
        trace_id = $ctx.trace_id
        source = if ($ctx.Contains('source')) { $ctx.source } else { 'app' }
        tool = if ($ctx.Contains('tool')) { $ctx.tool } else { 'powershell' }
    }

    if ($null -ne $AdditionalFields) {
        foreach ($entry in $AdditionalFields.GetEnumerator()) {
            $value = $entry.Value
            if ($value -is [string]) {
                $payload[$entry.Key] = ConvertTo-RepoKitRedactedText -Text $value -SecretValues $SecretValues -SecretKeys $SecretKeys
            }
            else {
                $payload[$entry.Key] = $value
            }
        }
    }

    $line = $payload | ConvertTo-Json -Depth 6 -Compress

    if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
        $dir = Split-Path -Parent $LogPath
        if (-not [string]::IsNullOrWhiteSpace($dir)) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }
        Add-Content -LiteralPath $LogPath -Value $line -Encoding utf8
    }

    Write-Output $line
}

Export-ModuleMember -Function @(
    'Resolve-RepoKitLevelName',
    'Get-RepoKitEffectiveLogLevel',
    'Test-RepoKitLogEnabled',
    'New-RepoKitLogContext',
    'ConvertTo-RepoKitRedactedText',
    'Write-RepoKitStructuredLog'
)

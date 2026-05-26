[CmdletBinding()]
param(
    [string]$ProviderPath = '.\fixtures\lecture-production-providers.json',
    [switch]$RequireConfigured
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ProviderPath -PathType Leaf)) {
    throw "Missing lecture production providers: $ProviderPath"
}

$providers = Get-Content -LiteralPath $ProviderPath -Raw | ConvertFrom-Json
$cloudContracts = @()
$errors = [System.Collections.Generic.List[string]]::new()

foreach ($providerId in @('cloud-tts', 'cloud-avatar', 'cloud-video-assembly')) {
    $provider = @($providers.providers | Where-Object { $_.providerId -eq $providerId } | Select-Object -First 1)
    if ($provider.Count -ne 1) {
        $errors.Add("Missing cloud provider profile: $providerId")
        continue
    }

    $envVars = @()
    foreach ($envVarName in @($provider[0].credentialEnvVars)) {
        $value = [Environment]::GetEnvironmentVariable([string]$envVarName)
        $present = -not [string]::IsNullOrWhiteSpace($value)
        if ($RequireConfigured -and -not $present) {
            $errors.Add("Missing required environment variable for ${providerId}: $envVarName")
        }
        $envVars += [ordered]@{
            name = $envVarName
            present = $present
            value = '<redacted>'
        }
    }

    $stage = switch ($providerId) {
        'cloud-tts' { 'tts' }
        'cloud-avatar' { 'avatar' }
        'cloud-video-assembly' { 'assembly' }
        default { 'unknown' }
    }

    $cloudContracts += [ordered]@{
        providerId = $provider[0].providerId
        stage = $stage
        type = $provider[0].type
        enabledByDefault = $provider[0].enabledByDefault
        capabilities = @($provider[0].capabilities)
        credentialEnvVars = @($envVars)
        outputPolicy = $provider[0].outputPolicy
        publishRequirement = 'cloud outputs must be downloaded to var\lecture-media, checksummed, and operator-approved before publish'
    }
}

[ordered]@{
    schemaVersion = 1
    adapterId = 'cloud-production-adapter-contracts-v1'
    mode = $(if ($RequireConfigured) { 'environment-required' } else { 'contract-check' })
    secretPolicy = 'Environment variable values are never printed; presence is reported with redacted values only.'
    errorCount = $errors.Count
    errors = @($errors)
    contracts = @($cloudContracts)
} | ConvertTo-Json -Depth 10

if ($errors.Count -gt 0) {
    exit 1
}

exit 0

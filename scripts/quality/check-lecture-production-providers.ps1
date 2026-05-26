[CmdletBinding()]
param(
    [string]$ProviderPath = '.\fixtures\lecture-production-providers.json',
    [string]$RepoRoot = '.'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Add-ProviderError {
    param(
        [System.Collections.Generic.List[string]]$Errors,
        [string]$Message
    )
    $Errors.Add($Message)
}

function Test-HasText {
    param([object]$Value)
    return -not [string]::IsNullOrWhiteSpace([string]$Value)
}

function Resolve-RepoRelativePath {
    param(
        [string]$Root,
        [string]$Path
    )

    $rootPath = (Resolve-Path -LiteralPath $Root).Path
    return [System.IO.Path]::GetFullPath((Join-Path -Path $rootPath -ChildPath $Path))
}

$errors = [System.Collections.Generic.List[string]]::new()

if (-not (Test-Path -LiteralPath $ProviderPath -PathType Leaf)) {
    Add-ProviderError $errors "Missing lecture production provider fixture: $ProviderPath"
}

if ($errors.Count -eq 0) {
    $providers = Get-Content -LiteralPath $ProviderPath -Raw | ConvertFrom-Json

    if ($providers.schemaVersion -ne 1) {
        Add-ProviderError $errors 'Lecture production providers schemaVersion must be 1.'
    }
    if (-not (Test-HasText $providers.providerSetId)) {
        Add-ProviderError $errors 'Lecture production providers must declare providerSetId.'
    }
    if (-not ([string]$providers.credentialPolicy).Contains('No provider credentials')) {
        Add-ProviderError $errors 'Lecture production providers must forbid committed credentials.'
    }
    if (-not ([string]$providers.artifactPolicy).Contains('var\lecture-media') -or -not ([string]$providers.artifactPolicy).Contains('SHA-256')) {
        Add-ProviderError $errors 'Lecture production providers must require local archive and SHA-256 checksums.'
    }

    $providerList = @($providers.providers)
    $defaultProvider = @($providerList | Where-Object { $_.providerId -eq $providers.defaultProviderId })
    if ($defaultProvider.Count -ne 1) {
        Add-ProviderError $errors 'Lecture production providers must include exactly one default provider.'
    }
    elseif ($defaultProvider[0].type -ne 'local') {
        Add-ProviderError $errors 'Default lecture production provider should be local.'
    }

    $localComfy = @($providerList | Where-Object { $_.providerId -eq 'local-comfyui' })
    if ($localComfy.Count -ne 1) {
        Add-ProviderError $errors 'Lecture production providers must include local-comfyui.'
    }
    else {
        $localProvider = $localComfy[0]
        if ($localProvider.integrationRepo -ne 'ComfyUI-automation') {
            Add-ProviderError $errors 'local-comfyui must point at the ComfyUI-automation repo.'
        }
        foreach ($capability in @('visual-render', 'avatar-render', 'video-assembly')) {
            if (@($localProvider.capabilities | Where-Object { $_ -eq $capability }).Count -ne 1) {
                Add-ProviderError $errors "local-comfyui missing capability: $capability"
            }
        }
        if (@($localProvider.credentialEnvVars).Count -ne 0) {
            Add-ProviderError $errors 'local-comfyui must not require cloud credentials.'
        }
        if ($localProvider.outputPolicy -ne 'copy-to-local-archive-and-checksum') {
            Add-ProviderError $errors 'local-comfyui output policy must copy artifacts into the local archive and checksum them.'
        }
        $localPath = Resolve-RepoRelativePath -Root $RepoRoot -Path ([string]$localProvider.localPath)
        if (-not (Test-Path -LiteralPath $localPath -PathType Container)) {
            Add-ProviderError $errors "local-comfyui path not found: $localPath"
        }
        else {
            foreach ($requiredPath in @('AGENTS.md', 'workflows')) {
                if (-not (Test-Path -LiteralPath (Join-Path -Path $localPath -ChildPath $requiredPath))) {
                    Add-ProviderError $errors "ComfyUI-automation repo missing expected path: $requiredPath"
                }
            }
            foreach ($stage in @('visuals', 'avatar', 'assembly')) {
                $mapping = @($localProvider.workflowMappings | Where-Object { $_.stage -eq $stage })
                if ($mapping.Count -ne 1) {
                    Add-ProviderError $errors "local-comfyui missing workflow mapping: $stage"
                    continue
                }
                $workflowPath = Join-Path -Path $localPath -ChildPath ([string]$mapping[0].workflowPath)
                if (-not (Test-Path -LiteralPath $workflowPath -PathType Leaf)) {
                    Add-ProviderError $errors "local-comfyui workflow mapping path not found: $($mapping[0].workflowPath)"
                }
            }
        }
    }

    foreach ($cloudProviderId in @('cloud-tts', 'cloud-avatar', 'cloud-video-assembly')) {
        $cloudProvider = @($providerList | Where-Object { $_.providerId -eq $cloudProviderId })
        if ($cloudProvider.Count -ne 1) {
            Add-ProviderError $errors "Lecture production providers missing cloud profile: $cloudProviderId"
            continue
        }
        if ($cloudProvider[0].type -ne 'cloud') {
            Add-ProviderError $errors "Cloud profile must use type cloud: $cloudProviderId"
        }
        if ($cloudProvider[0].enabledByDefault -ne $false) {
            Add-ProviderError $errors "Cloud profile must be opt-in, not enabled by default: $cloudProviderId"
        }
        if (@($cloudProvider[0].credentialEnvVars).Count -lt 2) {
            Add-ProviderError $errors "Cloud profile must declare provider and API key env vars without values: $cloudProviderId"
        }
        if ($cloudProvider[0].outputPolicy -ne 'download-to-local-archive-and-checksum') {
            Add-ProviderError $errors "Cloud output must be downloaded into the local archive and checksummed: $cloudProviderId"
        }
    }

    foreach ($route in @($providers.routing)) {
        if (-not (Test-HasText $route.stage)) {
            Add-ProviderError $errors 'Provider route missing stage.'
        }
        if (@($providerList | Where-Object { $_.providerId -eq $route.preferredProviderId }).Count -ne 1) {
            Add-ProviderError $errors "Provider route points at an unknown preferred provider: $($route.stage)"
        }
        foreach ($fallbackProviderId in @($route.fallbackProviderIds)) {
            if (@($providerList | Where-Object { $_.providerId -eq $fallbackProviderId }).Count -ne 1) {
                Add-ProviderError $errors "Provider route points at an unknown fallback provider: $($route.stage)"
            }
        }
        if (-not ([string]$route.publishRequirement).Contains('checksum') -and -not ([string]$route.publishRequirement).Contains('SHA-256')) {
            Add-ProviderError $errors "Provider route publish requirement must mention checksum: $($route.stage)"
        }
    }

    foreach ($stage in @('tts', 'visuals', 'avatar', 'assembly')) {
        if (@($providers.routing | Where-Object { $_.stage -eq $stage }).Count -ne 1) {
            Add-ProviderError $errors "Lecture production routing missing stage: $stage"
        }
    }
}

[ordered]@{
    schemaVersion = 1
    checkedAt = (Get-Date).ToString('o')
    providerPath = $ProviderPath
    errorCount = $errors.Count
    errors = @($errors)
} | ConvertTo-Json -Depth 8

if ($errors.Count -gt 0) {
    exit 1
}

exit 0

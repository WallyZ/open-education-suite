[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('validate-registry', 'validate-brain', 'validate-domain-cards', 'index', 'query', 'plan-query', 'locator-self-test', 'retrieval-self-test', 'run-tool', 'tool-self-test', 'domain-card-self-test')]
    [string]$Action,
    [string]$RegistryPath = '.\subject-brains.json',
    [string]$BrainRoot = '',
    [string]$IndexPath = '',
    [string]$Question = '',
    [ValidateSet('', 'K-2', '3-5', '6-8', '9-12', 'adult')]
    [string]$GradeBand = '',
    [ValidateRange(1, 20)]
    [int]$Limit = 5,
    [ValidateSet('hybrid', 'lexical')]
    [string]$RetrievalMode = 'hybrid',
    [string]$RequestPath = '',
    [string]$CardsPath = '',
    [switch]$Replace,
    [switch]$StrictFormats
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot 'subject_brain.py'
$python = Get-Command py -ErrorAction SilentlyContinue
$prefix = @()
if ($python) {
    $prefix = @('-3')
}
else {
    $python = Get-Command python -ErrorAction Stop
}

$arguments = @($prefix) + @($scriptPath, $Action)
switch ($Action) {
    'locator-self-test' {
    }
    'retrieval-self-test' {
    }
    'tool-self-test' {
    }
    'domain-card-self-test' {
    }
    'validate-domain-cards' {
        if ([string]::IsNullOrWhiteSpace($CardsPath)) { throw '-CardsPath is required.' }
        $arguments += @('--cards', $CardsPath)
    }
    'run-tool' {
        if ([string]::IsNullOrWhiteSpace($RequestPath)) { throw '-RequestPath is required.' }
        $arguments += @('--request', $RequestPath)
    }
    'validate-registry' {
        $arguments += @('--registry', $RegistryPath)
    }
    'validate-brain' {
        if ([string]::IsNullOrWhiteSpace($BrainRoot)) { throw '-BrainRoot is required.' }
        $arguments += @('--brain-root', $BrainRoot)
    }
    'index' {
        if ([string]::IsNullOrWhiteSpace($BrainRoot) -or [string]::IsNullOrWhiteSpace($IndexPath)) {
            throw '-BrainRoot and -IndexPath are required.'
        }
        $arguments += @('--brain-root', $BrainRoot, '--output', $IndexPath)
        if ($Replace) { $arguments += '--replace' }
        if ($StrictFormats) { $arguments += '--strict-formats' }
    }
    'query' {
        if ([string]::IsNullOrWhiteSpace($IndexPath) -or [string]::IsNullOrWhiteSpace($Question)) {
            throw '-IndexPath and -Question are required.'
        }
        $arguments += @('--index', $IndexPath, '--question', $Question, '--limit', [string]$Limit, '--retrieval-mode', $RetrievalMode)
        if (-not [string]::IsNullOrWhiteSpace($GradeBand)) { $arguments += @('--grade-band', $GradeBand) }
    }
    'plan-query' {
        if ([string]::IsNullOrWhiteSpace($Question)) { throw '-Question is required.' }
        $arguments += @('--registry', $RegistryPath, '--question', $Question, '--limit', [string]$Limit)
        if (-not [string]::IsNullOrWhiteSpace($GradeBand)) { $arguments += @('--grade-band', $GradeBand) }
    }
}

& $python.Source @arguments
exit $LASTEXITCODE

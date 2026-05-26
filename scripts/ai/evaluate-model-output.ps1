[CmdletBinding()]
param(
    [string]$OutputPath = '.\fixtures\ai-teacher-response.grounded.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$output = Get-Content -LiteralPath (Resolve-Path -LiteralPath $OutputPath).Path -Raw | ConvertFrom-Json
$errors = [System.Collections.Generic.List[string]]::new()

if ($output.schemaVersion -ne 1) {
    $errors.Add('Model output schemaVersion must be 1.')
}
if ([string]::IsNullOrWhiteSpace($output.objectiveId)) {
    $errors.Add('Model output missing objectiveId.')
}
if ([string]::IsNullOrWhiteSpace($output.response)) {
    $errors.Add('Model output missing response.')
}
if (@($output.citations).Count -lt 1) {
    $errors.Add('Model output must include at least one source citation.')
}
foreach ($citation in @($output.citations)) {
    if ([string]::IsNullOrWhiteSpace($citation.sourceId) -or [string]::IsNullOrWhiteSpace($citation.sourcePath)) {
        $errors.Add('Each citation must include sourceId and sourcePath.')
    }
}
if (@($output.selfCheck.unsupportedClaims).Count -gt 0) {
    $errors.Add('Model output contains unsupported claims.')
}
if ($output.selfCheck.directStateMutation -ne $false) {
    $errors.Add('Model output must not directly mutate durable state.')
}
if ($output.selfCheck.grounded -ne $true) {
    $errors.Add('Model output selfCheck must be grounded.')
}
if ($output.selfCheck.objectiveAligned -ne $true) {
    $errors.Add('Model output selfCheck must be objective aligned.')
}
if ($output.selfCheck.accessible -ne $true) {
    $errors.Add('Model output selfCheck must be accessible.')
}
if ($output.stateUpdateProposal.type -ne 'none' -and $output.stateUpdateProposal.type -ne 'proposal') {
    $errors.Add('State update must be none or proposal.')
}

[ordered]@{
    schemaVersion = 1
    checkedAt = (Get-Date).ToString('o')
    errorCount = $errors.Count
    errors = @($errors)
} | ConvertTo-Json -Depth 8

if ($errors.Count -gt 0) {
    exit 1
}

exit 0

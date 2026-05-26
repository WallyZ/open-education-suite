[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PackageRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$errors = [System.Collections.Generic.List[string]]::new()
$packagePath = Join-Path $PackageRoot 'package.json'
$objectsPath = Join-Path $PackageRoot 'objects.jsonl'
$sourcesPath = Join-Path $PackageRoot 'sources'

if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
    $errors.Add("Missing package.json: $packagePath")
}
if (-not (Test-Path -LiteralPath $objectsPath -PathType Leaf)) {
    $errors.Add("Missing objects.jsonl: $objectsPath")
}
if (-not (Test-Path -LiteralPath $sourcesPath -PathType Container)) {
    $errors.Add("Missing sources folder: $sourcesPath")
}

if ($errors.Count -eq 0) {
    $package = Get-Content -LiteralPath $packagePath -Raw | ConvertFrom-Json
    $objectLines = @(Get-Content -LiteralPath $objectsPath)
    if ($package.schemaVersion -ne 1) {
        $errors.Add('package.json schemaVersion must be 1.')
    }
    if ($objectLines.Count -ne [int]$package.objectCount) {
        $errors.Add("objects.jsonl line count $($objectLines.Count) does not match package objectCount $($package.objectCount).")
    }
    foreach ($line in $objectLines) {
        $object = $line | ConvertFrom-Json
        foreach ($field in @('id', 'sourceId', 'sourcePath', 'sourceRepo', 'type', 'title', 'license', 'attribution')) {
            if ([string]::IsNullOrWhiteSpace($object.$field)) {
                $errors.Add("Packaged object '$($object.id)' missing $field.")
            }
        }
        $copied = Join-Path (Join-Path $sourcesPath $object.sourceId) $object.sourcePath
        if (-not (Test-Path -LiteralPath $copied -PathType Leaf)) {
            $errors.Add("Packaged object source file missing: $copied")
        }
    }
}

[ordered]@{
    schemaVersion = 1
    checkedAt = (Get-Date).ToString('o')
    packageRoot = $PackageRoot
    errorCount = $errors.Count
    errors = @($errors)
} | ConvertTo-Json -Depth 8

if ($errors.Count -gt 0) {
    exit 1
}

exit 0

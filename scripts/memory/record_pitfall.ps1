[CmdletBinding()]
param(
    [string]$RepoRoot = '.',
    [string]$MemoryBankDir = 'memory-bank',
    [string]$ErrorText = '',
    [string]$Solution = '',
    [string]$Context = '',
    [string]$Category = '',
    [string]$SourcePath = '',
    [string]$VerificationCommand = '',
    [string[]]$Tags = @(),
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RepoRootPath {
    param([string]$Start)

    $resolved = (Resolve-Path -LiteralPath $Start).Path
    try {
        $top = git -C $resolved rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0 -and $top) {
            return $top.Trim()
        }
    }
    catch {
    }

    return $resolved
}

function Get-PitfallCategory {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return 'general'
    }

    $value = $Text.ToLowerInvariant()
    if ($value -match 'modulenotfounderror|importerror|pythonpath|sys\.path') {
        return 'python-imports'
    }
    if ($value -match 'parsererror|unexpected token|term is not recognized|call operator|&&') {
        return 'powershell-invocation'
    }
    if ($value -match 'convertfrom-json|json|invalid object passed in') {
        return 'json-data'
    }
    if ($value -match 'markdown|unresolved local reference|missing markdown reference') {
        return 'markdown-docs'
    }
    if ($value -match 'memory-bank|stale freshness date|handoff token') {
        return 'memory-bank'
    }
    if ($value -match 'unresolved external|lnk[0-9]+|undefined reference') {
        return 'cpp-linking'
    }
    if ($value -match 'cannot open include file|c1083|no such file or directory') {
        return 'cpp-includes'
    }
    if ($value -match 'blueprint|compileallblueprints|unrealeditor|uat|ubt') {
        return 'unreal'
    }

    return 'general'
}

function Escape-Multiline {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return '_not provided_'
    }

    return (($Value -replace "`r", '') -replace "`n", ' ').Trim()
}

$repo = Get-RepoRootPath -Start $RepoRoot
$memoryRoot = Join-Path $repo $MemoryBankDir
$target = Join-Path $memoryRoot 'commonPitfalls.md'
$today = Get-Date -Format 'yyyy-MM-dd'

if ([string]::IsNullOrWhiteSpace($Category)) {
    $Category = Get-PitfallCategory -Text (($ErrorText, $Context, $Solution) -join ' ')
}

if ([string]::IsNullOrWhiteSpace($Solution)) {
    throw 'Solution is required so future waves know what to reuse.'
}

$tagText = if ($Tags.Count -gt 0) { ($Tags -join ', ') } else { $Category }
$sourceText = if ([string]::IsNullOrWhiteSpace($SourcePath)) { '_not provided_' } else { $SourcePath }
$verificationText = if ([string]::IsNullOrWhiteSpace($VerificationCommand)) { '_not provided_' } else { $VerificationCommand }
$entry = @(
    '',
    ("## {0} - {1}" -f $today, $Category),
    '',
    ("- Context: {0}" -f (Escape-Multiline -Value $Context)),
    ("- Error signal: {0}" -f (Escape-Multiline -Value $ErrorText)),
    ("- Solution used: {0}" -f (Escape-Multiline -Value $Solution)),
    ("- Source path: {0}" -f $sourceText),
    ("- Verification: {0}" -f $verificationText),
    ("- Tags: {0}" -f $tagText)
) -join "`n"

$header = @(
    '# Common Pitfalls',
    '',
    'Durable issue and fix log for recurring coding, tooling, and workflow problems.',
    '',
    'Use `scripts/memory/record_pitfall.ps1` after resolving a nontrivial failure so future waves can search for the symptom and reuse the fix.',
    '',
    '## Index',
    '',
    '- Categories are inferred when `-Category` is omitted.',
    '- Keep entries compact and focused on symptoms, fix, and verification.',
    '',
    '## Entries',
    ''
) -join "`n"

if ($DryRun) {
    Write-Output $entry
    exit 0
}

New-Item -ItemType Directory -Force -Path $memoryRoot | Out-Null
if (-not (Test-Path -LiteralPath $target)) {
    Set-Content -LiteralPath $target -Encoding utf8 -Value $header
}

Add-Content -LiteralPath $target -Encoding utf8 -Value $entry
Write-Output ("Recorded pitfall: {0} category={1}" -f $target, $Category)
exit 0

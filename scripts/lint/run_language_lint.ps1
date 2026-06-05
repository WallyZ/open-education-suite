[CmdletBinding()]
param(
    [string]$RepoRoot = '.',
    [switch]$RequireExternalTools,
    [switch]$EnforceDocsTerminology,
    [string]$MatrixPath = '',
    [string]$OutputJson = '',
    [string]$OutputMarkdown = ''
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

function Get-RelativePath {
    param(
        [string]$Base,
        [string]$PathValue
    )

    return [System.IO.Path]::GetRelativePath($Base, $PathValue).Replace('\', '/')
}

function Test-SkippedPath {
    param([string]$RelativePath)

    $normalized = $RelativePath.Replace('\', '/')
    $skipPrefixes = @(
        '.git/',
        '.codex-cache/',
        '.venv/',
        'venv/',
        'archive/',
        'data/dev/_golden_repo_check_tmp/',
        'data/dev/_sync_contract_check_tmp/'
    )

    foreach ($prefix in $skipPrefixes) {
        if ($normalized.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    if ($normalized -match '(^|/)__pycache__(/|$)') {
        return $true
    }

    return $false
}

function Get-LanguageFiles {
    param(
        [string]$Repo,
        [string[]]$Extensions
    )

    $items = New-Object System.Collections.Generic.List[object]
    foreach ($file in (Get-ChildItem -LiteralPath $Repo -Recurse -File -ErrorAction SilentlyContinue)) {
        $rel = Get-RelativePath -Base $Repo -PathValue $file.FullName
        if (Test-SkippedPath -RelativePath $rel) {
            continue
        }
        if ($Extensions -contains $file.Extension.ToLowerInvariant()) {
            $items.Add($file) | Out-Null
        }
    }

    return $items.ToArray()
}

function Add-CheckResult {
    param(
        [System.Collections.Generic.List[object]]$Results,
        [string]$Name,
        [string]$Status,
        [string]$Detail
    )

    $Results.Add([pscustomobject]@{
        name = $Name
        status = $Status
        detail = $Detail
    }) | Out-Null
}

function Test-CommandExists {
    param([string]$Name)

    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-JsonProperty {
    param(
        [object]$ObjectValue,
        [string]$Name
    )

    if ($null -eq $ObjectValue) {
        return $null
    }

    $property = $ObjectValue.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Resolve-MatrixPath {
    param(
        [string]$Repo,
        [string]$RequestedPath
    )

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        return (Resolve-Path -LiteralPath $RequestedPath).Path
    }

    $defaultPath = Join-Path $Repo 'repo-standards\lint\language_lint_matrix.json'
    if (Test-Path -LiteralPath $defaultPath) {
        return $defaultPath
    }

    return ''
}

function Resolve-CspellConfigPath {
    param([string]$Repo)

    $candidates = @(
        'repo-standards\lint\cspell.json',
        '.cspell.json',
        'cspell.json'
    )
    foreach ($candidate in $candidates) {
        $path = Join-Path $Repo $candidate
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            return $path
        }
    }

    return ''
}

function Get-ApplicableMatrixProfiles {
    param(
        [string]$Repo,
        [object]$Matrix
    )

    $profiles = New-Object System.Collections.Generic.List[object]
    $matrixProfiles = Get-JsonProperty -ObjectValue $Matrix -Name 'profiles'
    if ($null -eq $matrixProfiles) {
        return $profiles.ToArray()
    }

    foreach ($profile in @($matrixProfiles)) {
        $detect = Get-JsonProperty -ObjectValue $profile -Name 'detect'
        $extensions = @((Get-JsonProperty -ObjectValue $detect -Name 'extensions') | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        $paths = @((Get-JsonProperty -ObjectValue $detect -Name 'paths') | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })

        $matched = New-Object System.Collections.Generic.List[string]
        foreach ($extension in $extensions) {
            $matches = @(Get-LanguageFiles -Repo $Repo -Extensions @([string]$extension))
            if ($matches.Count -gt 0) {
                $matched.Add(('{0} files={1}' -f $extension, $matches.Count)) | Out-Null
            }
        }

        foreach ($path in $paths) {
            if (Test-Path -LiteralPath (Join-Path $Repo ([string]$path))) {
                $matched.Add(('path={0}' -f $path)) | Out-Null
            }
        }

        $profiles.Add([pscustomobject]@{
            id = [string](Get-JsonProperty -ObjectValue $profile -Name 'id')
            language = [string](Get-JsonProperty -ObjectValue $profile -Name 'language')
            applies = ($matched.Count -gt 0)
            matched = @($matched)
            required_tools = @((Get-JsonProperty -ObjectValue $profile -Name 'required_tools'))
            optional_tools = @((Get-JsonProperty -ObjectValue $profile -Name 'optional_tools'))
            local_fallback = [string](Get-JsonProperty -ObjectValue $profile -Name 'local_fallback')
            report_artifact = [string](Get-JsonProperty -ObjectValue $profile -Name 'report_artifact')
            downstream_applicability = [string](Get-JsonProperty -ObjectValue $profile -Name 'downstream_applicability')
        }) | Out-Null
    }

    return $profiles.ToArray()
}

function Write-LanguageLintMarkdown {
    param([object]$Report)

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# Language Lint Report') | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add(('- generated_at_utc: `{0}`' -f $Report.generated_at_utc)) | Out-Null
    $lines.Add(('- repo_root: `{0}`' -f $Report.repo_root)) | Out-Null
    $lines.Add(('- matrix_path: `{0}`' -f $Report.matrix_path)) | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('## Results') | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('| Check | Status | Detail |') | Out-Null
    $lines.Add('| --- | --- | --- |') | Out-Null
    foreach ($result in $Report.results) {
        $lines.Add(('| {0} | {1} | {2} |' -f $result.name, $result.status, $result.detail)) | Out-Null
    }
    $lines.Add('') | Out-Null
    $lines.Add('## Matrix Profiles') | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('| Applies | Profile | Required | Optional | Report |') | Out-Null
    $lines.Add('| --- | --- | --- | --- | --- |') | Out-Null
    foreach ($profile in $Report.matrix_profiles) {
        $lines.Add(('| {0} | `{1}` | {2} | {3} | `{4}` |' -f $profile.applies, $profile.id, (($profile.required_tools) -join ', '), (($profile.optional_tools) -join ', '), $profile.report_artifact)) | Out-Null
    }

    return ($lines -join "`n")
}

$repo = Get-RepoRootPath -Start $RepoRoot
$results = New-Object System.Collections.Generic.List[object]
$failures = New-Object System.Collections.Generic.List[string]
$resolvedMatrixPath = Resolve-MatrixPath -Repo $repo -RequestedPath $MatrixPath
$matrix = $null
if (-not [string]::IsNullOrWhiteSpace($resolvedMatrixPath)) {
    $matrix = Get-Content -LiteralPath $resolvedMatrixPath -Raw | ConvertFrom-Json
}

Push-Location $repo
try {
    $markdownDocFiles = @(Get-LanguageFiles -Repo $repo -Extensions @('.md'))
    if (Test-Path -LiteralPath 'scripts/lifecycle/check_markdown_paths.py') {
        $output = python scripts/lifecycle/check_markdown_paths.py --repo-root . 2>&1
        if ($LASTEXITCODE -eq 0) {
            Add-CheckResult -Results $results -Name 'Markdown' -Status 'pass' -Detail 'check_markdown_paths.py passed'
        }
        else {
            $failures.Add("Markdown path check failed: $($output -join ' ')") | Out-Null
            Add-CheckResult -Results $results -Name 'Markdown' -Status 'fail' -Detail 'check_markdown_paths.py failed'
        }
    }
    else {
        Add-CheckResult -Results $results -Name 'Markdown' -Status 'skip' -Detail 'no markdown checker found'
    }

    if ($markdownDocFiles.Count -gt 0) {
        $cspellConfig = Resolve-CspellConfigPath -Repo $repo
        if (Test-CommandExists -Name 'cspell') {
            if ([string]::IsNullOrWhiteSpace($cspellConfig)) {
                if ($EnforceDocsTerminology) {
                    $failures.Add('Docs terminology lint is enforced but no cspell config was found.') | Out-Null
                    Add-CheckResult -Results $results -Name 'Docs terminology' -Status 'fail' -Detail 'missing cspell config'
                }
                else {
                    Add-CheckResult -Results $results -Name 'Docs terminology' -Status 'skip' -Detail 'cspell installed but no cspell config found'
                }
            }
            else {
                $cspellConfigRel = Get-RelativePath -Base $repo -PathValue $cspellConfig
                $output = cspell --config $cspellConfigRel --no-progress . 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Add-CheckResult -Results $results -Name 'Docs terminology' -Status 'pass' -Detail ("cspell passed with {0}" -f $cspellConfigRel)
                }
                elseif ($EnforceDocsTerminology) {
                    $failures.Add("Docs terminology lint failed: $($output -join ' ')") | Out-Null
                    Add-CheckResult -Results $results -Name 'Docs terminology' -Status 'fail' -Detail ("cspell findings promoted to failure with {0}" -f $cspellConfigRel)
                }
                else {
                    Add-CheckResult -Results $results -Name 'Docs terminology' -Status 'warn' -Detail ("cspell reported findings with {0}; use allowlist or -EnforceDocsTerminology after promotion" -f $cspellConfigRel)
                }
            }
        }
        elseif ($EnforceDocsTerminology) {
            $failures.Add('Docs terminology lint is enforced but cspell is not available.') | Out-Null
            Add-CheckResult -Results $results -Name 'Docs terminology' -Status 'fail' -Detail 'cspell required by -EnforceDocsTerminology'
        }
        else {
            Add-CheckResult -Results $results -Name 'Docs terminology' -Status 'skip' -Detail ("{0} Markdown files found; optional cspell unavailable" -f $markdownDocFiles.Count)
        }
    }

    $pyFiles = @(Get-LanguageFiles -Repo $repo -Extensions @('.py'))
    if ($pyFiles.Count -gt 0) {
        $previousPrefix = $env:PYTHONPYCACHEPREFIX
        $cacheRoot = Join-Path $env:TEMP 'repo_kit_pycache'
        $env:PYTHONPYCACHEPREFIX = $cacheRoot
        try {
            foreach ($file in $pyFiles) {
                $output = python -m py_compile $file.FullName 2>&1
                if ($LASTEXITCODE -ne 0) {
                    $rel = Get-RelativePath -Base $repo -PathValue $file.FullName
                    $failures.Add("Python compile failed: $rel :: $($output -join ' ')") | Out-Null
                }
            }
        }
        finally {
            $env:PYTHONPYCACHEPREFIX = $previousPrefix
            Remove-Item -LiteralPath $cacheRoot -Recurse -Force -ErrorAction SilentlyContinue
        }

        if (@($failures | Where-Object { $_ -like 'Python compile failed:*' }).Count -eq 0) {
            Add-CheckResult -Results $results -Name 'Python' -Status 'pass' -Detail ("py_compile passed for {0} files" -f $pyFiles.Count)
        }
        else {
            Add-CheckResult -Results $results -Name 'Python' -Status 'fail' -Detail 'one or more files failed py_compile'
        }
    }
    else {
        Add-CheckResult -Results $results -Name 'Python' -Status 'skip' -Detail 'no Python files found'
    }

    $psFiles = @(Get-LanguageFiles -Repo $repo -Extensions @('.ps1', '.psm1', '.psd1'))
    if ($psFiles.Count -gt 0) {
        foreach ($file in $psFiles) {
            $tokens = $null
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
            if ($errors -and $errors.Count -gt 0) {
                $rel = Get-RelativePath -Base $repo -PathValue $file.FullName
                foreach ($err in $errors) {
                    $failures.Add("PowerShell parse failed: $rel :: $($err.Message)") | Out-Null
                }
            }
        }

        if (@($failures | Where-Object { $_ -like 'PowerShell parse failed:*' }).Count -eq 0) {
            Add-CheckResult -Results $results -Name 'PowerShell' -Status 'pass' -Detail ("parser passed for {0} files" -f $psFiles.Count)
        }
        else {
            Add-CheckResult -Results $results -Name 'PowerShell' -Status 'fail' -Detail 'one or more scripts failed parser checks'
        }

        if (Test-CommandExists -Name 'Invoke-ScriptAnalyzer') {
            $analyzerFindings = @()
            foreach ($file in $psFiles) {
                $analyzerFindings += @(Invoke-ScriptAnalyzer -Path $file.FullName 2>&1)
            }
            $blockingFindings = @($analyzerFindings | Where-Object { $null -ne $_.Severity -and [string]$_.Severity -eq 'Error' })
            if ($blockingFindings.Count -eq 0) {
                Add-CheckResult -Results $results -Name 'PSScriptAnalyzer' -Status 'pass' -Detail 'Invoke-ScriptAnalyzer reported no error findings'
            }
            else {
                $failures.Add("PSScriptAnalyzer error findings: $($blockingFindings -join ' ')") | Out-Null
                Add-CheckResult -Results $results -Name 'PSScriptAnalyzer' -Status 'fail' -Detail 'Invoke-ScriptAnalyzer reported error findings'
            }
        }
        elseif ($RequireExternalTools) {
            $failures.Add('PSScriptAnalyzer is required but not available.') | Out-Null
            Add-CheckResult -Results $results -Name 'PSScriptAnalyzer' -Status 'fail' -Detail 'required tool missing'
        }
        else {
            Add-CheckResult -Results $results -Name 'PSScriptAnalyzer' -Status 'skip' -Detail 'optional tool not installed'
        }
    }

    $jsonFiles = @(Get-LanguageFiles -Repo $repo -Extensions @('.json'))
    foreach ($file in $jsonFiles) {
        try {
            $null = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json -AsHashtable
        }
        catch {
            $rel = Get-RelativePath -Base $repo -PathValue $file.FullName
            $failures.Add("JSON parse failed: $rel :: $($_.Exception.Message)") | Out-Null
        }
    }
    if ($jsonFiles.Count -gt 0) {
        if (@($failures | Where-Object { $_ -like 'JSON parse failed:*' }).Count -eq 0) {
            Add-CheckResult -Results $results -Name 'JSON' -Status 'pass' -Detail ("ConvertFrom-Json passed for {0} files" -f $jsonFiles.Count)
        }
        else {
            Add-CheckResult -Results $results -Name 'JSON' -Status 'fail' -Detail 'one or more JSON files failed parsing'
        }
    }

    $yamlFiles = @(Get-LanguageFiles -Repo $repo -Extensions @('.yml', '.yaml'))
    if ($yamlFiles.Count -gt 0) {
        if (Test-CommandExists -Name 'yamllint') {
            $output = yamllint . 2>&1
            if ($LASTEXITCODE -eq 0) {
                Add-CheckResult -Results $results -Name 'YAML' -Status 'pass' -Detail 'yamllint passed'
            }
            else {
                $failures.Add("YAML lint failed: $($output -join ' ')") | Out-Null
                Add-CheckResult -Results $results -Name 'YAML' -Status 'fail' -Detail 'yamllint failed'
            }
        }
        elseif ($RequireExternalTools) {
            $failures.Add('yamllint is required but not available.') | Out-Null
            Add-CheckResult -Results $results -Name 'YAML' -Status 'fail' -Detail 'required tool missing'
        }
        else {
            Add-CheckResult -Results $results -Name 'YAML' -Status 'skip' -Detail ("{0} YAML files found; optional yamllint unavailable" -f $yamlFiles.Count)
        }
    }

    if (Test-Path -LiteralPath 'package.json') {
        $package = Get-Content -LiteralPath 'package.json' -Raw | ConvertFrom-Json
        if ($package.scripts -and $package.scripts.PSObject.Properties['lint'] -and (Test-CommandExists -Name 'npm')) {
            $output = npm run lint --if-present 2>&1
            if ($LASTEXITCODE -eq 0) {
                Add-CheckResult -Results $results -Name 'JavaScript/TypeScript' -Status 'pass' -Detail 'npm run lint passed'
            }
            else {
                $failures.Add("npm lint failed: $($output -join ' ')") | Out-Null
                Add-CheckResult -Results $results -Name 'JavaScript/TypeScript' -Status 'fail' -Detail 'npm run lint failed'
            }
        }
        else {
            Add-CheckResult -Results $results -Name 'JavaScript/TypeScript' -Status 'skip' -Detail 'package.json present; no runnable lint script found'
        }
    }

    $csharpFiles = @(Get-LanguageFiles -Repo $repo -Extensions @('.cs', '.csproj', '.sln'))
    if ($csharpFiles.Count -gt 0) {
        $hasDotnetProject = @($csharpFiles | Where-Object { $_.Extension.ToLowerInvariant() -in @('.csproj', '.sln') }).Count -gt 0
        if ($RequireExternalTools -and -not (Test-CommandExists -Name 'dotnet')) {
            $failures.Add('C# lint requires dotnet when -RequireExternalTools is set.') | Out-Null
            Add-CheckResult -Results $results -Name 'C# / Unreal build scripts' -Status 'fail' -Detail 'dotnet is required but unavailable'
        }
        elseif ($RequireExternalTools -and -not $hasDotnetProject) {
            Add-CheckResult -Results $results -Name 'C# / Unreal build scripts' -Status 'skip' -Detail ("{0} C# file(s) found; dotnet format requires a .sln or .csproj" -f $csharpFiles.Count)
        }
        elseif ($RequireExternalTools) {
            $output = dotnet format --verify-no-changes 2>&1
            if ($LASTEXITCODE -eq 0) {
                Add-CheckResult -Results $results -Name 'C# / Unreal build scripts' -Status 'pass' -Detail 'dotnet format --verify-no-changes passed'
            }
            else {
                $failures.Add("C# dotnet format failed: $($output -join ' ')") | Out-Null
                Add-CheckResult -Results $results -Name 'C# / Unreal build scripts' -Status 'fail' -Detail 'dotnet format reported changes or errors'
            }
        }
        else {
            Add-CheckResult -Results $results -Name 'C# / Unreal build scripts' -Status 'skip' -Detail ("{0} C# file(s) found; dotnet format is optional" -f $csharpFiles.Count)
        }
    }

    $cppFiles = @(Get-LanguageFiles -Repo $repo -Extensions @('.c', '.cc', '.cpp', '.cxx', '.h', '.hh', '.hpp', '.hxx', '.ixx'))
    if ($cppFiles.Count -gt 0) {
        if ((Test-Path -LiteralPath 'compile_commands.json') -and (Test-CommandExists -Name 'clang-tidy')) {
            $sample = @($cppFiles | Where-Object { $_.Extension.ToLowerInvariant() -in @('.c', '.cc', '.cpp', '.cxx', '.ixx') } | Select-Object -First 20)
            foreach ($file in $sample) {
                $output = clang-tidy $file.FullName --quiet 2>&1
                if ($LASTEXITCODE -ne 0) {
                    $rel = Get-RelativePath -Base $repo -PathValue $file.FullName
                    $failures.Add("C++ clang-tidy failed: $rel :: $($output -join ' ')") | Out-Null
                }
            }
            if (@($failures | Where-Object { $_ -like 'C++ clang-tidy failed:*' }).Count -eq 0) {
                Add-CheckResult -Results $results -Name 'C++' -Status 'pass' -Detail ("clang-tidy passed for {0} sampled translation units" -f $sample.Count)
            }
            else {
                Add-CheckResult -Results $results -Name 'C++' -Status 'fail' -Detail 'clang-tidy reported findings'
            }
        }
        elseif ($RequireExternalTools) {
            $failures.Add('C++ lint requires clang-tidy and compile_commands.json.') | Out-Null
            Add-CheckResult -Results $results -Name 'C++' -Status 'fail' -Detail 'required C++ lint inputs missing'
        }
        else {
            Add-CheckResult -Results $results -Name 'C++' -Status 'skip' -Detail ("{0} C/C++ files found; clang-tidy requires compile_commands.json" -f $cppFiles.Count)
        }
    }

    $uprojectFiles = @(Get-LanguageFiles -Repo $repo -Extensions @('.uproject'))
    if ($uprojectFiles.Count -gt 0) {
        $ueCmd = [string]$env:UE_EDITOR_CMD
        if (-not [string]::IsNullOrWhiteSpace($ueCmd) -and (Test-Path -LiteralPath $ueCmd)) {
            foreach ($project in $uprojectFiles) {
                $output = & $ueCmd $project.FullName -run=CompileAllBlueprints -unattended -nop4 -nosplash -log 2>&1
                if ($LASTEXITCODE -ne 0) {
                    $rel = Get-RelativePath -Base $repo -PathValue $project.FullName
                    $failures.Add("Unreal Blueprint compile failed: $rel :: $($output -join ' ')") | Out-Null
                }
            }
            if (@($failures | Where-Object { $_ -like 'Unreal Blueprint compile failed:*' }).Count -eq 0) {
                Add-CheckResult -Results $results -Name 'Unreal Blueprints' -Status 'pass' -Detail 'CompileAllBlueprints passed'
            }
            else {
                Add-CheckResult -Results $results -Name 'Unreal Blueprints' -Status 'fail' -Detail 'CompileAllBlueprints failed'
            }
        }
        elseif ($RequireExternalTools) {
            $failures.Add('Unreal Blueprint lint requires UE_EDITOR_CMD pointing to UnrealEditor-Cmd.exe.') | Out-Null
            Add-CheckResult -Results $results -Name 'Unreal Blueprints' -Status 'fail' -Detail 'UE_EDITOR_CMD missing'
        }
        else {
            Add-CheckResult -Results $results -Name 'Unreal Blueprints' -Status 'skip' -Detail 'set UE_EDITOR_CMD to run CompileAllBlueprints'
        }
    }
}
finally {
    Pop-Location
}

$matrixProfiles = @(Get-ApplicableMatrixProfiles -Repo $repo -Matrix $matrix)
$resultArray = @($results.ToArray())
$failureArray = @($failures.ToArray())
$profileArray = @($matrixProfiles)
$matrixRelativePath = ''
$matrixId = ''
$matrixUpdated = ''
if (-not [string]::IsNullOrWhiteSpace($resolvedMatrixPath)) {
    $matrixRelativePath = Get-RelativePath -Base $repo -PathValue $resolvedMatrixPath
}
if ($null -ne $matrix) {
    $matrixId = [string](Get-JsonProperty -ObjectValue $matrix -Name 'id')
    $matrixUpdated = [string](Get-JsonProperty -ObjectValue $matrix -Name 'updated')
}

Write-Output 'Language lint summary:'
if ($matrixProfiles.Count -gt 0) {
    $appliesCount = @($matrixProfiles | Where-Object { $_.applies }).Count
    Write-Output ("- Matrix: pass ({0}; applicable_profiles={1}/{2})" -f $matrixRelativePath, $appliesCount, $matrixProfiles.Count)
}
foreach ($result in $results) {
    Write-Output ("- {0}: {1} ({2})" -f $result.name, $result.status, $result.detail)
}

$report = [pscustomobject]@{
    schema_version = 1
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    repo_root = $repo.Replace('\', '/')
    matrix_path = $matrixRelativePath
    matrix_id = $matrixId
    matrix_updated = $matrixUpdated
    require_external_tools = [bool]$RequireExternalTools
    enforce_docs_terminology = [bool]$EnforceDocsTerminology
    results = $resultArray
    matrix_profiles = $profileArray
    failures = $failureArray
}

if (-not [string]::IsNullOrWhiteSpace($OutputJson)) {
    $jsonPath = Join-Path $repo $OutputJson
    $jsonParent = Split-Path -Parent $jsonPath
    if (-not [string]::IsNullOrWhiteSpace($jsonParent)) {
        New-Item -ItemType Directory -Force -Path $jsonParent | Out-Null
    }
    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding utf8
    Write-Output ("Language lint JSON report: {0}" -f $jsonPath)
}

if (-not [string]::IsNullOrWhiteSpace($OutputMarkdown)) {
    $markdownPath = Join-Path $repo $OutputMarkdown
    $markdownParent = Split-Path -Parent $markdownPath
    if (-not [string]::IsNullOrWhiteSpace($markdownParent)) {
        New-Item -ItemType Directory -Force -Path $markdownParent | Out-Null
    }
    Write-LanguageLintMarkdown -Report $report | Set-Content -LiteralPath $markdownPath -Encoding utf8
    Write-Output ("Language lint markdown report: {0}" -f $markdownPath)
}

if ($failures.Count -gt 0) {
    Write-Output ''
    Write-Output 'Language lint failures:'
    foreach ($failure in $failures) {
        Write-Output ("- {0}" -f $failure)
    }
    exit 1
}

exit 0

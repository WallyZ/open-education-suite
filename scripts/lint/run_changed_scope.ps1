[CmdletBinding()]
param(
    [string]$RepoRoot = '.',
    [ValidateSet('32k', '64k', 'cloud')]
    [string]$ContextProfile = 'cloud',
    [string]$BaseRef = '',
    [switch]$IncludeUntracked,
    [switch]$ForceExchangeSmoke,
    [switch]$ListOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RepoRootPath {
    param([string]$Start)

    $resolved = (Resolve-Path $Start).Path
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

function Get-ChangedFiles {
    param(
        [string]$Repo,
        [string]$BaseRef,
        [bool]$IncludeUntracked
    )

    $collected = New-Object "System.Collections.Generic.List[string]"

    $cmdSets = @(
        @("diff", "--name-only"),
        @("diff", "--cached", "--name-only")
    )

    foreach ($cmd in $cmdSets) {
        $rows = @(git -C $Repo @cmd 2>$null)
        foreach ($row in $rows) {
            $norm = ($row -replace "\\", "/").Trim()
            if ($norm) {
                $collected.Add($norm) | Out-Null
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($BaseRef)) {
        git -C $Repo rev-parse --verify $BaseRef 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $rows = @(git -C $Repo diff --name-only "$BaseRef...HEAD" 2>$null)
            foreach ($row in $rows) {
                $norm = ($row -replace "\\", "/").Trim()
                if ($norm) {
                    $collected.Add($norm) | Out-Null
                }
            }
        }
    }

    if ($IncludeUntracked) {
        $rows = @(git -C $Repo ls-files --others --exclude-standard 2>$null)
        foreach ($row in $rows) {
            $norm = ($row -replace "\\", "/").Trim()
            if ($norm) {
                $collected.Add($norm) | Out-Null
            }
        }
    }

    $out = @(
        $collected |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )
    return $out
}

function Test-AnyChanged {
    param(
        [string[]]$Files,
        [string[]]$Patterns
    )

    foreach ($f in $Files) {
        foreach ($pat in $Patterns) {
            if ($f -imatch $pat) {
                return $true
            }
        }
    }
    return $false
}

function Invoke-Check {
    param(
        [string]$Name,
        [scriptblock]$Condition,
        [scriptblock]$Command
    )

    if (-not (& $Condition)) {
        Write-Host "SKIP: $Name"
        return [pscustomobject]@{ Name = $Name; Success = $true; Skipped = $true }
    }

    Write-Host "RUN : $Name"
    & $Command | Out-Host
    $ok = ($LASTEXITCODE -eq 0)

    if ($ok) {
        Write-Host "PASS: $Name"
    }
    else {
        Write-Host "FAIL: $Name"
    }

    return [pscustomobject]@{ Name = $Name; Success = $ok; Skipped = $false }
}

$repo = Get-RepoRootPath -Start $RepoRoot
$changed = @(Get-ChangedFiles -Repo $repo -BaseRef $BaseRef -IncludeUntracked:$IncludeUntracked)

$baseRefLabel = if ($BaseRef) { $BaseRef } else { '(none)' }
Write-Output ("run_changed_scope: repo={0} profile={1} base_ref={2} include_untracked={3} changed={4}" -f $repo, $ContextProfile, $baseRefLabel, [bool]$IncludeUntracked, $changed.Count)

if ($changed.Count -eq 0) {
    Write-Output 'No changed files detected. Nothing to run.'
    exit 0
}

Write-Output 'Changed files:'
foreach ($f in $changed) {
    Write-Output ("- {0}" -f $f)
}

$checks = @(
    [pscustomobject]@{
        Name = 'Markdown path checks'
        Patterns = @('\.md$')
        Exists = { Test-Path 'scripts/lifecycle/check_markdown_paths.py' }
        Command = {
            $mdFiles = @($changed | Where-Object {
                    $_ -imatch '\.md$' -and
                    $_ -inotmatch '^docs/todo/' -and
                    $_ -inotmatch '^docs/templates/' -and
                    $_ -inotmatch '^docs/wavekit/_archive/' -and
                    $_ -inotmatch '^examples/golden-[^/]+/'
                })
            if ($mdFiles.Count -eq 0) {
                Write-Output 'No changed Markdown files for markdown path checks.'
                return
            }
            python scripts/lifecycle/check_markdown_paths.py --repo-root . --files @mdFiles
        }
    },
    [pscustomobject]@{
        Name = 'TODO format checks'
        Patterns = @('^docs/todo/.*\.md$', '^docs/TODO\.md$', '^scripts/todo_audit', '^scripts/wavekit/todo_preflight_fix\.py$')
        Exists = { Test-Path 'scripts/lifecycle/check_todo_format.py' }
        Command = {
            python scripts/lifecycle/check_todo_format.py --repo-root . --todo-root docs/todo --min-severity info --fail-on error
            if ((Test-Path 'scripts/wavekit/todo_preflight_fix.py') -and (Test-Path 'docs/todo')) {
                python scripts/wavekit/todo_preflight_fix.py --todo-root docs/todo --check
            }
        }
    },
    [pscustomobject]@{
        Name = 'TODO ready-queue checks'
        Patterns = @('^docs/todo/.*\.md$', '^docs/TODO\.md$', '^repo-standards/todo/', '^scripts/todo_audit', '^scripts/lifecycle/check_todo_ready_queue\.py$', '^docs/TODO_AUDIT\.md$', '^docs/TODO_PROCESS\.md$')
        Exists = { Test-Path 'scripts/lifecycle/check_todo_ready_queue.py' }
        Command = {
            python scripts/lifecycle/check_todo_ready_queue.py --repo-root . --todo-root docs/todo --min-severity info --fail-on error --report -
        }
    },
    [pscustomobject]@{
        Name = 'Engineering Lesson Ledger checks'
        Patterns = @(
            '^repo-standards/lessons/',
            '^scripts/lessons/',
            '^scripts/fleet/collect_engineering_lessons\.py$',
            '^scripts/(codex-verify|memory/record_pitfall)\.(ps1|py)$',
            '^docs/(ENGINEERING_LESSON_LEDGER|LESSON_PROMOTION_POLICY)\.md$',
            '^docs/lessons/',
            '^\.repo-kit/lessons\.json$',
            '^scripts/bootstrap/install_repo_standards\.ps1$',
            '^repo-standards/(pack_versions|exchange/default_items)\.json$',
            '^examples/golden-repo/(\.repo-kit/lessons\.json|docs/ENGINEERING_LESSON_LEDGER\.md|repo-standards/lessons/|scripts/lessons/)'
        )
        Exists = { Test-Path 'scripts/lessons/lesson_ledger.py' }
        Command = {
            $lessonBaseRef = if ([string]::IsNullOrWhiteSpace($BaseRef)) { 'HEAD' } else { $BaseRef }
            python scripts/lessons/lesson_ledger.py verify-pack --repo-root . --base-ref $lessonBaseRef
            if ($LASTEXITCODE -ne 0) {
                return
            }
            python scripts/lessons/test_lesson_runtime.py --repo-root .
            if ($LASTEXITCODE -ne 0) {
                return
            }
            python scripts/fleet/collect_engineering_lessons.py --repo-kit-root . --self-test
        }
    },
    [pscustomobject]@{
        Name = 'Development Excellence pack checks'
        Patterns = @(
            '^repo-standards/(development-excellence|delivery-intelligence|change-contract|component-catalog)/',
            '^scripts/(delivery|change|architecture)/',
            '^docs/(REPOSITORY_DEVELOPMENT_EXCELLENCE|DELIVERY_INTELLIGENCE|CHANGE_CONTRACT|COMPONENT_CATALOG)\.md$',
            '^docs/todo/12_repository_development_excellence\.md$',
            '^\.repo-kit/(development_excellence|delivery_intelligence|change_contract|component_catalog)\.json$',
            '^scripts/(bootstrap/install_repo_standards|lifecycle/check_golden_repo|lint/run_all)\.(ps1|py)$',
            '^repo-standards/(pack_versions|exchange/default_items)\.json$',
            '^examples/golden-repo/(\.repo-kit/(development_excellence|delivery_intelligence|change_contract|component_catalog)\.json|docs/(REPOSITORY_DEVELOPMENT_EXCELLENCE|DELIVERY_INTELLIGENCE|CHANGE_CONTRACT|COMPONENT_CATALOG)\.md|repo-standards/(development-excellence|delivery-intelligence|change-contract|component-catalog)/|scripts/(delivery|change|architecture)/)'
        )
        Exists = { Test-Path 'scripts/delivery/check_delivery_intelligence_pack.py' }
        Command = {
            python -B scripts/delivery/check_delivery_intelligence_pack.py --repo-root .
            if ($LASTEXITCODE -ne 0) {
                return
            }
            python -B scripts/delivery/test_delivery_intelligence.py --repo-root .
            if ($LASTEXITCODE -ne 0) {
                return
            }
            python -B scripts/change/check_change_contract_pack.py --repo-root .
            if ($LASTEXITCODE -ne 0) {
                return
            }
            python -B scripts/change/test_change_contract.py --repo-root .
            if ($LASTEXITCODE -ne 0) {
                return
            }
            if (Test-Path 'scripts/architecture/test_component_catalog.py') {
                python -B scripts/architecture/test_component_catalog.py
            }
        }
    },
    [pscustomobject]@{
        Name = 'Repo consistency checks'
        Patterns = @('^docs/', '^scripts/', '^repo-standards/', '^\.github/workflows/', '^tools/tools_manifest\.json$')
        Exists = { Test-Path 'scripts/lifecycle/check_repo_consistency.py' }
        Command = {
            python scripts/lifecycle/check_repo_consistency.py --repo-root .
        }
    },
    [pscustomobject]@{
        Name = 'Codex skill pack checks'
        Patterns = @(
            '^repo-standards/codex-skills/',
            '^\.agents/skills/benchmark-gauntlet/',
            '^scripts/lifecycle/check_codex_skill_pack\.py$',
            '^scripts/bootstrap/install_repo_standards\.ps1$',
            '^scripts/lint/run_changed_scope\.ps1$',
            '^repo-standards/pack_versions\.json$',
            '^repo-standards/exchange/default_items\.json$',
            '^repo-standards/agents/agent_instruction_compatibility\.json$',
            '^docs/AGENT_INSTRUCTIONS_COMPATIBILITY\.md$',
            '^docs/changelogs/codex-skills\.md$'
        )
        Exists = { Test-Path 'scripts/lifecycle/check_codex_skill_pack.py' }
        Command = {
            python scripts/lifecycle/check_codex_skill_pack.py --repo-root .
        }
    },
    [pscustomobject]@{
        Name = 'External source ledger checks'
        Patterns = @('^docs/EXTERNAL_SOLUTION_SOURCES\.md$', '^scripts/lifecycle/check_external_solution_sources\.py$', '^docs/todo/.*\.md$')
        Exists = { Test-Path 'scripts/lifecycle/check_external_solution_sources.py' }
        Command = {
            python scripts/lifecycle/check_external_solution_sources.py --repo-root .
        }
    },
    [pscustomobject]@{
        Name = 'Language lint checks'
        Patterns = @('\.(md|py|ps1|psm1|psd1|jsonc?|ya?ml|js|jsx|ts|tsx|c|cc|cpp|cxx|h|hh|hpp|hxx|ixx|cs|uproject|uplugin)$', '^scripts/lint/run_language_lint\.ps1$', '^docs/LANGUAGE_LINTING\.md$', '^repo-standards/lint/(language_lint_matrix|cspell)\.json$', '^repo-standards/lint/docs_terminology_allowlist\.txt$', '^docs/COMMON_PITFALLS\.md$', '^scripts/memory/record_pitfall\.ps1$')
        Exists = { Test-Path 'scripts/lint/run_language_lint.ps1' }
        Command = {
            & ./scripts/lint/run_language_lint.ps1 -RepoRoot . -ChangedFiles $changed
        }
    },
    [pscustomobject]@{
        Name = 'Audio review packet contract checks'
        Patterns = @('^repo-standards/audio-review/', '^docs/audio-review/', '^scripts/lifecycle/check_audio_review_contracts\.py$', '^repo-standards/exchange/default_items\.json$')
        Exists = { Test-Path 'scripts/lifecycle/check_audio_review_contracts.py' }
        Command = {
            python scripts/lifecycle/check_audio_review_contracts.py --repo-root .
        }
    },
    [pscustomobject]@{
        Name = 'Security supply-chain pack checks'
        Patterns = @('^docs/SECURITY_SUPPLY_CHAIN_PACK\.md$', '^scripts/security/check_supply_chain_pack\.ps1$', '^scripts/doctor/(score_repo|detect_repo_type)\.ps1$', '^docs/(DEPENDENCY_UPDATE_POLICY|DEPENDENCY_DASHBOARD|WORKFLOW_POLICY|BRANCH_PROTECTION_POLICY|SECRETS_BACKUP_POLICY|SECRETS_RESTORE_CHECKLIST)\.md$', '^\.github/workflows/.*\.ya?ml$', '^repo-standards/security/security_scanner_profiles\.json$', '^repo-standards/exchange/default_items\.json$', '^docs/todo/(09_repo_maturity_upgrade_pipeline|10_external_benchmarking_and_todo_system)\.md$')
        Exists = { Test-Path 'scripts/security/check_supply_chain_pack.ps1' }
        Command = {
            $securityJson = Join-Path $env:TEMP 'security_supply_chain_pack.json'
            $securityMarkdown = Join-Path $env:TEMP 'security_supply_chain_pack.md'
            & ./scripts/security/check_supply_chain_pack.ps1 -RepoRoot . -OutputJson $securityJson -OutputMarkdown $securityMarkdown -FailOnError
            $security = Get-Content -LiteralPath $securityJson -Raw | ConvertFrom-Json
            if ($security.summary.errors -ne 0) {
                throw "Security supply-chain pack smoke expected zero errors, got $($security.summary.errors)."
            }
            if ($null -eq ($security.checks | Where-Object { [string]$_.id -eq 'sbom-policy' } | Select-Object -First 1)) {
                throw 'Security supply-chain pack smoke missing sbom-policy check.'
            }
            if ($null -eq ($security.checks | Where-Object { [string]$_.id -eq 'workflow-action-floating-refs' } | Select-Object -First 1)) {
                throw 'Security supply-chain pack smoke missing workflow action ref check.'
            }
            if ($null -eq ($security.checks | Where-Object { [string]$_.id -eq 'optional-scanner-profiles' } | Select-Object -First 1)) {
                throw 'Security supply-chain pack smoke missing optional scanner profile check.'
            }
            if ($security.summary.scanner_profiles -lt 4) {
                throw "Security supply-chain pack smoke expected at least 4 scanner profiles, got $($security.summary.scanner_profiles)."
            }
            if (-not (Test-Path -LiteralPath $securityMarkdown -PathType Leaf)) {
                throw "Security supply-chain pack smoke missing markdown report: $securityMarkdown"
            }
        }
    },
    [pscustomobject]@{
        Name = 'Testing strategy pack checks'
        Patterns = @('^docs/TESTING_STRATEGY_PACK\.md$', '^scripts/testing/check_testing_strategy_pack\.ps1$', '^templates/testing/', '^scripts/doctor/(score_repo|detect_repo_type)\.ps1$', '^docs/CLINE_TESTING_GUIDE\.md$', '^repo-standards/exchange/default_items\.json$', '^docs/todo/09_repo_maturity_upgrade_pipeline\.md$')
        Exists = { Test-Path 'scripts/testing/check_testing_strategy_pack.ps1' }
        Command = {
            $testingJson = Join-Path $env:TEMP 'testing_strategy_pack.json'
            $testingMarkdown = Join-Path $env:TEMP 'testing_strategy_pack.md'
            & ./scripts/testing/check_testing_strategy_pack.ps1 -RepoRoot . -OutputJson $testingJson -OutputMarkdown $testingMarkdown -FailOnError
            $testing = Get-Content -LiteralPath $testingJson -Raw | ConvertFrom-Json
            if ($testing.summary.errors -ne 0) {
                throw "Testing strategy pack smoke expected zero errors, got $($testing.summary.errors)."
            }
            if ($null -eq ($testing.checks | Where-Object { [string]$_.id -eq 'testing-fixture-templates' } | Select-Object -First 1)) {
                throw 'Testing strategy pack smoke missing fixture template check.'
            }
            if ($null -eq ($testing.checks | Where-Object { [string]$_.id -eq 'canonical-verifier' } | Select-Object -First 1)) {
                throw 'Testing strategy pack smoke missing canonical verifier check.'
            }
            if (-not (Test-Path -LiteralPath $testingMarkdown -PathType Leaf)) {
                throw "Testing strategy pack smoke missing markdown report: $testingMarkdown"
            }
        }
    },
    [pscustomobject]@{
        Name = 'Private AI repo pack checks'
        Patterns = @('^docs/PRIVATE_AI_REPO_PACK\.md$', '^scripts/private_ai/check_private_ai_repo_pack\.ps1$', '^repo-standards/private-ai/', '^examples/golden-repo/(docs/PRIVATE_AI_REPO_PACK\.md|repo-standards/private-ai/private_ai_repo_pack\.json)$', '^scripts/lifecycle/check_golden_repo\.py$', '^docs/SOLUTION_COLLECTION\.md$', '^docs/REUSABLE_PACK_EXTRACTION_ROADMAP\.md$')
        Exists = { Test-Path 'scripts/private_ai/check_private_ai_repo_pack.ps1' }
        Command = {
            $privateAiJson = Join-Path $env:TEMP 'private_ai_repo_pack.json'
            $privateAiMarkdown = Join-Path $env:TEMP 'private_ai_repo_pack.md'
            & ./scripts/private_ai/check_private_ai_repo_pack.ps1 -RepoRoot . -OutputJson $privateAiJson -OutputMarkdown $privateAiMarkdown -FailOnError
            $privateAi = Get-Content -LiteralPath $privateAiJson -Raw | ConvertFrom-Json
            if ($privateAi.summary.errors -ne 0) {
                throw "Private AI repo pack smoke expected zero errors, got $($privateAi.summary.errors)."
            }
            if ($null -eq ($privateAi.checks | Where-Object { [string]$_.id -eq 'privacy-boundary' } | Select-Object -First 1)) {
                throw 'Private AI repo pack smoke missing privacy-boundary check.'
            }
            if ($null -eq ($privateAi.checks | Where-Object { [string]$_.id -eq 'owner-gated-modules' } | Select-Object -First 1)) {
                throw 'Private AI repo pack smoke missing owner-gated module check.'
            }
            if ($null -eq ($privateAi.checks | Where-Object { [string]$_.id -eq 'golden-module-sync' } | Select-Object -First 1)) {
                throw 'Private AI repo pack smoke missing golden module sync check.'
            }
            if (-not (Test-Path -LiteralPath $privateAiMarkdown -PathType Leaf)) {
                throw "Private AI repo pack smoke missing markdown report: $privateAiMarkdown"
            }
        }
    },
    [pscustomobject]@{
        Name = 'Unreal C++ pack checks'
        Patterns = @('^docs/UNREAL_CPP_REPO_PACK\.md$', '^scripts/doctor/(check_unreal_cpp_pack|score_repo|detect_repo_type)\.ps1$', '^docs/templates/unreal/', '^docs/(CLINE_UNREAL_GUIDE|UNREAL_LOG_INGESTION_CONTRACT|LANGUAGE_LINTING)\.md$', '^docs/logging/unreal_ingestion_contract\.json$', '^repo-standards/exchange/default_items\.json$', '^docs/todo/09_repo_maturity_upgrade_pipeline\.md$')
        Exists = { Test-Path 'scripts/doctor/check_unreal_cpp_pack.ps1' }
        Command = {
            $unrealJson = Join-Path $env:TEMP 'unreal_cpp_pack.json'
            $unrealMarkdown = Join-Path $env:TEMP 'unreal_cpp_pack.md'
            & ./scripts/doctor/check_unreal_cpp_pack.ps1 -RepoRoot . -OutputJson $unrealJson -OutputMarkdown $unrealMarkdown -FailOnError
            $unreal = Get-Content -LiteralPath $unrealJson -Raw | ConvertFrom-Json
            if ($unreal.summary.errors -ne 0) {
                throw "Unreal C++ pack smoke expected zero errors, got $($unreal.summary.errors)."
            }
            if ($null -eq ($unreal.checks | Where-Object { [string]$_.id -eq 'unreal-command-templates' } | Select-Object -First 1)) {
                throw 'Unreal C++ pack smoke missing command template check.'
            }
            if ($null -eq ($unreal.checks | Where-Object { [string]$_.id -eq 'unreal-log-contract' } | Select-Object -First 1)) {
                throw 'Unreal C++ pack smoke missing Unreal log contract check.'
            }
            if (-not (Test-Path -LiteralPath $unrealMarkdown -PathType Leaf)) {
                throw "Unreal C++ pack smoke missing markdown report: $unrealMarkdown"
            }
        }
    },
    [pscustomobject]@{
        Name = 'Logging contract checks'
        Patterns = @('^docs/CLINE_LOGGING_GUIDE\.md$', '^docs/CLINE_UNREAL_GUIDE\.md$', '^docs/UNREAL_LOG_INGESTION_CONTRACT\.md$', '^docs/templates/LOGGING_template\.md$', '^docs/templates/logging/', '^scripts/lifecycle/check_logging_contract\.py$', '^scripts/logging/')
        Exists = { Test-Path 'scripts/lifecycle/check_logging_contract.py' }
        Command = {
            python scripts/lifecycle/check_logging_contract.py --repo-root .
        }
    },
    [pscustomobject]@{
        Name = 'Logging adapter smoke checks'
        Patterns = @('^scripts/logging/', '^docs/logging/unreal_ingestion_contract\.json$', '^docs/templates/logging/')
        Exists = { (Test-Path 'scripts/logging/test_python_logging_adapter_smoke.py') -and (Test-Path 'scripts/logging/Test-RepoKitLoggingAdapterSmoke.ps1') -and (Test-Path 'scripts/logging/test_unreal_log_ingest_regression.py') -and (Test-Path 'scripts/logging/fixtures/unreal_ingest_cases.json') }
        Command = {
            python scripts/logging/test_python_logging_adapter_smoke.py
            & ./scripts/logging/Test-RepoKitLoggingAdapterSmoke.ps1
            python scripts/logging/test_unreal_log_ingest_regression.py
        }
    },
    [pscustomobject]@{
        Name = 'Memory-bank quality checks'
        Patterns = @('^memory-bank/', '^scripts/memory/', '^docs/templates/memory-bank/', '^docs/MEMORY_BANK_QUICKSTART\.md$', '^docs/CLINE_MEMORY_BANK_STRATEGY\.md$')
        Exists = { Test-Path 'scripts/lifecycle/check_memory_bank.py' }
        Command = {
            python scripts/lifecycle/check_memory_bank.py --repo-root . --profile $ContextProfile --max-handoff-tokens 2000
        }
    },
    [pscustomobject]@{
        Name = 'Repo maturity scorecard smoke checks'
        Patterns = @('^scripts/doctor/(score_repo|detect_repo_type)\.ps1$', '^scripts/doctor/(test_score_repo|validate_json_schema)\.py$', '^repo-standards/development-excellence/(operational_health_evidence|repo_maturity_report)\.schema\.json$', '^docs/REPO_MATURITY_SCORECARD\.md$', '^docs/REPO_TYPE_PACK_RECOMMENDER\.md$', '^docs/todo/(09_repo_maturity_upgrade_pipeline|12_repository_development_excellence)\.md$')
        Exists = { Test-Path 'scripts/doctor/score_repo.ps1' }
        Command = {
            if (Test-Path 'scripts/doctor/detect_repo_type.ps1') {
                $typeJson = Join-Path $env:TEMP 'repo_type_pack_recommendations.json'
                $typeMarkdown = Join-Path $env:TEMP 'repo_type_pack_recommendations.md'
                & ./scripts/doctor/detect_repo_type.ps1 -RepoRoot . -OutputJson $typeJson -OutputMarkdown $typeMarkdown
            }
            $scoreJson = Join-Path $env:TEMP 'repo_maturity_scorecard.json'
            $scoreMarkdown = Join-Path $env:TEMP 'repo_maturity_scorecard.md'
            & ./scripts/doctor/score_repo.ps1 -RepoRoot . -OutputJson $scoreJson -OutputMarkdown $scoreMarkdown -FailBelow 1
            python scripts/doctor/test_score_repo.py --repo-root .
        }
    },
    [pscustomobject]@{
        Name = 'Sensitive-change workflow policy checks'
        Patterns = @('^scripts/doctor/check_workflow_policy\.py$', '^\.repo-kit/workflow_policy\.standard\.json$', '^\.github/(CODEOWNERS|workflows/ci\.yml)$', '^repo-standards/development-excellence/(workflow_policy|hosted_workflow_state)\.schema\.json$', '^docs/BRANCH_PROTECTION_POLICY\.md$', '^docs/todo/12_repository_development_excellence\.md$')
        Exists = { Test-Path 'scripts/doctor/check_workflow_policy.py' }
        Command = {
            python scripts/doctor/check_workflow_policy.py --repo-root . --self-test
        }
    },
    [pscustomobject]@{
        Name = 'Repo upgrade planner smoke checks'
        Patterns = @('^scripts/rollout/plan_repo_upgrade\.ps1$', '^scripts/exchange/Exchange\.Common\.ps1$', '^docs/REPO_UPGRADE_PLANNER\.md$', '^archive/local-reports/repo_upgrade_plan\.schema\.json$', '^repo-standards/exchange/default_items\.json$', '^docs/todo/09_repo_maturity_upgrade_pipeline\.md$')
        Exists = { Test-Path 'scripts/rollout/plan_repo_upgrade.ps1' }
        Command = {
            $planJson = Join-Path $env:TEMP 'repo_upgrade_plan.json'
            $planMarkdown = Join-Path $env:TEMP 'repo_upgrade_plan.md'
            & ./scripts/rollout/plan_repo_upgrade.ps1 -TargetRepo . -RepoKitRoot . -OutputJson $planJson -OutputMarkdown $planMarkdown
            $plan = Get-Content -LiteralPath $planJson -Raw | ConvertFrom-Json
            if ($plan.mode -ne 'plan') {
                throw "Repo upgrade planner smoke expected plan mode, got $($plan.mode)."
            }
            if (-not $plan.approval_gate.required) {
                throw 'Repo upgrade planner smoke expected approval gate.'
            }
            if ([string]$plan.approval_gate.required_token -ne 'APPROVED') {
                throw 'Repo upgrade planner smoke expected ApprovalToken APPROVED guidance.'
            }
            if ($plan.summary.total -lt 1) {
                throw 'Repo upgrade planner smoke expected at least one action row.'
            }
            if (-not (Test-Path -LiteralPath $planMarkdown -PathType Leaf)) {
                throw "Repo upgrade planner smoke missing markdown report: $planMarkdown"
            }
        }
    },
    [pscustomobject]@{
        Name = 'Upgrade task-pack generator smoke checks'
        Patterns = @('^scripts/rollout/(plan_repo_upgrade|write_task_pack)\.ps1$', '^docs/(REPO_UPGRADE_PLANNER|TASK_PACK_GENERATOR)\.md$', '^repo-standards/exchange/default_items\.json$', '^docs/todo/09_repo_maturity_upgrade_pipeline\.md$')
        Exists = { (Test-Path 'scripts/rollout/plan_repo_upgrade.ps1') -and (Test-Path 'scripts/rollout/write_task_pack.ps1') }
        Command = {
            $planJson = Join-Path $env:TEMP 'repo_upgrade_plan_for_task_pack.json'
            $planMarkdown = Join-Path $env:TEMP 'repo_upgrade_plan_for_task_pack.md'
            $taskPack = Join-Path $env:TEMP 'repo_upgrade_task_pack.md'
            $taskPackReport = Join-Path $env:TEMP 'repo_upgrade_task_pack_report.json'
            & ./scripts/rollout/plan_repo_upgrade.ps1 -TargetRepo . -RepoKitRoot . -OutputJson $planJson -OutputMarkdown $planMarkdown
            & ./scripts/rollout/write_task_pack.ps1 -UpgradePlanPath $planJson -RepoRoot . -OutputPath $taskPack -OutputJson $taskPackReport -ContextProfile $ContextProfile -MaxItems 3
            $taskPackText = Get-Content -LiteralPath $taskPack -Raw
            foreach ($required in @('## Scope', '## Verification', '## Risks', '## Acceptance')) {
                if ($taskPackText -notmatch [regex]::Escape($required)) {
                    throw "Task-pack smoke missing required section: $required"
                }
            }
            $taskPackJson = Get-Content -LiteralPath $taskPackReport -Raw | ConvertFrom-Json
            if ($taskPackJson.selected_count -lt 1) {
                throw 'Task-pack smoke expected at least one selected action.'
            }
            foreach ($action in @($taskPackJson.selected_actions)) {
                if ([string]$action.action -eq 'do_not_touch') {
                    throw 'Task-pack smoke should not select do_not_touch actions by default.'
                }
            }

            $todoFixtureRoot = Join-Path $env:TEMP 'todo_task_pack_fixture'
            New-Item -ItemType Directory -Force -Path $todoFixtureRoot | Out-Null
            $todoFixture = Join-Path $todoFixtureRoot 'TODO.md'
            Set-Content -LiteralPath $todoFixture -Encoding utf8 -Value @'
# TODO Fixture

- [ ] Smoke TODO ready task-pack bridge [PH2] <!-- ms:evidence id=RK_SMOKE_TASK_PACK_001 path=scripts/rollout/write_task_pack.ps1 symbols=Write-TodoTaskPack strings="QA Live Automation,Source TODO" --> <!-- ms:meta priority=p1 owner=@repo-kit stale-days=14 automation-level=assisted human-checkpoint=review rollout-scope=single-repo validation-profile=cloud safe-autofix=review updated=2026-06-03 -->
  - Deliverables: generated task pack from a ready-queue item.
  - Files: `scripts/rollout/write_task_pack.ps1`, `docs/TASK_PACK_GENERATOR.md`.
  - Verification: `pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\codex-verify.ps1 -RepoRoot . -ContextProfile cloud -Mode changed -IncludeUntracked`.
  - QA Live automation: Not required for this fixture; generated packs for UI/game/Unreal/runtime TODOs carry the repo-specific QA Live dry-run/capability-manifest instruction.
  - Drift guard: task pack includes source TODO metadata and relevant file list.
  - Downstream rollout: downstream agents can start from the generated pack without rescanning docs.
  - Acceptance:
    - Generated task pack includes Source TODO, QA Live Automation, Drift Guard, Downstream Rollout, and Acceptance sections.
'@
            $todoTaskPack = Join-Path $env:TEMP 'todo_ready_queue_task_pack.md'
            $todoTaskPackReport = Join-Path $env:TEMP 'todo_ready_queue_task_pack_report.json'
            & ./scripts/rollout/write_task_pack.ps1 -RepoRoot . -TodoRoot $todoFixtureRoot -TodoId RK_SMOKE_TASK_PACK_001 -OutputPath $todoTaskPack -OutputJson $todoTaskPackReport -ContextProfile $ContextProfile -Force
            $todoTaskPackText = Get-Content -LiteralPath $todoTaskPack -Raw
            foreach ($required in @('## Source TODO', '## QA Live Automation', '## Drift Guard', '## Downstream Rollout', '## Acceptance')) {
                if ($todoTaskPackText -notmatch [regex]::Escape($required)) {
                    throw "TODO task-pack smoke missing required section: $required"
                }
            }
            $todoTaskPackJson = Get-Content -LiteralPath $todoTaskPackReport -Raw | ConvertFrom-Json
            if ([string]$todoTaskPackJson.mode -ne 'todo_queue') {
                throw "TODO task-pack smoke expected mode=todo_queue, got: $($todoTaskPackJson.mode)"
            }
            if ([string]$todoTaskPackJson.selected_todo.todo_id -ne 'RK_SMOKE_TASK_PACK_001') {
                throw "TODO task-pack smoke selected unexpected TODO id: $($todoTaskPackJson.selected_todo.todo_id)"
            }
        }
    },
    [pscustomobject]@{
        Name = 'Downstream upgrade dashboard smoke checks'
        Patterns = @('^scripts/rollout/(build_upgrade_dashboard|plan_repo_upgrade)\.ps1$', '^scripts/doctor/(score_repo|detect_repo_type)\.ps1$', '^docs/DOWNSTREAM_UPGRADE_DASHBOARD\.md$', '^archive/local-reports/downstream_upgrade_dashboard_report\.schema\.json$', '^repo-standards/exchange/default_items\.json$', '^docs/todo/09_repo_maturity_upgrade_pipeline\.md$')
        Exists = { (Test-Path 'scripts/rollout/build_upgrade_dashboard.ps1') -and (Test-Path 'archive/local-reports/downstream_upgrade_dashboard_report.schema.json') }
        Command = {
            $dashboardJson = Join-Path $env:TEMP 'downstream_upgrade_dashboard.json'
            $dashboardMarkdown = Join-Path $env:TEMP 'downstream_upgrade_dashboard.md'
            $dashboardSchema = Get-Content -LiteralPath archive/local-reports/downstream_upgrade_dashboard_report.schema.json -Raw | ConvertFrom-Json
            if ($null -eq $dashboardSchema) {
                throw 'Downstream upgrade dashboard schema did not parse.'
            }
            & ./scripts/rollout/build_upgrade_dashboard.ps1 -RepoRoot . -RepoKitRoot . -OutputJson $dashboardJson -OutputMarkdown $dashboardMarkdown
            $dashboard = Get-Content -LiteralPath $dashboardJson -Raw | ConvertFrom-Json
            if ($dashboard.summary.repo_count -lt 1) {
                throw 'Downstream upgrade dashboard smoke expected at least one repo row.'
            }
            if (@($dashboard.repos).Count -lt 1) {
                throw 'Downstream upgrade dashboard smoke expected repo details.'
            }
            if ($dashboard.repos[0].priority_order -lt 1) {
                throw 'Downstream upgrade dashboard smoke expected priority_order >= 1.'
            }
            if ($null -eq $dashboard.repos[0].missing_packs) {
                throw 'Downstream upgrade dashboard smoke expected missing_packs property.'
            }
            if (-not (Test-Path -LiteralPath $dashboardMarkdown -PathType Leaf)) {
                throw "Downstream upgrade dashboard smoke missing markdown report: $dashboardMarkdown"
            }
        }
    },
    [pscustomobject]@{
        Name = 'Solution CLI smoke checks'
        Patterns = @('^scripts/solutions/search_solutions\.ps1$', '^docs/(SOLUTION_CLI|SOLUTION_COLLECTION|SOLUTION_DEPOT)\.md$', '^docs/solutions/', '^memory-bank/solutionHarvest\.md$', '^archive/local-reports/solution_cli_report\.schema\.json$', '^repo-standards/exchange/default_items\.json$', '^docs/todo/09_repo_maturity_upgrade_pipeline\.md$')
        Exists = { Test-Path 'scripts/solutions/search_solutions.ps1' }
        Command = {
            $solutionSearchJson = Join-Path $env:TEMP 'solution_cli_search.json'
            $solutionSearchMarkdown = Join-Path $env:TEMP 'solution_cli_search.md'
            $solutionPlanJson = Join-Path $env:TEMP 'solution_cli_plan.json'
            $solutionPlanMarkdown = Join-Path $env:TEMP 'solution_cli_plan.md'
            $solutionPromoteJson = Join-Path $env:TEMP 'solution_cli_promote.json'
            & ./scripts/solutions/search_solutions.ps1 -RepoRoot . -RepoKitRoot . -Query 'task-pack' -OutputJson $solutionSearchJson -OutputMarkdown $solutionSearchMarkdown
            $solutionSearch = Get-Content -LiteralPath $solutionSearchJson -Raw | ConvertFrom-Json
            if ($solutionSearch.summary.results -lt 1) {
                throw 'Solution CLI smoke expected at least one search result.'
            }
            if (-not (Test-Path -LiteralPath $solutionSearchMarkdown -PathType Leaf)) {
                throw "Solution CLI smoke missing markdown search report: $solutionSearchMarkdown"
            }

            & ./scripts/solutions/search_solutions.ps1 -RepoRoot . -RepoKitRoot . -Mode plan -Query 'memory bootstrap' -OutputJson $solutionPlanJson -OutputMarkdown $solutionPlanMarkdown
            $solutionPlan = Get-Content -LiteralPath $solutionPlanJson -Raw | ConvertFrom-Json
            if ($solutionPlan.approval_gate.required) {
                throw 'Solution CLI plan mode should not require approval.'
            }
            if ($solutionPlan.summary.planned_items -lt 1) {
                throw 'Solution CLI smoke expected at least one planned item.'
            }
            if (-not (Test-Path -LiteralPath $solutionPlanMarkdown -PathType Leaf)) {
                throw "Solution CLI smoke missing markdown plan report: $solutionPlanMarkdown"
            }

            & ./scripts/solutions/search_solutions.ps1 -RepoRoot . -RepoKitRoot . -Mode promote -Query 'repo-kit pull review' -OutputJson $solutionPromoteJson
            $solutionPromote = Get-Content -LiteralPath $solutionPromoteJson -Raw | ConvertFrom-Json
            if ([string]$solutionPromote.promotion.status -ne 'planned') {
                throw "Solution CLI promote smoke expected planned status, got $($solutionPromote.promotion.status)."
            }
            if ($solutionPromote.summary.promoted_records -ne 0) {
                throw 'Solution CLI promote smoke should not write records without -Execute.'
            }
        }
    },
    [pscustomobject]@{
        Name = 'Repo-kit exchange smoke checks'
        Patterns = @('^scripts/exchange/', '^scripts/rollout/plan_repo_upgrade\.ps1$', '^repo-standards/exchange/', '^docs/CROSS_REPO_EXCHANGE\.md$', '^docs/templates/repo-kit/exchange\.json$')
        Exists = { Test-Path 'scripts/exchange/check_due.ps1' }
        Command = {
            & ./scripts/exchange/check_due.ps1 -RepoRoot . -RepoKitRoot .
            & ./scripts/exchange/watch_due.ps1 -RepoRoot . -RepoKitRoot . -Json
            $exchangeDashboardJson = Join-Path $env:TEMP 'exchange_dashboard_report.json'
            $exchangeDashboardMarkdown = Join-Path $env:TEMP 'exchange_dashboard_report.md'
            & ./scripts/exchange/build_dashboard.ps1 -RepoRoot . -RepoKitRoot . -OutputJson $exchangeDashboardJson -OutputMarkdown $exchangeDashboardMarkdown
            & ./scripts/exchange/catalog_repo.ps1 -RepoRoot . -NoWrite
            $exchangeProposalPath = Join-Path $env:TEMP 'exchange_import_proposal.json'
            $exchangeProposalMarkdown = Join-Path $env:TEMP 'exchange_import_proposal.md'
            $exchangeApplyReport = Join-Path $env:TEMP 'exchange_apply_report.json'
            & ./scripts/exchange/propose_imports.ps1 -RepoRoot . -RepoKitRoot . -OutputJson $exchangeProposalPath -OutputMarkdown $exchangeProposalMarkdown
            & ./scripts/exchange/apply_approved_exchange.ps1 -RepoRoot . -RepoKitRoot . -ProposalPath $exchangeProposalPath -ProposalType import -ReportPath $exchangeApplyReport
            $exchangeCommon = Join-Path (Resolve-Path .).Path 'scripts/exchange/Exchange.Common.ps1'
            . $exchangeCommon
            $fingerprintFixture = Join-Path $env:TEMP ('generated_fingerprint_' + [guid]::NewGuid().ToString('N'))
            try {
                New-Item -ItemType Directory -Path $fingerprintFixture -Force | Out-Null
                'managed' | Set-Content -LiteralPath (Join-Path $fingerprintFixture 'managed.txt') -NoNewline
                $baselineFingerprint = Get-RepoKitDirectoryFingerprint -RootPath $fingerprintFixture
                $policy = Get-RepoKitGeneratedFingerprintPolicy
                if ($policy.version -ne 1) { throw 'Generated fingerprint policy version must be 1.' }
                foreach ($segment in @($policy.excluded_path_segments)) {
                    $excludedDirectory = Join-Path $fingerprintFixture ([string]$segment)
                    New-Item -ItemType Directory -Path $excludedDirectory -Force | Out-Null
                    $excludedFile = Join-Path $excludedDirectory 'changed.txt'
                    [guid]::NewGuid().ToString('N') | Set-Content -LiteralPath $excludedFile -NoNewline
                    if (-not (Test-RepoKitGeneratedPath -BasePath $fingerprintFixture -PathValue $excludedFile) -or
                        -not (Test-ExchangeGeneratedPath -BasePath $fingerprintFixture -PathValue $excludedFile)) {
                        throw "Generated fingerprint segment was not excluded consistently: $segment"
                    }
                }
                foreach ($extension in @($policy.excluded_file_extensions)) {
                    $excludedFile = Join-Path $fingerprintFixture ('changed' + [string]$extension)
                    [guid]::NewGuid().ToString('N') | Set-Content -LiteralPath $excludedFile -NoNewline
                    if (-not (Test-RepoKitGeneratedPath -BasePath $fingerprintFixture -PathValue $excludedFile) -or
                        -not (Test-ExchangeGeneratedPath -BasePath $fingerprintFixture -PathValue $excludedFile)) {
                        throw "Generated fingerprint extension was not excluded consistently: $extension"
                    }
                }
                if ((Get-RepoKitDirectoryFingerprint -RootPath $fingerprintFixture) -ne $baselineFingerprint -or
                    (Get-ExchangePathHash -Path $fingerprintFixture) -ne $baselineFingerprint -or
                    @(Get-RepoKitFingerprintRows -RootPath $fingerprintFixture).Count -ne 1) {
                    throw 'Generated/cache artifacts changed the shared exchange/upgrade fingerprint.'
                }
                'managed-changed' | Set-Content -LiteralPath (Join-Path $fingerprintFixture 'managed.txt') -NoNewline
                if ((Get-RepoKitDirectoryFingerprint -RootPath $fingerprintFixture) -eq $baselineFingerprint) {
                    throw 'Managed content did not change the shared fingerprint.'
                }
            }
            finally {
                if (Test-Path -LiteralPath $fingerprintFixture) {
                    Remove-Item -LiteralPath $fingerprintFixture -Recurse -Force
                }
            }
            $fixtureCatalog = [pscustomobject]@{ items = @(
                [pscustomobject]@{ id='repo-kit-language-lint-policy'; source_path='docs/policy.md'; target_path='docs/policy.md'; bundle_id='repo-kit-language-lint'; requires=@('repo-kit-language-lint-matrix','repo-kit-lint-scripts') },
                [pscustomobject]@{ id='repo-kit-language-lint-matrix'; source_path='standards/matrix.json'; target_path='standards/matrix.json'; bundle_id='repo-kit-language-lint'; requires=@() },
                [pscustomobject]@{ id='repo-kit-lint-scripts'; source_path='scripts/lint'; target_path='scripts/lint'; bundle_id='repo-kit-language-lint'; requires=@('repo-kit-language-lint-matrix') }
            ) }
            $validatedCatalog = Get-ExchangeCatalogItems -Catalog $fixtureCatalog
            $closure = @(Get-ExchangeSelectionClosure -ItemsById $validatedCatalog.by_id -SelectedIds @('repo-kit-lint-scripts'))
            $expectedClosure = @('repo-kit-language-lint-matrix','repo-kit-language-lint-policy','repo-kit-lint-scripts')
            if (($closure -join ',') -ne ($expectedClosure -join ',')) { throw "Exchange bundle selection closure failed: $($closure -join ',')" }
            foreach ($invalidCatalog in @(
                [pscustomobject]@{ items=@($fixtureCatalog.items[0], $fixtureCatalog.items[0]) },
                [pscustomobject]@{ items=@([pscustomobject]@{id='escape';source_path='../escape';target_path='safe';requires=@()}) },
                [pscustomobject]@{ items=@([pscustomobject]@{id='parent';source_path='a';target_path='dest';requires=@()},[pscustomobject]@{id='child';source_path='b';target_path='dest/child';requires=@()}) },
                [pscustomobject]@{ items=@([pscustomobject]@{id='a';source_path='a';target_path='a';requires=@('b')},[pscustomobject]@{id='b';source_path='b';target_path='b';requires=@('a')}) },
                [pscustomobject]@{ items=@([pscustomobject]@{id='bad-bundle';source_path='a';target_path='a';bundle_id='INVALID BUNDLE';requires=@()}) }
            )) {
                $rejected = $false
                try { $null = Get-ExchangeCatalogItems -Catalog $invalidCatalog } catch { $rejected = $true }
                if (-not $rejected) { throw 'Exchange catalog accepted duplicate, traversal, overlap, or cycle fixture.' }
            }
            $assertRejectedReport = {
                param([string]$Path, [string]$ExpectedReasonCode)
                if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Rejected exchange did not write a JSON report: $Path" }
                $rejection = Read-ExchangeJsonFile -Path $Path
                if ([string]$rejection.transaction_status -ne 'rejected' -or [string]$rejection.reason_code -ne $ExpectedReasonCode -or [int]$rejection.summary.rejected -ne 1) {
                    throw "Rejected exchange report mismatch: expected=$ExpectedReasonCode actual=$($rejection.reason_code) status=$($rejection.transaction_status)"
                }
                $rejectionMarkdown = Get-Content -LiteralPath ([IO.Path]::ChangeExtension($Path, '.md')) -Raw
                if ([string]$rejection.diagnostic_class -ne 'none' -or -not [string]::IsNullOrEmpty([string]$rejection.diagnostic_fingerprint) -or -not $rejectionMarkdown.Contains('diagnostic_class: `none`') -or -not $rejectionMarkdown.Contains('diagnostic_fingerprint: ``')) {
                    throw 'Rejection without a private diagnostic exposed inconsistent diagnostic evidence.'
                }
            }

            $transactionFixture = Join-Path $env:TEMP ('exchange_transaction_fixture_' + [Guid]::NewGuid().ToString('N'))
            $fixtureRepo = Join-Path $transactionFixture 'repo'
            $fixtureKit = Join-Path $transactionFixture 'kit'
            $fixtureLedger = ''
            $fixtureLedgerUnixMode = $null
            try {
                New-Item -ItemType Directory -Force -Path (Join-Path $fixtureKit 'repo-standards/exchange'),(Join-Path $fixtureKit 'source'),(Join-Path $fixtureRepo 'dest') | Out-Null
                git -C $fixtureRepo init --quiet
                if ($LASTEXITCODE -ne 0) { throw 'Could not initialize isolated exchange transaction fixture.' }
                '.repo-kit-local/' | Set-Content -LiteralPath (Join-Path $fixtureRepo '.gitignore') -NoNewline
                'new-one' | Set-Content -LiteralPath (Join-Path $fixtureKit 'source/one.txt') -NoNewline
                'new-two' | Set-Content -LiteralPath (Join-Path $fixtureKit 'source/two.txt') -NoNewline
                'old-one' | Set-Content -LiteralPath (Join-Path $fixtureRepo 'dest/one.txt') -NoNewline
                New-Item -ItemType Directory -Force -Path (Join-Path $fixtureRepo '.repo-kit') | Out-Null
                $fixtureLedger = Join-Path $fixtureRepo '.repo-kit/audit/custom-ledger.jsonl'
                Write-ExchangeJsonFile -Path (Join-Path $fixtureRepo '.repo-kit/exchange.json') -Payload ([ordered]@{ ledger=[ordered]@{ path='.repo-kit/audit/custom-ledger.jsonl' } })
                $transactionCatalog = [ordered]@{ version=2; items=@(
                    [ordered]@{id='one';source_path='source/one.txt';target_path='dest/one.txt';category='fixture';description='first'},
                    [ordered]@{id='two';source_path='source/two.txt';target_path='dest/two.txt';category='fixture';description='second transactional item'}
                ) }
                Write-ExchangeJsonFile -Path (Join-Path $fixtureKit 'repo-standards/exchange/default_items.json') -Payload $transactionCatalog
                $fixtureProposal = Join-Path $fixtureRepo 'proposal.json'
                $fixtureProposalMd = Join-Path $fixtureRepo 'proposal.md'
                & ./scripts/exchange/propose_imports.ps1 -RepoRoot $fixtureRepo -RepoKitRoot $fixtureKit -OutputJson $fixtureProposal -OutputMarkdown $fixtureProposalMd -DestinationOnlyPolicy remove
                'drifted' | Set-Content -LiteralPath (Join-Path $fixtureKit 'source/two.txt') -NoNewline
                $driftRejected = $false
                $driftReport = Join-Path $fixtureRepo 'drift-report.json'
                try { & ./scripts/exchange/apply_approved_exchange.ps1 -RepoRoot $fixtureRepo -RepoKitRoot $fixtureKit -ProposalPath $fixtureProposal -ProposalType import -ReportPath $driftReport } catch { $driftRejected = $true }
                if (-not $driftRejected) { throw 'Exchange apply accepted source drift.' }
                & $assertRejectedReport $driftReport 'source_drift'
                'new-two' | Set-Content -LiteralPath (Join-Path $fixtureKit 'source/two.txt') -NoNewline

                $overwriteRejected = $false
                $overwriteReport = Join-Path $fixtureRepo 'overwrite-report.json'
                try { & ./scripts/exchange/apply_approved_exchange.ps1 -RepoRoot $fixtureRepo -RepoKitRoot $fixtureKit -ProposalPath $fixtureProposal -ProposalType import -ReportPath $overwriteReport -Execute -ApprovalToken APPROVED } catch { $overwriteRejected = $true }
                if (-not $overwriteRejected) { throw 'Exchange apply replaced an existing target without -AllowOverwrite.' }
                if ((Get-Content -LiteralPath (Join-Path $fixtureRepo 'dest/one.txt') -Raw) -ne 'old-one' -or (Test-Path -LiteralPath (Join-Path $fixtureRepo 'dest/two.txt')) -or (Test-Path -LiteralPath $fixtureLedger)) { throw 'Overwrite preflight mutated a target or ledger.' }
                & $assertRejectedReport $overwriteReport 'overwrite_required'

                $fixtureLock = Join-Path $fixtureRepo '.repo-kit/exchange.lock'
                'held' | Set-Content -LiteralPath $fixtureLock -NoNewline
                $lockRejected = $false
                $lockReport = Join-Path $fixtureRepo 'lock-report.json'
                try { & ./scripts/exchange/apply_approved_exchange.ps1 -RepoRoot $fixtureRepo -RepoKitRoot $fixtureKit -ProposalPath $fixtureProposal -ProposalType import -ReportPath $lockReport -Execute -ApprovalToken APPROVED -AllowOverwrite } catch { $lockRejected = $true }
                if (-not $lockRejected) { throw 'Exchange apply accepted a contended transaction lock.' }
                if ((Get-Content -LiteralPath (Join-Path $fixtureRepo 'dest/one.txt') -Raw) -ne 'old-one' -or (Test-Path -LiteralPath (Join-Path $fixtureRepo 'dest/two.txt')) -or (Test-Path -LiteralPath $fixtureLedger)) { throw 'Contended lock attempt mutated a target or ledger.' }
                & $assertRejectedReport $lockReport 'lock_unavailable'
                Remove-Item -LiteralPath $fixtureLock -Force

                & ./scripts/exchange/apply_approved_exchange.ps1 -RepoRoot $fixtureRepo -RepoKitRoot $fixtureKit -ProposalPath $fixtureProposal -ProposalType import -ReportPath (Join-Path $fixtureRepo 'success-report.json') -Execute -ApprovalToken APPROVED -AllowOverwrite
                if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath (Join-Path $fixtureRepo 'dest/one.txt') -Raw) -ne 'new-one' -or (Get-Content -LiteralPath (Join-Path $fixtureRepo 'dest/two.txt') -Raw) -ne 'new-two') { throw 'Approved overwrite fixture did not apply both items.' }
                if (-not (Test-Path -LiteralPath $fixtureLedger -PathType Leaf)) { throw 'Manifest-configured nondefault exchange ledger was not written.' }

                'old-one' | Set-Content -LiteralPath (Join-Path $fixtureRepo 'dest/one.txt') -NoNewline
                Remove-Item -LiteralPath (Join-Path $fixtureRepo 'dest/two.txt') -Force
                '{"legacy":"prior-ledger"}' | Set-Content -LiteralPath $fixtureLedger -NoNewline
                if ($IsWindows) {
                    (Get-Item -LiteralPath $fixtureLedger).IsReadOnly = $true
                }
                else {
                    $fixtureLedgerUnixMode = [System.IO.File]::GetUnixFileMode($fixtureLedger)
                    [System.IO.File]::SetUnixFileMode($fixtureLedger, [System.IO.UnixFileMode]::UserRead -bor [System.IO.UnixFileMode]::GroupRead -bor [System.IO.UnixFileMode]::OtherRead)
                }
                & ./scripts/exchange/apply_approved_exchange.ps1 -RepoRoot $fixtureRepo -RepoKitRoot $fixtureKit -ProposalPath $fixtureProposal -ProposalType import -ReportPath (Join-Path $fixtureRepo 'rollback-report.json') -Execute -ApprovalToken APPROVED -AllowOverwrite
                $rollbackExit = $LASTEXITCODE
                if ($rollbackExit -ne 2) { throw "Exchange rollback fixture returned $rollbackExit instead of 2." }
                if ((Get-Content -LiteralPath (Join-Path $fixtureRepo 'dest/one.txt') -Raw) -ne 'old-one') { throw 'Exchange rollback left a partial first-item mutation.' }
                if ((Get-Content -LiteralPath $fixtureLedger -Raw) -ne '{"legacy":"prior-ledger"}') { throw 'Exchange rollback changed the prior ledger.' }
                $rollbackReport = Read-ExchangeJsonFile -Path (Join-Path $fixtureRepo 'rollback-report.json')
                if ([string]$rollbackReport.transaction_status -ne 'rolled_back' -or [string]$rollbackReport.reason_code -ne 'apply_failed_rolled_back') { throw 'Exchange rollback report lacks rolled_back status and reason code.' }
                $rollbackReportText = Get-Content -LiteralPath (Join-Path $fixtureRepo 'rollback-report.json') -Raw
                $rollbackMarkdownText = Get-Content -LiteralPath (Join-Path $fixtureRepo 'rollback-report.md') -Raw
                if ($rollbackReportText.Contains($transactionFixture) -or $rollbackMarkdownText.Contains($transactionFixture) -or $rollbackReportText -match 'Access to the path' -or $rollbackMarkdownText -match 'Access to the path') { throw 'Exchange rollback report persisted a raw exception or absolute fixture path.' }
            }
            finally {
                if (-not [string]::IsNullOrWhiteSpace($fixtureLedger) -and (Test-Path -LiteralPath $fixtureLedger -ErrorAction SilentlyContinue)) {
                    if ($IsWindows) { (Get-Item -LiteralPath $fixtureLedger).IsReadOnly = $false }
                    elseif ($null -ne $fixtureLedgerUnixMode) { [System.IO.File]::SetUnixFileMode($fixtureLedger, $fixtureLedgerUnixMode) }
                }
                if (Test-Path -LiteralPath $transactionFixture) { Remove-Item -LiteralPath $transactionFixture -Recurse -Force }
            }

            $exportFixture = Join-Path $env:TEMP ('exchange_export_fixture_' + [Guid]::NewGuid().ToString('N'))
            $exportRepo = Join-Path $exportFixture 'repo'
            $exportKit = Join-Path $exportFixture 'kit'
            $exportLedger = ''
            $exportLedgerUnixMode = $null
            try {
                New-Item -ItemType Directory -Force -Path (Join-Path $exportRepo '.repo-kit'),(Join-Path $exportRepo 'exports/a'),(Join-Path $exportKit 'exports') | Out-Null
                git -C $exportRepo init --quiet
                if ($LASTEXITCODE -ne 0) { throw 'Could not initialize isolated export transaction fixture.' }
                '.repo-kit-local/' | Set-Content -LiteralPath (Join-Path $exportRepo '.gitignore') -NoNewline
                'new-one' | Set-Content -LiteralPath (Join-Path $exportRepo 'exports/one.txt') -NoNewline
                'new-two' | Set-Content -LiteralPath (Join-Path $exportRepo 'exports/two.txt') -NoNewline
                'dash-path' | Set-Content -LiteralPath (Join-Path $exportRepo 'exports/a-b') -NoNewline
                'nested-path' | Set-Content -LiteralPath (Join-Path $exportRepo 'exports/a/b') -NoNewline
                'private-data' | Set-Content -LiteralPath (Join-Path $exportRepo 'exports/private.txt') -NoNewline
                'old-one' | Set-Content -LiteralPath (Join-Path $exportKit 'exports/one.txt') -NoNewline
                $exportLedger = Join-Path $exportRepo '.repo-kit/audit/export-ledger.jsonl'
                Write-ExchangeJsonFile -Path (Join-Path $exportRepo '.repo-kit/exchange.json') -Payload ([ordered]@{ exports=@(); exclusions=@(); ledger=[ordered]@{path='.repo-kit/audit/export-ledger.jsonl'} })
                $exportCatalogPath = Join-Path $exportRepo '.repo-kit/catalog.json'
                Write-ExchangeJsonFile -Path $exportCatalogPath -Payload ([ordered]@{ candidates=@(
                    [ordered]@{path='exports/one.txt';category='fixture';privacy_classification='public';bytes=7;sha256=(Get-ExchangeFileHash -Path (Join-Path $exportRepo 'exports/one.txt'))},
                    [ordered]@{path='exports/two.txt';category='fixture';privacy_classification='public';bytes=7;sha256=(Get-ExchangeFileHash -Path (Join-Path $exportRepo 'exports/two.txt'))},
                    [ordered]@{path='exports/a-b';category='fixture';privacy_classification='public';bytes=9;sha256=(Get-ExchangeFileHash -Path (Join-Path $exportRepo 'exports/a-b'))},
                    [ordered]@{path='exports/a/b';category='fixture';privacy_classification='public';bytes=11;sha256=(Get-ExchangeFileHash -Path (Join-Path $exportRepo 'exports/a/b'))},
                    [ordered]@{path='exports/private.txt';category='fixture-private';privacy_classification='private';bytes=12;sha256=(Get-ExchangeFileHash -Path (Join-Path $exportRepo 'exports/private.txt'))}
                ) })
                $exportProposal = Join-Path $exportRepo '.repo-kit/proposals/export.json'
                & ./scripts/exchange/propose_exports.ps1 -RepoRoot $exportRepo -RepoKitRoot $exportKit -CatalogJson $exportCatalogPath -OutputJson $exportProposal -OutputMarkdown (Join-Path $exportRepo '.repo-kit/proposals/export.md') -DestinationOnlyPolicy remove
                $exportPayload = Read-ExchangeJsonFile -Path $exportProposal
                if ([string]$exportPayload.schema_version -ne 'repo-kit.exchange-export-proposal.v2' -or [string]$exportPayload.transaction_mode -ne 'transactional-export' -or [string]::IsNullOrWhiteSpace([string]$exportPayload.proposal_id)) { throw 'Export proposal v2 identity contract is incomplete.' }
                $collidingSlugEntries = @($exportPayload.proposals | Where-Object { $_.local_path -in @('exports/a-b', 'exports/a/b') })
                if ($collidingSlugEntries.Count -ne 2 -or @($collidingSlugEntries.id | Sort-Object -Unique).Count -ne 2) { throw 'Export proposal IDs do not distinguish normalized paths with the same slug.' }
                if (@($exportPayload.proposals | Where-Object { $_.local_path -eq 'exports/private.txt' }).Count -ne 0) { throw 'Export proposal included a private catalog candidate.' }
                $assertNoExportMutation = {
                    if ((Get-Content -LiteralPath (Join-Path $exportKit 'exports/one.txt') -Raw) -ne 'old-one' -or
                        (Test-Path -LiteralPath (Join-Path $exportKit 'exports/two.txt')) -or
                        (Test-Path -LiteralPath (Join-Path $exportKit 'exports/a-b')) -or
                        (Test-Path -LiteralPath (Join-Path $exportKit 'exports/a/b')) -or
                        (Test-Path -LiteralPath (Join-Path $exportKit 'exports/private.txt')) -or
                        (Test-Path -LiteralPath $exportLedger)) { throw 'Rejected export mutated a destination or ledger.' }
                }

                $changedDestinationPayload = $exportPayload | ConvertTo-Json -Depth 20 | ConvertFrom-Json
                $changedDestinationPayload.proposals[0].proposed_destination = 'exports/changed.txt'
                $changedDestinationProposal = Join-Path $exportRepo '.repo-kit/proposals/export-changed-destination.json'
                Write-ExchangeJsonFile -Path $changedDestinationProposal -Payload $changedDestinationPayload
                $changedDestinationRejected = $false
                $changedDestinationReport = Join-Path $exportRepo 'changed-destination-report.json'
                try { & ./scripts/exchange/apply_approved_exchange.ps1 -RepoRoot $exportRepo -RepoKitRoot $exportKit -ProposalPath $changedDestinationProposal -ProposalType auto -ReportPath $changedDestinationReport -Execute -ApprovalToken APPROVED -AllowOverwrite } catch { $changedDestinationRejected = $true }
                if (-not $changedDestinationRejected) { throw 'Export apply trusted a proposal-changed destination.' }
                & $assertRejectedReport $changedDestinationReport 'catalog_authority_rejected'
                & $assertNoExportMutation

                $absentPayload = $exportPayload | ConvertTo-Json -Depth 20 | ConvertFrom-Json
                $absentEntry = $absentPayload.proposals[0] | ConvertTo-Json -Depth 20 | ConvertFrom-Json
                $absentEntry.id = 'absent-from-catalog-000000000000'
                $absentPayload.proposals = @($absentPayload.proposals) + @($absentEntry)
                $absentProposal = Join-Path $exportRepo '.repo-kit/proposals/export-absent.json'
                Write-ExchangeJsonFile -Path $absentProposal -Payload $absentPayload
                $absentRejected = $false
                $absentReport = Join-Path $exportRepo 'absent-report.json'
                try { & ./scripts/exchange/apply_approved_exchange.ps1 -RepoRoot $exportRepo -RepoKitRoot $exportKit -ProposalPath $absentProposal -ProposalType auto -ReportPath $absentReport -Execute -ApprovalToken APPROVED -AllowOverwrite } catch { $absentRejected = $true }
                if (-not $absentRejected) { throw 'Export apply accepted an entry absent from the bound catalog.' }
                & $assertRejectedReport $absentReport 'catalog_authority_rejected'
                & $assertNoExportMutation

                $privatePath = 'exports/private.txt'
                $privateIdSha = [Security.Cryptography.SHA256]::Create()
                try { $privateIdSuffix = ([BitConverter]::ToString($privateIdSha.ComputeHash([Text.Encoding]::UTF8.GetBytes($privatePath))).Replace('-', '').ToLowerInvariant()).Substring(0, 12) }
                finally { $privateIdSha.Dispose() }
                $privateSourceHash = Get-ExchangePathHash -Path (Join-Path $exportRepo $privatePath)
                $privatePayload = $exportPayload | ConvertTo-Json -Depth 20 | ConvertFrom-Json
                $privatePayload.proposals = @($privatePayload.proposals) + @([pscustomobject][ordered]@{
                    id = "exports-private-txt-$privateIdSuffix"; local_path = $privatePath; proposed_destination = $privatePath
                    category = 'fixture-private'; privacy_classification = 'private'; status = 'candidate'; bundle_id = ''; requires = @()
                    destination_only_policy = 'remove'; reviewed_source_hash = $privateSourceHash; reviewed_target_hash = $null; reviewed_result_hash = $privateSourceHash
                })
                $privateProposal = Join-Path $exportRepo '.repo-kit/proposals/export-private.json'
                Write-ExchangeJsonFile -Path $privateProposal -Payload $privatePayload
                $privateRejected = $false
                $privateReport = Join-Path $exportRepo 'private-report.json'
                try { & ./scripts/exchange/apply_approved_exchange.ps1 -RepoRoot $exportRepo -RepoKitRoot $exportKit -ProposalPath $privateProposal -ProposalType auto -ReportPath $privateReport -Execute -ApprovalToken APPROVED -AllowOverwrite } catch { $privateRejected = $true }
                if (-not $privateRejected) { throw 'Export apply accepted a private bound-catalog candidate.' }
                & $assertRejectedReport $privateReport 'privacy_rejected'
                & $assertNoExportMutation

                $traversalPayload = $exportPayload | ConvertTo-Json -Depth 20 | ConvertFrom-Json
                $traversalPayload.proposals[0].local_path = '../escape.txt'
                $traversalProposal = Join-Path $exportRepo '.repo-kit/proposals/export-traversal.json'
                Write-ExchangeJsonFile -Path $traversalProposal -Payload $traversalPayload
                $traversalRejected = $false
                $traversalReport = Join-Path $exportRepo 'traversal-report.json'
                try { & ./scripts/exchange/apply_approved_exchange.ps1 -RepoRoot $exportRepo -RepoKitRoot $exportKit -ProposalPath $traversalProposal -ProposalType auto -ReportPath $traversalReport } catch { $traversalRejected = $true }
                if (-not $traversalRejected) { throw 'Export apply accepted a traversing local_path.' }
                & $assertRejectedReport $traversalReport 'path_rejected'
                & $assertNoExportMutation

                'source-drift' | Set-Content -LiteralPath (Join-Path $exportRepo 'exports/two.txt') -NoNewline
                $sourceDriftRejected = $false
                $sourceDriftReport = Join-Path $exportRepo 'source-drift-report.json'
                try { & ./scripts/exchange/apply_approved_exchange.ps1 -RepoRoot $exportRepo -RepoKitRoot $exportKit -ProposalPath $exportProposal -ProposalType auto -ReportPath $sourceDriftReport } catch { $sourceDriftRejected = $true }
                if (-not $sourceDriftRejected) { throw 'Export apply accepted source drift.' }
                & $assertRejectedReport $sourceDriftReport 'source_drift'
                'new-two' | Set-Content -LiteralPath (Join-Path $exportRepo 'exports/two.txt') -NoNewline

                'target-drift' | Set-Content -LiteralPath (Join-Path $exportKit 'exports/one.txt') -NoNewline
                $targetDriftRejected = $false
                $targetDriftReport = Join-Path $exportRepo 'target-drift-report.json'
                try { & ./scripts/exchange/apply_approved_exchange.ps1 -RepoRoot $exportRepo -RepoKitRoot $exportKit -ProposalPath $exportProposal -ProposalType auto -ReportPath $targetDriftReport } catch { $targetDriftRejected = $true }
                if (-not $targetDriftRejected) { throw 'Export apply accepted target drift.' }
                & $assertRejectedReport $targetDriftReport 'target_drift'
                'old-one' | Set-Content -LiteralPath (Join-Path $exportKit 'exports/one.txt') -NoNewline

                $exportOverwriteRejected = $false
                $exportOverwriteReport = Join-Path $exportRepo 'export-overwrite-report.json'
                try { & ./scripts/exchange/apply_approved_exchange.ps1 -RepoRoot $exportRepo -RepoKitRoot $exportKit -ProposalPath $exportProposal -ProposalType auto -ReportPath $exportOverwriteReport -Execute -ApprovalToken APPROVED } catch { $exportOverwriteRejected = $true }
                if (-not $exportOverwriteRejected -or (Get-Content -LiteralPath (Join-Path $exportKit 'exports/one.txt') -Raw) -ne 'old-one' -or (Test-Path -LiteralPath $exportLedger)) { throw 'Export overwrite preflight was not mutation-free.' }
                & $assertRejectedReport $exportOverwriteReport 'overwrite_required'

                $exportSuccessReportPath = Join-Path $exportRepo 'export-success-report.json'
                & ./scripts/exchange/apply_approved_exchange.ps1 -RepoRoot $exportRepo -RepoKitRoot $exportKit -ProposalPath $exportProposal -ProposalType auto -ReportPath $exportSuccessReportPath -Execute -ApprovalToken APPROVED -AllowOverwrite
                $exportSuccessReport = Read-ExchangeJsonFile -Path $exportSuccessReportPath
                $exportSuccessMarkdown = Get-Content -LiteralPath ([IO.Path]::ChangeExtension($exportSuccessReportPath, '.md')) -Raw
                if ($LASTEXITCODE -ne 0 -or
                    [string]$exportSuccessReport.diagnostic_class -ne 'none' -or
                    -not [string]::IsNullOrEmpty([string]$exportSuccessReport.diagnostic_fingerprint) -or
                    -not $exportSuccessMarkdown.Contains('diagnostic_class: `none`') -or
                    -not $exportSuccessMarkdown.Contains('diagnostic_fingerprint: ``') -or
                    (Get-Content -LiteralPath (Join-Path $exportKit 'exports/one.txt') -Raw) -ne 'new-one' -or
                    (Get-Content -LiteralPath (Join-Path $exportKit 'exports/two.txt') -Raw) -ne 'new-two' -or
                    (Get-Content -LiteralPath (Join-Path $exportKit 'exports/a-b') -Raw) -ne 'dash-path' -or
                    (Get-Content -LiteralPath (Join-Path $exportKit 'exports/a/b') -Raw) -ne 'nested-path' -or
                    -not (Test-Path -LiteralPath $exportLedger)) { throw 'Transactional export did not publish all catalog-authorized items and ledger.' }

                'old-one' | Set-Content -LiteralPath (Join-Path $exportKit 'exports/one.txt') -NoNewline
                Remove-Item -LiteralPath (Join-Path $exportKit 'exports/two.txt') -Force
                Remove-Item -LiteralPath (Join-Path $exportKit 'exports/a-b') -Force
                Remove-Item -LiteralPath (Join-Path $exportKit 'exports/a') -Recurse -Force
                $priorExportLedgerContent = '{"legacy":"prior-export-ledger"}'
                $priorExportLedgerContent | Set-Content -LiteralPath $exportLedger -NoNewline
                $priorExportLedgerHash = Get-ExchangeFileHash -Path $exportLedger
                if ($IsWindows) {
                    (Get-Item -LiteralPath $exportLedger).IsReadOnly = $true
                }
                else {
                    $exportLedgerUnixMode = [System.IO.File]::GetUnixFileMode($exportLedger)
                    [System.IO.File]::SetUnixFileMode($exportLedger, [System.IO.UnixFileMode]::UserRead -bor [System.IO.UnixFileMode]::GroupRead -bor [System.IO.UnixFileMode]::OtherRead)
                }
                & ./scripts/exchange/apply_approved_exchange.ps1 -RepoRoot $exportRepo -RepoKitRoot $exportKit -ProposalPath $exportProposal -ProposalType auto -ReportPath (Join-Path $exportRepo 'export-rollback-report.json') -Execute -ApprovalToken APPROVED -AllowOverwrite
                if ($LASTEXITCODE -ne 2 -or (Get-Content -LiteralPath (Join-Path $exportKit 'exports/one.txt') -Raw) -ne 'old-one' -or (Test-Path -LiteralPath (Join-Path $exportKit 'exports/two.txt')) -or (Test-Path -LiteralPath (Join-Path $exportKit 'exports/a-b')) -or (Test-Path -LiteralPath (Join-Path $exportKit 'exports/a/b')) -or (Get-Content -LiteralPath $exportLedger -Raw) -ne $priorExportLedgerContent -or (Get-ExchangeFileHash -Path $exportLedger) -ne $priorExportLedgerHash) { throw 'Export ledger-last rollback left a partial mutation or changed prior ledger bytes.' }
                $exportRollbackReport = Read-ExchangeJsonFile -Path (Join-Path $exportRepo 'export-rollback-report.json')
                $exportRollbackReportText = Get-Content -LiteralPath (Join-Path $exportRepo 'export-rollback-report.json') -Raw
                $exportRollbackMarkdownText = Get-Content -LiteralPath (Join-Path $exportRepo 'export-rollback-report.md') -Raw
                if ([string]$exportRollbackReport.reason_code -ne 'apply_failed_rolled_back' -or $exportRollbackReportText.Contains($exportFixture) -or $exportRollbackMarkdownText.Contains($exportFixture) -or $exportRollbackReportText -match 'Access to the path' -or $exportRollbackMarkdownText -match 'Access to the path') { throw 'Export rollback report persisted a raw exception or absolute fixture path.' }
            }
            finally {
                if (-not [string]::IsNullOrWhiteSpace($exportLedger) -and (Test-Path -LiteralPath $exportLedger -ErrorAction SilentlyContinue)) {
                    if ($IsWindows) { (Get-Item -LiteralPath $exportLedger).IsReadOnly = $false }
                    elseif ($null -ne $exportLedgerUnixMode) { [System.IO.File]::SetUnixFileMode($exportLedger, $exportLedgerUnixMode) }
                }
                if (Test-Path -LiteralPath $exportFixture) { Remove-Item -LiteralPath $exportFixture -Recurse -Force }
            }

            $diagnosticClassCases = [ordered]@{
                'io-sharing' = [InvalidOperationException]::new('outer text is irrelevant', [IO.IOException]::new('localized sharing message is irrelevant', -2147024864))
                'io-permission' = [UnauthorizedAccessException]::new('localized permission message is irrelevant')
                'json-invalid' = [System.Text.Json.JsonException]::new('localized JSON message is irrelevant')
                'binding-invalid' = [InvalidOperationException]::new('localized binding message is irrelevant')
                'path-invalid' = [InvalidOperationException]::new('localized path message is irrelevant')
                'other' = [InvalidOperationException]::new('localized other message is irrelevant')
            }
            foreach ($expectedDiagnosticClass in $diagnosticClassCases.Keys) {
                $caseReason = if ($expectedDiagnosticClass -eq 'binding-invalid') { 'recovery_invalid' } elseif ($expectedDiagnosticClass -eq 'path-invalid') { 'path_rejected' } else { 'preflight_rejected' }
                $actualDiagnosticClass = Get-ExchangeDiagnosticClass -Exception $diagnosticClassCases[$expectedDiagnosticClass] -ReasonCode $caseReason
                if ($actualDiagnosticClass -ne $expectedDiagnosticClass) { throw "Diagnostic class mismatch: expected=$expectedDiagnosticClass actual=$actualDiagnosticClass" }
            }
            $diagnosticPrecedenceCases = @(
                [ordered]@{ expected='io-sharing'; reason='recovery_invalid'; exception=[InvalidOperationException]::new('outer binding text is irrelevant', [IO.IOException]::new('inner sharing text is irrelevant', -2147024864)) },
                [ordered]@{ expected='io-permission'; reason='path_rejected'; exception=[InvalidOperationException]::new('outer path text is irrelevant', [UnauthorizedAccessException]::new('inner permission text is irrelevant')) },
                [ordered]@{ expected='json-invalid'; reason='recovery_invalid'; exception=[InvalidOperationException]::new('outer binding text is irrelevant', [System.Text.Json.JsonException]::new('inner JSON text is irrelevant')) }
            )
            foreach ($precedenceCase in $diagnosticPrecedenceCases) {
                $actualDiagnosticClass = Get-ExchangeDiagnosticClass -Exception $precedenceCase.exception -ReasonCode $precedenceCase.reason
                if ($actualDiagnosticClass -ne $precedenceCase.expected) { throw "Diagnostic exception-chain precedence mismatch: expected=$($precedenceCase.expected) actual=$actualDiagnosticClass" }
            }
            $diagnosticClassEnum = @('none','io-sharing','io-permission','json-invalid','binding-invalid','path-invalid','other')
            if (@($diagnosticClassEnum | Sort-Object -Unique).Count -ne 7) { throw 'Diagnostic class public enum is not fixed and unique.' }

            $canonicalBindingA = [ordered]@{
                zeta = [ordered]@{ second='two'; first='one' }
                alpha = @([ordered]@{ beta=$true; alpha=$null }, [ordered]@{ beta=$false; alpha=2 })
                singleton = @([ordered]@{ id='only' })
                empty = @()
            }
            $canonicalBindingB = [ordered]@{
                empty = @()
                singleton = @([ordered]@{ id='only' })
                alpha = @([ordered]@{ alpha=$null; beta=$true }, [ordered]@{ alpha=2; beta=$false })
                zeta = [ordered]@{ first='one'; second='two' }
            }
            $canonicalHash = Get-ExchangeDurableObjectHash -Payload $canonicalBindingA
            if ($canonicalHash -ne (Get-ExchangeDurableObjectHash -Payload $canonicalBindingB)) { throw 'Durable exchange hash changed when nested object keys were reordered.' }
            $changedValue = $canonicalBindingB | ConvertTo-Json -Depth 20 | ConvertFrom-Json
            $changedValue.zeta.first = 'changed'
            if ($canonicalHash -eq (Get-ExchangeDurableObjectHash -Payload $changedValue)) { throw 'Durable exchange hash ignored a changed value.' }
            $changedArrayOrder = $canonicalBindingB | ConvertTo-Json -Depth 20 | ConvertFrom-Json
            $changedArrayOrder.alpha = @($changedArrayOrder.alpha[1], $changedArrayOrder.alpha[0])
            if ($canonicalHash -eq (Get-ExchangeDurableObjectHash -Payload $changedArrayOrder)) { throw 'Durable exchange hash ignored array order.' }
            $roundTripValue = $canonicalBindingA
            foreach ($iteration in 1..1000) {
                $roundTripValue = ($roundTripValue | ConvertTo-Json -Depth 20 -Compress) | ConvertFrom-Json
                if ((Get-ExchangeDurableObjectHash -Payload $roundTripValue) -ne $canonicalHash) { throw "Durable exchange hash changed after JSON roundtrip $iteration." }
            }
            $generatedUtcTimestamp = [DateTime]::UtcNow.ToString('o', [Globalization.CultureInfo]::InvariantCulture)
            $parsedUtcTimestamp = (([ordered]@{value=$generatedUtcTimestamp} | ConvertTo-Json -Compress) | ConvertFrom-Json).value
            if ((Get-ExchangeDurableObjectHash -Payload ([ordered]@{value=$generatedUtcTimestamp})) -ne (Get-ExchangeDurableObjectHash -Payload ([ordered]@{value=$parsedUtcTimestamp}))) {
                throw 'Durable exchange hash changed when a generated UTC timestamp was parsed from JSON.'
            }
            $ledgerTimestampRow = [ordered]@{schema_version=2;transaction_id='0123456789abcdef0123456789abcdef';recorded_at_utc='2026-08-15T16:05:00.1200000Z';action='exchange_apply';direction='import';proposal_id='proposal';item_id='item';source_path='source/item';target_path='target/item';reviewed_source_hash=('a' * 64);reviewed_target_hash='';result_hash=('b' * 64)}
            $ledgerTimestampSerialized = $ledgerTimestampRow | ConvertTo-Json -Compress
            $ledgerTimestampRoundTrip = $ledgerTimestampSerialized | ConvertFrom-Json
            if ($ledgerTimestampSerialized -eq ($ledgerTimestampRoundTrip | ConvertTo-Json -Compress)) { throw 'Ledger timestamp fixture did not reproduce raw JSON representation drift.' }
            if ((Get-ExchangeDurableObjectHash -Payload $ledgerTimestampRow) -ne (Get-ExchangeDurableObjectHash -Payload $ledgerTimestampRoundTrip)) { throw 'Durable ledger row comparison changed after timestamp JSON rehydration.' }
            $reorderedLedgerRow = [ordered]@{}
            foreach ($property in @($ledgerTimestampRoundTrip.PSObject.Properties | Sort-Object Name -Descending)) { $reorderedLedgerRow[$property.Name] = $property.Value }
            if ((Get-ExchangeDurableObjectHash -Payload $ledgerTimestampRow) -ne (Get-ExchangeDurableObjectHash -Payload $reorderedLedgerRow)) { throw 'Durable ledger row comparison changed when keys were reordered.' }
            $changedLedgerValue = $ledgerTimestampRoundTrip | ConvertTo-Json -Compress | ConvertFrom-Json
            $changedLedgerValue.result_hash = ('c' * 64)
            if ((Get-ExchangeDurableObjectHash -Payload $ledgerTimestampRow) -eq (Get-ExchangeDurableObjectHash -Payload $changedLedgerValue)) { throw 'Durable ledger row comparison ignored a changed bound value.' }
            $changedLedgerId = $ledgerTimestampRoundTrip | ConvertTo-Json -Compress | ConvertFrom-Json
            $changedLedgerId.item_id = 'other-item'
            if ((Get-ExchangeDurableObjectHash -Payload $ledgerTimestampRow) -eq (Get-ExchangeDurableObjectHash -Payload $changedLedgerId)) { throw 'Durable ledger row comparison ignored a changed item identity.' }
            $offsetTimestamp = [DateTimeOffset]::ParseExact('2026-08-15T05:30:00.0000000-05:00', 'o', [Globalization.CultureInfo]::InvariantCulture)
            $equivalentUtcTimestamp = [DateTimeOffset]::ParseExact('2026-08-15T10:30:00.0000000+00:00', 'o', [Globalization.CultureInfo]::InvariantCulture)
            if ((Get-ExchangeDurableObjectHash -Payload ([ordered]@{value=$offsetTimestamp})) -ne (Get-ExchangeDurableObjectHash -Payload ([ordered]@{value=$equivalentUtcTimestamp}))) {
                throw 'Durable exchange hash did not normalize equivalent offset timestamps to UTC.'
            }
            $changedTimestamp = $equivalentUtcTimestamp.AddSeconds(1)
            if ((Get-ExchangeDurableObjectHash -Payload ([ordered]@{value=$equivalentUtcTimestamp})) -eq (Get-ExchangeDurableObjectHash -Payload ([ordered]@{value=$changedTimestamp}))) {
                throw 'Durable exchange hash ignored a changed timestamp.'
            }
            if ((ConvertTo-ExchangeDurableCanonicalJson -Value 'release-2026-08-15') -ne '"release-2026-08-15"') { throw 'Durable exchange canonicalization changed an ordinary non-date string.' }
            $shapeHashes = @(
                Get-ExchangeDurableObjectHash -Payload ([ordered]@{ value=@() })
                Get-ExchangeDurableObjectHash -Payload ([ordered]@{ value=@('only') })
                Get-ExchangeDurableObjectHash -Payload ([ordered]@{ value='only' })
                Get-ExchangeDurableObjectHash -Payload ([ordered]@{ value=$true })
                Get-ExchangeDurableObjectHash -Payload ([ordered]@{ value='true' })
                Get-ExchangeDurableObjectHash -Payload ([ordered]@{ value=$null })
                Get-ExchangeDurableObjectHash -Payload ([ordered]@{ value=1 })
                Get-ExchangeDurableObjectHash -Payload ([ordered]@{ value='1' })
            )
            if (@($shapeHashes | Sort-Object -Unique).Count -ne $shapeHashes.Count) { throw 'Durable exchange hash collapsed empty, singleton, boolean, null, numeric, or string JSON semantics.' }
            foreach ($unsupportedCanonicalValue in @([double]::NaN, [double]::PositiveInfinity, [Guid]::NewGuid(), [TimeSpan]::FromSeconds(1), [DateTime]::SpecifyKind([DateTime]::UtcNow, [DateTimeKind]::Unspecified))) {
                $unsupportedRejected = $false
                try { [void](Get-ExchangeDurableObjectHash -Payload ([ordered]@{value=$unsupportedCanonicalValue})) } catch { $unsupportedRejected = $true }
                if (-not $unsupportedRejected) { throw 'Durable exchange hash accepted a nonfinite or unsupported value.' }
            }

            $exchangeApplyScript = (Resolve-Path './scripts/exchange/apply_approved_exchange.ps1').Path
            $pwshCommand = (Get-Command pwsh -ErrorAction Stop).Source
            $assertDurableJournalDigest = {
                param([object]$Journal)
                $payload = [ordered]@{}
                foreach ($property in $Journal.PSObject.Properties) { if ($property.Name -ne 'journal_digest') { $payload[$property.Name] = $property.Value } }
                if ([string]$Journal.journal_digest -notmatch '^[a-f0-9]{64}$' -or (Get-ExchangeDurableObjectHash -Payload $payload) -ne [string]$Journal.journal_digest) {
                    throw 'Durable transaction journal digest was not canonical or did not bind the complete journal state.'
                }
            }
            $runAbruptExchangeChild = {
                param([string]$Repo, [string]$Kit, [string]$Proposal, [string]$Point, [string]$Report)
                $startInfo = [Diagnostics.ProcessStartInfo]::new()
                $startInfo.FileName = $pwshCommand
                $startInfo.UseShellExecute = $false
                $startInfo.RedirectStandardOutput = $true
                $startInfo.RedirectStandardError = $true
                foreach ($argument in @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$exchangeApplyScript,'-RepoRoot',$Repo,'-RepoKitRoot',$Kit,'-ProposalPath',$Proposal,'-ProposalType','auto','-ReportPath',$Report,'-Execute','-ApprovalToken','APPROVED','-AllowOverwrite')) { $startInfo.ArgumentList.Add($argument) }
                $startInfo.Environment['REPO_KIT_EXCHANGE_TEST_CRASH_ENABLED'] = '1'
                $startInfo.Environment['REPO_KIT_EXCHANGE_TEST_CRASH_POINT'] = $Point
                $startInfo.Environment['TEMP'] = $env:TEMP
                $startInfo.Environment['TMP'] = $env:TEMP
                $process = [Diagnostics.Process]::Start($startInfo)
                $stdout = $process.StandardOutput.ReadToEndAsync()
                $stderr = $process.StandardError.ReadToEndAsync()
                $process.WaitForExit()
                [void]$stdout.Result
                [void]$stderr.Result
                if ($process.ExitCode -eq 0) { throw "Abrupt exchange child did not terminate at $Point." }
            }
            $runDurableCrashFixture = {
                param([ValidateSet('import','export')][string]$Direction, [string]$Point, [ValidateSet('none','target','ledger')][string]$TamperMode = 'none')
                $root = Join-Path $env:TEMP ("exchange_durable_${Direction}_${Point}_${TamperMode}_" + [Guid]::NewGuid().ToString('N'))
                $fixtureRepo = Join-Path $root 'repo'
                $fixtureKit = Join-Path $root 'kit'
                $diagnosticPath = Join-Path $root 'private-recovery-diagnostic.json'
                $previousDiagnosticFlag = $env:REPO_KIT_EXCHANGE_TEST_CRASH
                $previousDiagnosticPath = $env:REPO_KIT_EXCHANGE_TEST_DIAGNOSTIC_PATH
                $fixtureSucceeded = $false
                $env:REPO_KIT_EXCHANGE_TEST_CRASH = '1'
                $env:REPO_KIT_EXCHANGE_TEST_DIAGNOSTIC_PATH = $diagnosticPath
                $getDiagnosticFingerprint = { if (Test-Path -LiteralPath $diagnosticPath -PathType Leaf) { Get-ExchangeFileHash -Path $diagnosticPath } else { 'diagnostic-not-written' } }
                $assertPublicDiagnostic = {
                    param([object]$Report, [string]$Markdown, [string]$ExpectedClass)
                    $fingerprint = & $getDiagnosticFingerprint
                    $json = $Report | ConvertTo-Json -Depth 20 -Compress
                    $privateRootToken = Split-Path -Leaf $root
                    $privateDiagnosticToken = Split-Path -Leaf $diagnosticPath
                    if ($fingerprint -notmatch '^[a-f0-9]{64}$' -or
                        [string]$Report.diagnostic_class -ne $ExpectedClass -or
                        [string]$Report.diagnostic_fingerprint -ne $fingerprint -or
                        -not $Markdown.Contains("diagnostic_class: ``$ExpectedClass``") -or
                        -not $Markdown.Contains("diagnostic_fingerprint: ``$fingerprint``") -or
                        $json.Contains($root) -or $Markdown.Contains($root) -or
                        $json.Contains($privateRootToken) -or $Markdown.Contains($privateRootToken) -or
                        $json.Contains($privateDiagnosticToken) -or $Markdown.Contains($privateDiagnosticToken) -or
                        $json -match 'IOException|UnauthorizedAccessException|SecurityException|JsonReaderException|JsonSerializationException|JsonException|0x[0-9A-Fa-f]+' -or
                        $Markdown -match 'IOException|UnauthorizedAccessException|SecurityException|JsonReaderException|JsonSerializationException|JsonException|0x[0-9A-Fa-f]+') {
                        throw "Public recovery diagnostic evidence was inconsistent or disclosed private exception detail: class=$($Report.diagnostic_class) fingerprint=$fingerprint"
                    }
                }
                try {
                    New-Item -ItemType Directory -Force -Path (Join-Path $fixtureRepo '.repo-kit'),(Join-Path $fixtureKit 'repo-standards/exchange') | Out-Null
                    git -C $fixtureRepo init --quiet
                    if ($LASTEXITCODE -ne 0) { throw 'Could not initialize durable recovery fixture.' }
                    '.repo-kit-local/' | Set-Content -LiteralPath (Join-Path $fixtureRepo '.gitignore') -NoNewline
                    $ledger = Join-Path $fixtureRepo '.repo-kit/exchange-ledger.jsonl'
                    Write-ExchangeJsonFile -Path (Join-Path $fixtureRepo '.repo-kit/exchange.json') -Payload ([ordered]@{ version=2; ledger=[ordered]@{path='.repo-kit/exchange-ledger.jsonl'}; recovery=[ordered]@{mode='require-explicit';journal_root='.repo-kit-local/exchange/transactions'} })
                    if ($Direction -eq 'import') {
                        New-Item -ItemType Directory -Force -Path (Join-Path $fixtureKit 'source'),(Join-Path $fixtureRepo 'dest') | Out-Null
                        'new-one' | Set-Content -LiteralPath (Join-Path $fixtureKit 'source/one.txt') -NoNewline
                        'new-two' | Set-Content -LiteralPath (Join-Path $fixtureKit 'source/two.txt') -NoNewline
                        'old-one' | Set-Content -LiteralPath (Join-Path $fixtureRepo 'dest/one.txt') -NoNewline
                        Write-ExchangeJsonFile -Path (Join-Path $fixtureKit 'repo-standards/exchange/default_items.json') -Payload ([ordered]@{version=2;items=@([ordered]@{id='one';source_path='source/one.txt';target_path='dest/one.txt';category='fixture';description='Durable recovery first import fixture.';bundle_id='';requires=@()},[ordered]@{id='two';source_path='source/two.txt';target_path='dest/two.txt';category='fixture';description='Durable recovery second import fixture.';bundle_id='';requires=@()})})
                        $proposal = Join-Path $fixtureRepo 'proposal.json'
                        & ./scripts/exchange/propose_imports.ps1 -RepoRoot $fixtureRepo -RepoKitRoot $fixtureKit -OutputJson $proposal -OutputMarkdown (Join-Path $fixtureRepo 'proposal.md') -DestinationOnlyPolicy remove
                        $targetOne = Join-Path $fixtureRepo 'dest/one.txt'
                        $targetTwo = Join-Path $fixtureRepo 'dest/two.txt'
                    }
                    else {
                        New-Item -ItemType Directory -Force -Path (Join-Path $fixtureRepo 'exports'),(Join-Path $fixtureKit 'exports') | Out-Null
                        'new-one' | Set-Content -LiteralPath (Join-Path $fixtureRepo 'exports/one.txt') -NoNewline
                        'new-two' | Set-Content -LiteralPath (Join-Path $fixtureRepo 'exports/two.txt') -NoNewline
                        'old-one' | Set-Content -LiteralPath (Join-Path $fixtureKit 'exports/one.txt') -NoNewline
                        $catalogPath = Join-Path $fixtureRepo '.repo-kit/catalog.json'
                        Write-ExchangeJsonFile -Path $catalogPath -Payload ([ordered]@{candidates=@([ordered]@{path='exports/one.txt';category='fixture';privacy_classification='public';description='Durable recovery first export fixture.';bundle_id='';requires=@()},[ordered]@{path='exports/two.txt';category='fixture';privacy_classification='public';description='Durable recovery second export fixture.';bundle_id='';requires=@()})})
                        $proposal = Join-Path $fixtureRepo '.repo-kit/export-proposal.json'
                        & ./scripts/exchange/propose_exports.ps1 -RepoRoot $fixtureRepo -RepoKitRoot $fixtureKit -CatalogJson $catalogPath -OutputJson $proposal -OutputMarkdown (Join-Path $fixtureRepo '.repo-kit/export-proposal.md') -DestinationOnlyPolicy remove
                        $targetOne = Join-Path $fixtureKit 'exports/one.txt'
                        $targetTwo = Join-Path $fixtureKit 'exports/two.txt'
                    }
                    & $runAbruptExchangeChild $fixtureRepo $fixtureKit $proposal $Point (Join-Path $fixtureRepo 'crash-report.json')
                    $journalFiles = @(Get-ChildItem -LiteralPath (Join-Path $fixtureRepo '.repo-kit-local/exchange/transactions') -Filter journal.json -Recurse -File)
                    if ($journalFiles.Count -ne 1) { throw 'Abrupt exchange did not leave exactly one durable journal.' }
                    $journal = Read-ExchangeJsonFile -Path $journalFiles[0].FullName
                    & $assertDurableJournalDigest $journal
                    $transactionId = [string]$journal.transaction_id
                    $lockPayload = Read-ExchangeJsonFile -Path (Join-Path $fixtureRepo '.repo-kit/exchange.lock')
                    if ([string]$lockPayload.transaction_id -ne $transactionId -or [string]$lockPayload.journal_path -notmatch [regex]::Escape("/$transactionId/journal.json") -or [string]$lockPayload.binding_digest -ne [string]$journal.binding_digest) { throw 'Orphan lock is not bound to its durable journal.' }
                    if ($Direction -eq 'import' -and $Point -eq 'after_prepared') {
                        $secondId = [Guid]::NewGuid().ToString('N')
                        $secondDirectory = Join-Path (Split-Path -Parent $journalFiles[0].DirectoryName) $secondId
                        Copy-Item -LiteralPath $journalFiles[0].DirectoryName -Destination $secondDirectory -Recurse
                        $secondJournalPath = Join-Path $secondDirectory 'journal.json'
                        $secondJournal = Read-ExchangeJsonFile -Path $secondJournalPath
                        $secondJournal.transaction_id = $secondId
                        Write-ExchangeJsonFile -Path $secondJournalPath -Payload $secondJournal
                        $ambiguityReport = Join-Path $fixtureRepo 'recovery-ambiguous.json'
                        & $exchangeApplyScript -RepoRoot $fixtureRepo -RepoKitRoot $fixtureKit -ReportPath $ambiguityReport
                        $ambiguity = Read-ExchangeJsonFile -Path $ambiguityReport
                        if ($LASTEXITCODE -ne 3 -or [string]$ambiguity.reason_code -ne 'recovery_ambiguous') { throw 'Multiple active journals did not fail closed as ambiguous.' }
                        Remove-Item -LiteralPath $secondDirectory -Recurse -Force

                        $tamperedLock = $lockPayload | ConvertTo-Json -Depth 10 | ConvertFrom-Json
                        $tamperedLock.binding_digest = ('0' * 64)
                        Write-ExchangeJsonFile -Path (Join-Path $fixtureRepo '.repo-kit/exchange.lock') -Payload $tamperedLock
                        $tamperRejected = $false
                        $tamperReportPath = Join-Path $fixtureRepo 'recovery-tamper.json'
                        try { & $exchangeApplyScript -RepoRoot $fixtureRepo -RepoKitRoot $fixtureKit -RecoveryAction auto -ApprovalToken APPROVED -ReportPath $tamperReportPath; $tamperRejected = ($LASTEXITCODE -eq 3) } catch { $tamperRejected = $true }
                        $tamperReport = Read-ExchangeJsonFile -Path $tamperReportPath
                        $tamperMarkdownPath = [IO.Path]::ChangeExtension($tamperReportPath, '.md')
                        $tamperMarkdown = Get-Content -LiteralPath $tamperMarkdownPath -Raw
                        & $assertPublicDiagnostic $tamperReport $tamperMarkdown 'other'
                        if (-not $tamperRejected -or (& $getDiagnosticFingerprint) -notmatch '^[a-f0-9]{64}$' -or [string]$tamperReport.transaction_id -ne $transactionId -or -not [bool]$tamperReport.recovery_required -or -not [bool]$tamperReport.durable_crash_journal -or [string]$tamperReport.guarantee_scope -ne 'durable_journal_recovery' -or [string]$tamperReport.recovery_action -ne 'auto' -or -not $tamperMarkdown.Contains("transaction_id: ``$transactionId``") -or -not $tamperMarkdown.Contains('recovery_required: `true`') -or -not $tamperMarkdown.Contains('durable_crash_journal: `true`') -or -not $tamperMarkdown.Contains('guarantee_scope: `durable_journal_recovery`') -or -not $tamperMarkdown.Contains('recovery_action: `auto`') -or (Get-Content -LiteralPath $tamperReportPath -Raw).Contains($root) -or $tamperMarkdown.Contains($root) -or (Get-Content -LiteralPath $targetOne -Raw) -ne 'old-one' -or (Test-Path -LiteralPath $targetTwo) -or -not (Test-Path -LiteralPath (Join-Path $fixtureRepo '.repo-kit/exchange.lock'))) { throw "Unambiguous recovery failure did not preserve its selected transaction identity and public-safe evidence; diagnostic_fingerprint=$(& $getDiagnosticFingerprint)" }
                        Write-ExchangeJsonFile -Path (Join-Path $fixtureRepo '.repo-kit/exchange.lock') -Payload $lockPayload
                        if (Test-Path -LiteralPath $diagnosticPath) { Remove-Item -LiteralPath $diagnosticPath -Force }
                    }
                    if ($TamperMode -eq 'target') {
                        'target-tamper' | Set-Content -LiteralPath $targetTwo -NoNewline
                        $targetTamperRejected = $false
                        $targetTamperReportPath = Join-Path $fixtureRepo 'recovery-target-tamper.json'
                        try { & $exchangeApplyScript -RepoRoot $fixtureRepo -RepoKitRoot $fixtureKit -RecoveryAction rollback -TransactionId $transactionId -ApprovalToken APPROVED -ReportPath $targetTamperReportPath; $targetTamperRejected = ($LASTEXITCODE -eq 3) } catch { $targetTamperRejected = $true }
                        $targetTamperReport = Read-ExchangeJsonFile -Path $targetTamperReportPath
                        $targetTamperMarkdown = Get-Content -LiteralPath ([IO.Path]::ChangeExtension($targetTamperReportPath, '.md')) -Raw
                        & $assertPublicDiagnostic $targetTamperReport $targetTamperMarkdown 'binding-invalid'
                        $retainedJournal = Read-ExchangeJsonFile -Path $journalFiles[0].FullName
                        if (-not $targetTamperRejected -or (& $getDiagnosticFingerprint) -notmatch '^[a-f0-9]{64}$' -or [string]$targetTamperReport.transaction_id -ne $transactionId -or -not [bool]$targetTamperReport.recovery_required -or [string]$targetTamperReport.reason_code -ne 'recovery_invalid' -or (Get-Content -LiteralPath $targetOne -Raw) -ne 'new-one' -or (Get-Content -LiteralPath $targetTwo -Raw) -ne 'target-tamper' -or [string]$retainedJournal.state -ne 'applying' -or -not (Test-Path -LiteralPath (Join-Path $fixtureRepo '.repo-kit/exchange.lock'))) { throw "Target tamper did not emit recovery-aware failure before all mutation or retain durable evidence; diagnostic_fingerprint=$(& $getDiagnosticFingerprint)" }
                        Remove-Item -LiteralPath $targetTwo -Force
                        if (Test-Path -LiteralPath $diagnosticPath) { Remove-Item -LiteralPath $diagnosticPath -Force }
                    }
                    if ($TamperMode -eq 'ledger') {
                        $ledgerBeforeTamper = Get-Content -LiteralPath $ledger -Raw
                        'ledger-tamper' | Set-Content -LiteralPath $ledger -NoNewline
                        $ledgerTamperRejected = $false
                        $ledgerTamperReportPath = Join-Path $fixtureRepo 'recovery-ledger-tamper.json'
                        try { & $exchangeApplyScript -RepoRoot $fixtureRepo -RepoKitRoot $fixtureKit -RecoveryAction rollback -TransactionId $transactionId -ApprovalToken APPROVED -ReportPath $ledgerTamperReportPath; $ledgerTamperRejected = ($LASTEXITCODE -eq 3) } catch { $ledgerTamperRejected = $true }
                        $ledgerTamperReport = Read-ExchangeJsonFile -Path $ledgerTamperReportPath
                        $ledgerTamperMarkdown = Get-Content -LiteralPath ([IO.Path]::ChangeExtension($ledgerTamperReportPath, '.md')) -Raw
                        & $assertPublicDiagnostic $ledgerTamperReport $ledgerTamperMarkdown 'binding-invalid'
                        $retainedJournal = Read-ExchangeJsonFile -Path $journalFiles[0].FullName
                        if (-not $ledgerTamperRejected -or (& $getDiagnosticFingerprint) -notmatch '^[a-f0-9]{64}$' -or [string]$ledgerTamperReport.transaction_id -ne $transactionId -or -not [bool]$ledgerTamperReport.recovery_required -or [string]$ledgerTamperReport.reason_code -ne 'recovery_invalid' -or (Get-Content -LiteralPath $targetOne -Raw) -ne 'new-one' -or (Get-Content -LiteralPath $targetTwo -Raw) -ne 'new-two' -or (Get-Content -LiteralPath $ledger -Raw) -ne 'ledger-tamper' -or [string]$retainedJournal.state -ne 'ledger_persisting' -or -not (Test-Path -LiteralPath (Join-Path $fixtureRepo '.repo-kit/exchange.lock'))) { throw "Ledger tamper did not emit recovery-aware failure before all mutation or retain durable evidence; diagnostic_fingerprint=$(& $getDiagnosticFingerprint)" }
                        Write-ExchangeTextFile -Path $ledger -Content $ledgerBeforeTamper
                        if (Test-Path -LiteralPath $diagnosticPath) { Remove-Item -LiteralPath $diagnosticPath -Force }
                    }
                    $statusReport = Join-Path $fixtureRepo 'recovery-status.json'
                    & $exchangeApplyScript -RepoRoot $fixtureRepo -RepoKitRoot $fixtureKit -RecoveryAction status -TransactionId $transactionId -ReportPath $statusReport
                    if ($LASTEXITCODE -ne 0 -or -not (Read-ExchangeJsonFile -Path $statusReport).recovery_required) { throw "Recovery status did not report the interrupted transaction; diagnostic_fingerprint=$(& $getDiagnosticFingerprint)" }
                    & $exchangeApplyScript -RepoRoot $fixtureRepo -RepoKitRoot $fixtureKit -ProposalPath $proposal -ReportPath (Join-Path $fixtureRepo 'restart-report.json')
                    if ($LASTEXITCODE -ne 3) { throw 'Normal restart did not stop with recovery_required exit 3.' }
                    $recoveryReport = Join-Path $fixtureRepo 'recovery-auto.json'
                    & $exchangeApplyScript -RepoRoot $fixtureRepo -RepoKitRoot $fixtureKit -RecoveryAction auto -TransactionId $transactionId -ApprovalToken APPROVED -ReportPath $recoveryReport
                    if ($LASTEXITCODE -ne 0) { throw 'Approved automatic recovery failed.' }
                    $recovery = Read-ExchangeJsonFile -Path $recoveryReport
                    $terminalJournal = Read-ExchangeJsonFile -Path $journalFiles[0].FullName
                    & $assertDurableJournalDigest $terminalJournal
                    $expectsRollback = $Point -in @('after_prepared','after_first_target')
                    $expectedState = if ($expectsRollback) { 'rolled_back' } else { 'committed' }
                    if ([string]$recovery.transaction_status -ne $expectedState -or (Get-Content -LiteralPath $recoveryReport -Raw).Contains($root)) { throw 'Recovery report status/privacy contract failed.' }
                    $terminalLockFixture = ($Direction -eq 'import' -and $Point -eq 'after_prepared' -and $TamperMode -eq 'none') -or ($Direction -eq 'export' -and $Point -eq 'after_targets_verified' -and $TamperMode -eq 'none')
                    if ($terminalLockFixture) {
                        Write-ExchangeJsonFile -Path (Join-Path $fixtureRepo '.repo-kit/exchange.lock') -Payload ([ordered]@{schema_version='repo-kit.exchange-lock.v1';transaction_id=$transactionId;journal_path=".repo-kit-local/exchange/transactions/$transactionId/journal.json";binding_digest=[string]$journal.binding_digest})
                        $terminalStatusPath = Join-Path $fixtureRepo 'terminal-lock-status.json'
                        & $exchangeApplyScript -RepoRoot $fixtureRepo -RepoKitRoot $fixtureKit -RecoveryAction status -TransactionId $transactionId -ReportPath $terminalStatusPath
                        $terminalStatus = Read-ExchangeJsonFile -Path $terminalStatusPath
                        if ($LASTEXITCODE -ne 0 -or [string]$terminalStatus.transaction_status -ne $expectedState -or [string]$terminalStatus.reason_code -ne 'terminal_lock_cleanup_required' -or -not [bool]$terminalStatus.recovery_required -or -not (Test-Path -LiteralPath (Join-Path $fixtureRepo '.repo-kit/exchange.lock'))) { throw 'Terminal orphan lock status was not read-only and recovery-aware.' }
                    }
                    if ($expectsRollback) {
                        if ((Get-Content -LiteralPath $targetOne -Raw) -ne 'old-one' -or (Test-Path -LiteralPath $targetTwo) -or (Test-Path -LiteralPath $ledger)) { throw 'Durable rollback left a target or ledger mutation.' }
                        $terminalRollbackReport = Join-Path $fixtureRepo 'recovery-rollback-again.json'
                        & $exchangeApplyScript -RepoRoot $fixtureRepo -RepoKitRoot $fixtureKit -RecoveryAction rollback -TransactionId $transactionId -ApprovalToken APPROVED -ReportPath $terminalRollbackReport
                        $terminalRollback = Read-ExchangeJsonFile -Path $terminalRollbackReport
                        if ($LASTEXITCODE -ne 0 -or [string]$terminalRollback.transaction_status -ne 'rolled_back' -or [string]$terminalRollback.reason_code -ne 'already_recovered') { throw 'Repeated durable rollback did not return the stable terminal receipt.' }
                    }
                    else {
                        if ((Get-Content -LiteralPath $targetOne -Raw) -ne 'new-one' -or (Get-Content -LiteralPath $targetTwo -Raw) -ne 'new-two') { throw 'Durable resume did not finish all targets.' }
                        $ledgerRows = @(Get-Content -LiteralPath $ledger | ForEach-Object { $_ | ConvertFrom-Json })
                        if ($ledgerRows.Count -ne 2 -or @($ledgerRows | ForEach-Object { "$($_.transaction_id)|$($_.item_id)" } | Sort-Object -Unique).Count -ne 2) { throw 'Durable resume ledger rows are not idempotent transaction/item records.' }
                        & $exchangeApplyScript -RepoRoot $fixtureRepo -RepoKitRoot $fixtureKit -RecoveryAction resume -TransactionId $transactionId -ApprovalToken APPROVED -ReportPath (Join-Path $fixtureRepo 'recovery-resume-again.json')
                        $terminalReport = Read-ExchangeJsonFile -Path (Join-Path $fixtureRepo 'recovery-resume-again.json')
                        if ($LASTEXITCODE -ne 0 -or [string]$terminalReport.reason_code -ne 'already_recovered' -or @(Get-Content -LiteralPath $ledger).Count -ne 2) { throw 'Repeated durable resume did not return a stable terminal receipt or duplicated ledger rows.' }
                    }
                    if (Test-Path -LiteralPath (Join-Path $fixtureRepo '.repo-kit/exchange.lock')) { throw 'Recovery left its orphan lock behind.' }
                    $fixtureSucceeded = $true
                }
                finally {
                    if ($null -eq $previousDiagnosticFlag) { Remove-Item -LiteralPath Env:REPO_KIT_EXCHANGE_TEST_CRASH -ErrorAction SilentlyContinue } else { $env:REPO_KIT_EXCHANGE_TEST_CRASH = $previousDiagnosticFlag }
                    if ($null -eq $previousDiagnosticPath) { Remove-Item -LiteralPath Env:REPO_KIT_EXCHANGE_TEST_DIAGNOSTIC_PATH -ErrorAction SilentlyContinue } else { $env:REPO_KIT_EXCHANGE_TEST_DIAGNOSTIC_PATH = $previousDiagnosticPath }
                    if ($fixtureSucceeded -and (Test-Path -LiteralPath $root)) { Remove-Item -LiteralPath $root -Recurse -Force }
                }
            }
            foreach ($direction in @('import','export')) {
                foreach ($point in @('after_prepared','after_first_target','after_targets_verified','after_ledger_persisting')) { & $runDurableCrashFixture $direction $point }
            }
            & $runDurableCrashFixture import after_first_target target
            & $runDurableCrashFixture export after_ledger_persisting ledger
            $journalBoundaryRoot = Join-Path $env:TEMP ('exchange_journal_boundary_' + [Guid]::NewGuid().ToString('N'))
            try {
                New-Item -ItemType Directory -Force -Path $journalBoundaryRoot | Out-Null
                git -C $journalBoundaryRoot init --quiet
                '.repo-kit-local/' | Set-Content -LiteralPath (Join-Path $journalBoundaryRoot '.gitignore') -NoNewline
                $resolvedJournal = Resolve-ExchangeJournalRoot -RepoRoot $journalBoundaryRoot -JournalRoot '.repo-kit-local/exchange/transactions/team-a' -RequireIgnored
                if ($resolvedJournal.relative_path -ne '.repo-kit-local/exchange/transactions/team-a') { throw 'Contained journal subdirectory was not preserved.' }
                foreach ($invalidJournalRoot in @('.codex-cache/exchange/transactions','.repo-kit-local/exchange/transactions/../tracked','.repo-kit-local\exchange\transactions','C:/exchange-journal')) {
                    $journalRejected = $false
                    try { [void](Resolve-ExchangeJournalRoot -RepoRoot $journalBoundaryRoot -JournalRoot $invalidJournalRoot -RequireIgnored) } catch { $journalRejected = $true }
                    if (-not $journalRejected) { throw "Unsafe transaction journal root was accepted: $invalidJournalRoot" }
                }
                $outsideJournal = Join-Path $env:TEMP ('exchange_journal_outside_' + [Guid]::NewGuid().ToString('N'))
                New-Item -ItemType Directory -Force -Path $outsideJournal,(Join-Path $journalBoundaryRoot '.repo-kit-local/exchange') | Out-Null
                try {
                    $linkCreated = $false
                    try {
                        New-Item -ItemType SymbolicLink -Path (Join-Path $journalBoundaryRoot '.repo-kit-local/exchange/transactions') -Target $outsideJournal -ErrorAction Stop | Out-Null
                        $linkCreated = $true
                    }
                    catch { Write-Output "exchange journal symlink fixture skipped: $($_.Exception.GetType().Name)" }
                    if ($linkCreated) {
                    $linkRejected = $false
                    try { [void](Resolve-ExchangeJournalRoot -RepoRoot $journalBoundaryRoot -RequireIgnored) } catch { $linkRejected = $true }
                    if (-not $linkRejected) { throw 'Symlinked transaction journal root was accepted.' }
                    }
                }
                finally { if (Test-Path -LiteralPath $outsideJournal) { Remove-Item -LiteralPath $outsideJournal -Recurse -Force } }
            }
            finally { if (Test-Path -LiteralPath $journalBoundaryRoot) { Remove-Item -LiteralPath $journalBoundaryRoot -Recurse -Force } }
            $exchangeIntakeReport = Join-Path $env:TEMP 'reuse_intake_wave_smoke.json'
            $exchangeIntakeReportMd = Join-Path $env:TEMP 'reuse_intake_wave_smoke.md'
            $exchangeIntakeRepoList = Join-Path $env:TEMP 'reuse_intake_wave_smoke_repos.txt'
            (Resolve-Path -LiteralPath .).Path | Set-Content -LiteralPath $exchangeIntakeRepoList -Encoding utf8
            & ./scripts/exchange/run_full_intake_wave.ps1 -RepoListPath $exchangeIntakeRepoList -RepoKitRoot . -OutputJson $exchangeIntakeReport -OutputMarkdown $exchangeIntakeReportMd
            & ./scripts/exchange/check_drift.ps1 -RepoRoot . -RepoKitRoot . -NoWrite
        }
    },
    [pscustomobject]@{
        Name = 'Rollout prepare smoke checks'
        Patterns = @('^scripts/rollout/prepare_repo_updates\.ps1$', '^docs/AUTO_APPLY_POLICY\.md$', '^archive/local-reports/prepared_repo_updates_report\.schema\.json$')
        Exists = { Test-Path 'scripts/rollout/prepare_repo_updates.ps1' }
        Command = {
            $driftPath = Join-Path $env:TEMP 'prepared_repo_updates_smoke_drift.json'
            $reportPath = Join-Path $env:TEMP 'prepared_repo_updates_smoke_report.json'
            $markdownPath = Join-Path $env:TEMP 'prepared_repo_updates_smoke_report.md'
            $repoPath = (Resolve-Path -LiteralPath .).Path
            $payload = [ordered]@{
                schema_version = 1
                generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
                repos = @(
                    [ordered]@{
                        repo_name = 'repo-kit-smoke'
                        repo_path = $repoPath
                        pack_manifest_path = (Join-Path $repoPath 'repo-standards/pack_versions.json')
                        pack_assessments = @(
                            [ordered]@{ pack_id = 'repo-standards'; installed_version = '0.0.0'; target_version = '0.1.0' }
                        )
                    }
                )
                upgrade_plan = [ordered]@{
                    safe_auto_candidates = @(
                        [ordered]@{ repo_name = 'repo-kit-smoke'; packs = @('repo-standards') }
                    )
                    manual_followups = @()
                }
            }
            $payload | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $driftPath -Encoding utf8
            & ./scripts/rollout/prepare_repo_updates.ps1 -RepoRoot . -DriftReportPath $driftPath -OutputRoot (Join-Path $env:TEMP 'prepared_updates_smoke') -ReportPath $reportPath -MarkdownPath $markdownPath -RolloutRing general
            $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
            if ($report.mode -ne 'plan') {
                throw "Rollout prepare smoke expected plan mode, got $($report.mode)."
            }
            if (-not $report.approval_gate_required) {
                throw 'Rollout prepare smoke expected approval_gate_required=true.'
            }
            if ($report.summary.repos_prepared -lt 1) {
                throw 'Rollout prepare smoke expected at least one prepared repo.'
            }
            if ([string]$report.repos[0].rollout_ring -ne 'general') {
                throw 'Rollout prepare smoke expected default general rollout ring.'
            }
            if (-not (Test-Path -LiteralPath $markdownPath)) {
                throw "Rollout prepare smoke missing markdown report: $markdownPath"
            }
            if ([string]::IsNullOrWhiteSpace([string]$report.impact_preview_path) -or -not (Test-Path -LiteralPath ([string]$report.impact_preview_path))) {
                throw 'Rollout prepare smoke missing impact preview report.'
            }
            $impactPreview = Get-Content -LiteralPath ([string]$report.impact_preview_path) -Raw | ConvertFrom-Json
            if ($impactPreview.summary.repo_count -lt 1) {
                throw 'Rollout prepare smoke expected at least one impact preview row.'
            }
        }
    },
    [pscustomobject]@{
        Name = 'Downstream update watch smoke checks'
        Patterns = @('^scripts/sync/watch_downstream_updates\.ps1$', '^docs/DOWNSTREAM_UPDATE_WATCH\.md$', '^archive/local-reports/downstream_update_watch_report\.schema\.json$')
        Exists = { Test-Path 'scripts/sync/watch_downstream_updates.ps1' }
        Command = {
            $watchJson = Join-Path $env:TEMP 'downstream_update_watch_report.json'
            $watchMarkdown = Join-Path $env:TEMP 'downstream_update_watch_report.md'
            $watchSchema = Get-Content -LiteralPath archive/local-reports/downstream_update_watch_report.schema.json -Raw | ConvertFrom-Json
            if ($null -eq $watchSchema) {
                throw 'Downstream update watch schema did not parse.'
            }
            & ./scripts/sync/watch_downstream_updates.ps1 -RepoRoot . -RepoKitRoot . -OutputJson $watchJson -OutputMarkdown $watchMarkdown
            $watchReport = Get-Content -LiteralPath $watchJson -Raw | ConvertFrom-Json
            if ($watchReport.summary.relevant_updates -lt 0) {
                throw 'Downstream update watch smoke produced invalid relevant_updates count.'
            }
            if (-not (Test-Path -LiteralPath $watchMarkdown)) {
                throw "Downstream update watch smoke missing markdown report: $watchMarkdown"
            }
        }
    },
    [pscustomobject]@{
        Name = 'Secrets restore/check smoke checks'
        Patterns = @('^scripts/secrets/check_env_keys\.ps1$', '^docs/templates/secrets/restore_env_from_backup\.ps1$', '^docs/SECRETS_RESTORE_CHECKLIST\.md$', '^docs/SECRETS_BACKUP_POLICY\.md$')
        Exists = { (Test-Path 'scripts/secrets/check_env_keys.ps1') -and (Test-Path 'docs/templates/secrets/restore_env_from_backup.ps1') }
        Command = {
            $secretSmokeRoot = Join-Path '.codex-cache/tmp' 'secrets_restore_smoke'
            Remove-Item -LiteralPath $secretSmokeRoot -Recurse -Force -ErrorAction SilentlyContinue
            New-Item -ItemType Directory -Force -Path (Join-Path $secretSmokeRoot '.codex-cache/tmp') | Out-Host
            @'
API_TOKEN=
BOT_TOKEN=
'@ | Set-Content -LiteralPath (Join-Path $secretSmokeRoot '.env.example') -Encoding utf8
            @'
API_TOKEN=test-token
BOT_TOKEN=test-bot
'@ | Set-Content -LiteralPath (Join-Path $secretSmokeRoot '.env') -Encoding utf8
            & ./scripts/secrets/check_env_keys.ps1 -RepoRoot $secretSmokeRoot -EnvExamplePath .env.example -EnvPath .env
            $encrypted = Join-Path $secretSmokeRoot '.codex-cache/tmp/backup.env.enc'
            $plaintext = Join-Path $secretSmokeRoot '.codex-cache/tmp/plain.env'
            @'
API_TOKEN=restored-token
BOT_TOKEN=restored-bot
'@ | Set-Content -LiteralPath $plaintext -Encoding utf8
            'placeholder encrypted payload' | Set-Content -LiteralPath $encrypted -Encoding utf8
            & ./docs/templates/secrets/restore_env_from_backup.ps1 -EncryptedBackupPath $encrypted -OutputEnvPath (Join-Path $secretSmokeRoot '.codex-cache/tmp/restored.env') -Mode copy -PlaintextInputPath $plaintext
        }
    },
    [pscustomobject]@{
        Name = 'Tools manifest checks'
        Patterns = @('^tools/', '^scripts/tools/', '^docs/TOOLS_UPDATE_POLICY\.md$', '^tools/tools_manifest\.json$')
        Exists = { Test-Path 'scripts/lifecycle/check_tools_manifest.py' }
        Command = {
            python scripts/lifecycle/check_tools_manifest.py --repo-root .
        }
    },
    [pscustomobject]@{
        Name = 'Devcontainer template smoke checks'
        Patterns = @('^docs/templates/devcontainer/', '^docs/DEVCONTAINER_POLICY\.md$', '^scripts/bootstrap/install_devcontainer_template\.ps1$')
        Exists = { Test-Path 'scripts/bootstrap/install_devcontainer_template.ps1' }
        Command = {
            foreach ($templateName in @('base', 'python', 'powershell')) {
                $jsonPath = "docs/templates/devcontainer/$templateName/devcontainer.json"
                $postCreatePath = "docs/templates/devcontainer/$templateName/post-create.ps1"
                $config = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json
                if ([string]::IsNullOrWhiteSpace([string]$config.name)) {
                    throw "Devcontainer template missing name: $jsonPath"
                }
                if ([string]::IsNullOrWhiteSpace([string]$config.postCreateCommand)) {
                    throw "Devcontainer template missing postCreateCommand: $jsonPath"
                }
                if (-not (Test-Path -LiteralPath $postCreatePath -PathType Leaf)) {
                    throw "Devcontainer template missing post-create script: $postCreatePath"
                }
            }

            $devcontainerSmokeRoot = Join-Path $env:TEMP 'devcontainer_template_smoke'
            Remove-Item -LiteralPath $devcontainerSmokeRoot -Recurse -Force -ErrorAction SilentlyContinue
            New-Item -ItemType Directory -Force -Path $devcontainerSmokeRoot | Out-Host
            try {
                & ./scripts/bootstrap/install_devcontainer_template.ps1 -TargetRepo $devcontainerSmokeRoot -TemplateName base
                if ($LASTEXITCODE -ne 0) {
                    exit $LASTEXITCODE
                }
                if (-not (Test-Path -LiteralPath (Join-Path $devcontainerSmokeRoot '.devcontainer/devcontainer.json') -PathType Leaf)) {
                    throw 'Devcontainer smoke missing installed devcontainer.json.'
                }
                if (-not (Test-Path -LiteralPath (Join-Path $devcontainerSmokeRoot '.devcontainer/post-create.ps1') -PathType Leaf)) {
                    throw 'Devcontainer smoke missing installed post-create.ps1.'
                }
            }
            finally {
                Remove-Item -LiteralPath $devcontainerSmokeRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    },
    [pscustomobject]@{
        Name = 'Inventory checks'
        Patterns = @('^docs/INVENTORY\.(md|json)$', '^scripts/inventory/', '^scripts/lifecycle/check_repo_consistency\.py$', '^docs/README\.md$', '^docs/templates/README\.md$')
        Exists = { Test-Path 'scripts/inventory/generate_inventory.py' }
        Command = {
            python scripts/inventory/generate_inventory.py --repo-root . --check
        }
    },
    [pscustomobject]@{
        Name = 'Task-pack contract checks'
        Patterns = @(
            '^scripts/rollout/write_task_pack\.ps1$',
            '^scripts/status/next_work\.ps1$',
            '^codex-efficiency-kit/scripts/codex_(preflight|task_pack|todo_tasks)\.py$',
            '^tests/test_task_pack_freshness\.py$'
        )
        Exists = { Test-Path 'tests/test_task_pack_freshness.py' }
        Command = {
            python -m pytest -q tests/test_task_pack_freshness.py
        }
    },
    [pscustomobject]@{
        Name = 'Unsafe I/O checks'
        Patterns = @('^src/.*\.py$', '^scripts/.*\.py$', '^tests/.*\.py$', '^tools/.*\.py$')
        Exists = { Test-Path 'scripts/hooks/check_unsafe_io.py' }
        Command = {
            $pyFiles = @($changed | Where-Object { $_ -imatch '\.py$' })
            if ($pyFiles.Count -eq 0) {
                Write-Output 'No changed Python files for unsafe I/O checks.'
                return
            }
            python scripts/hooks/check_unsafe_io.py @pyFiles
        }
    },
    [pscustomobject]@{
        Name = 'Runtime footguns checks'
        Patterns = @('^src/.*\.(py|ps1)$', '^scripts/.*\.(py|ps1)$', '^tests/.*\.(py|ps1)$', '^tools/.*\.(py|ps1)$')
        Exists = { Test-Path 'scripts/hooks/check_runtime_footguns.py' }
        Command = {
            $candidateFiles = @($changed | Where-Object { $_ -imatch '\.(py|ps1)$' })
            if ($candidateFiles.Count -eq 0) {
                Write-Output 'No changed Python/PowerShell files for runtime footguns checks.'
                return
            }
            python scripts/hooks/check_runtime_footguns.py @candidateFiles
        }
    },
    [pscustomobject]@{
        Name = 'CLI help contract checks'
        Patterns = @('^scripts/hooks/check_cli_help_contracts\.py$', '^scripts/hooks/cli_help_contracts\.json$', '^scripts/hooks/cli_help_snapshots/.*\.txt$', '^scripts/lifecycle/(check_markdown_paths|check_repo_consistency|check_todo_format)\.py$')
        Exists = { Test-Path 'scripts/hooks/check_cli_help_contracts.py' }
        Command = {
            python scripts/hooks/check_cli_help_contracts.py --repo-root .
        }
    },
    [pscustomobject]@{
        Name = 'Structured log schema checks'
        Patterns = @('^scripts/lifecycle/check_log_schema\.py$', '^scripts/lifecycle/log_schema_contracts\.json$', '^tests/data/log_schema_samples/.*\.json$', '^docs/(REPO_SAFETY_STANDARD|REPO_SAFETY_00_REPO_KIT_DRAFT)\.md$')
        Exists = { Test-Path 'scripts/lifecycle/check_log_schema.py' }
        Command = {
            python scripts/lifecycle/check_log_schema.py --repo-root .
        }
    },
    [pscustomobject]@{
        Name = 'Local app launcher contract checks'
        Patterns = @('^repo-standards/local-app-launcher/', '^docs/local-app-launcher/', '^scripts/lifecycle/check_local_app_launcher_contracts\.py$', '^repo-standards/exchange/default_items\.json$')
        Exists = { Test-Path 'scripts/lifecycle/check_local_app_launcher_contracts.py' }
        Command = {
            python scripts/lifecycle/check_local_app_launcher_contracts.py --repo-root .
        }
    },
    [pscustomobject]@{
        Name = 'PowerShell hygiene checks'
        Patterns = @('^src/.*\.ps1$', '^scripts/.*\.ps1$', '^tests/.*\.ps1$', '^tools/.*\.ps1$', '^\.github/.*\.ps1$')
        Exists = { Test-Path 'scripts/hooks/check_powershell_hygiene.py' }
        Command = {
            $psFiles = @($changed | Where-Object { $_ -imatch '\.ps1$' })
            if ($psFiles.Count -eq 0) {
                Write-Output 'No changed PowerShell files for PowerShell hygiene checks.'
                return
            }
            python scripts/hooks/check_powershell_hygiene.py @psFiles
        }
    },
    [pscustomobject]@{
        Name = 'PowerShell ScriptAnalyzer checks'
        Patterns = @('^src/.*\.ps1$', '^scripts/.*\.ps1$', '^tests/.*\.ps1$', '^tools/.*\.ps1$', '^\.github/.*\.ps1$')
        Exists = { Test-Path 'scripts/hooks/check_powershell_scriptanalyzer.py' }
        Command = {
            $psFiles = @($changed | Where-Object { $_ -imatch '\.ps1$' })
            if ($psFiles.Count -eq 0) {
                Write-Output 'No changed PowerShell files for ScriptAnalyzer checks.'
                return
            }
            python scripts/hooks/check_powershell_scriptanalyzer.py @psFiles
        }
    },
    [pscustomobject]@{
        Name = 'Taskdoc lint checks'
        Patterns = @('^docs/CLINE_TASK_CURRENT\.md$', '^docs/templates/CLINE_TASK_CURRENT_template\.md$', '^scripts/lint/cline_task/')
        Exists = { (Test-Path 'scripts/lint/cline_task/cline_taskdoc_lint.py') -and (Test-Path 'docs/templates/CLINE_TASK_CURRENT_template.md') }
        Command = {
            python scripts/lint/cline_task/cline_taskdoc_lint.py --template docs/templates/CLINE_TASK_CURRENT_template.md --task docs/templates/CLINE_TASK_CURRENT_template.md --check
            if (Test-Path 'scripts/lint/cline_task/cline_frontmatter_lint.py') {
                python scripts/lint/cline_task/cline_frontmatter_lint.py --paths docs/templates/CLINE_TASK_CURRENT_template.md --check
            }
        }
    },
    [pscustomobject]@{
        Name = 'Verification runtime fixture checks'
        Patterns = @('^scripts/verification/', '^repo-standards/verification/', '^scripts/codex-verify\.ps1$', '^scripts/testing/check_testing_strategy_pack\.ps1$', '^docs/(VERIFICATION_RUNTIME|TESTING_STRATEGY_PACK)\.md$', '^docs/changelogs/verification-runtime\.md$', '^repo-standards/(pack_versions|exchange/default_items)\.json$', '^scripts/bootstrap/install_repo_standards\.ps1$')
        Exists = { Test-Path 'scripts/verification/test_profile_fixtures.py' }
        Command = {
            python scripts/verification/test_profile_fixtures.py --repo-root .
        }
    },
    [pscustomobject]@{
        Name = 'Compatibility evolution fixture checks'
        Patterns = @('^scripts/compatibility/', '^repo-standards/compatibility/', '^docs/COMPATIBILITY_EVOLUTION\.md$')
        Exists = { Test-Path 'scripts/compatibility/test_compatibility.py' }
        Command = {
            python scripts/compatibility/test_compatibility.py
            if ($LASTEXITCODE -ne 0) {
                exit $LASTEXITCODE
            }
            python scripts/compatibility/compatibility.py check-pack --repo-root .
        }
    },
    [pscustomobject]@{
        Name = 'Golden sample checks'
        Patterns = @('^examples/golden-repo/', '^scripts/lifecycle/check_golden_repo\.py$', '^scripts/bootstrap/install_repo_standards\.ps1$', '^scripts/logging/', '^docs/templates/LOGGING_template\.md$', '^docs/templates/logging/')
        Exists = { (Test-Path 'scripts/lifecycle/check_golden_repo.py') -and (Test-Path 'examples/golden-repo') }
        Command = {
            python scripts/lifecycle/check_golden_repo.py --repo-root . --sample-root examples/golden-repo
        }
    },
    [pscustomobject]@{
        Name = 'Golden profile checks'
        Patterns = @('^examples/golden-(python|powershell|web|cpp|unreal|docs-only)/', '^scripts/lifecycle/check_golden_profiles\.py$', '^scripts/bootstrap/install_repo_standards\.ps1$', '^scripts/doctor/(detect_repo_type|score_repo)\.ps1$', '^scripts/doctor/validate_json_schema\.py$', '^scripts/rollout/plan_repo_upgrade\.ps1$', '^docs/GOLDEN_PROFILE_REPOS\.md$', '^docs/todo/09_repo_maturity_upgrade_pipeline\.md$')
        Exists = { (Test-Path 'scripts/lifecycle/check_golden_profiles.py') -and (Test-Path 'examples/golden-python') }
        Command = {
            python scripts/lifecycle/check_golden_profiles.py --repo-root .
        }
    },
    [pscustomobject]@{
        Name = 'Root CI bootstrap contract'
        Patterns = @('^\.github/workflows/ci\.yml$', '^scripts/bootstrap/prepare_root_ci\.ps1$', '^repo-standards/verification/(requirements-ci\.lock|root_ci_toolchain\.json)$', '^repo-standards/lint/package(-lock)?\.json$')
        Exists = { (Test-Path 'scripts/bootstrap/prepare_root_ci.ps1') -and (Test-Path 'repo-standards/verification/root_ci_toolchain.json') }
        Command = {
            & ./scripts/bootstrap/prepare_root_ci.ps1 -RepoRoot . -Mode SelfTest
        }
    },
    [pscustomobject]@{
        Name = 'Repo-local lint tool readiness'
        Patterns = @('^scripts/lint/install_lint_tools\.ps1$', '^repo-standards/lint/(package(-lock)?\.json|requirements-lint\.txt|yamllint\.yml)$', '^docs/LANGUAGE_LINTING\.md$')
        Exists = { (Test-Path 'scripts/lint/install_lint_tools.ps1') -and (Test-Path 'repo-standards/lint/package-lock.json') }
        Command = {
            & ./scripts/lint/install_lint_tools.ps1 -RepoRoot . -CheckOnly
        }
    },
    [pscustomobject]@{
        Name = 'Obsidian TODO projection self-test'
        Patterns = @('^scripts/obsidian/', '^repo-standards/obsidian/', '^docs/OBSIDIAN_PROJECT_WORKSPACE\.md$', '^repo-standards/exchange/default_items\.json$')
        Exists = { Test-Path 'scripts/obsidian/sync_todo_workspace.ps1' }
        Command = {
            & ./scripts/obsidian/sync_todo_workspace.ps1 -RepoRoot . -SelfTest
        }
    },
    [pscustomobject]@{
        Name = 'Fleet problem/fix collector self-test'
        Patterns = @('^scripts/fleet/collect_problem_fixes\.ps1$', '^repo-standards/fleet/(managed_repos|problem_fix)(\.schema)?\.json$', '^archive/local-reports/fleet_problem_fix_report\.schema\.json$', '^docs/(COMMON_PITFALLS|CROSS_REPO_EXCHANGE|SOLUTION_COLLECTION)\.md$')
        Exists = { Test-Path 'scripts/fleet/collect_problem_fixes.ps1' }
        Command = {
            & ./scripts/fleet/collect_problem_fixes.ps1 -RepoKitRoot . -SelfTest
        }
    },
    [pscustomobject]@{
        Name = 'Fleet maturity dashboard self-test'
        Patterns = @('^scripts/fleet/build_maturity_dashboard\.ps1$', '^repo-standards/fleet/', '^archive/local-reports/fleet_(maturity_dashboard|problem_fix)_report\.schema\.json$', '^repo-standards/local-app-launcher/standard_ports\.json$', '^docs/(DOWNSTREAM_UPGRADE_DASHBOARD|REPO_MATURITY_SCORECARD|TODO_PROCESS)\.md$')
        Exists = { Test-Path 'scripts/fleet/build_maturity_dashboard.ps1' }
        Command = {
            & ./scripts/fleet/build_maturity_dashboard.ps1 -RepoKitRoot . -SelfTest
        }
    },
    [pscustomobject]@{
        Name = 'Markdown lint fleet report self-test'
        Patterns = @('^scripts/fleet/build_markdown_lint_fleet_report\.ps1$', '^repo-standards/fleet/managed_repos\.json$', '^archive/local-reports/markdown_lint_fleet_report\.schema\.json$', '^docs/(DOWNSTREAM_UPGRADE_DASHBOARD|LANGUAGE_LINTING)\.md$', '^docs/todo/10_external_benchmarking_and_todo_system\.md$')
        Exists = { Test-Path 'scripts/fleet/build_markdown_lint_fleet_report.ps1' }
        Command = {
            & ./scripts/fleet/build_markdown_lint_fleet_report.ps1 -RepoKitRoot . -SelfTest
        }
    },
    [pscustomobject]@{
        Name = 'Repository relationship map checks'
        Patterns = @('^scripts/fleet/build_repository_relationship_map\.ps1$', '^repo-standards/fleet/managed_repos\.json$', '^docs/REPOSITORY_RELATIONSHIP_MAP\.md$')
        Exists = { Test-Path 'scripts/fleet/build_repository_relationship_map.ps1' }
        Command = {
            & ./scripts/fleet/build_repository_relationship_map.ps1 -RepoKitRoot . -SelfTest
            & ./scripts/fleet/build_repository_relationship_map.ps1 -RepoKitRoot . -Check
        }
    }
)

if ($ListOnly) {
    Write-Output ''
    Write-Output 'Planned checks for changed scope:'
    foreach ($check in $checks) {
        $forceThisCheck = $ForceExchangeSmoke -and $check.Name -eq 'Repo-kit exchange smoke checks'
        $shouldRun = (& $check.Exists) -and ($forceThisCheck -or (Test-AnyChanged -Files $changed -Patterns $check.Patterns))
        $statusLabel = if ($shouldRun) { 'run' } else { 'skip' }
        Write-Output ("- {0}: {1}" -f $check.Name, $statusLabel)
    }
    exit 0
}

Push-Location $repo
try {
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($check in $checks) {
        $patterns = $check.Patterns
        $forceThisCheck = $ForceExchangeSmoke -and $check.Name -eq 'Repo-kit exchange smoke checks'
        $results.Add((Invoke-Check -Name $check.Name -Condition {
            (& $check.Exists) -and ($forceThisCheck -or (Test-AnyChanged -Files $changed -Patterns $patterns))
        } -Command $check.Command)) | Out-Null
    }

    $failed = @($results | Where-Object { -not $_.Success -and -not $_.Skipped })
    $ran = @($results | Where-Object { -not $_.Skipped })

    Write-Output ''
    Write-Output "run_changed_scope summary: ran=$($ran.Count) failed=$($failed.Count)"

    if ($failed.Count -gt 0) {
        foreach ($item in $failed) {
            Write-Output ("- {0}" -f $item.Name)
        }
        exit 1
    }

    exit 0
}
finally {
    Pop-Location
}

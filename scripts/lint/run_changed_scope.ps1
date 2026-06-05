[CmdletBinding()]
param(
    [string]$RepoRoot = '.',
    [ValidateSet('32k', '64k', 'cloud')]
    [string]$ContextProfile = 'cloud',
    [string]$BaseRef = '',
    [switch]$IncludeUntracked,
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
            python scripts/lifecycle/check_markdown_paths.py --repo-root .
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
        Name = 'Repo consistency checks'
        Patterns = @('^docs/', '^scripts/', '^repo-standards/', '^\.github/workflows/', '^tools/tools_manifest\.json$')
        Exists = { Test-Path 'scripts/lifecycle/check_repo_consistency.py' }
        Command = {
            python scripts/lifecycle/check_repo_consistency.py --repo-root .
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
        Patterns = @('\.(md|py|ps1|psm1|psd1|json|ya?ml|js|jsx|ts|tsx|c|cc|cpp|cxx|h|hh|hpp|hxx|ixx|cs|uproject|uplugin)$', '^scripts/lint/run_language_lint\.ps1$', '^docs/LANGUAGE_LINTING\.md$', '^repo-standards/lint/(language_lint_matrix|cspell)\.json$', '^repo-standards/lint/docs_terminology_allowlist\.txt$', '^docs/COMMON_PITFALLS\.md$', '^scripts/memory/record_pitfall\.ps1$')
        Exists = { Test-Path 'scripts/lint/run_language_lint.ps1' }
        Command = {
            & ./scripts/lint/run_language_lint.ps1 -RepoRoot .
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
        Patterns = @('^scripts/doctor/(score_repo|detect_repo_type)\.ps1$', '^docs/REPO_MATURITY_SCORECARD\.md$', '^docs/REPO_TYPE_PACK_RECOMMENDER\.md$', '^docs/todo/09_repo_maturity_upgrade_pipeline\.md$')
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
        }
    },
    [pscustomobject]@{
        Name = 'Repo upgrade planner smoke checks'
        Patterns = @('^scripts/rollout/plan_repo_upgrade\.ps1$', '^docs/REPO_UPGRADE_PLANNER\.md$', '^archive/local-reports/repo_upgrade_plan\.schema\.json$', '^repo-standards/exchange/default_items\.json$', '^docs/todo/09_repo_maturity_upgrade_pipeline\.md$')
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
  - Verification: `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex-verify.ps1 -RepoRoot . -ContextProfile cloud -Mode changed -IncludeUntracked`.
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
        Patterns = @('^scripts/exchange/', '^repo-standards/exchange/', '^docs/CROSS_REPO_EXCHANGE\.md$', '^docs/templates/repo-kit/exchange\.json$')
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
        Name = 'Golden sample checks'
        Patterns = @('^examples/golden-repo/', '^scripts/lifecycle/check_golden_repo\.py$', '^scripts/bootstrap/install_repo_standards\.ps1$', '^scripts/logging/', '^docs/templates/LOGGING_template\.md$', '^docs/templates/logging/')
        Exists = { (Test-Path 'scripts/lifecycle/check_golden_repo.py') -and (Test-Path 'examples/golden-repo') }
        Command = {
            python scripts/lifecycle/check_golden_repo.py --repo-root . --sample-root examples/golden-repo
        }
    },
    [pscustomobject]@{
        Name = 'Golden profile checks'
        Patterns = @('^examples/golden-(python|powershell|web|cpp|unreal|docs-only)/', '^scripts/lifecycle/check_golden_profiles\.py$', '^scripts/bootstrap/install_repo_standards\.ps1$', '^scripts/doctor/(detect_repo_type|score_repo)\.ps1$', '^scripts/rollout/plan_repo_upgrade\.ps1$', '^docs/GOLDEN_PROFILE_REPOS\.md$', '^docs/todo/09_repo_maturity_upgrade_pipeline\.md$')
        Exists = { (Test-Path 'scripts/lifecycle/check_golden_profiles.py') -and (Test-Path 'examples/golden-python') }
        Command = {
            python scripts/lifecycle/check_golden_profiles.py --repo-root .
        }
    }
)

if ($ListOnly) {
    Write-Output ''
    Write-Output 'Planned checks for changed scope:'
    foreach ($check in $checks) {
        $shouldRun = (& $check.Exists) -and (Test-AnyChanged -Files $changed -Patterns $check.Patterns)
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
        $results.Add((Invoke-Check -Name $check.Name -Condition {
            (& $check.Exists) -and (Test-AnyChanged -Files $changed -Patterns $patterns)
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

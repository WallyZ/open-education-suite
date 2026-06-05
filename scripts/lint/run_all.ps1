[CmdletBinding()]
param(
    [string]$RepoRoot = '.',
    [ValidateSet('32k', '64k', 'cloud')]
    [string]$ContextProfile = 'cloud',
    [switch]$SkipGoldenRepo,
    [switch]$SkipMemoryBank
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

function Invoke-Check {
    param(
        [string]$Name,
        [scriptblock]$Command,
        [scriptblock]$Condition
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
Push-Location $repo
try {
    $results = New-Object System.Collections.Generic.List[object]

    $results.Add((Invoke-Check -Name 'Markdown path checks' -Condition { Test-Path 'scripts/lifecycle/check_markdown_paths.py' } -Command {
        python scripts/lifecycle/check_markdown_paths.py --repo-root .
    })) | Out-Null

    $results.Add((Invoke-Check -Name 'Ignored artifact checks' -Condition { Test-Path 'scripts/lifecycle/check_ignored_artifacts.py' } -Command {
        python scripts/lifecycle/check_ignored_artifacts.py --repo-root .
    })) | Out-Null

    $results.Add((Invoke-Check -Name 'Repo consistency checks' -Condition { Test-Path 'scripts/lifecycle/check_repo_consistency.py' } -Command {
        python scripts/lifecycle/check_repo_consistency.py --repo-root .
    })) | Out-Null

    $results.Add((Invoke-Check -Name 'External source ledger checks' -Condition { Test-Path 'scripts/lifecycle/check_external_solution_sources.py' } -Command {
        python scripts/lifecycle/check_external_solution_sources.py --repo-root .
    })) | Out-Null

    $results.Add((Invoke-Check -Name 'Language lint checks' -Condition { Test-Path 'scripts/lint/run_language_lint.ps1' } -Command {
        & ./scripts/lint/run_language_lint.ps1 -RepoRoot .
    })) | Out-Null

    $results.Add((Invoke-Check -Name 'Security supply-chain pack checks' -Condition { Test-Path 'scripts/security/check_supply_chain_pack.ps1' } -Command {
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
    })) | Out-Null

    $results.Add((Invoke-Check -Name 'Testing strategy pack checks' -Condition { Test-Path 'scripts/testing/check_testing_strategy_pack.ps1' } -Command {
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
    })) | Out-Null

    $results.Add((Invoke-Check -Name 'Unreal C++ pack checks' -Condition { Test-Path 'scripts/doctor/check_unreal_cpp_pack.ps1' } -Command {
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
    })) | Out-Null

    $results.Add((Invoke-Check -Name 'Logging contract checks' -Condition { Test-Path 'scripts/lifecycle/check_logging_contract.py' } -Command {
        python scripts/lifecycle/check_logging_contract.py --repo-root .
    })) | Out-Null

    $results.Add((Invoke-Check -Name 'Python logging adapter smoke checks' -Condition { Test-Path 'scripts/logging/test_python_logging_adapter_smoke.py' } -Command {
        python scripts/logging/test_python_logging_adapter_smoke.py
    })) | Out-Null

    $results.Add((Invoke-Check -Name 'PowerShell logging adapter smoke checks' -Condition { Test-Path 'scripts/logging/Test-RepoKitLoggingAdapterSmoke.ps1' } -Command {
        & ./scripts/logging/Test-RepoKitLoggingAdapterSmoke.ps1
    })) | Out-Null

    $results.Add((Invoke-Check -Name 'Unreal ingestion regression checks' -Condition { (Test-Path 'scripts/logging/test_unreal_log_ingest_regression.py') -and (Test-Path 'scripts/logging/fixtures/unreal_ingest_cases.json') } -Command {
        python scripts/logging/test_unreal_log_ingest_regression.py
    })) | Out-Null

    $results.Add((Invoke-Check -Name 'Changed-scope checks' -Condition { Test-Path 'scripts/lint/run_changed_scope.ps1' } -Command {
        & ./scripts/lint/run_changed_scope.ps1 -RepoRoot . -ContextProfile $ContextProfile -IncludeUntracked
    })) | Out-Null

    $results.Add((Invoke-Check -Name 'Sync contract checks' -Condition { Test-Path 'scripts/lifecycle/check_sync_contracts.py' } -Command {
        python scripts/lifecycle/check_sync_contracts.py --repo-root .
    })) | Out-Null

    $results.Add((Invoke-Check -Name 'CLI help contract checks' -Condition { Test-Path 'scripts/hooks/check_cli_help_contracts.py' } -Command {
        python scripts/hooks/check_cli_help_contracts.py --repo-root .
    })) | Out-Null

    $results.Add((Invoke-Check -Name 'Structured log schema checks' -Condition { Test-Path 'scripts/lifecycle/check_log_schema.py' } -Command {
        python scripts/lifecycle/check_log_schema.py --repo-root .
    })) | Out-Null

    $results.Add((Invoke-Check -Name 'Host tool capability checks' -Condition { Test-Path 'scripts/doctor/check_host_tools.ps1' } -Command {
        & ./scripts/doctor/check_host_tools.ps1 -FailOnMissingRequired
    })) | Out-Null

    $results.Add((Invoke-Check -Name 'Repo type detector smoke checks' -Condition { Test-Path 'scripts/doctor/detect_repo_type.ps1' } -Command {
        $typeJson = Join-Path $env:TEMP 'repo_type_pack_recommendations.json'
        $typeMarkdown = Join-Path $env:TEMP 'repo_type_pack_recommendations.md'
        & ./scripts/doctor/detect_repo_type.ps1 -RepoRoot . -OutputJson $typeJson -OutputMarkdown $typeMarkdown
    })) | Out-Null

    $results.Add((Invoke-Check -Name 'Repo maturity scorecard smoke checks' -Condition { Test-Path 'scripts/doctor/score_repo.ps1' } -Command {
        $scoreJson = Join-Path $env:TEMP 'repo_maturity_scorecard.json'
        $scoreMarkdown = Join-Path $env:TEMP 'repo_maturity_scorecard.md'
        & ./scripts/doctor/score_repo.ps1 -RepoRoot . -OutputJson $scoreJson -OutputMarkdown $scoreMarkdown -FailBelow 1
    })) | Out-Null

    $results.Add((Invoke-Check -Name 'Repo upgrade planner smoke checks' -Condition { Test-Path 'scripts/rollout/plan_repo_upgrade.ps1' } -Command {
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
    })) | Out-Null

    $results.Add((Invoke-Check -Name 'Upgrade task-pack generator smoke checks' -Condition { (Test-Path 'scripts/rollout/plan_repo_upgrade.ps1') -and (Test-Path 'scripts/rollout/write_task_pack.ps1') } -Command {
        $planJson = Join-Path $env:TEMP 'repo_upgrade_plan_for_task_pack.json'
        $planMarkdown = Join-Path $env:TEMP 'repo_upgrade_plan_for_task_pack.md'
        $taskPack = Join-Path $env:TEMP 'repo_upgrade_task_pack.md'
        $taskPackReport = Join-Path $env:TEMP 'repo_upgrade_task_pack_report.json'
        & ./scripts/rollout/plan_repo_upgrade.ps1 -TargetRepo . -RepoKitRoot . -OutputJson $planJson -OutputMarkdown $planMarkdown
        & ./scripts/rollout/write_task_pack.ps1 -UpgradePlanPath $planJson -RepoRoot . -OutputPath $taskPack -OutputJson $taskPackReport -ContextProfile cloud -MaxItems 3
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
        & ./scripts/rollout/write_task_pack.ps1 -RepoRoot . -TodoRoot $todoFixtureRoot -TodoId RK_SMOKE_TASK_PACK_001 -OutputPath $todoTaskPack -OutputJson $todoTaskPackReport -ContextProfile cloud -Force
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
    })) | Out-Null

    $results.Add((Invoke-Check -Name 'Downstream upgrade dashboard smoke checks' -Condition { (Test-Path 'scripts/rollout/build_upgrade_dashboard.ps1') -and (Test-Path 'archive/local-reports/downstream_upgrade_dashboard_report.schema.json') } -Command {
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
    })) | Out-Null

    $results.Add((Invoke-Check -Name 'Solution CLI smoke checks' -Condition { Test-Path 'scripts/solutions/search_solutions.ps1' } -Command {
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
    })) | Out-Null

    $results.Add((Invoke-Check -Name 'Inventory checks' -Condition { Test-Path 'scripts/inventory/generate_inventory.py' } -Command {
        python scripts/inventory/generate_inventory.py --repo-root . --check
    })) | Out-Null

    $results.Add((Invoke-Check -Name 'Tools manifest checks' -Condition { Test-Path 'scripts/lifecycle/check_tools_manifest.py' } -Command {
        python scripts/lifecycle/check_tools_manifest.py --repo-root .
    })) | Out-Null
    $results.Add((Invoke-Check -Name 'Cline performance baseline checks' -Condition { (Test-Path 'scripts/wavekit/cline_perf_harness.py') -and (Test-Path 'docs/wavekit/perf/runs.jsonl') } -Command {
        python scripts/wavekit/cline_perf_harness.py --repo-root . --check --min-runs 6
    })) | Out-Null

    $results.Add((Invoke-Check -Name 'WaveKit TODO preflight' -Condition { (Test-Path 'scripts/wavekit/todo_preflight_fix.py') -and (Test-Path 'docs/todo') } -Command {
        python scripts/wavekit/todo_preflight_fix.py --todo-root docs/todo --check
    })) | Out-Null

    $results.Add((Invoke-Check -Name 'TODO format checks' -Condition { Test-Path 'scripts/lifecycle/check_todo_format.py' } -Command {
        python scripts/lifecycle/check_todo_format.py --repo-root . --todo-root docs/todo --min-severity info --fail-on error
    })) | Out-Null

    $results.Add((Invoke-Check -Name 'TODO ready-queue checks' -Condition { Test-Path 'scripts/lifecycle/check_todo_ready_queue.py' } -Command {
        python scripts/lifecycle/check_todo_ready_queue.py --repo-root . --todo-root docs/todo --min-severity info --fail-on error --report -
    })) | Out-Null

    if (-not $SkipMemoryBank) {
        $results.Add((Invoke-Check -Name 'Memory-bank quality checks' -Condition { Test-Path 'scripts/lifecycle/check_memory_bank.py' } -Command {
            python scripts/lifecycle/check_memory_bank.py --repo-root . --profile $ContextProfile
        })) | Out-Null
    }

    if (-not $SkipGoldenRepo) {
        $results.Add((Invoke-Check -Name 'Golden sample checks' -Condition { (Test-Path 'scripts/lifecycle/check_golden_repo.py') -and (Test-Path 'examples/golden-repo') } -Command {
            python scripts/lifecycle/check_golden_repo.py --repo-root . --sample-root examples/golden-repo
        })) | Out-Null

        $results.Add((Invoke-Check -Name 'Golden profile checks' -Condition { (Test-Path 'scripts/lifecycle/check_golden_profiles.py') -and (Test-Path 'examples/golden-python') } -Command {
            python scripts/lifecycle/check_golden_profiles.py --repo-root .
        })) | Out-Null
    }

    $failed = @($results | Where-Object { -not $_.Success -and -not $_.Skipped })
    $ran = @($results | Where-Object { -not $_.Skipped })

    Write-Output ''
    Write-Output "lint/run_all summary: ran=$($ran.Count) failed=$($failed.Count) repo=$repo profile=$ContextProfile"

    if ($failed.Count -gt 0) {
        foreach ($item in $failed) {
            Write-Output "- $($item.Name)"
        }
        exit 1
    }

    exit 0
}
finally {
    Pop-Location
}

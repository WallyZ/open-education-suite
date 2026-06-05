[CmdletBinding()]
param(
    [string]$RepoRoot = '.',
    [string]$RepoKitRoot = 'F:\dev\00-repo-kit',
    [string]$CatalogPath = 'memory-bank/repoKitCatalog.md',
    [switch]$DryRun
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

function Build-CapabilityTable {
    param(
        [string]$KitRoot,
        [string]$RepoRoot
    )

    $caps = @(
        [pscustomobject]@{
            Name = 'Standards bootstrap'
            Assets = @('scripts/bootstrap/install_repo_standards.ps1', 'docs/REPO_WIRING_PLAYBOOK.md')
            Pull = "pwsh -NoProfile -ExecutionPolicy Bypass -File '$KitRoot\scripts\bootstrap\install_repo_standards.ps1' -TargetRepo '$RepoRoot' -Mode existing"
        },
        [pscustomobject]@{
            Name = 'Memory-bank bootstrap'
            Assets = @('scripts/bootstrap/bootstrap_memory_bank.ps1', 'docs/MEMORY_BANK_QUICKSTART.md')
            Pull = "pwsh -NoProfile -ExecutionPolicy Bypass -File '$KitRoot\scripts\bootstrap\bootstrap_memory_bank.ps1' -TargetRepo '$RepoRoot'"
        },
        [pscustomobject]@{
            Name = 'Repo doctor + full lint'
            Assets = @('scripts/doctor/repo_doctor.ps1', 'scripts/lint/run_all.ps1')
            Pull = "pwsh -NoProfile -ExecutionPolicy Bypass -File '$KitRoot\scripts\lint\run_all.ps1' -RepoRoot '$RepoRoot' -ContextProfile cloud"
        },
        [pscustomobject]@{
            Name = 'Changed-scope checks'
            Assets = @('scripts/lint/run_changed_scope.ps1', 'scripts/lifecycle/check_repo_consistency.py')
            Pull = "pwsh -NoProfile -ExecutionPolicy Bypass -File '$RepoRoot\scripts\lint\run_changed_scope.ps1' -RepoRoot '$RepoRoot' -ContextProfile cloud -IncludeUntracked"
        },
        [pscustomobject]@{
            Name = 'Language lint + pitfall capture'
            Assets = @('scripts/codex-verify.ps1', 'scripts/lint/run_language_lint.ps1', 'docs/LANGUAGE_LINTING.md', 'scripts/memory/record_pitfall.ps1', 'docs/COMMON_PITFALLS.md')
            Pull = "pwsh -NoProfile -ExecutionPolicy Bypass -File '$RepoRoot\scripts\codex-verify.ps1' -RepoRoot '$RepoRoot' -ContextProfile cloud -Mode changed -IncludeUntracked"
        },
        [pscustomobject]@{
            Name = 'Repo maturity scorecard'
            Assets = @('scripts/doctor/score_repo.ps1', 'scripts/doctor/detect_repo_type.ps1', 'docs/REPO_MATURITY_SCORECARD.md', 'docs/REPO_TYPE_PACK_RECOMMENDER.md')
            Pull = "pwsh -NoProfile -ExecutionPolicy Bypass -File '$RepoRoot\scripts\doctor\score_repo.ps1' -RepoRoot '$RepoRoot' -OutputJson '$RepoRoot\archive\local-reports\repo_maturity_scorecard.json' -OutputMarkdown '$RepoRoot\archive\local-reports\repo_maturity_scorecard.md'"
        },
        [pscustomobject]@{
            Name = 'Existing repo upgrade planner'
            Assets = @('scripts/rollout/plan_repo_upgrade.ps1', 'scripts/rollout/write_task_pack.ps1', 'docs/REPO_UPGRADE_PLANNER.md', 'docs/TASK_PACK_GENERATOR.md', 'archive/local-reports/repo_upgrade_plan.schema.json')
            Pull = "pwsh -NoProfile -ExecutionPolicy Bypass -File '$KitRoot\scripts\rollout\plan_repo_upgrade.ps1' -TargetRepo '$RepoRoot' -RepoKitRoot '$KitRoot' -OutputJson '$RepoRoot\archive\local-reports\repo_upgrade_plan.json' -OutputMarkdown '$RepoRoot\archive\local-reports\repo_upgrade_plan.md'"
        },
        [pscustomobject]@{
            Name = 'Upgrade task-pack generator'
            Assets = @('scripts/rollout/write_task_pack.ps1', 'docs/TASK_PACK_GENERATOR.md')
            Pull = "pwsh -NoProfile -ExecutionPolicy Bypass -File '$KitRoot\scripts\rollout\write_task_pack.ps1' -UpgradePlanPath '$RepoRoot\archive\local-reports\repo_upgrade_plan.json' -RepoRoot '$RepoRoot' -OutputPath '$RepoRoot\.codex-cache\task-pack.md' -MaxItems 5"
        },
        [pscustomobject]@{
            Name = 'Downstream upgrade dashboard'
            Assets = @('scripts/rollout/build_upgrade_dashboard.ps1', 'docs/DOWNSTREAM_UPGRADE_DASHBOARD.md', 'archive/local-reports/downstream_upgrade_dashboard_report.schema.json')
            Pull = "pwsh -NoProfile -ExecutionPolicy Bypass -File '$KitRoot\scripts\rollout\build_upgrade_dashboard.ps1' -RepoRoot '$RepoRoot' -RepoKitRoot '$KitRoot' -OutputJson '$RepoRoot\archive\local-reports\downstream_upgrade_dashboard.json' -OutputMarkdown '$RepoRoot\archive\local-reports\downstream_upgrade_dashboard.md'"
        },
        [pscustomobject]@{
            Name = 'Security and supply-chain pack'
            Assets = @('docs/SECURITY_SUPPLY_CHAIN_PACK.md', 'scripts/security/check_supply_chain_pack.ps1', 'docs/templates/SECURITY_template.md', 'docs/templates/CODEOWNERS_template', 'docs/templates/renovate.json')
            Pull = "pwsh -NoProfile -ExecutionPolicy Bypass -File '$KitRoot\scripts\security\check_supply_chain_pack.ps1' -RepoRoot '$RepoRoot' -OutputJson '$RepoRoot\archive\local-reports\security_supply_chain_pack.json' -OutputMarkdown '$RepoRoot\archive\local-reports\security_supply_chain_pack.md' -FailOnError"
        },
        [pscustomobject]@{
            Name = 'Testing strategy pack'
            Assets = @('docs/TESTING_STRATEGY_PACK.md', 'scripts/testing/check_testing_strategy_pack.ps1', 'templates/testing/minimum_viable_suite', 'templates/testing/portable_regression')
            Pull = "pwsh -NoProfile -ExecutionPolicy Bypass -File '$KitRoot\scripts\testing\check_testing_strategy_pack.ps1' -RepoRoot '$RepoRoot' -OutputJson '$RepoRoot\archive\local-reports\testing_strategy_pack.json' -OutputMarkdown '$RepoRoot\archive\local-reports\testing_strategy_pack.md' -FailOnError"
        },
        [pscustomobject]@{
            Name = 'Unreal and C++ repo pack'
            Assets = @('docs/UNREAL_CPP_REPO_PACK.md', 'scripts/doctor/check_unreal_cpp_pack.ps1', 'docs/templates/unreal', 'docs/CLINE_UNREAL_GUIDE.md', 'docs/UNREAL_LOG_INGESTION_CONTRACT.md')
            Pull = "pwsh -NoProfile -ExecutionPolicy Bypass -File '$KitRoot\scripts\doctor\check_unreal_cpp_pack.ps1' -RepoRoot '$RepoRoot' -OutputJson '$RepoRoot\archive\local-reports\unreal_cpp_pack.json' -OutputMarkdown '$RepoRoot\archive\local-reports\unreal_cpp_pack.md' -FailOnError"
        },
        [pscustomobject]@{
            Name = 'Golden profile repo validation'
            Assets = @('docs/GOLDEN_PROFILE_REPOS.md', 'scripts/lifecycle/check_golden_profiles.py', 'examples/golden-python', 'examples/golden-powershell', 'examples/golden-web', 'examples/golden-cpp', 'examples/golden-unreal', 'examples/golden-docs-only')
            Pull = "python '$KitRoot\scripts\lifecycle\check_golden_profiles.py' --repo-root '$KitRoot'"
        },
        [pscustomobject]@{
            Name = 'Solution search/promote/apply CLI'
            Assets = @('scripts/solutions/search_solutions.ps1', 'docs/SOLUTION_CLI.md', 'archive/local-reports/solution_cli_report.schema.json', 'docs/solutions')
            Pull = "pwsh -NoProfile -ExecutionPolicy Bypass -File '$KitRoot\scripts\solutions\search_solutions.ps1' -RepoRoot '$RepoRoot' -RepoKitRoot '$KitRoot' -Mode plan -Query 'memory bootstrap' -OutputJson '$RepoRoot\archive\local-reports\solution_plan.json' -OutputMarkdown '$RepoRoot\archive\local-reports\solution_plan.md'"
        },
        [pscustomobject]@{
            Name = 'Wave generation pipeline'
            Assets = @('scripts/wavekit/wavekit_autogen.py', 'scripts/wavekit/todo_preflight_fix.py', 'docs/WAVEKIT.md')
            Pull = "python '$KitRoot\scripts\wavekit\wavekit_autogen.py' --repo-root '$RepoRoot' --phase-mode next --normalize-phase-tags"
        },
        [pscustomobject]@{
            Name = 'TODO contract enforcement'
            Assets = @('scripts/todo_audit.py', 'scripts/lifecycle/check_todo_format.py', 'docs/TODO_AUDIT.md')
            Pull = "python '$RepoRoot\scripts\lifecycle\check_todo_format.py' --repo-root '$RepoRoot' --todo-root docs/todo --min-severity info --fail-on error"
        },
        [pscustomobject]@{
            Name = 'Maintenance cadence runner'
            Assets = @('scripts/maintenance/run_maintenance.ps1', 'docs/MAINTENANCE_SCHEDULE.md')
            Pull = "pwsh -NoProfile -ExecutionPolicy Bypass -File '$RepoRoot\scripts\maintenance\run_maintenance.ps1' -RepoRoot '$RepoRoot' -Cadence weekly -ContextProfile cloud"
        },
        [pscustomobject]@{
            Name = 'Portable tools governance'
            Assets = @('tools/tools_manifest.json', 'scripts/lifecycle/check_tools_manifest.py', 'scripts/tools/update_tools.ps1')
            Pull = "python '$RepoRoot\scripts\lifecycle\check_tools_manifest.py' --repo-root '$RepoRoot'"
        }
    )

    $lines = @(
        '| Capability | Key assets (repo-kit) | Typical pull action |',
        '| --- | --- | --- |'
    )

    foreach ($cap in $caps) {
        $assetBits = @()
        foreach ($asset in $cap.Assets) {
            $assetPath = Join-Path $KitRoot $asset
            $suffix = if (Test-Path -LiteralPath $assetPath) { 'ok' } else { 'missing' }
            $assetBits += ('`{0}` ({1})' -f $asset.Replace('\', '/'), $suffix)
        }

        $assetCell = ($assetBits -join '; ')
        $pullCell = ('`{0}`' -f ($cap.Pull.Replace('\', '/')))
        $lines += ('| {0} | {1} | {2} |' -f $cap.Name, $assetCell, $pullCell)
    }

    return $lines
}

$repo = Get-RepoRootPath -Start $RepoRoot
if (-not (Test-Path -LiteralPath $RepoKitRoot)) {
    throw "RepoKitRoot not found: $RepoKitRoot"
}
$kit = (Resolve-Path -LiteralPath $RepoKitRoot).Path

$catalog = Join-Path $repo ($CatalogPath.Replace('/', '\'))
$catalogDir = Split-Path -Parent $catalog
if ($catalogDir -and -not (Test-Path -LiteralPath $catalogDir) -and -not $DryRun) {
    New-Item -ItemType Directory -Force -Path $catalogDir | Out-Null
}

$today = Get-Date -Format 'yyyy-MM-dd'
$table = Build-CapabilityTable -KitRoot $kit -RepoRoot $repo

$generatedLines = @('<!-- REPO_KIT_CATALOG:BEGIN -->') + $table + @('<!-- REPO_KIT_CATALOG:END -->')
$generatedBlock = $generatedLines -join "`n"

$metadataAndSnapshot = @(
    '# Repo-Kit Catalog',
    '',
    '## Metadata',
    '',
    "- Last synced: $today",
    ("- Repo-kit source root: {0}" -f ($kit.Replace('\', '/'))),
    ("- Sync command: pwsh -NoProfile -ExecutionPolicy Bypass -File .\\scripts\\memory\\sync_repo_kit_catalog.ps1 -RepoRoot . -RepoKitRoot '{0}'" -f $kit),
    '',
    '## Capabilities Snapshot',
    '',
    $generatedBlock,
    ''
) -join "`n"

$defaultTail = @(
    '## Wave Pull Review Checklist',
    '',
    '- [ ] Reviewed current wave objective against capabilities snapshot.',
    '- [ ] Selected at least one candidate asset to adopt, or recorded why none apply.',
    '- [ ] Added adoption/no-adoption note to `memory-bank/solutionHarvest.md`.',
    '',
    '## Wave Pull Review Log',
    '',
    '- YYYY-MM-DD: `<wave-id>` -> adopted `<asset/path>` because `<why>`.'
) -join "`n"

$tail = $defaultTail
if (Test-Path -LiteralPath $catalog) {
    $existing = Get-Content -LiteralPath $catalog -Raw
    $m = [regex]::Match($existing, '(?ms)^## Wave Pull Review Checklist\s*$.*$')
    if ($m.Success) {
        $tail = $m.Value.TrimStart("`r", "`n")
    }
}

$out = $metadataAndSnapshot + "`n" + $tail + "`n"

if ($DryRun) {
    Write-Output $out
    Write-Output "sync_repo_kit_catalog dry-run complete (repo=$repo kit=$kit path=$catalog)"
    exit 0
}

Set-Content -LiteralPath $catalog -Value $out -Encoding utf8
Write-Output "sync_repo_kit_catalog complete (repo=$repo kit=$kit path=$catalog)"

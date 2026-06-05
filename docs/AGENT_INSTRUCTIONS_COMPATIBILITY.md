# Agent Instructions Compatibility

This repo uses `AGENTS.md` as the source-of-truth agent contract. Other agent files should be projections of that contract, not independent policy sources.

Machine-readable model: `repo-standards/agents/agent_instruction_compatibility.json`.

## Default Policy

Repo-kit installs Codex plus memory-bank by default. Cline is supported as an optional compatibility pack, not as required repo infrastructure.

Default downstream install includes:

- `AGENTS.md`
- `memory-bank/`
- `scripts/codex-verify.ps1`
- TODO, lifecycle, lint, logging, exchange, and standards assets

Cline assets are installed only when requested with `-IncludeCline` or `-InstallHooksProfile`.

## Canonical Startup Contract

1. Read `AGENTS.md`.
2. Read `.codex-cache/task-pack.md` when present.
3. Use `memory-bank/` to keep context bounded.
4. Open only the smallest relevant file set.
5. Use `scripts/codex-verify.ps1` as the verifier entrypoint.
6. Read TODO `QA Live automation:` instructions before testing UI, game, Unreal, runtime, or live workflows.
7. Preserve repo-local overrides and do not overwrite local agent instructions without review.
8. Run every automatable QA Live check; if QA Live cannot cover automatable behavior, add/update the repo-owned QA Live spec or adjacent `qa-live-test-system` capability before calling it manual.
9. Follow solo-owner direct-main by default: commit on `main` and push to `origin/main` unless `.repo-kit/workflow_policy.local.json` or hosted branch protection requires team/PR flow.
10. Follow the post-TODO completion contract in `docs/TODO_PROCESS.md`: update TODO evidence, add gap/improvement TODOs, update docs/decisions, verify, refresh memory, commit/push, recommend QA Live-first validation, and list user-only checks only when automation or QA Live cannot prove the behavior.

## Installed Projections

- Codex: `AGENTS.md`
- Shared context: `memory-bank/`
- Shared verifier: `scripts/codex-verify.ps1`

## Optional Projections

These files are not installed by default because many repos already have local agent instructions or do not use that agent surface. Add or update them only after reviewing local content.

### Cline Projection

Use Cline only when a downstream repo actively needs that surface:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File F:\dev\00-repo-kit\scripts\bootstrap\install_repo_standards.ps1 `
  -TargetRepo <repo> `
  -Mode existing `
  -IncludeCline `
  -ReportPath <repo>\archive\local-reports\install_repo_standards_agents_cline.json
```

The optional pack writes a repo-local Cline guide, current-task pointer, rules directory, and ignore file in the target repo.

The optional Cline projection must remain subordinate to `AGENTS.md`. Do not use Cline docs to define independent scope, verification, or memory policy.

### Claude Code `CLAUDE.md`

```markdown
# CLAUDE.md

Source: AGENTS.md + repo-standards/agents/agent_instruction_compatibility.json
Updated: 2026-06-03
Supported agent: Claude Code
Repo-local override boundary: Add repo-specific details below this header; do not remove AGENTS.md startup/verifier/memory requirements.

Read order:
1. AGENTS.md
2. .codex-cache/task-pack.md when present
3. memory-bank/context-pack.md and memory-bank/activeContext.md when present

Rules:
- Keep scope narrow and open only files required by the task pack.
- Use scripts/codex-verify.ps1 for verification.
- Follow TODO QA Live automation instructions for UI/game/Unreal/runtime/live workflows.
- If QA Live lacks automatable coverage, add/update the repo-owned QA Live spec or adjacent qa-live-test-system capability before calling it manual.
- Commit on main and push to origin/main by default unless .repo-kit/workflow_policy.local.json requires team/PR flow.
- After completing a TODO, run the post-TODO closeout from docs/TODO_PROCESS.md, including QA Live-first validation and documented user-only exceptions, before handing back.
```

### Cursor `.cursor/rules/repo-kit.mdc`

```markdown
---
description: Repo-kit agent contract projection
alwaysApply: true
---

Source: AGENTS.md + repo-standards/agents/agent_instruction_compatibility.json
Updated: 2026-06-03
Supported agent: Cursor
Repo-local override boundary: Add local Cursor rules in separate files; do not contradict AGENTS.md.

Read AGENTS.md first. If .codex-cache/task-pack.md exists, use it as the task scope. Prefer memory-bank summaries before broad file reads. Verify with scripts/codex-verify.ps1. Follow TODO QA Live automation instructions before UI/game/Unreal/runtime/live testing, adding QA Live coverage before calling an automatable gap manual. Commit on main and push to origin/main by default unless .repo-kit/workflow_policy.local.json requires team/PR flow. After TODO work, run the post-TODO closeout in docs/TODO_PROCESS.md, recommending QA Live-first validation and listing user-only checks only as documented exceptions.
```

### GitHub Copilot `.github/copilot-instructions.md`

```markdown
# GitHub Copilot Instructions

Source: AGENTS.md + repo-standards/agents/agent_instruction_compatibility.json
Updated: 2026-06-03
Supported agent: GitHub Copilot
Repo-local override boundary: Add repo-specific details below this section; keep AGENTS.md as canonical.

- Read AGENTS.md before making changes.
- Use .codex-cache/task-pack.md when present to limit scope.
- Prefer memory-bank context over broad repo scans.
- Use scripts/codex-verify.ps1 for verification.
- Follow TODO QA Live automation instructions for UI/game/Unreal/runtime/live workflows.
- If QA Live lacks automatable coverage, add/update the repo-owned QA Live spec or adjacent qa-live-test-system capability before calling it manual.
- Commit on main and push to origin/main by default unless .repo-kit/workflow_policy.local.json requires team/PR flow.
- After completing TODO-scoped work, follow the post-TODO closeout in docs/TODO_PROCESS.md, including QA Live-first validation and documented user-only exceptions.
```

## Downstream Rollout

Run the standards installer to copy the compatibility model and default installed projections:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File F:\dev\00-repo-kit\scripts\bootstrap\install_repo_standards.ps1 `
  -TargetRepo <repo> `
  -Mode existing `
  -ReportPath <repo>\archive\local-reports\install_repo_standards_agents.json
```

For existing repos, review `pending_updates` before using `-Force`. Do not overwrite existing `CLAUDE.md`, `.cursor/rules/`, or `.github/copilot-instructions.md` automatically unless a repo owner approves the projection.

Use `-IncludeCline` only for repos that actively use Cline. Existing Cline files in downstream repos should be preserved unless the repo owner approves updating or removing them.

## Drift Guard

- Keep `AGENTS.md` and `repo-standards/agents/agent_instruction_compatibility.json` aligned.
- Projection headers should include source, update date, supported agent, and repo-local override boundary.
- Golden sample validation must confirm default installer output excludes Cline assets and optional `-IncludeCline` output includes them.

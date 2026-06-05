# TODO_PROCESS.md

Operational process for keeping split TODO files executable, auditable, and queue-driven.

## Objectives

- Keep TODO items actionable with explicit evidence and execution metadata for open PH2/PH3 work.
- Surface the next unblocked high-value work across all `docs/todo/*.md` files.
- Separate automation-safe work from human-gated work.

## Canonical Item Shape

- Checkbox line:
  - `- [ ] Task text [PH2] <!-- ms:evidence ... -->`
- Optional metadata comment on the same line:
  - `<!-- ms:meta priority=p1 owner=@team depends-on=<id1,id2> blocked-by=<id3> target-repo=<repo> stale-days=14 automation-level=auto human-checkpoint=none rollout-scope=fleet validation-profile=cloud safe-autofix=safe -->`

`yta:*` tags are also supported; do not mix `ms:*` and `yta:*` on one line.

## Metadata Keys

Supported optional metadata keys:

- `priority`: `p0|p1|p2|p3|high|medium|low`
- `owner`: one or more owners (`owner=@alice,@bob`)
- `depends-on`: TODO ids that must be completed first
- `blocked-by`: external blockers (ticket/decision ids)
- `target-repo`: downstream repo target
- `stale-days`: positive integer staleness threshold
- `automation-level`: `auto|assisted|manual|none`
- `human-checkpoint`: reviewer gate (`none` to indicate no gate)
- `rollout-scope`: rollout target class (for example `single`, `fleet`)
- `validation-profile`: `32k|64k|cloud|full`
- `safe-autofix`: `safe|review|manual|none|auto`
- `updated`: optional `YYYY-MM-DD` review/update date (used for stale checks)

Aliases with hyphens/underscores are accepted; canonical names above should be preferred.

## Agent-Ready Item Shape

Open PH2/PH3 items must be written so an agent can execute the item without scanning unrelated docs. `scripts/lifecycle/check_todo_format.py` enforces the metadata and child-bullet sections below.

```markdown
- [ ] Task text [PH2] <!-- ms:evidence id=RK_EXAMPLE_001 path=docs/TODO_PROCESS.md strings="Files,Verification,Drift guard" --> <!-- ms:meta priority=p1 owner=@repo-kit stale-days=14 automation-level=assisted human-checkpoint=review rollout-scope=fleet validation-profile=cloud safe-autofix=review updated=2026-06-03 -->
  - Deliverables: concrete output files, scripts, docs, or reports.
  - Files: smallest expected file set to inspect or edit.
  - Verification: exact repo verifier command or the narrow verifier mode.
  - QA Live automation: how to use `qa-live-test-system` for automated UI/runtime testing, or `Not required` with the reason for verifier/static-only work. If QA Live lacks a capability for automatable behavior, the TODO should call for adding the repo-owned spec/contract or improving `qa-live-test-system`; user-only checks belong here only when automation or QA Live cannot verify the behavior.
  - Drift guard: what future check prevents stale docs, broken paths, or behavior drift.
  - Downstream rollout: how the work is installed, copied, proposed, or reported in other repos.
  - Acceptance:
    - Observable completion criteria.
```

For completed items, keep the existing `Evidence (YYYY-MM-DD)` block and include the passing verification command/log when available.

## Post-TODO Completion Contract

Every TODO completion wave must end with the same durable closeout steps:

1. Update the in-scope TODO checkbox and evidence only after the implementation and verification are complete.
2. Add or update TODO items for newly discovered gaps, feature improvements, safety risks, documentation drift, missing tests, or useful follow-up capabilities.
3. Split work into smaller TODO items when a single TODO proves too broad, touches too many unrelated files, needs human decisions, or spans multiple validation profiles.
4. Update all affected docs, including `docs/decisions.md` for lightweight permanent decisions or `docs/adr/` for substantial architectural decisions.
5. Run the exact verifier named by the TODO, plus every QA Live or artifact review gate named by `QA Live automation:` or `Acceptance:`.
6. Refresh `memory-bank/` when status, context, reusable solutions, or recurring pitfalls changed.
7. Record reusable fixes or cross-repo candidates in `memory-bank/commonPitfalls.md`, `memory-bank/solutionHarvest.md`, `docs/solutions/`, or `docs/adr/` as appropriate.
8. If QA Live cannot currently cover automatable UI, game, Unreal, browser, VM, installer, or runtime behavior, add or update the repo-owned QA Live spec/contract or the adjacent `qa-live-test-system` capability before treating the gap as manual. Commit and push any required `qa-live-test-system` change to that repo's `main`.
9. Commit the related change set and push to `main` by default. Use branch/PR flow only when `.repo-kit/workflow_policy.local.json` or hosted branch protection requires it, and state why it was not pushed directly to `main`.
10. Recommend QA Live-first validation for real functionality: name the `qa-live-test-system` contract, run-spec, capability check, expected result, and report path when the change affects UI, game, Unreal, browser, VM, installer, or runtime behavior. List user-only verification only for functionality that cannot be proven by automation or QA Live, and state why each user check is absolutely required.

If no unchecked TODO remains, run `scripts/status/next_work.ps1` and perform a bounded gap scan for project gaps or useful improvements. Add a standard TODO for any credible next improvement; only continue implementing another TODO when the user explicitly asked to keep working through the queue or the follow-up is small, safe, and directly necessary to complete the current item.

## Agent Queue JSON Contract

Schema-backed agent output is exported by `scripts/lifecycle/check_todo_ready_queue.py` and described by `repo-standards/todo/todo_agent_queue.schema.json`.

Each exported item includes:

- `todo_id`, `file`, `line`, `text`, `phase`, queue metadata, dependency/blocker state, stale state, and readiness flags.
- `agent.task_id`, `agent.files`, `agent.file_refs`, `agent.verification`, `agent.qa_live_automation`, `agent.acceptance`, `agent.drift_guard`, `agent.downstream_rollout`, `agent.dependencies`, `agent.stale_threshold_days`, `agent.validation_profile`, and `agent.deliverables`.
- `agent_ready=false` plus `agent_ready_missing=[...]` when a required field is not parseable.

## QA Live Automation Direction

Every open PH2/PH3 TODO must include `QA Live automation:` so task packs can decide how to exercise changes through `qa-live-test-system` without guessing.

- For UI, game, Unreal, browser, VM, installer, or runtime workflow changes: name the expected QA Live contract or run-spec location in the target repo, use dry-run/capability-manifest mode first, and call out any host/VM prerequisite such as Hyper-V, resident guest agent, unlocked desktop session, or heartbeat freshness.
- If a needed check is automatable but unsupported, do not downgrade it to a user-only check. Add or update the downstream repo's QA Live spec/contract, or update the adjacent `qa-live-test-system` adapter/capability and commit/push that repo to `main`, then rerun validation.
- For repo-kit static docs/schema/lint/checker work: write `Not required` and explain which local verifier covers the change instead.
- Manual or user-only verification is an exception, not the default. Use it only for checks QA Live cannot observe, such as private account billing state, subjective creative review, physical-device behavior, or external credentials the agent cannot access.
- Do not vendor `qa-live-test-system` code into downstream repos; TODOs should point to repo-owned specs/contracts and invoke the adjacent QA system when host capabilities are present.

## Repo Workflow Mode

Repo-kit-managed repos default to solo-owner direct-main:

- Commit on `main`.
- Push to `origin/main`.
- Avoid feature branches and PRs unless a repo-local override requires them.

To switch a repo to team/PR flow, add `.repo-kit/workflow_policy.local.json` with:

```json
{
  "mode": "team_pr",
  "default_branch": "main",
  "requires_pull_request": true
}
```

Agents must read that override before commit/push closeout. Without it, direct `main` commit/push is the default.

## Downstream Installation And Migration

Use the standards installer to add or refresh the TODO process pack in a downstream repo. Existing repos should run report-only first so local TODO files are not overwritten without review.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File F:\dev\00-repo-kit\scripts\bootstrap\install_repo_standards.ps1 `
  -TargetRepo <repo> `
  -Mode existing `
  -ReportPath <repo>\archive\local-reports\install_repo_standards_todo_process.json `
  -FailOnPendingUpdates
```

The installed TODO process pack includes:

- `docs/TODO.md`
- `docs/TODO_AUDIT.md`
- `docs/TODO_PROCESS.md`
- `docs/todo/00_repo_bootstrap.md`
- `repo-standards/todo/todo_agent_queue.schema.json`
- `scripts/lifecycle/check_todo_format.py`
- `scripts/lifecycle/check_todo_ready_queue.py`
- `scripts/todo_audit/`

For an existing repo, the installer preserves differing local files and reports them as `pending_updates` unless `-Force` is supplied. Review the JSON report before forcing updates. A force run is acceptable only after local TODO hub/process files and repo-specific backlog content are confirmed safe to replace or merge.

After installation, verify the downstream TODO pack:

```powershell
python scripts/lifecycle/check_todo_format.py --repo-root . --todo-root docs/todo --min-severity info --fail-on error
python scripts/lifecycle/check_todo_ready_queue.py --repo-root . --todo-root docs/todo --min-severity info --fail-on error --report -
```

## Ready Queue Workflow

1. Lint TODO format + metadata:

```powershell
python scripts/lifecycle/check_todo_format.py --repo-root . --todo-root docs/todo --min-severity info --fail-on error
```

2. Build/validate the cross-file ready queue:

```powershell
python scripts/lifecycle/check_todo_ready_queue.py --repo-root . --todo-root docs/todo --min-severity info --fail-on error --report -
```

3. Optional machine-readable queue output:

```powershell
python scripts/lifecycle/check_todo_ready_queue.py --repo-root . --todo-root docs/todo --agent-json .codex-cache/tmp/todo_agent_queue.json --report docs/TODO_READY_QUEUE.md
```

`--json-report` remains as a compatibility alias for existing consumers.

## Queue Semantics

- `Ready Queue (Auto-Eligible)`: unblocked items marked safe for automation.
- `Ready Queue (Human-Required)`: unblocked items that still need a checkpoint/review.
- `Blocked`: items blocked by open dependencies, missing dependency ids, or explicit blockers.
- Duplicate open TODO text across files is reported as a warning for cleanup.
- Stale warnings are emitted when `stale-days` is exceeded.

## Policy

- Metadata is required for open PH2/PH3 TODO items (priority, owner, stale-days, automation-level, human-checkpoint, validation-profile, safe-autofix, updated).
- Agent child sections are required for open PH2/PH3 TODO items (Deliverables, Files, Verification, QA Live automation, Drift guard, Downstream rollout, Acceptance).
- `Files:` entries should wrap paths in backticks so `agent.files` and `agent.file_refs` are parseable.
- Completed (`[x]`) items still require evidence/id tags per `docs/TODO_AUDIT.md`.
- Dependency ids should point to TODO ids in the same split backlog set when possible.

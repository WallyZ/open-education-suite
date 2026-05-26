# Codex Runbook

This runbook is the durable companion to `.codex-cache/task-pack.md`. `AGENTS.md` remains the authority for behavior; the task pack narrows the current work.

## Startup Sequence

1. Read `AGENTS.md`.
2. Read [task-pack.md](../.codex-cache/task-pack.md).
3. Run:

```powershell
.\scripts\status\next-work.ps1
```

4. State intended verification before editing:

```powershell
.\scripts\codex-verify.ps1
```

5. Work only the files needed for the selected TODO.

## Next Work Helper

[next-work.ps1](../scripts/status/next-work.ps1) scans `docs/todo/TODO_*.md` in filename order and returns the first unchecked task with file, line, heading, and task text.

Use it instead of broad TODO searches when choosing the next task.

## Common Commands

```powershell
.\scripts\status\next-work.ps1
.\scripts\teaching\start-session.ps1 -NonInteractive
.\scripts\ingestion\scan-content-sources.ps1
.\scripts\ingestion\build-content-package.ps1
.\scripts\quality\check-content-quality.ps1
.\scripts\quality\check-teaching-quality.ps1
.\scripts\codex-verify.ps1
```

## Boundaries

- Core repo owns platform behavior, schemas, fixtures, verification, ingestion, and orchestration.
- Content repos own curricula, resources, objectives, assessments, and misconceptions.
- AI teacher outputs may propose state changes; deterministic code applies durable updates.
- Verification must remain runnable without prompts or live model calls.

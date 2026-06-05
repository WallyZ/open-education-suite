# Context Pack

Use this compact context for a single focused wave.

Generated: 2026-06-05

## Context profile
- Profile: cloud (requested: cloud)
- Profile note: Cloud profile: keep richer context for speed/quality, but remain bounded to control token cost.
- Line budgets: activeContext<=200, progress<=280, context-pack<=140
- Text caps: max_items=8, max_line_length=200

## Objective
- Review docs terminology lint for education-suite vocabulary [PH2]

## TODO source files scanned
- docs/todo/00_repo_bootstrap.md

## Must-read files
- memory-bank/activeContext.md
- memory-bank/progress.md
- docs/TODO.md

## Constraints
- Keep scope limited to the active TODO/wave objective.
- Keep notes compact; avoid raw logs and long transcripts.
- Prefer links over pasted dumps for large context.

## Acceptance criteria
- Active context and progress reflect current objective and TODO deltas.
- Context remains concise and action-oriented within profile budgets.

## Verification commands
- `git status --short`
- `pwsh -File .\scripts\memory\refresh_memory_bank.ps1 -DryRun`
- python scripts/lifecycle/check_memory_bank.py --repo-root . --profile cloud

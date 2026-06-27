# Context Pack

Use this compact context for a single focused wave.

Generated: 2026-06-27

## Context profile
- Profile: 32k (requested: auto)
- Profile note: Local AI 32k profile: extremely aggressive compression/cutting to stay within tight windows.
- Line budgets: activeContext<=90, progress<=120, context-pack<=60
- Text caps: max_items=3, max_line_length=120

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
- python scripts/lifecycle/check_memory_bank.py --repo-root . --profile 32k


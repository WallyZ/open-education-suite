# Context Pack

Use this compact context for a single focused wave.

Generated: 2026-10-30

## Context profile

- Profile: cloud; bounded to the current Founder integration.
- Line budgets: activeContext<=200, progress<=280, context-pack<=140.

## Objective

- Persist private grading authority for lesson-g1-cw10-d01 and verify receipts/mastery across actual bridge restarts.

## TODO source files scanned

- docs/todo/TODO_07_learner_state_persistence_and_privacy.md

## Must-read files

- AGENTS.md
- .codex-cache/task-pack.md
- memory-bank/activeContext.md
- docs/assessment-feedback.md

## Constraints

- Preserve 54 pre-existing Founder files. Reuse the approved sequence and canonical mastery updater.
- Keep encrypted DPAPI authority outside Git/HTTP/tutor retrieval. No plaintext fallback or tracked private recovery fixtures.
- Ordinary and synthetic ledgers remain separate; source/mode changes and corrupt stores fail closed.
- No human outcomes, identity, credentials, portable migration or whole-store rollback protection claims.

## Acceptance criteria

- Founder-persistence passed: three scoring processes, two restarts, 168 browser actions; no console/page/network errors.
- Confidence 0.2 and four audit entries recover exactly; replay adds none; withdrawal and stale-receipt rejection persist.
- Memory/catalog refreshed. Broader changed mode stops on two pre-existing Founder safeguarding links; preserve source work and disclose the limitation.
- Recheck founder-persistence after final edits; commit/push intended Suite files only.

## Verification commands

- `pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\codex-verify.ps1 -Mode founder-persistence`
- `pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\codex-verify.ps1 -Mode changed`

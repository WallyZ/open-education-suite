# Repo-Kit Exchange Scripts

These scripts implement the proposal-first cross-repo exchange loop.
They are intentionally non-destructive by default.

## Commands

- `check_due.ps1`: decide whether repo-kit exchange review is due and safe to prompt.
- `watch_due.ps1`: check one or many repos and optionally prompt with review/postpone/skip choices.
- `build_dashboard.ps1`: summarize exchange adoption, due/drift status, and duplicate candidates across repos.
- `run_full_intake_wave.ps1`: run a read-only fleet intake wave (catalog/import/export/drift/due) and emit consolidated reports.
- `catalog_repo.ps1`: catalog repeatable local process/tooling assets.
- `propose_imports.ps1`: compare downstream files against repo-kit exchange defaults.
- `propose_exports.ps1`: identify local catalog items not yet tracked as export candidates.
- `check_drift.ps1`: compare tracked imported items against recorded source hashes.
- `apply_approved_exchange.ps1`: plan or execute reviewed exchange proposals with an explicit approval gate.

## Contract

Scripts may write reports and proposals under `.repo-kit/` in the target repo.
They must not apply file changes, push, publish, or modify another repo without an explicit apply command and owner approval.
`apply_approved_exchange.ps1` runs in plan mode by default; mutation requires `-Execute -ApprovalToken APPROVED`.
`watch_due.ps1` is non-mutating; scheduled usage should write a report and leave interactive review to the operator.
`build_dashboard.ps1` writes dashboard reports only and does not apply exchange proposals.
`run_full_intake_wave.ps1` writes reports only and does not apply exchange proposals.
`catalog_repo.ps1` and `propose_exports.ps1` skip zero-byte and `.gitkeep` placeholders by default (override with `-IncludeZeroByte` when intentionally cataloging placeholders).
`run_full_intake_wave.ps1` supports lane-safe latest aliases through `-LatestAliasPrefix` (for example `reuse_intake_game_unreal`) so focused scans do not overwrite full-fleet `reuse_intake_wave_latest.*`.

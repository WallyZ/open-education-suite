# HANDOFF

- Last updated: 2026-10-30

## Current Objective

Complete restart-safe private grading authority for the same Founder sequence. Verify with QA Live, preserve unrelated work, commit and push.

## Current State

- Prior commits 3683f59, 17bf674 and 675affd establish consumer recovery, live UI and independent structured assessment.
- OES_FOUNDER_PRIVATE_AUTHORITY_001 adds Windows-user DPAPI encryption for signing authority, canonical state and replay records in one SQLite transaction.
- Ordinary authority defaults to ignored .repo-kit-local/grading/ordinary-v1.sqlite; synthetic QA uses isolated run-temp stores.
- Founder-persistence passed, exit 0; log .codex-cache/logs/codex-verify_20261030_120117_20e4db77.log.
- QA Live passed 168 actions, including three distinct scoring bridge processes and two actual restarts, with no console/page/network errors.
- Exact mastery/audit recovery, committed replay, withdrawal and stale-receipt rejection passed.
- Final changed-mode gate found six stale memory surfaces; this refresh replaces obsolete Wave 47 handoff status.
- Memory/catalog refresh is complete. Broader changed mode stops on two pre-existing Founder links to missing safeguarding-and-mandatory-reporting-operations.md; source files are preserved.
- Founder has 54 protected pre-existing files; hashes remain unchanged. QA Live harness remains clean.

## Next Commands (Max 5)

1. Recheck canonical founder-persistence after final edits; report the broader changed-mode source-link limitation.
2. Inspect exact staged Suite files and preservation hashes.
3. Commit/push verified Suite candidate to origin/main.

## Must Read

- AGENTS.md
- .codex-cache/task-pack.md
- docs/assessment-feedback.md
- docs/todo/TODO_07_learner_state_persistence_and_privacy.md

## Boundaries

- Curriculum and protected keys stay in Founder; Suite owns runtime integration. Reuse existing tasks and sequence.
- Keep private authority, answers, learner records and recovery fixtures outside Git/HTTP/tutor context.
- Store recovery requires the same Windows DPAPI account/profile. Portable migration and whole-store rollback defenses are separate work.
- Synthetic QA does not establish real learning outcomes, identity, outside-help prevention or credentials.
- Preserve canonical verification composition; do not vendor QA Live or install dependencies.

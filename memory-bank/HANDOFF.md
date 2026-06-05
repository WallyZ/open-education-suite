# HANDOFF

- Last updated: 2026-06-05

## Current Objective
Repo-kit standards adoption is complete and verified. The next open TODO is `OES_DOCS_TERMINOLOGY_LINT_001`: review docs terminology lint for education-suite vocabulary.

## Current State
- Repo-kit standards are installed and tailored for `open-education-suite`.
- The verifier runs TODO format, ready queue, memory-bank, and platform checks through one entrypoint.
- `scripts/status/next-work.ps1` sees `00_repo_bootstrap.md` and reports three open follow-up items.

## Next Commands (Max 5)
1. `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\status\next-work.ps1`
2. `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex-verify.ps1`
3. `python scripts/lifecycle/check_todo_format.py --repo-root . --todo-root docs/todo --min-severity info --fail-on error`
4. `python scripts/lifecycle/check_todo_ready_queue.py --repo-root . --todo-root docs/todo --min-severity info --fail-on error --report -`
5. `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\memory\refresh_memory_bank.ps1 -RepoRoot . -ContextProfile cloud`

## Must Read
- `AGENTS.md`
- `.codex-cache/task-pack.md`
- `memory-bank/context-pack.md`
- `docs/TODO.md`
- `docs/todo/00_repo_bootstrap.md`

## Boundaries
- Do not mutate sibling content repos unless the user explicitly asks.
- Do not vendor QA Live harness code.
- Do not commit `.codex-cache/`, generated media, learner private data, traces, logs, or local reports.

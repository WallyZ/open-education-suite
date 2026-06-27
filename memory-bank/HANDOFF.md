# HANDOFF

- Last updated: 2026-06-21

## Current Objective
Register the American History reference pilot as a sibling content repo and keep Open Education Suite as the central content-agnostic interface.

## Current State
- `F:\dev\open-education-american-history` contains the imported pilot pack plus suite adapter files.
- `content-sources.json` registers `american-history`.
- `docs/program-pack-template.md` defines the suite-owned program-pack standard.
- `ui/learner/session-data.js` has been exported and includes the American History source/course/objectives.

## Next Commands (Max 5)
1. `.\scripts\codex-verify.ps1`
2. `Select-String -Path .\ui\learner\session-data.js -Pattern 'american-history' -Context 0,2`
3. `Set-Location F:\dev\open-education-american-history`
4. `.\scripts\codex-verify.ps1`
5. `git status --short`

## Must Read
- `AGENTS.md`
- `.codex-cache/task-pack.md`
- `memory-bank/context-pack.md`
- `content-sources.json`
- `docs/program-pack-template.md`
- `docs/TODO.md`
- `F:\dev\open-education-american-history\content-repo.json`

## Boundaries
- Do not copy subject course bodies into the suite.
- Do not vendor QA Live harness code.
- Do not commit `.codex-cache/`, generated media, learner private data, traces, logs, or local reports.

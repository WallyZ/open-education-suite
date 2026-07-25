# HANDOFF

- Last updated: 2026-07-24

## Current Objective
Keep learner content URLs stable when a registered content repo is renamed, junction-mounted, or checked out into an isolated worktree.

## Current State
- `scripts/teaching/export-learner-ui-session.ps1` reads an optional URL-safe `httpSlug` from a content repo manifest.
- Existing content repos without `httpSlug` retain the repository-folder fallback.
- The Founder content repo declares `open-education-founder-level-civic-classical`, so isolated worktrees export the same learner bridge root.
- The canonical verifier checks the stable-slug implementation markers.

## Next Commands (Max 5)
1. `.\scripts\codex-verify.ps1`
2. `git diff --check`
3. `git status --short`

## Must Read
- `AGENTS.md`
- `.codex-cache/task-pack.md`
- `memory-bank/context-pack.md`
- `scripts/teaching/export-learner-ui-session.ps1`
- `docs/WORKFLOW.md`
- `docs/todo/TODO_01_content_ingestion_and_packaging.md`

## Boundaries
- Do not copy subject course bodies into the suite.
- Do not vendor QA Live harness code.
- Do not derive a manifest-declared public content route from an incidental checkout name.
- Do not commit `.codex-cache/`, generated media, learner private data, traces, logs, or local reports.

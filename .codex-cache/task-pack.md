# Codex Task Pack

## Current Mission

Build Open Education Suite into a content-agnostic adaptive AI teaching platform. Keep subject content in sibling `open-education-*` repos and keep this repo focused on ingestion, learner state, assessment, AI-teacher orchestration, quality gates, and runnable teaching workflows.

## Start Here

1. Read `AGENTS.md`.
2. Read this task pack.
3. Run `.\scripts\status\next-work.ps1` to find the first open TODO.
4. State the intended verification command before editing: `.\scripts\codex-verify.ps1`.
5. Work the smallest relevant file set for the selected TODO.

## Smallest Relevant File Sets

- TODO selection: `docs/TODO.md`, `docs/todo/TODO_*.md`, `scripts/status/next-work.ps1`
- Content ingestion/package work: `content-sources.json`, `scripts/ingestion/`, `docs/content-ingestion.md`, `docs/content-package-format.md`
- Learner state work: `schemas/learner-state.schema.json`, `fixtures/learner-state*.json`, `scripts/state/`, `docs/learner-state-privacy.md`
- Teaching session work: `scripts/teaching/`, `scripts/testing/run-golden-session.ps1`, `fixtures/`
- Assessment work: `schemas/assessment.schema.json`, `fixtures/assessment-items.json`, `scripts/assessment/`, `docs/assessment-feedback.md`
- AI teacher work: `schemas/ai-teacher.schema.json`, `fixtures/ai-teacher-response.grounded.json`, `scripts/ai/`, `docs/ai-teacher-integration.md`
- Quality work: `scripts/quality/`, `fixtures/golden-workflows.json`, `fixtures/teaching-quality-benchmarks.json`, `docs/teaching-quality-rubric.md`
- Content repo work: sibling repos under `F:\dev\open-education-*`; keep domain content out of this core repo

If more than 3-5 files are needed, justify it in the working update before editing.

## Current Repo Shape

- Core repo: `F:\dev\open-education-suite`
- Content repos:
  - `F:\dev\open-education-cybersecurity`
  - `F:\dev\open-education-data-science`
  - `F:\dev\open-education-game-development`
  - `F:\dev\open-education-software-development`
- Content source registry: `content-sources.json`
- Master TODO index: `docs/TODO.md`
- Split TODO files: `docs/todo/TODO_*.md`

## Verification

Use exactly:

```powershell
.\scripts\codex-verify.ps1
```

The verification entrypoint checks required files, content ingestion, learner decisions, assessment evaluation, state validation/update/audit, golden workflows, golden teaching session, AI prompt/output fixtures, package build/validation, content quality, and teaching quality.

## Codex Operating Notes

- Do not add domain study plans or resource libraries back into this core repo.
- Do not mutate content repos during ingestion or package generation.
- Use `.codex-cache\tmp\<run-id>\` for temp artifacts.
- Keep generated logs under `.codex-cache\logs\`.
- Prefer PowerShell-native commands and repo scripts.
- Update TODO checkboxes only when the repo has concrete artifacts and verification coverage for the item.
- Preserve deterministic fixture verification before adding live model calls.

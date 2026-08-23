# HANDOFF

- Last updated: 2026-08-23

## Current Objective

Verify that Open Education Suite remains content-agnostic while sibling subject packs adopt source-grounded advanced evaluation and optional third-party credential pathways.

Complete root-owned Markdown lint fleet Wave 47 without weakening those boundaries or the existing canonical verification suite.

## Current State

- American History remains registered through `content-sources.json`; its curriculum and evaluation policy stay in the sibling subject repository.
- American History version 1.1.0 uses named benchmarks, source and citation checks, learner artifacts, separate evaluation passes, adversarial defense, revision, retention, transfer, and reproducibility for advanced performance.
- Qualified historians and human committees are optional for the default noncredentialing path. An authorized third-party provider controls any opt-in degree or certification requirements and award.
- The Suite must not infer, award, or guarantee a credential from completion or an automated score.
- The clean Wave 47 baseline reached memory validation and stopped only because six memory surfaces were 15 days old.
- The tracked memory bank and repo-kit catalog were refreshed on 2026-08-23.
- The Wave 47 candidate passes exact changed and full canonical verification while preserving cross-repository ingestion, browser, lecture-production, and QA Live checks; independent review and commit/push remain.

## Next Commands (Max 5)

1. `git diff --check`
2. `git status --short`
3. After independent approval, commit the exact staged candidate.
4. Push the approved commit to `origin/main`.

## Must Read

- `AGENTS.md`
- `.codex-cache/task-pack.md`
- `memory-bank/context-pack.md`
- `content-sources.json`
- `docs/content-ingestion.md`
- `docs/program-pack-template.md`
- `..\open-education-american-history\program.yaml`

## Boundaries

- Do not copy subject course bodies into the suite.
- Do not vendor QA Live harness code.
- Do not treat source quality, completion, or one opaque automated score as proof of advanced learner performance.
- Do not claim a degree or certification without an authorized third-party provider's award record.
- Do not make qualified historians a default subject-pack completion dependency when reproducible source-grounded evidence can establish the performance claim.
- Do not commit `.codex-cache/`, generated media, learner private data, traces, logs, or local reports.

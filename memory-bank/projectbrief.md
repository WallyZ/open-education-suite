# Project Brief

## Project

- Name: open-education-suite
- Repo path: F:\dev\open-education-suite
- Primary maintainer: WallyZ

## Mission

Build a content-agnostic adaptive AI teaching platform core. This repo owns ingestion, learner state, assessment, AI-teacher orchestration, learner UI contracts, QA gates, and runnable teaching workflows.

## Success outcomes

- Content repos can be ingested read-only through `content-sources.json`.
- Learner state is local-first, auditable, and privacy-preserving.
- Assessment uses essays as the default high-rigor summative evidence and keeps quizzes diagnostic.
- The learner UI and QA Live contracts can prove real functionality without manual-only checks.
- Shared repo-kit process assets stay current without replacing platform-specific behavior.

## Non-goals

- Do not store subject study plans, generated lecture media, or domain resource libraries in this core repo.
- Do not vendor `qa-live-test-system` or sibling content repos.
- Do not add live external service calls to default verification.

## Critical constraints

- Verify through `scripts/codex-verify.ps1`.
- Keep temp artifacts under `.codex-cache/tmp/<run-id>/` and logs under `.codex-cache/logs/`.
- Keep sibling content repo access read-only unless the user explicitly requests a content repo wave.

# Solution Harvest

## Metadata
- Last updated: 2026-06-05
- Repo: open-education-suite
- Privacy default: internal

## Candidate Reusable Solutions

### Content-source registry contract
- Local path: `content-sources.json`
- Reuse value: read-only sibling repo ingestion with provenance and content repo boundaries.
- Privacy: internal; strip private local paths before public examples.

### Essay-first assessment policy
- Local path: `docs/assessment-feedback.md`
- Reuse value: keeps high-rigor mastery evidence separate from diagnostic quizzes.
- Verification: `scripts/codex-verify.ps1` checks fixture policy and evidence weighting.

### Learner-state privacy/audit pattern
- Local path: `docs/learner-state-privacy.md`
- Reuse value: local-first learner state, redaction, export boundaries, and audit explanations.

### QA Live learner UI contract
- Local path: `qa-live/workflow.learner_ui_live.json`
- Reuse value: repo-owned contract invoking adjacent QA Live harness without vendoring it.

### Content package generator
- Local path: `scripts/ingestion/build-content-package.ps1`
- Reuse value: deterministic package build with source provenance and no source repo mutation.

## Promoted to Repo-Kit
- None yet. Review candidates through `.repo-kit/exchange.json` before upstreaming.

# Solution Harvest

## Metadata

- Last updated: 2026-08-23
- Repo: open-education-suite
- Privacy default: internal

## Candidate Reusable Solutions

### Content-source registry contract

- Local path: `content-sources.json`
- Reuse value: read-only sibling repo ingestion with provenance and content repo boundaries.
- Privacy: internal; strip private local paths before public examples.

### Checkout-independent content HTTP routes

- Local path: `scripts/teaching/export-learner-ui-session.ps1`
- Reuse value: lets a content manifest declare a stable URL slug while retaining a folder-name fallback for existing repos.
- Privacy: public-safe; the route contains a manifest slug, not a local filesystem path.

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

### Program-pack template contract

- Local path: `docs/program-pack-template.md`
- Reuse value: reusable world-class subject pack standard with benchmark, competency, assessment, rubric, provenance, and maintenance requirements.
- Privacy: public-safe after replacing local paths with repo-relative examples.

### Subject-owned advanced-evaluation and credential boundary

- Local path: sibling subject-pack `program.yaml` and release contracts; American History version 1.1.0 is the current reference.
- Reuse value: keeps named benchmarks, source checks, learner artifacts, independent evaluation passes, defense, revision, retention, transfer, and reproducibility in the subject repo while the Suite remains content-agnostic.
- Claim boundary: a subject repo or Suite may report demonstrated performance but may not award or guarantee a degree or certification; only an authorized third-party provider's award record supports the exact credential claim.
- Human boundary: qualified experts are optional for the default noncredentialing path and provider-required only on a learner's opt-in credential pathway.
- Privacy: reviewer identities, qualification evidence, attestations, learner records, and provider award records remain private-local unless specifically consented and redacted.

## Promoted to Repo-Kit

- None yet. Review candidates through `.repo-kit/exchange.json` before upstreaming.

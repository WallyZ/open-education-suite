# RELEASE_CHECKLIST

Release and closeout checklist for `open-education-suite`.

## 1. Scope and boundaries

- [ ] Confirm the release or wave scope.
- [ ] Confirm no subject content, generated lecture media, learner private data, credentials, or local artifacts are being added to the core repo unintentionally.
- [ ] Confirm any sibling content repo dependency is read-only unless explicitly requested.
- [ ] Update `docs/decisions.md` for durable technical or workflow decisions.

## 2. TODO and docs

- [ ] Update `docs/TODO.md` and the relevant `docs/todo/*.md` items.
- [ ] Mark TODO items `[x]` only when artifact evidence and verification are present.
- [ ] Add follow-up TODOs for gaps, useful improvements, drift risks, or broad work that should be split.
- [ ] Update affected docs for content ingestion, learner state, assessment, AI teacher, UI, QA Live, or release behavior.
- [ ] Refresh `memory-bank/` when status, reusable solutions, or pitfalls changed.

## 3. Automated validation

Run from repo root:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex-verify.ps1
```

This verifier covers:

- required file and folder contracts,
- TODO format and ready-queue lifecycle checks,
- content-source ingestion and package generation,
- learner-state validation, update, and audit,
- assessment fixtures and essay-first high-rigor policy,
- adaptive teacher and AI-teacher deterministic fixtures,
- learner UI static and browser/QA Live workflow checks,
- lecture package and teaching-quality gates,
- next-work status helper behavior.

## 4. QA Live-first validation

- [ ] If the change affects learner UI, browser automation, runtime teaching workflow, generated lecture playback, or live QA behavior, run the repo-owned QA Live workflow through `scripts/testing/run-qa-live-learner-ui.ps1` or the verifier.
- [ ] If QA Live lacks a needed automatable capability, update the repo-owned `qa-live/` contract or the adjacent `F:\dev\qa-live-test-system` capability before treating the behavior as manual.
- [ ] Record the QA Live report path, expected result, and observed status in TODO evidence or release notes.
- [ ] Do not vendor QA Live harness code into this repo.

## 5. Artifact review

- [ ] Review generated packages, reports, screenshots, traces, logs, local media, and `.codex-cache/` files before staging.
- [ ] Stage only source files, docs, schemas, fixtures, and intentional repo-owned specs.
- [ ] Keep secrets, `.env*`, learner private data, generated media, Playwright artifacts, and transient reports untracked or ignored.

## 6. User-only exceptions

List user-only validation only when automation or QA Live cannot prove the behavior, such as:

- subjective teaching quality or creative media review,
- private account or billing state,
- credentials the agent cannot access,
- physical device or host UI state unavailable to automation.

Each user-only item must include the location, action, expected result, and why it cannot be automated.

## 7. Commit and push

- [ ] Confirm `.repo-kit/workflow_policy.local.json` does not require PR flow.
- [ ] Commit the related change set on `main`.
- [ ] Push to `origin/main`.
- [ ] Report the verifier command, pass/fail status, and log path.

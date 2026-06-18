# Codex Task Pack

## Objective

Refresh suite-generated learner catalog metadata after the registered `open-education-mens-relationship-skills` content repo added the Phase 3 `MRS-303` modern dating safety, sexual health, breakup recovery, practical partnership, and referral-boundary course.

## Smallest Relevant File Set

- ui/learner/session-data.js
- F:\dev\open-education-mens-relationship-skills\*

## Intended Verification Command

```powershell
.\scripts\codex-verify.ps1
```

## Scope Guardrails

- Keep Open Education Suite content-agnostic; do not copy course content into suite docs.
- Update generated learner catalog metadata only.
- Do not add learner PII, private relationship logs, dating messages, surveillance data, credentials, secrets, or local private paths.

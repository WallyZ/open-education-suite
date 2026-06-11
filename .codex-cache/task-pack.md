# Codex Task Pack

## Objective

Add the actual `open-education-suite` consumer adapter for `assessment-mastery/assessment/v1`, exporting public-safe assessment/rubric/mastery metadata without learner submissions, learner PII, private feedback bodies, private course content, generated media, secrets, credentials, local paths, or private datastore rows.

## Smallest Relevant File Set

- scripts/assessment/export-assessment-mastery-contract.ps1
- scripts/codex-verify.ps1
- docs/assessment-feedback.md
- docs/todo/TODO_03_assessment_practice_and_feedback.md
- fixtures/assessment-items.json
- fixtures/mastery-calibration.json

## Intended Verification Command

```powershell
.\scripts\codex-verify.ps1
```

## Scope Guardrails

- Emit metadata only: logical refs, sanitized IDs, rubric/task/mastery policy, feedback template refs, privacy flags, and output refs.
- Do not emit learner submissions, learner PII, private feedback bodies, private course content, generated media, credentials, secrets, absolute private paths, or local datastore rows.
- No changes to assessment scoring behavior unless needed for the adapter surface.

# Codex Task Pack

## Objective

Add the smallest usable local-first learner profile system so multiple students can use Open Education Suite on the same computer with separate preferences, learning style, accessibility needs, goals, progress, assessment history, and recommendation context.

## Smallest Relevant File Set

- ui/learner/*
- scripts/*
- tests/*
- docs/TODO.md
- docs/WORKFLOW.md
- scripts/codex-verify.ps1

## Intended Verification Command

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex-verify.ps1
```

## Scope Guardrails

- Keep the suite content-agnostic; do not copy course content into the suite.
- Keep learner data local-first and avoid authentication, cloud sync, or external identity providers.
- Support multiple learners on one computer through explicit local learner selection and isolated profile/progress records.
- Do not add learner PII beyond user-entered display name/preferences.
- Add concrete TODOs only for discovered gaps that remain after the usable slice is implemented.

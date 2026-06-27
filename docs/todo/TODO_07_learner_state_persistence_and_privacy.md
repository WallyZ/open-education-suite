# TODO 07 - Learner State Persistence and Privacy

## Goal

Create durable learner state that can support real adaptation while protecting learner privacy and preserving auditability.

## Why This Matters

Great teachers remember what a student knows, where they struggle, and what support works. The suite needs that memory in a safe, inspectable form.

## Tasks

- [x] Define a versioned learner-state file format for profile, goals, mastery, misconceptions, review queue, and learning events. <!-- ms:id 01e8c6feb29d -->
- [x] Add a learner-state loader that validates schema version and rejects malformed records. <!-- ms:id 0fd2238be1b7 -->
- [x] Add an append-only learning event log with event ids and timestamps. <!-- ms:id f3a8d34609ee -->
- [x] Add a state update function that applies assessment results to mastery evidence. <!-- ms:id 06ad7c2eed23 -->
- [x] Add a misconception update function that can create, preserve, and resolve misconceptions. <!-- ms:id 9acc7f351800 -->
- [x] Add review queue persistence with due dates and reason codes. <!-- ms:id a5db17ebbde6 -->
- [x] Add privacy rules for personally identifying fields, local storage, redaction, and export. <!-- ms:id 28bcdca09650 -->
- [x] Add a learner-state audit report that explains why each mastery value changed. <!-- ms:id d0d4ad405571 -->
- [x] Add conflict-safe local sync rules for future offline/online merging. <!-- ms:id 5885d8cfa1bc -->
- [x] Add verification fixtures for valid state, invalid state, update-after-answer, and returning-after-gap. <!-- ms:id 13cc67116db3 -->
- [x] Add same-computer multi-learner profile isolation for local learner state, journals, assessment evidence, checkpoints, lecture resume, and course selection. <!-- ms:id 9f3a1c47b2de -->
  - Evidence (2026-06-27): `ui/learner/app.js` now stores `openEducationLearnerProfiles`, `openEducationActiveLearnerId`, and learner-scoped browser keys; `docs/learner-state-privacy.md` documents the scoped-key contract; `tests/learner-ui.spec.js` verifies two local profiles keep journal and state records separate. Verification: `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex-verify.ps1` passed (`.codex-cache\logs\codex-verify_20260627_104945_a404c6e9.log`).

## Acceptance Notes

- Learner state must be human-inspectable during early development.
- State updates must be deterministic and explainable.
- Privacy and audit rules should exist before adding hosted storage.

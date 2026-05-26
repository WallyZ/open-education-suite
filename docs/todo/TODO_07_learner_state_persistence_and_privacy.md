# TODO 07 - Learner State Persistence and Privacy

## Goal

Create durable learner state that can support real adaptation while protecting learner privacy and preserving auditability.

## Why This Matters

Great teachers remember what a student knows, where they struggle, and what support works. The suite needs that memory in a safe, inspectable form.

## Tasks

- [x] Define a versioned learner-state file format for profile, goals, mastery, misconceptions, review queue, and learning events.
- [x] Add a learner-state loader that validates schema version and rejects malformed records.
- [x] Add an append-only learning event log with event ids and timestamps.
- [x] Add a state update function that applies assessment results to mastery evidence.
- [x] Add a misconception update function that can create, preserve, and resolve misconceptions.
- [x] Add review queue persistence with due dates and reason codes.
- [x] Add privacy rules for personally identifying fields, local storage, redaction, and export.
- [x] Add a learner-state audit report that explains why each mastery value changed.
- [x] Add conflict-safe local sync rules for future offline/online merging.
- [x] Add verification fixtures for valid state, invalid state, update-after-answer, and returning-after-gap.

## Acceptance Notes

- Learner state must be human-inspectable during early development.
- State updates must be deterministic and explainable.
- Privacy and audit rules should exist before adding hosted or multi-user storage.

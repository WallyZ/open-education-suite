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

## Acceptance Notes

- Learner state must be human-inspectable during early development.
- State updates must be deterministic and explainable.
- Privacy and audit rules should exist before adding hosted or multi-user storage.

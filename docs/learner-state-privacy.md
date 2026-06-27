# Learner State Persistence and Privacy

Learner state is the durable memory that lets the suite adapt over time. It must be inspectable, deterministic, and privacy-conscious before hosted or multi-user storage exists.

## State File Contract

The schema lives in `schemas/learner-state.schema.json`. A learner state file contains:

- `schemaVersion`
- `learnerId`
- `profile`
- `mastery`
- `misconceptions`
- `reviewQueue`
- `learningEvents`
- `auditLog`
- `privacy`
- `sync`

## Privacy Rules

- Store local learner state only where the user explicitly chooses or under test fixtures.
- Keep personally identifying fields out of fixtures.
- Redact free-text profile fields before exporting support bundles.
- Treat accommodations as sensitive learner data.
- Keep learning events append-only for auditability.
- Apply deterministic code to state updates; model output may propose changes but must not write state directly.

## Audit Rules

Every mastery-changing update should append an audit log entry with:

- timestamp
- objective id
- old confidence
- new confidence
- evidence source
- reason

## Local Sync Rules

Future offline/online sync should:

- preserve append-only events from both sides
- keep the highest schema version only after migration
- avoid overwriting newer mastery evidence with older values
- resolve conflicts by retaining both evidence records and recomputing mastery

## Learner UI Local State

The learner UI stores a local profile registry in browser `localStorage` under `openEducationLearnerProfiles` plus the selected learner id in `openEducationActiveLearnerId`. Each learner profile has a stable `learnerId`, display name, goals, preferences, accommodations, prior experience, and timestamps.

Learner-owned records use profile-scoped keys so multiple students can use the same computer/browser without overwriting each other:

- `openEducationLearnerState:<learnerId>`
- `openEducationAssessmentEvidence:<learnerId>`
- `openEducationLectureCheckpoints:<learnerId>`
- `openEducationLearnerJournal:<learnerId>`
- `openEducationLectureResume:<learnerId>`
- `openEducationLastCourseSelection:<learnerId>`

The UI can save, export, import, and preview sync conflicts locally; the preview reports incoming learning events and mastery differences without mutating state. Hosted or multi-device sync must keep the same append-events-and-recompute-mastery conflict policy and must not merge profile-scoped records without explicit learner identity mapping.

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

- [x] Persist private Founder grading authority and verify recovery across bridge restarts. [PH2] <!-- ms:id OES_FOUNDER_PRIVATE_AUTHORITY_001 --> <!-- ms:meta priority=p1 owner=@suite depends-on=OES_FOUNDER_INDEPENDENT_001 stale-days=30 automation-level=auto human-checkpoint=none rollout-scope=repo validation-profile=cloud safe-autofix=review updated=2026-10-30 -->
  - Deliverables: Windows-user-encrypted transactional authority, stable receipts and replay cache, private-root exclusions, restart QA and documented recovery limits.
  - Files: private grading store, existing grader/bridge, scoring tests and QA preparer, restart feature spec, canonical verifier, Founder UI verification message, ignore rules, assessment documentation, this TODO and task pack.
  - Verification: `pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\codex-verify.ps1 -Mode founder-persistence`.
  - QA Live automation: retain the prior UI regression; create scored evidence, stop the bridge, recover through a fresh bridge/browser, replay without another update, then restart again and verify withdrawal/stale-receipt rejection.
  - Drift guard: source/mode/format bindings, current-receipt validation, transactional rollback, encrypted storage and corruption rejection, distinct bridge-instance markers and exact mastery/audit counts.
  - Downstream rollout: same Founder sequence and canonical updater; Founder stays read-only. No external service, identity/credential claim or unreviewed data migration. Broader changed-mode verification stops on two pre-existing Founder safeguarding-document links (`.codex-cache/logs/codex-verify_20261030_120718_ab0dc690.log`); those protected files are preserved.
  - Acceptance: signed authority and canonical state survive two bridge restarts; pending/committed submissions remain idempotent; wrong/forged/stale receipts fail; the private store is absent from Git, HTTP and tutor retrieval.
  - Evidence (2026-10-30): canonical `-Mode founder-persistence` passed, exit 0; log `.codex-cache/logs/codex-verify_20261030_120117_20e4db77.log`. QA Live evidence under `.codex-cache/logs/founder-ui-qa_20261030_120117_20e4db77_{0,1,2,3}`: 61 regression, 77 scoring, 15 recovery/replay and 15 withdrawal actions passed; zero console/page/network errors. Three distinct scoring bridge instances stopped between phases; recovered confidence 0.2 and four audit entries without duplicate evidence. Storage checks passed for pending-token recovery, rollback, encryption, corruption and source/mode mismatch. Windows DPAPI profile portability and whole-store backup rollback protection are separate boundaries.

- Learner state must be human-inspectable during early development.
- State updates must be deterministic and explainable.
- Privacy and audit rules should exist before adding hosted storage.

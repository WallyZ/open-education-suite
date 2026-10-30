# TODO 03 - Assessment, Practice, and Feedback

## Goal

Build assessment and practice primitives that let the teacher gather evidence, provide hints, and adapt without depending on a single content domain.

## Source Ideas

- OATutor uses hinting and scaffolding as part of adaptive tutoring.
- H5P demonstrates reusable interactive content types.
- INGInious focuses on automated assessment for programming-style tasks.
- Canvas and Sakai provide mature assignment, quiz, and feedback workflows.

## Tasks

- [x] Define platform-neutral assessment item types: recall, multiple choice, short answer, code/task, project checkpoint, and reflection. <!-- ms:id 000bac487bb5 -->
- [x] Define a hint/scaffold schema with escalating levels from nudge to worked example. <!-- ms:id c69f39c21da4 -->
- [x] Add answer-evaluation hooks that can be deterministic first and AI-assisted later. <!-- ms:id 0b50b3c07f12 -->
- [x] Support project checkpoints that produce mastery evidence without requiring a traditional quiz. <!-- ms:id 47d565f19cd7 -->
- [x] Add feedback templates for correct, partially correct, incorrect, and uncertain answers. <!-- ms:id 7f5f35a3860b -->
- [x] Track hint usage as mastery evidence instead of treating hints as invisible help. <!-- ms:id d412313c5534 -->
- [x] Define how content repos can contribute reusable interactive exercises without coupling to the core UI. <!-- ms:id 6c457bffe171 -->
- [x] Export public-safe Assessment Mastery pack metadata. <!-- ms:evidence id=OES_ASSESSMENT_MASTERY_ADAPTER_001 paths="scripts/assessment/export-assessment-mastery-contract.ps1,scripts/codex-verify.ps1,docs/assessment-feedback.md,docs/todo/TODO_03_assessment_practice_and_feedback.md" strings="assessment-mastery/assessment/v1,export-assessment-mastery-contract.ps1,logical_refs_only" -->
  - Evidence (2026-06-10): Added `scripts/assessment/export-assessment-mastery-contract.ps1` to emit sanitized `assessment-mastery/assessment/v1` metadata from fixture-backed assessment items, wired the export into `scripts/codex-verify.ps1`, and documented the handoff command in `docs/assessment-feedback.md`.

## Acceptance Notes

- [x] Add server-scored structured assessment for the selected Founder sequence. [PH2] <!-- ms:id OES_FOUNDER_INDEPENDENT_001 --> <!-- ms:meta priority=p1 owner=@suite depends-on=OES_FOUNDER_LOOP_UI_001 stale-days=30 automation-level=auto human-checkpoint=none rollout-scope=repo validation-profile=cloud safe-autofix=review updated=2026-10-30 -->
  - Deliverables: protected grader adapter, canonical mastery updates, verified receipts, UI controls and private QA inputs for the existing forms.
  - Files: `scripts/assessment/founder_independent.py`, `scripts/testing/check_founder_independent.py`, learner bridge, Founder UI module/index, learner-state UI integration, assessment QA template, canonical verifier, this TODO, assessment documentation, and task pack.
  - Verification: `pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\codex-verify.ps1 -Mode founder-assessment`.
  - QA Live automation: reuse the prior UI workflow as regression; materialize `qa-live/feature_spec.founder_assessment.json` privately and run the real browser against an operator-enabled rehearsal bridge. Retain synthetic evidence in ignored logs.
  - Drift guard: protected-bank/source hashes, strict submissions, current signed receipts, idempotency, support/timing/withdrawal gates, canonical audit counts and daily-objective scope.
  - Downstream rollout: Founder stays read-only. No new curriculum, human reviewer, credential, model service or publication authority.
  - Acceptance: incorrect/partial/assisted input cannot increase confidence; successful declared-unassisted retry/delayed input updates canonical state once; forged/cross-learner/stale/restarted receipts fail; tutor/public responses exclude private grading fields.
  - Evidence (2026-10-30): canonical scoring checks and both QA Live workflows passed: 61 self-check regression actions and 80 independent-scoring actions, zero console/page/network failures, teardown passed. Incorrect and assisted answers left confidence at 0; successful declared-unassisted retry and delayed evidence raised the daily objective to 0.1 and 0.2 with four audit entries; replay, forged import and withdrawal checks passed. Log: `.codex-cache/logs/codex-verify_20261030_101151_25a573af.log`; retained QA evidence has the matching run ID with suffixes `_0` and `_1`. This is deterministic structured scoring, not unrestricted essay evaluation or independently observed learner outcomes. Durable private scoring-authority recovery remains a separate gate.

- Assessment output must update mastery evidence.
- Hints should preserve learner agency before revealing full solutions.
- Project feedback should cite the relevant objective and source content.

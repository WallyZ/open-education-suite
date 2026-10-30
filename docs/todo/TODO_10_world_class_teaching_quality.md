# TODO 10 - World-Class Teaching Quality

## Goal

Make the suite aim at expert teaching quality: diagnostic, adaptive, motivating, rigorous, humane, accessible, and measurably effective.

## Teaching Standard

The teacher should behave like a top human tutor:

- diagnose before prescribing
- teach from first principles when needed
- adapt explanations to the learner
- ask high-quality questions
- give timely, specific feedback
- preserve confidence while maintaining rigor
- build durable mastery, not short-term completion
- know when to review, when to challenge, and when to slow down

## Tasks

- [x] Define a teaching quality rubric covering clarity, correctness, diagnosis, scaffolding, feedback, motivation, rigor, accessibility, and learner agency. <!-- ms:id ce265b8bd833 -->
- [x] Add benchmark learner scenarios for bored, anxious, overconfident, confused, advanced, returning, and time-constrained learners. <!-- ms:id 2b4742c7711f -->
- [x] Add misconception libraries per content repo so the teacher can diagnose common failure modes. <!-- ms:id a4109cb05791 -->
- [x] Add mastery calibration checks that compare predicted mastery against later assessment evidence. <!-- ms:id 6522d4060ab4 -->
- [x] Add adaptive difficulty rules that choose easier, equivalent, harder, or transfer tasks based on evidence. <!-- ms:id de8b13351e0b -->
- [x] Add deliberate-practice loops: attempt, feedback, retry, reflection, spacing, and transfer. <!-- ms:id c8141cd1bc6c -->
- [x] Add metacognitive coaching prompts: planning, self-explanation, confidence rating, and reflection. <!-- ms:id 9195cfaea2a0 -->
- [x] Add motivation and persistence supports without false praise or lowered standards. <!-- ms:id 021f6dd4650e -->
- [x] Add teacher self-checks before responding: groundedness, objective alignment, accessibility, and next-step quality. <!-- ms:id 95cf18aaf7a3 -->
- [x] Add human review workflows for teacher behavior regressions and questionable advice. <!-- ms:id 1c42644af3ae -->
- [x] Add longitudinal evaluation metrics: retention, transfer, remediation success, time to mastery, and learner trust. <!-- ms:id d477dc00d03a -->
- [x] Compare the suite against OATutor, Open edX, Moodle, Kolibri, OpenStax Tutor, Canvas, Sakai, H5P, and INGInious for gaps worth adopting. <!-- ms:id b23cf0ef37ee -->

## Acceptance Notes

- [x] Verify the existing Founder sequence through delayed evidence and export recovery. [PH2] <!-- ms:id OES_FOUNDER_LOOP_001 --> <!-- ms:meta priority=p1 owner=@suite stale-days=30 automation-level=auto human-checkpoint=none rollout-scope=repo validation-profile=cloud safe-autofix=review updated=2026-10-29 -->
  - Deliverables: extend the existing export consumer and expose one narrow canonical verifier mode; no new lesson runtime.
  - Files: `scripts/export/check_founder_course_export.py`, `scripts/codex-verify.ps1`, `docs/assessment-feedback.md`, this TODO, and the task pack.
  - Verification: `pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\codex-verify.ps1 -Mode founder-loop`.
  - QA Live automation: not required for this export-consumer rehearsal; it does not exercise or certify UI behavior.
  - Drift guard: pin the Suite schema's existing lesson and the current Founder fixture; validate source checksums, references, negative boundaries, and recovered state.
  - Downstream rollout: read Founder exports without modifying its working tree; retain TODO18 and formal-study gates.
  - Acceptance: execute the synthetic delayed assessment, preserve earlier attempts, reject unsupported scoring and damaged/mismatched restores, and recover the completed temporary state.
  - Evidence (2026-10-29): canonical `founder-loop` passed, including 114,799 exported records, the selected planning handoff, initial level 2, changed retry level 4, delayed level 4, preserved first attempt, completed-state recovery, and ten rejected negative cases. Log: `.codex-cache/logs/codex-verify_20261029_211910_afcac3b5.log`. All 54 pre-existing Founder changes remained byte-for-byte unchanged. No real learner, elapsed-retention, configured-model, UI, or formal-pilot claim.

- "World class" must be measured through behavior and outcomes, not branding.
- The system should optimize for durable learning, not just pleasant answers.
- The best version should make the learner more capable, independent, and honest about mastery.

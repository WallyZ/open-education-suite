# TODO 05 - Interoperability, Quality, and Research

## Goal

Keep the suite compatible with education ecosystems while building repeatable quality checks for adaptive behavior.

## Source Ideas

- Open edX and Moodle have mature integration and deployment ecosystems.
- OATutor is grounded in learning-science research and reports learning gains.
- Learning Locker implements xAPI learning records.
- OpenStax TutorJS uses end-to-end testing around realistic learner workflows.
- Sakai documents release support, accessibility, and internationalization discipline.

## Tasks

- [x] Document an interoperability target list: xAPI first, LTI later, import/export formats as needed.
- [x] Add an event vocabulary for lesson viewed, practice attempted, hint used, mastery updated, review scheduled, and remediation assigned.
- [x] Create deterministic fixtures for adaptive-teacher regression tests.
- [x] Add golden-path learner workflow tests once a UI or CLI teaching loop exists.
- [x] Define content quality checks for broken links, missing attribution, missing objective mappings, and malformed assessments.
- [x] Add evaluation metrics for mastery accuracy, time-to-remediation, hint usefulness, and learner retention.
- [x] Maintain a reviewed-projects section with source links and decisions borrowed or rejected.

## Acceptance Notes

- Quality checks should be runnable through `.\scripts\codex-verify.ps1`.
- Research-inspired features should become testable product behavior, not only notes.
- Interoperability should not compromise the separate content repo boundary.

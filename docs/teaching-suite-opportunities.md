# Teaching Suite Opportunities

These notes capture ideas from comparable open education and adaptive learning projects.

## Projects Reviewed

- [OATutor](https://github.com/CAHLR/OATutor): adaptive tutoring with Bayesian Knowledge Tracing, hints, optional logging, accessibility compliance, and a separate content repository.
- [Open edX Platform](https://github.com/openedx/openedx-platform): separates authoring and learning delivery concerns through Studio/CMS and LMS concepts, with modular platform boundaries.
- [Moodle](https://github.com/moodle/moodle): mature role-based learning platform focused on configurable personalized learning environments and broad community workflows.
- [Kolibri](https://github.com/learningequality/kolibri): offline-first teaching and learning platform with content packaging and distribution as a first-class concern.
- [OpenStax TutorJS](https://github.com/openstax/tutor-js): front-end separated from server and exercise systems, with realistic student workflows and end-to-end testing discipline.

## Ideas to Borrow

- Keep content repositories separate from the teaching engine, with source manifests and attribution.
- Model mastery explicitly by objective, with confidence, recency, and evidence.
- Add a hint/scaffold contract so explanations can escalate from light nudges to worked examples.
- Design for accessibility from the start, including generated materials.
- Support offline or local-first content packages so learners are not blocked by connectivity.
- Separate authoring, teaching, and learner runtime concerns.
- Provide instructor/operator dashboards without making them the source of truth for content.
- Build fixture-based learner scenarios for repeatable testing of adaptive behavior.

## Early Build Priorities

1. Read-only content ingestion from `content-sources.json`.
2. A minimal learner profile and mastery evidence schema.
3. A teaching-loop prototype that chooses the next action from objective mastery.
4. A hint/scaffold format that content repos can optionally provide.
5. Verification fixtures for common learner states: new, struggling, advancing, reviewing, and returning after a gap.

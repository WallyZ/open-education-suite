# Interoperability, Quality, and Research

## Interoperability Targets

1. xAPI-style learning events first, because they map cleanly to learner activity and mastery evidence.
2. LTI later, when the suite needs LMS launch and gradebook integration.
3. Import/export formats as needed for content packages, assessment fixtures, and learner progress exports.

## Event Vocabulary

The first event vocabulary is:

- `lesson_viewed`
- `practice_attempted`
- `quiz_answered`
- `hint_used`
- `mastery_updated`
- `review_scheduled`
- `remediation_assigned`
- `project_checkpoint_submitted`
- `interactive_completed`

Each event should include learner id, verb, object id, timestamp, result, and enough context to map later into xAPI actor, verb, object, and result fields.

## Golden Workflow Tests

`fixtures/golden-workflows.json` defines expected decisions for deterministic learner scenarios. `scripts/testing/run-golden-workflows.ps1` runs those expectations through the current teaching-loop CLI.

These checks are intentionally small and deterministic. They are regression tests for adaptive behavior, not a replacement for learning research.

## Content Quality Checks

`scripts/quality/check-content-quality.ps1` checks:

- content source validation through the ingestion scanner
- missing license or attribution in imported objects
- malformed assessment fixtures
- missing objective mappings in assessments and learner mastery
- broken local Markdown links in core docs and content repos

## Evaluation Metrics

Track these once learner data exists:

- mastery accuracy: later evidence confirms earlier mastery estimates
- time to remediation: time from misconception detection to assigned remediation
- hint usefulness: success after each hint level
- learner retention: return rate after scheduled review
- review effectiveness: confidence change after spaced review
- content health: validation errors per source repo

## Reviewed Projects and Borrowed Decisions

- OATutor: borrow mastery estimation, hint/scaffold structure, and separate content repo boundary.
- Open edX: borrow authoring/runtime separation.
- Moodle: borrow role and personalized learning environment concepts.
- Kolibri: borrow offline-first packaging as a product requirement.
- OpenStax TutorJS: borrow realistic learner workflow testing.
- Canvas LMS: borrow mature course delivery and operator workflow patterns.
- Sakai: borrow accessibility, localization, and release discipline.
- Learning Locker: borrow xAPI-aligned learning event thinking.
- H5P: borrow reusable interactive content type concepts.
- INGInious: borrow automated assessment patterns for task-based work.

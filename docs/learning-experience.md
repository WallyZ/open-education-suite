# Learning Experience and Accessibility

## Core Roles

- Learner: studies content, answers assessments, receives adaptive guidance, and owns personal goals.
- Instructor/operator: monitors progress, reviews blockers, assigns interventions, and checks content health.
- Content author: creates domain content in a content repo without changing platform behavior.
- Reviewer: checks content quality, accessibility, attribution, and objective mapping before content is trusted.

## Learner Home View

The learner home view should prioritize:

- next action with the reason it was selected
- active goals and current objective
- mastery map by objective
- review queue with due dates
- current blockers or misconceptions
- recent feedback and evidence
- source links for the content being taught

The view should avoid hiding the adaptive logic. A learner should know whether they are seeing a new lesson, practice item, review, remediation, quiz, or project because of mastery evidence.

## Course Navigation

The learner workspace exposes the ingested content catalog as read-only navigation over sources, courses, and objectives. Selecting a source, course, or objective helps the learner inspect what exists in content repos, but it does not mutate the active session or learner state; a new teaching session must still be started before the adaptive teacher changes objectives.

## Learner Analytics

Learner analytics should report evidence the learner can inspect: mastery confidence, evidence counts, due reviews, active goals, and source provenance. Avoid surveillance framing such as time-spent judgments, clickstream scoring, hidden engagement labels, or inferred motivation. Analytics are a learner-facing explanation of evidence, not a monitoring surface.

## Instructor/Operator View

The instructor/operator view should prioritize:

- learner progress by goal and objective
- learners blocked by unresolved misconceptions
- overdue reviews and stalled objectives
- content sources with validation errors or missing attribution
- assessment items with low success or high hint usage
- recommended interventions with evidence links

Dashboards are views over learner state, learning events, and content ingestion reports. They must not become a separate source of truth.

## Operator Handoff

The learner workspace includes a read-only handoff view for instructors and operators. It summarizes blockers, suggested interventions, and content health from the active session, content catalog, and lecture QA metadata. Handoff notes must stay review-only until an operator or bridge writes an explicit learner-state update.

## Accessibility Requirements

Generated lessons, quizzes, hints, dashboards, and reports should:

- use semantic headings and lists
- provide text alternatives for images and interactive media
- keep instructions visible outside color alone
- avoid time-only interactions unless an accommodation allows it
- support keyboard navigation for controls
- expose hint levels and feedback in screen-reader friendly order
- keep provenance and attribution readable

## UI Regression Checks

The learner UI browser harness should cover keyboard-only movement across workspace views and a deterministic visual contract for each view. Visual checks should prove the primary panel is visible, sized, non-overflowing, and screenshot-capturable across configured desktop and mobile browser projects.

## Localization Requirements

Content and UI should prepare for localization by separating:

- content titles
- objective names
- prompts
- feedback templates
- hint text
- dashboard labels
- date and number formatting

Generated text should retain source language metadata when content repos provide it.

The learner UI loads a locale module before session data and app logic. Locale modules own fixed labels, date formatting options, objective-name overrides, and reusable feedback strings; dynamic content still comes from content packages and learner state.

## Offline and Low-Connectivity Behavior

When content is packaged locally:

- learners can continue lessons, practice, reviews, and project work from the package
- learning events are queued locally until sync is available
- stale packages are labeled with generation time and source commit if available
- unavailable interactive exercises fall back to static prompts
- sync conflicts preserve learner evidence rather than overwriting it

## Source of Truth

Durable state belongs in:

- content repos for domain source content
- ingestion reports or packages for normalized content snapshots
- learner state for goals, mastery, misconceptions, and events

Dashboards, home screens, and reports should derive from those records.

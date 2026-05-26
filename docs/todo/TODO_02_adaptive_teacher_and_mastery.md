# TODO 02 - Adaptive Teacher and Mastery

## Goal

Create the learner model and teaching loop needed for an AI teacher that adapts to each student's goals, skill, pace, misconceptions, and review history.

## Source Ideas

- OATutor uses Bayesian Knowledge Tracing for skill mastery estimation.
- Moodle emphasizes personalized learning environments.
- OpenStax Tutor separates learner runtime concerns from server/exercise systems.
- Learning Locker shows the value of durable learning event records through xAPI.

## Tasks

- [x] Define a learner profile schema with goals, constraints, preferences, accommodations, and prior experience.
- [x] Define objective-level mastery evidence with confidence, recency, source, and evidence type.
- [x] Add a misconception record that can link mistakes to objectives and remediation paths.
- [x] Prototype a teaching-loop decision function that selects lesson, practice, quiz, review, or remediation.
- [x] Add spaced-review scheduling based on mastery confidence and last evidence date.
- [x] Store learning events in a format that can later map to xAPI-style statements.
- [x] Add fixture learners for new, struggling, advancing, reviewing, and returning-after-a-gap scenarios.

## Acceptance Notes

- The adaptive loop should explain why it chose the next action.
- Mastery should be based on evidence, not only completion.
- The first version can be deterministic before adding model-driven behavior.

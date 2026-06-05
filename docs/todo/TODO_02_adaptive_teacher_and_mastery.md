# TODO 02 - Adaptive Teacher and Mastery

## Goal

Create the learner model and teaching loop needed for an AI teacher that adapts to each student's goals, skill, pace, misconceptions, and review history.

## Source Ideas

- OATutor uses Bayesian Knowledge Tracing for skill mastery estimation.
- Moodle emphasizes personalized learning environments.
- OpenStax Tutor separates learner runtime concerns from server/exercise systems.
- Learning Locker shows the value of durable learning event records through xAPI.

## Tasks

- [x] Define a learner profile schema with goals, constraints, preferences, accommodations, and prior experience. <!-- ms:id f5046c922f3c -->
- [x] Define objective-level mastery evidence with confidence, recency, source, and evidence type. <!-- ms:id 5efb6c6e30c6 -->
- [x] Add a misconception record that can link mistakes to objectives and remediation paths. <!-- ms:id d775bf39190f -->
- [x] Prototype a teaching-loop decision function that selects lesson, practice, quiz, review, or remediation. <!-- ms:id 61b0f2463c2f -->
- [x] Add spaced-review scheduling based on mastery confidence and last evidence date. <!-- ms:id 99762d0ef347 -->
- [x] Store learning events in a format that can later map to xAPI-style statements. <!-- ms:id 61e3fa19b82d -->
- [x] Add fixture learners for new, struggling, advancing, reviewing, and returning-after-a-gap scenarios. <!-- ms:id 120d6fc6166a -->

## Acceptance Notes

- The adaptive loop should explain why it chose the next action.
- Mastery should be based on evidence, not only completion.
- The first version can be deterministic before adding model-driven behavior.

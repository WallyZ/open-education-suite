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

## Acceptance Notes

- Assessment output must update mastery evidence.
- Hints should preserve learner agency before revealing full solutions.
- Project feedback should cite the relevant objective and source content.

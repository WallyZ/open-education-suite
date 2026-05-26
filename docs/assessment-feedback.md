# Assessment and Feedback Contract

Assessments collect mastery evidence. They are not limited to quizzes; project checkpoints and interactive exercises can also update mastery when they produce clear evidence.

## Assessment Item Types

- `recall`
- `multiple-choice`
- `short-answer`
- `code-task`
- `project-checkpoint`
- `reflection`
- `interactive`

The machine-readable contract is in `schemas/assessment.schema.json`.

## Hints and Scaffolds

Hints use ordered scaffold levels:

1. nudge
2. concept-reminder
3. worked-example
4. solution

Hint usage is recorded as evidence. A correct answer after heavy hint usage should not update mastery the same way as an unaided correct answer.

## Deterministic Evaluation Hook

`scripts/assessment/evaluate-answer.ps1` evaluates fixture-backed items without external services. It returns:

- correctness status
- score
- feedback text
- hint usage
- mastery evidence

AI-assisted grading can be added later behind the same output contract.

## Reusable Interactive Exercises

Content repos may contribute interactive exercises by declaring:

- exercise id
- objective id
- interaction type
- launch metadata
- expected evidence event
- fallback static prompt

The core UI can render or launch the exercise later without coupling content repos to a specific frontend.

## Learner UI Rendering

The learner workspace renders four local assessment modes as evidence proposals before any mastery update is accepted: multiple choice, short answer, project rubric, and oral/explained-answer transcript. Saved responses stay in browser local storage under `openEducationAssessmentEvidence` with objective and source provenance so a later bridge or instructor review can decide whether they become durable mastery evidence.

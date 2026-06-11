# Assessment and Feedback Contract

Assessments collect mastery evidence. They are not limited to quizzes; project checkpoints and interactive exercises can also update mastery when they produce clear evidence.

## Assessment Rigor Policy

Essays are the default high-rigor assessment type for complex objectives because they require a learner to explain, connect evidence, compare alternatives, handle tradeoffs, and defend a conclusion. A quiz can check recall or diagnose a misconception, but it should not be treated as enough evidence for synthesis-level mastery.

For summative testing, prefer this order unless the objective requires a different artifact:

1. essay
2. project-checkpoint with written defense
3. oral/explained-answer transcript
4. code-task or interactive simulation with written rationale
5. short-answer
6. multiple-choice or recall

Essay prompts must include a rubric, minimum evidence requirements, and at least one synthesis move such as comparison, causal explanation, tradeoff analysis, counterargument, transfer, or design justification.

## Assessment Item Types

- `recall`
- `multiple-choice`
- `short-answer`
- `essay`
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

## Assessment Mastery Pack Handoff

`scripts/assessment/export-assessment-mastery-contract.ps1` exports public-safe
`assessment-mastery/assessment/v1` metadata for the reusable Assessment Mastery
Engine pack. The export includes sanitized assessment IDs, rubric criteria,
task refs, expected evidence refs, mastery policy, feedback template refs,
privacy flags, and logical output refs.

It does not export learner submissions, learner PII, private feedback bodies,
private course content, generated media, private paths, or credential material.
Use `-ItemId` to select a fixture-backed assessment item and `-OutputPath` to
write the metadata file:

```powershell
.\scripts\assessment\export-assessment-mastery-contract.ps1 -ItemId gdev-synthesis-essay-001 -OutputPath .\.codex-cache\tmp\assessment-mastery-contract.json
```

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

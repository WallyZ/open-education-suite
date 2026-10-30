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

## Founder Learning-Loop Integration Slice

The canonical narrow command is:

```powershell
pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\codex-verify.ps1 -Mode founder-loop
```

This reuses `scripts/export/check_founder_course_export.py` and the existing
Founder-selected Grade 1 Calendar Week 10 Day 1 sequence,
`lesson:lesson-g1-cw10-d01`, with initial/retry/delayed forms
`assess-g1-t1-src-i1`, `assess-g1-t1-src-x1`, and `assess-g1-t1-src-d1`.
The Suite schema pins that choice and the Founder-owned
`fixtures/founder-course-end-to-end.current.expected.json` supplies current
export counts. Source content remains in Founder. Its export README explicitly
selects this sequence for deterministic integration; that is the approval
basis for a synthetic software rehearsal, not qualified approval for a child
or formal program pilot. The Grade 9 rhetoric pilot is an authored alternative
but is not the current executable export-consumer contract.

The slice validates source checksums and references, reads the actual lesson,
source-rights, the checksum-bound solo parent/student planning handoff and its
text safe-equivalent route, materials/access routes, public assessments, grader-only keys,
rubrics and correction route, then exercises initial evidence, feedback,
changed retry, delayed review at a simulated due date, persistence, export and
recovery after loss of the active temporary state. The first attempt is
retained. It rejects early/wrong/repeated delayed forms, an empty scoring key,
withdrawn participation, unsupported fluent text, a restricted field in public/tutor data, corrupted
exports, and cross-source/cross-lesson restoration.

Task reconciliation: Founder TODO04 integration and TODO05 pilot authoring
are already complete; TODO18 remains the program-closeout owner. Suite TODO06
owns the existing teaching turn, TODO07 persistence/privacy, and TODO10 the
practice/transfer primitives. `OES_FOUNDER_LOOP_001` under existing TODO10 owns
only the missing delayed/recovery integration evidence; it does not reopen
completed primitives or create another curriculum, runtime, or backlog.

All answers and dates are synthetic. Rubric-key matching here tests contract
plumbing, not an essay grader, actual unassisted learner performance, the live
UI, a configured tutor model, real elapsed retention, or educational efficacy.
The text/access routes are checked as exported contracts; this does not certify
the full parent/student UI. Ordinary autonomous study and formal-study approval
remain distinct. No real learner data, restricted answers, or state files are
emitted into the tracked source corpus; temporary state is removed on exit.
Founder is read-only, including its unrelated uncommitted work.

## Server-Scored Founder Assessment

`OES_FOUNDER_INDEPENDENT_001` extends the existing selected forms, not the
curriculum or learning runtime. Run the canonical verifier with
`-Mode founder-assessment` for scorer checks, the prior self-check UI regression,
and the actual independent-scoring QA Live workflow.

The grader alone reads the checksum-bound restricted bank. It interprets the
current forms as a bounded structured-response contract: quantities, decision,
privacy, named roles, exact recalled source facts, and source-scope judgments.
It rejects unsupported rubric drift rather than guessing. This is not a general
essay evaluator. Public task fields and source passages are available for study;
the UI closes sources for an attempt, and grading keys never enter the lesson
projection, catalog, tutor context, static server, or grading response.

Only a server-scored, fully correct, declared-unassisted attempt adds 0.1
confidence to the existing daily objective
`founder-level-civic-classical:objective/lesson-g1-cw10-d01`. This conservative
adapter weight is not an empirically calibrated probability or whole-course
mastery threshold. Incorrect, partial, or assisted evidence adds no confidence.
The existing canonical state updater owns evidence counts, review scheduling,
misconceptions and audit entries. Replay cannot add another event. Self-awarded
scores and imported unsigned claims cannot create this scored mastery.

Signed receipts bind the learner, form history, source/rubric revision,
submission hash and canonical state. Verification precedes import or restored
authority. A denied assessment RPC returns `accepted: false`, never a grade;
the UI must handle that result before changing state. Receipts are
local-bridge-session evidence: the signing key and
authoritative session state are temporary and discarded on shutdown. After a
restart, old exports remain learner records but cannot restore verified scoring
authority; a durable private evidence store is a separate integration gate.
This does not establish identity, prevent off-screen help, or replace an
independent human/credential review. Support is explicitly declared.

Only `--assessment-rehearsal` permits synthetic dates, and those receipts are
marked synthetic. The ordinary bridge rejects that clock. QA answers are
materialized from the protected bank into the ignored run directory; tracked QA
templates contain placeholders. Synthetic traces stay in ignored local logs,
outside tutor retrieval. No real participants or learning outcomes are claimed.

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

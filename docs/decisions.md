# DECISIONS

Permanent technical decisions for `open-education-suite`.

## Markdown is the canonical docs format

- Decision: Use Markdown for repo documentation, runbooks, task packs, and backlog files.
- Rationale: Markdown is plain text, diff-friendly, GitHub-rendered, and easy for agents and humans to edit.
- Exceptions: Generate PDFs or rich documents only as release artifacts or user-facing distribution formats, not as the editable source of truth.

## Keep this repo content-agnostic

- Decision: `open-education-suite` owns ingestion, learner state, assessment, AI-teacher orchestration, quality gates, UI/runtime contracts, and teaching workflows.
- Rationale: Subject study plans, resources, generated lectures, and domain-specific course content belong in sibling `open-education-*` repos so the core platform remains reusable.
- Verification: `scripts/codex-verify.ps1` rejects domain study plans and resources in the core repo and verifies declared sibling content sources through `content-sources.json`.

## Keep the program-pack template contract in the suite

- Decision: `open-education-suite` owns the reusable program-pack standard, while each subject repo owns its concrete template copies, schemas, benchmarks, resources, assessments, rubrics, and content.
- Rationale: The standard is part of the central interface and should improve every course. A separate template repo would add coordination overhead before the contract stabilizes.
- Verification: Subject repos register through `content-repo.json`; the suite scanner imports adapter Markdown and generated lecture manifests without copying domain course bodies into the suite.

## Split reusable generated-instructor assets from subject lectures

- Decision: A future sibling `open-education-teacher` repo should own reusable generated-instructor persona and media-model assets, while subject repos own final rendered lecture packages.
- Rationale: Instructor identity, voice profiles, mannerisms, age/style variants, and avatar generation settings should be reusable across subjects without mixing with course content or platform code.
- Verification: Lecture manifests reference approved persona and provider contracts; rendered lecture media remains under the owning subject repo.

## Preserve essay-first high-rigor assessment

- Decision: Essays are the default high-rigor summative assessment type; quizzes remain diagnostic, retrieval, and misconception-check tools.
- Rationale: Synthesis evidence is stronger than multiple-choice correctness when judging durable mastery.
- Verification: `scripts/codex-verify.ps1` checks `fixtures/assessment-items.json` for essay-first policy, synthesis essay fixtures, and higher mastery weight for synthesis evidence.

## Adopt repo-kit standards with local overrides

- Decision: Reusable process/tooling assets come from `F:\dev\00-repo-kit`, but this repo keeps local authority over `AGENTS.md`, `.codex-cache/task-pack.md`, `docs/TODO.md`, and `scripts/codex-verify.ps1`.
- Rationale: Repo-kit standards should improve consistency without weakening education-suite behavior gates or replacing platform-specific workflow details.
- Verification: The canonical verifier runs repo-kit TODO lifecycle checks and the existing education-suite checks through one entrypoint.

## Keep QA Live adjacent and contract-driven

- Decision: This repo owns QA Live specs and workflow contracts under `qa-live/` and invokes the adjacent `qa-live-test-system`; it does not vendor QA harness code.
- Rationale: QA Live should be reusable across repos while each repo remains independent and explicit about its runtime validation needs.
- Verification: `scripts/codex-verify.ps1` runs the learner UI QA Live workflow through `scripts/testing/run-qa-live-learner-ui.ps1`.

## Default workflow is solo-owner direct-main

- Decision: Commit and push completed verified work to `main` by default.
- Rationale: This matches the owner-operated repo workflow and avoids unnecessary PR overhead.
- Exception: Add `.repo-kit/workflow_policy.local.json` if hosted branch protection or team collaboration requires PR flow.

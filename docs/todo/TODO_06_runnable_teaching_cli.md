# TODO 06 - Runnable Teaching CLI

## Goal

Turn the verified prototype pieces into a minimal learner-facing session that can actually be run end to end.

## Why This Matters

The suite is not useful until a learner can start a session, receive an adaptive next action, respond, get feedback, and see state change.

## Tasks

- [x] Add a `scripts/teaching/start-session.ps1` entrypoint that runs one complete teaching turn.
- [x] Load content through `content-sources.json` and the ingestion scanner before selecting a lesson or assessment.
- [x] Load a learner profile from a local learner-state file.
- [x] Select the next action through the adaptive teacher selector.
- [x] Render a learner-facing prompt for lesson, practice, quiz, review, remediation, or project action types.
- [x] Accept a learner response from CLI input or a supplied non-interactive parameter for tests.
- [x] Evaluate the response through the deterministic assessment hook when an assessment item is selected.
- [x] Show feedback, hint options, objective id, and source provenance.
- [x] Write an updated learner-state draft after the turn.
- [x] Add a fixture-backed golden CLI session test to `.\scripts\codex-verify.ps1`.

## Acceptance Notes

- A developer should be able to run one command and complete one teaching turn.
- The first version can be CLI-only and deterministic.
- Non-interactive mode must exist so verification can run without prompts.

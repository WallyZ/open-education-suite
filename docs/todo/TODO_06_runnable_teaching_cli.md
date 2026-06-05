# TODO 06 - Runnable Teaching CLI

## Goal

Turn the verified prototype pieces into a minimal learner-facing session that can actually be run end to end.

## Why This Matters

The suite is not useful until a learner can start a session, receive an adaptive next action, respond, get feedback, and see state change.

## Tasks

- [x] Add a `scripts/teaching/start-session.ps1` entrypoint that runs one complete teaching turn. <!-- ms:id 2d90abf56a09 -->
- [x] Load content through `content-sources.json` and the ingestion scanner before selecting a lesson or assessment. <!-- ms:id f835288b5a62 -->
- [x] Load a learner profile from a local learner-state file. <!-- ms:id 7cf7e57324d5 -->
- [x] Select the next action through the adaptive teacher selector. <!-- ms:id 3a5943cc6824 -->
- [x] Render a learner-facing prompt for lesson, practice, quiz, review, remediation, or project action types. <!-- ms:id 70193ac03fdc -->
- [x] Accept a learner response from CLI input or a supplied non-interactive parameter for tests. <!-- ms:id f17cc7abaff8 -->
- [x] Evaluate the response through the deterministic assessment hook when an assessment item is selected. <!-- ms:id 4ce437ade0ca -->
- [x] Show feedback, hint options, objective id, and source provenance. <!-- ms:id 55c00d001fdd -->
- [x] Write an updated learner-state draft after the turn. <!-- ms:id a38d87551263 -->
- [x] Add a fixture-backed golden CLI session test to `.\scripts\codex-verify.ps1`. <!-- ms:id 9442e3504bbd -->

## Acceptance Notes

- A developer should be able to run one command and complete one teaching turn.
- The first version can be CLI-only and deterministic.
- Non-interactive mode must exist so verification can run without prompts.

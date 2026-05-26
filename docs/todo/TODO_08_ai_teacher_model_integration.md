# TODO 08 - AI Teacher Model Integration

## Goal

Integrate a real AI teacher in a way that improves instruction without replacing deterministic state, provenance, and safety boundaries.

## Why This Matters

The system should be more than a content recommender. It should explain, question, diagnose, scaffold, and adapt like an expert tutor while staying grounded in source content and learner evidence.

## Tasks

- [x] Define the AI teacher tool contract: content lookup, learner state read, next-action read, assessment read, and state update proposal.
- [x] Add a teaching prompt contract that includes role, objective, learner state summary, source snippets, constraints, and desired output shape.
- [x] Require the AI teacher to cite source repo id and source path when explaining content.
- [x] Add guardrails that prevent unsupported claims when source content is missing.
- [x] Add a misconception diagnosis prompt that separates observed evidence from inference.
- [x] Add a Socratic tutoring mode that asks calibrated questions before giving answers.
- [x] Add an explanation-style adapter for concise, stepwise, examples-first, recap-first, and worked-example preferences.
- [x] Add a confidence gate that falls back to deterministic content or asks for clarification when model output is uncertain.
- [x] Add model-output evaluation fixtures for groundedness, correctness, tone, accessibility, and next-step usefulness.
- [x] Keep state mutations deterministic: the model may propose updates, but checked code applies them.

## Acceptance Notes

- AI output must be grounded in ingested content and learner state.
- The model should never be the only source of durable truth.
- Verification should include saved model-response fixtures before live model calls are used in CI.

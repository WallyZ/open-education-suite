# TODO 08 - AI Teacher Model Integration

## Goal

Integrate a real AI teacher in a way that improves instruction without replacing deterministic state, provenance, and safety boundaries.

## Why This Matters

The system should be more than a content recommender. It should explain, question, diagnose, scaffold, and adapt like an expert tutor while staying grounded in source content and learner evidence.

## Tasks

- [x] Define the AI teacher tool contract: content lookup, learner state read, next-action read, assessment read, and state update proposal. <!-- ms:id 879388c6fe6e -->
- [x] Add a teaching prompt contract that includes role, objective, learner state summary, source snippets, constraints, and desired output shape. <!-- ms:id 5ebeda649fc4 -->
- [x] Require the AI teacher to cite source repo id and source path when explaining content. <!-- ms:id a2d3294ea42d -->
- [x] Add guardrails that prevent unsupported claims when source content is missing. <!-- ms:id a9e13c402d67 -->
- [x] Add a misconception diagnosis prompt that separates observed evidence from inference. <!-- ms:id ead2210b9744 -->
- [x] Add a Socratic tutoring mode that asks calibrated questions before giving answers. <!-- ms:id 4798c8a68e2b -->
- [x] Add an explanation-style adapter for concise, stepwise, examples-first, recap-first, and worked-example preferences. <!-- ms:id 5bc1f8824a52 -->
- [x] Add a confidence gate that falls back to deterministic content or asks for clarification when model output is uncertain. <!-- ms:id 90c5d6ff5983 -->
- [x] Add model-output evaluation fixtures for groundedness, correctness, tone, accessibility, and next-step usefulness. <!-- ms:id 1d67e4f3f1ad -->
- [x] Keep state mutations deterministic: the model may propose updates, but checked code applies them. <!-- ms:id f8700778a162 -->

## Acceptance Notes

- AI output must be grounded in ingested content and learner state.
- The model should never be the only source of durable truth.
- Verification should include saved model-response fixtures before live model calls are used in CI.

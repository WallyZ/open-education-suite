# Adaptive Teacher Contract

The adaptive teacher chooses the next learner action from durable learner state, not from a single chat turn.

## Learner State

Learner state includes:

- profile: goals, constraints, preferences, accommodations, and prior experience
- objective mastery: confidence, recency, evidence count, review timing, and source evidence
- misconceptions: unresolved mistakes linked to objectives and remediation paths
- learning events: append-only activity records that can later map to xAPI statements

The machine-readable contract is in `schemas/adaptive-teacher.schema.json`.

## Deterministic First Loop

`scripts/teaching/select-next-action.ps1` is the first teaching-loop prototype. It is intentionally deterministic so behavior can be tested before model-driven planning is added.

Decision order:

1. If an objective has an unresolved misconception, assign remediation.
2. If an objective has no evidence, assign a lesson.
3. If confidence is low, assign practice.
4. If the spaced-review due date has passed, assign review.
5. If confidence is strong, assign an advancing project.
6. Otherwise, assign a quiz.

## Spaced Review

The prototype computes review timing from confidence and the last evidence date:

- confidence below 0.50: 1 day
- confidence below 0.70: 3 days
- confidence below 0.85: 7 days
- confidence 0.85 or higher: 14 days

The returned decision includes the reason, objective id, action type, and next review date.

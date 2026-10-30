# Founder Learner UI Integration

Objective: connect the existing schema-selected Grade 1 Week 10 Day 1 Founder
sequence to the real learner workspace under OES_FOUNDER_LOOP_UI_001, depending
on completed OES_FOUNDER_LOOP_001. Reuse the current bridge, learner-state
export/import controls, local profiles, and QA Live harness.

Relevant files: bridge; ui/learner/index.html, app.js, founder-loop.js;
qa-live/workflow.founder_ui.json and feature_spec.founder_ui.json;
scripts/codex-verify.ps1; docs/todo/TODO_11_learner_facing_ui.md; this task pack.
Nine files are needed for one executable source/UI/state/QA vertical slice.

Verification:

```powershell
pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\codex-verify.ps1 -Mode founder-ui
```

Founder remains read-only, with all pre-existing changes checksummed. Public
projection must not load or expose restricted keys or private repository paths.
Self-check reports cannot earn independent mastery. QA uses an isolated browser,
synthetic responses, and a clearly labelled simulated clock; reject importing
synthetic state into ordinary practice. No new curriculum, grading runtime,
participant service, model account, or external automation.

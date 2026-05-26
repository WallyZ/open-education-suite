# TODO 11 - Learner-Facing UI

## Goal

Build a learner-facing experience that makes the adaptive teacher usable, transparent, accessible, and motivating without hiding content provenance or learner-state evidence.

## Why This Matters

The CLI proves the teaching engine works, but learners need a real workspace: next action, lesson conversation, source citations, mastery progress, review queue, evidence, accommodations, and offline status in one coherent surface.

## Tasks

- [x] Add a first static learner workspace that can open locally without installing dependencies.
- [x] Show the current next action, why it was selected, the active objective, and source provenance.
- [x] Include a teacher interaction panel with learner response, hint, journal, and completion controls.
- [x] Show mastery, review queue, evidence, learner preferences, accommodations, and local-only privacy status.
- [x] Add accessibility foundations: semantic landmarks, skip link, keyboard focus, live region, reduced-motion handling, and responsive layout.
- [x] Add deterministic verification for required learner UI files and accessibility/product markers.
- [x] Install Playwright and add a learner UI browser smoke test for load, source provenance, keyboard flow, core interactions, and responsive overflow.
- [x] Integrate `qa-live-test-system` for a local learner UI live workflow with browser actions, HTTP evidence capture, and teardown.
- [x] Connect the UI to `scripts/teaching/start-session.ps1` output instead of embedded demo state.
- [x] Add a local session API or file bridge that can run the deterministic teaching turn from the UI.
- [x] Add live AI teacher invocation behind an explicit operator-controlled setting.
- [x] Add durable learner-state save, export, import, and conflict-safe sync preview.
- [x] Add assessment rendering for multiple choice, short answer, project rubric, and oral/explained-answer modes.
- [x] Add course navigation across ingested content sources and objectives.
- [x] Add learner analytics views that show evidence without surveillance-style framing.
- [x] Add instructor/operator handoff views for blockers, interventions, and content health.
- [x] Add visual regression and keyboard-flow checks once a browser test harness exists.
- [x] Add localization scaffolding for UI labels, dates, objective names, and feedback.

## Acceptance Notes

- The learner should always know what to do next, why the system chose it, and what source it is using.
- The UI must remain a view over learner state and content packages, not a second source of truth.
- The first static slice should be useful as a design target and smoke-test surface even before a server is introduced.

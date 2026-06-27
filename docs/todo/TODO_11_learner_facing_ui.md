# TODO 11 - Learner-Facing UI

## Goal

Build a learner-facing experience that makes the adaptive teacher usable, transparent, accessible, and motivating without hiding content provenance or learner-state evidence.

## Why This Matters

The CLI proves the teaching engine works, but learners need a real workspace: next action, lesson conversation, source citations, mastery progress, review queue, evidence, accommodations, and offline status in one coherent surface.

## Tasks

- [x] Add a first static learner workspace that can open locally without installing dependencies. <!-- ms:id e5c2ab3b49c4 -->
- [x] Show the current next action, why it was selected, the active objective, and source provenance. <!-- ms:id e8116ce742e5 -->
- [x] Include a teacher interaction panel with learner response, hint, journal, and completion controls. <!-- ms:id 38bb1d1f3143 -->
- [x] Show mastery, review queue, evidence, learner preferences, accommodations, and local-only privacy status. <!-- ms:id 333578cb61e9 -->
- [x] Add accessibility foundations: semantic landmarks, skip link, keyboard focus, live region, reduced-motion handling, and responsive layout. <!-- ms:id a570339717fd -->
- [x] Add deterministic verification for required learner UI files and accessibility/product markers. <!-- ms:id 55fe8d3b08f6 -->
- [x] Install Playwright and add a learner UI browser smoke test for load, source provenance, keyboard flow, core interactions, and responsive overflow. <!-- ms:id 8e885e7ddb21 -->
- [x] Integrate `qa-live-test-system` for a local learner UI live workflow with browser actions, HTTP evidence capture, and teardown. <!-- ms:id e89c0fdc1fae -->
- [x] Connect the UI to `scripts/teaching/start-session.ps1` output instead of embedded demo state. <!-- ms:id 4be7737fc3ef -->
- [x] Add a local session API or file bridge that can run the deterministic teaching turn from the UI. <!-- ms:id a13e0edb3ee8 -->
- [x] Add live AI teacher invocation behind an explicit operator-controlled setting. <!-- ms:id 3b8d331d5c7a -->
- [x] Add durable learner-state save, export, import, and conflict-safe sync preview. <!-- ms:id bfcd52334991 -->
- [x] Add assessment rendering for multiple choice, short answer, project rubric, and oral/explained-answer modes. <!-- ms:id 6458306cca46 -->
- [x] Add course navigation across ingested content sources and objectives. <!-- ms:id 46eb31b3154f -->
- [x] Add learner analytics views that show evidence without surveillance-style framing. <!-- ms:id 67bc65453fb9 -->
- [x] Add instructor/operator handoff views for blockers, interventions, and content health. <!-- ms:id 92018bdba1e3 -->
- [x] Add visual regression and keyboard-flow checks once a browser test harness exists. <!-- ms:id 7d5062247e50 -->
- [x] Add localization scaffolding for UI labels, dates, objective names, and feedback. <!-- ms:id 3368c844c1b3 -->
- [x] Add a `local-app-launcher/v1` consumer adapter for the learner UI bridge with dynamic live/test ports, watchdog delegation, and manifest verification. <!-- ms:id 5f0f48c8f16d -->
- [x] Add local learner profile manager for multiple students on the same computer with per-profile preferences and isolated learner-owned records. <!-- ms:id b4e72d83a9c1 -->
  - Evidence (2026-06-27): `ui/learner/index.html` exposes active-student selection and profile fields for display name, goals, explanation style, practice mode, pace, format, accommodations, and prior experience; `ui/learner/app.js` applies the selected profile to the active session and scopes saved state/evidence by learner id; `tests/learner-ui.spec.js` covers creating Alex and Blair profiles in the same browser without mixing their saved state. Verification: `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex-verify.ps1` passed (`.codex-cache\logs\codex-verify_20260627_104945_a404c6e9.log`).

## Acceptance Notes

- The learner should always know what to do next, why the system chose it, and what source it is using.
- The UI must remain a view over learner state and content packages, not a second source of truth.
- The first static slice should be useful as a design target and smoke-test surface even before a server is introduced.
- Launcher adapter evidence: `scripts/export_local_app_launcher_manifest.ps1`, `scripts/start_learner_ui_bridge.ps1`, `scripts/manage_learner_ui_launcher.ps1`, `docs/WORKFLOW.md`, and `.\scripts\codex-verify.ps1`.

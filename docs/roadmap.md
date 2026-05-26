# Project Roadmap

## Phase 1 - Content Boundary

- Keep this repo content agnostic.
- Maintain `content-sources.json` as the source registry.
- Seed separate content repos for cybersecurity, data science, game development, and software development.
- Add one verification entrypoint: `.\scripts\codex-verify.ps1`.

## Phase 2 - Read-Only Ingestion

- Implement manifest validation for content repos.
- Index Markdown study plans and resource libraries.
- Preserve source repo, path, and attribution.
- Produce an ingestion report without mutating content repos.

## Phase 3 - Adaptive Teaching Core

- Define learner profiles, objectives, mastery evidence, and review schedules.
- Build a teaching loop that chooses the next lesson, hint, quiz, review, or project.
- Track misconceptions and remediation paths.

## Phase 4 - Authoring and Review

- Add content quality checks for source repos.
- Support subject matter expert review workflows.
- Add accessibility and provenance requirements for generated materials.

## Phase 5 - Product Experience

- Build learner and instructor interfaces.
- Add progress dashboards and exportable study plans.
- Evaluate offline-first packaging and LMS integration options.

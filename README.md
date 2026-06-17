# Open Education Suite

Open Education Suite is the core AI teaching platform. Its job is to adapt to each student, reason over progress, and ingest learning content from separate content repositories.

The suite should stay content agnostic. Cybersecurity, data science, game development, software development, and future subjects live in sibling repos so each curriculum can evolve independently without forcing changes in the teaching engine.

## Product Focus

- Adaptive AI teacher that responds to each student's current skill, pace, goals, and misconceptions.
- Content ingestion from external subject repos through explicit manifests.
- Learner model, mastery tracking, remediation, spaced review, quizzes, flashcards, and project feedback.
- Authoring/review workflows that keep subject matter content separate from platform behavior.

## Content Repositories

The local content sources are declared in `content-sources.json` and are expected beside this repo under `F:\dev`:

- `F:\dev\open-education-cybersecurity`
- `F:\dev\open-education-data-science`
- `F:\dev\open-education-game-development`
- `F:\dev\open-education-mens-relationship-skills`
- `F:\dev\open-education-software-development`

Each content repo owns its study plans, resource lists, assessments, examples, and domain-specific learning assets. This core repo owns the ingestion contract and teaching system.

## Core Repository Structure

```text
open-education-suite/
  content-sources.json        # Local content source registry
  docs/
    architecture-overview.md
    content-ingestion.md
    teaching-suite-opportunities.md
    roadmap.md
  resources/
    README.md                 # Core policy; domain resources live outside this repo
  scripts/
    codex-verify.ps1
  study-plans/
    README.md                 # Core policy; domain plans live outside this repo
    templates/
  ui/
    learner/                  # Static learner-facing workspace prototype
  tools/
```

## Getting Started

1. Keep this repo focused on platform behavior and content ingestion.
2. Add or update subject material in the matching `open-education-*` content repo.
3. Register new content repos in `content-sources.json`.
4. Run `.\scripts\codex-verify.ps1` after changes.

See `docs/content-ingestion.md` for the content boundary and ingestion contract.

## Learner UI

The first learner-facing workspace is a static, dependency-free prototype at `ui/learner/index.html`. It shows the next adaptive action, teacher interaction, source citation, mastery, review queue, journal, preferences, accommodations, and local-only privacy status.

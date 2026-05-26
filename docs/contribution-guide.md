# Contribution Guide

## Where Changes Belong

- Core teaching behavior, ingestion contracts, learner modeling, platform docs, and verification belong in `open-education-suite`.
- Domain curricula, resource libraries, exercises, and subject-specific examples belong in the matching `open-education-*` content repo.

## Adding a New Content Repo

1. Create a sibling repo under `F:\dev`.
2. Add `content-repo.json`, `study-plans/`, and `resources/`.
3. Register it in `content-sources.json`.
4. Run `.\scripts\codex-verify.ps1`.

## Pull Request Guidelines

- Keep platform and content changes separate unless the contract changes require both.
- Preserve public paths and manifest fields unless the change is intentional.
- Include verification results in the PR description.
- Keep generated artifacts out of source folders.

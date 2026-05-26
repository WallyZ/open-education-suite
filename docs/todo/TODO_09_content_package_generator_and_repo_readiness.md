# TODO 09 - Content Package Generator and Repo Readiness

## Goal

Move from package contract and placeholder content repos to real package generation and content repos that can support useful teaching sessions.

## Why This Matters

The core suite can only be content agnostic if content repos are strong, licensed, attributable, and packageable.

## Tasks

- [x] Implement a package generator that writes `package.json`, `objects.jsonl`, and copied source snapshots under an ignored output path.
- [x] Include source repo id, source path, source commit when available, license, attribution, generated time, and object count in each package.
- [x] Add package validation to `.\scripts\codex-verify.ps1`.
- [x] Replace `license: TBD` in all content manifests with explicit license decisions.
- [x] Add a content readiness checklist to each content repo.
- [x] Add at least one real starter study plan for cybersecurity.
- [x] Add at least one real starter study plan for data science.
- [x] Add at least one real starter study plan for software development.
- [x] Normalize the game-development imported content into package-friendly objectives, resources, and assessments.
- [x] Add content quality checks for minimum viable content: objectives, resources, assessments, attribution, and broken links.
- [x] Define how content repos should add interactive exercise metadata without depending on the core UI.

## Acceptance Notes

- Generated packages must not mutate source content repos.
- Placeholder README-only repos should fail readiness checks until real content is added.
- Licenses must be explicit before content is used beyond local development.

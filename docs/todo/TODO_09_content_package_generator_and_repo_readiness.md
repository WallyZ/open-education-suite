# TODO 09 - Content Package Generator and Repo Readiness

## Goal

Move from package contract and placeholder content repos to real package generation and content repos that can support useful teaching sessions.

## Why This Matters

The core suite can only be content agnostic if content repos are strong, licensed, attributable, and packageable.

## Tasks

- [x] Implement a package generator that writes `package.json`, `objects.jsonl`, and copied source snapshots under an ignored output path. <!-- ms:id 677aa9505197 -->
- [x] Include source repo id, source path, source commit when available, license, attribution, generated time, and object count in each package. <!-- ms:id 3d87168f6438 -->
- [x] Add package validation to `.\scripts\codex-verify.ps1`. <!-- ms:id 366779a31547 -->
- [x] Replace `license: TBD` in all content manifests with explicit license decisions. <!-- ms:id 3d8256caac83 -->
- [x] Add a content readiness checklist to each content repo. <!-- ms:id d479f53ecccd -->
- [x] Add at least one real starter study plan for cybersecurity. <!-- ms:id b76a5c14138f -->
- [x] Add at least one real starter study plan for data science. <!-- ms:id 69186486651e -->
- [x] Add at least one real starter study plan for software development. <!-- ms:id e97e4ccc32f1 -->
- [x] Normalize the game-development imported content into package-friendly objectives, resources, and assessments. <!-- ms:id a8f3ffccbd83 -->
- [x] Add content quality checks for minimum viable content: objectives, resources, assessments, attribution, and broken links. <!-- ms:id 7eb2b664d278 -->
- [x] Define how content repos should add interactive exercise metadata without depending on the core UI. <!-- ms:id e5bd06015b89 -->

## Acceptance Notes

- Generated packages must not mutate source content repos.
- Placeholder README-only repos should fail readiness checks until real content is added.
- Licenses must be explicit before content is used beyond local development.

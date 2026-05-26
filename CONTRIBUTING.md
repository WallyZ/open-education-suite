# Contributing to Open Education Suite

Open Education Suite is the content-agnostic AI teaching platform. Contributions should keep the core engine separate from subject content.

## Choose the Correct Repo

- Use `open-education-suite` for platform behavior, ingestion contracts, learner modeling, verification, and product documentation.
- Use a sibling `open-education-*` repo for subject curricula, resource libraries, exercises, examples, and assessments.

## Core Repo Contributions

Core changes should:

- preserve the external content boundary
- update `content-sources.json` only when content sources change
- document ingestion or learner-model contract changes
- run `.\scripts\codex-verify.ps1`

## Content Repo Contributions

Content changes should:

- live in the matching subject repo
- preserve source attribution and licenses
- use platform-neutral Markdown and metadata where practical
- avoid coupling a subject repo to unreleased platform behavior

## Review Standard

Keep changes focused, tested through the repo entrypoint, and clear about whether they affect the platform contract or a specific subject.

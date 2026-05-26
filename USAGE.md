# Usage Guide

This repo is the teaching platform, not the curriculum library. Use it to ingest subject content from sibling repos and adapt instruction to each learner.

## 1. Register Content Sources

Content sources are listed in `content-sources.json`. Each source points to a sibling repo that contains a `content-repo.json` manifest plus `study-plans/` and `resources/` folders.

Default local layout:

```text
F:\dev\
  open-education-suite\
  open-education-cybersecurity\
  open-education-data-science\
  open-education-game-development\
  open-education-software-development\
```

## 2. Add or Update Subject Content

Make domain-specific changes in the matching content repo:

- Study plans and course paths go in that repo's `study-plans/`.
- Resource libraries, videos, references, and exercises go in that repo's `resources/`.
- Platform-neutral metadata goes in that repo's `content-repo.json`.

## 3. Ingest Content

The core suite should ingest from the registered manifests, normalize content into internal learning objects, and keep source attribution back to the content repo.

The first implementation target is a read-only local ingestion pass:

1. Read `content-sources.json`.
2. Resolve each content repo.
3. Read each `content-repo.json`.
4. Index study plans, resources, assessments, and metadata.
5. Report missing or malformed sources without mutating the content repos.

## 4. Teach Adaptively

The teaching loop should combine:

- learner profile and goals
- current mastery estimates
- content graph prerequisites
- practice history and review timing
- feedback from quizzes, projects, and conversations

The teacher should adapt sequence, explanation style, review cadence, and remediation while keeping content provenance visible.

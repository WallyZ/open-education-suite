# Content Package Format

Content packages are local/offline snapshots produced from content repos. They are generated artifacts, not source content, and must not be committed back into content repos.

## Package Goals

- Let the teaching suite run from a stable snapshot when content repos are unavailable.
- Preserve source repo, path, title, license, and attribution for each learning object.
- Keep package generation read-only against source content repos.
- Make package validation deterministic through `.\scripts\codex-verify.ps1`.

## Package Shape

```text
content-package/
  package.json
  objects.jsonl
  sources/
```

`package.json` should contain:

- `schemaVersion`
- `generatedAt`
- `registryPath`
- `sourceCount`
- `objectCount`
- source repo ids and content manifest paths

`objects.jsonl` should contain one normalized learning object per line:

- `id`
- `sourceId`
- `sourceRepo`
- `sourcePath`
- `type`
- `title`
- `license`
- `attribution`

Course and study-plan objects may also include source-review metadata when the subject repo links external courseware for learner reference or authoring inspiration:

- `externalSourceLinks[]`
  - `provider`
  - `title`
  - `url`
  - `license`
  - `useBoundary`
  - `lastReviewed`
  - `whyUseful`
  - `borrowedPattern`
- `courseDesignReview`
  - `prerequisitesPresent`
  - `outcomesPresent`
  - `moduleMapPresent`
  - `videosPresent`
  - `readingsPresent`
  - `practicePresent`
  - `quizzesPresent`
  - `projectsPresent`
  - `testsPresent`
  - `rubricsPresent`
  - `supportAndPoliciesPresent`
  - `adaptiveHooksPresent`
- `courseStructure`
  - `level`
  - `estimatedHours`
  - `moduleCount`
  - `finalDeliverable`
  - `completionEvidence`

External source links are provenance and learning aids, not permission to copy course assets. Subject repos should link to external courseware, explain why each source is useful, and define original or properly licensed local assessments, projects, quizzes, and lectures.

The first implementation may emit a single JSON report from `scripts/ingestion/scan-content-sources.ps1`. A later packaging command can split that report into the package shape above.

## Storage Rules

- Temporary package builds belong under `.codex-cache\tmp\<run-id>\`.
- Durable runtime caches should use an ignored cache folder, not source content folders.
- Source repos must not be mutated during package generation.

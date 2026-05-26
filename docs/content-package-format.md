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

The first implementation may emit a single JSON report from `scripts/ingestion/scan-content-sources.ps1`. A later packaging command can split that report into the package shape above.

## Storage Rules

- Temporary package builds belong under `.codex-cache\tmp\<run-id>\`.
- Durable runtime caches should use an ignored cache folder, not source content folders.
- Source repos must not be mutated during package generation.

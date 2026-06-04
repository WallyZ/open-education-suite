# Content Ingestion

The suite ingests learning content from sibling repositories. This keeps the teaching engine stable while individual subjects evolve independently.

## Local Source Registry

`content-sources.json` is the core registry. Each entry provides:

- `id`: stable source identifier used by the suite
- `title`: human-readable content repo name
- `localPath`: path from this repo to the sibling content repo
- `contentManifest`: manifest file inside the content repo
- `status`: seeding or readiness note

## Content Repo Contract

Each content repo should include:

```text
content-repo.json
study-plans/
resources/
generated-lectures/   # optional subject-owned generated lecture packages
```

The manifest should identify the repo, declare its platform role, and list the folders the suite may ingest.

## First Ingestion Target

The read-only scanner is:

```powershell
.\scripts\ingestion\scan-content-sources.ps1
```

It:

1. Reads `content-sources.json`.
2. Resolves and validates each content repo.
3. Reads each `content-repo.json`.
4. Indexes Markdown files under declared content folders and `lecture-video.json` files under optional `generatedLectures`.
5. Emits a report of imported objects, skipped files, and validation errors.

## Rules

- Do not mutate content repos during ingestion.
- Do not copy domain content back into this core repo.
- Store generated lectures, lecture manifests, rendered media metadata, and subject-specific materials in the owning content repo, such as `F:\dev\open-education-game-development\generated-lectures\...` for game development.
- Store generated indexes or cache files under `.codex-cache\tmp\` or a future ignored runtime cache.
- Keep source paths and attribution with each imported object.

See `content-package-format.md` for the local/offline package contract.

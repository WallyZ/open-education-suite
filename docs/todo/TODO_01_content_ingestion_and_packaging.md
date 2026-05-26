# TODO 01 - Content Ingestion and Packaging

## Goal

Build a read-only ingestion path that lets the suite teach from separate content repos without copying domain content back into the core repo.

## Source Ideas

- OATutor keeps tutoring logic separate from its content repository.
- Open edX separates authoring/CMS concerns from learner delivery/LMS concerns.
- Kolibri treats offline content packaging and distribution as a first-class requirement.
- H5P uses a content hub model for discovering reusable interactive content types.

## Tasks

- [x] Implement a read-only content source scanner for `content-sources.json`.
- [x] Validate each content repo's `content-repo.json` schema before ingesting files.
- [x] Index Markdown files under declared `study-plans` and `resources` paths.
- [x] Preserve source repo id, source path, title, license, and attribution for each imported object.
- [x] Emit an ingestion report with imported files, skipped files, and validation errors.
- [x] Define a content package format for local/offline use without mutating source repos.
- [x] Add checks that prevent domain content from being added back into the core repo.

## Acceptance Notes

- Ingestion must be read-only.
- Missing content repos should produce actionable validation output.
- Generated indexes and temporary artifacts must stay out of tracked domain content.

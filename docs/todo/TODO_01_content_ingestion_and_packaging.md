# TODO 01 - Content Ingestion and Packaging

## Goal

Build a read-only ingestion path that lets the suite teach from separate content repos without copying domain content back into the core repo.

## Source Ideas

- OATutor keeps tutoring logic separate from its content repository.
- Open edX separates authoring/CMS concerns from learner delivery/LMS concerns.
- Kolibri treats offline content packaging and distribution as a first-class requirement.
- H5P uses a content hub model for discovering reusable interactive content types.

## Tasks

- [x] Implement a read-only content source scanner for `content-sources.json`. <!-- ms:id e3d11bf6e8ae -->
- [x] Validate each content repo's `content-repo.json` schema before ingesting files. <!-- ms:id d89aa5adcd20 -->
- [x] Index Markdown files under declared `study-plans` and `resources` paths. <!-- ms:id fedee688b4cb -->
- [x] Preserve source repo id, source path, title, license, and attribution for each imported object. <!-- ms:id ec53778b2f12 -->
- [x] Emit an ingestion report with imported files, skipped files, and validation errors. <!-- ms:id 158fd8ce8af0 -->
- [x] Define a content package format for local/offline use without mutating source repos. <!-- ms:id 582960ca1832 -->
- [x] Add checks that prevent domain content from being added back into the core repo. <!-- ms:id 48a6dd256296 -->

## Acceptance Notes

- Ingestion must be read-only.
- Missing content repos should produce actionable validation output.
- Generated indexes and temporary artifacts must stay out of tracked domain content.

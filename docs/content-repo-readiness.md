# Content Repo Readiness

Each content repo should be ready for ingestion, packaging, and teaching without changing the core suite.

## Required Folders

- `study-plans/`
- `resources/`
- `objectives/`
- `assessments/`

## Required Manifest Fields

- `schemaVersion`
- `id`
- `title`
- `role`
- `compatibleSuite`
- `license`
- `attribution`
- `paths.studyPlans`
- `paths.resources`
- `paths.objectives`
- `paths.assessments`

## Interactive Exercise Metadata

Content repos can define interactive exercises without coupling to the core UI by documenting:

- exercise id
- objective id
- interaction type
- launch reference
- expected evidence event
- fallback static prompt

The core suite may later render the interaction, open an external tool, or fall back to the static prompt.

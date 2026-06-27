# Program Pack Template

This is the suite-owned standard for world-class subject packs. Concrete subject content belongs in sibling `open-education-*` repos; this file defines the interface those repos should satisfy.

## Repo Placement Decision

Keep the reusable template standard in `open-education-suite` for now. It is part of the central interface: ingestion, learner UI, adaptive teaching, assessment policy, lecture generation, and quality gates all need to understand it. A separate template repo can come later if multiple independent tools need to version it apart from the suite.

Subject repos should carry their own concrete copies of schemas and templates when useful, as the American History pilot does under `schemas/` and `templates/`.

## Required Pack Surfaces

| Surface | Purpose |
| --- | --- |
| `program.yaml` | Program identity, scope, stages, allowed claims, prohibited claims, mastery defaults, and graduation artifacts. |
| `benchmarks/` | University, professional, public, and external assessment references used to calibrate rigor. |
| `competencies/` | Competency map, prerequisite graph, domains, periods, themes, vocabulary, and evidence expectations. |
| `pathways/` | Diagnostic routes, full mastery route, acceleration/remediation paths, and scheduling models. |
| `curriculum/` | Module sequence, module specs, reading/viewing map, and lesson design inputs. |
| `resources/` | Open resources, books, scholarship, primary sources, instructor references, and resource selection policy. |
| `assessments/` | Diagnostics, quizzes, essay prompts, source-analysis tasks, practicals, oral exams, comprehensive exams, and research defenses. |
| `rubrics/` | Rubrics for each major evidence type, including synthesis and transfer. |
| `teaching/` | Instructor guide, student guide, remediation, misconceptions, Socratic prompts, accessibility, controversy/balance, and AI-integrity guidance. |
| `provenance/` | Source list, licenses, rejected resources, review log, and update history. |
| `schemas/` | Machine-readable validation contracts for program, module, resource, assessment, rubric, and related records. |
| `templates/` | Authoring templates and adaptation checklist for future subject packs. |

## Quality Bar

Define world class by demonstrated performance, not hours watched or books completed. A pack should show that the learner can perform at the relevant benchmark level through authentic evidence: analysis, writing, projects, oral explanation, revision, public artifacts, portfolio work, and external review where needed.

The pack must include:

- Benchmark dossier against respected programs and external assessments.
- Competency map with prerequisites and evidence expectations.
- Diagnostics that route learners to remediation without weakening standards.
- Learning sequence with resources, practice, assessment, and feedback loops.
- Resource plan that distinguishes open, linked, paid, archival, and reference-only materials.
- Assessment ladder that favors synthesis evidence over passive completion.
- Rubrics and reviewer guides that make performance claims defensible.
- Teaching supports for misconceptions, remediation, accessibility, learner motivation, and academic integrity.
- Quality record with validation reports, review logs, maintenance cadence, and current-history update rules when relevant.

## Suite Adapter Requirement

If a subject pack uses YAML, JSONL, or other rich structures, it should also provide adapter Markdown for the current suite scanner:

```text
study-plans/
  <program-summary>.md
  courses/
    <course-or-program-object>.md
resources/
  <resource-index>.md
objectives/
  <objective-index>.md
assessments/
  <assessment-bank-summary>.md
misconceptions/
  <misconception-summary>.md
generated-lectures/
  <lecture-slug>/lecture-video.json
```

Adapter Markdown should expose objective ids and learner-facing course objects while linking back to the pack source of truth. It should not become a second copy of the course.

## Assessment Preference

Use quizzes for retrieval, diagnosis, and misconception detection. Use essays, source analysis, projects, practical exams, oral exams, defenses, and portfolio reviews for mastery. The suite should treat passive video completion and quiz correctness as insufficient for durable mastery unless paired with synthesis evidence.

# Architecture Overview

Open Education Suite is the content-agnostic teaching engine. Subject content lives in separate repositories and is ingested through explicit manifests.

## Core Responsibilities

### 1. Content Source Layer

- Read `content-sources.json`.
- Resolve each external content repo.
- Load each repo's `content-repo.json`.
- Preserve source repo, path, and attribution for every imported learning object.

### 2. Content Normalization Layer

- Convert study plans, resource libraries, assessments, projects, and notes into platform-neutral learning objects.
- Build prerequisite, topic, objective, and assessment relationships.
- Keep generated artifacts separate from source content.

### 3. Learner Model Layer

- Store learner goals, preferences, history, constraints, and accommodations.
- Track mastery by objective, confidence, recency, and evidence source.
- Detect misconceptions and stalled progress.

### 4. Teaching Loop Layer

- Choose the next explanation, practice item, project, quiz, or review.
- Adapt pacing and style to the learner.
- Generate hints and remediation from the content graph.
- Ask for evidence when mastery is uncertain.

### 5. Output Layer

- Produce lessons, quizzes, flashcards, study plans, review schedules, and project feedback.
- Show content provenance so generated teaching output can be traced back to the source repo.

## Boundary Rule

This repo owns the engine and ingestion contract. Content repos own curricula, resource lists, assessments, examples, and subject-specific assets.

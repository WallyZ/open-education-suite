# TODO 12 - Generated Lecture Video

## Goal

Create original, durable lecture videos with a generated instructor, grounded in content packages and usable by the adaptive teacher as a first-class lesson format.

## Why This Matters

Good lecture videos can provide the in-class explanation layer learners expect, but hosted videos are fragile and can disappear. The suite needs a way to study strong teaching examples, extract reusable pedagogy patterns, and produce original archived lessons with captions, transcripts, citations, and quality checks.

## Tasks

- [x] Build a source review matrix for representative high-quality lectures across open courseware, university courses, educator channels, and professional talks.
- [x] Define a `lecture-video.json` package schema for source links, objective ids, transcript, captions, slides, media paths, checksums, license audit, and QA status.
- [x] Add a script and storyboard generator that turns a content package objective into an original cited lecture plan.
- [x] Add a copyright and licensing gate that blocks copied transcripts, unlicensed slides, unauthorized likenesses, and host-only media from required course paths.
- [x] Define generated instructor persona rules, disclosure language, voice/likeness consent rules, and tone requirements.
- [x] Add local archive conventions for rendered lecture media, including checksums and a large-file storage decision.
- [x] Add caption, transcript, chapter, slide, and alt-text requirements for every lecture package.
- [x] Add a teaching-quality rubric for video pacing, examples, active recall, misconception checks, accessibility, and assessment handoff.
- [x] Add a deterministic short lecture fixture for one ingested course objective.
- [x] Add a verification script that validates lecture package manifests, file references, checksums, captions, citations, and QA status.
- [x] Add learner UI support for lecture playback, transcript reading, source citations, checkpoints, and resume position.
- [x] Connect video checkpoints to learner-state evidence without treating passive watch completion as mastery.
- [x] Add adaptive selection rules so the teacher can choose full lecture, short segment, transcript, or remediation clip based on learner state.
- [x] Add operator review workflow for approving generated scripts, visuals, media, and final packages before publishing.

## Acceptance Notes

- Generated videos must be original course artifacts, not copied versions of hosted videos.
- External videos may inform the source review matrix and remain optional references when licensing permits.
- Required instruction should be available from local generated packages or media the project is allowed to archive.
- Every lecture package must preserve accessibility and provenance at least as strongly as text lessons.

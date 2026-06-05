# TODO 12 - Generated Lecture Video

## Goal

Create original, durable lecture videos with a generated instructor, grounded in content packages and usable by the adaptive teacher as a first-class lesson format.

## Why This Matters

Good lecture videos can provide the in-class explanation layer learners expect, but hosted videos are fragile and can disappear. The suite needs a way to study strong teaching examples, extract reusable pedagogy patterns, and produce original archived lessons with captions, transcripts, citations, and quality checks.

## Tasks

- [x] Build a source review matrix for representative high-quality lectures across open courseware, university courses, educator channels, and professional talks. <!-- ms:id 8d980a407fc4 -->
- [x] Define a `lecture-video.json` package schema for source links, objective ids, transcript, captions, slides, media paths, checksums, license audit, and QA status. <!-- ms:id 30754599dbf0 -->
- [x] Add a script and storyboard generator that turns a content package objective into an original cited lecture plan. <!-- ms:id 21d341ef06b4 -->
- [x] Add a copyright and licensing gate that blocks copied transcripts, unlicensed slides, unauthorized likenesses, and host-only media from required course paths. <!-- ms:id a409c0e84914 -->
- [x] Define generated instructor persona rules, disclosure language, voice/likeness consent rules, and tone requirements. <!-- ms:id f0b59b94b5e3 -->
- [x] Add local archive conventions for rendered lecture media, including checksums and a large-file storage decision. <!-- ms:id 14490f3bb414 -->
- [x] Add caption, transcript, chapter, slide, and alt-text requirements for every lecture package. <!-- ms:id bd66da652983 -->
- [x] Add a teaching-quality rubric for video pacing, examples, active recall, misconception checks, accessibility, and assessment handoff. <!-- ms:id 5917ef4c4e23 -->
- [x] Add a deterministic short lecture fixture for one ingested course objective. <!-- ms:id cc57617b28eb -->
- [x] Add a verification script that validates lecture package manifests, file references, checksums, captions, citations, and QA status. <!-- ms:id eb46b564a950 -->
- [x] Add learner UI support for lecture playback, transcript reading, source citations, checkpoints, and resume position. <!-- ms:id 90fd435b7007 -->
- [x] Connect video checkpoints to learner-state evidence without treating passive watch completion as mastery. <!-- ms:id 2c1ac3f5f30f -->
- [x] Add adaptive selection rules so the teacher can choose full lecture, short segment, transcript, or remediation clip based on learner state. <!-- ms:id ef14a0223796 -->
- [x] Add operator review workflow for approving generated scripts, visuals, media, and final packages before publishing. <!-- ms:id ad528c1777dc -->

## Acceptance Notes

- Generated videos must be original course artifacts, not copied versions of hosted videos.
- External videos may inform the source review matrix and remain optional references when licensing permits.
- Required instruction should be available from local generated packages or media the project is allowed to archive.
- Every lecture package must preserve accessibility and provenance at least as strongly as text lessons.

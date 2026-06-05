# TODO 18 - Courseware Source Review and Course Design

## Goal

Learn from MIT OpenCourseWare and similar open courseware sites without copying their content into the core repo. Preserve useful links, course setup patterns, resource types, and borrowing decisions so our own courses can become more complete, rigorous, and learner-friendly.

## Source Ideas

- MIT OpenCourseWare uses durable course pages with syllabus, calendar, readings, lecture notes, assignments, projects, exams, downloads, attribution, and license metadata when available.
- MIT Open Learning Library emphasizes self-paced interactive practice with immediate feedback.
- Harvard CS50 exposes a highly usable learner map: weeks, lectures, notes, shorts, problem sets, practice, final project, academic honesty, staff, FAQ, tools, and community.
- Stanford Engineering Everywhere keeps archive-style lecture videos, handouts, assignments, and exams together.
- CMU OLI focuses on learning-engineered pages, activities, checkpoints, and immediate feedback.
- OpenStax provides open textbook chapters, learning objectives, examples, exercises, and instructor/learner resources.
- OpenLearn and Saylor show short-course packaging with level, time estimates, units, assessments, completion evidence, and certificates/badges.
- Nand2Tetris is a strong model for cumulative project ladders that build mastery through staged deliverables.

## Tasks

- [x] Compile a curated courseware source review with representative MIT OCW and similar course links, setup notes, resources provided, use boundaries, and borrowable patterns. <!-- ms:id 01ad673cb9d5 -->
- [x] Add course-source metadata guidance to the content package/course-object format so external references can be linked, reviewed, licensed, and mapped without copying content. <!-- ms:id 755efb8cc7c5 -->
- [x] Add a subject-repo course authoring template that requires overview, prerequisites, outcomes, module/week map, videos, readings, practice, quizzes, projects, tests, rubrics, support, policies, and adaptive hooks. <!-- ms:id ba24b6efa879 -->
- [x] Build a read-only source-link audit that checks courseware URLs, last-reviewed dates, provider names, license/use-boundary notes, and broken links without downloading course assets. <!-- ms:id 2b30a2794988 -->
- [x] Apply the courseware audit to `open-education-game-development` starting with GDEV-101 and record gaps against MIT OCW, CS50 Games, Stanford SEE, OpenStax, and Nand2Tetris patterns. <!-- ms:id 84bcb7564218 -->
- [x] Add a course-design quality gate that fails when a course lacks objectives, practice, assessment, project work, citations/source links, accessibility notes, or adaptive remediation metadata. <!-- ms:id e6026678fbe3 -->

## Acceptance Notes

- External courseware stays linked and attributed; course-specific learning materials stay in subject repos.
- The core repo owns the format, ingestion, QA, and adaptive-teaching contracts, not the copied curriculum.
- Each borrowed idea should become a course-object field, authoring template requirement, quality check, or learner-facing behavior.

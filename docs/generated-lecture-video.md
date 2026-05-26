# Generated Lecture Video

## Purpose

The suite should be able to create original lecture videos with a generated instructor, similar to the structured lessons learners get in real classes. These videos should be grounded in ingested content packages, adapted to learner needs, and stored as durable local artifacts so a host deleting a referenced video does not remove the course's core lesson.

## Non-Negotiables

- Use public lecture videos as research references for teaching patterns, not as copied source material.
- Do not clone a real instructor's face, voice, likeness, slides, transcript, or branded style unless the license and consent are explicit.
- Ground every generated script in content package sources, objectives, assessments, and citations.
- Store generated transcripts, captions, slides, manifests, and rendered media with checksums.
- Keep large rendered media out of Git unless the repo explicitly adopts a large-file storage strategy.
- Provide captions, transcript, chapters, and source citations for every generated video.
- Preserve learner choice: video should augment the adaptive teacher, not become the only path through a lesson.

## Lecture Package Shape

A generated lecture package should include:

- `lecture-video.json`: package manifest with schema version, source object ids, objective ids, generation settings, media paths, checksums, license audit, and source review notes.
- `script.md`: instructor narration, stage directions, pause prompts, citations, and adaptation notes.
- `storyboard.md`: scene order, visual plan, board or slide moments, checks for common misconceptions, and active recall prompts.
- `slides/`: generated or authored visual material with alt text and attribution metadata.
- `captions/`: WebVTT captions and plain transcript.
- `media/`: rendered audio/video outputs, stored outside Git when large.
- `qa-report.json`: factuality, accessibility, source-grounding, licensing, pacing, and teaching-quality checks.

## Pipeline

1. Source survey: review representative high-quality lectures for structure, pacing, examples, board use, active recall, and assessment alignment. Record transferable teaching moves, not copied content.
2. Lesson specification: select content object, objective, learner level, prerequisites, target duration, and assessment handoff.
3. Script and storyboard: generate an original script with citations, examples, misconception checks, pauses, and summary.
4. Asset plan: choose original, licensed, or generated visuals and record attribution.
5. Instructor generation: render voice and instructor presence from an approved persona profile with generated-content disclosure.
6. Assembly: combine narration, instructor, slides, board moments, captions, chapters, and transcript.
7. QA: verify source grounding, accessibility, copyright/licensing, factual accuracy, pacing, and alignment with the adaptive teacher.
8. Publish package: write the manifest, checksums, local archive path, and content package linkage.

## Lecture Plan Generator

`scripts/teaching/build-lecture-plan.ps1` creates a deterministic original script and storyboard plan for one objective. It can read the live content registry or a generated content package:

```powershell
.\scripts\teaching\build-lecture-plan.ps1 -ObjectiveId 'game-development:objectives/course/gdev-101/design-vocabulary'
.\scripts\teaching\build-lecture-plan.ps1 -PackageRoot '.codex-cache\tmp\example-package' -ObjectiveId 'game-development:objectives/course/gdev-101/design-vocabulary'
```

The generator emits JSON with `contentSource`, `citations`, `script`, `storyboard`, `licenseBoundaries`, and `qaExpectations`. Its output is a planning artifact, not a publishable video package; the package still needs a license gate, generated instructor review, captions, media checksums, and operator approval.

## Copyright And Licensing Gate

`scripts/quality/check-lecture-license-gate.ps1` blocks lecture packages that rely on copied transcripts, unlicensed slides, unauthorized likenesses, or host-only media for required course paths. It accepts a `lecture-video.json` manifest and fails before publish when:

- `licenseAudit.status` is not `pass`, blocked materials remain, or required instruction still depends on an external host.
- Transcript metadata or text indicates copied, downloaded, or verbatim third-party transcript material.
- Slide attribution is missing, unknown, unlicensed, host-only, or points to unaudited source media.
- The generated instructor clones a real person or has unsafe voice or likeness consent.
- Required media points at `http` or `https` paths or declares host-only status.

The gate also has a deterministic `-SelfTest` mode that mutates the approved fixture into four blocked cases and confirms each one fails.

```powershell
.\scripts\quality\check-lecture-license-gate.ps1 -ManifestPath .\fixtures\lecture-video.gdev-101-design-vocabulary.json -SelfTest
```

## Generated Instructor Persona Rules

`fixtures/generated-instructor-persona.default.json` defines the default generated instructor policy. A lecture package must match an approved `personaId`, show learner-facing disclosure language, and use approved voice and likeness consent values before it can be published.

The default policy requires:

- Disclosure: "This lecture uses an original generated instructor and synthetic voice for an Open Education Suite lesson."
- Voice consent: only project-owned synthetic voices or explicitly consented voices.
- Likeness consent: only synthetic non-real-person likenesses or explicitly consented real-person likenesses.
- Tone: clear, rigorous, calm, specific about evidence, transparent about uncertainty, and supportive without false praise.
- Prohibited uses: real-person voice cloning without consent, real-person likeness cloning without consent, creator or teacher impersonation, undisclosed generated instruction, and false claims that a generated instructor is human or live.

The persona policy is checked by `scripts/quality/check-lecture-video.ps1` against the deterministic fixture so generated instructor disclosure, consent, and tone rules cannot drift silently.

## Local Archive Conventions

`fixtures/lecture-media-archive-policy.json` defines where rendered lecture media lives and how it is referenced. The current large-file storage decision is: do not commit rendered media to Git. Store rendered audio and video under the ignored local archive `var\lecture-media`, record SHA-256 checksums in `lecture-video.json`, and defer Git LFS or object storage until a publishing workflow needs versioned media distribution.

Conventions:

- Keep `lecture-video.json`, scripts, captions, transcripts, storyboards, slides metadata, and QA reports in Git.
- Keep rendered `.mp4`, `.m4a`, `.wav`, and similar large binaries under `var\lecture-media\{sourceId}\{packageId}\`.
- Required media must move from `planned` to `rendered` or `archived` before a course can depend on it.
- Rendered or archived media must use a 64-character SHA-256 checksum in the manifest.
- Required course paths cannot point only to hosted media.

## Lecture Accessibility Requirements

`fixtures/lecture-accessibility-policy.json` makes captions, transcripts, chapters, slides, and slide alt text required for every lecture package. Captions and transcripts are required package assets, not optional publish extras.

Requirements:

- Captions must be WebVTT, declare a language, start with `WEBVTT`, and include timestamps.
- Transcripts must be plain text, declare a language, and be readable without video.
- Chapters must include at least two meaningful segments, start at second `0`, and stay within lecture duration.
- Slides must include title, path, attribution, and meaningful alt text.
- Slides must be understandable from alt text and narration.
- Package metadata must support transcript-first, audio-first, and video-first learners.

## Video Teaching-Quality Rubric

`fixtures/lecture-video-quality-rubric.json` defines the video-specific teaching rubric used before publishing generated lectures. Each dimension uses a 1-5 score, with `3` as the minimum publishable baseline.

Required dimensions:

- Video Pacing: short, chaptered segments without long passive stretches.
- Worked Examples: original concrete examples connected to observable learner work.
- Active Recall: prediction, naming, retrieval, or decision prompts before answers are revealed.
- Misconception Checks: diagnostic contrasts for likely misunderstandings.
- Accessibility: captions, transcript, chapters, slide alt text, and narration that does not rely on visuals alone.
- Assessment Handoff: a practice or assessment artifact that creates evidence without treating watch completion as mastery.

## Source Review Matrix

Use these sources as representative teaching references. They are not source media for required course paths unless a later license audit explicitly approves local archival and reuse.

| Category | Representative source | What to review | Transferable teaching moves | Reuse boundary |
| --- | --- | --- | --- | --- |
| Open courseware | [MIT OpenCourseWare 6.0001 video lectures](https://ocw.mit.edu/courses/6-0001-introduction-to-computer-science-and-programming-in-python-fall-2016/video_galleries/video-lectures/) | Dense concept explanations, lecture segmentation, board-and-code rhythm | Start with a concrete problem, name the mental model, alternate explanation with worked examples, recap with precise vocabulary | Review pedagogy only; do not copy transcript, slides, screenshots, or lecturer likeness into generated packages |
| Open courseware | [Harvard CS50x lectures](https://cs50.harvard.edu/x/) | High-production lecture staging, demonstrations, recurring checks, problem-set handoff | Use a memorable opening demo, connect concepts to near-term practice, close with explicit next action | Link as optional reference only unless each asset license is audited for archival use |
| University course | [Stanford CS193p](https://cs193p.sites.stanford.edu/) | Iterative app-building lectures, live coding, incremental complexity | Build from a small complete artifact, narrate tradeoffs while coding, leave learners with a testable next increment | Do not copy code, project assets, or instructor style; derive only structure and pacing lessons |
| University course | [CMU 15-462/662 Computer Graphics](https://15462.courses.cs.cmu.edu/fall2020/) | Visual explanations, math-to-implementation transitions, assignment alignment | Pair equations with visual intuition, show failure modes, connect lecture topics to deliverables | Treat as reference-only unless course materials are separately licensed for reuse |
| Educator channel | [Crash Course Computer Science](https://www.youtube.com/playlist?list=PL8dPuuaLjXtNlUrzyH5r6jN9ulIgZBpdo) | Short scripted segments, strong analogies, clear chapter-sized ideas | Keep segments short, define terms before use, use analogy and contrast without reducing accuracy | Do not reuse narration, animation, visual identity, music, or hosted video files |
| Educator channel | [The Coding Train](https://www.youtube.com/@TheCodingTrain) | Conversational live coding, creative coding projects, mistake recovery | Normalize debugging, show exploratory thinking, turn mistakes into diagnostic questions | Do not clone persona, voice, catchphrases, code, or visual branding |
| Educator channel | [Game Maker's Toolkit](https://www.youtube.com/@GMTK) | Game design analysis, concrete examples, player-experience framing | Anchor abstract design ideas in observable player behavior, compare alternatives, end with design questions | Use as inspiration for critique structure only; do not copy clips, footage, scripts, or thumbnails |
| Professional talk | [GDC talks](https://www.youtube.com/@Gdconf) | Production postmortems, expert tradeoff discussion, domain vocabulary | Surface authentic constraints, include decision rationale, translate expert lessons into beginner-safe takeaways | Professional talks are optional references; do not archive talks or reuse studio assets without rights |
| Professional talk | [Strange Loop conference talks](https://www.youtube.com/@strangeloopconf) | Deep technical storytelling, concept framing, audience pacing | Build a thesis, layer examples, pause for implications, summarize transfer beyond the example domain | Reference teaching structure only; do not copy slides, talk audio, or speaker likeness |
| Professional talk | [Unity Learn](https://learn.unity.com/) | Tool-centered workflows, guided projects, skill-path sequencing | Use visible outcomes, checklist-style production steps, and checkpointed practice after each tool concept | Keep generated course content tool-agnostic unless the target course explicitly requires that tool |

The matrix should be extended per subject area before large-scale lecture generation. Each new entry should record the teaching pattern being borrowed and the material that is explicitly off limits.

## Teaching Patterns To Capture

- Clear opening problem and why the topic matters.
- Board or slide explanation paired with worked examples.
- Active recall pauses before revealing answers.
- Common misconception callouts with diagnostic questions.
- Short segments with chapter markers and objective tags.
- Practice handoffs after major concepts.
- Recaps that distinguish facts, procedures, and transfer questions.
- Accessibility-first narration that does not rely on visuals alone.
- Instructor warmth without false praise or unsupported claims.

## Adaptive Teacher Integration

The adaptive teacher should be able to:

- select a full lecture or a short segment based on learner state
- cite the content package source behind the segment
- offer transcript-first, audio-first, and video-first modes
- pause for checks for understanding
- branch to remediation when the learner misses a checkpoint
- resume from local progress without treating video completion as mastery by itself

## Checkpoint Evidence

Lecture checkpoints create learner-state evidence proposals, not mastery updates. `scripts/state/apply-lecture-checkpoint.ps1` appends a `lecture_checkpoint_submitted` learning event and an audit entry with unchanged confidence. It does not increment mastery `evidenceCount`, add `lecture-checkpoint` as a direct mastery evidence source, or treat passive video watch completion as proof of mastery.

The learner UI follows the same rule: saving a checkpoint writes `openEducationLectureCheckpoints` and appends the event to `openEducationLearnerState`, while preserving the current mastery confidence. The adaptive teacher can review the submitted answer and decide whether later assessment evidence should change mastery.

## Adaptive Lecture Selection

`fixtures/lecture-selection-rules.json` and `scripts/teaching/select-lecture-mode.ps1` let the teacher choose a full lecture, short segment, transcript, or remediation clip from learner state. The recommendation is `selection-only`; it does not change mastery.

Selection rules:

- `full-lecture`: no mastery evidence exists for the objective or confidence is below the starting threshold.
- `short-segment`: the learner has some evidence and needs focused review without an unresolved misconception.
- `transcript`: the learner has some evidence and accommodations or preferences favor text-first, low-distraction review.
- `remediation-clip`: a misconception or failed checkpoint is unresolved for the objective.

The rules explicitly forbid marking mastery from watch completion alone. They only select the lecture path; checkpoint, assessment, project, or instructor-reviewed evidence must drive any later mastery update.

## Operator Review Workflow

`fixtures/lecture-operator-review-workflow.json` defines the human approval workflow for generated lecture packages. `scripts/quality/check-lecture-operator-review.ps1` enforces the workflow and self-tests the publish gate.

Required stages:

- Script: citations, original narration, misconception checks, and assessment handoff.
- Visuals: original or licensed slide plan, alt text, no copied screenshots, and storyboard alignment.
- Media: local archive path, SHA-256 checksums, rendered or archived required media, and no host-only dependencies.
- Accessibility: captions, transcript, chapters, and slide alt text.
- License and persona: license gate pass, generated instructor disclosure, voice consent, and likeness consent.
- Final package approval: all required stages approved, quality rubric passed, content source linked, and operator final approval.

Generated systems, generated instructors, and automated checks cannot approve their own packages. A package can only move to `approved-for-publish` after all required stages are `approved`, required media is rendered or archived with 64-character checksums, and `finalApproval.status` is `approved` by an allowed operator. The deterministic GDEV fixture records script, visuals, accessibility, and license/persona approval, but remains `not-ready` until rendered media and final package approval are complete.

## Lecture Media Production Providers

`fixtures/lecture-production-providers.json` defines provider-neutral routing for lecture production. The default route uses the local sibling `ComfyUI-automation` repo for visuals, avatar rendering, and video assembly when available. Cloud providers remain opt-in profiles for TTS, avatar rendering, or video assembly.

Rules:

- Local ComfyUI production must copy outputs into `var\lecture-media` and record SHA-256 checksums before publish.
- Cloud providers must not store credentials in the repo; adapters may only read secret values from environment variables or a local-only secret store.
- Cloud outputs must be downloaded, archived, and checksummed before they can satisfy required course paths.
- Host-only cloud outputs are not acceptable for required lecture instruction.
- Provider routing is checked by `scripts/quality/check-lecture-production-providers.ps1`.

## Dry-Run Production Job

`scripts/teaching/build-lecture-production-job.ps1` turns a `lecture-video.json` package and provider profile into a deterministic dry-run job. It does not call ComfyUI, TTS, avatar, or cloud services. It only plans the production stages and expected archive outputs.

The dry-run job includes TTS, visuals, avatar, assembly, archive, and QA stages. Every required output path is under `var\lecture-media`, every renderable artifact requires `sha256`, and publish remains blocked until a real render, checksum/archive update, and operator review pass.

## Local ComfyUI Adapter

`scripts/teaching/invoke-comfyui-production-adapter.ps1` binds the dry-run production job to the sibling `ComfyUI-automation` repo. In default dry-run mode, it verifies the repo path, maps visuals, avatar, and assembly stages to existing workflow JSON files, and reports the planned handoff path without writing to the sibling repo.

The adapter can also read a completed output folder and report file lengths plus SHA-256 hashes. Operators can use `-Submit` later to write a handoff JSON into the sibling repo's `.codex-cache\tmp` area, but automated verification uses dry-run mode only.

## Cloud Production Adapter Contracts

`scripts/teaching/invoke-cloud-production-adapter.ps1` validates the secret-free cloud provider contracts for TTS, avatar, and video assembly. It reports only environment variable names and whether each variable is present; values are always redacted.

Cloud adapters stay opt-in. Verification runs in `contract-check` mode, so missing cloud credentials do not fail local development. Operators can use `-RequireConfigured` when they want to confirm that a specific machine is ready for cloud rendering. Even then, cloud outputs must be downloaded to `var\lecture-media`, checksummed, and approved before publish.

## Rendered Audio Fixture

`scripts/teaching/render-lecture-audio-fixture.ps1` produces a real short local WAV file for the GDEV lecture fixture under the ignored `var\lecture-media` archive. `fixtures/lecture-rendered-media.gdev-101.json` records the audio path, render engine, status, and SHA-256 checksum.

The audio fixture proves the archive can hold real generated media without committing binaries. It is not the final publishable lecture video; the package still requires final video assembly, checksum/archive manifest updates, and operator approval before `approved-for-publish`.

## Archive Manifest Update Tooling

`scripts/teaching/build-lecture-archive-manifest.ps1` builds the deterministic checksum/archive manifest view for a lecture package. By default it is a dry run: it reads `lecture-video.json` and rendered media metadata, computes SHA-256 values, and reports the current archive state without writing files.

The manifest covers audio, video, captions, and package metadata:

- Rendered audio and video files must live under `var\lecture-media` and have matching SHA-256 values before they can satisfy required publish media.
- Inline WebVTT captions are checksummed from `captions.text` so the package has a stable accessibility artifact even before captions are written to a standalone file.
- Package metadata is checksummed from the lecture manifest bytes so operator review can tie approval to the exact package being published.
- planned required media stays a publish blocker until the real file exists locally and the checksum matches.

The tool only writes when called with `-Apply -OutputPath ...`, and output is constrained to `var\lecture-media` or `.codex-cache\tmp`. The manifest also records `requiresOperatorPublishGate`, because checksums alone do not approve a lecture for learners.

## Operator Publish Gate Run

`scripts/teaching/render-lecture-publish-fixture.ps1` uses the local `ffmpeg` encoder to turn the rendered WAV fixture into archived M4A and MP4 files under `var\lecture-media`. This gives the operator gate a real rendered package candidate instead of a host-only URL or metadata-only placeholder.

`scripts/teaching/run-lecture-publish-gate.ps1` then builds a publish candidate, records the publish-ready path, and runs `scripts/quality/check-lecture-operator-review.ps1 -RequirePublishReady`. In dry-run mode it writes only to `.codex-cache\tmp`; with `-Apply`, it writes the approved package manifest to `var\lecture-media\...\publish\lecture-video.publish-ready.json`.

The gate can return `approved-for-publish` only when required media is archived, SHA-256 checksums are recorded, every review stage has an allowed human reviewer, and final package approval is present. The checked path is still an operator-controlled archive artifact; learner-facing selection should use it only after the production smoke test proves playback and transcript behavior.

## Production Learner Smoke Test

`scripts/testing/run-lecture-production-smoke.ps1` exercises the rendered package through the learner flow. It renders the deterministic publish fixture, applies the operator gate to write the publish-ready manifest under `var\lecture-media`, exports a temporary learner UI session against that manifest, and runs Playwright against the temporary UI copy.

The smoke test proves the learner can select the lecture view, load the archived MP4 asset, see the transcript and SHA-256 provenance, press play, and continue using the timeline. The test uses `.codex-cache\tmp` for the temporary UI and Playwright spec, while the approved package manifest stays in the ignored lecture media archive.

## Durability

Hosted third-party videos can disappear. Generated lecture packages should therefore keep local, checksummed artifacts for course-critical instruction. External videos can remain useful as optional references, but required learning paths should prefer locally generated packages or permissively licensed media that the project is allowed to archive.

## Acceptance Criteria

- A course can declare a lecture video requirement without embedding provider-specific assumptions.
- A generated lecture has source citations, captions, transcript, chapters, and QA metadata.
- The platform can distinguish optional external references from required locally archived instruction.
- The learner UI can show video, transcript, citations, checkpoints, and follow-up practice in one lesson flow.

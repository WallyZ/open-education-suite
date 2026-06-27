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
- `deliveryPlan`: audience mode, generic baseline use, single-learner adaptation rules, full-lecture duration target, segment cadence, learning-environment prompts, and board close-up plan.
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

## Generic Baseline And Single-Learner Adaptation

The suite should produce a shareable baseline lecture for a course objective, then adapt the teaching session around one learner. The baseline lecture is content-grounded and not personalized: it covers the objective, cites the course package, includes practice opportunities, and avoids assumptions about a specific learner. The adaptive teacher then selects the mode, pacing, examples, remediation, checkpoint prompts, and next lecture emphasis from that learner's evidence.

The default teaching sequence is:

1. Intro lecture: orient the learner, define the objective, and model the core ideas.
2. Diagnostic check: ask a short retrieval or application question before marking progress.
3. Materials and curriculum: provide the relevant reading, video, practice, and project structure.
4. Guided practice: create evidence through short answers, sketches, prototypes, or problem solving.
5. Progress assessment: test the learner against the objective without treating watch time as mastery.
6. Next lecture plan: choose the next full lecture, segment, transcript path, or remediation clip from the evidence.

The teacher must always cover the required material, but should adapt the route through it for the single learner's needs.

## Lecture Duration And Cadence

Use about 50 minutes as the target for full class-replacement lectures: `3000` seconds, with an acceptable range of `2700` to `3300` seconds. That does not mean 50 minutes of passive video. Full lectures should be divided into 5-12 minute concept segments, with active recall roughly every 6-10 minutes and practice handoffs every 10-15 minutes.

Short deterministic fixtures can remain 1-10 minutes for verification, smoke tests, previews, and publishing gates. Those fixtures must still carry the full-lecture duration policy so the production planner knows what to generate for real course delivery.

## Chalkboard And Board Close-Up

Generated lectures should default to a teacher at a chalkboard or equivalent board surface when the subject benefits from visual explanation. The board plan should identify each important board moment, its timestamp, label, and summary. The learner UI should expose a board close-up mode so a learner can inspect the board without losing the transcript, citations, or checkpoints.

Board visuals should be original or generated, accessible through narration and alt text, and useful without copying another teacher's board layout, slides, or visual identity.

## Learning Environment And Note-Taking

Lectures should prompt the learner to prepare an environment that supports real learning:

- Choose a quiet, low-distraction place.
- Keep a paper notebook and pen available.
- Listen first, then write the key words, diagrams, questions, and examples by hand.
- Pause before checkpoint answers are revealed.
- Rewrite notes after the lecture into cleaner terms, worked examples, and remaining questions.
- Treat practice and assessment evidence as the progress signal, not the feeling of having watched the lecture.

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
.\scripts\quality\check-lecture-license-gate.ps1 -ManifestPath ..\open-education-game-development\generated-lectures\gdev-101-design-vocabulary\lecture-video.json -SelfTest
```

## Generated Instructor Persona Rules

`fixtures/generated-instructor-persona.default.json` defines the default generated instructor policy. A lecture package must match an approved `personaId`, show learner-facing disclosure language, and use approved voice and likeness consent values before it can be published.

The default policy requires:

- Disclosure: "This lecture uses an original generated instructor and synthetic voice for an Open Education Suite lesson."
- Voice consent: only project-owned synthetic voices or explicitly consented voices.
- Likeness consent: only synthetic non-real-person likenesses or explicitly consented real-person likenesses.
- Voice matching: `generatedInstructor.gender`, `generatedInstructor.voiceMatchPolicy`, and `performancePlan.audioProfile` must agree before rendering; a male instructor routes to a masculine lower-register profile, a female instructor routes to a feminine profile, and neutral/nonbinary instructors route to a neutral adult profile.
- Tone: clear, rigorous, calm, specific about evidence, transparent about uncertainty, and supportive without false praise.
- Prohibited uses: real-person voice cloning without consent, real-person likeness cloning without consent, creator or teacher impersonation, undisclosed generated instruction, and false claims that a generated instructor is human or live.

The persona policy is checked by `scripts/quality/check-lecture-video.ps1` against the deterministic fixture so generated instructor disclosure, consent, and tone rules cannot drift silently.

## Persona Contract Stabilization

`schemas/generated-instructor-persona.schema.json` is the stable suite-owned contract for generated instructors. It covers persona identity, semantic version, status, disclosure, voice and likeness consent, gender/voice matching, likeness clone safety, mannerisms, teaching style, accessibility defaults, board interaction defaults, and operator review requirements.

Approved persona fixtures live under `fixtures/generated-instructor-personas/`. The current approved set includes male, female, and neutral instructor profiles with explicit voice register, emotion targets, board posture, provider references, and consent-safe likeness metadata. Blocked fixtures live under `fixtures/generated-instructor-personas/blocked/` and prove the contract rejects real-person cloning, missing disclosure, unapproved consent, and voice/gender mismatch.

`scripts/quality/check-generated-instructor-persona.ps1 -SelfTest` is the dedicated persona contract gate. It validates the default persona, approved fixtures, blocked fixtures, the GDEV lecture package reference, and the American History pilot persona reference. The suite verifier runs this gate before the broader lecture-video check so persona drift is caught even if a lecture package has not changed.

This is the split boundary for a future `open-education-teacher` repo: reusable voice profiles, avatar seeds, mannerism profiles, approved samples, consent records, and provider routing hints can move there once the schema remains stable. The suite should continue to own the schema, selector contract, learner-facing disclosure rules, and verifier gate. Subject repos should continue to own rendered lectures, transcripts, captions, board visuals, checksums, and subject-specific persona references.

## Teacher Media Repository Boundary

Reusable generated-instructor assets should move into a sibling `open-education-teacher` repo once the persona contract stabilizes. That repo should own project-approved persona profiles, voice profile references, image and avatar seeds, mannerism profiles, age/style variants, gender/voice matching rules, consent records, provider routing hints, and QA samples.

The suite should own only the schema, selection contract, safety gates, and learner UI behavior. Subject repos should own the finished lecture packages, transcripts, captions, checksums, rendered media metadata, and subject-specific board visuals. This keeps reusable teacher models separate from course content while still letting every generated lecture reference an approved instructor profile.

## Instructor Realism Contract

Each lecture package carries a `generatedInstructor.realismProfile` so realistic rendering has a deterministic target before a provider is plugged in. The profile must name the presentation style, render-readiness state, visual fidelity targets, movement plan, and board interaction plan.

The first GDEV fixture uses a realistic synthetic instructor at a chalkboard. It requires natural gaze shifts, board-aware pointing, pauses during active recall, no real-person clone, and a board layout where the instructor does not cover high-priority text. The current local path uses a ComfyUI-generated avatar keyframe as the instructor visual source; ffmpeg only assembles that rendered keyframe with audio for the short fixture.

## Local Archive Conventions

`fixtures/lecture-media-archive-policy.json` defines where rendered lecture media lives and how it is referenced. Generated lecture packages and subject-specific materials belong in the owning content repo. For game development, that means `F:\dev\open-education-game-development\generated-lectures\...`, not this core suite repo. The current large-file storage decision is: keep manifests, captions, transcripts, storyboards, QA metadata, and checksums in the content repo; ignore large rendered audio/video binaries until the project adopts Git LFS or object storage.

Conventions:

- Keep `lecture-video.json`, scripts, captions, transcripts, storyboards, slides metadata, and QA reports in the owning subject repo.
- The large binary rule is still: do not commit rendered media.
- Keep rendered `.mp4`, `.m4a`, `.wav`, and similar large binaries under `generated-lectures\{lectureSlug}\media\` in the owning subject repo, with that media folder ignored by Git unless a large-file policy replaces this rule.
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
- Learning Environment: low-distraction setup, pen-and-paper note taking, pausing before answers, and rewritten notes after the lecture.
- Board Clarity: legible board work, narrated diagrams, and close-up access.
- Instructor Realism: consistent synthetic identity, natural gaze and gestures, board-aware movement, and no real-person cloning.
- Adaptive Continuity: checkpoint and assessment evidence shape the next lecture while the required material remains covered.

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
- Instructor realism: face/body consistency, board occlusion check, gesture timing, and generated instructor disclosure.
- Final package approval: all required stages approved, quality rubric passed, content source linked, and operator final approval.

Generated systems, generated instructors, and automated checks cannot approve their own packages. A package can only move to `approved-for-publish` after all required stages are `approved`, required media is rendered or archived with 64-character checksums, and `finalApproval.status` is `approved` by an allowed operator. The instructor realism stage must explicitly document face/body consistency, board occlusion, gesture timing, and generated instructor disclosure before publish. The deterministic GDEV fixture records script, visuals, accessibility, and license/persona approval, but remains `not-ready` until rendered media, instructor realism review, and final package approval are complete.

## Lecture Media Production Providers

`fixtures/lecture-production-providers.json` defines provider-neutral routing for lecture production. The default route uses the local sibling `ComfyUI-automation` repo for visuals, avatar rendering, and video assembly when available. Cloud providers remain opt-in profiles for TTS, avatar rendering, or video assembly.

Rules:

- Local ComfyUI production must copy outputs into the subject content repo `generated-lectures` archive and record SHA-256 checksums before publish.
- Cloud providers must not store credentials in the repo; adapters may only read secret values from environment variables or a local-only secret store.
- Cloud outputs must be downloaded, archived, and checksummed before they can satisfy required course paths.
- Host-only cloud outputs are not acceptable for required lecture instruction.
- Provider routing is checked by `scripts/quality/check-lecture-production-providers.ps1`.

## Dry-Run Production Job

`scripts/teaching/build-lecture-production-job.ps1` turns a `lecture-video.json` package and provider profile into a deterministic dry-run job. It does not call ComfyUI, TTS, avatar, or cloud services. It only plans the production stages and expected archive outputs.

The dry-run job includes TTS, visuals, avatar, assembly, archive, and QA stages. Every required output path is under the subject content repo `generated-lectures` archive, every renderable artifact requires `sha256`, and publish remains blocked until a real render, checksum/archive update, and operator review pass.

## Local ComfyUI Adapter

`scripts/teaching/invoke-comfyui-production-adapter.ps1` binds the dry-run production job to the sibling `ComfyUI-automation` repo. In default dry-run mode, it verifies the repo path, maps visuals, avatar, and assembly stages to existing workflow JSON files, and reports the planned handoff path without writing to the sibling repo.

The adapter can also read a completed output folder and report file lengths plus SHA-256 hashes. Operators can use `-Submit` later to write a handoff JSON into the sibling repo's `.codex-cache\tmp` area, but automated verification uses dry-run mode only.

## Local ComfyUI TTS Readiness

`local-comfyui-tts` is now defined as a disabled local candidate provider for generic synthetic instructor voice. It uses the `ComfyUI-automation` Qwen3 voice-design workflow, not the voice-clone workflow, and stays behind a readiness gate until the runtime exposes the required TTS nodes.

Run the non-failing readiness report:

```powershell
.\scripts\quality\check-comfyui-tts-readiness.ps1
```

Run the strict gate before switching lecture voice routing to local ComfyUI:

```powershell
.\scripts\quality\check-comfyui-tts-readiness.ps1 -RequireReady
```

The gate requires `Qwen3TTSModelLoader`, `Qwen3TTSVoiceDesign`, and `SaveAudio`, rejects `Qwen3TTSVoiceClone`, and keeps operator listening review mandatory. On this machine, ComfyUI is reachable but the runtime does not currently expose those TTS node classes, so local ComfyUI voice rendering is not publish-ready yet.

## Rendered ComfyUI Avatar Fixture

`scripts/teaching/render-lecture-avatar-comfyui.ps1` renders the GDEV synthetic instructor keyframe through the local ComfyUI API and writes the image to the subject repo under `generated-lectures\gdev-101-design-vocabulary\media\visuals`. `lecture-avatar-rendered-media.json` records the local ComfyUI provider, workflow path, subject-owned media path, file length, and SHA-256 checksum.

The avatar keyframe is a real local generated visual, not an ffmpeg-drawn instructor block. The checked publish renderer uses `local-comfyui+ffmpeg`: ComfyUI supplies the instructor-at-chalkboard keyframe and ffmpeg assembles the MP4 with the local lecture audio.

## Cloud Production Adapter Contracts

`scripts/teaching/invoke-cloud-production-adapter.ps1` validates the secret-free cloud provider contracts for TTS, avatar, and video assembly. It reports only environment variable names and whether each variable is present; values are always redacted.

Cloud adapters stay opt-in. Verification runs in `contract-check` mode, so missing cloud credentials do not fail local development. Operators can use `-RequireConfigured` when they want to confirm that a specific machine is ready for cloud rendering. Even then, cloud outputs must be downloaded to the subject content repo, checksummed, and approved before publish.

For publish-grade lecture voice, the TTS adapter supports an OpenAI-compatible binary speech endpoint. Operators configure `LECTURE_TTS_PROVIDER`, `LECTURE_TTS_API_KEY`, `LECTURE_TTS_ENDPOINT`, `LECTURE_TTS_MODEL`, and `LECTURE_TTS_VOICE` outside the repo, then run:

```powershell
.\scripts\teaching\invoke-cloud-production-adapter.ps1 -RenderTts -RequireConfigured -ManifestPath ..\open-education-game-development\generated-lectures\gdev-101-design-vocabulary\lecture-video.json
```

The render writes `lecture-audio-neural-tts.mp3` and `lecture-neural-tts-rendered-media.json` under the owning subject repo's `generated-lectures` folder. The adapter never prints or stores credential values. The returned audio is still blocked from publish until the checksum/archive update and operator listening review pass.

## Rendered Audio Fixture

`scripts/teaching/render-lecture-audio-fixture.ps1` produces a real short local WAV file for the GDEV lecture fixture under `F:\dev\open-education-game-development\generated-lectures\gdev-101-design-vocabulary\media\audio`. `lecture-rendered-media.json` in that lecture folder records the audio path, render engine, status, and SHA-256 checksum.

The audio fixture proves the archive can hold real generated media without committing binaries. It is not the final publishable lecture video; the package still requires final video assembly, checksum/archive manifest updates, and operator approval before `approved-for-publish`.

## Archive Manifest Update Tooling

`scripts/teaching/build-lecture-archive-manifest.ps1` builds the deterministic checksum/archive manifest view for a lecture package. By default it is a dry run: it reads `lecture-video.json` and rendered media metadata, computes SHA-256 values, and reports the current archive state without writing files.

The manifest covers audio, video, captions, and package metadata:

- Rendered audio and video files must live under the subject repo `generated-lectures` archive and have matching SHA-256 values before they can satisfy required publish media.
- Inline WebVTT captions are checksummed from `captions.text` so the package has a stable accessibility artifact even before captions are written to a standalone file.
- Package metadata is checksummed from the lecture manifest bytes so operator review can tie approval to the exact package being published.
- planned required media stays a publish blocker until the real file exists locally and the checksum matches.

The tool only writes when called with `-Apply -OutputPath ...`, and output is constrained to the subject lecture archive or `.codex-cache\tmp`. The manifest also records `requiresOperatorPublishGate`, because checksums alone do not approve a lecture for learners.

## Operator Publish Gate Run

`scripts/teaching/render-lecture-publish-fixture.ps1` uses the local ComfyUI avatar keyframe plus the local `ffmpeg` encoder to turn the rendered WAV fixture into archived M4A and MP4 files under the game-development content repo's generated lecture folder. This gives the operator gate a real rendered package candidate instead of a host-only URL, metadata-only placeholder, or an ffmpeg-drawn instructor.

`scripts/teaching/run-lecture-publish-gate.ps1` then builds a publish candidate, records the publish-ready path, and runs `scripts/quality/check-lecture-operator-review.ps1 -RequirePublishReady`. In dry-run mode it writes only to `.codex-cache\tmp`; with `-Apply`, it writes the approved package manifest to `generated-lectures\...\publish\lecture-video.publish-ready.json` in the owning subject repo.

The gate can return `approved-for-publish` only when required media is archived, SHA-256 checksums are recorded, every review stage has an allowed human reviewer, and final package approval is present. The checked path is still an operator-controlled archive artifact; learner-facing selection should use it only after the production smoke test proves playback and transcript behavior.

## Production Learner Smoke Test

`scripts/testing/run-lecture-production-smoke.ps1` exercises the rendered package through the learner flow. It renders the deterministic publish fixture, applies the operator gate to write the publish-ready manifest under the subject repo `generated-lectures` folder, exports a temporary learner UI session against that manifest, and runs Playwright against the temporary UI copy.

The smoke test proves the learner can select the lecture view, load the archived MP4 asset, see the transcript and SHA-256 provenance, press play, and continue using the timeline. The test uses `.codex-cache\tmp` for the temporary UI and Playwright spec, while the approved package manifest stays in the ignored lecture media archive.

## Durability

Hosted third-party videos can disappear. Generated lecture packages should therefore keep local, checksummed artifacts for course-critical instruction. External videos can remain useful as optional references, but required learning paths should prefer locally generated packages or permissively licensed media that the project is allowed to archive.

## Acceptance Criteria

- A course can declare a lecture video requirement without embedding provider-specific assumptions.
- A generated lecture has source citations, captions, transcript, chapters, and QA metadata.
- The platform can distinguish optional external references from required locally archived instruction.
- The learner UI can show video, transcript, citations, checkpoints, and follow-up practice in one lesson flow.

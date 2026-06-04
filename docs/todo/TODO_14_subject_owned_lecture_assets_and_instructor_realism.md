# TODO 14 - Subject-Owned Lecture Assets And Instructor Realism

Generated lectures and subject-specific materials must live in the owning content repo, while this suite provides the ingestion, validation, rendering, and learner UI plumbing.

## Backlog

- [x] Add a subject-owned generated lecture folder contract so game-development lecture packages live under `F:\dev\open-education-game-development\generated-lectures\...`.
- [x] Update content ingestion so optional `generatedLectures` paths can expose `lecture-video.json` packages without pulling subject content back into the core repo.
- [x] Route the GDEV deterministic lecture manifest, rendered-media metadata, rendered media, publish-ready manifest, and learner UI media URLs from the game-development repo.
- [x] Add a first instructor realism contract covering presentation style, visual fidelity targets, movement, gaze, and chalkboard interaction.
- [x] Replace the deterministic ffmpeg instructor block with a real local ComfyUI/avatar render that satisfies the realism profile.
- [x] Add an operator realism review stage with checks for face/body consistency, board occlusion, gesture timing, and disclosure before publish.

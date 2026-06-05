# TODO 14 - Subject-Owned Lecture Assets And Instructor Realism

Generated lectures and subject-specific materials must live in the owning content repo, while this suite provides the ingestion, validation, rendering, and learner UI plumbing.

## Backlog

- [x] Add a subject-owned generated lecture folder contract so game-development lecture packages live under `F:\dev\open-education-game-development\generated-lectures\...`. <!-- ms:id 2962537db0ab -->
- [x] Update content ingestion so optional `generatedLectures` paths can expose `lecture-video.json` packages without pulling subject content back into the core repo. <!-- ms:id f58dd198ab4c -->
- [x] Route the GDEV deterministic lecture manifest, rendered-media metadata, rendered media, publish-ready manifest, and learner UI media URLs from the game-development repo. <!-- ms:id dc05eb643b55 -->
- [x] Add a first instructor realism contract covering presentation style, visual fidelity targets, movement, gaze, and chalkboard interaction. <!-- ms:id 99ac25c22996 -->
- [x] Replace the deterministic ffmpeg instructor block with a real local ComfyUI/avatar render that satisfies the realism profile. <!-- ms:id 29cd1d1aee20 -->
- [x] Add an operator realism review stage with checks for face/body consistency, board occlusion, gesture timing, and disclosure before publish. <!-- ms:id bc1a6ae9ee07 -->

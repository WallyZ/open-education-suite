# TODO 15 - Lecture Performance And Synchronized Board

Goal: make generated lectures feel useful as lectures, with human-sounding delivery, board visuals that match the lesson, and pause prompts that give learners real time to think and write.

## Items

- [x] Add a lecture performance contract for expressive human-sounding audio, timed pause prompts, and synchronized board/overlay direction.
- [x] Route the performance contract into the renderer/TTS/avatar production job so audio uses emotional prosody and pause gaps are rendered into the media timeline.
- [x] Replace static instructor video with scene-aware board visuals that match storyboard board moments and active-recall overlays.
- [x] Add operator review checks for audio naturalness, board-content synchronization, overlay timing, and learner usefulness before publish.
- [x] Add live learner UI evidence that pause overlays and board states appear at the right times during playback.
- [x] Build an updated GDEV lecture render using the new performance contract and compare it against the current static fixture.

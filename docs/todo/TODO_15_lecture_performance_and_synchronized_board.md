# TODO 15 - Lecture Performance And Synchronized Board

Goal: make generated lectures feel useful as lectures, with human-sounding delivery, board visuals that match the lesson, and pause prompts that give learners real time to think and write.

## Items

- [x] Add a lecture performance contract for expressive human-sounding audio, timed pause prompts, and synchronized board/overlay direction. <!-- ms:id 84c2ea3c45cc -->
- [x] Route the performance contract into the renderer/TTS/avatar production job so audio uses emotional prosody and pause gaps are rendered into the media timeline. <!-- ms:id e1631e44d5bc -->
- [x] Replace static instructor video with scene-aware board visuals that match storyboard board moments and active-recall overlays. <!-- ms:id 2da63ba0fd21 -->
- [x] Add operator review checks for audio naturalness, board-content synchronization, overlay timing, and learner usefulness before publish. <!-- ms:id 0cb9cd6e0cf5 -->
- [x] Add live learner UI evidence that pause overlays and board states appear at the right times during playback. <!-- ms:id a5af04ea7396 -->
- [x] Build an updated GDEV lecture render using the new performance contract and compare it against the current static fixture. <!-- ms:id 2651ba9fb2fd -->

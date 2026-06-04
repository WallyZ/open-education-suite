# TODO 16 - Natural Human Lecture Voice

Goal: make lecture narration sound like a real instructor by eliminating flat robotic delivery, preserving deterministic local fixtures, and preparing a publish-grade neural TTS path.

## Items

- [x] Replace flat local `Speak()` narration with selected installed voice rendering, sentence pacing, vocabulary emphasis, and active-recall pause silence.
- [x] Archive selected voice, available voices, prosody mode, sentence breaks, and inserted pause duration in the subject-owned rendered audio metadata.
- [x] Add quality checks that reject flat rendered audio metadata and require SSML pacing plus pause-silence evidence.
- [x] Add an opt-in publish-grade neural TTS adapter, local or cloud, with credentials kept outside the repo and rendered audio archived in the owning subject repo when configured.
- [x] Run a configured neural TTS provider for the first production voice candidate and archive the returned audio/checksum in `open-education-game-development`.
- [x] Add an operator listening review that compares the local expressive fixture against the neural render for warmth, clarity, emotion, pacing, and student usefulness.
- [x] Add a local ComfyUI TTS readiness gate that verifies required audio/TTS nodes and approved non-clone model paths before enabling local voice routing.
- [x] Wire an approved local ComfyUI TTS workflow for a generic synthetic instructor voice, then archive/checksum outputs in the owning subject repo.
- [x] Install or activate the approved ComfyUI TTS custom nodes and local model files after the ComfyUI repo backup/snapshot path is confirmed.
- [x] Run `check-comfyui-tts-readiness.ps1 -RequireReady` and capture the ready state before switching the lecture TTS route to local ComfyUI.
- [x] Render three local ComfyUI generic voice-design samples for the GDEV objective and compare them against the neural TTS candidate for warmth, clarity, emotion, pacing, pause handling, and student usefulness.
- [x] Promote the best local ComfyUI voice candidate only after operator listening review confirms it meets or beats the current neural TTS quality bar.

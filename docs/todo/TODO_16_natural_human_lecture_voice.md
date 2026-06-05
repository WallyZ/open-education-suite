# TODO 16 - Natural Human Lecture Voice

Goal: make lecture narration sound like a real instructor by eliminating flat robotic delivery, preserving deterministic local fixtures, and preparing a publish-grade neural TTS path.

## Items

- [x] Replace flat local `Speak()` narration with selected installed voice rendering, sentence pacing, vocabulary emphasis, and active-recall pause silence. <!-- ms:id 22041a80aa15 -->
- [x] Archive selected voice, available voices, prosody mode, sentence breaks, and inserted pause duration in the subject-owned rendered audio metadata. <!-- ms:id bf728bd511e5 -->
- [x] Add quality checks that reject flat rendered audio metadata and require SSML pacing plus pause-silence evidence. <!-- ms:id ee9b6bf758e8 -->
- [x] Add an opt-in publish-grade neural TTS adapter, local or cloud, with credentials kept outside the repo and rendered audio archived in the owning subject repo when configured. <!-- ms:id 4c85927f6150 -->
- [x] Run a configured neural TTS provider for the first production voice candidate and archive the returned audio/checksum in `open-education-game-development`. <!-- ms:id f11867331854 -->
- [x] Add an operator listening review that compares the local expressive fixture against the neural render for warmth, clarity, emotion, pacing, and student usefulness. <!-- ms:id 93d7afcdf55f -->
- [x] Add a local ComfyUI TTS readiness gate that verifies required audio/TTS nodes and approved non-clone model paths before enabling local voice routing. <!-- ms:id 16907886e67f -->
- [x] Wire an approved local ComfyUI TTS workflow for a generic synthetic instructor voice, then archive/checksum outputs in the owning subject repo. <!-- ms:id e8150343c499 -->
- [x] Install or activate the approved ComfyUI TTS custom nodes and local model files after the ComfyUI repo backup/snapshot path is confirmed. <!-- ms:id 232bf59e4fb4 -->
- [x] Run `check-comfyui-tts-readiness.ps1 -RequireReady` and capture the ready state before switching the lecture TTS route to local ComfyUI. <!-- ms:id ae26377cc3d0 -->
- [x] Render three local ComfyUI generic voice-design samples for the GDEV objective and compare them against the neural TTS candidate for warmth, clarity, emotion, pacing, pause handling, and student usefulness. <!-- ms:id 1b55ef6a7e9f -->
- [x] Promote the best local ComfyUI voice candidate only after operator listening review confirms it meets or beats the current neural TTS quality bar. <!-- ms:id 368122a4c7c7 -->

# TODO 17: Front-Row Classroom Video Realism

Goal: make generated lectures feel like sitting in the front row of a university classroom, with a realistic instructor, readable chalkboard, board-local writing, movement, and lip sync.

## Projects Reviewed for Ideas

- [Wav2Lip](https://github.com/Rudrabha/Wav2Lip) - audio-driven lip sync with strong mouth/audio alignment; useful for a future lip-sync stage after audio is finalized.
- [SadTalker](https://github.com/OpenTalker/SadTalker) - talking-head generation from a still image and audio; useful for moving beyond a static instructor keyframe.
- [MuseTalk](https://github.com/TMElyralab/MuseTalk) - real-time/high-quality lip sync; useful as a local or ComfyUI-backed candidate for instructor mouth movement.
- [ComfyUI-MuseTalk](https://github.com/chaojie/ComfyUI-MuseTalk) and [ComfyUI-MuseTalk-KJ](https://github.com/kijai/ComfyUI-MuseTalk-KJ) - ComfyUI integration routes for local production experiments.
- [LivePortrait](https://github.com/KlingAIResearch/LivePortrait) - portrait animation and motion transfer; useful for subtle instructor head motion, gaze shifts, and gesture plates.
- [ComfyUI-LivePortraitKJ](https://github.com/kijai/ComfyUI-LivePortraitKJ) and [comfyui-liveportrait](https://github.com/MixLabPro/comfyui-liveportrait) - ComfyUI routes for local portrait animation.
- [AniPortrait](https://github.com/Zejun-Yang/AniPortrait) and [ComfyUI-AniPortrait](https://github.com/chaojie/ComfyUI-AniPortrait) - audio/pose-conditioned portrait animation references for later higher-fidelity instructor motion.

## Work Items

- [x] Replace whole-video board subtitle overlays in the deterministic publish fixture with a board-local chalk writing layer anchored to explicit chalkboard coordinates.
- [x] Emit render metadata for the classroom composition, board surface, board writing layer, board close-up crop, and the fact that global instructional overlays are not used.
- [x] Update the lecture video quality gate to reject the old burned-in full-frame board overlay mode and require board-local writing metadata.
- [x] Render and archive a new GDEV comparison package that proves the board-local writing layer changes the MP4 checksum and remains subject-owned.
- [x] Add operator-review criteria for front-row framing, board readability, body/board occlusion, close-up usefulness, and absence of whole-frame teaching text overlays.
- [x] Add a local ComfyUI motion adapter spike for subtle instructor motion using LivePortrait or SadTalker-style motion before lip sync.
- [x] Add a local ComfyUI lip-sync adapter spike using MuseTalk or Wav2Lip-style audio-driven mouth movement.
- [x] Add deterministic metadata for motion/lip-sync stages: source frame, source audio, model/provider, seed/config, checksum, and archived output path.
- [x] Add visual QA checks for lip-sync timing, gaze direction, head/hand motion naturalness, and board-writing/gesture synchronization.
- [x] Add a board close-up render path that crops the board surface without losing audio, transcript checkpoints, or classroom context.
- [x] Add a guided-camera render that cuts between the front-row classroom view and board close-up during dense board and pause moments.
- [x] Replace the metadata-only motion/lip-sync stage with a real local preview render and promote it only after visual QA passes.
- [x] Replace subtitle-style board writing with a stroke-based chalk writing layer that appears progressively on the physical board.
- [x] Add extracted-frame QA evidence for board readability, instructor occlusion, camera shot selection, and board-surface alignment.
- [x] Route learner playback to the guided-camera render when available while keeping the classroom and board-only assets selectable.

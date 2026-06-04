# TODO 19: Publish-Grade Classroom Video Realism

Goal: move generated lecture video from deterministic preview realism to publish-grade classroom performance while preserving synthetic-instructor disclosure, subject-owned media archives, checksums, and operator QA.

## Projects Reviewed for Ideas

- [LivePortrait](https://github.com/KlingAIResearch/LivePortrait) - portrait motion transfer for subtle head, gaze, and expression movement.
- [SadTalker](https://github.com/OpenTalker/SadTalker) - still-image talking-head animation patterns for moving beyond static instructor frames.
- [MuseTalk](https://github.com/TMElyralab/MuseTalk) - high-quality lip-sync candidate for audio-driven instructor mouth movement.
- [Wav2Lip](https://github.com/Rudrabha/Wav2Lip) - mouth/audio alignment reference for lip-sync QA.
- [AniPortrait](https://github.com/Zejun-Yang/AniPortrait) - audio/pose-conditioned portrait animation reference for future full-performance control.
- [ComfyUI-MuseTalk-KJ](https://github.com/kijai/ComfyUI-MuseTalk-KJ) and [ComfyUI-LivePortraitKJ](https://github.com/kijai/ComfyUI-LivePortraitKJ) - local ComfyUI integration routes for model-backed production experiments.

## Work Items

- [x] Add a publish-grade instructor performance manifest and gate that distinguishes deterministic preview renders from model-backed motion/lip-sync candidates.
- [x] Require model-backed motion and lip-sync outputs to record provider, workflow, source frame/audio, seed/config, output path, SHA-256, duration, and operator visual QA status.
- [x] Add instructor gesture planning metadata for pointing, writing, gaze shifts, pause posture, and board-occlusion avoidance.
- [x] Add classroom scene realism targets for lighting, contact shadows, board surface integration, camera depth, lens motion, and compositing artifacts.
- [x] Add physical chalk-writing targets for chalk texture, stroke timing, erasing, hand alignment, and board residue.
- [x] Add automated visual comparison evidence for board readability, mouth-open timing, gaze direction, instructor occlusion, board crop correctness, and shot selection.
- [x] Add a shot-director plan that chooses front-row, board close-up, and instructor close-up shots based on teaching purpose.
- [x] Promote a model-backed instructor performance candidate only after checksum/archive refresh, automated QA evidence, and operator publish approval pass.

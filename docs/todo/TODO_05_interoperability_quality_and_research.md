# TODO 05 - Interoperability, Quality, and Research

## Goal

Keep the suite compatible with education ecosystems while building repeatable quality checks for adaptive behavior.

## Source Ideas

- Open edX and Moodle have mature integration and deployment ecosystems.
- OATutor is grounded in learning-science research and reports learning gains.
- Learning Locker implements xAPI learning records.
- OpenStax TutorJS uses end-to-end testing around realistic learner workflows.
- Sakai documents release support, accessibility, and internationalization discipline.

## Tasks

- [x] Document an interoperability target list: xAPI first, LTI later, import/export formats as needed. <!-- ms:id 7271f84a55cb -->
- [x] Add an event vocabulary for lesson viewed, practice attempted, hint used, mastery updated, review scheduled, and remediation assigned. <!-- ms:id 757326a7406a -->
- [x] Create deterministic fixtures for adaptive-teacher regression tests. <!-- ms:id 6b20c3101058 -->
- [x] Add golden-path learner workflow tests once a UI or CLI teaching loop exists. <!-- ms:id ace1b57a8033 -->
- [x] Define content quality checks for broken links, missing attribution, missing objective mappings, and malformed assessments. <!-- ms:id 51b8e6e1aae0 -->
- [x] Add evaluation metrics for mastery accuracy, time-to-remediation, hint usefulness, and learner retention. <!-- ms:id 93314ac69856 -->
- [x] Maintain a reviewed-projects section with source links and decisions borrowed or rejected. <!-- ms:id adbfe8b79f43 -->
- [x] Add an Open Education Suite Voice Studio session adapter that exports lecture/practice audio metadata as public-safe `voice-studio/session/v1`. <!-- ms:id f68f6c83b1bb -->
  - Evidence (2026-06-10): Added `scripts/teaching/export-voice-session-contract.ps1`, verifier checks in `scripts/codex-verify.ps1`, and operator docs in `docs/WORKFLOW.md`. The adapter emits sanitized refs and logical segments only; verifier rejects raw audio paths, generated media paths, hashes, private repo names, and credential markers.
  - Verification: `.\scripts\codex-verify.ps1`.
- [ ] Define reusable Voice Studio and Video Studio module contracts so content repos can import sanitized performance metrics from creator/recording workflows without tracking private media. [PH2] <!-- ms:evidence id=1a08bd1a3f33 path=..\open-education-performing-arts\resources\voice-studio-integration-contract.md strings="Sanitized Progress Fields,Private Data Boundary,Video Studio" --> <!-- ms:meta priority=p2 owner=@owner stale-days=30 automation-level=assisted human-checkpoint=review rollout-scope=multi-repo validation-profile=cloud safe-autofix=manual updated=2026-06-10 -->
  - Deliverables: stable sanitized metric schemas, importer design, privacy gate, and module boundary notes for Voice Studio and Video Studio.
  - Files: `docs/todo/TODO_05_interoperability_quality_and_research.md`, `content-sources.json`, `..\open-education-performing-arts\resources\voice-studio-integration-contract.md`, `..\open-education-performing-arts\resources\video-studio-module-brief.md`.
  - Verification: `.\scripts\codex-verify.ps1`.
  - QA Live automation: Reuse learner UI and content-ingestion checks once the importer has a UI or workflow surface.
  - Drift guard: Contract fields must reject raw media, embeddings, waveform data, face data, motion data, and private file paths.
  - Downstream rollout: Coordinate with `F:\dev\youtube-automation` before extracting any shared Voice Studio or Video Studio module.
  - Current status: Voice Studio session export is verifier-backed in this repo; full closeout still needs the Video Studio sanitized-performance contract/import side to reach the same level.
  - Acceptance:
    - Open Education Suite can ingest sanitized practice progress without private media.
    - YouTube Automation can keep production-specific behavior while sharing only reusable studio contracts.

## Acceptance Notes

- Quality checks should be runnable through `.\scripts\codex-verify.ps1`.
- Research-inspired features should become testable product behavior, not only notes.
- Interoperability should not compromise the separate content repo boundary.

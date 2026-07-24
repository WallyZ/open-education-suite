# TODO 22 - Subject Brain Federation

## Goal

Provide a rights-safe federation of specialist knowledge systems that can act
as cited subject matter context for an adaptive teacher without replacing
curriculum truth, deterministic learner state, or human review.

## Foundation

- [x] Add a machine-readable registry covering existing and planned K-12 subject brains. <!-- ms:id 7f21c0c418b1 -->
- [x] Add manifest, corpus, registry, and query-result schemas with rights, provenance, citation, age-band, privacy, and state-mutation boundaries. <!-- ms:id d8e6ae2c5104 -->
- [x] Add a dependency-free validation, local indexing, and lexical retrieval adapter with optional PDF extraction. <!-- ms:id a927b373e765 -->
- [x] Let the AI teaching prompt consume saved subject-brain retrieval results as cited context. <!-- ms:id 301437266e6d -->
- [x] Add localhost-only Ollama and LM Studio teacher invocation using the same prompt and output evaluation contract. <!-- ms:id 0f2778827836 -->
- [x] Register starter contracts for critical thinking, psychology/learning science, and biblical/theological literacy. <!-- ms:id 50160fdce5c7 -->

## Production Readiness

- [x] Create and validate the planned language/literature, mathematics, science/engineering, history/civics, economics/finance, computing, health/fitness, arts, human-relations, and practical-life brain repos. <!-- ms:id 063f36d6b42f --> <!-- ms:meta priority=p1 owner=@owner stale-days=30 automation-level=assisted human-checkpoint=review rollout-scope=multi validation-profile=cloud safe-autofix=review updated=2026-07-20 -->
- [ ] Add deterministic EPUB spine, PDF page/figure, OCR confidence, audiovisual timestamp, equation, table, code-block, and primary-source section locators. <!-- ms:id bb4acb47a630 --> <!-- ms:meta priority=p1 owner=@owner stale-days=30 automation-level=assisted human-checkpoint=review rollout-scope=multi validation-profile=cloud safe-autofix=review updated=2026-07-20 -->
- [ ] Add hybrid lexical/vector retrieval, subject-aware chunking, reranking, duplicate/version resolution, and cross-brain query planning while keeping a lexical offline fallback. <!-- ms:id ee7b860d4281 --> <!-- ms:meta priority=p1 owner=@owner stale-days=30 automation-level=assisted human-checkpoint=review rollout-scope=multi validation-profile=cloud safe-autofix=review updated=2026-07-20 -->
- [ ] Add corpus coverage reports by grade, objective, topic, source type, viewpoint, edition, rights status, freshness, and accessibility; fail learner release on critical holes. <!-- ms:id f5dadf9671ec --> <!-- ms:meta priority=p1 owner=@owner stale-days=30 automation-level=assisted human-checkpoint=review rollout-scope=multi validation-profile=cloud safe-autofix=review updated=2026-07-20 -->
- [ ] Seed every registered course repo with objective-, misconception-, assessment-, source-, and lecture-level AI knowledge records instead of relying on a few hand-written summaries. <!-- ms:id 17e6f73639f4 --> <!-- ms:meta priority=p1 owner=@owner stale-days=30 automation-level=assisted human-checkpoint=review rollout-scope=multi validation-profile=cloud safe-autofix=review updated=2026-07-20 -->
- [ ] Build grade-banded gold question sets and evaluate retrieval recall, citation precision, factual correctness, calibration, viewpoint balance, age appropriateness, accessibility, refusal behavior, and delayed tutor-transcript review. <!-- ms:id bf6b6eb003dd --> <!-- ms:meta priority=p1 owner=@owner stale-days=30 automation-level=assisted human-checkpoint=review rollout-scope=multi validation-profile=cloud safe-autofix=review updated=2026-07-20 -->
- [ ] Add explicit cross-source disagreement packets and require the teacher to distinguish fact, interpretation, uncertainty, application, and conviction on controversial subjects. <!-- ms:id bb44b5645465 --> <!-- ms:meta priority=p1 owner=@owner stale-days=30 automation-level=assisted human-checkpoint=review rollout-scope=multi validation-profile=cloud safe-autofix=review updated=2026-07-20 -->
- [ ] Complete owner-reviewed source acquisition, checksum, license, AI-ingestion-terms, edition, alternate-route, and refresh records before expanding beyond starter corpora. <!-- ms:id b604bc6e4bf0 --> <!-- ms:meta priority=p1 owner=@owner stale-days=30 automation-level=assisted human-checkpoint=review rollout-scope=multi validation-profile=cloud safe-autofix=review updated=2026-07-20 -->
- [ ] Run real local-model pilots with Ollama and LM Studio, capture reproducible model/version/prompt evidence, and block promotion when a smaller model cannot teach the subject reliably. <!-- ms:id 15b03c6412d2 --> <!-- ms:meta priority=p1 owner=@owner stale-days=30 automation-level=assisted human-checkpoint=review rollout-scope=multi validation-profile=cloud safe-autofix=review updated=2026-07-20 -->

## Acceptance Notes

- A subject brain retrieves evidence; it never becomes the sole durable truth.
- A teacher answer is not grounded merely because it contains a citation. The
  cited passage must support the exact claim and locator.
- Purchased or free-to-read material is not automatically licensed for local
  ingestion, model context, redistribution, or training.
- Production readiness requires real question and transcript evidence, not
  only schema validation.

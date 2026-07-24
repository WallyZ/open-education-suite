# AI Teacher Model Integration

The AI teacher is an instructional layer over deterministic content ingestion, learner state, assessment, and state update code. It can explain and propose, but it does not directly mutate durable learner state.

## Tool Contract

The AI teacher may use these platform tools:

- `content.lookup`: read ingested source objects and source snippets
- `learner_state.read`: read a summarized learner state
- `next_action.read`: read the deterministic next action
- `assessment.read`: read assessment prompt, accepted answer metadata, hints, and feedback templates
- `offline_knowledge.lookup`: read local course seed records and private overlays from the offline AI knowledge store
- `offline_knowledge.write_note`: write local/private AI or learner notes without changing public course seed records
- `subject_brain.query`: retrieve rights-approved specialist excerpts with exact source locators
- `ai_runtime.select`: select Ollama or LM Studio local runtime profile
- `state_update.propose`: propose a state update for checked code to validate and apply

## Prompt Contract

`scripts/ai/build-teaching-prompt.ps1` emits a model-ready JSON payload containing:

- teacher role
- objective id
- learner state summary
- deterministic next action
- source snippets and provenance
- optional subject-brain retrieval results with source, locator, checksum, and license
- learner constraints and preferences
- desired output shape
- guardrails

## Guardrails

- Cite source repo id and source path for content explanations.
- Cite the exact subject-brain locator when specialist context is used.
- Treat specialist retrieval as supplemental context; do not override the scheduled objective or reviewed lesson source silently.
- Disclose material source disagreement and state when retrieved evidence is insufficient.
- Separate observed evidence from diagnosis.
- Ask calibrated questions before giving away answers in Socratic mode.
- Refuse or ask for clarification when source content is missing.
- Keep state mutations as proposals only.
- Preserve accessibility and learner agency.

## Output Evaluation

`scripts/ai/evaluate-model-output.ps1` checks saved model-output fixtures for:

- grounded source citations
- no unsupported claims
- objective alignment
- appropriate tone
- accessible wording
- useful next step
- no direct durable state mutation

## Live Smoke Test

`scripts/ai/invoke-openai-teacher.ps1` can call the OpenAI Chat Completions API using `OPENAI_API_KEY`. It writes the prompt payload and model output to caller-provided paths under `.codex-cache\tmp\` or another controlled run directory.

The learner UI bridge keeps live model calls disabled by default. `scripts/teaching/learner_ui_bridge_server.py` must be started with `--enable-live-ai` before `/api/teacher/live` will invoke `scripts/ai/invoke-openai-teacher.ps1`; otherwise the endpoint returns `live-ai-disabled` without using credentials or network.

## Offline AI Knowledge Store

`docs/offline-ai-knowledge-store.md` defines the local database template for offline AI tutors. The suite owns the schema and builder; subject repos own public-safe seed manifests and records.

Use:

```powershell
.\scripts\ai\build-offline-knowledge-store.ps1 -Provider ollama -OutputRoot .\.codex-cache\tmp\offline-ai-store
```

The builder reads registered content repos from `content-sources.json`, finds each repo's `aiKnowledgeStore` manifest, validates public/private boundaries, and emits `manifest.json`, `records.jsonl`, and `offline-knowledge-store.sqlite`. Use `-Provider lm-studio` when LM Studio should host the local model. Normal verification remains deterministic and does not require either runtime to be installed.

`scripts/testing/run-live-gdev-teacher-smoke.ps1` performs a live GDEV-101 smoke test:

- builds a learner state for `game-development:objectives/course/gdev-101/design-vocabulary`
- verifies the prompt includes a real excerpt from `study-plans\courses\GDEV-101-game-design-foundations.md`
- calls the live model
- validates the saved model output with `scripts/ai/evaluate-model-output.ps1`
- checks the model cites the GDEV-101 course file and preserves learner adaptation evidence

The live smoke test is intentionally not part of `scripts/codex-verify.ps1`, because normal verification must remain deterministic and runnable without network access or API credentials.

## Specialist Subject Brains

`docs/subject-brain-federation.md` defines the discovery, corpus, rights, and
query contracts. The local adapter validates `subject-brains.json`, builds a
per-brain SQLite FTS index, and returns retrieval-only JSON. Save that JSON and
pass it to:

```powershell
.\scripts\ai\build-teaching-prompt.ps1 -SubjectBrainResultsPath <query-result.json>
```

For an installed local model, use
`scripts/ai/invoke-local-teacher.ps1 -Provider ollama|lm-studio`. It accepts the
same subject-brain result and refuses non-localhost endpoints. Live local-model
calls remain outside normal deterministic verification.

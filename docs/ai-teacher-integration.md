# AI Teacher Model Integration

The AI teacher is an instructional layer over deterministic content ingestion, learner state, assessment, and state update code. It can explain and propose, but it does not directly mutate durable learner state.

## Tool Contract

The AI teacher may use these platform tools:

- `content.lookup`: read ingested source objects and source snippets
- `learner_state.read`: read a summarized learner state
- `next_action.read`: read the deterministic next action
- `assessment.read`: read assessment prompt, accepted answer metadata, hints, and feedback templates
- `state_update.propose`: propose a state update for checked code to validate and apply

## Prompt Contract

`scripts/ai/build-teaching-prompt.ps1` emits a model-ready JSON payload containing:

- teacher role
- objective id
- learner state summary
- deterministic next action
- source snippets and provenance
- learner constraints and preferences
- desired output shape
- guardrails

## Guardrails

- Cite source repo id and source path for content explanations.
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

`scripts/testing/run-live-gdev-teacher-smoke.ps1` performs a live GDEV-101 smoke test:

- builds a learner state for `game-development:objectives/course/gdev-101/design-vocabulary`
- verifies the prompt includes a real excerpt from `study-plans\courses\GDEV-101-game-design-foundations.md`
- calls the live model
- validates the saved model output with `scripts/ai/evaluate-model-output.ps1`
- checks the model cites the GDEV-101 course file and preserves learner adaptation evidence

The live smoke test is intentionally not part of `scripts/codex-verify.ps1`, because normal verification must remain deterministic and runnable without network access or API credentials.

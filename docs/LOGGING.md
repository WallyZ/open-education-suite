# LOGGING

Logging standard for `open-education-suite`, aligned with `00-repo-kit`.

## Goals

- Correlate verifier, ingestion, teaching, assessment, learner UI, and QA Live runs.
- Keep logs useful at normal verbosity and expandable during investigation.
- Redact learner private data, credentials, model prompts when sensitive, and environment secrets.
- Keep logs and temp artifacts in approved locations.

## Levels

Use only these levels:

- `TRACE`: deep diagnostic details for short investigations.
- `DEBUG`: detailed deterministic state useful for development.
- `INFO`: default progress and summary events.
- `WARN`: recoverable issue or degraded behavior.
- `ERROR`: failed operation requiring attention.
- `FATAL`: unrecoverable process-level failure.

## Required fields

Structured events should include:

- `ts`
- `level`
- `component`
- `event`
- `msg`
- `run_id`
- `trace_id`
- `source`

Recommended fields:

- `duration_ms`
- `attempt`
- `exit_code`
- `content_source_id`
- `objective_id`
- `learner_state_id` only when pseudonymous and safe
- `qa_live_report`

## Runtime controls

Precedence:

1. CLI flag such as `--log-level` when a script exposes it.
2. `LOG_LEVEL_<COMPONENT>` environment variable.
3. `LOG_LEVEL` environment variable.
4. Script default.

Use profiles when available:

- `normal`: `INFO` console, concise file logging.
- `investigation`: `DEBUG` for selected component.
- `deep_trace`: `TRACE` for a short, explicit run only.

## Sinks and paths

- Verification logs: `.codex-cache/logs/`.
- Verification temp files: `.codex-cache/tmp/<run-id>/`.
- QA Live reports: repo-owned QA Live report paths or adjacent `qa-live-test-system` report paths named in the run output.
- Do not write ad hoc logs to repo root.
- Do not commit `.codex-cache/`, generated QA traces, screenshots, browser artifacts, or local media unless a fixture/spec explicitly requires it.

## Redaction

Never log raw:

- `.env*` contents,
- API keys, tokens, private keys, or credentials,
- learner personally identifying data,
- private learner free-response text unless a test fixture is explicitly synthetic,
- raw model prompts/responses that contain private content.

Use the shared adapters when adding new Python or PowerShell logging:

- `scripts/logging/repokit_logging_adapter.py`
- `scripts/logging/RepoKit.LoggingAdapter.psm1`

## Unreal/toolchain adapter note

This repo does not normally run Unreal Editor, UAT, or UBT. The Unreal ingestion contract is installed for downstream game/Unreal repos and for sibling generated-lecture tooling reference only:

- `docs/logging/unreal_ingestion_contract.json`
- `scripts/logging/unreal_log_ingest_adapter.py`

Do not add Unreal runtime logging to this repo unless a future feature introduces an actual Unreal integration boundary.

## Verification

The canonical verifier is the first logging quality gate:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex-verify.ps1
```

When adding logging behavior, include checks for level override behavior, redaction, and correlation IDs in the narrowest script or fixture that exercises the new path.

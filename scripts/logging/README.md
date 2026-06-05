# Logging Adapters

Shared logging adapters for downstream repos.

## Files

- `repokit_logging_adapter.py`
  - Python structured logger adapter.
  - Auto-injects `run_id`/`trace_id`.
  - Supports `LOG_LEVEL` + `LOG_LEVEL_<COMPONENT>` overrides.
  - Redacts seeded/env secret values and sensitive key patterns.
- `RepoKit.LoggingAdapter.psm1`
  - PowerShell structured logging module with the same contract.
- `unreal_log_ingest_adapter.py`
  - Normalizes Unreal Editor/UAT/UBT log lines into unified events.
- `test_python_logging_adapter_smoke.py`
  - Python smoke checks for level override + redaction.
- `Test-RepoKitLoggingAdapterSmoke.ps1`
  - PowerShell smoke checks for level override + redaction.
- `test_unreal_log_ingest_regression.py`
  - Fixture-driven regression checks for Unreal line normalization.
- `fixtures/unreal_ingest_cases.json`
  - Real-world-style Unreal/UAT/UBT line fixtures and expected normalized output.

## Usage

Python smoke:

```powershell
python .\scripts\logging\test_python_logging_adapter_smoke.py
```

PowerShell smoke:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\logging\Test-RepoKitLoggingAdapterSmoke.ps1
```

Unreal ingestion example:

```powershell
python .\scripts\logging\unreal_log_ingest_adapter.py --source ue_editor --run-id run-001 --trace-id trace-001 --input .\logs\Editor.log --output .\logs\Editor.normalized.jsonl
```

Unreal ingestion regression:

```powershell
python .\scripts\logging\test_unreal_log_ingest_regression.py
```

# Tech Context

## Languages and tools

- PowerShell for verifier, ingestion, state, assessment, quality gates, and QA runners.
- Python for lifecycle, TODO audit, logging helpers, and bridge scripts.
- JavaScript/Playwright for learner UI browser checks.
- JSON schemas and fixtures for deterministic validation.

## Verification

Use:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex-verify.ps1
```

Do not run direct test runners unless explicitly requested.

## Runtime boundaries

- Default verification is offline-safe and deterministic.
- Live AI and hosted checks are opt-in.
- QA Live runtime checks must use repo-owned specs/contracts and the adjacent harness.

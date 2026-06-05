# Memory Scripts

## refresh_memory_bank.ps1

Refreshes compact memory-bank artifacts for Cline waves with profile-specific budgets.

### What it updates

- `memory-bank/activeContext.md`
- `memory-bank/progress.md`
- `memory-bank/context-pack.md` (unless `-SkipContextPack`)
- `memory-bank/.refresh_state.json` (state for TODO deltas and profile resolution)

## sync_repo_kit_catalog.ps1

Refreshes `memory-bank/repoKitCatalog.md` with a deterministic snapshot of reusable repo-kit capabilities and pull commands.

### Usage

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\memory\sync_repo_kit_catalog.ps1 -RepoRoot . -RepoKitRoot F:\dev\00-repo-kit
```

Dry-run preview:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\memory\sync_repo_kit_catalog.ps1 -RepoRoot . -RepoKitRoot F:\dev\00-repo-kit -DryRun
```

## Context profiles

- `auto` (default): resolves to `32k`, `64k`, or `cloud` using runtime signals.
- `32k`: local AI profile with extremely aggressive compression.
- `64k`: local AI profile with still-aggressive compression.
- `cloud`: richer but bounded profile for hosted/cloud runtimes.

Resolution order for `auto`:
1. `-ContextProfile 32k|64k|cloud` parameter override.
2. `CLINE_CONTEXT_PROFILE=32k|64k|cloud`.
3. `CLINE_MODEL_RUNTIME=local|ondevice|on-device` -> `32k`.
4. `CLINE_MODEL_RUNTIME=hosted|cloud|remote` -> `cloud`.
5. Local indicators (`OLLAMA_*`, `LM_STUDIO_*`, `LOCALAI_*`, or local `CLINE_PROVIDER`) -> `32k`.
6. Fallback to `cloud`.

## pre_tool_context_guard.ps1

Pre-tool guard script to block context anti-patterns before heavy tool use.

Checks include:
- pointer-file size/line budgets
- pointer-only behavior guard (`docs/CLINE_TASK_CURRENT.md`)
- memory-bank line budgets by resolved profile (`auto|32k|64k|cloud`)
- optional `.clineignore` allowlist enforcement

### Usage

```powershell
pwsh -File .\scripts\memory\pre_tool_context_guard.ps1 -RepoRoot . -RequireMemoryFiles
```

Force explicit profile:

```powershell
pwsh -File .\scripts\memory\pre_tool_context_guard.ps1 -RepoRoot . -ContextProfile 32k -RequireMemoryFiles
```

## post_tool_memory_reminder.ps1

Post-tool hook script that reminds or auto-refreshes memory-bank files when non-memory files changed.

### Usage

```powershell
pwsh -File .\scripts\memory\post_tool_memory_reminder.ps1 -RepoRoot .
```

```powershell
pwsh -File .\scripts\memory\post_tool_memory_reminder.ps1 -RepoRoot . -AutoRefresh
```

## Memory quality check

Use lifecycle checker for structure/freshness/link validation:

```powershell
python .\scripts\lifecycle\check_memory_bank.py --repo-root . --profile cloud --max-handoff-tokens 2000
```

Strict mode (require memory-bank files to exist):

```powershell
python .\scripts\lifecycle\check_memory_bank.py --repo-root . --profile 32k --require-memory-bank
```

Required memory files now include:
- `memory-bank/repoKitCatalog.md`
- `memory-bank/solutionHarvest.md`

## Bootstrap integration

Install starter memory-bank files and hook wrappers together:

```powershell
pwsh -File .\scripts\bootstrap\bootstrap_memory_bank.ps1 -TargetRepo . -Force -InstallHooksProfile -AutoRefreshPostHook
```

Install hooks only:

```powershell
pwsh -File .\scripts\bootstrap\install_cline_hooks_profile.ps1 -TargetRepo . -Force -AutoRefreshPostHook
```

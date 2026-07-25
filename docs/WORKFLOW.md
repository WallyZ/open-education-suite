# Workflow

## 1. Work in the Correct Repo

- Platform and ingestion changes happen in `open-education-suite`.
- Subject content changes happen in a sibling `open-education-*` content repo.

## 2. Register Content Sources

Update `content-sources.json` when adding, renaming, or removing a content repo.

Content repos may declare an optional, URL-safe `httpSlug` in `content-repo.json`. The learner bridge uses that value for `/content-repos/<slug>/...` URLs so a repo remains portable across renamed checkouts, junctions, and isolated worktrees. Existing repos without `httpSlug` continue to use the content repo folder name.

AI knowledge record checksums accept the manifest-declared byte hash or the equivalent UTF-8 text hash after CRLF-to-LF normalization. This preserves content integrity without making a valid package depend on Git checkout line-ending settings.

## 3. Ingest Content

The suite should read content repos through their manifests, normalize learning objects, and preserve source attribution. Ingestion should be read-only until a task explicitly requires authoring support.

## 4. Adapt Teaching

Use the learner model, mastery evidence, prerequisites, and review history to choose the next explanation, practice item, quiz, project, or remediation.

## 5. Select the Local Learner Profile

The learner UI supports multiple local students on the same computer/browser. Before studying, select or create the active student profile in the Learner Workspace rail. Profile-specific preferences and records stay local and are stored under scoped browser keys for that learner id, including learner state, assessment evidence, lecture checkpoints, journal entries, lecture resume position, and last course selection.

Use profile fields for display name, goals, explanation style, practice mode, learning pace, preferred format, accommodations, and prior experience. Keep sensitive accommodations local and avoid putting real learner PII into fixtures or support bundles.

## 6. Verify

Run:

```powershell
.\scripts\codex-verify.ps1
```

Report the command, exit code, and log path when verification fails.

## 7. Run the Learner UI Bridge Locally

The learner UI bridge is the local web surface for browser-based learner workflow checks. It defaults to `http://127.0.0.1:8786/ui/learner/index.html`.

Start it directly when you want a foreground process:

```powershell
.\scripts\start_learner_ui_bridge.ps1
```

The bridge also exposes a `local-app-launcher/v1` consumer adapter for the shared `local-app-launcher-kit`. Export the manifest with:

```powershell
.\scripts\export_local_app_launcher_manifest.ps1 -OutputPath .codex-cache\launcher\open-education-learner-ui-bridge.json
```

Use the manager wrapper to delegate start, stop, restart, status, startup-task, and watchdog operations to the shared launcher kit:

```powershell
.\scripts\manage_learner_ui_launcher.ps1 -Action Start
.\scripts\manage_learner_ui_launcher.ps1 -Action Status
.\scripts\manage_learner_ui_launcher.ps1 -Action Restart
.\scripts\manage_learner_ui_launcher.ps1 -Action Stop
```

The live port defaults to `8786`; the test port defaults to `8787`. The shared launcher may select the next open port in each range and passes it through `LOCAL_APP_LAUNCHER_SELECTED_PORT`, which `scripts/start_learner_ui_bridge.ps1` honors.

Windows startup is supported but not enabled by default for this repo. To enable it intentionally, run:

```powershell
.\scripts\manage_learner_ui_launcher.ps1 -Action InstallStartup
.\scripts\manage_learner_ui_launcher.ps1 -Action EnableStartup
```

Disable or remove startup with:

```powershell
.\scripts\manage_learner_ui_launcher.ps1 -Action DisableStartup
.\scripts\manage_learner_ui_launcher.ps1 -Action UninstallStartup
```

## 8. Export Voice Studio Session Metadata

The suite can export public-safe lecture/practice audio metadata to the shared `voice-studio/session/v1` contract without copying raw audio, voiceprints, model artifacts, hashes, generated media paths, or private file paths.

Export the default GDEV lecture voice session contract:

```powershell
.\scripts\teaching\export-voice-session-contract.ps1 -OutputPath .codex-cache\tmp\voice-studio-session.json
```

The export maps lecture board sections and active-recall pauses into logical `recording_plan.segments`. It uses sanitized `speaker_ref`, `script_ref`, and logical artifact refs only. Raw/generated audio remains in the owning subject repo or ignored runtime storage; the contract is metadata for reusable Voice Studio and education-progress adapters.

The canonical verifier checks this contract through:

```powershell
.\scripts\codex-verify.ps1
```

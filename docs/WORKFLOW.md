# Workflow

## 1. Work in the Correct Repo

- Platform and ingestion changes happen in `open-education-suite`.
- Subject content changes happen in a sibling `open-education-*` content repo.

## 2. Register Content Sources

Update `content-sources.json` when adding, renaming, or removing a content repo.

## 3. Ingest Content

The suite should read content repos through their manifests, normalize learning objects, and preserve source attribution. Ingestion should be read-only until a task explicitly requires authoring support.

## 4. Adapt Teaching

Use the learner model, mastery evidence, prerequisites, and review history to choose the next explanation, practice item, quiz, project, or remediation.

## 5. Verify

Run:

```powershell
.\scripts\codex-verify.ps1
```

Report the command, exit code, and log path when verification fails.

## 6. Run the Learner UI Bridge Locally

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

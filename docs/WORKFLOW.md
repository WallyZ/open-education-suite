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

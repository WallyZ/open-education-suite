# CROSS_REPO_EXCHANGE

Cross-repo exchange rules for `open-education-suite`.

## Authority model

- `F:\dev\00-repo-kit` is the canonical source for reusable process, standards, lifecycle, memory, logging, lint, and exchange tooling.
- `open-education-suite` is canonical for the adaptive education platform core.
- Sibling `open-education-*` repos are canonical for subject content.
- `qa-live-test-system` is canonical for QA Live harness implementation; this repo owns only QA Live specs/contracts and runner scripts.

Exchange automation is proposal-first. It may catalog, compare, and report, but it must not silently apply, delete, overwrite, push, publish, or export private artifacts.

## Manifest

The local manifest is `.repo-kit/exchange.json` and is validated by `.repo-kit/exchange.schema.json`.

It records:

- imports from `00-repo-kit`,
- reusable export candidates from this repo,
- private/local exclusions,
- append-only ledger path.

## Privacy rules

Use the strictest reasonable classification:

- `public`: safe to share broadly.
- `internal`: useful in trusted private repos, but not public by default.
- `private`: repo or learner content that must not be exported by automation.
- `secret`: credentials, tokens, private keys, or any value requiring rotation if exposed.
- `local_only`: machine-specific state or generated local artifacts.

Only `public` or explicitly approved `internal` candidates may be proposed for upstream repo-kit reuse.

## Proposed reusable candidates

This repo can feed these patterns back to `00-repo-kit` after review:

- content-source registry and read-only sibling repo ingestion,
- essay-first assessment policy and deterministic assessment fixtures,
- learner UI QA Live contract shape,
- local-only learner-state privacy/audit patterns,
- teaching-quality and course-design quality gates.

Do not export subject course content, generated lectures, learner private data, local media, credentials, or reports containing private content.

## Commands

Check whether an exchange review is due:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\exchange\check_due.ps1 -RepoRoot . -RepoKitRoot F:\dev\00-repo-kit
```

Catalog local reusable candidates:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\exchange\catalog_repo.ps1 -RepoRoot .
```

Propose imports from repo-kit:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\exchange\propose_imports.ps1 -RepoRoot . -RepoKitRoot F:\dev\00-repo-kit
```

Propose exports back to repo-kit:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\exchange\propose_exports.ps1 -RepoRoot .
```

Check drift for tracked imports:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\exchange\check_drift.ps1 -RepoRoot . -RepoKitRoot F:\dev\00-repo-kit
```

Apply only after reviewing an approved proposal:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\exchange\apply_approved_exchange.ps1 -RepoRoot . -RepoKitRoot F:\dev\00-repo-kit -ProposalPath .\.repo-kit\proposals\import_proposal.json -ProposalType import -Execute -ApprovalToken APPROVED
```

## Drift status

- `current`: local copy matches recorded source hash.
- `missing`: tracked local target is absent.
- `stale`: repo-kit source hash differs from recorded source hash.
- `local_override`: local target differs and the manifest documents why.
- `rejected`: reviewed and intentionally not adopted or exported.

## Closeout

After an exchange wave:

- update `.repo-kit/exchange.json` only for reviewed imports/exports,
- update `memory-bank/solutionHarvest.md` for reusable patterns,
- update TODO evidence or follow-up TODOs,
- run `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex-verify.ps1`,
- commit and push to `main` unless a local workflow override says otherwise.

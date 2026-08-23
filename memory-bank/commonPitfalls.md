# Common Pitfalls

## Index

- Generic verifier replacement during standards sync.
- Subject content accidentally added to core platform repo.
- Manual UI checks used before QA Live capability review.

## Entries

### Replacing the verifier with generic standards checks

- Symptom: repo-kit sync drops education-suite-specific checks.
- Fix: extend `scripts/codex-verify.ps1` with shared lifecycle checks; do not replace platform checks.
- Verification: `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex-verify.ps1`.

### Treating subject content as core platform files

- Symptom: study plans/resources/generated lectures appear in this repo instead of sibling content repos.
- Fix: move subject content to the relevant `open-education-*` repo and keep `content-sources.json` pointing to it.
- Verification: the canonical verifier rejects domain study plans/resources in the core repo.

### Calling a manual UI check when QA Live can cover it

- Symptom: TODO evidence asks the user to click through UI behavior without checking QA Live capability first.
- Fix: add/update repo-owned `qa-live/` specs or adjacent QA Live capability, then run through the verifier or QA runner.

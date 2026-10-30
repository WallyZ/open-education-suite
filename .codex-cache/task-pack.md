# Restart-Safe Founder Private Authority

Objective: persist the same Founder scorer's signing authority, canonical
mastery and replay records under OES_FOUNDER_PRIVATE_AUTHORITY_001. Reuse the
existing source sequence, updater, UI import/verification and QA Live harness.

Relevant files: new private store; existing grader, bridge, test/QA preparer;
restart QA spec; canonical verifier; Founder UI message; .gitignore;
assessment documentation; TODO07; this task pack. Eleven files implement one
storage/restart/recovery vertical slice. No source curriculum changes.
Final changed-mode verification also requires refreshing six stale repo memory
surfaces (activeContext, progress, repoKitCatalog, solutionHarvest, context-pack,
HANDOFF); the total is seventeen files. Refresh current evidence and retire
obsolete Wave 47 status without altering runtime scope. The changed-mode gate
also requires regenerating stale ui/learner/session-data.js with its existing
exporter; eighteen files total, no new curriculum or source changes.
Broader changed mode then stops on two pre-existing Founder safeguarding links;
preserve that source work and report the limitation. Final verification repeats
founder-persistence after memory/catalog/documentation edits.

Verification:

```powershell
pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\codex-verify.ps1 -Mode founder-persistence
```

Private runtime authority: ignored .repo-kit-local/grading; encrypted to the
current Windows account with DPAPI, no plaintext fallback. QA uses isolated
stores under the run temp directory, distinct real bridge processes and fresh
browser contexts. Protected answers remain outside public/tutor projections.
Hash all pre-existing Founder work and preserve it byte-for-byte. Never reset
an existing corrupt/incompatible ledger to make verification pass. No external
service, real learner outcomes, portable key export or policy migration claim.

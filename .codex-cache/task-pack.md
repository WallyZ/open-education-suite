# Founder Independent Assessment

Objective: extend the same existing Founder forms with server scoring rather
than self-awarded marks under OES_FOUNDER_INDEPENDENT_001. Reuse Suite's
canonical mastery updater and existing UI/state/QA Live contracts.

Relevant files: grader adapter, grader checks/private QA preparer, learner bridge,
Founder UI module/index and app state integration, assessment QA template,
canonical verifier, TODO03, assessment documentation, and this task pack.
Eleven files are needed for one protected grader/state/UI/QA slice; no Founder
files or external service configuration is changed.

Verification:

```powershell
pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\codex-verify.ps1 -Mode founder-assessment
```

Hash all pre-existing Founder changes and keep them byte-for-byte unchanged.
Restricted keys are grader-only; correct QA inputs are generated privately in
the ignored run directory. No expected answers in tracked QA templates or tutor
context. Server receipts are bridge-session-scoped; restarted/forged receipts
cannot restore scoring authority. No real learner or external review claims.

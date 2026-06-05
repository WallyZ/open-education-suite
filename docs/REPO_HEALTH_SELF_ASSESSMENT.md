# REPO_HEALTH_SELF_ASSESSMENT

Repo health review for `open-education-suite` after adopting `00-repo-kit` standards.

## Scope

- Repo: `F:\dev\open-education-suite`
- Purpose: content-agnostic adaptive AI teaching platform core
- Canonical verifier: `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex-verify.ps1`
- Last reviewed: 2026-06-05

## Status legend

| Status | Meaning |
| --- | --- |
| Local evidence present | Repo-owned files or scripts satisfy the criterion locally. |
| Hosted confirmation required | GitHub-hosted settings or external services must be checked outside local files. |
| Owner decision required | A policy should not be guessed by automation. |
| Follow-up tracked | A TODO item exists for the gap. |

## Criteria mapping

| Area | Status | Evidence |
| --- | --- | --- |
| Project identity | Local evidence present | `README.md`, `USAGE.md`, `.codex-cache/task-pack.md`, `AGENTS.md` |
| Contribution guidance | Local evidence present | `CONTRIBUTING.md` |
| License | Local evidence present | `LICENSE` |
| Agent workflow | Local evidence present | `AGENTS.md`, `docs/AGENT_INSTRUCTIONS_COMPATIBILITY.md`, `memory-bank/` |
| Verification entrypoint | Local evidence present | `scripts/codex-verify.ps1` |
| TODO lifecycle | Local evidence present | `docs/TODO.md`, `docs/TODO_AUDIT.md`, `docs/TODO_PROCESS.md`, `docs/todo/*.md`, `scripts/lifecycle/` |
| Content boundaries | Local evidence present | `content-sources.json`, `scripts/ingestion/`, verifier checks for sibling content repos and no domain content in core repo |
| Learner state privacy | Local evidence present | `docs/learner-state-privacy.md`, `schemas/learner-state.schema.json`, `scripts/state/` |
| Assessment quality | Local evidence present | `docs/assessment-feedback.md`, `fixtures/assessment-items.json`, verifier essay-first policy checks |
| QA Live automation | Local evidence present | `qa-live/`, `scripts/testing/run-qa-live-learner-ui.ps1`, verifier QA Live learner workflow |
| Cross-repo exchange | Local evidence present | `.repo-kit/exchange.json`, `docs/CROSS_REPO_EXCHANGE.md`, `scripts/exchange/` |
| Logging and redaction | Local evidence present | `docs/LOGGING.md`, `scripts/logging/`, `docs/logging/` |
| Language lint matrix | Local evidence present | `repo-standards/lint/language_lint_matrix.json`, `scripts/lint/` |
| Security scanner profiles | Follow-up tracked | `docs/todo/00_repo_bootstrap.md` tracks review before enabling scanner profiles. |
| Hosted CI and branch protection | Owner decision required | No local branch-protection setting can prove hosted GitHub enforcement. Add workflow callers only if required. |

## Hosted checks not claimed locally

- GitHub branch protection and required status checks.
- GitHub security advisory settings.
- Hosted CI run history.
- OpenSSF Scorecard or external badge state.

Record hosted owner decisions in `docs/decisions.md` before treating them as enforced policy.

## Maintenance

Review this self-assessment when any of these change:

- content-source registry or sibling repo boundaries,
- learner-state privacy model,
- assessment policy,
- QA Live contracts,
- hosted workflow policy,
- repo-kit standards version or installer behavior.

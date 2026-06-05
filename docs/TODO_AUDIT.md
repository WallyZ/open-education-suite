# TODO_AUDIT

Canonical TODO formatting for this repo is implemented by the installed repo-kit audit tools:

- `python -m scripts.todo_audit.cli`
- `scripts/lifecycle/check_todo_format.py`
- `scripts/lifecycle/check_todo_ready_queue.py`

`docs/todo/*.md` is the primary backlog set. `docs/TODO.md` is the hub only.

## Canonical item contract

- Use Markdown checklist items with `- [ ]` and `- [x]`.
- Put the phase on the item line as `[PH1]`, `[PH2]`, or `[PH3]`; do not use heading-scoped phases for new items.
- Use the `ms:*` tag namespace in this repo.
- Completed items must include at least one auditable tag:
  - `<!-- ms:evidence id=... path=... symbols=... strings=... -->` for newly completed work.
  - `<!-- ms:id ... -->` is acceptable for historical completed items when detailed evidence predates this audit system.
- Open PH2/PH3 items must include `ms:meta` and the agent child sections required by `docs/TODO_PROCESS.md`.

## Commands

Lint one TODO file:

```powershell
python -m scripts.todo_audit.cli --todo docs/todo/00_repo_bootstrap.md --repo-root . --lint --lint-min-severity info --lint-fail-on error
```

Preview canonical repair:

```powershell
python -m scripts.todo_audit.cli --todo docs/todo/00_repo_bootstrap.md --repo-root . --repair --dry-run
```

Apply canonical repair with this repo's namespace:

```powershell
python -m scripts.todo_audit.cli --todo docs/todo/00_repo_bootstrap.md --repo-root . --repair --repair-namespace ms
```

Enforce every split TODO file:

```powershell
python scripts/lifecycle/check_todo_format.py --repo-root . --todo-root docs/todo --min-severity info --fail-on error
```

Build and validate the agent ready queue:

```powershell
python scripts/lifecycle/check_todo_ready_queue.py --repo-root . --todo-root docs/todo --min-severity info --fail-on error --report -
```

The canonical repo verifier runs both lifecycle checks:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex-verify.ps1
```

## Evidence style

Prefer evidence tags that point at real files and symbols:

```markdown
- [x] Wire TODO lifecycle checks through the canonical verifier [PH1] <!-- ms:evidence id=OES_TODO_LIFECYCLE_CHECKS_001 path=scripts/codex-verify.ps1 symbols=Test-TodoLifecycle,Invoke-PythonCheck strings="check_todo_format.py,check_todo_ready_queue.py" -->
  - Evidence (2026-06-05): Added verifier calls for TODO format and ready-queue validation before platform checks; verification passed with `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex-verify.ps1`.
```

Use stable ID names that are repo-specific and searchable, for example `OES_TODO_LIFECYCLE_CHECKS_001`.

## Historical completed items

Many education-suite TODO lanes were completed before strict audit tags existed. They are kept as completed when the repo has matching artifacts and verifier coverage, but repair adds stable `ms:id` tags so strict checks can track them. Do not replace a historical `ms:id` with an evidence tag unless you have verified the exact artifact and command.

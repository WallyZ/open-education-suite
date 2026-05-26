# AGENTS.md

## Mission
Minimize Codex usage, context growth, and command churn.
Make the smallest correct change that satisfies the task.

## Operating model
This file is evergreen repo guidance.
Task-specific instructions belong in `.codex-cache/task-pack.md`.

At the start of every task:
1. Read this file.
2. If present, read `.codex-cache/task-pack.md`.
3. From the task pack, identify the smallest relevant file set before doing any coding.
4. State the intended verification command before editing.
5. Keep scope narrow and avoid unrelated cleanup.

If `.codex-cache/task-pack.md` is missing, create a minimal working plan from the user request and the smallest relevant file set. Do not broaden scope just to compensate for missing task-pack data.

## Scope discipline
- Prefer the smallest safe patch over a refactor.
- Do not make incidental style, naming, formatting, dependency, or structural changes unless required for the task.
- Do not scan the whole repo if the task can be solved from the task pack, changed files, repo docs, or a small targeted search.
- If more than 3-5 files appear necessary, stop and justify why.
- If the task is ambiguous, preserve existing behavior and public interfaces unless the user explicitly asked for change.

## Shell and tool policy
Use PowerShell-native commands on Windows unless the user explicitly instructs otherwise or the repo already requires a different tool.

Do not use these by default:
- `rg`, `ripgrep`, `fd`
- `bash`, `sh`, `zsh`
- `sed`, `awk`, `xargs`, Unix `find`
- `curl`, `wget`
- `npx`, `npm exec`
- `winget`, `choco`, `scoop`
- `brew`, `apt`, `apt-get`, `yum`, `dnf`
- `Start-Process` for launching extra apps
- ad hoc `python -c` or `py -c` one-liners when a repo script or normal PowerShell command will do

Prefer:
- `Select-String` instead of `rg` / `grep`
- `Get-ChildItem` + `Where-Object` instead of `find`
- `Get-Content` instead of `cat`, `head`, `tail`
- built-in Git commands when repo search is specifically needed
- repo-checked PowerShell or Python scripts instead of shell one-liners
- existing repo scripts before inventing a new command

Do not install new tools, global packages, or dependencies unless the user explicitly asks.

## Search policy
Before using any search command:
1. Check `.codex-cache/task-pack.md`.
2. Check the repo root docs and the nearest relevant docs.
3. Search only the most likely directory.
4. Search the whole repo only if the narrow search failed.

When searching:
- start with exact filenames, symbols, or error strings
- avoid repeated exploratory searches that restate the same question
- do not open large unrelated files "just in case"

## Edit policy
- Preserve existing style unless the repo has a documented standard.
- Preserve public APIs, CLI behavior, file layout, and docs structure unless the task requires a change.
- Avoid broad renames or moves unless requested.
- Do not create new files when an existing file is the natural home, unless separation clearly improves maintainability and is in scope.

## Verification policy
Before editing, choose the narrowest verification command that proves the change.
After editing:
- run the narrowest relevant verification first
- expand verification only if the narrow check fails or the task affects broader behavior
- report exactly what was run and whether it passed

If no safe verification is available, say so explicitly and explain the smallest reasonable manual check.

## Escalation rules
Stop and ask for confirmation only if the task would require:
- installing tools or dependencies
- changing CI, deployment, secrets, credentials, or environment configuration
- deleting files, force pushes, or destructive Git operations
- changing more files than the task pack suggests without a clear reason

Otherwise, continue with the smallest safe interpretation.

## Output style
Be concise and practical.
List:
- files changed
- why they changed
- verification run
- any follow-up risk or limitation

Do not produce long repo summaries unless requested.

## Downstream repo inheritance
Child repos should inherit this file unchanged where possible.
Put repo-specific workflow details in the child repo root `AGENTS.md`.
Put sub-area overrides in nested `AGENTS.override.md` files only when necessary.
Keep task-specific handoff material out of `AGENTS.md`.

## Verification contract
Use exactly one repo entrypoint for automated verification:

- `.\scripts\codex-verify.ps1`

Do not run test runners directly unless the user explicitly asks:
- `pytest`
- `python -m pytest`
- `py -m pytest`
- `python -m unittest`
- `py -m unittest`
- `tox`
- `nox`
- `npm test`
- `pnpm test`
- `yarn test`

Verification rules:
- Always state the exact verification command before editing.
- Always use the repo verification entrypoint, not ad hoc test commands.
- Always stream stdout and stderr live to the console.
- Always stop on the first failure.
- Never hide output with `>$null`, `2>$null`, `Out-Null`, background jobs, or detached processes.
- Always preserve and report the real exit code.
- Always write a verification log under `.codex-cache\logs\`.
- On failure, report:
  - the exact command run
  - the exit code
  - the log file path

## Temporary file contract
Temporary files and folders may be created only under:

- `.codex-cache\tmp\<run-id>\`

Rules:
- Verification scripts must set `TEMP` and `TMP` to the run temp directory.
- Python bytecode caches should be redirected into the run temp directory when practical.
- Do not write temp artifacts elsewhere in the repo or under the user profile.
- Verification scripts must remove their run temp directory in a `finally` block unless the user explicitly asks to keep artifacts for debugging.

## Verification scope
Prefer the narrowest verification mode the repo supports:
- changed tests first
- targeted module/package next
- full suite only when needed

If the repo does not yet have `.\scripts\codex-verify.ps1`, create or update it before doing broader feature work.

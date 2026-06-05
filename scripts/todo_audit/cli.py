"""CLI entrypoint module for the TODO audit tool.

This file is the *implementation* behind the public wrapper `scripts/todo_audit.py`.

CONTRACT:
- Preserve CLI behavior and output.
- Keep imports stdlib-only.
"""

from __future__ import annotations

import argparse
import difflib
import json
import re
import sys
from pathlib import Path

from scripts.todo_audit.apply import _unique_backup_path, apply_plan_to_todo, write_plan_json
from scripts.todo_audit.detectors import _looks_like_path
from scripts.todo_audit.evidence import _normalize_hint_token, _split_list_value
from scripts.todo_audit.lint import compute_lint_exit_code, lint_and_format
from scripts.todo_audit.repair import render_repair_markdown, repair_phase_tags_text, repair_todo_text
from scripts.todo_audit.plan import DEFAULT_SUGGEST_IGNORE_GLOBS, build_plan_and_report_data
from scripts.todo_audit.report import render_how_to_tag_section, render_report_markdown
from scripts.todo_audit.repo_scan import RepoTextIndex
from scripts.todo_audit.scoring import compute_item_assessment
from scripts.todo_audit.todo_parse import TodoItem, parse_markdown_todos
from scripts.todo_audit.util import _dedupe_stable, _iso_utc_now, compute_stable_todo_id


DEFAULT_PLAN_PATH = Path("data/dev/todo_audit_plan.json")


def _infer_repo_root() -> Path:
    # scripts/todo_audit.py -> repo root is parent of scripts/
    return Path(__file__).resolve().parents[2]


def resolve_todo_path(todo_arg: str, repo_root: Path) -> Path:
    """Resolve a TODO markdown path in a repo-smart way.

    Accepts:
      - exact paths (absolute or relative)
      - old/renamed paths that no longer exist
      - basenames (e.g. 04_ideas_and_research.md)

    Resolution order:
      1) Path(todo_arg) exists and is a file
      2) (repo_root / todo_arg) exists and is a file
      3) Search docs/todo/, docs/TODO/, docs/ for *.md (in that order)
         - exact basename match (case-insensitive)
         - else fuzzy basename match via difflib.get_close_matches (limit 5)
    """

    raw = (todo_arg or "").strip()
    if not raw:
        print("ERROR: --todo must be a non-empty string", file=sys.stderr)
        raise SystemExit(2)

    direct = Path(raw)
    if direct.is_file():
        return direct.resolve()

    under_root = (repo_root / raw)
    if under_root.is_file():
        return under_root.resolve()

    basename = Path(raw).name
    if not basename:
        print(f"ERROR: invalid --todo value: {todo_arg!r}", file=sys.stderr)
        raise SystemExit(2)

    search_dirs = [
        repo_root / "docs" / "todo",
        repo_root / "docs" / "TODO",
        repo_root / "docs",
    ]

    candidates: list[Path] = []
    seen: set[str] = set()
    for d in search_dirs:
        if not d.exists() or not d.is_dir():
            continue
        for p in sorted(d.rglob("*.md")):
            if not p.is_file():
                continue
            key = str(p.resolve())
            if key in seen:
                continue
            seen.add(key)
            candidates.append(p.resolve())

    if not candidates:
        print(
            "ERROR: could not resolve --todo; no markdown files found under docs/",
            file=sys.stderr,
        )
        raise SystemExit(2)

    base_l = basename.lower()
    exact = [p for p in candidates if p.name.lower() == base_l]
    if len(exact) == 1:
        resolved = exact[0]
        print(f"Resolved TODO via search: {resolved.relative_to(repo_root).as_posix()}", file=sys.stderr)
        return resolved
    if len(exact) > 1:
        rels = sorted({p.relative_to(repo_root).as_posix() for p in exact})
        print(f"Ambiguous --todo {todo_arg!r}", file=sys.stderr)
        for r in rels:
            print(f"  - {r}", file=sys.stderr)
        print("Use --todo with an exact path, or use --todo-key XX", file=sys.stderr)
        raise SystemExit(2)

    # Fuzzy basename match (deterministic candidate list)
    name_to_paths: dict[str, list[Path]] = {}
    for p in candidates:
        name_to_paths.setdefault(p.name.lower(), []).append(p)
    possible_names = sorted(name_to_paths.keys())
    fuzzy_names = difflib.get_close_matches(base_l, possible_names, n=5)
    fuzzy_paths: list[Path] = []
    for nm in fuzzy_names:
        fuzzy_paths.extend(sorted(name_to_paths.get(nm, [])))

    if len(fuzzy_paths) == 1:
        resolved = fuzzy_paths[0]
        print(f"Resolved TODO via search: {resolved.relative_to(repo_root).as_posix()}", file=sys.stderr)
        return resolved
    if len(fuzzy_paths) > 1:
        rels = sorted({p.relative_to(repo_root).as_posix() for p in fuzzy_paths})
        print(f"Ambiguous --todo {todo_arg!r}", file=sys.stderr)
        for r in rels:
            print(f"  - {r}", file=sys.stderr)
        print("Use --todo with an exact path, or use --todo-key XX", file=sys.stderr)
        raise SystemExit(2)

    searched = ", ".join([d.relative_to(repo_root).as_posix() for d in search_dirs])
    print(f"ERROR: could not resolve --todo {todo_arg!r}", file=sys.stderr)
    print(f"Searched: {searched}", file=sys.stderr)
    print("Hint: Use --todo with an exact path, or use --todo-key XX", file=sys.stderr)
    raise SystemExit(2)


def resolve_todo_key(todo_key: str, repo_root: Path) -> Path:
    """Resolve a TODO markdown file by numeric key (e.g. 4 -> 04).

    Searches ONLY:
      - docs/todo/
      - docs/TODO/

    Match rules:
      1) basename starts with '{key}_' or '{key}-'
      2) else: basename token near start equals key (conservative)
    """

    raw = (todo_key or "").strip()
    if not raw:
        print("ERROR: --todo-key must be provided", file=sys.stderr)
        raise SystemExit(2)

    if not raw.isdigit():
        print(f"ERROR: --todo-key must be numeric (got {todo_key!r})", file=sys.stderr)
        raise SystemExit(2)

    key2 = f"{int(raw):02d}"
    key_int = str(int(raw))

    search_dirs = [repo_root / "docs" / "todo", repo_root / "docs" / "TODO"]

    candidates: list[Path] = []
    seen: set[str] = set()
    for d in search_dirs:
        if not d.exists() or not d.is_dir():
            continue
        for p in sorted(d.rglob("*.md")):
            if not p.is_file():
                continue
            rp = p.resolve()
            key = str(rp)
            if key in seen:
                continue
            seen.add(key)
            candidates.append(rp)

    # 1) Strict prefix match
    prefixes = (f"{key2}_", f"{key2}-")
    strict = [p for p in candidates if p.stem.lower().startswith(prefixes)]
    if len(strict) == 1:
        return strict[0]
    if len(strict) > 1:
        rels = sorted({p.relative_to(repo_root).as_posix() for p in strict})
        print(f"Ambiguous --todo-key {key2!r}", file=sys.stderr)
        for r in rels:
            print(f"  - {r}", file=sys.stderr)
        print("Use --todo with an exact path, or use --todo-key XX", file=sys.stderr)
        raise SystemExit(2)

    # 2) Conservative token near start
    acceptable = {key2, key_int}
    near_start: list[Path] = []
    for p in candidates:
        tokens = [t for t in re.split(r"[^0-9A-Za-z]+", p.stem) if t]
        if not tokens:
            continue
        for t in tokens[:3]:
            if t in acceptable:
                near_start.append(p)
                break

    if len(near_start) == 1:
        return near_start[0]
    if len(near_start) > 1:
        rels = sorted({p.relative_to(repo_root).as_posix() for p in near_start})
        print(f"Ambiguous --todo-key {key2!r}", file=sys.stderr)
        for r in rels:
            print(f"  - {r}", file=sys.stderr)
        print("Use --todo with an exact path, or use --todo-key XX", file=sys.stderr)
        raise SystemExit(2)

    dirs_s = ", ".join([d.relative_to(repo_root).as_posix() for d in search_dirs])
    print(f"No TODO file found for key {key2}", file=sys.stderr)
    print(f"Searched: {dirs_s}", file=sys.stderr)
    print("Hint: Use --todo with a path or basename", file=sys.stderr)
    raise SystemExit(2)



def _infer_repair_namespace(md_text: str, *, requested: str) -> str:
    req = (requested or "auto").strip().lower()
    if req in {"ms", "yta"}:
        return req

    ms_count = len(re.findall(r"<!--\s*ms:", md_text or "", flags=re.IGNORECASE))
    yta_count = len(re.findall(r"<!--\s*yta:", md_text or "", flags=re.IGNORECASE))
    if ms_count > yta_count:
        return "ms"
    return "yta"


def _write_repaired_todo(todo_path: Path, *, original_text: str, repaired_text: str) -> Path:
    newline = "\r\n" if "\r\n" in (original_text or "") else "\n"
    out = repaired_text or ""
    if out and not out.endswith("\n"):
        out += "\n"
    if (not out) and (original_text or "").endswith(("\n", "\r\n")):
        out = newline
    if newline == "\r\n":
        out = out.replace("\n", "\r\n")

    backup_path = _unique_backup_path(todo_path)
    backup_path.write_text(original_text, encoding="utf-8")
    todo_path.write_text(out, encoding="utf-8")
    return backup_path


def parse_args(argv: list[str]) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Audit a Markdown TODO checklist against the repo and generate a proposal plan (Phase 1)."
    )

    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("--todo", help="Path/basename/old path for the markdown TODO file to audit")
    g.add_argument(
        "--todo-key",
        dest="todo_key",
        help="Numeric TODO key (e.g. 4 or 04) to resolve under docs/todo/",
    )
    p.add_argument(
        "--repo-root",
        default=None,
        help="Repo root path (default: inferred from script location)",
    )
    p.add_argument(
        "--report",
        default=None,
        help="Write markdown report to this path (default: stdout). Use '-' for stdout.",
    )
    p.add_argument(
        "--plan",
        default=str(DEFAULT_PLAN_PATH.as_posix()),
        help=f"Write/read proposal plan JSON at this path (default: {DEFAULT_PLAN_PATH.as_posix()})",
    )

    mode = p.add_mutually_exclusive_group()
    mode.add_argument("--apply", action="store_true", help="Apply the plan to the TODO file")
    mode.add_argument(
        "--lint",
        action="store_true",
        help="Run non-destructive TODO quality lint checks (no plan/report generation)",
    )
    mode.add_argument(
        "--repair",
        action="store_true",
        help="Normalize TODO markdown into canonical format deterministically",
    )

    p.add_argument(
        "--lint-report",
        default="-",
        help="Write lint report to this path (default: '-'/stdout). Use '-' for stdout.",
    )
    p.add_argument(
        "--lint-format",
        choices=["md", "json"],
        default="md",
        help="Lint report format (default: md)",
    )
    p.add_argument(
        "--lint-min-severity",
        choices=["info", "warn", "error"],
        default="warn",
        help="Only emit lint issues at or above this severity (default: warn)",
    )
    p.add_argument(
        "--lint-fail-on",
        choices=["none", "warn", "error"],
        default="error",
        help="Exit non-zero when lint issues at/above threshold exist (default: error)",
    )
    p.add_argument(
        "--repair-report",
        default="-",
        help="Write repair preview/report to this path (default: '-'/stdout). Use '-' for stdout.",
    )
    p.add_argument(
        "--repair-namespace",
        choices=["auto", "ms", "yta"],
        default="auto",
        help="Namespace for generated repair tags when missing (default: auto infer)",
    )
    p.add_argument(
        "--repair-scope",
        choices=["all", "phase-tags"],
        default="all",
        help="Repair scope: full canonical repair or phase-heading to inline [PHn] conversion only.",
    )
    p.add_argument(
        "--yes",
        action="store_true",
        help="Non-interactive apply (only if --plan points to an existing plan)",
    )
    p.add_argument(
        "--yes-structure",
        action="store_true",
        help="Allow structural changes (move) when using --apply --yes",
    )
    p.add_argument(
        "--allow-actions",
        default=None,
        help=(
            "Comma-separated allowlist of actions for --apply --yes. "
            "Examples: 'check,uncheck' or 'check,uncheck,move,annotate,add'. "
            "If provided, this fully defines allowed actions."
        ),
    )
    p.add_argument(
        "--allow-adds",
        action="store_true",
        help=(
            "Explicitly allow applying 'add' actions (appending new TODO lines). "
            "Required even if --allow-actions includes 'add'."
        ),
    )
    p.add_argument(
        "--interactive",
        action="store_true",
        help="Confirm each change interactively (default when --apply is used without --yes)",
    )

    p.add_argument(
        "--min-confidence",
        type=int,
        default=70,
        help="Only propose 'mark complete' above this confidence threshold (0..100)",
    )
    p.add_argument(
        "--max-items",
        type=int,
        default=None,
        help="Cap number of suggestions in the plan (and recommendations shown in report)",
    )
    p.add_argument(
        "--include-unknown",
        action="store_true",
        help="Include unclear items in the report",
    )
    p.add_argument(
        "--suggest-additions",
        dest="suggest_additions",
        action="store_true",
        help=(
            "Include conservative 'add' suggestions for existing artifacts not referenced in the TODO. "
            "OFF by default to prevent noisy common-file suggestions."
        ),
    )
    p.add_argument(
        "--no-recommend-adds",
        action="store_true",
        help=(
            "Disable all 'add completed item' recommendations (even if --suggest-additions is set)."
        ),
    )

    p.add_argument(
        "--recommend-deny-glob",
        dest="recommend_deny_glob",
        action="append",
        default=None,
        help=(
            "Glob to deny for 'add completed item' recommendations (repeatable). "
            "Allow-glob beats deny."
        ),
    )
    p.add_argument(
        "--recommend-allow-glob",
        dest="recommend_allow_glob",
        action="append",
        default=None,
        help=(
            "Glob to allow for 'add completed item' recommendations (repeatable). "
            "Allow beats deny."
        ),
    )
    # Optional override for ignore patterns used ONLY during suggestion scanning.
    # If omitted, defaults are used.
    p.add_argument(
        "--ignore-glob",
        dest="ignore_glob",
        action="append",
        default=None,
        help=(
            "DEPRECATED alias for --recommend-deny-glob. "
            "Only affects --suggest-additions; does not change evidence checks."
        ),
    )
    # Back-compat alias (hidden)
    p.add_argument(
        "--recommend-additions",
        dest="suggest_additions",
        action="store_true",
        help=argparse.SUPPRESS,
    )
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="Never write changes even if --apply/--repair is set (still show what would happen)",
    )

    return p.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)

    if args.yes and not args.apply:
        print("ERROR: --yes requires --apply", file=sys.stderr)
        return 2

    if sum(1 for flag in [args.apply, args.lint, args.repair] if flag) > 1:
        # Should be prevented by argparse mutual exclusion; keep a defensive check.
        print("ERROR: --lint/--repair are mutually exclusive with --apply", file=sys.stderr)
        return 2

    if args.min_confidence < 0 or args.min_confidence > 100:
        print("ERROR: --min-confidence must be 0..100", file=sys.stderr)
        return 2

    if args.max_items is not None and args.max_items <= 0:
        print("ERROR: --max-items must be a positive integer", file=sys.stderr)
        return 2

    repo_root = Path(args.repo_root) if args.repo_root else _infer_repo_root()
    repo_root = repo_root.resolve()
    if not repo_root.exists():
        print(f"ERROR: --repo-root does not exist: {repo_root}", file=sys.stderr)
        return 2

    # Resolve TODO path after repo_root is known (do not rely on CWD).
    if args.todo_key:
        todo_path = resolve_todo_key(args.todo_key, repo_root)
    else:
        todo_path = resolve_todo_path(args.todo, repo_root)
    if not todo_path.is_file():
        print(f"ERROR: resolved TODO path is not a file: {todo_path}", file=sys.stderr)
        return 2

    report_to_stdout = (args.report is None) or (args.report == "-")
    report_path = None
    if not report_to_stdout:
        report_path = Path(args.report)
        if not report_path.is_absolute():
            report_path = (repo_root / report_path).resolve()

    plan_path = Path(args.plan)
    if not plan_path.is_absolute():
        plan_path = (repo_root / plan_path).resolve()

    todo_text = todo_path.read_text(encoding="utf-8", errors="replace")

    if args.lint:
        lint_to_stdout = (args.lint_report is None) or (args.lint_report == "-")
        lint_path = None
        if not lint_to_stdout:
            lint_path = Path(args.lint_report)
            if not lint_path.is_absolute():
                lint_path = (repo_root / lint_path).resolve()

        issues, rendered = lint_and_format(
            todo_text,
            todo_path=todo_path,
            fmt=args.lint_format,
            min_severity=args.lint_min_severity,
        )

        if lint_to_stdout:
            sys.stdout.write(rendered)
        else:
            assert lint_path is not None
            lint_path.parent.mkdir(parents=True, exist_ok=True)
            lint_path.write_text(rendered, encoding="utf-8")
            print(f"Wrote lint report: {lint_path}")

        return compute_lint_exit_code(issues, fail_on=args.lint_fail_on)

    if args.repair:
        repair_to_stdout = (args.repair_report is None) or (args.repair_report == "-")
        repair_path = None
        if not repair_to_stdout:
            repair_path = Path(args.repair_report)
            if not repair_path.is_absolute():
                repair_path = (repo_root / repair_path).resolve()

        if args.repair_scope == "phase-tags":
            repaired_text, actions = repair_phase_tags_text(todo_text, top_level_only=True)
        else:
            default_ns = _infer_repair_namespace(todo_text, requested=args.repair_namespace)
            repaired_text, actions = repair_todo_text(todo_text, default_namespace=default_ns)
        rendered = render_repair_markdown(actions, todo_path=todo_path, dry_run=args.dry_run)

        if repair_to_stdout:
            sys.stdout.write(rendered)
        else:
            assert repair_path is not None
            repair_path.parent.mkdir(parents=True, exist_ok=True)
            repair_path.write_text(rendered, encoding="utf-8")
            print(f"Wrote repair report: {repair_path}")

        if args.dry_run:
            return 0

        if not actions:
            print("No repair changes written; file is already canonical.")
            return 0

        backup_path = _write_repaired_todo(
            todo_path,
            original_text=todo_text,
            repaired_text=repaired_text,
        )
        print(f"Wrote repaired TODO: {todo_path}")
        print(f"Backup saved: {backup_path}")
        print(f"Changes applied: {len(actions)}.")
        return 0

    generated_at = _iso_utc_now()

    # NOTE: deny/allow globs only affect "add recommendation" scanning; they must not affect
    # evidence checks for explicit TODO items.
    recommend_deny_globs: list[str] = []
    for x in (args.recommend_deny_glob or []) + (args.ignore_glob or []):
        g = _normalize_hint_token(x).replace("\\", "/")
        if g:
            recommend_deny_globs.append(g)
    recommend_deny_globs = _dedupe_stable([g for g in recommend_deny_globs if (g or "").strip()])

    recommend_allow_globs: list[str] = []
    for x in args.recommend_allow_glob or []:
        g = _normalize_hint_token(x).replace("\\", "/")
        if g:
            recommend_allow_globs.append(g)
    recommend_allow_globs = _dedupe_stable([g for g in recommend_allow_globs if (g or "").strip()])

    generated_plan, report_data = build_plan_and_report_data(
        todo_path=todo_path,
        repo_root=repo_root,
        md_text=todo_text,
        min_confidence=args.min_confidence,
        include_unknown=args.include_unknown,
        max_items=args.max_items,
        suggest_additions=bool(args.suggest_additions),
        suggest_ignore_globs=recommend_deny_globs,
        recommend_allow_globs=recommend_allow_globs,
        recommend_adds_enabled=(not bool(args.no_recommend_adds)),
        generated_at=generated_at,
    )

    report_md = render_report_markdown(todo_path=todo_path, repo_root=repo_root, report_data=report_data)
    if report_to_stdout:
        sys.stdout.write(report_md)
        sys.stdout.write(render_how_to_tag_section())
    else:
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(report_md, encoding="utf-8")
        print(f"Wrote report: {report_path}")

    # Plan behavior:
    # - If --apply and plan exists: load and use it (do not overwrite).
    # - If not --apply: do NOT overwrite an existing plan (keeps the tool read-only by default).
    # - Otherwise: write a freshly generated plan.
    plan_to_use = generated_plan
    plan_was_loaded = False

    if args.apply and plan_path.exists():
        try:
            plan_to_use = json.loads(plan_path.read_text(encoding="utf-8"))
            plan_was_loaded = True
        except Exception as e:
            print(f"ERROR: failed to read plan JSON: {plan_path}: {e}", file=sys.stderr)
            return 2
    elif (not args.apply) and plan_path.exists():
        # Report-only runs should not churn plan files.
        pass
    else:
        write_plan_json(generated_plan, plan_path)
        print(f"Wrote plan: {plan_path}")

    if not args.apply:
        return 0

    # Add actions always require explicit opt-in; this applies to both interactive and --yes.
    if not args.allow_adds:
        plan_has_add = any(
            (it.get("action") or "").strip().lower() == "add" for it in (plan_to_use.get("items") or [])
        )
        if plan_has_add:
            print(
                "ERROR: refusing to apply plan; plan contains 'add' actions but --allow-adds was not provided.\n"
                "This prevents accidental growth/noise in TODO markdown.",
                file=sys.stderr,
            )
            return 2

    # Apply safety rules:
    # - --yes requires an existing plan file.
    if args.yes and not plan_was_loaded:
        print(
            "ERROR: --yes requires an existing plan file at --plan.\n"
            "Run once without --yes to generate a plan, then re-run with --apply --yes.",
            file=sys.stderr,
        )
        return 2

    # Apply safety gate (ALL apply modes):
    # - --allow-actions (if provided) is the source of truth
    # - else: --yes-structure allows check/uncheck/move
    # - else: check/uncheck only
    # NOTE: annotate is report-only (no file edits), but we still recognize it in plans so we can
    # fail closed unless the user explicitly allows it via --allow-actions.
    known_actions = {"check", "uncheck", "move", "annotate", "add"}

    # Collect all actions present in plan (including unknown ones, for clear diagnostics)
    plan_actions_all: set[str] = set()
    plan_actions_known: set[str] = set()
    for it in (plan_to_use.get("items") or []):
        a = (it.get("action") or "").strip().lower()
        if not a:
            continue
        plan_actions_all.add(a)
        if a in known_actions:
            plan_actions_known.add(a)
    unknown_in_plan = sorted(a for a in plan_actions_all if a not in known_actions)

    if unknown_in_plan:
        present_s = ", ".join(sorted(plan_actions_all))
        unknown_s = ", ".join(unknown_in_plan)
        print(
            "ERROR: refusing to apply plan; plan contains unknown actions that this tool does not understand.\n"
            f"Present actions: {present_s}\n"
            f"Unknown actions: {unknown_s}\n"
            "Fix the plan or upgrade the tool.",
            file=sys.stderr,
        )
        return 2

    # Safety gate: ONLY enforced for non-interactive `--apply --yes` flows.
    # Interactive apply already requires per-action confirmation.
    if args.yes:
        allow_actions_raw = (args.allow_actions or "").strip()
        if allow_actions_raw:
            allowed_actions = {a.strip().lower() for a in _split_list_value(allow_actions_raw) if a.strip()}
            invalid = sorted(allowed_actions - known_actions)
            if invalid:
                print(
                    "ERROR: --allow-actions contained unknown actions: " + ", ".join(invalid),
                    file=sys.stderr,
                )
                print("Allowed actions are: check, uncheck, move, annotate, add", file=sys.stderr)
                return 2
            if not allowed_actions:
                print("ERROR: --allow-actions must not be empty", file=sys.stderr)
                return 2
        else:
            # Default allowlist for `--apply --yes`:
            # - `--yes-structure` adds move
            # - NOTE: `add` is never allowed by default; it must be explicitly opted into.
            allowed_actions = {"check", "uncheck"}
            if args.yes_structure:
                allowed_actions |= {"move"}

        if ("add" in allowed_actions) and (not args.allow_adds):
            print(
                "ERROR: refusing to apply plan; 'add' requires BOTH --allow-actions add AND --allow-adds.\n"
                "Re-run with --allow-adds if you truly want to append new TODO lines.",
                file=sys.stderr,
            )
            return 2

        disallowed = sorted(a for a in plan_actions_known if a not in allowed_actions)
        if disallowed:
            present_s = ", ".join(sorted(plan_actions_all)) if plan_actions_all else "(none)"
            allowed_s = ", ".join(sorted(allowed_actions))
            disallowed_s = ", ".join(disallowed)
            print(
                "ERROR: refusing to apply plan; plan contains disallowed actions under the current safety gates.\n"
                f"Present actions: {present_s}\n"
                f"Allowed actions: {allowed_s}\n"
                f"Disallowed actions: {disallowed_s}\n\n"
                "How to proceed:\n"
                "  - For move actions: re-run with --yes-structure\n"
                "  - To allow add actions safely: pass --allow-actions add,...\n"
                "  - To *generate* add actions: re-run the audit with --suggest-additions",
                file=sys.stderr,
            )
            return 2

    # If we generated a plan this run (no plan existed), require a one-time gate prompt
    # before doing per-action prompts.
    if (not plan_was_loaded) and (not args.yes):
        ans = input("Plan was generated this run. Proceed to apply it to the TODO file? [y/N]: ").strip().lower()
        if ans not in {"y", "yes"}:
            print("Apply cancelled.")
            return 0

    # Default interactive when --apply is used without --yes.
    interactive = args.interactive or (args.apply and not args.yes)

    _ = apply_plan_to_todo(
        todo_path=todo_path,
        plan=plan_to_use,
        interactive=interactive,
        yes=args.yes,
        dry_run=args.dry_run,
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

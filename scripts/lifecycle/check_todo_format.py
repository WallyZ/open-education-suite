#!/usr/bin/env python3
"""check_todo_format.py

Run canonical TODO-format lint checks across `docs/todo/*.md` (excluding `_archive` by default).
This is a repo-level enforcer built on top of `scripts/todo_audit` lint rules.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


# Ensure repo imports work when this script is executed directly.
_REPO_ROOT_BOOTSTRAP = Path(__file__).resolve().parents[2]
for _p in (_REPO_ROOT_BOOTSTRAP, _REPO_ROOT_BOOTSTRAP / "scripts"):
    _s = str(_p)
    if _s not in sys.path:
        sys.path.insert(0, _s)

from scripts.todo_audit.lint import lint_todo, summarize_issues  # noqa: E402


_SEVERITY_RANK = {"info": 0, "warn": 1, "error": 2}


def _iter_todo_files(todo_root: Path, *, include_archive: bool) -> list[Path]:
    files: list[Path] = []
    for p in sorted(todo_root.rglob("*.md")):
        if not p.is_file():
            continue
        rel = p.relative_to(todo_root).as_posix()
        if (not include_archive) and rel.startswith("_archive/"):
            continue
        files.append(p)
    return files


def _filter_min_severity(issues, *, min_severity: str):
    min_rank = _SEVERITY_RANK[min_severity]
    return [it for it in issues if _SEVERITY_RANK[it.severity] >= min_rank]


def _filter_fail_threshold(issues, *, fail_on: str):
    if fail_on == "none":
        return []
    threshold = "warn" if fail_on == "warn" else "error"
    min_rank = _SEVERITY_RANK[threshold]
    return [it for it in issues if _SEVERITY_RANK[it.severity] >= min_rank]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo-root", default=".")
    ap.add_argument("--todo-root", default="docs/todo")
    ap.add_argument("--min-severity", choices=["info", "warn", "error"], default="info")
    ap.add_argument("--fail-on", choices=["none", "warn", "error"], default="error")
    ap.add_argument("--include-archive", action="store_true")
    args = ap.parse_args()

    repo_root = Path(args.repo_root).resolve()
    todo_root = Path(args.todo_root)
    if not todo_root.is_absolute():
        todo_root = (repo_root / todo_root).resolve()

    if not todo_root.exists() or not todo_root.is_dir():
        print(f"ERROR: todo root not found: {todo_root}")
        return 2

    files = _iter_todo_files(todo_root, include_archive=bool(args.include_archive))
    if not files:
        print(f"No TODO markdown files found under: {todo_root}")
        return 0

    totals = {"error": 0, "warn": 0, "info": 0}
    failing: list[tuple[Path, list]] = []

    print(f"TODO format scan root: {todo_root}")
    print(f"Files scanned: {len(files)}")

    for f in files:
        text = f.read_text(encoding="utf-8", errors="replace")
        issues_all = lint_todo(text, path=f)
        issues = _filter_min_severity(issues_all, min_severity=args.min_severity)
        counts = summarize_issues(issues)
        for k in totals:
            totals[k] += int(counts.get(k, 0))

        rel = f.relative_to(repo_root).as_posix() if f.is_relative_to(repo_root) else f.as_posix()
        print(
            f"- {rel}: errors={counts.get('error', 0)} warns={counts.get('warn', 0)} infos={counts.get('info', 0)}"
        )

        fail_issues = _filter_fail_threshold(issues, fail_on=args.fail_on)
        if fail_issues:
            failing.append((f, fail_issues))

    print(
        "Totals: "
        f"errors={totals.get('error', 0)} "
        f"warns={totals.get('warn', 0)} "
        f"infos={totals.get('info', 0)}"
    )

    if failing:
        print("")
        print(f"FAIL: TODO format issues met fail threshold ({args.fail_on}).")
        for f, issues in failing:
            rel = f.relative_to(repo_root).as_posix() if f.is_relative_to(repo_root) else f.as_posix()
            print(f"- {rel}")
            for it in issues[:8]:
                print(f"  L{it.line} {it.severity.upper()} {it.code}: {it.message}")
            if len(issues) > 8:
                print(f"  ... ({len(issues) - 8} more)")
        return 1

    print("TODO format checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

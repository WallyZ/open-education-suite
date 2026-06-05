"""Internal package for the TODO audit script.

This package exists to split the original `scripts/todo_audit.py` monolith into
small modules while keeping `python scripts/todo_audit.py ...` working as the
public entry point.
"""

from __future__ import annotations

# Re-export key public-ish symbols for back-compat (tests import from the top-level wrapper,
# which delegates to scripts.todo_audit.cli).
from scripts.todo_audit.apply import apply_plan_to_todo, write_plan_json
from scripts.todo_audit.plan import (
    DEFAULT_SUGGEST_IGNORE_GLOBS,
    build_plan_and_report_data,
)
from scripts.todo_audit.repo_scan import RepoTextIndex
from scripts.todo_audit.scoring import compute_item_assessment
from scripts.todo_audit.todo_parse import TodoItem, parse_markdown_todos
from scripts.todo_audit.util import compute_stable_todo_id

__all__ = [
    "DEFAULT_SUGGEST_IGNORE_GLOBS",
    "RepoTextIndex",
    "TodoItem",
    "apply_plan_to_todo",
    "build_plan_and_report_data",
    "compute_item_assessment",
    "compute_stable_todo_id",
    "parse_markdown_todos",
    "write_plan_json",
]

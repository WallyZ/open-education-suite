"""Shared helpers for the TODO audit tool.

Keep this small and dependency-free (stdlib only).
"""

from __future__ import annotations

import datetime as _dt
import hashlib
import re
from pathlib import Path


TEMPLATE_PLACEHOLDER_RE = re.compile(r"<[^>]+>")


def _iso_utc_now() -> str:
    return (
        _dt.datetime.now(tz=_dt.timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z")
    )


def _safe_relpath(path: Path, repo_root: Path) -> str:
    try:
        return path.resolve().relative_to(repo_root.resolve()).as_posix()
    except Exception:
        return path.as_posix()


def _stable_id(*parts: str) -> str:
    h = hashlib.sha1("|".join(parts).encode("utf-8", errors="replace")).hexdigest()
    return h[:12]


def compute_stable_todo_id(todo_text: str) -> str:
    """Compute a stable ID for a TODO item.

    Must not depend on line numbers or headings so that moves remain deterministic.
    """

    normalized = re.sub(r"\s+", " ", todo_text.strip())
    return _stable_id("yta:todo", normalized)


def _truncate(s: str, max_len: int) -> str:
    if len(s) <= max_len:
        return s
    return s[: max(0, max_len - 1)] + "…"


def _dedupe_stable(seq: list[str]) -> list[str]:
    out: list[str] = []
    seen = set()
    for x in seq:
        if x in seen:
            continue
        seen.add(x)
        out.append(x)
    return out

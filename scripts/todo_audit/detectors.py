"""Detectors and token extraction helpers for the TODO audit tool.

This module contains the small regex-based detectors used by scoring and planning:
- path/filename heuristics
- weak evidence token extraction from TODO text
- dict-key / field pattern detection

Stdlib only.
"""

from __future__ import annotations

import re
from pathlib import Path

from scripts.todo_audit.evidence import _normalize_hint_token
from scripts.todo_audit.repo_scan import ALLOWED_TEXT_EXTS
from scripts.todo_audit.util import _dedupe_stable


# Evidence filename extensions that we treat as "bare filename" references.
# (These are the ones we will resolve against a section base path from headings.)
EVIDENCE_FILENAME_EXTS = {
    ".py",
    ".md",
    ".toml",
    ".json",
    ".jsonl",
    ".yml",
    ".yaml",
}


def _looks_like_path(token: str) -> bool:
    # Avoid treating descriptive phrases like "views, length/duration" as paths.
    # (Heuristic: if it contains whitespace, it's not a path hint.)
    if re.search(r"\s", token):
        return False
    if "://" in token:
        return False
    if re.match(r"^[A-Za-z]:/", token):
        return True
    if "/" in token or "\\" in token:
        return True
    lower = token.lower()
    for ext in (
        ".py",
        ".md",
        ".toml",
        ".yaml",
        ".yml",
        ".json",
        ".jsonl",
        ".ps1",
        ".ts",
        ".tsx",
        ".js",
        ".txt",
    ):
        if lower.endswith(ext):
            return True
    return False


def _looks_like_filename(token: str) -> bool:
    """True for bare filenames like 'foo.py' (no slashes) that we can try to resolve."""

    if not token:
        return False
    if "/" in token or "\\" in token:
        return False
    # Treat any bare token with a real suffix (e.g. foo.ts, bar.md) as a filename.
    # NOTE: Path(".venv").suffix == "" so dot-directories aren't misclassified.
    try:
        if Path(token).suffix:
            return True
    except Exception:
        pass

    lower = token.lower()
    return any(lower.endswith(ext) for ext in EVIDENCE_FILENAME_EXTS)


def extract_hints(item_text: str) -> dict:
    """Extract simple hints from TODO item text.

    Returns:
        {"paths": [...], "symbols": [...], "commands": [...]}
    """

    paths: list[str] = []
    symbols: list[str] = []
    commands: list[str] = []

    # Backticks are the highest-signal hint container.
    for m in re.finditer(r"`([^`]+)`", item_text):
        token = _normalize_hint_token(m.group(1) or "")
        if not token:
            continue
        if _looks_like_path(token):
            paths.append(token)
        else:
            if " " in token:
                commands.append(token)
            else:
                if re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", token):
                    symbols.append(token)

    # Parentheses hints, e.g. (.../file.py)
    for m in re.finditer(r"\(([^)]+)\)", item_text):
        token = _normalize_hint_token(m.group(1) or "")
        if token and _looks_like_path(token):
            paths.append(token)

    # “def foo” / “class Foo” patterns.
    for m in re.finditer(r"\bdef\s+([A-Za-z_][A-Za-z0-9_]*)\b", item_text):
        symbols.append(m.group(1))
    for m in re.finditer(r"\bclass\s+([A-Za-z_][A-Za-z0-9_]*)\b", item_text):
        symbols.append(m.group(1))

    # Plain-text filename/path tokens.
    # This is intentionally conservative; it exists mainly to capture bare '*.py' filenames
    # that are scoped by a section base path in the heading.
    for m in re.finditer(r"\b[A-Za-z0-9_][A-Za-z0-9_.-]*\.py\b", item_text):
        token = _normalize_hint_token(m.group(0) or "")
        if token and _looks_like_filename(token):
            paths.append(token)

    # Plain-text relative paths (contains / or \\ and ends with .py)
    for m in re.finditer(r"\b[\w.-]+(?:[\\/][\w.-]+)+\.py\b", item_text):
        token = _normalize_hint_token(m.group(0) or "")
        if token and _looks_like_path(token):
            paths.append(token)

    return {
        "paths": _dedupe_stable(paths),
        "symbols": _dedupe_stable(symbols),
        "commands": _dedupe_stable(commands),
    }


def _extract_implicit_evidence_tokens(item_text: str, *, max_tokens: int = 5) -> dict:
    """Extract conservative, code-ish evidence tokens from free-form TODO text.

    RATIONALE:
    - Many TODOs reference dataclass fields / JSON keys / API fields (not def/class symbols).
    - When no explicit `yta:evidence` is present, we still want *some* deterministic signals,
      but we must avoid turning generic prose into noisy evidence.

    Returns:
        {
          "identifiers": ["priority_score", "trend_signals"],
          "strings": ["videos.list", "contentDetails", "--channel"],
        }

    Notes:
    - Identifiers are strict Python identifiers.
    - "strings" are code-ish tokens that aren't identifiers (flags, dotted tokens, etc.).
    - All tokens are treated as WEAK evidence (confidence ceiling handled in assessment).
    """

    text = (item_text or "").strip()
    if not text:
        return {"identifiers": [], "strings": []}

    stop = {
        # very common TODO words
        "todo",
        "tbd",
        "wip",
        "note",
        "fix",
        "add",
        "remove",
        "refactor",
        "rename",
        "update",
        "create",
        "implement",
        "support",
        "handle",
        "ensure",
        "make",
        "improve",
        "cleanup",
        "extract",
        "basic",
        "metadata",
        "use",
        "from",
        "into",
        "with",
        "for",
        "and",
        "or",
        "the",
        "a",
        "an",
    }

    raw_tokens: list[str] = []

    def add_token(t: str) -> None:
        tt = (t or "").strip().strip("\"'")
        tt = tt.strip("()[]{}<>")
        if not tt:
            return
        if _looks_like_path(tt):
            return
        if tt.lower() in stop:
            return
        raw_tokens.append(tt)

    # Backticks are still the highest-signal container.
    for m in re.finditer(r"`([^`]+)`", text):
        add_token(m.group(1) or "")

    # Dotted tokens (API methods, namespaces)
    # Supports multi-segment paths like: youtube_automation.ideas.store.add_or_update_idea
    for m in re.finditer(
        r"\b[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)+\b", text
    ):
        add_token(m.group(0) or "")

    # Slash-separated tokens like statistics/contentDetails
    for m in re.finditer(r"\b[A-Za-z][A-Za-z0-9_]*(?:/[A-Za-z][A-Za-z0-9_]*)+\b", text):
        for part in (m.group(0) or "").split("/"):
            add_token(part)

    # CLI flags
    for m in re.finditer(r"\b--[A-Za-z0-9][A-Za-z0-9_-]*\b", text):
        add_token(m.group(0) or "")

    # CLI subcommand patterns like: ideas pick-next
    # (Conservative: require a hyphen in the subcommand token to reduce prose noise.)
    for m in re.finditer(
        r"\b([a-z][a-z0-9_-]{2,})\s+([a-z][a-z0-9_-]*-[a-z0-9_-]*)\b", text
    ):
        add_token((m.group(1) or "") + " " + (m.group(2) or ""))

    # Underscore identifiers (high signal for fields/keys)
    for m in re.finditer(r"\b[A-Za-z_][A-Za-z0-9_]*_[A-Za-z0-9_]+\b", text):
        add_token(m.group(0) or "")

    # CamelCase-ish (e.g. contentDetails)
    for m in re.finditer(r"\b[A-Za-z][A-Za-z0-9]*[A-Z][A-Za-z0-9]*\b", text):
        add_token(m.group(0) or "")

    raw_tokens = _dedupe_stable(raw_tokens)

    identifiers: list[str] = []
    strings: list[str] = []

    for t in raw_tokens:
        if len(identifiers) + len(strings) >= max(1, int(max_tokens)):
            break

        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", t):
            # Only treat as an implicit identifier if it looks code-ish.
            # (Underscore or CamelCase are both high-signal patterns.)
            looks_codeish = ("_" in t) or bool(re.search(r"[A-Z]", t))
            if looks_codeish:
                identifiers.append(t)
        else:
            # Dotted tokens, flags, etc.
            strings.append(t)

    return {
        "identifiers": _dedupe_stable(identifiers)[: max(1, int(max_tokens))],
        "strings": _dedupe_stable(strings)[: max(1, int(max_tokens))],
    }


def _extract_context_base_dir(section_path: list[str]) -> str | None:
    """Extract a context base dir from the nearest heading that carries a backticked path.

    Example heading:
      "4.1 Idea sources (`youtube_automation/ideas/sources/)`"

    CONTRACT:
    - This is used only for heuristic resolution of *bare filenames* inside a section.
    - It must never write back into the TODO; it only influences evidence checks.
    """

    def iter_heading_path_tokens(heading: str) -> list[str]:
        tokens: list[str] = []
        for m in re.finditer(r"`([^`]+)`", heading or ""):
            tokens.append(m.group(1) or "")
        # Also support parenthetical section base paths, e.g. "(youtube_automation/ideas/sources/)".
        for m in re.finditer(r"\(([^)]+)\)", heading or ""):
            tokens.append(m.group(1) or "")
        return tokens

    for h in reversed(section_path or []):
        for raw in iter_heading_path_tokens(h):
            token = _normalize_hint_token(raw)
            if not token:
                continue
            if not _looks_like_path(token):
                continue

            token = token.replace("\\", "/")
            # If a heading points at a concrete file, treat its parent directory as the context.
            if "/" in token and not token.endswith("/"):
                lower = token.lower()
                if any(lower.endswith(ext) for ext in ALLOWED_TEXT_EXTS) or lower.endswith(".py"):
                    parent = Path(token).parent.as_posix().strip("/")
                    return parent + "/" if parent else None

            # Directory-like path (or a non-file path): use as-is.
            token = token.rstrip("/")
            return token + "/" if token else None

    return None


def _file_contains_any_field_patterns(text: str, field_name: str) -> bool:
    """Return True if text likely references a dataclass/pydantic-ish field.

    Patterns (conservative):
    - typed declaration: `name: Type` or `name: Type = ...`
    - dataclasses: `name = field(...)`
    - attribute access: `self.name` or `obj.name` (requires a real identifier)
    """

    if not text or not field_name:
        return False
    esc = re.escape(field_name)
    pats = [
        # Typed fields (dataclasses/pydantic/attrs style): `name: Type` / `name: Type = ...`
        re.compile(rf"(?m)^\s*{esc}\s*:\s*[^#\n]+$"),
        re.compile(rf"(?m)^\s*{esc}\s*:\s*[^#\n]+?\s*=\s*[^#\n]+$"),
        # dataclasses.field(...) style
        re.compile(rf"(?m)^\s*{esc}\s*=\s*field\s*\("),
        # Simple assignments (constants/config defaults/enum members): `NAME = ...`
        re.compile(rf"(?m)^\s*{esc}\s*=\s*[^#\n]+$"),
        re.compile(rf"(?m)^\s*{esc}\s*=\s*[^#\n]+?\s*#.*$"),
        # Attribute access
        re.compile(rf"\bself\.{esc}\b"),
        # `obj.field_name` / `.field_name` but with an explicit identifier.
        re.compile(rf"\b[A-Za-z_][A-Za-z0-9_]*\.{esc}\b"),
    ]
    return any(p.search(text) for p in pats)


def _file_contains_any_key_patterns(text: str, key_name: str) -> bool:
    """Return True if text likely references a dict/JSON key.

    Patterns:
    - dict literals / JSON: `"key":`, `'key':`
    - indexing: `["key"]`, `['key']`
    - `.get("key")` / `.get('key')`
    """

    if not text or not key_name:
        return False
    esc = re.escape(key_name)
    pats = [
        re.compile(rf"\[\s*\"{esc}\"\s*\]"),
        re.compile(rf"\[\s*'{esc}'\s*\]"),
        re.compile(rf"\"{esc}\"\s*:", flags=re.MULTILINE),
        re.compile(rf"'{esc}'\s*:", flags=re.MULTILINE),
        re.compile(rf"\.get\(\s*\"{esc}\"\s*[,)]"),
        re.compile(rf"\.get\(\s*'{esc}'\s*[,)]"),
    ]
    return any(p.search(text) for p in pats)


def _classify_symbol_hit(text: str, symbol_name: str) -> str:
    """Classify a *non-def/class* symbol hit.

    CONTRACT:
    - Deterministic and offline-safe (regex only).
    - This is used only for report evidence tags (it does not execute code).

    Returns:
      - "dict_key"
      - "field_or_const"
    """

    if _file_contains_any_key_patterns(text, symbol_name):
        return "dict_key"
    # NOTE: This intentionally lumps dataclass fields, pydantic-ish fields,
    # module/class constants, and Enum members into the same bucket.
    return "field_or_const"

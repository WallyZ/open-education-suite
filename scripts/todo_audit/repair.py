"""Canonical TODO repair helpers.

This module powers `scripts/todo_audit.py --repair`.

CONTRACT:
- Deterministic output for identical input.
- Idempotent normalization (second repair run should be a no-op).
- Non-destructive unless caller writes returned text.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

from scripts.todo_audit.evidence import (
    HTML_COMMENT_RE,
    _line_tag_namespace,
    _parse_yta_tags_from_text,
    _strip_html_comments,
)
from scripts.todo_audit.util import _dedupe_stable, compute_stable_todo_id


_LOOSE_CHECKBOX_RE = re.compile(
    r"^(?P<indent>\s*)(?P<marker>[-*])\s*\[\s*(?P<state>[xX ])\s*\]\s*(?P<text>.*)$"
)
_SUPPORTED_TAG_BODIES = ("yta:id", "ms:id", "yta:evidence", "ms:evidence")
_PHASE_HEADING_RE = re.compile(r"^\s*#{1,6}\s*phase\s*(?P<num>[123])\b", re.IGNORECASE)
_INLINE_PHASE_TAG_RE = re.compile(
    r"\[\s*(?:MVP|PH\s*[123]|P\s*[123]|Phase\s*[123])\s*\]",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class RepairAction:
    line: int
    code: str
    before: str
    after: str


def _is_supported_todo_comment(comment_body: str) -> bool:
    body_l = (comment_body or "").strip().lower()
    return any(body_l.startswith(prefix) for prefix in _SUPPORTED_TAG_BODIES)


def _collect_non_todo_comments(text_with_comments: str) -> list[str]:
    comments: list[str] = []
    for m in HTML_COMMENT_RE.finditer(text_with_comments or ""):
        body = (m.group("body") or "").strip()
        if _is_supported_todo_comment(body):
            continue
        comments.append(f"<!-- {body} -->")
    return comments


def _quote_if_needed(value: str) -> str:
    v = (value or "").strip()
    if not v:
        return ""
    if any(ch.isspace() for ch in v):
        return '"' + v.replace('"', "'") + '"'
    return v


def _join_values(values: list[str]) -> str:
    vals = _dedupe_stable([v.strip() for v in values if (v or "").strip()])
    if not vals:
        return ""
    joined = ",".join(vals)
    return _quote_if_needed(joined)


def _canonical_tag_comment(
    *,
    namespace: str,
    evidence: dict,
    explicit_id: str | None,
) -> str | None:
    ns = "ms" if namespace == "ms" else "yta"

    paths = _dedupe_stable([x.strip() for x in (evidence.get("paths") or []) if x.strip()])
    symbols = _dedupe_stable([x.strip() for x in (evidence.get("symbols") or []) if x.strip()])
    strings = _dedupe_stable([x.strip() for x in (evidence.get("strings") or []) if x.strip()])
    fields = _dedupe_stable([x.strip() for x in (evidence.get("fields") or []) if x.strip()])
    keys = _dedupe_stable([x.strip() for x in (evidence.get("keys") or []) if x.strip()])

    parts: list[str] = []
    tid = (explicit_id or "").strip()
    if tid:
        parts.append(f"id={_quote_if_needed(tid)}")

    if paths:
        parts.append(f"path={_join_values(paths)}")
    if symbols:
        parts.append(f"symbols={_join_values(symbols)}")
    if strings:
        parts.append(f"strings={_join_values(strings)}")
    if fields:
        parts.append(f"fields={_join_values(fields)}")
    if keys:
        parts.append(f"keys={_join_values(keys)}")

    has_actionable = bool(paths or symbols or strings or fields or keys)
    if has_actionable:
        return f"<!-- {ns}:evidence {' '.join(parts)} -->"

    if tid:
        return f"<!-- {ns}:id {tid} -->"

    return None


def _normalize_checkbox_line(line: str, *, default_namespace: str) -> str:
    m = _LOOSE_CHECKBOX_RE.match(line)
    if not m:
        return line.rstrip()

    indent = m.group("indent") or ""
    state_raw = m.group("state") or " "
    text_with_comments = (m.group("text") or "").rstrip()

    state = "x" if state_raw.strip().lower() == "x" else " "
    visible_text = _strip_html_comments(text_with_comments).strip()

    evidence, explicit_id = _parse_yta_tags_from_text(text_with_comments)
    non_todo_comments = _collect_non_todo_comments(text_with_comments)

    namespace = _line_tag_namespace(text_with_comments, default_namespace=default_namespace)
    effective_id = (explicit_id or "").strip() or None

    if state == "x" and not effective_id and visible_text:
        effective_id = compute_stable_todo_id(visible_text)

    rebuilt_comments: list[str] = []
    rebuilt_comments.extend(non_todo_comments)

    tag_comment = _canonical_tag_comment(
        namespace=namespace,
        evidence=evidence,
        explicit_id=effective_id,
    )
    if tag_comment:
        rebuilt_comments.append(tag_comment)

    final_text = visible_text
    if rebuilt_comments:
        if final_text:
            final_text = f"{final_text} {' '.join(rebuilt_comments)}"
        else:
            final_text = " ".join(rebuilt_comments)

    normalized = f"{indent}- [{state}] {final_text}".rstrip()
    return normalized


def _normalize_phase_for_checkbox_text(text_with_comments: str, *, phase_num: int) -> str:
    """Inject a canonical [PHn] phase tag into checkbox text while preserving comments."""

    if phase_num not in (1, 2, 3):
        return text_with_comments.rstrip()

    raw = (text_with_comments or "").rstrip()
    comment_idx = raw.find("<!--")
    if comment_idx >= 0:
        visible = raw[:comment_idx].rstrip()
        comment_tail = raw[comment_idx:].strip()
    else:
        visible = raw.strip()
        comment_tail = ""

    if not visible:
        return raw

    cleaned = _INLINE_PHASE_TAG_RE.sub("", visible)
    cleaned = re.sub(r"\s{2,}", " ", cleaned).strip()
    if not cleaned:
        return raw

    tagged = f"{cleaned} [PH{phase_num}]"
    if comment_tail:
        return f"{tagged} {comment_tail}".rstrip()
    return tagged.rstrip()


def repair_phase_tags_text(
    md_text: str,
    *,
    top_level_only: bool = True,
) -> tuple[str, list[RepairAction]]:
    """Convert heading-scoped phase sections to inline [PHn] tags on checkbox items."""

    lines = (md_text or "").splitlines()
    out_lines: list[str] = []
    actions: list[RepairAction] = []
    active_phase: int | None = None

    for line_no, original in enumerate(lines, start=1):
        hm = _PHASE_HEADING_RE.match(original)
        if hm:
            active_phase = int(hm.group("num"))
            out_lines.append(original.rstrip())
            continue

        cm = _LOOSE_CHECKBOX_RE.match(original)
        if not cm or active_phase is None:
            out_lines.append(original.rstrip())
            continue

        indent = cm.group("indent") or ""
        if top_level_only and bool(indent.strip()):
            out_lines.append(original.rstrip())
            continue

        old_text = (cm.group("text") or "").rstrip()
        new_text = _normalize_phase_for_checkbox_text(old_text, phase_num=active_phase)
        rebuilt = original[: cm.start("text")] + new_text
        rebuilt = rebuilt.rstrip()

        out_lines.append(rebuilt)
        if rebuilt != original:
            actions.append(
                RepairAction(
                    line=line_no,
                    code="INLINE_PHASE_TAG",
                    before=original,
                    after=rebuilt,
                )
            )

    return "\n".join(out_lines), actions


def repair_todo_text(
    md_text: str,
    *,
    default_namespace: str = "yta",
) -> tuple[str, list[RepairAction]]:
    """Return canonicalized TODO markdown text and line-level repair actions."""

    lines = (md_text or "").splitlines()
    out_lines: list[str] = []
    actions: list[RepairAction] = []

    for line_no, original in enumerate(lines, start=1):
        repaired = _normalize_checkbox_line(original, default_namespace=default_namespace)
        if not _LOOSE_CHECKBOX_RE.match(original):
            repaired = repaired.rstrip()

        out_lines.append(repaired)

        if repaired != original:
            actions.append(
                RepairAction(
                    line=line_no,
                    code="CANONICALIZE_LINE",
                    before=original,
                    after=repaired,
                )
            )

    return "\n".join(out_lines), actions


def _truncate(value: str, max_len: int = 96) -> str:
    v = (value or "").replace("|", "\\|")
    if len(v) <= max_len:
        return v
    return v[: max_len - 1] + "..."


def render_repair_markdown(
    actions: list[RepairAction],
    *,
    todo_path: Path | None = None,
    dry_run: bool = False,
) -> str:
    title = "TODO Repair Preview" if dry_run else "TODO Repair Report"
    if todo_path:
        title = f"{title}: {todo_path.as_posix()}"

    out: list[str] = [f"# {title}", ""]

    if not actions:
        out.append("No changes required; file is already canonical.")
        out.append("")
        return "\n".join(out)

    out.append(f"Changes: **{len(actions)}**")
    out.append("")
    out.append("| Line | Code | Before | After |")
    out.append("|---:|---|---|---|")
    for action in actions:
        out.append(
            f"| {action.line} | `{action.code}` | {_truncate(action.before)} | {_truncate(action.after)} |"
        )
    out.append("")
    return "\n".join(out)

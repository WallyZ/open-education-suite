"""Non-destructive TODO quality linter.

This module powers the `--lint` mode of `scripts/todo_audit.py`.

CONTRACT:
- Offline-only and deterministic: operates solely on the provided markdown text.
- Never writes to TODO files; no repo scanning.
"""

from __future__ import annotations

import json
import re
from datetime import datetime
from dataclasses import dataclass
from pathlib import Path
from typing import Literal

from scripts.todo_audit.detectors import extract_hints
from scripts.todo_audit.evidence import HTML_COMMENT_RE, _parse_yta_tags_from_text, _strip_html_comments
from scripts.todo_audit.metadata import (
    AUTOMATION_ALLOWED,
    PRIORITY_ALLOWED,
    SAFE_AUTOFIX_ALLOWED,
    VALIDATION_PROFILE_ALLOWED,
    parse_todo_metadata,
)
from scripts.todo_audit.todo_parse import (
    CHECKBOX_RE,
    HEADING_RE,
    extract_agent_file_paths,
    parse_todo_agent_sections,
)


Severity = Literal["info", "warn", "error"]


_SEVERITY_RANK: dict[Severity, int] = {"info": 0, "warn": 1, "error": 2}
_SUPPORTED_PREFIXES = ("yta:", "ms:")
_KEYVAL_RE = re.compile(r"(?P<key>[A-Za-z_][A-Za-z0-9_-]*)\s*=\s*(?P<val>\"[^\"]*\"|'[^']*'|\S+)")
_PHASE_HEADING_RE = re.compile(r"^\s*#{1,6}\s*phase\s*[123]\b", re.IGNORECASE)
_PHASE_TAG_RE = re.compile(r"\[PH(?P<num>[123])\]", re.IGNORECASE)
_ALIAS_TO_CANON = {
    "path": "path",
    "paths": "path",
    "symbol": "symbols",
    "symbols": "symbols",
    "string": "strings",
    "strings": "strings",
    "field": "fields",
    "fields": "fields",
    "key": "keys",
    "keys": "keys",
    "id": "id",
}
_CANON_KEY_ORDER = {"id": 0, "path": 1, "symbols": 2, "strings": 3, "fields": 4, "keys": 5}
_AGENT_REQUIRED_SECTIONS = {
    "deliverables": "Deliverables",
    "files": "Files",
    "verification": "Verification",
    "qa_live_automation": "QA Live automation",
    "drift_guard": "Drift guard",
    "downstream_rollout": "Downstream rollout",
    "acceptance": "Acceptance",
}


@dataclass(frozen=True)
class LintIssue:
    severity: Severity
    code: str
    line: int
    message: str
    suggestion: str | None = None

    def to_dict(self) -> dict:
        return {
            "severity": self.severity,
            "code": self.code,
            "line": int(self.line),
            "message": self.message,
            "suggestion": self.suggestion,
        }


def _min_severity_filter(issues: list[LintIssue], min_severity: Severity) -> list[LintIssue]:
    min_rank = _SEVERITY_RANK[min_severity]
    return [it for it in issues if _SEVERITY_RANK[it.severity] >= min_rank]


def _parse_comment_bodies(text_with_comments: str) -> list[str]:
    bodies: list[str] = []
    for m in HTML_COMMENT_RE.finditer(text_with_comments or ""):
        bodies.append((m.group("body") or "").strip())
    return bodies


def _extract_ids_from_comments(text_with_comments: str) -> tuple[str | None, str | None]:
    """Return (todo_id, evidence_id) for this line (if present)."""

    todo_id: str | None = None
    evidence_id: str | None = None

    for body in _parse_comment_bodies(text_with_comments):
        body_l = body.lower()

        if body_l.startswith("yta:id") or body_l.startswith("ms:id"):
            rest = body.split(":", 1)[1]
            rest = rest[len("id") :].strip()
            if not rest:
                todo_id = ""
                continue
            km = re.search(r"\bid\s*=\s*(\S+)", rest)
            if km:
                todo_id = km.group(1).strip().strip("\"'")
            else:
                todo_id = rest.split()[0].strip().strip("\"'")
            continue

        if body_l.startswith("yta:evidence") or body_l.startswith("ms:evidence"):
            km = re.search(
                r"\bid\s*=\s*(\"[^\"]*\"|'[^']*'|\S+)",
                body.split(":", 1)[1],
            )
            if km:
                evidence_id = km.group(1).strip().strip("\"'")

    return todo_id, evidence_id


def _has_supported_evidence_comment(text_with_comments: str) -> bool:
    for body in _parse_comment_bodies(text_with_comments):
        body_l = body.lower()
        if body_l.startswith("yta:evidence") or body_l.startswith("ms:evidence"):
            return True
    return False


def _extract_tag_namespaces(text_with_comments: str) -> set[str]:
    namespaces: set[str] = set()
    for body in _parse_comment_bodies(text_with_comments):
        body_l = body.lower()
        if body_l.startswith("ms:"):
            namespaces.add("ms")
        elif body_l.startswith("yta:"):
            namespaces.add("yta")
    return namespaces


def _extract_evidence_key_lists(text_with_comments: str) -> list[list[str]]:
    key_lists: list[list[str]] = []
    for body in _parse_comment_bodies(text_with_comments):
        body_l = body.lower()
        if not (body_l.startswith("yta:evidence") or body_l.startswith("ms:evidence")):
            continue
        rest = body.split(":", 1)[1]
        rest = rest[len("evidence") :].strip()
        keys: list[str] = []
        for km in _KEYVAL_RE.finditer(rest):
            keys.append((km.group("key") or "").strip().lower())
        key_lists.append(keys)
    return key_lists


def _is_malformed_id(tok: str | None) -> bool:
    if tok is None:
        return False
    t = (tok or "").strip()
    if not t:
        return True
    if re.search(r"\s", t):
        return True
    if "<" in t or ">" in t:
        return True
    # Conservative "stable id" token charset: allow manual IDs like `04-4.4-note`.
    if not re.match(r"^[A-Za-z0-9][A-Za-z0-9_.:-]{2,128}$", t):
        return True
    return False


_STOPWORDS = {
    "a",
    "an",
    "and",
    "are",
    "as",
    "be",
    "by",
    "for",
    "from",
    "if",
    "in",
    "into",
    "is",
    "it",
    "of",
    "on",
    "or",
    "the",
    "to",
    "with",
    "that",
    "this",
    "these",
    "those",
}


def _non_stopword_token_count(text: str) -> int:
    tokens = [t.lower() for t in re.split(r"[^A-Za-z0-9]+", text or "") if t]
    tokens = [t for t in tokens if t not in _STOPWORDS and len(t) >= 2]
    return len(tokens)


def _has_acceptance_markers(text: str) -> bool:
    t = (text or "").strip()
    if not t:
        return False
    # Keep this conservative: only count markers that tend to make TODOs testable/actionable.
    markers = [
        "`",
        "e.g.",
        "so that",
        "such that",
        "->",
        "should ",
        "must ",
        "assert",
        "test",
        "when ",
        "then ",
        "returns",
        "raise",
        "output",
    ]
    tl = t.lower()
    if any(m in t for m in ["`", "->"]):
        return True
    if any(m in tl for m in [m for m in markers if m not in {"`", "->"}]):
        return True
    return False


def _extract_phase_num(text: str) -> int | None:
    m = _PHASE_TAG_RE.search(text or "")
    if not m:
        return None
    try:
        return int(m.group("num"))
    except Exception:
        return None


def _is_iso_date(value: str) -> bool:
    token = (value or "").strip()
    if not token:
        return False
    try:
        datetime.strptime(token, "%Y-%m-%d")
        return True
    except Exception:
        return False


def _extract_checkbox_parts(line: str) -> tuple[str, str, str, str] | None:
    """Return (indent, marker, state, text_with_comments) for checkbox-ish lines."""

    loose_checkbox_re = re.compile(
        r"^(?P<indent>\s*)(?P<marker>[-*])\s*\[\s*(?P<state>[xX ])\s*\]\s*(?P<text>.*)$"
    )
    m = loose_checkbox_re.match(line)
    if not m:
        return None
    return m.group("indent"), m.group("marker"), m.group("state"), (m.group("text") or "").rstrip()


def lint_todo(md_text: str, *, path: Path | None = None) -> list[LintIssue]:
    """Lint a markdown TODO file's text and return a list of issues."""

    issues: list[LintIssue] = []
    lines = (md_text or "").splitlines()
    agent_sections_by_line = parse_todo_agent_sections(md_text)

    headings: list[tuple[int, str]] = []

    # ID tracking.
    todo_id_to_lines: dict[str, list[int]] = {}
    ev_id_to_lines: dict[str, list[int]] = {}

    # Indentation hierarchy tracking (reset per heading block).
    indent_stack: list[tuple[int, int]] = []  # (indent_len, line_no)

    for line_no, line in enumerate(lines, start=1):
        hm = HEADING_RE.match(line)
        if hm:
            level = len(hm.group("hashes"))
            title = hm.group("title").strip()
            while headings and headings[-1][0] >= level:
                headings.pop()
            headings.append((level, title))
            indent_stack.clear()
            if _PHASE_HEADING_RE.match(line):
                issues.append(
                    LintIssue(
                        severity="error",
                        code="PHASE_HEADING_NON_CANONICAL",
                        line=line_no,
                        message="Phase headings are non-canonical for TODOs; use inline [PHn] tags on TODO items.",
                        suggestion=(
                            "Remove phase headings and add [PH1]/[PH2]/[PH3] inline tags; "
                            "run 'python scripts/todo_audit.py --todo <path> --repair --repair-scope phase-tags'."
                        ),
                    )
                )
            continue

        parts = _extract_checkbox_parts(line)
        if not parts:
            continue

        indent_raw, marker, state_raw, text_with_comments = parts
        indent_len = len(indent_raw.replace("\t", "    "))
        item_text = _strip_html_comments(text_with_comments).strip()
        checked = state_raw.strip().lower() == "x"
        phase_num = _extract_phase_num(item_text)

        # Canonical checkbox shape checks.
        if not CHECKBOX_RE.match(line):
            issues.append(
                LintIssue(
                    severity="info",
                    code="CHECKBOX_SPACING",
                    line=line_no,
                    message="Checkbox spacing is non-canonical; prefer '- [ ]' / '- [x]'.",
                    suggestion="Rewrite as '- [ ] ...' or '- [x] ...' (single spaces; no extra spaces in brackets).",
                )
            )
        if marker != "-":
            issues.append(
                LintIssue(
                    severity="info",
                    code="CHECKBOX_MARKER",
                    line=line_no,
                    message="Checkbox marker is non-canonical; use '-' (not '*').",
                    suggestion="Rewrite checkbox line to start with '- [ ]' or '- [x]'.",
                )
            )
        if state_raw == "X":
            issues.append(
                LintIssue(
                    severity="info",
                    code="CHECKBOX_UPPER_X",
                    line=line_no,
                    message="Checked checkbox uses uppercase 'X'; canonical form is lowercase 'x'.",
                    suggestion="Use '- [x]' for checked items.",
                )
            )

        # Structure: heading hierarchy.
        has_heading_context = bool(headings)
        if not has_heading_context:
            issues.append(
                LintIssue(
                    severity="warn",
                    code="STRUCT_NO_HEADING",
                    line=line_no,
                    message="Checkbox TODO appears outside any heading context.",
                    suggestion="Move this item under an appropriate markdown heading.",
                )
            )

        # Structure: indentation parent.
        while indent_stack and indent_stack[-1][0] >= indent_len:
            indent_stack.pop()
        if indent_len > 0 and not indent_stack:
            issues.append(
                LintIssue(
                    severity="warn",
                    code="STRUCT_INDENT_ORPHAN",
                    line=line_no,
                    message="Indented checkbox item has no clear parent checkbox.",
                    suggestion="Ensure the nearest less-indented previous item is a checkbox parent.",
                )
            )
        indent_stack.append((indent_len, line_no))

        # Tag namespace and evidence comment consistency.
        namespaces = _extract_tag_namespaces(text_with_comments)
        if len(namespaces) > 1:
            issues.append(
                LintIssue(
                    severity="warn",
                    code="TAG_NAMESPACE_MIXED",
                    line=line_no,
                    message="Line mixes ms:* and yta:* TODO tags; use one namespace per line.",
                    suggestion="Keep either ms:* or yta:* tags on a given checkbox line, not both.",
                )
            )

        evidence_key_lists = _extract_evidence_key_lists(text_with_comments)
        if len(evidence_key_lists) > 1:
            issues.append(
                LintIssue(
                    severity="warn",
                    code="EVIDENCE_MULTIPLE_COMMENTS",
                    line=line_no,
                    message="Multiple evidence comments found on one checkbox line.",
                    suggestion="Consolidate to a single evidence comment with canonical key order.",
                )
            )

        for keys in evidence_key_lists:
            if not keys:
                continue
            canonicalized = [_ALIAS_TO_CANON.get(k, k) for k in keys]
            order = [_CANON_KEY_ORDER[k] for k in canonicalized if k in _CANON_KEY_ORDER]
            if any(order[i] < order[i - 1] for i in range(1, len(order))):
                issues.append(
                    LintIssue(
                        severity="info",
                        code="EVIDENCE_KEY_ORDER",
                        line=line_no,
                        message="Evidence keys are not in canonical order (id,path,symbols,strings,fields,keys).",
                        suggestion="Reorder evidence keys deterministically for stable diffs.",
                    )
                )
            alias_keys = [k for k in keys if _ALIAS_TO_CANON.get(k, k) != k]
            if alias_keys:
                issues.append(
                    LintIssue(
                        severity="info",
                        code="EVIDENCE_KEY_ALIAS",
                        line=line_no,
                        message="Evidence uses non-canonical key aliases (e.g., paths/symbol/string/field/key).",
                        suggestion="Prefer canonical keys: id, path, symbols, strings, fields, keys.",
                    )
                )

        evidence_dict, _explicit_id_any = _parse_yta_tags_from_text(text_with_comments)
        has_evidence_comment = _has_supported_evidence_comment(text_with_comments)
        todo_id, evidence_id = _extract_ids_from_comments(text_with_comments)

        meta = parse_todo_metadata(text_with_comments)
        if meta.get("present"):
            unknown_keys = meta.get("unknown_keys") or []
            if unknown_keys:
                issues.append(
                    LintIssue(
                        severity="error",
                        code="META_UNKNOWN_KEY",
                        line=line_no,
                        message=(
                            "Metadata contains unknown key(s): "
                            + ", ".join(sorted({str(k) for k in unknown_keys if str(k).strip()}))
                        ),
                        suggestion=(
                            "Use canonical meta keys: priority, owner, depends-on, blocked-by, target-repo, "
                            "stale-days, automation-level, human-checkpoint, rollout-scope, validation-profile, safe-autofix."
                        ),
                    )
                )

            priority = (meta.get("priority") or "").strip().lower()
            if priority and priority not in PRIORITY_ALLOWED:
                issues.append(
                    LintIssue(
                        severity="error",
                        code="META_PRIORITY_INVALID",
                        line=line_no,
                        message=f"Metadata priority value is not recognized: {priority!r}",
                        suggestion="Use one of: p0, p1, p2, p3, high, medium, low.",
                    )
                )

            automation_level = (meta.get("automation_level") or "").strip().lower()
            if automation_level and automation_level not in AUTOMATION_ALLOWED:
                issues.append(
                    LintIssue(
                        severity="error",
                        code="META_AUTOMATION_LEVEL_INVALID",
                        line=line_no,
                        message=f"Metadata automation-level value is not recognized: {automation_level!r}",
                        suggestion="Use one of: auto, assisted, manual, none.",
                    )
                )

            validation_profile = (meta.get("validation_profile") or "").strip().lower()
            if validation_profile and validation_profile not in VALIDATION_PROFILE_ALLOWED:
                issues.append(
                    LintIssue(
                        severity="error",
                        code="META_VALIDATION_PROFILE_INVALID",
                        line=line_no,
                        message=f"Metadata validation-profile value is not recognized: {validation_profile!r}",
                        suggestion="Use one of: 32k, 64k, cloud, full.",
                    )
                )

            safe_autofix = (meta.get("safe_autofix") or "").strip().lower()
            if safe_autofix and safe_autofix not in SAFE_AUTOFIX_ALLOWED:
                issues.append(
                    LintIssue(
                        severity="error",
                        code="META_SAFE_AUTOFIX_INVALID",
                        line=line_no,
                        message=f"Metadata safe-autofix value is not recognized: {safe_autofix!r}",
                        suggestion="Use one of: safe, review, manual, none, auto.",
                    )
                )

            stale_days_raw = (meta.get("stale_days_raw") or "").strip()
            stale_days = meta.get("stale_days")
            if stale_days_raw and stale_days is None:
                issues.append(
                    LintIssue(
                        severity="error",
                        code="META_STALE_DAYS_INVALID",
                        line=line_no,
                        message=f"Metadata stale-days is not a valid integer: {stale_days_raw!r}",
                        suggestion="Use a positive integer for stale-days (for example: stale-days=14).",
                    )
                )
            elif isinstance(stale_days, int) and stale_days <= 0:
                issues.append(
                    LintIssue(
                        severity="error",
                        code="META_STALE_DAYS_NON_POSITIVE",
                        line=line_no,
                        message=f"Metadata stale-days must be > 0 (got {stale_days}).",
                        suggestion="Use stale-days with a positive integer (for example: stale-days=14).",
                    )
                )

            ref_ids = {x.strip() for x in [todo_id, evidence_id] if isinstance(x, str) and x.strip()}
            for dep in meta.get("depends_on") or []:
                dep_id = str(dep).strip()
                if dep_id and dep_id in ref_ids:
                    issues.append(
                        LintIssue(
                            severity="error",
                            code="META_SELF_DEPENDENCY",
                            line=line_no,
                            message=f"depends-on contains this item's own id: {dep_id!r}",
                            suggestion="Remove self-references from depends-on.",
                        )
                    )

        if (not checked) and (phase_num is not None) and phase_num >= 2:
            if not (todo_id or evidence_id):
                issues.append(
                    LintIssue(
                        severity="error",
                        code="AGENT_READY_ID_MISSING",
                        line=line_no,
                        message="Open PH2/PH3 TODO items must carry an explicit id or evidence id for agent queueing.",
                        suggestion="Add `id=<STABLE_ID>` to the ms:evidence/yta:evidence tag or add an ms:id/yta:id tag.",
                    )
                )

            if not meta.get("present"):
                issues.append(
                    LintIssue(
                        severity="error",
                        code="META_REQUIRED_OPEN_PHASE2_PLUS",
                        line=line_no,
                        message="Open PH2/PH3 TODO items must include an ms:meta/yta:meta comment for queueing.",
                        suggestion=(
                            "Add metadata on the TODO line (priority, owner, stale-days, automation-level, "
                            "human-checkpoint, validation-profile, safe-autofix, updated)."
                        ),
                    )
                )
            else:
                required_missing: list[str] = []
                if not (meta.get("priority") or "").strip():
                    required_missing.append("priority")
                if not (meta.get("owner") or []):
                    required_missing.append("owner")
                if not (meta.get("stale_days_raw") or "").strip():
                    required_missing.append("stale-days")
                if not (meta.get("automation_level") or "").strip():
                    required_missing.append("automation-level")
                human_checkpoint = (meta.get("human_checkpoint") or "").strip()
                if not human_checkpoint:
                    required_missing.append("human-checkpoint")
                if not (meta.get("validation_profile") or "").strip():
                    required_missing.append("validation-profile")
                if not (meta.get("safe_autofix") or "").strip():
                    required_missing.append("safe-autofix")

                updated_value = (meta.get("updated") or "").strip()
                if not updated_value:
                    required_missing.append("updated")
                elif not _is_iso_date(updated_value):
                    issues.append(
                        LintIssue(
                            severity="error",
                            code="META_UPDATED_INVALID",
                            line=line_no,
                            message=f"Metadata updated value must be YYYY-MM-DD (got {updated_value!r}).",
                            suggestion="Use updated=YYYY-MM-DD (for example: updated=2026-03-13).",
                        )
                    )

                if required_missing:
                    issues.append(
                        LintIssue(
                            severity="error",
                            code="META_REQUIRED_MISSING",
                            line=line_no,
                            message=(
                                "Open PH2/PH3 TODO metadata is missing required field(s): "
                                + ", ".join(required_missing)
                            ),
                            suggestion=(
                                "Add a meta tag, for example: <!-- ms:meta priority=p2 owner=@repo-kit "
                                "stale-days=14 automation-level=assisted human-checkpoint=review "
                                "validation-profile=cloud safe-autofix=review updated=2026-03-13 -->"
                            ),
                        )
                    )

            sections = agent_sections_by_line.get(line_no, {})
            missing_sections = [
                label
                for key, label in _AGENT_REQUIRED_SECTIONS.items()
                if not any((value or "").strip() for value in sections.get(key, []))
            ]
            if missing_sections:
                issues.append(
                    LintIssue(
                        severity="error",
                        code="AGENT_READY_SECTION_MISSING",
                        line=line_no,
                        message=(
                            "Open PH2/PH3 TODO item is missing agent-ready child section(s): "
                            + ", ".join(missing_sections)
                        ),
                        suggestion=(
                            "Add nested child bullets for Deliverables, Files, Verification, Drift guard, "
                            "QA Live automation, Downstream rollout, and Acceptance."
                        ),
                    )
                )

            file_section_values = sections.get("files", [])
            if file_section_values and not extract_agent_file_paths(file_section_values):
                issues.append(
                    LintIssue(
                        severity="error",
                        code="AGENT_READY_FILES_UNPARSEABLE",
                        line=line_no,
                        message="Open PH2/PH3 TODO Files section has no parseable file path tokens.",
                        suggestion="Put expected files in backticks, for example: `docs/TODO_PROCESS.md`, `scripts/foo.py`.",
                    )
                )

        # Evidence/actionability (only path/symbols/strings are considered "actionable" for lint).
        has_actionable_evidence = bool(
            (evidence_dict.get("paths") or [])
            or (evidence_dict.get("symbols") or [])
            or (evidence_dict.get("strings") or [])
        )

        # Completed tasks should always carry id/evidence for auditability.
        if checked and (not has_evidence_comment) and (not todo_id):
            issues.append(
                LintIssue(
                    severity="error",
                    code="DONE_EVIDENCE_OR_ID_MISSING",
                    line=line_no,
                    message="Completed TODO has no evidence/id tag; completion is non-auditable.",
                    suggestion="Add '<!-- ms:evidence ... -->', '<!-- yta:evidence ... -->', or at least '<!-- ...:id ... -->'.",
                )
            )

        if has_evidence_comment and not has_actionable_evidence:
            issues.append(
                LintIssue(
                    severity="warn",
                    code="EVIDENCE_NOT_ACTIONABLE",
                    line=line_no,
                    message="Evidence tag is present but has no path=/symbols=/strings= tokens.",
                    suggestion="Add at least one of: path=..., symbols=..., strings=... (comma/semicolon separated).",
                )
            )

        # Unchecked items without evidence are acceptable, but we still nudge when very concrete artifacts appear.
        if (not has_evidence_comment) and (not has_actionable_evidence) and (not checked):
            hints = extract_hints(item_text)
            looks_impl_specific = bool(
                (hints.get("paths") or [])
                or (hints.get("symbols") or [])
                or (hints.get("commands") or [])
            )
            if looks_impl_specific:
                issues.append(
                    LintIssue(
                        severity="info",
                        code="EVIDENCE_RECOMMENDED",
                        line=line_no,
                        message="TODO references concrete artifacts but has no explicit evidence tokens.",
                        suggestion="Consider an explicit '<!-- ...:evidence path=... symbols=... strings=... -->' tag.",
                    )
                )

        # Stable IDs: track + validate.
        if todo_id is not None:
            if _is_malformed_id(todo_id):
                issues.append(
                    LintIssue(
                        severity="warn",
                        code="ID_MALFORMED",
                        line=line_no,
                        message=f"id token looks malformed: {todo_id!r}",
                        suggestion="Use a compact, space-free ID (e.g., stable hash id=... or '04-...').",
                    )
                )
            key = (todo_id or "").strip()
            todo_id_to_lines.setdefault(key, []).append(line_no)

        if evidence_id is not None:
            if _is_malformed_id(evidence_id):
                issues.append(
                    LintIssue(
                        severity="warn",
                        code="ID_MALFORMED",
                        line=line_no,
                        message=f"evidence id= token looks malformed: {evidence_id!r}",
                        suggestion="Use a compact, space-free ID (e.g., stable hash id=... or '04-...').",
                    )
                )
            key = (evidence_id or "").strip()
            ev_id_to_lines.setdefault(key, []).append(line_no)

        # Vagueness heuristics (advisory only).
        if not has_actionable_evidence:
            non_stop = _non_stopword_token_count(item_text)
            if non_stop > 0 and non_stop < 6:
                issues.append(
                    LintIssue(
                        severity="info",
                        code="VAGUE_TOO_SHORT",
                        line=line_no,
                        message="TODO text looks short/vague and has no actionable evidence tokens.",
                        suggestion="Add specificity (artifact + acceptance criteria) or evidence tokens.",
                    )
                )

            if re.match(r"(?i)^(ensure|improve|fix)\b", item_text) or re.match(
                r"(?i)^handle\s+edge\s+cases\b", item_text
            ):
                if not _has_acceptance_markers(item_text):
                    issues.append(
                        LintIssue(
                            severity="info",
                            code="VAGUE_IMPERATIVE",
                            line=line_no,
                            message="TODO starts with a vague imperative without acceptance markers/evidence.",
                            suggestion="Add concrete criteria (what to verify) and/or evidence tokens.",
                        )
                    )

            if re.search(r"\[PH\d+\]", item_text):
                hints = extract_hints(item_text)
                has_artifact_hints = bool(
                    (hints.get("paths") or [])
                    or (hints.get("symbols") or [])
                    or (hints.get("commands") or [])
                )
                if not has_artifact_hints:
                    issues.append(
                        LintIssue(
                            severity="info",
                            code="PHASE_NO_ARTIFACT",
                            line=line_no,
                            message="TODO has a phase tag but no obvious concrete artifact target (path/symbol/string).",
                            suggestion="Consider adding an artifact hint (e.g., file path) and/or evidence tokens.",
                        )
                    )

    # Duplicate IDs (id comments)
    for tid, ls in sorted(todo_id_to_lines.items(), key=lambda x: (x[0], x[1])):
        if not tid or len(ls) <= 1:
            continue
        first = ls[0]
        for dup_line in ls[1:]:
            issues.append(
                LintIssue(
                    severity="error",
                    code="ID_DUPLICATE",
                    line=dup_line,
                    message=f"Duplicate id value {tid!r} (first seen on line {first}).",
                    suggestion="IDs must be unique per file; regenerate or rename one of the duplicates.",
                )
            )

    # Duplicate evidence IDs (evidence id=...)
    for eid, ls in sorted(ev_id_to_lines.items(), key=lambda x: (x[0], x[1])):
        if not eid or len(ls) <= 1:
            continue
        first = ls[0]
        for dup_line in ls[1:]:
            issues.append(
                LintIssue(
                    severity="error",
                    code="EVIDENCE_ID_DUPLICATE",
                    line=dup_line,
                    message=f"Duplicate evidence id= value {eid!r} (first seen on line {first}).",
                    suggestion="Evidence IDs must be unique per file; regenerate or rename one of the duplicates.",
                )
            )

    # Stable/deterministic ordering.
    issues = sorted(
        issues,
        key=lambda it: (-_SEVERITY_RANK[it.severity], int(it.line), it.code, it.message),
    )
    return issues


def _severity_label(sev: Severity) -> str:
    return sev.upper()


def summarize_issues(issues: list[LintIssue]) -> dict[str, int]:
    out = {"error": 0, "warn": 0, "info": 0}
    for it in issues:
        out[it.severity] = out.get(it.severity, 0) + 1
    return out


def render_lint_markdown(issues: list[LintIssue], *, todo_path: Path | None = None) -> str:
    counts = summarize_issues(issues)
    title = f"TODO Lint Report" + (f": {todo_path.as_posix()}" if todo_path else "")

    out: list[str] = []
    out.append(f"# {title}")
    out.append("")
    out.append(f"Summary: **{counts.get('error', 0)} error**, **{counts.get('warn', 0)} warn**, **{counts.get('info', 0)} info**")
    out.append("")

    for sev in ["error", "warn", "info"]:
        group = [it for it in issues if it.severity == sev]
        out.append(f"## {_severity_label(sev)} ({len(group)})")
        out.append("")
        if not group:
            out.append("_(none)_")
            out.append("")
            continue
        out.append("| Line | Code | Message | Suggestion |")
        out.append("|---:|---|---|---|")
        for it in group:
            sugg = it.suggestion or ""
            msg = it.message.replace("\n", " ")
            sugg = sugg.replace("\n", " ")
            out.append(f"| {it.line} | `{it.code}` | {msg} | {sugg} |")
        out.append("")

    return "\n".join(out).rstrip() + "\n"


def render_lint_json(issues: list[LintIssue], *, todo_path: Path | None = None) -> str:
    payload = {
        "todo_path": str(todo_path.as_posix()) if todo_path else None,
        "summary": summarize_issues(issues),
        "issues": [it.to_dict() for it in issues],
    }
    return json.dumps(payload, indent=2, sort_keys=True) + "\n"


def compute_lint_exit_code(issues: list[LintIssue], *, fail_on: Literal["none", "warn", "error"]) -> int:
    if fail_on == "none":
        return 0
    counts = summarize_issues(issues)
    if fail_on == "warn":
        return 2 if (counts.get("warn", 0) > 0 or counts.get("error", 0) > 0) else 0
    # fail_on == "error"
    return 2 if counts.get("error", 0) > 0 else 0


def lint_and_format(
    md_text: str,
    *,
    todo_path: Path | None = None,
    fmt: Literal["md", "json"] = "md",
    min_severity: Severity = "warn",
) -> tuple[list[LintIssue], str]:
    issues_all = lint_todo(md_text, path=todo_path)
    issues = _min_severity_filter(issues_all, min_severity)
    if fmt == "json":
        return issues, render_lint_json(issues, todo_path=todo_path)
    return issues, render_lint_markdown(issues, todo_path=todo_path)

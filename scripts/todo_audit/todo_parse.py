"""TODO markdown parsing for the TODO audit tool."""

from __future__ import annotations

import re

from scripts.todo_audit.evidence import _parse_yta_tags_from_text, _strip_html_comments
from scripts.todo_audit.metadata import parse_todo_metadata
from scripts.todo_audit.util import compute_stable_todo_id


HEADING_RE = re.compile(r"^(?P<hashes>#{1,6})\s+(?P<title>.+?)\s*$")
CHECKBOX_RE = re.compile(
    r"^(?P<indent>\s*)[-*]\s+\[(?P<state>[ xX])\]\s+(?P<text>.*)$"
)
AGENT_SECTION_RE = re.compile(
    r"^(?P<indent>\s*)[-*]\s+(?P<label>[A-Za-z][A-Za-z0-9 _/-]*):\s*(?P<body>.*)$"
)
NESTED_BULLET_RE = re.compile(r"^(?P<indent>\s*)[-*]\s+(?P<body>.+?)\s*$")
INLINE_CODE_RE = re.compile(r"`([^`]+)`")

AGENT_SECTION_LABELS = {
    "deliverables": {"deliverable", "deliverables"},
    "files": {"file", "files"},
    "verification": {"verification", "verify", "verifier"},
    "qa_live_automation": {
        "qa live",
        "qa live automation",
        "qa live testing",
        "qa-live",
        "qa-live automation",
        "qa-live testing",
        "qa_live",
        "qa_live_automation",
        "automated testing",
    },
    "drift_guard": {"drift guard", "drift-guard", "drift_guard", "drift guards"},
    "downstream_rollout": {
        "downstream rollout",
        "downstream-rollout",
        "downstream_rollout",
        "rollout",
    },
    "acceptance": {"acceptance", "acceptance criteria"},
}

_LABEL_TO_AGENT_SECTION = {
    alias: key for key, aliases in AGENT_SECTION_LABELS.items() for alias in aliases
}


class TodoItem:
    def __init__(
        self,
        *,
        line_no: int,
        raw_line: str,
        indent: str,
        checked: bool,
        text_with_comments: str,
        section_path: list[str],
    ):
        self.line_no = line_no
        self.raw_line = raw_line
        self.indent = indent
        self.checked = checked
        self.text_with_comments = text_with_comments
        self.text = _strip_html_comments(text_with_comments).strip()
        self.section_path = section_path

        self.yta_evidence, explicit_id = _parse_yta_tags_from_text(text_with_comments)
        self.explicit_id = explicit_id
        self.todo_id = explicit_id or compute_stable_todo_id(self.text)

        # Section display is still useful for the report.
        self.section_display = " > ".join(section_path) if section_path else "(no heading)"
        self.meta = parse_todo_metadata(text_with_comments)

    def has_explicit_evidence(self) -> bool:
        e = self.yta_evidence
        return bool(
            e.get("paths")
            or e.get("symbols")
            or e.get("strings")
            or e.get("fields")
            or e.get("keys")
        )

    def checkbox(self) -> str:
        return "[x]" if self.checked else "[ ]"


def parse_markdown_todos(md_text: str) -> list[TodoItem]:
    items: list[TodoItem] = []
    headings: list[tuple[int, str]] = []
    lines = md_text.splitlines()

    for idx, line in enumerate(lines, start=1):
        hm = HEADING_RE.match(line)
        if hm:
            level = len(hm.group("hashes"))
            title = hm.group("title").strip()
            while headings and headings[-1][0] >= level:
                headings.pop()
            headings.append((level, title))
            continue

        cm = CHECKBOX_RE.match(line)
        if not cm:
            continue

        indent = cm.group("indent")
        state = cm.group("state")
        text_with_comments = cm.group("text").rstrip()
        checked = state.strip().lower() == "x"
        section_path = [t for (_lvl, t) in headings]

        items.append(
            TodoItem(
                line_no=idx,
                raw_line=line,
                indent=indent,
                checked=checked,
                text_with_comments=text_with_comments,
                section_path=section_path,
            )
        )

    return items


def _indent_len(raw_indent: str) -> int:
    return len((raw_indent or "").replace("\t", "    "))


def _normalize_agent_section_label(label: str) -> str | None:
    token = re.sub(r"\s+", " ", (label or "").strip().lower())
    token = token.replace("_", " ")
    return _LABEL_TO_AGENT_SECTION.get(token)


def parse_todo_agent_sections(md_text: str) -> dict[int, dict[str, list[str]]]:
    """Return immediate child-bullet agent sections keyed by TODO checkbox line.

    The parser is intentionally conservative. It only captures bullets nested
    under a checkbox and stops at the next sibling checkbox or heading.
    """

    lines = (md_text or "").splitlines()
    items = parse_markdown_todos(md_text)
    sections_by_line: dict[int, dict[str, list[str]]] = {}

    for item in items:
        root_indent = _indent_len(item.indent)
        current_key: str | None = None
        current_indent: int | None = None
        captured: dict[str, list[str]] = {key: [] for key in AGENT_SECTION_LABELS}

        for idx in range(item.line_no, len(lines)):
            line = lines[idx]
            if HEADING_RE.match(line):
                break

            checkbox_match = CHECKBOX_RE.match(line)
            if checkbox_match and _indent_len(checkbox_match.group("indent")) <= root_indent:
                break

            if not line.strip():
                continue

            section_match = AGENT_SECTION_RE.match(line)
            if section_match:
                indent = _indent_len(section_match.group("indent"))
                key = _normalize_agent_section_label(section_match.group("label"))
                if key and indent > root_indent:
                    body = (section_match.group("body") or "").strip()
                    if body:
                        captured[key].append(body)
                    current_key = key
                    current_indent = indent
                    continue

            nested_match = NESTED_BULLET_RE.match(line)
            if current_key and current_indent is not None and nested_match:
                indent = _indent_len(nested_match.group("indent"))
                if indent > current_indent:
                    captured[current_key].append((nested_match.group("body") or "").strip())
                    continue

            if current_key and current_indent is not None:
                indent = _indent_len(line[: len(line) - len(line.lstrip())])
                if indent > current_indent:
                    captured[current_key].append(line.strip())

        sections_by_line[item.line_no] = {
            key: [value for value in values if value.strip()]
            for key, values in captured.items()
        }

    return sections_by_line


def extract_agent_file_paths(values: list[str]) -> list[str]:
    """Extract normalized path-like tokens from an agent-ready Files section."""

    paths: list[str] = []
    seen: set[str] = set()
    for value in values or []:
        candidates = [m.group(1) for m in INLINE_CODE_RE.finditer(value or "")]
        if not candidates:
            candidates = [part.strip() for part in re.split(r"[;,]", value or "") if part.strip()]

        for candidate in candidates:
            token = candidate.strip().strip(".,")
            token = token.strip("\"'")
            token = token.replace("\\", "/")
            while token.startswith("./"):
                token = token[2:]
            if not token or token.lower().startswith(("http://", "https://")):
                continue
            if token not in seen:
                paths.append(token)
                seen.add(token)

    return paths

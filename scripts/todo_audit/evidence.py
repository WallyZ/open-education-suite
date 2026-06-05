"""Evidence token parsing and normalization for TODO audit.

Handles:
- `yta:evidence` / `ms:evidence` HTML comment parsing
- `yta:id` / `ms:id` HTML comment parsing
- ID injection helpers
"""

from __future__ import annotations

import re

from scripts.todo_audit.util import _dedupe_stable, compute_stable_todo_id


HTML_COMMENT_RE = re.compile(r"<!--\s*(?P<body>.*?)\s*-->")
SUPPORTED_TAG_PREFIXES = ("yta:", "ms:")

# Checkbox lines in markdown TODO files.
CHECKBOX_RE = re.compile(
    r"^(?P<indent>\s*)[-*]\s+\[(?P<state>[ xX])\]\s+(?P<text>.*)$"
)


def _normalize_hint_token(token: str) -> str:
    token = token.strip().strip("\"'")
    token = token.strip("()[]{}<>")
    token = token.strip("`")
    token = token.replace("\\", "/")
    while token.startswith("./"):
        token = token[2:]
    return token


def _strip_html_comments(s: str) -> str:
    return HTML_COMMENT_RE.sub("", s).rstrip()


def _split_list_value(value: str) -> list[str]:
    value = value.strip().strip("\"'")
    if not value:
        return []
    parts = [p.strip() for p in re.split(r"[;,]", value) if p.strip()]
    return parts


def _parse_yta_tags_from_text(text_with_comments: str) -> tuple[dict, str | None]:
    """Parse supported TODO evidence tags embedded in HTML comments.

    Supported:
      - <!-- yta:evidence ... --> / <!-- ms:evidence ... -->
      - <!-- yta:id <stable_id> --> / <!-- ms:id <stable_id> -->
      - id=<stable_id> inside evidence comments

    Returns:
      (evidence_dict, explicit_id)

    evidence_dict keys: paths, symbols, strings, fields, keys
    """

    evidence = {"paths": [], "symbols": [], "strings": [], "fields": [], "keys": []}
    explicit_id: str | None = None

    # We allow multiple HTML comments on the same line.
    for m in HTML_COMMENT_RE.finditer(text_with_comments):
        body = (m.group("body") or "").strip()
        body_l = body.lower()
        if not any(body_l.startswith(prefix) for prefix in SUPPORTED_TAG_PREFIXES):
            continue

        # yta:id / ms:id
        if body_l.startswith("yta:id") or body_l.startswith("ms:id"):
            rest = body.split(":", 1)[1]
            rest = rest[len("id") :].strip()
            if not rest:
                continue
            km = re.search(r"\bid\s*=\s*(\S+)", rest)
            if km:
                explicit_id = km.group(1).strip().strip("\"'")
            else:
                explicit_id = rest.split()[0].strip().strip("\"'")
            continue

        # yta:evidence / ms:evidence
        if body_l.startswith("yta:evidence") or body_l.startswith("ms:evidence"):
            rest = body.split(":", 1)[1]
            rest = rest[len("evidence") :].strip()
            # key=value pairs; values with spaces must be quoted.
            for km in re.finditer(
                r"(?P<key>[A-Za-z_][A-Za-z0-9_-]*)\s*=\s*(?P<val>\"[^\"]*\"|'[^']*'|\S+)",
                rest,
            ):
                key = km.group("key").strip().lower()
                val = km.group("val").strip()

                if key == "id" and not explicit_id:
                    explicit_id = val.strip().strip("\"'")
                    continue

                if key in {"path", "paths"}:
                    evidence["paths"].extend(_split_list_value(val))
                elif key in {"symbol", "symbols"}:
                    evidence["symbols"].extend(_split_list_value(val))
                elif key in {"string", "strings"}:
                    evidence["strings"].extend(_split_list_value(val))
                elif key in {"field", "fields"}:
                    evidence["fields"].extend(_split_list_value(val))
                elif key in {"key", "keys"}:
                    evidence["keys"].extend(_split_list_value(val))

    evidence = {
        "paths": _dedupe_stable([_normalize_hint_token(x) for x in evidence["paths"]]),
        "symbols": _dedupe_stable([x.strip() for x in evidence["symbols"] if x.strip()]),
        "strings": _dedupe_stable([x.strip() for x in evidence["strings"] if x.strip()]),
        "fields": _dedupe_stable([x.strip() for x in evidence["fields"] if x.strip()]),
        "keys": _dedupe_stable([x.strip().strip("\"'") for x in evidence["keys"] if x.strip()]),
    }
    if explicit_id:
        explicit_id = explicit_id.strip()
    return evidence, explicit_id


def _extract_yta_id_from_line(line: str) -> str | None:
    # Parse from any supported tag. We allow yta/ms id comments and id= in evidence.
    if "<!--" not in line:
        return None
    _e, explicit = _parse_yta_tags_from_text(line)
    return explicit


def _line_has_yta_evidence_comment(line: str) -> bool:
    for m in HTML_COMMENT_RE.finditer(line):
        body = (m.group("body") or "").strip().lower()
        if body.startswith("yta:evidence") or body.startswith("ms:evidence"):
            return True
    return False


def _line_tag_namespace(line: str, *, default_namespace: str = "yta") -> str:
    """Return preferred namespace for TODO tags found on this line.

    Prefers the first explicit supported tag (`ms:` or `yta:`) encountered.
    Falls back to `default_namespace`.
    """

    for m in HTML_COMMENT_RE.finditer(line):
        body = (m.group("body") or "").strip().lower()
        if body.startswith("ms:"):
            return "ms"
        if body.startswith("yta:"):
            return "yta"
    return "ms" if (default_namespace or "").strip().lower() == "ms" else "yta"


def _ensure_line_has_yta_id(line: str, todo_id: str, *, default_namespace: str = "yta") -> str:
    """Ensure a checkbox line carries a stable ID tag.

    Rules:
    - If an explicit TODO id exists, do NOT overwrite it.
    - If an evidence comment exists without id=, inject id= into that comment.
    - Otherwise append `<!-- <ns>:id <id> -->`, where `<ns>` is inferred per-line.
    """

    existing = _extract_yta_id_from_line(line)
    if existing:
        return line
    if not todo_id:
        return line

    if _line_has_yta_evidence_comment(line):
        # Inject into the first evidence comment that lacks id=.
        for m in HTML_COMMENT_RE.finditer(line):
            body = (m.group("body") or "").strip()
            body_l = body.lower()
            if (
                (body_l.startswith("yta:evidence") or body_l.startswith("ms:evidence"))
                and not re.search(r"\bid\s*=", body_l)
            ):
                new_comment = f"<!-- {body} id={todo_id} -->"
                return line[: m.start()] + new_comment + line[m.end() :]

    ns = _line_tag_namespace(line, default_namespace=default_namespace)
    return line.rstrip() + f" <!-- {ns}:id {todo_id} -->"


def _todo_id_from_checkbox_line(line: str) -> str | None:
    """Extract or compute a stable todo id from a checkbox line."""

    m = CHECKBOX_RE.match(line)
    if not m:
        return None
    text_with_comments = m.group("text").rstrip()
    explicit = _extract_yta_id_from_line(text_with_comments)
    if explicit:
        return explicit
    text = _strip_html_comments(text_with_comments).strip()
    if not text:
        return None
    return compute_stable_todo_id(text)

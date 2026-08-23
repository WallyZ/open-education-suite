"""Dependency-free Markdown format guard.

Check-only by default. ``--fix`` applies conservative formatting repairs while
preserving fenced and indented code, inline code, raw HTML, frontmatter, UTF-8
BOMs, and the file's dominant newline style.

Rules:
  - MD009: trailing whitespace (exactly two hard-break spaces are preserved)
  - MD010: tabs outside protected Markdown regions
  - MD012: multiple consecutive blank lines
  - MD018/MD019: ATX headings use exactly one separating space (MD018 check-only)
  - MD022: top-level ATX headings are surrounded by blank lines
  - MD027: blockquote markers use one separating space where safely fixable
  - MD030: list markers use one separating space
  - MD031: top-level fenced code blocks are surrounded by blank lines
  - MD032: top-level lists start after a blank line
  - MD034: bare HTTP(S) URLs use Markdown autolinks (``<https://...>``)
  - MD040: fenced code blocks declare an info string (check-only)
  - MD042: inline links and images have non-empty targets (check-only)
  - MD045: inline images have alt text (check-only)
  - MD047: files end with exactly one newline
  - Structural: strict UTF-8, terminated YAML frontmatter, balanced fences

Directory inputs skip generated, vendored, cache, environment, and archive
trees. Explicit files under those trees are skipped as well. The guard is
designed for changed-file enforcement so existing repository debt can be
adopted without a mass rewrite.
"""

from __future__ import annotations

import argparse
import codecs
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Optional
from urllib.parse import urlsplit


_IGNORED_DIR_NAMES = {
    ".git",
    ".codex-cache",
    ".mypy_cache",
    ".pytest_cache",
    ".ruff_cache",
    ".tox",
    ".venv",
    "__pycache__",
    "archive",
    "build",
    "coverage",
    "dist",
    "frontend/node_modules",
    "lifeai_env",
    "node_modules",
    "vendor",
    "venv",
}
_FENCE_RE = re.compile(
    r"^(?P<indent>[ \t]*)(?P<fence>`{3,}|~{3,})(?P<rest>.*)$"
)
_ATX_HEADING_RE = re.compile(
    r"^(?P<indent> {0,3})(?P<marks>#{1,6})(?P<spacing>[ \t]*)(?P<title>.*)$"
)
_UNORDERED_LIST_RE = re.compile(r"^(?P<indent> {0,3})[-+*][ \t]+\S")
_ORDERED_LIST_RE = re.compile(
    r"^(?P<indent> {0,3})(?P<number>\d{1,9})[.)][ \t]+\S"
)
_THEMATIC_BREAK_RE = re.compile(
    r"^ {0,3}(?:(?:\*[ \t]*){3,}|(?:-[ \t]*){3,}|(?:_[ \t]*){3,})$"
)
_REFERENCE_DEFINITION_RE = re.compile(r"^ {0,3}\[[^\]]+\]:[ \t]+\S")
_ANGLE_SPAN_RE = re.compile(r"<[^>\n]+>")
_BARE_URL_RE = re.compile(r"https?://[^\s<>`]+", re.IGNORECASE)
_INDENTED_CODE_RE = re.compile(r"^(?: {4,}|\t)")
_RAW_HTML_LITERAL_OPEN_RE = re.compile(
    r"^ {0,3}<(?P<tag>pre|script|style|textarea)(?:\s|>)", re.IGNORECASE
)
_RAW_HTML_BLOCK_TAG_RE = re.compile(
    r"^ {0,3}</?(?:address|article|aside|base|basefont|blockquote|body|caption|"
    r"center|col|colgroup|dd|details|dialog|dir|div|dl|dt|fieldset|figcaption|"
    r"figure|footer|form|frame|frameset|h[1-6]|head|header|hr|html|iframe|legend|"
    r"li|link|main|menu|menuitem|nav|noframes|ol|optgroup|option|p|param|search|"
    r"section|summary|table|tbody|td|tfoot|th|thead|title|tr|track|ul)(?:\s|/?>|$)",
    re.IGNORECASE,
)
_RAW_HTML_COMPLETE_TAG_RE = re.compile(
    r"^ {0,3}</?[A-Za-z][A-Za-z0-9-]*(?:\s[^<>]*?)?/?>[ \t]*$"
)
_LIST_MARKER_SPACING_RE = re.compile(
    r"^(?P<indent> {0,3})(?P<marker>(?:[-+*]|\d{1,9}[.)]))"
    r"(?P<spacing>[ \t]+)(?P<body>\S.*)$"
)


@dataclass(frozen=True, slots=True)
class Issue:
    kind: str
    message: str
    line: Optional[int] = None


@dataclass(slots=True)
class FileResult:
    path: Path
    issues: list[Issue]
    fixed: bool = False
    changed: bool = False
    skipped: bool = False


@dataclass(frozen=True, slots=True)
class FenceBlock:
    start: int
    end: int | None
    indent: str


@dataclass(frozen=True, slots=True)
class InlineLink:
    start: int
    end: int
    is_image: bool
    label: str
    target: str


def _path_is_ignored(path: Path) -> bool:
    folded_parts = [part.casefold() for part in path.parts]
    for index, part in enumerate(folded_parts):
        if part in _IGNORED_DIR_NAMES:
            return True
        if (
            index + 1 < len(folded_parts)
            and f"{part}/{folded_parts[index + 1]}" in _IGNORED_DIR_NAMES
        ):
            return True
    return False


def _iter_md_files(inputs: list[str]) -> list[Path]:
    found: list[Path] = []
    for raw in inputs:
        path = Path(raw)
        if path.is_dir():
            found.extend(
                candidate
                for candidate in path.rglob("*.md")
                if candidate.is_file() and not _path_is_ignored(candidate)
            )
        elif any(character in raw for character in "*?["):
            found.extend(
                candidate
                for candidate in Path().glob(raw)
                if candidate.is_file()
                and candidate.suffix.casefold() == ".md"
                and not _path_is_ignored(candidate)
            )
        elif not _path_is_ignored(path):
            found.append(path)

    unique: dict[str, Path] = {}
    for path in found:
        key = str(path.resolve()) if path.exists() else str(path)
        unique.setdefault(key.casefold(), path)
    return sorted(unique.values(), key=lambda candidate: str(candidate).casefold())


def _detect_preferred_newline(text: str) -> str:
    crlf_count = text.count("\r\n")
    lf_count = text.count("\n") - crlf_count
    return "\r\n" if crlf_count > lf_count else "\n"


def _frontmatter_lines(lines: list[str]) -> tuple[set[int], list[Issue]]:
    if not lines or lines[0].lstrip("\ufeff").strip() != "---":
        return set(), []
    for index in range(1, len(lines)):
        if lines[index].strip() in {"---", "..."}:
            return set(range(index + 1)), []
    return set(range(len(lines))), [
        Issue(
            "frontmatter",
            "YAML frontmatter is missing a terminating '---' or '...'.",
            1,
        )
    ]


def _fence_lines(
    lines: list[str], frontmatter: set[int]
) -> tuple[set[int], list[FenceBlock], list[Issue]]:
    protected: set[int] = set()
    blocks: list[FenceBlock] = []
    opener_index: int | None = None
    opener_character: str | None = None
    opener_length = 0
    opener_indent = ""
    issues: list[Issue] = []

    for index, line in enumerate(lines):
        if index in frontmatter:
            continue
        if opener_index is None:
            match = _FENCE_RE.match(line)
            if (
                match is None
                or len(match.group("indent").expandtabs(4)) > 3
            ):
                continue
            opener = match.group("fence")
            if opener.startswith("`") and "`" in match.group("rest"):
                continue
            opener_index = index
            opener_character = opener[0]
            opener_length = len(opener)
            opener_indent = match.group("indent")
            protected.add(index)
            if not match.group("rest").strip():
                issues.append(
                    Issue(
                        "MD040",
                        "Fenced code blocks should declare an info string.",
                        index + 1,
                    )
                )
            continue

        protected.add(index)
        match = _FENCE_RE.match(line)
        if match is None:
            continue
        candidate = match.group("fence")
        if (
            candidate[0] == opener_character
            and len(candidate) >= opener_length
            and not match.group("rest").strip()
        ):
            blocks.append(FenceBlock(opener_index, index, opener_indent))
            opener_index = None
            opener_character = None
            opener_length = 0
            opener_indent = ""

    if opener_index is not None:
        protected.update(range(opener_index, len(lines)))
        blocks.append(FenceBlock(opener_index, None, opener_indent))
        issues.append(
            Issue(
                "fence",
                "Unterminated fenced code block (missing closing fence).",
                opener_index + 1,
            )
        )
    return protected, blocks, issues


def _blockquote_content_offset(line: str) -> int | None:
    """Return the content offset after a valid leading blockquote marker chain."""

    index = len(line) - len(line.lstrip(" "))
    if index > 3 or index >= len(line) or line[index] != ">":
        return None
    while index < len(line) and line[index] == ">":
        index += 1
        if index < len(line) and line[index] == " ":
            index += 1
        if index >= len(line) or line[index] != ">":
            break
    return index


def _indented_code_lines(lines: list[str], protected: set[int]) -> set[int]:
    """Conservatively protect top-level and blockquoted indented code runs."""

    code_lines: set[int] = set()
    in_code = False
    for index, line in enumerate(lines):
        if index in protected:
            in_code = False
            continue
        quote_offset = _blockquote_content_offset(line)
        content = line[quote_offset:] if quote_offset is not None else line
        is_indented = _INDENTED_CODE_RE.match(content) is not None
        if is_indented:
            code_lines.add(index)
            in_code = True
        elif in_code and _is_blank(line):
            code_lines.add(index)
        else:
            in_code = False
    return code_lines


def _raw_html_lines(lines: list[str], protected: set[int]) -> set[int]:
    html_lines: set[int] = set()
    state: str | None = None
    literal_tag: str | None = None

    def closes(active_state: str, line: str) -> bool:
        if active_state == "comment":
            return "-->" in line
        if active_state == "processing":
            return "?>" in line
        if active_state == "declaration":
            return ">" in line
        if active_state == "cdata":
            return "]]>" in line
        if active_state == "literal" and literal_tag is not None:
            return re.search(rf"</{re.escape(literal_tag)}>", line, re.IGNORECASE) is not None
        return False

    for index, line in enumerate(lines):
        if state == "blank":
            if _is_blank(line):
                state = None
            else:
                html_lines.add(index)
            continue
        if state is not None:
            html_lines.add(index)
            if closes(state, line):
                state = None
                literal_tag = None
            continue
        stripped = line.lstrip()
        if index in protected or len(line) - len(stripped) > 3:
            continue
        if stripped.startswith("<!--"):
            html_lines.add(index)
            if "-->" not in line:
                state = "comment"
        elif stripped.startswith("<?"):
            html_lines.add(index)
            if "?>" not in line:
                state = "processing"
        elif stripped.startswith("<![CDATA["):
            html_lines.add(index)
            if "]]>" not in line:
                state = "cdata"
        elif re.match(r"^<![A-Z]", stripped):
            html_lines.add(index)
            if ">" not in line:
                state = "declaration"
        else:
            literal = _RAW_HTML_LITERAL_OPEN_RE.match(line)
            if literal is not None:
                html_lines.add(index)
                literal_tag = literal.group("tag")
                if re.search(
                    rf"</{re.escape(literal_tag)}>", line, re.IGNORECASE
                ) is None:
                    state = "literal"
            elif _RAW_HTML_BLOCK_TAG_RE.match(line) or _RAW_HTML_COMPLETE_TAG_RE.match(line):
                html_lines.add(index)
                state = "blank"
    return html_lines


def _code_spans(line: str) -> list[tuple[int, int]]:
    spans: list[tuple[int, int]] = []
    index = 0
    while index < len(line):
        if line[index] != "`":
            index += 1
            continue
        end_of_run = index
        while end_of_run < len(line) and line[end_of_run] == "`":
            end_of_run += 1
        delimiter = line[index:end_of_run]
        close_index = line.find(delimiter, end_of_run)
        if close_index < 0:
            index = end_of_run
            continue
        spans.append((index, close_index + len(delimiter)))
        index = close_index + len(delimiter)
    return spans


def _find_balanced_end(
    line: str, start: int, opener: str, closer: str
) -> int | None:
    depth = 1
    index = start
    while index < len(line):
        character = line[index]
        if character == "\\":
            index += 2
            continue
        if character == opener:
            depth += 1
        elif character == closer:
            depth -= 1
            if depth == 0:
                return index
        index += 1
    return None


def _inline_links(line: str) -> list[InlineLink]:
    """Parse inline links/images enough to protect balanced destinations safely."""

    code_spans = _code_spans(line)
    links: list[InlineLink] = []
    index = 0
    while index < len(line):
        is_image = line.startswith("![", index)
        if is_image:
            label_start = index + 2
        elif line[index] == "[":
            label_start = index + 1
        else:
            index += 1
            continue
        start = index
        if _overlaps((start, label_start), code_spans):
            index = label_start
            continue
        label_end = _find_balanced_end(line, label_start, "[", "]")
        if label_end is None or label_end + 1 >= len(line) or line[label_end + 1] != "(":
            index = label_start
            continue
        target_start = label_end + 2
        target_end = _find_balanced_end(line, target_start, "(", ")")
        if target_end is None:
            index = label_start
            continue
        end = target_end + 1
        if _overlaps((start, end), code_spans):
            index = end
            continue
        links.append(
            InlineLink(
                start=start,
                end=end,
                is_image=is_image,
                label=line[label_start:label_end],
                target=line[target_start:target_end],
            )
        )
        index = end
    return links


def _inline_protected_spans(line: str) -> list[tuple[int, int]]:
    if _REFERENCE_DEFINITION_RE.match(line):
        return [(0, len(line))]
    spans = _code_spans(line)
    spans.extend((link.start, link.end) for link in _inline_links(line))
    spans.extend(match.span() for match in _ANGLE_SPAN_RE.finditer(line))
    return spans


def _overlaps(span: tuple[int, int], protected: Iterable[tuple[int, int]]) -> bool:
    start, end = span
    return any(start < protected_end and end > protected_start for protected_start, protected_end in protected)


def _trim_url(candidate: str) -> str:
    candidate = candidate.rstrip(".,;:!?\"'\u2019\u201d")
    pairs = (("(", ")"), ("[", "]"), ("{", "}"))
    changed = True
    while candidate and changed:
        changed = False
        for opener, closer in pairs:
            if candidate.endswith(closer) and candidate.count(closer) > candidate.count(opener):
                candidate = candidate[:-1]
                changed = True
    return candidate


def _is_valid_http_url(candidate: str) -> bool:
    try:
        parsed = urlsplit(candidate)
        hostname = parsed.hostname
        parsed.port
    except ValueError:
        return False
    if (
        parsed.scheme.casefold() not in {"http", "https"}
        or not parsed.netloc
        or not hostname
        or any(character.isspace() for character in candidate)
    ):
        return False
    normalized_host = hostname.rstrip(".")
    if not normalized_host:
        return False
    if ":" not in normalized_host:
        labels = normalized_host.split(".")
        if any(
            not label
            or len(label) > 63
            or not label[0].isalnum()
            or not label[-1].isalnum()
            or any(not (character.isalnum() or character == "-") for character in label)
            for label in labels
        ):
            return False
    return True


def _bare_urls(line: str) -> list[tuple[int, int, str]]:
    protected = _inline_protected_spans(line)
    results: list[tuple[int, int, str]] = []
    for match in _BARE_URL_RE.finditer(line):
        if _overlaps(match.span(), protected):
            continue
        candidate = _trim_url(match.group(0))
        if (
            match.start() >= 2
            and line[match.start() - 2 : match.start()] == "**"
            and candidate.endswith("**")
        ):
            candidate = candidate[:-2]
        if not candidate or not _is_valid_http_url(candidate):
            continue
        results.append((match.start(), match.start() + len(candidate), candidate))
    return results


def _is_blank(line: str) -> bool:
    return not line.strip()


def _normalize_blockquote_spacing(line: str, *, fix: bool) -> tuple[str, int]:
    leading = len(line) - len(line.lstrip(" "))
    if leading > 3:
        return line, 0
    index = leading
    replacements: list[tuple[int, int]] = []
    issue_count = 0
    while index < len(line) and line[index] == ">":
        index += 1
        spacing_start = index
        while index < len(line) and line[index] in " \t":
            index += 1
        spacing = line[spacing_start:index]
        has_content = index < len(line)
        if has_content and spacing != " ":
            issue_count += 1
            next_is_marker = index < len(line) and line[index] == ">"
            safe_to_fix = not spacing or (
                "\t" not in spacing and (len(spacing) <= 3 or next_is_marker)
            )
            if fix and safe_to_fix:
                replacements.append((spacing_start, index))
        if index >= len(line) or line[index] != ">":
            break
    output = line
    for start, end in reversed(replacements):
        output = f"{output[:start]} {output[end:]}"
    return output, issue_count


def _normalize_list_marker_spacing(line: str, *, fix: bool) -> tuple[str, bool]:
    if _THEMATIC_BREAK_RE.match(line):
        return line, False
    match = _LIST_MARKER_SPACING_RE.match(line)
    if match is None or match.group("spacing") == " ":
        return line, False
    if not fix:
        return line, True
    return (
        match.group("indent")
        + match.group("marker")
        + " "
        + match.group("body"),
        True,
    )


def _inline_link_issues(line: str, line_number: int) -> list[Issue]:
    issues: list[Issue] = []
    for link in _inline_links(line):
        target = link.target.strip()
        target_is_empty = not target or (
            target.startswith("<")
            and target.endswith(">")
            and not target[1:-1].strip()
        )
        if target_is_empty:
            issues.append(
                Issue(
                    "MD042",
                    "Inline links and images require a non-empty target.",
                    line_number,
                )
            )
        if link.is_image and not link.label.strip():
            issues.append(
                Issue("MD045", "Inline images require alt text.", line_number)
            )
    return issues


def _top_level_list_item(line: str) -> bool:
    if _THEMATIC_BREAK_RE.match(line):
        return False
    if _UNORDERED_LIST_RE.match(line):
        return True
    ordered = _ORDERED_LIST_RE.match(line)
    return ordered is not None


def _list_continues_before(lines: list[str], index: int) -> bool:
    for previous_index in range(index - 1, -1, -1):
        previous = lines[previous_index]
        if _is_blank(previous):
            return False
        if _top_level_list_item(previous):
            return True
        leading_spaces = len(previous) - len(previous.lstrip(" "))
        if leading_spaces >= 2 or previous.lstrip().startswith(">"):
            continue
        return False
    return False


def _structural_spacing(
    lines: list[str],
    protected: set[int],
    blocks: list[FenceBlock],
) -> tuple[set[int], set[int], list[Issue]]:
    insert_before: set[int] = set()
    insert_after: set[int] = set()
    issues: list[Issue] = []

    for index, line in enumerate(lines):
        if index in protected:
            continue
        heading = _ATX_HEADING_RE.match(line)
        if heading is not None:
            title = heading.group("title")
            spacing = heading.group("spacing")
            if title and spacing != " ":
                rule = "MD018" if not spacing else "MD019"
                issues.append(
                    Issue(rule, "ATX headings require exactly one separating space.", index + 1)
                )
            is_valid_heading = not title or bool(spacing)
            if is_valid_heading:
                if index > 0 and not _is_blank(lines[index - 1]):
                    insert_before.add(index)
                    issues.append(
                        Issue("MD022", "Headings must be surrounded by blank lines.", index + 1)
                    )
                if index + 1 < len(lines) and not _is_blank(lines[index + 1]):
                    insert_after.add(index)
                    issues.append(
                        Issue("MD022", "Headings must be surrounded by blank lines.", index + 1)
                    )

        if _top_level_list_item(line) and not _list_continues_before(lines, index):
            if index > 0 and not _is_blank(lines[index - 1]):
                insert_before.add(index)
                issues.append(
                    Issue("MD032", "Lists must start after a blank line.", index + 1)
                )

    for block in blocks:
        if len(block.indent.expandtabs(4)) > 3:
            continue
        if block.start > 0 and not _is_blank(lines[block.start - 1]):
            insert_before.add(block.start)
            issues.append(
                Issue("MD031", "Fenced code blocks must be surrounded by blank lines.", block.start + 1)
            )
        if (
            block.end is not None
            and block.end + 1 < len(lines)
            and not _is_blank(lines[block.end + 1])
        ):
            insert_after.add(block.end)
            issues.append(
                Issue("MD031", "Fenced code blocks must be surrounded by blank lines.", block.end + 1)
            )
    return insert_before, insert_after, issues


def _replace_bare_urls(line: str, matches: list[tuple[int, int, str]]) -> str:
    output = line
    for start, end, url in reversed(matches):
        output = f"{output[:start]}<{url}>{output[end:]}"
    return output


def _scan_and_fix_text(
    text: str, *, fix: bool, tab_width: int
) -> tuple[str, list[Issue], bool]:
    preferred_newline = _detect_preferred_newline(text)
    lines = text.splitlines()
    frontmatter, frontmatter_issues = _frontmatter_lines(lines)
    fenced, blocks, fence_issues = _fence_lines(lines, frontmatter)
    protected = frontmatter | fenced
    protected |= _indented_code_lines(lines, protected)
    protected |= _raw_html_lines(lines, protected)
    structural_errors = frontmatter_issues + fence_issues
    insert_before, insert_after, spacing_issues = _structural_spacing(
        lines, protected, blocks
    )
    issues = list(structural_errors) + spacing_issues
    transformed: list[str] = []
    changed = False

    consecutive_blank_lines = 0
    for index, original in enumerate(lines):
        line = original
        if index not in protected:
            if "\t" in line:
                issues.append(Issue("MD010", "Tab outside a protected Markdown region.", index + 1))
                if fix:
                    line = line.expandtabs(tab_width)

            trailing = re.search(r"[ \t]+$", line)
            if trailing is not None and trailing.group(0) != "  ":
                issues.append(Issue("MD009", "Trailing whitespace.", index + 1))
                if fix:
                    base = line[: trailing.start()]
                    preserve_break = len(trailing.group(0).replace("\t", "")) >= 2
                    line = base + ("  " if preserve_break else "")

            heading = _ATX_HEADING_RE.match(line)
            if (
                heading is not None
                and heading.group("title")
                and heading.group("spacing")
                and heading.group("spacing") != " "
            ):
                if fix:
                    line = (
                        heading.group("indent")
                        + heading.group("marks")
                        + " "
                        + heading.group("title")
                    )

            line, blockquote_issue_count = _normalize_blockquote_spacing(
                line, fix=fix
            )
            for _ in range(blockquote_issue_count):
                issues.append(
                    Issue(
                        "MD027",
                        "Blockquote markers should use one separating space.",
                        index + 1,
                    )
                )

            line, list_spacing_issue = _normalize_list_marker_spacing(
                line, fix=fix
            )
            if list_spacing_issue:
                issues.append(
                    Issue(
                        "MD030",
                        "List markers should use one separating space.",
                        index + 1,
                    )
                )

            issues.extend(_inline_link_issues(line, index + 1))

            url_matches = _bare_urls(line)
            for _, _, _ in url_matches:
                issues.append(
                    Issue("MD034", "Bare URL must use a Markdown autolink.", index + 1)
                )
            if fix and url_matches:
                line = _replace_bare_urls(line, url_matches)

        if fix and index in insert_before and transformed and not _is_blank(transformed[-1]):
            transformed.append("")
            changed = True

        if _is_blank(line) and index not in protected:
            consecutive_blank_lines += 1
            if consecutive_blank_lines > 1:
                issues.append(
                    Issue("MD012", "Multiple consecutive blank lines.", index + 1)
                )
                if fix:
                    changed = True
                    continue
        else:
            consecutive_blank_lines = 0

        transformed.append(line)
        if line != original:
            changed = True

        if fix and index in insert_after:
            following_is_blank = (
                index + 1 < len(lines) and _is_blank(lines[index + 1])
            )
            if not following_is_blank:
                transformed.append("")
                changed = True

    while transformed and _is_blank(transformed[-1]):
        transformed.pop()
        changed = True

    newline_suffix = ""
    if text:
        without_newlines = text.rstrip("\r\n")
        newline_suffix = text[len(without_newlines) :]
        if newline_suffix != preferred_newline:
            issues.append(Issue("MD047", "File must end with exactly one newline."))
    if "\r\n" in text and "\n" in text.replace("\r\n", ""):
        issues.append(Issue("newline_style", "Mixed newline styles."))

    if not fix:
        return text, issues, False

    new_text = preferred_newline.join(transformed)
    if new_text:
        new_text += preferred_newline
    if new_text != text:
        changed = True
    return new_text, issues, changed


def _read_utf8(path: Path) -> tuple[str | None, bool, Issue | None]:
    try:
        raw = path.read_bytes()
    except OSError as exc:
        return None, False, Issue("input", f"Unable to read file: {exc}")
    has_bom = raw.startswith(codecs.BOM_UTF8)
    payload = raw[len(codecs.BOM_UTF8) :] if has_bom else raw
    try:
        return payload.decode("utf-8", errors="strict"), has_bom, None
    except UnicodeDecodeError as exc:
        return None, has_bom, Issue("encoding", f"File is not strict UTF-8: {exc}")


def _process_file(path: Path, *, fix: bool, tab_width: int) -> FileResult:
    if path.suffix.casefold() != ".md":
        return FileResult(path, [Issue("input", "Not a Markdown file (.md).")])
    if not path.exists():
        return FileResult(path, [Issue("input", "File does not exist.")])
    if _path_is_ignored(path):
        return FileResult(path, [], skipped=True)

    text, has_bom, read_issue = _read_utf8(path)
    if read_issue is not None or text is None:
        return FileResult(path, [read_issue or Issue("input", "Unable to read file.")])

    new_text, issues, changed = _scan_and_fix_text(
        text, fix=fix, tab_width=tab_width
    )
    structural_error = any(issue.kind in {"encoding", "frontmatter", "fence"} for issue in issues)
    if fix and changed and not structural_error:
        payload = new_text.encode("utf-8")
        if has_bom:
            payload = codecs.BOM_UTF8 + payload
        path.write_bytes(payload)  # safe-io: ignore - explicit formatter target
        _, remaining_issues, _ = _scan_and_fix_text(
            new_text, fix=False, tab_width=tab_width
        )
        return FileResult(
            path,
            remaining_issues,
            fixed=True,
            changed=True,
        )
    return FileResult(path, issues, changed=changed)


def _print_results(results: list[FileResult]) -> int:
    failed = False
    for result in results:
        if result.skipped:
            print(f"[SKIP] {result.path}")
            continue
        if result.issues:
            status = "FAIL"
            failed = True
        else:
            status = "OK"
        fixed = " (fixed)" if result.fixed else ""
        print(f"[{status}]{fixed} {result.path}")
        for issue in result.issues:
            location = f":{issue.line}" if issue.line is not None else ""
            print(f"  - {issue.kind}{location}: {issue.message}")
    return 1 if failed else 0


def _self_test() -> int:
    cases = (
        (
            "urls-and-list",
            "Sources: https://example.test/a, https://example.test/b?q=1.\n- item\n",
            "Sources: <https://example.test/a>, <https://example.test/b?q=1>.\n\n- item\n",
        ),
        (
            "bold-wrapped-url",
            "Source: **https://example.test**\n",
            "Source: **<https://example.test>**\n",
        ),
        (
            "quoted-url-and-validation",
            'Sources: "https://example.test/path" and https://.\n',
            'Sources: "<https://example.test/path>" and https://.\n',
        ),
        (
            "protected-balanced-links",
            "`https://code.test` [link](https://link.test/a_(b)) <https://auto.test>\n",
            "`https://code.test` [link](https://link.test/a_(b)) <https://auto.test>\n",
        ),
        (
            "heading-safe-spacing-and-blanks",
            "#   Title\n\n\nParagraph\n",
            "# Title\n\nParagraph\n",
        ),
        (
            "crlf",
            "Intro:\r\n- item\r\n",
            "Intro:\r\n\r\n- item\r\n",
        ),
        (
            "hard-break",
            "Line with break  \nNext\n",
            "Line with break  \nNext\n",
        ),
        (
            "fenced-code",
            "```text\nhttps://inside.test\n```\n",
            "```text\nhttps://inside.test\n```\n",
        ),
        (
            "indented-code",
            "    https://inside.test\n\n    #not-a-heading\n",
            "    https://inside.test\n\n    #not-a-heading\n",
        ),
        (
            "blockquote-indented-code",
            ">     https://inside.test\n",
            ">     https://inside.test\n",
        ),
        (
            "raw-html-blocks",
            "<div>\nhttps://inside.test\n</div>\n\n<!--\nhttps://comment.test\n-->\n",
            "<div>\nhttps://inside.test\n</div>\n\n<!--\nhttps://comment.test\n-->\n",
        ),
        (
            "raw-html-declarations",
            "<!DOCTYPE html>\n\n<?processor\nhttps://processing.test\n?>\n\n<![CDATA[\nhttps://cdata.test\n]]>\n",
            "<!DOCTYPE html>\n\n<?processor\nhttps://processing.test\n?>\n\n<![CDATA[\nhttps://cdata.test\n]]>\n",
        ),
        (
            "blockquote-spacing",
            ">quote\n>  quote\n>>   nested\n",
            "> quote\n> quote\n> > nested\n",
        ),
        (
            "list-marker-spacing",
            "-   first\n1.  second\n",
            "- first\n1. second\n",
        ),
        (
            "lazy-list-continuation",
            "Intro:\n- item\nlazy continuation\n",
            "Intro:\n\n- item\nlazy continuation\n",
        ),
    )
    failures: list[str] = []
    for name, source, expected in cases:
        fixed, _, _ = _scan_and_fix_text(source, fix=True, tab_width=4)
        if fixed != expected:
            failures.append(f"{name}: unexpected fixed output {fixed!r}")
            continue
        second, remaining, changed = _scan_and_fix_text(
            fixed, fix=True, tab_width=4
        )
        if second != fixed or remaining or changed:
            failures.append(
                f"{name}: fix is not idempotent or leaves issues: {remaining!r}"
            )

    long_frontmatter = "---\n" + ("key: value\n" * 450) + "---\nBody\n"
    fixed_frontmatter, frontmatter_issues, frontmatter_changed = _scan_and_fix_text(
        long_frontmatter, fix=True, tab_width=4
    )
    if (
        fixed_frontmatter != long_frontmatter
        or frontmatter_issues
        or frontmatter_changed
    ):
        failures.append(
            "long-frontmatter: valid frontmatter beyond 400 lines was not preserved"
        )

    check_only_cases = (
        ("missing-heading-space", "#hashtag\n", "MD018"),
        ("missing-fence-info", "```\ncode\n```\n", "MD040"),
        ("empty-link-target", "[label]()\n", "MD042"),
        ("missing-image-alt", "![](image.png)\n", "MD045"),
    )
    for name, source, expected_issue in check_only_cases:
        fixed, issues, changed = _scan_and_fix_text(source, fix=True, tab_width=4)
        if fixed != source or changed:
            failures.append(f"{name}: check-only rule modified source")
        if not any(issue.kind == expected_issue for issue in issues):
            failures.append(f"{name}: missing expected {expected_issue} issue")

    _, unclosed_issues, _ = _scan_and_fix_text(
        "```text\nunterminated\n", fix=False, tab_width=4
    )
    if not any(issue.kind == "fence" for issue in unclosed_issues):
        failures.append("unclosed-fence: structural error was not reported")

    if failures:
        print("Markdown format guard self-test failed:")
        for failure in failures:
            print(f"- {failure}")
        return 1
    print("Markdown format guard self-test passed.")
    return 0


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Markdown format guard (check/fix).")
    mode = parser.add_mutually_exclusive_group(required=False)
    mode.add_argument("--check", action="store_true", help="Check only (default).")
    mode.add_argument("--fix", action="store_true", help="Apply conservative fixes.")
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="Run dependency-free regression cases.",
    )
    parser.add_argument(
        "--tab-width", type=int, default=4, help="Spaces per tab when fixing."
    )
    parser.add_argument("paths", nargs="*", help="Markdown files, dirs, or globs.")
    args = parser.parse_args(argv)

    if args.self_test:
        if args.paths:
            parser.error("--self-test does not accept paths")
        return _self_test()
    if not args.paths:
        parser.error("at least one Markdown path is required")
    if args.tab_width < 1 or args.tab_width > 16:
        parser.error("--tab-width must be between 1 and 16")

    paths = _iter_md_files(args.paths)
    if not paths:
        print("No Markdown files found.")
        return 0
    results = [
        _process_file(path, fix=bool(args.fix), tab_width=args.tab_width)
        for path in paths
    ]
    result = _print_results(results)
    if result != 0 and not args.fix:
        print("\nHint: re-run with --fix to apply conservative Markdown repairs.")
    return result


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

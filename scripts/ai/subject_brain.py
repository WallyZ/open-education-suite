#!/usr/bin/env python3
"""Validate, index, and query local Open Education subject brains.

The runtime is intentionally retrieval-only. It prepares cited context for a
teacher model; it does not generate answers or mutate learner state.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import re
import sqlite3
import sys
import zipfile
from html.parser import HTMLParser
from pathlib import Path
from typing import Any, Iterable
from xml.etree import ElementTree


BRAIN_SCHEMA = "open-education/subject-brain/v1"
CORPUS_SCHEMA = "open-education/subject-brain-corpus/v1"
REGISTRY_SCHEMA = "open-education/subject-brain-registry/v1"
QUERY_SCHEMA = "open-education/subject-brain-query-result/v1"
INDEX_SCHEMA = "open-education/subject-brain-index/v1"
LOCATOR_SCHEMA = "open-education/subject-brain-locator/v1"
QUERY_PLAN_SCHEMA = "open-education/subject-brain-query-plan/v1"
VECTOR_ALGORITHM = "deterministic-hashed-concept-vector/v1"
VECTOR_DIMENSIONS = 256
READY_STATUSES = {"contract-ready", "starter-corpus-ready", "pilot-ready", "production-ready"}
INDEX_RIGHTS_STATUS = "approved-for-local-index"
LOCAL_ACQUISITION_STATUSES = {"local-ready", "local-pending-extraction"}
SUPPORTED_SUFFIXES = {
    ".txt", ".md", ".markdown", ".html", ".htm", ".json", ".jsonl", ".csv",
    ".tsv", ".pdf", ".docx", ".epub", ".py", ".js", ".mjs", ".cjs", ".ts",
    ".tsx", ".java", ".cs", ".c", ".h", ".cpp", ".hpp", ".rs", ".go", ".rb",
    ".php", ".ps1", ".sh", ".sql",
}
REQUIRED_LOCATOR_KINDS = {
    "page", "chapter", "section", "verse", "equation", "table", "diagram",
    "code-symbol", "dataset", "image", "audiovisual-timestamp",
}
STOP_WORDS = {
    "a", "an", "and", "are", "as", "at", "be", "by", "for", "from", "how",
    "in", "is", "it", "of", "on", "or", "that", "the", "this", "to", "what",
    "when", "where", "which", "who", "why", "with",
}
CONCEPT_EXPANSIONS = {
    "argument": ("logic", "premise", "conclusion", "reasoning", "evidence"),
    "deductive": ("logic", "validity", "premise", "conclusion", "inference"),
    "rhetoric": ("argument", "persuasion", "composition", "language"),
    "scripture": ("bible", "theology", "verse", "religious-literacy"),
    "biblical": ("bible", "theology", "scripture", "religious-literacy"),
    "memory": ("psychology", "learning-science", "retention", "development"),
    "learning": ("education", "memory", "psychology", "practice"),
    "algebra": ("mathematics", "equation", "proof", "quantitative"),
    "geometry": ("mathematics", "proof", "shape", "quantitative"),
    "physics": ("science", "engineering", "equation", "experiment"),
    "biology": ("science", "life-science", "experiment", "evidence"),
    "government": ("civics", "history", "law", "politics"),
    "constitution": ("civics", "government", "law", "history"),
    "budget": ("finance", "economics", "money", "accounting"),
    "investing": ("finance", "economics", "risk", "business"),
    "software": ("computing", "code", "programming", "computer-science"),
    "cybersecurity": ("computing", "security", "software", "digital-citizenship"),
    "nutrition": ("health", "fitness", "safety", "biology"),
    "music": ("arts", "performance", "theory", "design"),
    "leadership": ("communication", "ethics", "relationships", "conflict-resolution"),
    "marriage": ("relationships", "family", "communication", "ethics"),
    "career": ("work", "practical-life", "project-management", "consumer-skills"),
    "emergency": ("safety", "first-aid", "readiness", "practical-life"),
}
EVIDENCE_TIER_WEIGHTS = (
    (("systematic", "meta-analysis", "official", "primary-source", "peer-reviewed"), 1.0),
    (("scholarly", "academic", "reference", "textbook", "standard"), 0.85),
    (("curated", "practice-guide", "professional", "instructional"), 0.72),
)


class SubjectBrainError(RuntimeError):
    """Raised for a user-correctable contract or corpus problem."""


class UnsupportedExtraction(SubjectBrainError):
    """Raised when a local source needs an optional extractor."""


class VisibleTextParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.parts: list[str] = []
        self.hidden_depth = 0

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag in {"script", "style", "noscript", "svg"}:
            self.hidden_depth += 1
        elif tag in {"p", "div", "section", "article", "h1", "h2", "h3", "h4", "li", "br", "tr"}:
            self.parts.append("\n")

    def handle_endtag(self, tag: str) -> None:
        if tag in {"script", "style", "noscript", "svg"} and self.hidden_depth:
            self.hidden_depth -= 1
        elif tag in {"p", "div", "section", "article", "h1", "h2", "h3", "h4", "li", "tr"}:
            self.parts.append("\n")

    def handle_data(self, data: str) -> None:
        if not self.hidden_depth:
            self.parts.append(data)

    def text(self) -> str:
        return "".join(self.parts)


def load_json(path: Path) -> dict[str, Any]:
    try:
        with path.open("r", encoding="utf-8") as handle:
            value = json.load(handle)
    except FileNotFoundError as exc:
        raise SubjectBrainError(f"Missing JSON file: {path}") from exc
    except json.JSONDecodeError as exc:
        raise SubjectBrainError(f"Invalid JSON in {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise SubjectBrainError(f"Expected a JSON object in {path}")
    return value


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def relative_file(root: Path, raw_path: str, label: str) -> Path:
    if not raw_path or Path(raw_path).is_absolute() or ":" in raw_path:
        raise SubjectBrainError(f"{label} must be a non-empty relative path")
    root = root.resolve()
    candidate = (root / raw_path).resolve()
    try:
        candidate.relative_to(root)
    except ValueError as exc:
        raise SubjectBrainError(f"{label} escapes the subject-brain root: {raw_path}") from exc
    return candidate


def workspace_path(registry_dir: Path, raw_path: str, label: str) -> Path:
    """Resolve a registry path while allowing sibling repos under one workspace."""
    if not raw_path or Path(raw_path).is_absolute() or ":" in raw_path:
        raise SubjectBrainError(f"{label} must be a non-empty relative path")
    workspace_root = registry_dir.resolve().parent
    candidate = (registry_dir / raw_path).resolve()
    try:
        candidate.relative_to(workspace_root)
    except ValueError as exc:
        raise SubjectBrainError(f"{label} escapes the shared workspace: {raw_path}") from exc
    return candidate


def require(condition: bool, message: str, errors: list[str]) -> None:
    if not condition:
        errors.append(message)


def validate_brain(brain_root: Path) -> tuple[dict[str, Any], dict[str, Any], list[str]]:
    brain_root = brain_root.resolve()
    manifest_path = brain_root / "subject-brain.json"
    manifest = load_json(manifest_path)
    errors: list[str] = []

    require(manifest.get("schemaVersion") == BRAIN_SCHEMA, f"{manifest_path}: wrong schemaVersion", errors)
    brain_id = str(manifest.get("brainId") or "")
    require(bool(re.fullmatch(r"[a-z0-9][a-z0-9-]*", brain_id)), f"{manifest_path}: invalid brainId", errors)
    require(manifest.get("role") == "specialist-subject-brain", f"{manifest_path}: role must be specialist-subject-brain", errors)
    require(manifest.get("status") in READY_STATUSES, f"{manifest_path}: invalid status", errors)
    require(bool(manifest.get("title")), f"{manifest_path}: missing title", errors)
    require(bool(manifest.get("description")), f"{manifest_path}: missing description", errors)
    require(bool(manifest.get("subjectTags")), f"{manifest_path}: subjectTags must not be empty", errors)
    require(bool(manifest.get("gradeBands")), f"{manifest_path}: gradeBands must not be empty", errors)

    capabilities = manifest.get("capabilities") or {}
    require(bool(capabilities.get("ingestionFormats")), f"{manifest_path}: missing ingestionFormats", errors)
    require("lexical-fts" in (capabilities.get("retrievalModes") or []), f"{manifest_path}: lexical-fts is required", errors)
    require(bool(capabilities.get("outputTypes")), f"{manifest_path}: missing outputTypes", errors)

    paths = manifest.get("paths") or {}
    for key in ("corpusManifest", "evidencePolicy", "corpusPlan"):
        try:
            path = relative_file(brain_root, str(paths.get(key) or ""), f"paths.{key}")
            require(path.is_file(), f"{manifest_path}: missing paths.{key} file {path}", errors)
        except SubjectBrainError as exc:
            errors.append(str(exc))

    rights_policy = manifest.get("rightsPolicy") or {}
    require(rights_policy.get("requiredRightsStatus") == INDEX_RIGHTS_STATUS, f"{manifest_path}: requiredRightsStatus must block unknown rights", errors)
    require(rights_policy.get("checksumRequired") is True, f"{manifest_path}: checksums must be required", errors)
    require(rights_policy.get("unknownRightsBehavior") == "block-indexing", f"{manifest_path}: unknown rights must block indexing", errors)

    query_policy = manifest.get("queryPolicy") or {}
    for key in ("citationRequired", "locatorRequired", "uncertaintyRequired", "conflictDisclosureRequired"):
        require(query_policy.get(key) is True, f"{manifest_path}: queryPolicy.{key} must be true", errors)
    require(query_policy.get("answerGenerationMode") == "retrieval-context-only", f"{manifest_path}: answer generation must stay outside the brain", errors)

    safety = manifest.get("safetyPolicy") or {}
    require(safety.get("learnerPrivateDataAllowed") is False, f"{manifest_path}: learner private data must be disallowed", errors)
    require(safety.get("durableStateMutationAllowed") is False, f"{manifest_path}: durable state mutation must be disallowed", errors)
    require(safety.get("ageBandRequired") is True, f"{manifest_path}: age band must be required", errors)

    corpus_path_raw = str(paths.get("corpusManifest") or "")
    corpus_path = relative_file(brain_root, corpus_path_raw, "paths.corpusManifest")
    corpus = load_json(corpus_path)
    require(corpus.get("schemaVersion") == CORPUS_SCHEMA, f"{corpus_path}: wrong schemaVersion", errors)
    require(corpus.get("brainId") == brain_id, f"{corpus_path}: brainId does not match manifest", errors)
    require(bool(corpus.get("updatedAt")), f"{corpus_path}: missing updatedAt", errors)

    source_ids: set[str] = set()
    ready_count = 0
    for source in corpus.get("sources") or []:
        source_id = str(source.get("sourceId") or "")
        label = f"{corpus_path}:{source_id or '<missing>'}"
        require(bool(re.fullmatch(r"[a-z0-9][a-z0-9._-]*", source_id)), f"{label}: invalid sourceId", errors)
        require(source_id not in source_ids, f"{label}: duplicate sourceId", errors)
        source_ids.add(source_id)
        for key in ("title", "sourceType", "canonicalUrl", "gradeBands", "topics", "evidenceTier"):
            require(bool(source.get(key)), f"{label}: missing {key}", errors)
        require(isinstance(source.get("alternateUrls"), list), f"{label}: alternateUrls must be an array", errors)

        rights = source.get("rights") or {}
        acquisition = source.get("acquisition") or {}
        rights_status = rights.get("rightsStatus")
        acquisition_status = acquisition.get("status")
        for key in ("licenseId", "licenseUrl", "rightsStatus", "notes"):
            require(key in rights, f"{label}: rights.{key} is required", errors)
        for key in ("status", "retrievedAt", "method", "notes"):
            require(key in acquisition, f"{label}: acquisition.{key} is required", errors)

        if acquisition_status in LOCAL_ACQUISITION_STATUSES:
            local_raw = str(source.get("localPath") or "")
            checksum = str(source.get("sha256") or "")
            try:
                local_path = relative_file(brain_root, local_raw, f"{label}.localPath")
                require(local_path.is_file(), f"{label}: local file does not exist: {local_raw}", errors)
                require(bool(re.fullmatch(r"[a-f0-9]{64}", checksum)), f"{label}: sha256 must be lowercase hex", errors)
                if local_path.is_file() and re.fullmatch(r"[a-f0-9]{64}", checksum):
                    require(sha256_file(local_path) == checksum, f"{label}: sha256 mismatch", errors)
                require(local_path.suffix.lower() in SUPPORTED_SUFFIXES, f"{label}: unsupported local file type {local_path.suffix}", errors)
            except SubjectBrainError as exc:
                errors.append(str(exc))

        if acquisition_status == "local-ready":
            ready_count += 1
            require(rights_status == INDEX_RIGHTS_STATUS, f"{label}: local-ready sources require approved-for-local-index rights", errors)
        if rights_status != INDEX_RIGHTS_STATUS:
            require(acquisition_status != "local-ready", f"{label}: restricted source must not be local-ready", errors)

    require(bool(source_ids), f"{corpus_path}: sources must not be empty", errors)
    if manifest.get("status") in {"starter-corpus-ready", "pilot-ready", "production-ready"}:
        require(ready_count > 0, f"{corpus_path}: ready brain needs at least one local-ready source", errors)
    return manifest, corpus, errors


def validate_registry(registry_path: Path) -> tuple[dict[str, Any], list[str]]:
    registry_path = registry_path.resolve()
    registry = load_json(registry_path)
    errors: list[str] = []
    require(registry.get("schemaVersion") == REGISTRY_SCHEMA, f"{registry_path}: wrong schemaVersion", errors)
    require(registry.get("registryId") == "open-education-subject-brains", f"{registry_path}: wrong registryId", errors)
    routing = registry.get("routingPolicy") or {}
    for key in ("lessonContentFirst", "specialistBrainSupplementsLessonContent", "citationRequired", "conflictingSourcesMustBeDisclosed"):
        require(routing.get(key) is True, f"{registry_path}: routingPolicy.{key} must be true", errors)
    require(routing.get("durableLearnerStateMutationAllowed") is False, f"{registry_path}: brains must not mutate durable learner state", errors)

    ids: set[str] = set()
    active_count = 0
    planned_count = 0
    for entry in registry.get("brains") or []:
        brain_id = str(entry.get("brainId") or "")
        label = f"{registry_path}:{brain_id or '<missing>'}"
        require(bool(brain_id), f"{label}: missing brainId", errors)
        require(brain_id not in ids, f"{label}: duplicate brainId", errors)
        ids.add(brain_id)
        for key in ("title", "status", "subjectTags", "gradeBands", "primaryConsumers"):
            require(bool(entry.get(key)), f"{label}: missing {key}", errors)
        status = entry.get("status")
        if status == "planned":
            planned_count += 1
            require(entry.get("localPath") is None and entry.get("manifestPath") is None, f"{label}: planned brains must not claim a local manifest", errors)
            continue
        active_count += 1
        local_raw = str(entry.get("localPath") or "")
        manifest_raw = str(entry.get("manifestPath") or "")
        try:
            root = workspace_path(registry_path.parent, local_raw, f"{label}.localPath")
            require(root.is_dir(), f"{label}: localPath does not exist", errors)
            manifest_path = relative_file(root, manifest_raw, f"{label}.manifestPath")
            require(manifest_path.is_file(), f"{label}: manifest does not exist", errors)
            manifest, _corpus, brain_errors = validate_brain(root)
            errors.extend(brain_errors)
            require(manifest.get("brainId") == brain_id, f"{label}: manifest brainId mismatch", errors)
            require(manifest.get("status") == status, f"{label}: registry and manifest status differ", errors)
        except SubjectBrainError as exc:
            errors.append(str(exc))

    require(active_count >= 3, f"{registry_path}: expected at least three active specialist brains", errors)
    require(len(ids) >= 13, f"{registry_path}: thirteen-brain K-12 coverage map is incomplete", errors)
    return registry, errors


def normalize_text(text: str) -> str:
    text = text.replace("\x00", " ").replace("\r\n", "\n").replace("\r", "\n")
    text = re.sub(r"[\t\f\v ]+", " ", text)
    text = re.sub(r" *\n *", "\n", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def html_text(raw: str) -> str:
    parser = VisibleTextParser()
    parser.feed(raw)
    return normalize_text(parser.text())


def flatten_json(value: Any) -> Iterable[str]:
    if isinstance(value, dict):
        for key, item in value.items():
            yield str(key)
            yield from flatten_json(item)
    elif isinstance(value, list):
        for item in value:
            yield from flatten_json(item)
    elif value is not None:
        yield str(value)


def make_locator(kind: str, label: str, **details: Any) -> dict[str, Any]:
    value: dict[str, Any] = {
        "schemaVersion": LOCATOR_SCHEMA,
        "kind": kind,
        "label": label,
    }
    value.update({key: item for key, item in details.items() if item is not None and item != ""})
    return value


def locator_label(locator: dict[str, Any]) -> str:
    base = str(locator.get("label") or locator.get("kind") or "document")
    qualifiers: list[str] = []
    for key in ("page", "chapter", "section", "verse", "equation", "table", "diagram", "symbol", "dataset", "image", "timestamp", "spineItem", "jsonPath", "rowStart", "rowEnd", "lineStart", "lineEnd", "charStart", "charEnd"):
        value = locator.get(key)
        if value is not None and value != "" and str(value) not in base:
            qualifiers.append(f"{key}={value}")
    return f"{base}; " + "; ".join(qualifiers) if qualifiers else base


def strip_markup(value: str) -> str:
    return html_text(re.sub(r"<[^>]+>", " ", value))


def heading_kind(title: str, level: int) -> str:
    return "chapter" if level == 1 or re.match(r"(?i)^(chapter|book|part|act)\b", title.strip()) else "section"


def extract_timestamp_seconds(value: str) -> float | None:
    match = re.search(r"(?<!\d)(?:(\d{1,2}):)?(\d{1,2}):(\d{2})(?:[.,](\d{1,3}))?(?!\d)", value)
    if not match:
        return None
    hours = int(match.group(1) or 0)
    minutes = int(match.group(2))
    seconds = int(match.group(3))
    millis = int((match.group(4) or "0").ljust(3, "0")[:3])
    return round(hours * 3600 + minutes * 60 + seconds + millis / 1000, 3)


def code_symbol_name(line: str) -> tuple[str, str] | None:
    patterns = (
        ("class", r"^\s*(?:export\s+)?class\s+([A-Za-z_][A-Za-z0-9_]*)"),
        ("function", r"^\s*(?:export\s+)?(?:async\s+)?function\s+([A-Za-z_][A-Za-z0-9_]*)"),
        ("function", r"^\s*(?:async\s+)?def\s+([A-Za-z_][A-Za-z0-9_]*)"),
        ("function", r"^\s*function\s+([A-Za-z_][A-Za-z0-9_]*)"),
        ("type", r"^\s*(?:export\s+)?(?:interface|type|enum|struct|trait)\s+([A-Za-z_][A-Za-z0-9_]*)"),
        ("function", r"^\s*(?:public|private|protected|static|async|final|\s)+\s*[A-Za-z_][A-Za-z0-9_<>,\[\]? ]*\s+([A-Za-z_][A-Za-z0-9_]*)\s*\("),
        ("function", r"^\s*(?:const|let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?:async\s*)?\("),
        ("function", r"^\s*function\s+([A-Za-z_][A-Za-z0-9_]*)"),
    )
    for symbol_type, pattern in patterns:
        match = re.search(pattern, line)
        if match:
            return symbol_type, match.group(1)
    return None


def extract_code_text(raw: str, source_label: str = "code") -> list[tuple[dict[str, Any], str]]:
    lines = raw.splitlines()
    starts: list[tuple[int, str, str]] = []
    for index, line in enumerate(lines, start=1):
        symbol = code_symbol_name(line)
        if symbol:
            starts.append((index, symbol[0], symbol[1]))
    if not starts:
        return [(make_locator("section", source_label, section=source_label, lineStart=1, lineEnd=max(len(lines), 1)), normalize_text(raw))]
    sections: list[tuple[dict[str, Any], str]] = []
    for position, (line_start, symbol_type, symbol_name) in enumerate(starts):
        line_end = starts[position + 1][0] - 1 if position + 1 < len(starts) else len(lines)
        text = normalize_text("\n".join(lines[line_start - 1:line_end]))
        if text:
            sections.append(
                (
                    make_locator(
                        "code-symbol",
                        f"{symbol_type} {symbol_name}",
                        symbol=symbol_name,
                        symbolType=symbol_type,
                        lineStart=line_start,
                        lineEnd=line_end,
                    ),
                    text,
                )
            )
    return sections


def extract_markdown_text(raw: str, source_type: str = "", topics: Iterable[str] = ()) -> list[tuple[dict[str, Any], str]]:
    sections: list[tuple[dict[str, Any], str]] = []
    lines = raw.splitlines()
    topic_text = " ".join(topics).lower()

    page_matches = list(re.finditer(r"(?m)^\[\[PAGE (\d+)\]\]\s*$", raw))
    for index, match in enumerate(page_matches):
        end = page_matches[index + 1].start() if index + 1 < len(page_matches) else len(raw)
        text = normalize_text(raw[match.end():end])
        if text:
            page = int(match.group(1))
            sections.append((make_locator("page", f"page {page}", page=page), text))

    heading_rows: list[tuple[int, int, str]] = []
    for index, line in enumerate(lines, start=1):
        match = re.match(r"^\s{0,3}(#{1,6})\s+(.+?)\s*#*\s*$", line)
        if match:
            heading_rows.append((index, len(match.group(1)), match.group(2).strip()))
    for position, (line_start, level, title) in enumerate(heading_rows):
        line_end = heading_rows[position + 1][0] - 1 if position + 1 < len(heading_rows) else len(lines)
        text = normalize_text("\n".join(lines[line_start - 1:line_end]))
        if text:
            kind = heading_kind(title, level)
            detail_key = "chapter" if kind == "chapter" else "section"
            sections.append((make_locator(kind, f"{detail_key} {title}", **{detail_key: title, "headingLevel": level, "lineStart": line_start, "lineEnd": line_end}), text))

    verse_pattern = re.compile(r"^\s*(?:(?:[1-3]\s*)?[A-Za-z][A-Za-z ]+\s+)?(\d{1,3}):(\d{1,3})(?:[-–](\d{1,3}))?\s+(.+)$")
    if source_type == "primary-source" or any(term in topic_text for term in ("bible", "scripture", "verse", "theology")):
        for index, line in enumerate(lines, start=1):
            match = verse_pattern.match(line)
            if match:
                verse = f"{match.group(1)}:{match.group(2)}" + (f"-{match.group(3)}" if match.group(3) else "")
                sections.append((make_locator("verse", f"verse {verse}", verse=verse, lineStart=index, lineEnd=index), normalize_text(match.group(4))))

    equation_rows: list[tuple[int, str]] = []
    in_display_math = False
    math_buffer: list[str] = []
    math_start = 0
    for index, line in enumerate(lines, start=1):
        stripped = line.strip()
        if stripped.startswith("$$") or stripped.startswith(r"\["):
            if not in_display_math:
                in_display_math = True
                math_start = index
                math_buffer = [stripped]
                if stripped.endswith("$$") and len(stripped) > 4:
                    equation_rows.append((index, stripped.strip("$")))
                    in_display_math = False
            else:
                math_buffer.append(stripped)
                equation_rows.append((math_start, " ".join(math_buffer).strip("$[] \\")))
                in_display_math = False
            continue
        if in_display_math:
            math_buffer.append(stripped)
            if stripped.endswith("$$") or stripped.endswith(r"\]"):
                equation_rows.append((math_start, " ".join(math_buffer).strip("$[] \\")))
                in_display_math = False
        elif re.match(r"^\s*(?:Equation\s+\d+\s*[:.]?\s*)?[A-Za-z0-9()[\]{}_^+\-*/. ]+\s*=\s*[^=].+$", line) and len(stripped) <= 300:
            equation_rows.append((index, stripped))
    for equation_index, (line_start, equation_text) in enumerate(equation_rows, start=1):
        text = normalize_text(equation_text)
        if text:
            sections.append((make_locator("equation", f"equation {equation_index}", equation=equation_index, lineStart=line_start, lineEnd=line_start), text))

    table_start: int | None = None
    for index in range(len(lines) + 1):
        is_table = index < len(lines) and lines[index].count("|") >= 2
        if is_table and table_start is None:
            table_start = index
        if not is_table and table_start is not None:
            table_lines = lines[table_start:index]
            if len(table_lines) >= 2:
                table_number = sum(1 for locator, _ in sections if locator["kind"] == "table") + 1
                sections.append((make_locator("table", f"table {table_number}", table=table_number, rowStart=table_start + 1, rowEnd=index), normalize_text("\n".join(table_lines))))
            table_start = None

    fence_pattern = re.compile(r"(?ms)^```([A-Za-z0-9_-]*)\s*\n(.*?)^```\s*$")
    for fence_index, match in enumerate(fence_pattern.finditer(raw), start=1):
        language = match.group(1).lower()
        content = match.group(2)
        line_start = raw[:match.start()].count("\n") + 1
        if language in {"mermaid", "graphviz", "dot", "plantuml"}:
            sections.append((make_locator("diagram", f"diagram {fence_index}", diagram=fence_index, diagramType=language, lineStart=line_start), normalize_text(content)))
        else:
            for locator, text in extract_code_text(content, f"code block {fence_index}"):
                locator["lineStart"] = int(locator.get("lineStart", 1)) + line_start
                locator["lineEnd"] = int(locator.get("lineEnd", 1)) + line_start
                sections.append((locator, text))

    for image_index, match in enumerate(re.finditer(r"!\[([^\]]*)\]\(([^)\s]+)(?:\s+\"([^\"]*)\")?\)", raw), start=1):
        alt, image_path, title = match.group(1), match.group(2), match.group(3)
        line_start = raw[:match.start()].count("\n") + 1
        sections.append((make_locator("image", f"image {image_index}: {alt or title or image_path}", image=image_index, imagePath=image_path, alt=alt, title=title, lineStart=line_start), normalize_text(" ".join(item for item in (alt, title, image_path) if item))))

    for timestamp_index, line in enumerate(lines, start=1):
        seconds = extract_timestamp_seconds(line)
        if seconds is not None:
            timestamp = re.search(r"(?:(?:\d{1,2}:)?\d{1,2}:\d{2}(?:[.,]\d{1,3})?)", line)
            timestamp_text = timestamp.group(0) if timestamp else str(seconds)
            sections.append((make_locator("audiovisual-timestamp", f"timestamp {timestamp_text}", timestamp=timestamp_text, seconds=seconds, lineStart=timestamp_index), normalize_text(line)))

    if not sections:
        sections.append((make_locator("section", "document", section="document", lineStart=1, lineEnd=max(len(lines), 1)), normalize_text(raw)))
    return sections


def extract_html_text(raw: str, spine_item: str | None = None) -> list[tuple[dict[str, Any], str]]:
    sections: list[tuple[dict[str, Any], str]] = []
    heading_matches = list(re.finditer(r"(?is)<h([1-6])\b[^>]*>(.*?)</h\1>", raw))
    for index, match in enumerate(heading_matches):
        end = heading_matches[index + 1].start() if index + 1 < len(heading_matches) else len(raw)
        title = strip_markup(match.group(2))
        text = html_text(raw[match.start():end])
        if text:
            level = int(match.group(1))
            kind = heading_kind(title, level)
            detail_key = "chapter" if kind == "chapter" else "section"
            sections.append((make_locator(kind, f"{detail_key} {title}", **{detail_key: title, "headingLevel": level, "spineItem": spine_item}), text))
    for image_index, match in enumerate(re.finditer(r"(?is)<img\b([^>]*)>", raw), start=1):
        attrs = dict((key.lower(), value) for key, _, value in re.findall(r"([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*([\"'])(.*?)\2", match.group(1)))
        alt = attrs.get("alt", "")
        image_path = attrs.get("src", "")
        sections.append((make_locator("image", f"image {image_index}: {alt or image_path}", image=image_index, imagePath=image_path, alt=alt, spineItem=spine_item), normalize_text(f"{alt} {image_path}")))
    for table_index, match in enumerate(re.finditer(r"(?is)<table\b[^>]*>(.*?)</table>", raw), start=1):
        text = html_text(match.group(1))
        if text:
            sections.append((make_locator("table", f"table {table_index}", table=table_index, spineItem=spine_item), text))
    if not sections:
        text = html_text(raw)
        if text:
            sections.append((make_locator("section", spine_item or "document", section=spine_item or "document", spineItem=spine_item), text))
    return sections


def extract_pdf(path: Path) -> list[tuple[dict[str, Any], str]]:
    try:
        from pypdf import PdfReader  # type: ignore

        reader = PdfReader(str(path))
        return [(make_locator("page", f"page {index}", page=index), normalize_text(page.extract_text() or "")) for index, page in enumerate(reader.pages, start=1)]
    except ImportError:
        pass
    try:
        import fitz  # type: ignore

        with fitz.open(path) as document:
            return [(make_locator("page", f"page {index}", page=index), normalize_text(page.get_text("text"))) for index, page in enumerate(document, start=1)]
    except ImportError as exc:
        raise UnsupportedExtraction("PDF extraction requires pypdf or PyMuPDF; source was retained but not indexed") from exc


def extract_docx(path: Path) -> list[tuple[dict[str, Any], str]]:
    with zipfile.ZipFile(path) as archive:
        raw = archive.read("word/document.xml")
    root = ElementTree.fromstring(raw)
    paragraphs: list[str] = []
    for paragraph in root.iter():
        if paragraph.tag.endswith("}p"):
            text = "".join(node.text or "" for node in paragraph.iter() if node.tag.endswith("}t"))
            if text.strip():
                paragraphs.append(text.strip())
    return [(make_locator("section", "document", section="document"), normalize_text("\n\n".join(paragraphs)))]


def extract_epub(path: Path) -> list[tuple[dict[str, Any], str]]:
    sections: list[tuple[dict[str, Any], str]] = []
    with zipfile.ZipFile(path) as archive:
        names = sorted(name for name in archive.namelist() if Path(name).suffix.lower() in {".html", ".htm", ".xhtml"})
        for name in names:
            raw = archive.read(name).decode("utf-8", errors="replace")
            sections.extend(extract_html_text(raw, name))
    return sections


def extract_json_sections(value: Any, source_type: str) -> list[tuple[dict[str, Any], str]]:
    sections: list[tuple[dict[str, Any], str]] = []

    def visit(item: Any, json_path: str) -> None:
        if isinstance(item, dict):
            scalar_text = " ".join(f"{key}: {value}" for key, value in item.items() if not isinstance(value, (dict, list)) and value is not None)
            if scalar_text:
                kind = "dataset" if source_type == "dataset" else "section"
                sections.append((make_locator(kind, f"{kind} {json_path}", **{kind: json_path, "jsonPath": json_path}), normalize_text(scalar_text)))
            for key, value in item.items():
                if isinstance(value, (dict, list)):
                    visit(value, f"{json_path}.{key}")
        elif isinstance(item, list):
            for index, value in enumerate(item):
                visit(value, f"{json_path}[{index}]")
        elif item is not None:
            kind = "dataset" if source_type == "dataset" else "section"
            sections.append((make_locator(kind, f"{kind} {json_path}", **{kind: json_path, "jsonPath": json_path}), normalize_text(str(item))))

    visit(value, "$")
    return sections


def extract_delimited(path: Path, delimiter: str, source_type: str) -> list[tuple[dict[str, Any], str]]:
    with path.open("r", encoding="utf-8-sig", errors="replace", newline="") as handle:
        rows = list(csv.reader(handle, delimiter=delimiter))
    if not rows:
        return []
    kind = "dataset" if source_type == "dataset" else "table"
    sections: list[tuple[dict[str, Any], str]] = []
    header = rows[0]
    page_size = 100
    for start in range(1, len(rows), page_size):
        end = min(start + page_size, len(rows))
        selected = [header] + rows[start:end]
        row_start = start + 1
        row_end = end
        sections.append((make_locator(kind, f"{kind} rows {row_start}-{row_end}", **{kind: f"rows {row_start}-{row_end}", "rowStart": row_start, "rowEnd": row_end}), normalize_text("\n".join(" | ".join(row) for row in selected))))
    if len(rows) == 1:
        sections.append((make_locator(kind, f"{kind} row 1", **{kind: "row 1", "rowStart": 1, "rowEnd": 1}), normalize_text(" | ".join(rows[0]))))
    return sections


def extract_sections(path: Path, source: dict[str, Any]) -> list[tuple[dict[str, Any], str]]:
    suffix = path.suffix.lower()
    source_type = str(source.get("sourceType") or "")
    topics = source.get("topics") or []
    if suffix in {".txt", ".md", ".markdown"}:
        raw = path.read_text(encoding="utf-8", errors="replace")
        return extract_markdown_text(raw, source_type, topics)
    if suffix in {".html", ".htm"}:
        return extract_html_text(path.read_text(encoding="utf-8", errors="replace"))
    if suffix in {".json", ".jsonl"}:
        if suffix == ".jsonl":
            values = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
            return extract_json_sections(values, source_type)
        value = json.loads(path.read_text(encoding="utf-8"))
        return extract_json_sections(value, source_type)
    if suffix in {".csv", ".tsv"}:
        return extract_delimited(path, "," if suffix == ".csv" else "\t", source_type)
    if suffix == ".pdf":
        return extract_pdf(path)
    if suffix == ".docx":
        return extract_docx(path)
    if suffix == ".epub":
        return extract_epub(path)
    if suffix in SUPPORTED_SUFFIXES:
        return extract_code_text(path.read_text(encoding="utf-8", errors="replace"), path.name)
    raise UnsupportedExtraction(f"No extractor for {suffix}")


def chunk_sections(sections: list[tuple[dict[str, Any], str]], max_chars: int = 1800, overlap_chars: int = 220) -> list[tuple[dict[str, Any], str]]:
    chunks: list[tuple[dict[str, Any], str]] = []
    for locator, section in sections:
        if not section:
            continue
        section = normalize_text(section)
        start = 0
        chunk_index = 0
        while start < len(section):
            desired_end = min(start + max_chars, len(section))
            end = desired_end
            if desired_end < len(section):
                candidates = (
                    section.rfind("\n\n", start + max_chars // 2, desired_end),
                    section.rfind(". ", start + max_chars // 2, desired_end),
                    section.rfind(" ", start + max_chars // 2, desired_end),
                )
                end = max(candidates)
                if end <= start:
                    end = desired_end
                elif section[end:end + 2] in {". ", "\n\n"}:
                    end += 1
            text = section[start:end].strip()
            if text:
                chunk_index += 1
                chunk_locator = dict(locator)
                chunk_locator.update({"chunkIndex": chunk_index, "charStart": start + 1, "charEnd": end})
                chunks.append((chunk_locator, text))
            if end >= len(section):
                break
            start = max(end - overlap_chars, start + 1)
    return chunks


def locator_self_test() -> dict[str, Any]:
    samples: list[tuple[dict[str, Any], str]] = []
    samples.extend(extract_markdown_text("[[PAGE 12]]\nPinned page text."))
    samples.extend(extract_markdown_text("# Chapter 3\nChapter text.\n\n## Evidence Section\nSection text."))
    samples.extend(extract_markdown_text("John 3:16 For God so loved the world.", "primary-source", ["scripture"]))
    samples.extend(extract_markdown_text("$$\nE = mc^2\n$$"))
    samples.extend(extract_markdown_text("| Name | Value |\n| --- | --- |\n| alpha | 1 |"))
    samples.extend(extract_markdown_text("```mermaid\ngraph TD\nA --> B\n```\n\n```python\ndef solve(value):\n    return value\n```"))
    samples.extend(extract_markdown_text("![Map of the route](route-map.png \"Route map\")"))
    samples.extend(extract_markdown_text("[00:01:23.500] The demonstration begins.", "media-transcript"))
    samples.extend(extract_json_sections({"series": [{"year": 2025, "value": 4.2}]}, "dataset"))
    chunks = chunk_sections(samples, max_chars=300, overlap_chars=30)
    kinds = sorted({locator["kind"] for locator, _ in chunks})
    missing = sorted(REQUIRED_LOCATOR_KINDS - set(kinds))
    malformed = [
        locator for locator, text in chunks
        if locator.get("schemaVersion") != LOCATOR_SCHEMA
        or not locator.get("label")
        or not locator.get("kind")
        or not locator.get("charStart")
        or not locator.get("charEnd")
        or not text
    ]
    return {
        "schemaVersion": LOCATOR_SCHEMA,
        "requiredLocatorKinds": sorted(REQUIRED_LOCATOR_KINDS),
        "observedLocatorKinds": kinds,
        "sectionCount": len(samples),
        "chunkCount": len(chunks),
        "missingLocatorKinds": missing,
        "malformedChunkCount": len(malformed),
        "passed": not missing and not malformed,
        "examples": [
            {
                "kind": locator["kind"],
                "locator": locator_label(locator),
                "locatorData": locator,
                "excerpt": text[:120],
            }
            for locator, text in chunks
        ],
    }


def retrieval_tokens(text: str, expand_concepts: bool = False) -> list[str]:
    tokens = [
        token
        for token in re.findall(r"[a-z0-9]+", text.lower().replace("-", " "))
        if len(token) > 1 and token not in STOP_WORDS
    ]
    if expand_concepts:
        expanded = list(tokens)
        for token in tokens:
            expanded.extend(CONCEPT_EXPANSIONS.get(token, ()))
        tokens = expanded
    return tokens


def feature_vector(text: str, expand_concepts: bool = False) -> dict[int, float]:
    tokens = retrieval_tokens(text, expand_concepts)
    features = [f"word:{token}" for token in tokens]
    features.extend(f"pair:{left}:{right}" for left, right in zip(tokens, tokens[1:]))
    counts: dict[int, float] = {}
    for feature in features:
        digest = hashlib.sha256(feature.encode("utf-8")).digest()
        slot = int.from_bytes(digest[:4], "big") % VECTOR_DIMENSIONS
        counts[slot] = counts.get(slot, 0.0) + 1.0
    weighted = {slot: 1.0 + math.log(value) for slot, value in counts.items()}
    magnitude = math.sqrt(sum(value * value for value in weighted.values()))
    if magnitude == 0:
        return {}
    return {slot: round(value / magnitude, 8) for slot, value in weighted.items()}


def vector_json(vector: dict[int, float]) -> str:
    return json.dumps({str(key): value for key, value in sorted(vector.items())}, separators=(",", ":"))


def parse_vector(value: str) -> dict[int, float]:
    return {int(key): float(item) for key, item in json.loads(value).items()}


def cosine_similarity(left: dict[int, float], right: dict[int, float]) -> float:
    if not left or not right:
        return 0.0
    if len(left) > len(right):
        left, right = right, left
    return max(0.0, min(1.0, sum(value * right.get(key, 0.0) for key, value in left.items())))


def stable_key(value: str) -> str:
    return "-".join(retrieval_tokens(value)) or "untitled"


def source_work_key(source: dict[str, Any]) -> str:
    return str(source.get("workKey") or source.get("versionOf") or stable_key(str(source.get("title") or "")))


def evidence_tier_score(value: str) -> float:
    normalized = value.lower()
    for markers, score in EVIDENCE_TIER_WEIGHTS:
        if any(marker in normalized for marker in markers):
            return score
    return 0.6


def publication_year(value: str) -> int:
    match = re.search(r"\b(1[0-9]{3}|20[0-9]{2}|21[0-9]{2})\b", value)
    return int(match.group(1)) if match else 0


def candidate_score(candidate: dict[str, Any], retrieval_mode: str) -> tuple[float, dict[str, float]]:
    lexical_score = float(candidate.get("lexicalScore") or 0.0)
    vector_score = float(candidate.get("vectorScore") or 0.0)
    evidence_score = evidence_tier_score(str(candidate.get("evidenceTier") or ""))
    topic_score = float(candidate.get("topicScore") or 0.0)
    edition_score = 1.0 if candidate.get("preferredEdition") else min(publication_year(str(candidate.get("publicationDate") or "")) / 2200.0, 0.95)
    if retrieval_mode == "lexical":
        weights = {"lexical": 0.72, "vector": 0.0, "evidence": 0.16, "topic": 0.08, "edition": 0.04}
    else:
        weights = {"lexical": 0.43, "vector": 0.34, "evidence": 0.13, "topic": 0.06, "edition": 0.04}
    breakdown = {
        "lexical": round(lexical_score * weights["lexical"], 8),
        "vector": round(vector_score * weights["vector"], 8),
        "evidenceStrength": round(evidence_score * weights["evidence"], 8),
        "topicMatch": round(topic_score * weights["topic"], 8),
        "editionPreference": round(edition_score * weights["edition"], 8),
    }
    return round(sum(breakdown.values()), 8), breakdown


def resolve_duplicates_and_editions(candidates: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], dict[str, int]]:
    selected: list[dict[str, Any]] = []
    seen_content: set[str] = set()
    seen_passages: set[str] = set()
    duplicate_count = 0
    superseded_edition_count = 0
    for candidate in candidates:
        content_hash = str(candidate.get("contentHash") or "")
        passage_key = str(candidate.get("passageKey") or "")
        if content_hash and content_hash in seen_content:
            duplicate_count += 1
            continue
        if passage_key and passage_key in seen_passages:
            superseded_edition_count += 1
            continue
        selected.append(candidate)
        if content_hash:
            seen_content.add(content_hash)
        if passage_key:
            seen_passages.add(passage_key)
    return selected, {
        "exactDuplicateSuppressedCount": duplicate_count,
        "supersededEditionSuppressedCount": superseded_edition_count,
    }


def diversify_coverage(candidates: list[dict[str, Any]], limit: int) -> list[dict[str, Any]]:
    selected: list[dict[str, Any]] = []
    remaining = list(candidates)
    seen_viewpoints: set[str] = set()
    seen_traditions: set[str] = set()
    while remaining and len(selected) < limit:
        if not selected:
            choice_index = 0
        else:
            choice_index = max(
                range(len(remaining)),
                key=lambda index: (
                    bool(set(remaining[index].get("viewpointTags") or []) - seen_viewpoints)
                    + bool(set(remaining[index].get("traditionTags") or []) - seen_traditions),
                    float(remaining[index].get("score") or 0.0),
                ),
            )
        choice = remaining.pop(choice_index)
        selected.append(choice)
        seen_viewpoints.update(choice.get("viewpointTags") or [])
        seen_traditions.update(choice.get("traditionTags") or [])
    return selected


def plan_query(registry_path: Path, question: str, grade_band: str | None, limit: int) -> dict[str, Any]:
    registry, errors = validate_registry(registry_path)
    if errors:
        raise SubjectBrainError("Subject-brain registry validation failed:\n- " + "\n- ".join(errors))
    question_tokens = set(retrieval_tokens(question, True))
    question_vector = feature_vector(question, True)
    candidates: list[dict[str, Any]] = []
    for brain in registry.get("brains") or []:
        if brain.get("status") == "planned":
            continue
        grade_bands = brain.get("gradeBands") or []
        if grade_band and grade_band not in grade_bands:
            continue
        subject_tags = brain.get("subjectTags") or []
        routing_text = " ".join([str(brain.get("title") or ""), *subject_tags])
        routing_tokens = set(retrieval_tokens(routing_text, True))
        exact_tags = sorted(question_tokens & routing_tokens)
        vector_score = cosine_similarity(question_vector, feature_vector(routing_text, True))
        score = round(min(1.0, len(exact_tags) * 0.18 + vector_score * 0.55), 8)
        candidates.append(
            {
                "brainId": brain["brainId"],
                "title": brain["title"],
                "status": brain["status"],
                "gradeBands": grade_bands,
                "subjectTags": subject_tags,
                "matchedTerms": exact_tags,
                "routingScore": score,
                "role": "candidate",
                "query": question,
            }
        )
    candidates.sort(key=lambda item: (-float(item["routingScore"]), str(item["brainId"])))
    selected = [item for item in candidates if item["routingScore"] > 0][:limit]
    if not selected and candidates:
        selected = candidates[:1]
    for index, item in enumerate(selected):
        item["role"] = "primary" if index == 0 else "supporting"
    return {
        "schemaVersion": QUERY_PLAN_SCHEMA,
        "registryId": registry["registryId"],
        "query": question,
        "gradeBand": grade_band,
        "plannedBrainCount": len(selected),
        "plans": selected,
        "routingPolicy": {
            "lessonContentFirst": True,
            "maximumSpecialistBrains": limit,
            "queryEachBrainIndependently": True,
            "mergeRequiresCitations": True,
            "crossSourceDisagreementMustBeDisclosed": True,
            "offlineLexicalFallbackAvailable": True,
            "durableLearnerStateMutationAllowed": False,
        },
    }


def retrieval_self_test() -> dict[str, Any]:
    question_vector = feature_vector("deductive reasoning", True)
    semantic_vector_score = cosine_similarity(question_vector, feature_vector("logic validity premise conclusion", False))
    candidates = [
        {
            "sourceId": "weak-old",
            "contentHash": "duplicate-content",
            "passageKey": "shared-work:section:1",
            "evidenceTier": "informal-curated",
            "preferredEdition": False,
            "publicationDate": "2010",
            "lexicalScore": 1.0,
            "vectorScore": 0.8,
            "topicScore": 1.0,
            "viewpointTags": ["viewpoint-a"],
            "traditionTags": ["tradition-a"],
        },
        {
            "sourceId": "strong-new",
            "contentHash": "duplicate-content",
            "passageKey": "shared-work:section:1",
            "evidenceTier": "peer-reviewed",
            "preferredEdition": True,
            "publicationDate": "2026",
            "lexicalScore": 1.0,
            "vectorScore": 0.8,
            "topicScore": 1.0,
            "viewpointTags": ["viewpoint-a"],
            "traditionTags": ["tradition-a"],
        },
        {
            "sourceId": "independent-b",
            "contentHash": "independent-content",
            "passageKey": "independent-work:section:1",
            "evidenceTier": "official-primary-source",
            "preferredEdition": True,
            "publicationDate": "2025",
            "lexicalScore": 0.7,
            "vectorScore": 0.7,
            "topicScore": 0.8,
            "viewpointTags": ["viewpoint-b"],
            "traditionTags": ["tradition-b"],
        },
    ]
    for candidate in candidates:
        candidate["score"], candidate["scoreBreakdown"] = candidate_score(candidate, "hybrid")
    candidates.sort(key=lambda item: (-float(item["score"]), str(item["sourceId"])))
    resolved, resolution = resolve_duplicates_and_editions(candidates)
    diversified = diversify_coverage(resolved, 2)
    selected_ids = [item["sourceId"] for item in diversified]
    observed_viewpoints = sorted({tag for item in diversified for tag in item["viewpointTags"]})
    observed_traditions = sorted({tag for item in diversified for tag in item["traditionTags"]})
    checks = {
        "semanticVectorMatchedExpandedConcept": semantic_vector_score > 0,
        "preferredStrongEditionSelected": "strong-new" in selected_ids and "weak-old" not in selected_ids,
        "duplicateOrEditionSuppressed": sum(resolution.values()) == 1,
        "viewpointCoverageDiversified": observed_viewpoints == ["viewpoint-a", "viewpoint-b"],
        "traditionCoverageDiversified": observed_traditions == ["tradition-a", "tradition-b"],
        "evidenceStrengthReranked": candidates[0]["sourceId"] == "strong-new",
        "lexicalFallbackAvailable": True,
    }
    return {
        "schemaVersion": "open-education/subject-brain-retrieval-self-test/v1",
        "vectorAlgorithm": VECTOR_ALGORITHM,
        "vectorDimensions": VECTOR_DIMENSIONS,
        "checks": checks,
        "semanticVectorScore": round(semantic_vector_score, 8),
        "duplicateResolution": resolution,
        "selectedSourceIds": selected_ids,
        "observedViewpoints": observed_viewpoints,
        "observedTraditions": observed_traditions,
        "passed": all(checks.values()),
    }


def build_index(brain_root: Path, output_path: Path, replace: bool, strict_formats: bool) -> dict[str, Any]:
    manifest, corpus, errors = validate_brain(brain_root)
    if errors:
        raise SubjectBrainError("Subject brain validation failed:\n- " + "\n- ".join(errors))
    output_path = output_path.resolve()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    if output_path.exists():
        if not replace:
            raise SubjectBrainError(f"Index already exists; pass --replace to rebuild: {output_path}")
        output_path.unlink()

    indexed_sources: list[dict[str, Any]] = []
    skipped_sources: list[dict[str, str]] = []
    chunk_count = 0
    locator_kind_counts: dict[str, int] = {}
    connection: sqlite3.Connection | None = None
    try:
        connection = sqlite3.connect(output_path)
        connection.execute("PRAGMA journal_mode=DELETE")
        connection.execute("CREATE TABLE metadata (key TEXT PRIMARY KEY, value_json TEXT NOT NULL)")
        connection.execute(
            """CREATE TABLE sources (
                source_id TEXT PRIMARY KEY, title TEXT NOT NULL, source_path TEXT NOT NULL,
                canonical_url TEXT NOT NULL, license_id TEXT NOT NULL, sha256 TEXT NOT NULL,
                grade_bands_json TEXT NOT NULL, topics_json TEXT NOT NULL,
                source_type TEXT NOT NULL, evidence_tier TEXT NOT NULL,
                viewpoint_tags_json TEXT NOT NULL, tradition_tags_json TEXT NOT NULL,
                edition TEXT NOT NULL, work_key TEXT NOT NULL, preferred_edition INTEGER NOT NULL,
                publication_date TEXT NOT NULL, source_json TEXT NOT NULL
            )"""
        )
        connection.execute(
            """CREATE TABLE chunks (
                 chunk_id INTEGER PRIMARY KEY, source_id TEXT NOT NULL, locator TEXT NOT NULL,
                 locator_kind TEXT NOT NULL, locator_json TEXT NOT NULL, chunk_text TEXT NOT NULL,
                 vector_json TEXT NOT NULL, content_hash TEXT NOT NULL, passage_key TEXT NOT NULL,
                 FOREIGN KEY(source_id) REFERENCES sources(source_id)
             )"""
        )
        connection.execute("CREATE VIRTUAL TABLE chunk_fts USING fts5(chunk_text, source_id UNINDEXED, title, topics)")

        for source in corpus.get("sources") or []:
            if (source.get("acquisition") or {}).get("status") != "local-ready":
                continue
            if (source.get("rights") or {}).get("rightsStatus") != INDEX_RIGHTS_STATUS:
                continue
            local_path = relative_file(brain_root, str(source.get("localPath")), f"{source.get('sourceId')}.localPath")
            try:
                sections = extract_sections(local_path, source)
            except UnsupportedExtraction as exc:
                skipped_sources.append({"sourceId": str(source.get("sourceId")), "reason": str(exc)})
                if strict_formats:
                    raise
                continue
            chunks = chunk_sections(sections)
            if not chunks:
                skipped_sources.append({"sourceId": str(source.get("sourceId")), "reason": "extractor returned no text"})
                if strict_formats:
                    raise SubjectBrainError(f"No text extracted from {source.get('sourceId')}")
                continue
            source_id = str(source["sourceId"])
            connection.execute(
                """INSERT INTO sources(
                       source_id, title, source_path, canonical_url, license_id, sha256,
                       grade_bands_json, topics_json, source_type, evidence_tier,
                       viewpoint_tags_json, tradition_tags_json, edition, work_key,
                       preferred_edition, publication_date, source_json
                   ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (
                    source_id,
                    source["title"],
                    source["localPath"],
                    source["canonicalUrl"],
                    source["rights"]["licenseId"],
                    source["sha256"],
                    json.dumps(source.get("gradeBands") or []),
                    json.dumps(source.get("topics") or []),
                    str(source.get("sourceType") or ""),
                    str(source.get("evidenceTier") or ""),
                    json.dumps(source.get("viewpointTags") or ["unclassified"]),
                    json.dumps(source.get("traditionTags") or ["unclassified"]),
                    str(source.get("edition") or ""),
                    source_work_key(source),
                    1 if source.get("isPreferredEdition") else 0,
                    str(source.get("publicationDate") or source.get("reviewedAt") or ""),
                    json.dumps(source, sort_keys=True),
                ),
            )
            topics = " ".join(source.get("topics") or [])
            source_locator_counts: dict[str, int] = {}
            for locator, text in chunks:
                locator_kind = str(locator["kind"])
                locator_text = locator_label(locator)
                content_hash = hashlib.sha256(normalize_text(text).lower().encode("utf-8")).hexdigest()
                passage_key = hashlib.sha256(
                    "|".join(
                        (
                            source_work_key(source),
                            locator_kind,
                            str(locator.get("label") or ""),
                            str(locator.get("chunkIndex") or 1),
                        )
                    ).encode("utf-8")
                ).hexdigest()
                chunk_vector = feature_vector(f"{source['title']} {topics} {text}")
                cursor = connection.execute(
                    """INSERT INTO chunks(
                           source_id, locator, locator_kind, locator_json, chunk_text,
                           vector_json, content_hash, passage_key
                       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                    (
                        source_id,
                        locator_text,
                        locator_kind,
                        json.dumps(locator, sort_keys=True),
                        text,
                        vector_json(chunk_vector),
                        content_hash,
                        passage_key,
                    ),
                )
                chunk_id = int(cursor.lastrowid)
                connection.execute(
                    "INSERT INTO chunk_fts(rowid, chunk_text, source_id, title, topics) VALUES (?, ?, ?, ?, ?)",
                    (chunk_id, text, source_id, source["title"], topics),
                )
                chunk_count += 1
                locator_kind_counts[locator_kind] = locator_kind_counts.get(locator_kind, 0) + 1
                source_locator_counts[locator_kind] = source_locator_counts.get(locator_kind, 0) + 1
            indexed_sources.append(
                {
                    "sourceId": source_id,
                    "chunkCount": len(chunks),
                    "locatorKindCounts": dict(sorted(source_locator_counts.items())),
                }
            )

        if not indexed_sources:
            raise SubjectBrainError("No rights-approved local source could be indexed")
        metadata = {
            "schemaVersion": INDEX_SCHEMA,
            "brainId": manifest["brainId"],
            "sourceCount": len(indexed_sources),
            "chunkCount": chunk_count,
            "locatorSchemaVersion": LOCATOR_SCHEMA,
            "locatorKindCounts": dict(sorted(locator_kind_counts.items())),
            "retrievalMode": "hybrid-lexical-vector",
            "vectorAlgorithm": VECTOR_ALGORITHM,
            "vectorDimensions": VECTOR_DIMENSIONS,
            "lexicalFallbackAvailable": True,
            "duplicateAndEditionResolution": True,
            "viewpointAndTraditionDiversification": True,
            "evidenceStrengthReranking": True,
            "answerGenerationMode": "retrieval-context-only",
        }
        connection.execute("INSERT INTO metadata(key, value_json) VALUES (?, ?)", ("manifest", json.dumps(metadata, sort_keys=True)))
        connection.commit()
    except Exception:
        if connection is not None:
            connection.close()
            connection = None
        if output_path.exists():
            output_path.unlink()
        raise
    finally:
        if connection is not None:
            connection.close()

    return {
        "schemaVersion": INDEX_SCHEMA,
        "brainId": manifest["brainId"],
        "indexPath": str(output_path),
        "indexedSourceCount": len(indexed_sources),
        "chunkCount": chunk_count,
        "locatorSchemaVersion": LOCATOR_SCHEMA,
        "locatorKindCounts": dict(sorted(locator_kind_counts.items())),
        "retrievalMode": "hybrid-lexical-vector",
        "vectorAlgorithm": VECTOR_ALGORITHM,
        "vectorDimensions": VECTOR_DIMENSIONS,
        "lexicalFallbackAvailable": True,
        "indexedSources": indexed_sources,
        "skippedSources": skipped_sources,
    }


def fts_expression(question: str) -> str:
    terms: list[str] = []
    for token in re.findall(r"[A-Za-z0-9][A-Za-z0-9_-]{1,}", question.lower()):
        if token in STOP_WORDS or token in terms:
            continue
        terms.append(token)
        if len(terms) >= 16:
            break
    if not terms:
        raise SubjectBrainError("Query has no searchable terms")
    return " OR ".join(f'"{term}"*' for term in terms)


def query_index(index_path: Path, question: str, limit: int, grade_band: str | None, retrieval_mode: str) -> dict[str, Any]:
    index_path = index_path.resolve()
    if not index_path.is_file():
        raise SubjectBrainError(f"Missing subject-brain index: {index_path}")
    candidate_pool_size = max(limit * 20, 100)
    query_vector = feature_vector(question, True)
    query_tokens = set(retrieval_tokens(question, True))
    with sqlite3.connect(index_path) as connection:
        connection.row_factory = sqlite3.Row
        metadata_row = connection.execute("SELECT value_json FROM metadata WHERE key = 'manifest'").fetchone()
        if not metadata_row:
            raise SubjectBrainError("Index is missing its manifest")
        metadata = json.loads(metadata_row["value_json"])
        select_columns = """
            c.chunk_id, c.locator, c.locator_kind, c.locator_json, c.chunk_text,
            c.vector_json, c.content_hash, c.passage_key,
            s.source_id, s.title, s.source_path, s.canonical_url, s.license_id,
            s.sha256, s.grade_bands_json, s.topics_json, s.source_type,
            s.evidence_tier, s.viewpoint_tags_json, s.tradition_tags_json,
            s.edition, s.work_key, s.preferred_edition, s.publication_date
        """
        lexical_rows = connection.execute(
            f"""SELECT {select_columns}, bm25(chunk_fts) AS rank
                FROM chunk_fts
                JOIN chunks c ON c.chunk_id = chunk_fts.rowid
                JOIN sources s ON s.source_id = c.source_id
                WHERE chunk_fts MATCH ?
                ORDER BY rank
                LIMIT ?""",
            (fts_expression(question), candidate_pool_size),
        ).fetchall()
        vector_rows = []
        if retrieval_mode == "hybrid":
            vector_rows = connection.execute(
                f"""SELECT {select_columns}
                    FROM chunks c
                    JOIN sources s ON s.source_id = c.source_id"""
            ).fetchall()

    def row_candidate(row: sqlite3.Row) -> dict[str, Any] | None:
        grade_bands = json.loads(row["grade_bands_json"])
        if grade_band and grade_band not in grade_bands:
            return None
        topics = json.loads(row["topics_json"])
        source_tokens = set(retrieval_tokens(f"{row['title']} {' '.join(topics)}", True))
        topic_score = len(query_tokens & source_tokens) / max(len(query_tokens), 1)
        return {
            "chunkId": int(row["chunk_id"]),
            "sourceId": row["source_id"],
            "sourceRepo": metadata["brainId"],
            "sourcePath": row["source_path"],
            "sourceType": row["source_type"],
            "title": row["title"],
            "locator": row["locator"],
            "locatorKind": row["locator_kind"],
            "locatorData": json.loads(row["locator_json"]),
            "chunkText": row["chunk_text"],
            "canonicalUrl": row["canonical_url"],
            "licenseId": row["license_id"],
            "sha256": row["sha256"],
            "gradeBands": grade_bands,
            "topics": topics,
            "evidenceTier": row["evidence_tier"],
            "viewpointTags": json.loads(row["viewpoint_tags_json"]),
            "traditionTags": json.loads(row["tradition_tags_json"]),
            "edition": row["edition"] or None,
            "workKey": row["work_key"],
            "preferredEdition": bool(row["preferred_edition"]),
            "publicationDate": row["publication_date"] or None,
            "contentHash": row["content_hash"],
            "passageKey": row["passage_key"],
            "lexicalScore": 0.0,
            "vectorScore": 0.0,
            "topicScore": topic_score,
        }

    candidates_by_id: dict[int, dict[str, Any]] = {}
    lexical_count = len(lexical_rows)
    for index, row in enumerate(lexical_rows):
        candidate = row_candidate(row)
        if candidate is None:
            continue
        candidate["lexicalScore"] = round(1.0 - index / max(lexical_count, 1), 8)
        candidates_by_id[candidate["chunkId"]] = candidate

    if retrieval_mode == "hybrid":
        vector_candidates: list[tuple[float, sqlite3.Row]] = []
        for row in vector_rows:
            grade_bands = json.loads(row["grade_bands_json"])
            if grade_band and grade_band not in grade_bands:
                continue
            similarity = cosine_similarity(query_vector, parse_vector(row["vector_json"]))
            if similarity > 0:
                vector_candidates.append((similarity, row))
        vector_candidates.sort(key=lambda item: (-item[0], int(item[1]["chunk_id"])))
        for similarity, row in vector_candidates[:candidate_pool_size]:
            chunk_id = int(row["chunk_id"])
            candidate = candidates_by_id.get(chunk_id) or row_candidate(row)
            if candidate is None:
                continue
            candidate["vectorScore"] = round(similarity, 8)
            candidates_by_id[chunk_id] = candidate

    candidates = list(candidates_by_id.values())
    for candidate in candidates:
        candidate["score"], candidate["scoreBreakdown"] = candidate_score(candidate, retrieval_mode)
    candidates.sort(
        key=lambda item: (
            -float(item["score"]),
            -int(bool(item["preferredEdition"])),
            -publication_year(str(item.get("publicationDate") or "")),
            str(item["sourceId"]),
            int(item["chunkId"]),
        )
    )
    resolved, duplicate_resolution = resolve_duplicates_and_editions(candidates)
    selected = diversify_coverage(resolved, limit)
    results: list[dict[str, Any]] = []
    for candidate in selected:
        results.append(
            {
                "sourceId": candidate["sourceId"],
                "sourceRepo": candidate["sourceRepo"],
                "sourcePath": candidate["sourcePath"],
                "sourceType": candidate["sourceType"],
                "title": candidate["title"],
                "locator": candidate["locator"],
                "locatorKind": candidate["locatorKind"],
                "locatorData": candidate["locatorData"],
                "excerpt": candidate["chunkText"][:1600],
                "canonicalUrl": candidate["canonicalUrl"],
                "licenseId": candidate["licenseId"],
                "sha256": candidate["sha256"],
                "evidenceTier": candidate["evidenceTier"],
                "evidenceStrengthScore": evidence_tier_score(str(candidate["evidenceTier"])),
                "viewpointTags": candidate["viewpointTags"],
                "traditionTags": candidate["traditionTags"],
                "edition": candidate["edition"],
                "workKey": candidate["workKey"],
                "preferredEdition": candidate["preferredEdition"],
                "publicationDate": candidate["publicationDate"],
                "retrievalScore": candidate["score"],
                "scoreBreakdown": candidate["scoreBreakdown"],
                "retrievalSignals": {
                    "lexicalMatched": candidate["lexicalScore"] > 0,
                    "vectorMatched": candidate["vectorScore"] > 0,
                },
                "citationRequired": True,
            }
        )
    observed_viewpoints = sorted(
        {
            tag
            for result in results
            for tag in result["viewpointTags"]
            if tag != "unclassified"
        }
    )
    observed_traditions = sorted(
        {
            tag
            for result in results
            for tag in result["traditionTags"]
            if tag != "unclassified"
        }
    )
    return {
        "schemaVersion": QUERY_SCHEMA,
        "brainId": metadata["brainId"],
        "query": question,
        "gradeBand": grade_band,
        "retrievalModeRequested": retrieval_mode,
        "retrievalModeUsed": "hybrid-lexical-vector" if retrieval_mode == "hybrid" else "lexical-fts",
        "vectorAlgorithm": VECTOR_ALGORITHM if retrieval_mode == "hybrid" else None,
        "lexicalFallbackAvailable": True,
        "retrievalOnly": True,
        "generatedAnswer": None,
        "resultCount": len(results),
        "results": results,
        "candidateCount": len(candidates),
        "duplicateResolution": duplicate_resolution,
        "coverage": {
            "observedViewpointTags": observed_viewpoints,
            "observedTraditionTags": observed_traditions,
            "viewpointMetadataGap": not observed_viewpoints,
            "traditionMetadataGap": not observed_traditions,
            "diversificationApplied": True,
            "coverageDoesNotImplyTruth": True,
        },
        "rankingPolicy": {
            "lexicalAndVectorSignalsCombined": retrieval_mode == "hybrid",
            "evidenceStrengthIncluded": True,
            "topicMatchIncluded": True,
            "preferredAndNewerEditionIncluded": True,
            "exactDuplicatesSuppressed": True,
            "supersededEditionsSuppressed": True,
            "viewpointAndTraditionDiversityAppliedAfterRelevance": True,
        },
        "teacherPolicy": {
            "useAsGroundedContextOnly": True,
            "citeEveryUsedResult": True,
            "discloseConflictingSources": True,
            "stateWhenEvidenceIsInsufficient": True,
            "durableLearnerStateMutationAllowed": False,
        },
    }


def print_result(value: dict[str, Any]) -> None:
    print(json.dumps(value, indent=2, sort_keys=True))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    registry_parser = subparsers.add_parser("validate-registry")
    registry_parser.add_argument("--registry", default="subject-brains.json")

    brain_parser = subparsers.add_parser("validate-brain")
    brain_parser.add_argument("--brain-root", required=True)

    index_parser = subparsers.add_parser("index")
    index_parser.add_argument("--brain-root", required=True)
    index_parser.add_argument("--output", required=True)
    index_parser.add_argument("--replace", action="store_true")
    index_parser.add_argument("--strict-formats", action="store_true")

    query_parser = subparsers.add_parser("query")
    query_parser.add_argument("--index", required=True)
    query_parser.add_argument("--question", required=True)
    query_parser.add_argument("--limit", type=int, default=5)
    query_parser.add_argument("--grade-band", choices=("K-2", "3-5", "6-8", "9-12", "adult"))
    query_parser.add_argument("--retrieval-mode", choices=("hybrid", "lexical"), default="hybrid")

    plan_parser = subparsers.add_parser("plan-query")
    plan_parser.add_argument("--registry", default="subject-brains.json")
    plan_parser.add_argument("--question", required=True)
    plan_parser.add_argument("--limit", type=int, default=3)
    plan_parser.add_argument("--grade-band", choices=("K-2", "3-5", "6-8", "9-12", "adult"))

    subparsers.add_parser("locator-self-test")
    subparsers.add_parser("retrieval-self-test")

    args = parser.parse_args()
    try:
        if args.command == "validate-registry":
            registry, errors = validate_registry(Path(args.registry))
            print_result(
                {
                    "schemaVersion": registry.get("schemaVersion"),
                    "registryId": registry.get("registryId"),
                    "brainCount": len(registry.get("brains") or []),
                    "activeBrainCount": sum(1 for item in registry.get("brains") or [] if item.get("status") != "planned"),
                    "plannedBrainCount": sum(1 for item in registry.get("brains") or [] if item.get("status") == "planned"),
                    "errorCount": len(errors),
                    "errors": errors,
                }
            )
            return 1 if errors else 0
        if args.command == "validate-brain":
            manifest, corpus, errors = validate_brain(Path(args.brain_root))
            print_result(
                {
                    "schemaVersion": manifest.get("schemaVersion"),
                    "brainId": manifest.get("brainId"),
                    "status": manifest.get("status"),
                    "sourceCount": len(corpus.get("sources") or []),
                    "localReadyCount": sum(1 for item in corpus.get("sources") or [] if (item.get("acquisition") or {}).get("status") == "local-ready"),
                    "errorCount": len(errors),
                    "errors": errors,
                }
            )
            return 1 if errors else 0
        if args.command == "index":
            print_result(build_index(Path(args.brain_root), Path(args.output), args.replace, args.strict_formats))
            return 0
        if args.command == "query":
            if args.limit < 1 or args.limit > 20:
                raise SubjectBrainError("--limit must be between 1 and 20")
            print_result(query_index(Path(args.index), args.question, args.limit, args.grade_band, args.retrieval_mode))
            return 0
        if args.command == "plan-query":
            if args.limit < 1 or args.limit > 5:
                raise SubjectBrainError("--limit must be between 1 and 5 for cross-brain planning")
            print_result(plan_query(Path(args.registry), args.question, args.grade_band, args.limit))
            return 0
        if args.command == "locator-self-test":
            result = locator_self_test()
            print_result(result)
            return 0 if result["passed"] else 1
        if args.command == "retrieval-self-test":
            result = retrieval_self_test()
            print_result(result)
            return 0 if result["passed"] else 1
    except (SubjectBrainError, OSError, sqlite3.Error, zipfile.BadZipFile, json.JSONDecodeError) as exc:
        print(json.dumps({"error": str(exc), "command": args.command}, indent=2), file=sys.stderr)
        return 1
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

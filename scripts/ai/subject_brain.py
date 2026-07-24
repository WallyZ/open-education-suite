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
READY_STATUSES = {"contract-ready", "starter-corpus-ready", "pilot-ready", "production-ready"}
INDEX_RIGHTS_STATUS = "approved-for-local-index"
LOCAL_ACQUISITION_STATUSES = {"local-ready", "local-pending-extraction"}
SUPPORTED_SUFFIXES = {".txt", ".md", ".markdown", ".html", ".htm", ".json", ".csv", ".pdf", ".docx", ".epub"}
STOP_WORDS = {
    "a", "an", "and", "are", "as", "at", "be", "by", "for", "from", "how",
    "in", "is", "it", "of", "on", "or", "that", "the", "this", "to", "what",
    "when", "where", "which", "who", "why", "with",
}


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


def extract_pdf(path: Path) -> list[tuple[str, str]]:
    try:
        from pypdf import PdfReader  # type: ignore

        reader = PdfReader(str(path))
        return [(f"page {index}", normalize_text(page.extract_text() or "")) for index, page in enumerate(reader.pages, start=1)]
    except ImportError:
        pass
    try:
        import fitz  # type: ignore

        with fitz.open(path) as document:
            return [(f"page {index}", normalize_text(page.get_text("text"))) for index, page in enumerate(document, start=1)]
    except ImportError as exc:
        raise UnsupportedExtraction("PDF extraction requires pypdf or PyMuPDF; source was retained but not indexed") from exc


def extract_docx(path: Path) -> list[tuple[str, str]]:
    with zipfile.ZipFile(path) as archive:
        raw = archive.read("word/document.xml")
    root = ElementTree.fromstring(raw)
    paragraphs: list[str] = []
    for paragraph in root.iter():
        if paragraph.tag.endswith("}p"):
            text = "".join(node.text or "" for node in paragraph.iter() if node.tag.endswith("}t"))
            if text.strip():
                paragraphs.append(text.strip())
    return [("document", normalize_text("\n\n".join(paragraphs)))]


def extract_epub(path: Path) -> list[tuple[str, str]]:
    sections: list[tuple[str, str]] = []
    with zipfile.ZipFile(path) as archive:
        names = sorted(name for name in archive.namelist() if Path(name).suffix.lower() in {".html", ".htm", ".xhtml"})
        for name in names:
            raw = archive.read(name).decode("utf-8", errors="replace")
            text = html_text(raw)
            if text:
                sections.append((name, text))
    return sections


def extract_sections(path: Path) -> list[tuple[str, str]]:
    suffix = path.suffix.lower()
    if suffix in {".txt", ".md", ".markdown"}:
        raw = path.read_text(encoding="utf-8", errors="replace")
        page_parts = re.split(r"(?m)^\[\[PAGE (\d+)\]\]\s*$", raw)
        if len(page_parts) > 1:
            sections: list[tuple[str, str]] = []
            for index in range(1, len(page_parts), 2):
                text = normalize_text(page_parts[index + 1])
                if text:
                    sections.append((f"page {page_parts[index]}", text))
            return sections
        return [("document", normalize_text(raw))]
    if suffix in {".html", ".htm"}:
        return [("document", html_text(path.read_text(encoding="utf-8", errors="replace")))]
    if suffix == ".json":
        value = json.loads(path.read_text(encoding="utf-8"))
        return [("document", normalize_text("\n".join(flatten_json(value))))]
    if suffix == ".csv":
        with path.open("r", encoding="utf-8-sig", errors="replace", newline="") as handle:
            rows = [" | ".join(row) for row in csv.reader(handle)]
        return [("rows", normalize_text("\n".join(rows)))]
    if suffix == ".pdf":
        return extract_pdf(path)
    if suffix == ".docx":
        return extract_docx(path)
    if suffix == ".epub":
        return extract_epub(path)
    raise UnsupportedExtraction(f"No extractor for {suffix}")


def chunk_sections(sections: list[tuple[str, str]], max_chars: int = 1800, overlap_chars: int = 220) -> list[tuple[str, str]]:
    chunks: list[tuple[str, str]] = []
    for locator, section in sections:
        if not section:
            continue
        paragraphs = [part.strip() for part in re.split(r"\n\s*\n|(?<=\.)\s+(?=[A-Z])", section) if part.strip()]
        current = ""
        for paragraph in paragraphs:
            if len(paragraph) > max_chars:
                slices = [paragraph[index:index + max_chars] for index in range(0, len(paragraph), max_chars - overlap_chars)]
            else:
                slices = [paragraph]
            for piece in slices:
                candidate = f"{current}\n\n{piece}".strip() if current else piece
                if current and len(candidate) > max_chars:
                    chunks.append((locator, current))
                    current = f"{current[-overlap_chars:]} {piece}".strip()
                else:
                    current = candidate
        if current:
            chunks.append((locator, current))
    return chunks


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
    connection: sqlite3.Connection | None = None
    try:
        connection = sqlite3.connect(output_path)
        connection.execute("PRAGMA journal_mode=DELETE")
        connection.execute("CREATE TABLE metadata (key TEXT PRIMARY KEY, value_json TEXT NOT NULL)")
        connection.execute(
            """CREATE TABLE sources (
                source_id TEXT PRIMARY KEY, title TEXT NOT NULL, source_path TEXT NOT NULL,
                canonical_url TEXT NOT NULL, license_id TEXT NOT NULL, sha256 TEXT NOT NULL,
                grade_bands_json TEXT NOT NULL, topics_json TEXT NOT NULL, source_json TEXT NOT NULL
            )"""
        )
        connection.execute(
            """CREATE TABLE chunks (
                chunk_id INTEGER PRIMARY KEY, source_id TEXT NOT NULL, locator TEXT NOT NULL,
                chunk_text TEXT NOT NULL, FOREIGN KEY(source_id) REFERENCES sources(source_id)
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
                sections = extract_sections(local_path)
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
                "INSERT INTO sources VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    source_id,
                    source["title"],
                    source["localPath"],
                    source["canonicalUrl"],
                    source["rights"]["licenseId"],
                    source["sha256"],
                    json.dumps(source.get("gradeBands") or []),
                    json.dumps(source.get("topics") or []),
                    json.dumps(source, sort_keys=True),
                ),
            )
            topics = " ".join(source.get("topics") or [])
            for locator, text in chunks:
                cursor = connection.execute(
                    "INSERT INTO chunks(source_id, locator, chunk_text) VALUES (?, ?, ?)",
                    (source_id, locator, text),
                )
                chunk_id = int(cursor.lastrowid)
                connection.execute(
                    "INSERT INTO chunk_fts(rowid, chunk_text, source_id, title, topics) VALUES (?, ?, ?, ?, ?)",
                    (chunk_id, text, source_id, source["title"], topics),
                )
                chunk_count += 1
            indexed_sources.append({"sourceId": source_id, "chunkCount": len(chunks)})

        if not indexed_sources:
            raise SubjectBrainError("No rights-approved local source could be indexed")
        metadata = {
            "schemaVersion": INDEX_SCHEMA,
            "brainId": manifest["brainId"],
            "sourceCount": len(indexed_sources),
            "chunkCount": chunk_count,
            "retrievalMode": "lexical-fts",
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


def query_index(index_path: Path, question: str, limit: int, grade_band: str | None) -> dict[str, Any]:
    index_path = index_path.resolve()
    if not index_path.is_file():
        raise SubjectBrainError(f"Missing subject-brain index: {index_path}")
    with sqlite3.connect(index_path) as connection:
        connection.row_factory = sqlite3.Row
        metadata_row = connection.execute("SELECT value_json FROM metadata WHERE key = 'manifest'").fetchone()
        if not metadata_row:
            raise SubjectBrainError("Index is missing its manifest")
        metadata = json.loads(metadata_row["value_json"])
        rows = connection.execute(
            """SELECT c.chunk_id, c.locator, c.chunk_text, s.source_id, s.title,
                      s.source_path, s.canonical_url, s.license_id, s.sha256,
                      s.grade_bands_json, bm25(chunk_fts) AS rank
               FROM chunk_fts
               JOIN chunks c ON c.chunk_id = chunk_fts.rowid
               JOIN sources s ON s.source_id = c.source_id
               WHERE chunk_fts MATCH ?
               ORDER BY rank
               LIMIT ?""",
            (fts_expression(question), max(limit * 4, limit)),
        ).fetchall()

    results: list[dict[str, Any]] = []
    for row in rows:
        grade_bands = json.loads(row["grade_bands_json"])
        if grade_band and grade_band not in grade_bands:
            continue
        results.append(
            {
                "sourceId": row["source_id"],
                "sourceRepo": metadata["brainId"],
                "sourcePath": row["source_path"],
                "title": row["title"],
                "locator": row["locator"],
                "excerpt": row["chunk_text"][:1600],
                "canonicalUrl": row["canonical_url"],
                "licenseId": row["license_id"],
                "sha256": row["sha256"],
                "citationRequired": True,
            }
        )
        if len(results) >= limit:
            break
    return {
        "schemaVersion": QUERY_SCHEMA,
        "brainId": metadata["brainId"],
        "query": question,
        "gradeBand": grade_band,
        "retrievalOnly": True,
        "generatedAnswer": None,
        "resultCount": len(results),
        "results": results,
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
            print_result(query_index(Path(args.index), args.question, args.limit, args.grade_band))
            return 0
    except (SubjectBrainError, OSError, sqlite3.Error, zipfile.BadZipFile, json.JSONDecodeError) as exc:
        print(json.dumps({"error": str(exc), "command": args.command}, indent=2), file=sys.stderr)
        return 1
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

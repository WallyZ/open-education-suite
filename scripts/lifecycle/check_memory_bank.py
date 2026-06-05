#!/usr/bin/env python3
"""check_memory_bank.py

Validate memory-bank structure, freshness, size budgets, and local references.
"""

from __future__ import annotations

import argparse
import datetime as dt
import math
import re
from pathlib import Path

PROFILE_LIMITS = {
    "32k": {
        "activeContext.md": 90,
        "progress.md": 120,
        "context-pack.md": 60,
    },
    "64k": {
        "activeContext.md": 120,
        "progress.md": 160,
        "context-pack.md": 80,
    },
    "cloud": {
        "activeContext.md": 200,
        "progress.md": 280,
        "context-pack.md": 140,
    },
}

REQUIRED_FILES = [
    "projectbrief.md",
    "productContext.md",
    "systemPatterns.md",
    "techContext.md",
    "activeContext.md",
    "progress.md",
    "repoKitCatalog.md",
    "solutionHarvest.md",
]

OPTIONAL_FILES = [
    "context-pack.md",
    "decisions.md",
    "HANDOFF.md",
    "commonPitfalls.md",
]

REQUIRED_HEADINGS = {
    "projectbrief.md": ["# Project Brief"],
    "productContext.md": ["# Product Context"],
    "systemPatterns.md": ["# System Patterns"],
    "techContext.md": ["# Tech Context"],
    "activeContext.md": ["# Active Context", "## Current objective", "## Next 3 actions"],
    "progress.md": ["# Progress", "## Completed", "## In progress", "## Next"],
    "context-pack.md": ["# Context Pack", "## Objective", "## Must-read files"],
    "HANDOFF.md": ["# HANDOFF", "## Current Objective", "## Next Commands (Max 5)"],
    "repoKitCatalog.md": ["# Repo-Kit Catalog", "## Metadata", "## Capabilities Snapshot", "## Wave Pull Review Log"],
    "solutionHarvest.md": ["# Solution Harvest", "## Metadata", "## Candidate Reusable Solutions", "## Promoted to Repo-Kit"],
    "commonPitfalls.md": ["# Common Pitfalls", "## Index", "## Entries"],
}

LOCAL_LINK_RE = re.compile(r"\[[^\]]+\]\(([^)]+)\)")
CODE_SPAN_RE = re.compile(r"`([^`]+)`")
DATE_RE = re.compile(r"\b(\d{4}-\d{2}-\d{2})\b")
TOKEN_SPLIT_RE = re.compile(r"\w+|[^\w\s]", re.UNICODE)

PREFIXES = (
    "docs/",
    "scripts/",
    "memory-bank/",
    "tools/",
    "repo-standards/",
    ".github/",
    "src/",
)


def normalize_candidate(raw: str) -> str | None:
    value = raw.strip().strip("\"'")
    if not value:
        return None
    if value.startswith(("http://", "https://", "mailto:", "#")):
        return None
    if value.startswith("./"):
        value = value[2:]
    if any(ch in value for ch in ("<", ">", "{", "}", "*", "|")):
        return None
    return value.rstrip(".,:;)")


def is_probable_path(token: str) -> bool:
    if any(ch.isspace() for ch in token):
        return False
    t = token.replace("\\", "/")
    if t.startswith(PREFIXES):
        return True
    if t.startswith("../"):
        return True
    if re.match(r"^[A-Za-z]:[\\/]", token):
        return True
    return False


def resolve_path(token: str, repo_root: Path, source: Path) -> Path:
    if re.match(r"^[A-Za-z]:[\\/]", token):
        return Path(token)
    if token.startswith("../"):
        return (source.parent / token).resolve()
    return (repo_root / token.replace("\\", "/")).resolve()


def collect_refs(text: str) -> list[str]:
    refs: list[str] = []
    for m in LOCAL_LINK_RE.finditer(text):
        cand = normalize_candidate(m.group(1))
        if cand and is_probable_path(cand):
            refs.append(cand)
    for m in CODE_SPAN_RE.finditer(text):
        cand = normalize_candidate(m.group(1))
        if cand and is_probable_path(cand):
            refs.append(cand)
    return refs


def parse_date(value: str) -> dt.date | None:
    try:
        return dt.datetime.strptime(value, "%Y-%m-%d").date()
    except ValueError:
        return None


def date_age_days(date_value: dt.date, today: dt.date) -> int:
    return (today - date_value).days


def estimate_tokens(text: str) -> int:
    """Estimate token count without external tokenizer dependencies.

    Uses a conservative max between:
    - unicode token-ish splits (words + punctuation)
    - char-based estimate (4 chars/token heuristic)
    """

    if not text:
        return 0
    split_count = len(TOKEN_SPLIT_RE.findall(text))
    by_chars = math.ceil(len(text) / 4.0)
    return max(split_count, by_chars)


def extract_freshness_date(path: Path, text: str) -> dt.date | None:
    name = path.name
    if name == "activeContext.md":
        m = re.search(r"(?im)^\s*Last\s+updated:\s*(\d{4}-\d{2}-\d{2})\s*$", text)
        if m:
            return parse_date(m.group(1))
    if name == "context-pack.md":
        m = re.search(r"(?im)^\s*Generated:\s*(\d{4}-\d{2}-\d{2})\s*$", text)
        if m:
            return parse_date(m.group(1))
    if name == "HANDOFF.md":
        m = re.search(r"(?im)^\s*[-*]?\s*Last\s+updated:\s*(\d{4}-\d{2}-\d{2})\s*$", text)
        if m:
            return parse_date(m.group(1))
    if name == "repoKitCatalog.md":
        m = re.search(r"(?im)^\s*[-*]\s*Last\s+synced:\s*(\d{4}-\d{2}-\d{2})\s*$", text)
        if m:
            return parse_date(m.group(1))
    if name == "solutionHarvest.md":
        m = re.search(r"(?im)^\s*[-*]\s*Last\s+updated:\s*(\d{4}-\d{2}-\d{2})\s*$", text)
        if m:
            return parse_date(m.group(1))
    if name == "progress.md":
        matches = DATE_RE.findall(text)
        dates = [parse_date(v) for v in matches]
        dates = [d for d in dates if d is not None]
        if dates:
            return max(dates)
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo-root", default=".")
    ap.add_argument("--memory-dir", default="memory-bank")
    ap.add_argument("--profile", choices=["32k", "64k", "cloud"], default="cloud")
    ap.add_argument("--max-age-days", type=int, default=14)
    ap.add_argument("--max-handoff-tokens", type=int, default=2000)
    ap.add_argument("--require-memory-bank", action="store_true")
    args = ap.parse_args()

    repo_root = Path(args.repo_root).resolve()
    memory_root = (repo_root / args.memory_dir).resolve()

    if not memory_root.exists():
        if args.require_memory_bank:
            print(f"Memory-bank directory missing: {memory_root}")
            return 1
        print(f"Memory-bank directory not present; skipping check: {memory_root}")
        return 0

    violations: list[str] = []
    today = dt.date.today()
    limits = PROFILE_LIMITS[args.profile]

    files_to_check: list[Path] = []
    for rel in REQUIRED_FILES:
        p = memory_root / rel
        if not p.exists():
            violations.append(f"Missing required memory file: {args.memory_dir}/{rel}")
            continue
        files_to_check.append(p)

    for rel in OPTIONAL_FILES:
        p = memory_root / rel
        if p.exists():
            files_to_check.append(p)

    for path in files_to_check:
        rel = path.relative_to(repo_root).as_posix()
        text = path.read_text(encoding="utf-8", errors="ignore")

        expected = REQUIRED_HEADINGS.get(path.name, [])
        for heading in expected:
            if heading not in text:
                violations.append(f"{rel}: missing heading '{heading}'")

        if path.name in limits:
            line_count = len(text.splitlines())
            limit = limits[path.name]
            if line_count > limit:
                violations.append(f"{rel}: exceeds profile line budget ({line_count} > {limit})")

        if path.name == "HANDOFF.md":
            estimated = estimate_tokens(text)
            if estimated > args.max_handoff_tokens:
                violations.append(
                    f"{rel}: exceeds handoff token budget estimate ({estimated} > {args.max_handoff_tokens})"
                )

        freshness_date = extract_freshness_date(path, text)
        if path.name in (
            "activeContext.md",
            "progress.md",
            "context-pack.md",
            "HANDOFF.md",
            "repoKitCatalog.md",
            "solutionHarvest.md",
        ):
            if freshness_date is None:
                violations.append(f"{rel}: missing freshness date marker")
            else:
                age = date_age_days(freshness_date, today)
                if age > args.max_age_days:
                    violations.append(
                        f"{rel}: stale freshness date {freshness_date.isoformat()} ({age} days > {args.max_age_days})"
                    )

        # repoKitCatalog.md intentionally snapshots assets from the external
        # repo-kit checkout. Those entries are not local repo links.
        refs = [] if path.name == "repoKitCatalog.md" else collect_refs(text)
        for ref in refs:
            target = resolve_path(ref, repo_root, path)
            if not target.exists():
                violations.append(f"{rel}: unresolved local reference '{ref}'")

    if violations:
        print("Memory-bank quality check failed:")
        for item in violations:
            print(f"- {item}")
        return 1

    print(
        f"Memory-bank quality check passed (repo={repo_root}, profile={args.profile}, files_checked={len(files_to_check)})."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

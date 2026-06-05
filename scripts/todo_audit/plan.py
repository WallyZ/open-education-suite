"""Plan generation and related helper functions for TODO audit.

NOTE: Per your direction, this module may exceed ~400 LOC slightly so we can keep
`build_plan_and_report_data` mechanically identical.
"""

from __future__ import annotations

import json
import re
from fnmatch import fnmatchcase
from pathlib import Path, PurePosixPath

from scripts.todo_audit.detectors import _looks_like_path, extract_hints
from scripts.todo_audit.repo_scan import RepoTextIndex
from scripts.todo_audit.scoring import compute_item_assessment
from scripts.todo_audit.todo_parse import TodoItem, parse_markdown_todos
from scripts.todo_audit.util import _dedupe_stable, _safe_relpath, compute_stable_todo_id


# Default ignore globs used ONLY when scanning for suggestion additions.
# These must not affect normal evidence checks for explicit TODO items.

# DEFAULT_RECOMMENDATION_DENY_* governs whether we emit "add completed item" recommendations.
# These are intentionally conservative; adds are the easiest way for this tool to create noisy
# TODO churn (e.g., "Track completed: __init__.py exists").
#
# Behavior:
# - deny matches => suppress add recommendation
# - allow-glob matches => allow beats deny
# - some denies (README.md, docs index hubs, tests/) can also be overridden when those paths are
#   explicitly referenced via existing TODO evidence.
DEFAULT_RECOMMENDATION_DENY_GLOBS = [
    "**/__pycache__/**",
    "**/*.pyc",
    "**/*.pyo",
    "**/*.pyi",
    "**/*.bak",
    "**/*.tmp",
    "**/*.log",
    "**/.venv/**",
    "**/venv/**",
    "**/.git/**",
    # Tests are high-noise unless the TODO explicitly references them.
    "tests/**",
    "**/tests/**",
    # Hub docs are high-noise unless explicitly referenced.
    "docs/index.md",
    "docs/**/index.md",
    # Root docs are often hub-like process docs; opt-in via allow-glob.
    "docs/*.md",
    # Repo/process docs (not task-scoped TODOs) are noise.
    "docs/CLINE_*.md",
    "docs/todo/**",
]

DEFAULT_RECOMMENDATION_DENY_BASENAMES = {
    "__init__.py",
    "__main__.py",
    "py.typed",
    "readme.md",
    "license",
    "license.md",
    ".gitignore",
    "requirements.txt",
    "pyproject.toml",
    # typing.py-ish stubs
    "typing.py",
    "typing.pyi",
    "typing_extensions.pyi",
}

# Back-compat: older tests/flags refer to "suggest ignore globs".
DEFAULT_SUGGEST_IGNORE_GLOBS = list(DEFAULT_RECOMMENDATION_DENY_GLOBS)


# Very simple mapping for “out of place” suggestions.
SECTION_KEYWORD_BY_PREFIX = {
    "youtube_automation/research/": "Research",
    "youtube_automation/ideas/": "Idea System",
    "youtube_automation/interfaces/": "CLI",
}


EXCLUDE_BASENAMES_FOR_ADDITIONS = {
    "__init__.py",
    "__main__.py",
}


EXCLUDE_PATH_PARTS_ANYWHERE = {
    "__pycache__",
    ".venv",
    "venv",
    "site-packages",
    ".git",
    ".github",
    ".mypy_cache",
    ".pytest_cache",
    "data",
    "build",
    "dist",
}


def _section_explicitly_about_tests(section_path: list[str]) -> bool:
    txt = " ".join(section_path or []).lower()
    return "test" in txt or "tests" in txt


def _section_explicitly_about_scripts(section_path: list[str]) -> bool:
    txt = " ".join(section_path or []).lower()
    return any(k in txt for k in ["script", "scripts", "tool", "tools"])


def _is_excluded_by_policy(rel_posix: str) -> bool:
    rel_posix = (rel_posix or "").replace("\\", "/").strip("/")
    if not rel_posix:
        return True
    parts = [p for p in rel_posix.split("/") if p]
    return any(p in EXCLUDE_PATH_PARTS_ANYWHERE for p in parts)


def is_disallowed_addition(
    rel_posix: str,
    *,
    section_path: list[str] | None = None,
    allow_tests: bool = False,
    allow_docs: bool = False,
) -> bool:
    """Apply the wave's deterministic exclusion policy for *add* recommendations.

    RATIONALE:
    - Add suggestions are intentionally conservative; they are the most likely to create noisy
      "common file" churn in TODO markdown.
    - This denylist is enforced even when --suggest-additions is enabled.
    """

    rel_posix = (rel_posix or "").replace("\\", "/").lstrip("/")
    if not rel_posix:
        return True

    parts = [p for p in rel_posix.split("/") if p]
    name = parts[-1] if parts else ""
    name_l = name.lower()
    rel_l = rel_posix.lower()

    # Compiled artifacts are always noise for "track completed" suggestions.
    if name_l.endswith((".pyc", ".pyo")):
        return True

    if _is_excluded_by_policy(rel_posix):
        return True

    # docs infra noise
    if rel_l.startswith("docs/cline_") and rel_l.endswith(".md"):
        return True

    # Never suggest adding TODO markdown files themselves (case variants normalize via .lower()).
    if rel_l.startswith("docs/todo/"):
        return True

    # NOTE:
    # - Tests/docs suppression for *recommendation adds* is now handled via
    #   DEFAULT_RECOMMENDATION_DENY_GLOBS + allow/deny overrides.
    # - We keep allow_tests/allow_docs parameters for back-compat, but do not use them here.

    # scripts are still excluded unless the section is explicitly about scripts/tools.
    sp = section_path or []
    if (rel_l.startswith("scripts/") or "/scripts/" in rel_l) and not _section_explicitly_about_scripts(sp):
        return True

    # underscore-internal files are noise by default
    if name.startswith("_") and name_l.endswith(".py"):
        return True

    return False


def _matches_any_suggest_ignore_glob(rel_posix: str, globs: list[str]) -> bool:
    rel_posix = (rel_posix or "").replace("\\", "/").lstrip("/")
    if not rel_posix:
        return False
    p = PurePosixPath(rel_posix)
    for g in globs or []:
        pat = (g or "").strip().replace("\\", "/")
        if not pat:
            continue
        # Prefer pathlib's ** semantics; fall back to fnmatch for odd patterns.
        try:
            if p.match(pat):
                return True
        except Exception:
            if fnmatchcase(rel_posix, pat):
                return True
    return False


def _matches_any_glob(rel_posix: str, globs: list[str] | None) -> str | None:
    """Return the first matching glob pattern, if any."""

    rel_posix = (rel_posix or "").replace("\\", "/").lstrip("/")
    if not rel_posix:
        return None
    p = PurePosixPath(rel_posix)
    for g in globs or []:
        pat = (g or "").strip().replace("\\", "/")
        if not pat:
            continue
        try:
            if p.match(pat):
                return pat
        except Exception:
            if fnmatchcase(rel_posix, pat):
                return pat
    return None


def _collect_explicit_evidence_path_hints(items: list["TodoItem"]) -> set[str]:
    """Collect explicit yta:evidence path hints (exact relative paths only).

    NOTE:
    - We intentionally do *not* collect basenames.
      Common basenames (e.g., __init__.py) are too low-signal and would cause
      repo-wide allow-by-basename leakage.
    """

    explicit_paths: set[str] = set()
    for it in items:
        for raw in (it.yta_evidence.get("paths") or []):
            p = (raw or "").replace("\\", "/").lstrip("/")
            if not p or "<" in p or ">" in p:
                continue
            explicit_paths.add(p.lower())

        # Also accept explicit in-text path mentions, not just yta:evidence.
        hints = extract_hints(it.text)
        for raw in (hints.get("paths") or []):
            p = (raw or "").replace("\\", "/").lstrip("/")
            if not p or "<" in p or ">" in p:
                continue
            explicit_paths.add(p.lower())
    return explicit_paths


def _item_explicitly_references_path(it: "TodoItem", rel_posix: str) -> bool:
    """True if this specific TODO line explicitly references the exact path.

    Explicit reference means:
    - The TODO line contains the exact repo-relative path string, OR
    - The TODO line has `<!-- yta:evidence path=<that path> -->`.
    """

    rel_posix = (rel_posix or "").replace("\\", "/").lstrip("/")
    if not rel_posix:
        return False

    rel_l = rel_posix.lower()
    line_l = (it.text_with_comments or "").lower()
    if rel_l in line_l:
        return True

    for raw in (it.yta_evidence.get("paths") or []):
        p = (raw or "").replace("\\", "/").lstrip("/")
        if p.lower() == rel_l:
            return True

    return False


def _recommend_add_decision(
    rel_posix: str,
    *,
    deny_globs: list[str],
    deny_basenames: set[str],
    allow_globs: list[str],
    explicit_paths_l: set[str],
    allow_common_basename: bool,
) -> tuple[bool, str | None]:
    """Decide whether to emit an add recommendation for a path.

    Returns:
      (should_emit, suppression_hint)
    """

    rel_posix = (rel_posix or "").replace("\\", "/").lstrip("/")
    if not rel_posix:
        return False, "suppressed_add:empty_path"

    rel_l = rel_posix.lower()
    name_l = PurePosixPath(rel_posix).name.lower()

    # "Common file" basenames are always suppressed unless the *source TODO line*
    # explicitly references the exact path (allow_common_basename=True).
    if name_l in {b.lower() for b in deny_basenames} and not allow_common_basename:
        return False, f"suppressed_add:common_file({name_l})"

    # Allow-by-evidence exceptions (exact path only).
    if rel_l in explicit_paths_l:
        return True, None

    # Allow-glob beats deny (but does NOT override the common-file gate above).
    if _matches_any_glob(rel_posix, allow_globs):
        return True, None

    mg = _matches_any_glob(rel_posix, deny_globs)
    if mg:
        return False, f"suppressed_add:deny_glob({mg})"

    return True, None


def _recommended_section_keyword_for_paths(paths: list[str]) -> str | None:
    # Deterministic: check prefixes in a stable order.
    for prefix in sorted(SECTION_KEYWORD_BY_PREFIX.keys()):
        kw = SECTION_KEYWORD_BY_PREFIX[prefix]
        for p in paths:
            if (p or "").replace("\\", "/").startswith(prefix):
                return kw
    return None


def _section_contains_keyword(section_path: list[str], keyword: str) -> bool:
    kw = keyword.lower()
    for h in section_path:
        if kw in h.lower():
            return True
    return False


def _format_suggest_yta_evidence(hints: dict) -> str | None:
    """Create a weak-evidence suggestion for untagged TODO lines.

    RATIONALE:
    - Many TODO lines mention fields/keys/CLI commands without deterministic evidence tags.
    - This is report-only: it is never auto-applied, and it does not affect assessment.
    """

    if (hints or {}).get("source") != "heuristic":
        return None

    paths = list(hints.get("paths") or [])
    symbols = list(hints.get("symbols") or [])
    strings = list(hints.get("strings") or [])
    commands = list(hints.get("commands") or [])

    # CLI commands are treated as string evidence candidates.
    for c in commands:
        if c and c not in strings:
            strings.append(c)

    # Keep suggestions compact/deterministic.
    paths = paths[:2]
    symbols = symbols[:5]
    strings = strings[:3]

    parts: list[str] = []
    if paths:
        parts.append("path=" + ";".join(paths))
    if symbols:
        parts.append("symbols=" + ";".join(symbols))
    if strings:
        # Quote to allow spaces; semicolons make it copy/pasteable.
        safe = ";".join([s.replace('"', "") for s in strings])
        parts.append(f'strings="{safe}"')

    if not parts:
        return None
    return "suggest:yta:evidence " + " ".join(parts)


def build_plan_and_report_data(
    *,
    todo_path: Path,
    repo_root: Path,
    md_text: str,
    min_confidence: int,
    include_unknown: bool,
    max_items: int | None,
    suggest_additions: bool,
    suggest_ignore_globs: list[str] | None,
    recommend_allow_globs: list[str] | None = None,
    recommend_adds_enabled: bool = True,
    generated_at: str,
) -> tuple[dict, dict]:
    items = parse_markdown_todos(md_text)
    index = RepoTextIndex(repo_root=repo_root)

    # Used for "unless explicitly referenced" exceptions.
    explicit_paths_l = _collect_explicit_evidence_path_hints(items)

    # Effective allow/deny configuration for recommendation adds.
    recommend_deny_globs = _dedupe_stable(
        list(DEFAULT_RECOMMENDATION_DENY_GLOBS) + list(suggest_ignore_globs or [])
    )
    recommend_allow_globs = list(recommend_allow_globs or [])
    recommend_deny_basenames = {b.lower() for b in DEFAULT_RECOMMENDATION_DENY_BASENAMES}

    assessed: list[dict] = []
    assessed_by_id: dict[str, dict] = {}
    section_key_to_ids: dict[tuple[str, ...], list[str]] = {}
    counts = {"done_likely": 0, "partial_likely": 0, "not_done_likely": 0, "unknown": 0}

    raw_plan_items: list[dict] = []

    for item in items:
        a = compute_item_assessment(item, repo_root=repo_root, index=index)
        counts[a["status"]] = counts.get(a["status"], 0) + 1

        recs: list[dict] = []

        # Propose check.
        if (not item.checked) and a["status"] == "done_likely" and a["confidence"] >= min_confidence:
            recs.append(
                {
                    "action": "check",
                    "confidence": a["confidence"],
                    "reason": "Evidence suggests this TODO is already implemented.",
                    "evidence": a["evidence"],
                }
            )

        # Propose uncheck.
        if item.checked and a["status"] == "not_done_likely" and a["confidence"] >= min_confidence:
            recs.append(
                {
                    "action": "uncheck",
                    "confidence": a["confidence"],
                    "reason": "Evidence suggests this TODO is not implemented (e.g., referenced paths missing).",
                    "evidence": a["evidence"],
                }
            )

        # Checkbox drift / review prompts:
        # - checked but unclear/partial -> review manually
        # - checked but not_done_likely -> uncheck already handled above
        if item.checked and a["status"] in {"unknown", "partial_likely"}:
            recs.append(
                {
                    "action": "annotate",
                    "confidence": max(40, int(a.get("confidence") or 0)),
                    "reason": "Checkbox drift risk: item is checked but evidence is unclear/partial; review manually.",
                    "evidence": a["evidence"],
                }
            )

        # Propose move (very simple mapping).
        kw = _recommended_section_keyword_for_paths(a["hints"]["paths"])
        if kw and not _section_contains_keyword(item.section_path, kw):
            recs.append(
                {
                    "action": "move",
                    "confidence": min(80, max(60, a["confidence"])) if a["confidence"] else 60,
                    "reason": f"Item references paths under a domain mapped to '{kw}'.",
                    "evidence": a["evidence"][:2] + [f"section_map:{kw}"],
                    "to_section": kw,
                }
            )

        row = {"item": item, "assessment": a, "recs": recs, "hints": []}

        # Weak evidence suggestions (report-only) for untagged TODOs.
        if not item.has_explicit_evidence():
            sug = _format_suggest_yta_evidence(a.get("hints") or {})
            if sug:
                row["hints"].append(sug)
        assessed.append(row)
        assessed_by_id[item.todo_id] = row

        section_key = tuple(item.section_path or [])
        section_key_to_ids.setdefault(section_key, []).append(item.todo_id)

        for r in recs:
            # Keep annotate recommendations in the human report, but do not emit them into the
            # machine plan (since annotate is not an apply-able edit action).
            if r.get("action") == "annotate":
                continue
            raw_plan_items.append(
                {
                    "action": r["action"],
                    "target": {
                        "id": item.todo_id,
                        "line": item.line_no,
                        "text": item.text,
                    },
                    "from_section": item.section_display,
                    "to_section": r.get("to_section"),
                    "proposed_text": None,
                    "confidence": int(r.get("confidence", 0)),
                    "evidence": list(r.get("evidence", []))[:8],
                    "reason": r.get("reason", ""),
                }
            )

    add_suggestions: list[dict] = []
    recommend_adds_suppressed = 0
    recommend_adds_emitted = 0
    if suggest_additions and recommend_adds_enabled:
        # Completed-but-missing suggestions (low confidence, conservative).
        # IMPORTANT: gated behind --suggest-additions to prevent repo-wide “common file” auto-additions.
        md_lower = md_text.lower()
        add_candidates: list[tuple[str, str, tuple[str, ...]]] = []

        # Back-compat: "suggest_ignore_globs" is now the deny-glob list for recommendation adds.
        # IMPORTANT: do not pre-filter candidates using deny globs here; allow-glob must be able
        # to override deny. We apply deny/allow in _recommend_add_decision.

        def _tokenize_text_for_match(s: str) -> set[str]:
            s = (s or "").lower()
            tokens = [t for t in re.split(r"[^a-z0-9]+", s) if t]
            stop = {
                "a",
                "an",
                "and",
                "the",
                "to",
                "of",
                "in",
                "for",
                "on",
                "with",
                "as",
                "by",
                "or",
                "is",
                "are",
                "be",
                "make",
                "add",
                "update",
                "fix",
                "todo",
                "wip",
            }
            return {t for t in tokens if len(t) >= 3 and t not in stop}

        def _tokens_for_path(rel: str) -> set[str]:
            rel = (rel or "").replace("\\", "/")
            name = PurePosixPath(rel).name
            stem = Path(name).stem
            return _tokenize_text_for_match(stem)

        def _tokens_for_item(it: TodoItem) -> set[str]:
            tokens = set()
            tokens |= _tokenize_text_for_match(it.text)
            # Prefer backticked hints (higher signal).
            for m in re.finditer(r"`([^`]+)`", it.text):
                tok = (m.group(1) or "").strip().strip("\"'")
                tok = tok.strip("()[]{}<>")
                tok = tok.strip("`")
                tok = tok.replace("\\", "/")
                while tok.startswith("./"):
                    tok = tok[2:]
                if not tok:
                    continue
                tokens |= _tokenize_text_for_match(Path(tok).stem)
            return tokens

        def _best_existing_target_for_path(rel: str, *, section_path: list[str] | None) -> TodoItem | None:
            section_key = tuple(section_path or [])
            ids = section_key_to_ids.get(section_key) or []
            if not ids:
                return None
            cand_tokens = _tokens_for_path(rel)
            if not cand_tokens:
                return None

            best: tuple[int, int, str] | None = None
            best_item: TodoItem | None = None
            for tid in ids:
                row = assessed_by_id.get(tid)
                if not row:
                    continue
                it = row["item"]
                it_tokens = _tokens_for_item(it)
                score = len(cand_tokens & it_tokens)
                if score <= 0:
                    continue
                key = (-score, int(it.line_no), it.todo_id)
                if best is None or key < best:
                    best = key
                    best_item = it
            return best_item

        def _best_source_context_for_add(rel: str, *, section_path: list[str] | None) -> tuple[TodoItem | None, int, bool]:
            """Pick a concrete TODO item that "triggered" an add-suggestion.

            Returns: (best_item, token_overlap, exact_path_mentioned)

            CONTRACT:
            - If no item has any overlap and no item explicitly mentions the exact path,
              returns (None, 0, False).
            """

            rel_posix = (rel or "").replace("\\", "/").lstrip("/")
            if not rel_posix:
                return None, 0, False

            section_key = tuple(section_path or [])
            ids = section_key_to_ids.get(section_key) or []
            if not ids:
                return None, 0, False

            rel_l = rel_posix.lower()
            cand_tokens = _tokens_for_path(rel_posix)

            best: tuple[int, int, str] | None = None
            best_item: TodoItem | None = None
            best_overlap = 0
            best_exact = False

            for tid in ids:
                row = assessed_by_id.get(tid)
                if not row:
                    continue
                it = row["item"]

                line_l = (it.text_with_comments or "").lower()
                exact = rel_l in line_l
                overlap = 0
                if cand_tokens:
                    overlap = len(cand_tokens & _tokens_for_item(it))

                # Prefer exact path mention; else highest overlap.
                score = 10_000 if exact else overlap
                if score <= 0:
                    continue

                key = (-score, int(it.line_no), it.todo_id)
                if best is None or key < best:
                    best = key
                    best_item = it
                    best_overlap = overlap
                    best_exact = exact

            return best_item, int(best_overlap), bool(best_exact)

        def should_skip_add_candidate(rel_path: str) -> bool:
            """Return True if this file is too boilerplate/noisy for "add" suggestions."""

            rel_posix = (rel_path or "").replace("\\", "/").lstrip("/")
            if not rel_posix:
                return True

            p = PurePosixPath(rel_posix)
            parts_l = [x.lower() for x in p.parts]
            name_l = (p.name or "").lower()

            if "__pycache__" in parts_l:
                return True
            if name_l.endswith((".pyc", ".pyo")):
                return True
            if name_l.startswith("."):
                return True
            if name_l.startswith("test_"):
                return True
            if name_l.endswith("_test.py"):
                return True

            return False

        def extract_dir_context_from_section(section_path: list[str]) -> str | None:
            for h in reversed(section_path or []):
                for m in re.finditer(r"`([^`]+)`", h):
                    token = (m.group(1) or "").strip().strip("\"'")
                    token = token.strip("()[]{}<>")
                    token = token.strip("`")
                    token = token.replace("\\", "/")
                    while token.startswith("./"):
                        token = token[2:]
                    if not token or not token.endswith("/"):
                        continue
                    if not _looks_like_path(token):
                        continue
                    return token
                # Also allow parenthetical directory paths in headings.
                for m in re.finditer(r"\(([^)]+)\)", h):
                    token = (m.group(1) or "").strip().strip("\"'")
                    token = token.strip("()[]{}<>")
                    token = token.strip("`")
                    token = token.replace("\\", "/")
                    while token.startswith("./"):
                        token = token[2:]
                    if not token or not token.endswith("/"):
                        continue
                    if not _looks_like_path(token):
                        continue
                    return token
            return None

        # 1) Suggest only from explicit TODO section context directories (backticked, directory-like).
        # This avoids repo-wide scans that can produce noisy “common file” additions.
        # Map context dir -> representative section_path (so tests/scripts can be included only when explicit).
        context_dirs: dict[str, list[str]] = {}
        for it in items:
            ctx = extract_dir_context_from_section(it.section_path)
            if not ctx:
                continue
            if "<" in ctx or ">" in ctx:
                continue
            if ctx.startswith("scripts/"):
                # scripts suggestions are too noisy; keep conservative.
                continue

            # Keep default scan scope conservative.
            if not (
                ctx.startswith("youtube_automation/")
                or ctx.startswith("docs/")
                or ctx.startswith("tests/")
                or ctx.startswith("scripts/")
            ):
                continue

            context_dirs.setdefault(ctx, it.section_path)

        for ctx in sorted(context_dirs.keys()):
            if ctx.startswith("youtube_automation/ideas/"):
                kw = "Idea System"
                globs_to_scan = ["*.py", "py.typed"]
            elif ctx.startswith("youtube_automation/research/"):
                kw = "Research"
                globs_to_scan = ["*.py", "py.typed"]
            elif ctx.startswith("youtube_automation/interfaces/"):
                kw = "CLI"
                globs_to_scan = ["*.py", "py.typed"]
            elif ctx.startswith("docs/"):
                kw = "Docs"
                globs_to_scan = ["*.md"]
            elif ctx.startswith("tests/"):
                kw = "Tests"
                globs_to_scan = ["*.py"]
            elif ctx.startswith("scripts/"):
                kw = "Scripts"
                globs_to_scan = ["*.py"]
            else:
                continue

            abs_dir = (repo_root / ctx).resolve()
            if not abs_dir.is_dir():
                continue

            section_path = context_dirs.get(ctx)
            section_key = tuple(section_path or [])

            scan_files: list[Path] = []
            for pat in globs_to_scan:
                if pat == "py.typed":
                    pt = abs_dir / "py.typed"
                    if pt.exists() and pt.is_file():
                        scan_files.append(pt)
                    continue
                scan_files.extend(sorted(abs_dir.glob(pat)))

            for p in scan_files:
                rel = _safe_relpath(p, repo_root)
                if should_skip_add_candidate(rel):
                    continue
                if is_disallowed_addition(
                    rel,
                    section_path=section_path,
                    allow_tests=False,
                    allow_docs=False,
                ):
                    continue
                if rel.lower() in md_lower:
                    continue
                if p.name.lower() in md_lower:
                    continue
                add_candidates.append((rel, kw, section_key))

        for rel, kw, section_key in add_candidates[:25]:
            section_path = list(section_key)

            # Explicit operator override: if the user passed an allow-glob that matches this
            # candidate, we will treat that as a relevance signal (still requiring a concrete
            # source_context TODO line).
            allow_glob_hit = _matches_any_glob(rel, recommend_allow_globs)

            # Step 0: do not create add suggestions unless we can tie them to a concrete TODO line.
            source_item, overlap, exact_path_mentioned = _best_source_context_for_add(
                rel,
                section_path=section_path,
            )
            if source_item is None and allow_glob_hit:
                # Deterministic fallback: tie to the first TODO line in the section.
                ids = section_key_to_ids.get(section_key) or []
                if ids:
                    row0 = assessed_by_id.get(ids[0])
                    if row0 is not None:
                        source_item = row0["item"]
            if source_item is None:
                recommend_adds_suppressed += 1
                ids = section_key_to_ids.get(section_key) or []
                if ids:
                    row = assessed_by_id.get(ids[0])
                    if row is not None:
                        row["hints"].append("suppressed_add:no_source_context")
                continue

            # Relevance gate: exact path mention or token overlap.
            is_common_basename = PurePosixPath(rel).name.lower() in {
                b.lower() for b in DEFAULT_RECOMMENDATION_DENY_BASENAMES
            }
            relevance_ok = bool(
                exact_path_mentioned
                or bool(allow_glob_hit)
                or (overlap >= 2)
                or ((overlap >= 1) and (not is_common_basename))
            )
            if not relevance_ok:
                recommend_adds_suppressed += 1
                row = assessed_by_id.get(source_item.todo_id)
                if row is not None:
                    row["hints"].append("suppressed_add:irrelevant")
                continue

            # Common/low-signal files are only allowed when the *source TODO line*
            # explicitly references the exact relative path.
            allow_common_by_source = bool(_item_explicitly_references_path(source_item, rel))
            if is_common_basename and not allow_common_by_source:
                recommend_adds_suppressed += 1
                row = assessed_by_id.get(source_item.todo_id)
                if row is not None:
                    row["hints"].append(f"suppressed_add:common_file({PurePosixPath(rel).name})")
                continue

            should_emit, suppression_hint = _recommend_add_decision(
                rel,
                deny_globs=list(recommend_deny_globs),
                deny_basenames=set(recommend_deny_basenames),
                allow_globs=recommend_allow_globs,
                explicit_paths_l=explicit_paths_l,
                allow_common_basename=allow_common_by_source,
            )
            if not should_emit:
                recommend_adds_suppressed += 1
                # Attach hint to the source item so the report can show "why".
                if suppression_hint:
                    row = assessed_by_id.get(source_item.todo_id)
                    if row is not None:
                        row["hints"].append(suppression_hint)
                continue

            # PROPOSED: keep wording neutral; do not auto-claim completion.
            add_text = f"PROPOSED: consider tracking `{rel}` (file exists in repo)"
            add_id = compute_stable_todo_id(add_text)
            add_suggestions.append({"path": rel, "to_section": kw})
            raw_plan_items.append(
                {
                    "action": "add",
                    "target": {
                        "id": add_id,
                        "line": None,
                        "text": add_text,
                    },
                    "source_context": {
                        "todo_id": source_item.todo_id,
                        "explicit_id": source_item.explicit_id,
                        "todo_line": (source_item.raw_line or "").strip(),
                        "line": int(source_item.line_no),
                        "section_path": list(source_item.section_path or []),
                    },
                    "from_section": None,
                    "to_section": kw,
                    "proposed_text": f"- [ ] {add_text} <!-- yta:evidence id={add_id} path={rel} -->",
                    "confidence": 20,
                    "evidence": [f"exists:{rel}"],
                    "reason": (
                        "Repo contains an artifact not referenced in this TODO file; "
                        "consider tracking it (tied to a specific TODO line via source_context)."
                    ),
                }
            )
            recommend_adds_emitted += 1

    # Stable ordering for plan items.
    action_rank = {"check": 0, "uncheck": 1, "move": 2, "annotate": 3, "note": 3, "add": 4}
    raw_plan_items = sorted(
        raw_plan_items,
        key=lambda x: (
            action_rank.get(x["action"], 99),
            -int(x.get("confidence", 0)),
            (x.get("target") or {}).get("line", 10**9),
            json.dumps(x, sort_keys=True),
        ),
    )

    plan_items = raw_plan_items
    if max_items is not None:
        plan_items = plan_items[:max_items]

    # Filter per-item recommendations to only those that survived max_items.
    if max_items is not None:
        keep = set()
        for pi in plan_items:
            tgt = pi.get("target")
            if tgt and tgt.get("id"):
                keep.add((pi["action"], tgt["id"]))
        for row in assessed:
            item = row["item"]
            row["recs"] = [r for r in row["recs"] if (r["action"], item.todo_id) in keep]

    plan = {
        "todo_path": str(todo_path.as_posix()),
        "repo_root": str(repo_root.as_posix()),
        "generated_at": generated_at,
        "items": plan_items,
    }

    report_data = {
        "generated_at": generated_at,
        "assessed": assessed,
        "counts": counts,
        "include_unknown": include_unknown,
        "min_confidence": min_confidence,
        "add_suggestions": add_suggestions,
        "suggest_additions": bool(suggest_additions),
        "recommend_adds_suppressed": int(recommend_adds_suppressed),
        "recommend_adds_emitted": int(recommend_adds_emitted),
    }

    return plan, report_data

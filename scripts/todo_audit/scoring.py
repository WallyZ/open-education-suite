"""Status classification + confidence scoring for the TODO audit tool.

NOTE: Per your direction, this module is allowed to exceed the ~400 LOC target so we can
keep `compute_item_assessment` mechanically identical.
"""

from __future__ import annotations

import re
from pathlib import Path

from scripts.todo_audit.detectors import (
    _classify_symbol_hit,
    _extract_context_base_dir,
    _extract_implicit_evidence_tokens,
    _file_contains_any_field_patterns,
    _file_contains_any_key_patterns,
    _looks_like_filename,
    extract_hints,
)
from scripts.todo_audit.evidence import _normalize_hint_token
from scripts.todo_audit.repo_scan import ALLOWED_TEXT_EXTS, RepoTextIndex, _iter_text_files_under_dir
from scripts.todo_audit.todo_parse import TodoItem
from scripts.todo_audit.util import TEMPLATE_PLACEHOLDER_RE, _dedupe_stable, _safe_relpath, _truncate


def _expand_template_path(path_token: str, repo_root: Path) -> tuple[str, list[Path]]:
    """Expand a templated path token to concrete paths under repo_root.

    CONTRACT:
    - A "template" is any path containing `<...>` placeholders.
    - Placeholders are replaced with `*` and evaluated via `Path.glob`.
    - This is deterministic (sorted results) and offline-safe.

    Returns:
      (glob_token, matched_paths)
    """

    token = _normalize_hint_token(path_token)
    if not token:
        return "", []
    if not TEMPLATE_PLACEHOLDER_RE.search(token):
        return "", []

    # We only support repo-relative templates.
    p = Path(token)
    if p.is_absolute():
        try:
            token = p.resolve().relative_to(repo_root.resolve()).as_posix()
        except Exception:
            return "", []

    glob_token = TEMPLATE_PLACEHOLDER_RE.sub("*", token).replace("\\", "/")
    is_dir_hint = glob_token.endswith("/")
    pattern = glob_token.rstrip("/").lstrip("/")
    if not pattern:
        return glob_token, []

    matches: list[Path] = []
    try:
        for m in sorted(repo_root.glob(pattern)):
            if is_dir_hint and not m.is_dir():
                continue
            matches.append(m)
    except Exception:
        matches = []

    return glob_token, matches


def compute_item_assessment(
    item: TodoItem,
    *,
    repo_root: Path,
    index: RepoTextIndex,
) -> dict:

    def find_identifier_occurrences(
        identifier: str,
        *,
        candidate_paths: list[str] | None,
        max_files: int | None = 250,
        max_hits: int = 5,
    ) -> list[str]:
        """Return repo-relative paths where an identifier likely appears.

        RATIONALE:
        - Many TODOs reference fields/keys/strings rather than def/class symbols.
        - We want a fast, deterministic text scan using the existing repo index.
        - Prefer a narrowed candidate set when evidence provides paths.
        """

        ident = (identifier or "").strip()
        if not ident:
            return []

        paths: list[Path] = []
        if candidate_paths:
            for rel in candidate_paths:
                rel_posix = (rel or "").replace("\\", "/").lstrip("/")
                if not rel_posix:
                    continue
                paths.append((repo_root / rel_posix).resolve())
        else:
            # Deterministic scan: python files only.
            #
            # NOTE:
            # - In heuristic mode we keep this bounded to avoid scanning the whole repo
            #   for low-signal tokens.
            # - In explicit yta:evidence mode, callers may pass max_files=None to scan
            #   all indexed python files for higher accuracy.
            paths = [p for p in index.iter_text_files() if p.suffix.lower() == ".py"]
            if max_files is not None:
                paths = paths[: max(1, int(max_files))]

        esc = re.escape(ident)
        ident_pat = re.compile(rf"(?<![A-Za-z0-9_]){esc}(?![A-Za-z0-9_])")
        hits: list[str] = []
        for p in paths:
            if not p.is_file():
                continue
            txt = index.get_text(p)
            if not txt:
                continue
            if ident_pat.search(txt):
                hits.append(_safe_relpath(p, repo_root))
                if len(hits) >= max(1, int(max_hits)):
                    break
        return hits

    # Prefer explicit evidence tags over heuristic extraction.
    if item.has_explicit_evidence():
        paths: list[str] = list(item.yta_evidence.get("paths") or [])
        symbols: list[str] = list(item.yta_evidence.get("symbols") or [])
        strings: list[str] = list(item.yta_evidence.get("strings") or [])
        fields: list[str] = list(item.yta_evidence.get("fields") or [])
        keys: list[str] = list(item.yta_evidence.get("keys") or [])
        commands: list[str] = []
        used_source = "yta:evidence"
    else:
        hints = extract_hints(item.text)
        implicit = _extract_implicit_evidence_tokens(item.text)

        paths = hints["paths"]
        # Symbols from TODO text are often fields/keys; treat implicit identifiers as symbols.
        symbols = _dedupe_stable(list(hints["symbols"]) + list(implicit.get("identifiers") or []))
        commands = hints["commands"]
        # Non-identifier code-ish tokens become weak string evidence.
        strings = list(implicit.get("strings") or [])
        fields = []
        keys = []
        used_source = "heuristic"

    # Used to resolve bare-filename references like `backlog_file.py`.
    # (Even in yta:evidence mode, a heading backticked path can provide the preferred search scope.)
    context_base_dir = _extract_context_base_dir(item.section_path)

    evidence: list[str] = []
    done_points = 0
    not_done_points = 0
    has_ambiguity = False

    path_positive = False
    path_negative = False
    symbol_hit_any = False
    string_hit_any = False
    string_missing_any = False
    field_hit_any = False
    key_hit_any = False

    # Derived per-token totals for stable status classification.
    symbols_total = 0
    symbols_ok = 0

    paths_total = 0
    paths_ok = 0
    strings_total = 0
    strings_ok = 0
    fields_total = 0
    fields_ok = 0
    keys_total = 0
    keys_ok = 0

    # Avoid false positives: default searches should not count markdown/docs hits unless the
    # TODO explicitly points at docs.
    allow_docs_search = any(
        (p or "").replace("\\", "/").lstrip("/").lower().startswith("docs/")
        or (p or "").lower().endswith(".md")
        for p in (paths or [])
    )
    search_exts = set(ALLOWED_TEXT_EXTS)
    if not allow_docs_search:
        search_exts.discard(".md")

    # 1) Path existence.
    referenced_py_paths: list[Path] = []
    referenced_text_paths: list[Path] = []
    for raw in paths:
        token = _normalize_hint_token(raw)
        if not token:
            continue

        candidate = Path(token)
        if candidate.is_absolute() and repo_root not in candidate.parents:
            # Looks like a local drive path not under this repo; ignore.
            continue

        paths_total += 1

        # Placeholder directories like data/<channel_id>/ideas/ should be checked via globs.
        # (We treat any <...> placeholder as a wildcard for existence checks.)
        if TEMPLATE_PLACEHOLDER_RE.search(token) and not candidate.is_absolute():
            glob_token, matches = _expand_template_path(token, repo_root)
            if matches:
                done_points += 60 if used_source == "yta:evidence" else 50
                evidence.append(f"exists_glob:{glob_token}")
                path_positive = True
                paths_ok += 1

                # If the template expands to concrete files (or directories), use them as
                # deterministic scan scope for fields/keys evidence.
                for m in matches:
                    if m.is_file() and m.suffix.lower() == ".py":
                        referenced_py_paths.append(m)
                    if m.is_file() and m.suffix.lower() in ALLOWED_TEXT_EXTS:
                        referenced_text_paths.append(m)
                    if m.is_dir():
                        referenced_text_paths.extend(_iter_text_files_under_dir(m))
            else:
                not_done_points += 60 if used_source == "yta:evidence" else 50
                evidence.append(f"missing_glob:{glob_token or token}")
                path_negative = True
            continue

        rel = Path(token)
        if rel.is_absolute():
            try:
                rel = rel.resolve().relative_to(repo_root.resolve())
            except Exception:
                continue

        abs_path = (repo_root / rel).resolve()

        # Repo-smart basename resolver:
        # If the hint is a bare filename, check it:
        #   - as-is (repo root), AND
        #   - resolved against section base path (if present)
        # If neither exists, search the repo for a single basename match.
        if _looks_like_filename(token) and ("/" not in token and "\\" not in token) and not Path(token).is_absolute():
            abs_candidates: list[Path] = []
            if context_base_dir:
                abs_candidates.append((repo_root / Path(context_base_dir) / token).resolve())
            abs_candidates.append(abs_path)

            found_existing = False
            for abs_c in abs_candidates:
                if abs_c.exists():
                    rel_posix = _safe_relpath(abs_c, repo_root)
                    done_points += 60 if used_source == "yta:evidence" else 50
                    evidence.append(f"exists:{rel_posix}")
                    path_positive = True
                    found_existing = True
                    paths_ok += 1
                    if abs_c.suffix.lower() == ".py":
                        referenced_py_paths.append(abs_c)
                    if abs_c.suffix.lower() in ALLOWED_TEXT_EXTS:
                        referenced_text_paths.append(abs_c)
                    break

            if found_existing:
                continue

            # 3) Search for basename matches anywhere in the repo.
            # This is primarily intended for common TODO evidence that references only a filename.
            matches = index.find_paths_by_basename(token, limit=25)

            # Prefer section scope if it yields any matches.
            if context_base_dir:
                ctx_l = context_base_dir.lower()
                scoped = [m for m in matches if m.lower().startswith(ctx_l)]
                if scoped:
                    matches = scoped

            if len(matches) == 1:
                rel_posix = matches[0]
                done_points += 60 if used_source == "yta:evidence" else 50
                evidence.append(f"basename:{token}->{rel_posix}")
                path_positive = True
                paths_ok += 1
                if rel_posix.lower().endswith(".py"):
                    referenced_py_paths.append((repo_root / rel_posix).resolve())
                if Path(rel_posix).suffix.lower() in ALLOWED_TEXT_EXTS:
                    referenced_text_paths.append((repo_root / rel_posix).resolve())
            elif len(matches) > 1:
                has_ambiguity = True
                preview = ", ".join(matches[:6])
                suffix = "" if len(matches) <= 6 else f" (+{len(matches) - 6} more)"
                evidence.append(f"ambiguous_basename:{token} -> [{preview}]{suffix}")
            else:
                not_done_points += 60 if used_source == "yta:evidence" else 50
                if context_base_dir:
                    evidence.append(f"missing:{context_base_dir}{token}")
                evidence.append(f"missing:{token}")
                path_negative = True
            continue

        # Non-basename path resolution.
        rel_posix = _safe_relpath(abs_path, repo_root)
        if abs_path.exists():
            done_points += 60 if used_source == "yta:evidence" else 50
            evidence.append(f"exists:{rel_posix}")
            path_positive = True
            paths_ok += 1
            if abs_path.suffix.lower() == ".py":
                referenced_py_paths.append(abs_path)
            if abs_path.suffix.lower() in ALLOWED_TEXT_EXTS:
                referenced_text_paths.append(abs_path)
        else:
            not_done_points += 60 if used_source == "yta:evidence" else 50
            evidence.append(f"missing:{rel_posix}")
            path_negative = True

    # 2) Symbol presence via AST in referenced file(s) first.
    symbol_checked: set[str] = set()
    for py_path in referenced_py_paths:
        defs = index.python_defs_in_file(py_path)
        for sym in symbols:
            if sym in defs:
                done_points += 45 if used_source == "yta:evidence" else 40
                evidence.append(
                    f"symbol:def_or_class:{sym}@{_safe_relpath(py_path, repo_root)}"
                )
                symbol_checked.add(sym)
                symbol_hit_any = True

    # 3) Cheap repo-wide symbol lookup.
    for sym in symbols:
        if sym in symbol_checked:
            continue
        hits = index.search_substring(f"def {sym}", exts={".py"}, max_hits=2)
        if not hits:
            hits = index.search_substring(f"class {sym}", exts={".py"}, max_hits=2)
        if hits:
            done_points += 30 if used_source == "yta:evidence" else 25
            evidence.append(f"symbol:def_or_class:{sym} hit in {hits[0]}")
            symbol_checked.add(sym)
            symbol_hit_any = True

    # 3b) Identifier presence beyond def/class.
    # This catches common cases like dataclass fields, attribute access, and dict keys.
    # Prefer referenced python files; otherwise scan a bounded python subset.
    symbol_candidates: list[str] | None = None
    if referenced_py_paths:
        symbol_candidates = [_safe_relpath(p, repo_root) for p in referenced_py_paths]

    for sym in symbols:
        if sym in symbol_checked:
            continue
        hits = find_identifier_occurrences(
            sym,
            candidate_paths=symbol_candidates,
            max_files=(None if used_source == "yta:evidence" else 250),
        )
        if not hits:
            continue

        # Classify the first hit for clearer evidence.
        hit_path = hits[0]
        hit_abs = (repo_root / hit_path).resolve()
        txt = index.get_text(hit_abs)

        kind = _classify_symbol_hit(txt, sym)
        evidence.append(f"symbol:{kind}:{sym} hit in {hit_path}")

        done_points += 25 if used_source == "yta:evidence" else 20
        symbol_checked.add(sym)
        symbol_hit_any = True

    # Explicit symbol-missing evidence (important for partial classification).
    for sym in symbols:
        if sym not in symbol_checked:
            evidence.append(f"missing_symbol:{sym}")

    symbols_total = len([s for s in symbols if s])
    symbols_ok = len(symbol_checked)

    # 4) Explicit string checks.
    # If yta:evidence provided strings, treat them as strong indicators.
    for s in strings:
        if len(s) < 3:
            continue
        strings_total += 1
        hits = index.search_substring(s, exts=search_exts, max_hits=1)
        if hits:
            done_points += 25
            evidence.append(f"string:'{_truncate(s, 30)}' hit in {hits[0]}")
            string_hit_any = True
            strings_ok += 1
        else:
            not_done_points += 25
            evidence.append(f"string:'{_truncate(s, 30)}' not found")
            string_missing_any = True

    # 4b) Explicit field checks (yta:evidence only).
    # Match patterns like:
    #   - field_name:
    #   - self.field_name
    #   - field_name =
    # Deterministic, regex-based scanning; no imports, no execution.
    field_checked: set[str] = set()
    if used_source == "yta:evidence" and fields:
        py_candidates = referenced_py_paths
        if not py_candidates:
            py_candidates = [p for p in index.iter_text_files() if p.suffix.lower() == ".py"]

        for field_name in fields:
            if not field_name:
                continue
            fields_total += 1
            hit_path: str | None = None
            for p in py_candidates:
                txt = index.get_text(p)
                if _file_contains_any_field_patterns(txt, field_name):
                    hit_path = _safe_relpath(p, repo_root)
                    break

            if hit_path:
                done_points += 25
                evidence.append(f"field:{field_name} hit in {hit_path}")
                field_checked.add(field_name)
                field_hit_any = True
                fields_ok += 1
            else:
                not_done_points += 25
                evidence.append(f"missing_field:{field_name}")

    # 4c) Explicit key checks (yta:evidence only).
    # Match patterns like:
    #   - ["key"] / ['key']
    #   - "key": / 'key':
    key_checked: set[str] = set()
    if used_source == "yta:evidence" and keys:
        text_candidates = referenced_text_paths
        if not text_candidates:
            text_candidates = index.iter_text_files()

        for key_name in keys:
            if not key_name:
                continue
            keys_total += 1
            hit_path = None
            for p in text_candidates:
                txt = index.get_text(p)
                if _file_contains_any_key_patterns(txt, key_name):
                    hit_path = _safe_relpath(p, repo_root)
                    break

            if hit_path:
                done_points += 25
                evidence.append(f"key:{key_name} hit in {hit_path}")
                key_checked.add(key_name)
                key_hit_any = True
                keys_ok += 1
            else:
                not_done_points += 25
                evidence.append(f"missing_key:{key_name}")

    # 5) CLI-ish strings (heuristic mode only).
    for cmd in commands:
        tokens = [t for t in re.split(r"\s+", cmd.strip()) if t]
        if not tokens:
            continue

        probes: list[str] = []
        probes.append(cmd)
        probes.extend(tokens[:3])
        for t in tokens:
            if "-" in t:
                probes.append(t.replace("-", "_"))

        cmd_hits: list[tuple[str, str]] = []
        for probe in probes:
            if len(probe) < 3:
                continue
            hits = index.search_substring(probe, exts={".py"}, max_hits=1)
            if hits:
                cmd_hits.append((probe, hits[0]))

        if cmd_hits:
            done_points += 20
            probe, hit = cmd_hits[0]
            evidence.append(f"cmd:'{_truncate(probe, 40)}' hit in {hit}")

    # Determine status.
    # Targets per wave spec: done_likely / partial_likely / not_done_likely / unknown
    if used_source == "yta:evidence":
        groups_present = {
            "paths": paths_total > 0,
            "symbols": bool(symbols),
            "strings": strings_total > 0,
            "fields": fields_total > 0,
            "keys": keys_total > 0,
        }
        groups_satisfied = {
            "paths": (paths_total > 0) and (paths_ok == paths_total) and (not has_ambiguity),
            "symbols": bool(symbols) and (len(symbol_checked) == len(set(symbols))),
            "strings": (strings_total > 0) and (strings_ok == strings_total),
            "fields": (fields_total > 0) and (fields_ok == fields_total),
            "keys": (keys_total > 0) and (keys_ok == keys_total),
        }

        failed_groups = [
            k
            for k in ("paths", "symbols", "strings", "fields", "keys")
            if groups_present.get(k) and not groups_satisfied.get(k)
        ]
        if failed_groups:
            evidence.append("failed_groups:" + ",".join(failed_groups))

        # Token-level classification (stable): partial when some evidence hits and some misses.
        token_total = paths_total + symbols_total + strings_total + fields_total + keys_total
        token_hits = paths_ok + symbols_ok + strings_ok + fields_ok + keys_ok
        token_misses = token_total - token_hits

        if has_ambiguity:
            status = "unknown"
            confidence = 50
        elif token_total == 0:
            status = "unknown"
            confidence = 50
            evidence.append("audit_hint:no_evidence_tokens")
        elif token_hits > 0 and token_misses == 0:
            status = "done_likely"
            confidence = 90
        elif token_hits == 0 and token_misses > 0:
            status = "not_done_likely"
            confidence = 50
        else:
            status = "partial_likely"
            confidence = 65

        # Do not auto-downgrade checked items; warn instead.
        if item.checked and token_misses > 0:
            evidence.append("drift:checked_but_missing_evidence")
            status = "done_likely"
            confidence = max(75, int(confidence))

        # Report-only status mapping (does not affect apply semantics).
        if has_ambiguity or status == "unknown":
            report_status = "unclear"
        elif token_total >= 2 and token_hits > 0 and token_misses > 0:
            report_status = "partial"
        else:
            report_status = status

        return {
            "status": status,
            "report_status": report_status,
            "confidence": int(confidence),
            "evidence": evidence,
            "hints": {
                "paths": list(paths),
                "symbols": list(symbols),
                "strings": list(strings),
                "fields": list(fields),
                "keys": list(keys),
                "commands": list(commands),
                "source": used_source,
            },
            "todo_id": item.todo_id,
        }

    symbols_required = bool(symbols)
    symbols_missing_any = symbols_required and (len(symbol_checked) < len(set(symbols)))

    # Token-level classification for heuristic evidence.
    token_total = paths_total + symbols_total + strings_total
    token_hits = paths_ok + symbols_ok + strings_ok
    token_misses = token_total - token_hits

    if has_ambiguity:
        status = "unknown"
        confidence = 50
    elif token_total == 0:
        status = "unknown"
        confidence = 50
        evidence.append("audit_hint:no_evidence_tokens")
    elif token_hits > 0 and token_misses == 0:
        status = "done_likely"
        confidence = 78
    elif token_hits == 0 and token_misses > 0:
        status = "not_done_likely"
        confidence = 50
    else:
        status = "partial_likely"
        confidence = 65

    # Do not auto-downgrade checked items; warn instead.
    if item.checked and token_misses > 0:
        evidence.append("drift:checked_but_missing_evidence")
        status = "done_likely"
        confidence = max(75, int(confidence))

    # Report-only status mapping (does not affect apply semantics).
    # Heuristic-only evidence is considered weak unless anchored by at least one path hint.
    strong_heuristic = paths_total > 0
    if has_ambiguity or status == "unknown":
        report_status = "unclear"
    elif token_total >= 2 and token_hits > 0 and token_misses > 0:
        report_status = "partial"
    elif not strong_heuristic:
        report_status = "unclear"
    else:
        report_status = status

    # Keep legacy boolean flags for internal drift heuristics.
    _ = symbols_missing_any
    _ = symbol_hit_any
    _ = string_hit_any

    return {
        "status": status,
        "report_status": report_status,
        "confidence": int(confidence),
        "evidence": evidence,
        "hints": {
            "paths": list(paths),
            "symbols": list(symbols),
            "strings": list(strings),
            "fields": list(fields),
            "keys": list(keys),
            "commands": list(commands),
            "source": used_source,
        },
        "todo_id": item.todo_id,
    }

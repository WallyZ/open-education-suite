"""Repo scanning and safe file read helpers for the TODO audit tool."""

from __future__ import annotations

import ast
from pathlib import Path

from scripts.todo_audit.util import _dedupe_stable, _safe_relpath


IGNORE_DIR_NAMES = {
    ".git",
    ".venv",
    "venv",
    "__pycache__",
    "site-packages",
    "node_modules",
    "dist",
    "build",
    "tools",
    "data",
    "downloads",
    "runtime",
    "logs",
    ".mypy_cache",
    ".pytest_cache",
}


ALLOWED_TEXT_EXTS = {
    ".py",
    ".md",
    ".txt",
    ".toml",
    ".yaml",
    ".yml",
    ".json",
    ".jsonl",
    ".ini",
    ".cfg",
    ".ts",
    ".tsx",
    ".js",
    ".ps1",
    ".bat",
    ".sh",
}


MAX_TEXT_FILE_BYTES = 1_500_000


class RepoTextIndex:
    def __init__(self, repo_root: Path):
        self.repo_root = repo_root
        self._file_list: list[Path] | None = None
        self._text_cache: dict[str, str] = {}
        self._ast_defs_cache: dict[str, set[str]] = {}

    def _is_ignored_path(self, rel: Path) -> bool:
        for part in rel.parts:
            if part in IGNORE_DIR_NAMES:
                return True
        return False

    def iter_text_files(self) -> list[Path]:
        if self._file_list is not None:
            return self._file_list
        out: list[Path] = []
        for p in sorted(self.repo_root.rglob("*")):
            if not p.is_file():
                continue
            try:
                rel = p.relative_to(self.repo_root)
            except Exception:
                continue
            if self._is_ignored_path(rel):
                continue
            if p.suffix.lower() not in ALLOWED_TEXT_EXTS:
                continue
            try:
                if p.stat().st_size > MAX_TEXT_FILE_BYTES:
                    continue
            except OSError:
                continue
            out.append(p)
        self._file_list = out
        return out

    def get_text(self, path: Path) -> str:
        key = _safe_relpath(path, self.repo_root)
        if key in self._text_cache:
            return self._text_cache[key]
        try:
            txt = path.read_text(encoding="utf-8", errors="replace")
        except Exception:
            txt = ""
        self._text_cache[key] = txt
        return txt

    def search_substring(
        self,
        needle: str,
        *,
        exts: set[str] | None = None,
        max_hits: int = 5,
        case_sensitive: bool = False,
    ) -> list[str]:
        if not needle:
            return []
        hits: list[str] = []
        needle_cmp = needle if case_sensitive else needle.lower()
        for p in self.iter_text_files():
            if exts is not None and p.suffix.lower() not in exts:
                continue
            txt = self.get_text(p)
            hay = txt if case_sensitive else txt.lower()
            if needle_cmp in hay:
                hits.append(_safe_relpath(p, self.repo_root))
                if len(hits) >= max_hits:
                    break
        return hits

    def python_defs_in_file(self, py_path: Path) -> set[str]:
        key = _safe_relpath(py_path, self.repo_root)
        if key in self._ast_defs_cache:
            return self._ast_defs_cache[key]
        names: set[str] = set()
        try:
            txt = self.get_text(py_path)
            tree = ast.parse(txt, filename=str(py_path))
            for node in ast.walk(tree):
                if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                    names.add(node.name)
        except Exception:
            names = set()
        self._ast_defs_cache[key] = names
        return names

    def find_paths_by_basename(self, basename: str, *, limit: int = 10) -> list[str]:
        """Find repo-relative paths whose basename matches (case-insensitive).

        CONTRACT:
        - Deterministic ordering (sorted output)
        - Offline-safe: uses the existing index file list
        - Conservative: searches only the indexed text file set
        """

        base = (basename or "").strip()
        if not base:
            return []
        if "/" in base or "\\" in base:
            return []

        base_l = base.lower()
        hits: list[str] = []
        for p in self.iter_text_files():
            if p.name.lower() != base_l:
                continue
            hits.append(_safe_relpath(p, self.repo_root))
            if len(hits) >= max(1, int(limit)):
                break

        # Stable/deterministic ordering independent of filesystem traversal.
        hits = _dedupe_stable(hits)
        return sorted(hits, key=lambda s: s.lower())


def iter_text_files_under_dir(root: Path, *, max_files: int = 250) -> list[Path]:
    """Collect a bounded set of text files under a directory.

    RATIONALE:
    - RepoTextIndex intentionally ignores some large/noisy roots (e.g. data/).
    - For explicit `yta:evidence path=...` templates that expand into such directories,
      we still want deterministic evidence checks without scanning the whole repo.
    """

    if not root.exists() or not root.is_dir():
        return []

    out: list[Path] = []
    try:
        for p in sorted(root.rglob("*")):
            if not p.is_file():
                continue
            if p.suffix.lower() not in ALLOWED_TEXT_EXTS:
                continue
            try:
                if p.stat().st_size > MAX_TEXT_FILE_BYTES:
                    continue
            except OSError:
                continue
            out.append(p)
            if len(out) >= max_files:
                break
    except Exception:
        return []

    return out


# Back-compat alias: the original monolith used a private helper name.
_iter_text_files_under_dir = iter_text_files_under_dir

"""TODO metadata parsing helpers.

Supported optional metadata tags:
- <!-- ms:meta ... -->
- <!-- yta:meta ... -->

Metadata is advisory and used for ready-queue planning.
"""

from __future__ import annotations

import re

from scripts.todo_audit.evidence import HTML_COMMENT_RE, _split_list_value
from scripts.todo_audit.util import _dedupe_stable


META_KEY_ALIASES = {
    "priority": "priority",
    "owner": "owner",
    "owners": "owner",
    "depends-on": "depends_on",
    "depends_on": "depends_on",
    "depends": "depends_on",
    "blocked-by": "blocked_by",
    "blocked_by": "blocked_by",
    "blocked": "blocked_by",
    "target-repo": "target_repo",
    "target_repo": "target_repo",
    "stale-days": "stale_days",
    "stale_days": "stale_days",
    "stale-age": "stale_days",
    "stale_age": "stale_days",
    "automation-level": "automation_level",
    "automation_level": "automation_level",
    "human-checkpoint": "human_checkpoint",
    "human_checkpoint": "human_checkpoint",
    "rollout-scope": "rollout_scope",
    "rollout_scope": "rollout_scope",
    "validation-profile": "validation_profile",
    "validation_profile": "validation_profile",
    "safe-autofix": "safe_autofix",
    "safe_autofix": "safe_autofix",
    "updated": "updated",
    "last-reviewed": "updated",
    "last_reviewed": "updated",
}


PRIORITY_ALLOWED = {"p0", "p1", "p2", "p3", "high", "medium", "low"}
AUTOMATION_ALLOWED = {"auto", "assisted", "manual", "none"}
VALIDATION_PROFILE_ALLOWED = {"32k", "64k", "cloud", "full"}
SAFE_AUTOFIX_ALLOWED = {"safe", "review", "manual", "none", "auto"}
_KEYVAL_RE = re.compile(r"(?P<key>[A-Za-z_][A-Za-z0-9_-]*)\s*=\s*(?P<val>\"[^\"]*\"|'[^']*'|\S+)")
_META_PREFIXES = ("ms:meta", "yta:meta")


def _normalize_token(value: str) -> str:
    return (value or "").strip().strip("\"'")


def _parse_int(value: str) -> int | None:
    token = _normalize_token(value)
    if not token:
        return None
    try:
        return int(token)
    except Exception:
        return None


def parse_todo_metadata(text_with_comments: str) -> dict:
    """Parse optional metadata tags from a checkbox line's comment text."""

    meta = {
        "present": False,
        "namespaces": [],
        "priority": None,
        "owner": [],
        "depends_on": [],
        "blocked_by": [],
        "target_repo": None,
        "stale_days": None,
        "stale_days_raw": None,
        "automation_level": None,
        "human_checkpoint": None,
        "rollout_scope": None,
        "validation_profile": None,
        "safe_autofix": None,
        "updated": None,
        "unknown_keys": [],
    }

    namespaces: list[str] = []
    unknown_keys: list[str] = []

    for m in HTML_COMMENT_RE.finditer(text_with_comments or ""):
        body = (m.group("body") or "").strip()
        body_l = body.lower()
        if not body_l.startswith(_META_PREFIXES):
            continue

        meta["present"] = True
        ns = body_l.split(":", 1)[0].strip()
        namespaces.append(ns)

        rest = body.split(":", 1)[1]
        rest = rest[len("meta") :].strip()
        for km in _KEYVAL_RE.finditer(rest):
            raw_key = (km.group("key") or "").strip().lower()
            val = (km.group("val") or "").strip()
            canon = META_KEY_ALIASES.get(raw_key)
            if not canon:
                unknown_keys.append(raw_key)
                continue

            if canon in {"owner", "depends_on", "blocked_by"}:
                values = [_normalize_token(x) for x in _split_list_value(val)]
                meta[canon].extend([x for x in values if x])
                continue

            if canon == "stale_days":
                meta["stale_days_raw"] = _normalize_token(val)
                meta["stale_days"] = _parse_int(val)
                continue

            meta[canon] = _normalize_token(val) or None

    for key in ("owner", "depends_on", "blocked_by"):
        meta[key] = _dedupe_stable([x for x in meta[key] if x])

    meta["namespaces"] = sorted(set([x for x in namespaces if x]))
    meta["unknown_keys"] = _dedupe_stable([x for x in unknown_keys if x])
    return meta

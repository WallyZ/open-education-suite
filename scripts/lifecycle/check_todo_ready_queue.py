#!/usr/bin/env python3
"""check_todo_ready_queue.py

Build and validate a cross-file TODO ready queue.

Goals:
- Surface unblocked, high-value work first.
- Flag dependency/blocker issues.
- Separate auto-eligible tasks from human-required tasks.
"""

from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Literal
import sys

# Ensure repo imports work when this script is run directly.
_REPO_ROOT_BOOTSTRAP = Path(__file__).resolve().parents[2]
for _p in (_REPO_ROOT_BOOTSTRAP, _REPO_ROOT_BOOTSTRAP / "scripts"):
    _s = str(_p)
    if _s not in sys.path:
        sys.path.insert(0, _s)

from scripts.todo_audit.todo_parse import (
    TodoItem,
    extract_agent_file_paths,
    parse_markdown_todos,
    parse_todo_agent_sections,
)
from scripts.todo_audit.util import _iso_utc_now


Severity = Literal["info", "warn", "error"]
SEVERITY_RANK = {"info": 0, "warn": 1, "error": 2}
PHASE_RE = re.compile(r"\[PH(?P<num>[123])\]", re.IGNORECASE)
NONE_TOKENS = {"", "none", "no", "false", "0", "na", "n/a"}
AGENT_QUEUE_SCHEMA_VERSION = 1
AGENT_QUEUE_SCHEMA_ID = "repo-kit.todo-agent-queue.v1"
AGENT_QUEUE_SCHEMA_PATH = "repo-standards/todo/todo_agent_queue.schema.json"
AGENT_REQUIRED_EXPORT_FIELDS = {
    "task_id": "task id",
    "phase": "phase",
    "priority": "priority",
    "files": "files",
    "verification": "verification",
    "qa_live_automation": "QA Live automation",
    "acceptance": "acceptance",
    "drift_guard": "drift guard",
    "downstream_rollout": "downstream rollout",
    "dependencies": "dependencies",
    "stale_threshold": "stale threshold",
    "validation_profile": "validation profile",
}


@dataclass(frozen=True)
class QueueIssue:
    severity: Severity
    code: str
    message: str
    todo_id: str | None = None
    file: str | None = None
    line: int | None = None


@dataclass
class QueueRow:
    todo_id: str
    text: str
    file: str
    line: int
    phase: int
    priority: str
    priority_rank: int
    owner: str
    target_repo: str
    validation_profile: str
    automation_level: str
    safe_autofix: str
    human_checkpoint: str
    depends_on: list[str]
    blocked_by: list[str]
    blocked_reasons: list[str]
    stale_days: int | None
    age_days: int
    stale: bool
    auto_eligible: bool
    deliverables: list[str]
    files: list[str]
    files_raw: list[str]
    file_refs: list[dict]
    verification: list[str]
    qa_live_automation: list[str]
    drift_guard: list[str]
    downstream_rollout: list[str]
    acceptance: list[str]
    agent_ready: bool
    agent_ready_missing: list[str]


def normalize_rel(path: Path, repo_root: Path) -> str:
    try:
        return path.resolve().relative_to(repo_root.resolve()).as_posix()
    except Exception:
        return path.as_posix().replace("\\", "/")


def iter_todo_files(todo_root: Path) -> list[Path]:
    files: list[Path] = []
    for p in sorted(todo_root.rglob("*.md")):
        if not p.is_file():
            continue
        rel = p.relative_to(todo_root).as_posix()
        if rel.startswith("_archive/"):
            continue
        files.append(p)
    return files


def parse_phase(text: str) -> int:
    m = PHASE_RE.search(text or "")
    if not m:
        return 9
    try:
        return int(m.group("num"))
    except Exception:
        return 9


def priority_rank(value: str | None) -> tuple[str, int]:
    token = (value or "").strip().lower()
    mapping = {
        "p0": 0,
        "high": 0,
        "p1": 1,
        "p2": 2,
        "medium": 2,
        "p3": 3,
        "low": 3,
    }
    rank = mapping.get(token, 4)
    return (token or "(unset)"), rank


def parse_updated_date(value: str | None, *, fallback_dt: datetime) -> date:
    token = (value or "").strip()
    if token:
        try:
            return datetime.strptime(token, "%Y-%m-%d").date()
        except Exception:
            pass
    return fallback_dt.astimezone(timezone.utc).date()


def classify_auto_eligible(meta: dict) -> bool:
    automation = (meta.get("automation_level") or "").strip().lower()
    safe_autofix = (meta.get("safe_autofix") or "").strip().lower()
    checkpoint = (meta.get("human_checkpoint") or "").strip().lower()
    checkpoint_required = checkpoint not in NONE_TOKENS

    if checkpoint_required:
        return False
    if automation in {"auto"}:
        return True
    if safe_autofix in {"safe", "auto"}:
        return True
    return False


def build_file_refs(paths: list[str], *, repo_root: Path) -> list[dict]:
    refs: list[dict] = []
    for rel in paths:
        token = (rel or "").strip().replace("\\", "/")
        if not token:
            continue
        candidate = Path(token)
        exists = candidate.exists() if candidate.is_absolute() else (repo_root / token).exists()
        refs.append({"path": token, "exists": bool(exists)})
    return refs


def compute_agent_ready_missing(
    *,
    todo_id: str,
    phase: int,
    priority: str,
    files: list[str],
    verification: list[str],
    qa_live_automation: list[str],
    acceptance: list[str],
    drift_guard: list[str],
    downstream_rollout: list[str],
    depends_on: list[str],
    stale_days: int | None,
    validation_profile: str,
) -> list[str]:
    missing: list[str] = []
    values = {
        "task_id": todo_id,
        "phase": None if phase == 9 else phase,
        "priority": "" if priority == "(unset)" else priority,
        "files": files,
        "verification": verification,
        "qa_live_automation": qa_live_automation,
        "acceptance": acceptance,
        "drift_guard": drift_guard,
        "downstream_rollout": downstream_rollout,
        "dependencies": depends_on,
        "stale_threshold": stale_days,
        "validation_profile": "" if validation_profile == "(unset)" else validation_profile,
    }
    for key, label in AGENT_REQUIRED_EXPORT_FIELDS.items():
        value = values[key]
        if key == "dependencies":
            # Empty dependencies are still explicit because the field is always exported.
            continue
        if value is None:
            missing.append(label)
        elif isinstance(value, str) and not value.strip():
            missing.append(label)
        elif isinstance(value, list) and not any(str(x).strip() for x in value):
            missing.append(label)
    return missing


def build_queue(repo_root: Path, todo_root: Path) -> tuple[list[QueueRow], list[QueueIssue], dict]:
    files = iter_todo_files(todo_root)
    open_items: list[tuple[TodoItem, str, datetime, dict[str, list[str]]]] = []
    all_items: list[TodoItem] = []

    for f in files:
        text = f.read_text(encoding="utf-8", errors="replace")
        rel = normalize_rel(f, repo_root)
        mtime = datetime.fromtimestamp(f.stat().st_mtime, tz=timezone.utc)
        sections_by_line = parse_todo_agent_sections(text)
        for item in parse_markdown_todos(text):
            all_items.append(item)
            if item.checked:
                continue
            open_items.append((item, rel, mtime, sections_by_line.get(item.line_no, {})))

    id_to_item: dict[str, TodoItem] = {}
    for item in all_items:
        id_to_item[item.todo_id] = item

    issues: list[QueueIssue] = []
    rows: list[QueueRow] = []

    # Duplicate open text detection across split TODO files.
    text_groups: dict[str, list[tuple[TodoItem, str]]] = {}
    for item, rel, _mtime, _sections in open_items:
        key = re.sub(r"\s+", " ", (item.text or "").strip().lower())
        if not key:
            continue
        text_groups.setdefault(key, []).append((item, rel))

    for key, members in sorted(text_groups.items(), key=lambda kv: kv[0]):
        if len(members) <= 1:
            continue
        preview = (members[0][0].text or "").strip()
        refs = ", ".join([f"{rel}:{it.line_no}" for it, rel in members[:4]])
        suffix = "" if len(members) <= 4 else f" (+{len(members) - 4} more)"
        issues.append(
            QueueIssue(
                severity="warn",
                code="DUPLICATE_OPEN_TEXT",
                message=f"Potential duplicate open TODO: {preview!r} at {refs}{suffix}",
            )
        )

    today = datetime.now(tz=timezone.utc).date()

    for item, rel, mtime, sections in open_items:
        meta = dict(item.meta or {})
        p_label, p_rank = priority_rank(meta.get("priority"))
        owner = ",".join(meta.get("owner") or [])
        target_repo = (meta.get("target_repo") or "").strip() or "(unset)"
        validation_profile = (meta.get("validation_profile") or "").strip() or "(unset)"
        automation_level = (meta.get("automation_level") or "").strip() or "(unset)"
        safe_autofix = (meta.get("safe_autofix") or "").strip() or "(unset)"
        human_checkpoint = (meta.get("human_checkpoint") or "").strip() or "(unset)"

        depends_on = [str(x).strip() for x in (meta.get("depends_on") or []) if str(x).strip()]
        blocked_by = [str(x).strip() for x in (meta.get("blocked_by") or []) if str(x).strip()]

        blocked_reasons: list[str] = []
        for dep in depends_on:
            dep_item = id_to_item.get(dep)
            if dep_item is None:
                blocked_reasons.append(f"missing_dependency:{dep}")
                issues.append(
                    QueueIssue(
                        severity="warn",
                        code="DEPENDENCY_MISSING",
                        todo_id=item.todo_id,
                        file=rel,
                        line=item.line_no,
                        message=f"depends-on references unknown TODO id: {dep}",
                    )
                )
                continue
            if not dep_item.checked:
                blocked_reasons.append(f"depends_on_open:{dep}")

        for blk in blocked_by:
            blocked_reasons.append(f"blocked_by:{blk}")

        stale_days = meta.get("stale_days")
        updated = parse_updated_date(meta.get("updated"), fallback_dt=mtime)
        age_days = max(0, (today - updated).days)
        stale = isinstance(stale_days, int) and stale_days > 0 and age_days > stale_days
        if stale:
            issues.append(
                QueueIssue(
                    severity="warn",
                    code="STALE_ITEM",
                    todo_id=item.todo_id,
                    file=rel,
                    line=item.line_no,
                    message=(
                        f"TODO item exceeded stale-days threshold ({age_days}d > {stale_days}d)."
                    ),
                )
            )

        deliverables = [str(x).strip() for x in sections.get("deliverables", []) if str(x).strip()]
        files_raw = [str(x).strip() for x in sections.get("files", []) if str(x).strip()]
        parsed_files = extract_agent_file_paths(files_raw)
        verification = [str(x).strip() for x in sections.get("verification", []) if str(x).strip()]
        qa_live_automation = [
            str(x).strip() for x in sections.get("qa_live_automation", []) if str(x).strip()
        ]
        drift_guard = [str(x).strip() for x in sections.get("drift_guard", []) if str(x).strip()]
        downstream_rollout = [
            str(x).strip() for x in sections.get("downstream_rollout", []) if str(x).strip()
        ]
        acceptance = [str(x).strip() for x in sections.get("acceptance", []) if str(x).strip()]
        agent_missing = compute_agent_ready_missing(
            todo_id=item.todo_id,
            phase=parse_phase(item.text),
            priority=p_label,
            files=parsed_files,
            verification=verification,
            qa_live_automation=qa_live_automation,
            acceptance=acceptance,
            drift_guard=drift_guard,
            downstream_rollout=downstream_rollout,
            depends_on=depends_on,
            stale_days=stale_days if isinstance(stale_days, int) else None,
            validation_profile=validation_profile,
        )

        rows.append(
            QueueRow(
                todo_id=item.todo_id,
                text=item.text,
                file=rel,
                line=item.line_no,
                phase=parse_phase(item.text),
                priority=p_label,
                priority_rank=p_rank,
                owner=owner or "(unset)",
                target_repo=target_repo,
                validation_profile=validation_profile,
                automation_level=automation_level,
                safe_autofix=safe_autofix,
                human_checkpoint=human_checkpoint,
                depends_on=depends_on,
                blocked_by=blocked_by,
                blocked_reasons=blocked_reasons,
                stale_days=stale_days if isinstance(stale_days, int) else None,
                age_days=age_days,
                stale=bool(stale),
                auto_eligible=classify_auto_eligible(meta),
                deliverables=deliverables,
                files=parsed_files,
                files_raw=files_raw,
                file_refs=build_file_refs(parsed_files, repo_root=repo_root),
                verification=verification,
                qa_live_automation=qa_live_automation,
                drift_guard=drift_guard,
                downstream_rollout=downstream_rollout,
                acceptance=acceptance,
                agent_ready=not agent_missing,
                agent_ready_missing=agent_missing,
            )
        )

    rows.sort(
        key=lambda r: (
            r.priority_rank,
            r.phase,
            0 if not r.blocked_reasons else 1,
            0 if r.auto_eligible else 1,
            r.file,
            r.line,
            r.todo_id,
        )
    )

    summary = {
        "open_total": len(rows),
        "blocked_total": sum(1 for r in rows if r.blocked_reasons),
        "ready_auto": sum(1 for r in rows if (not r.blocked_reasons) and r.auto_eligible),
        "ready_human": sum(1 for r in rows if (not r.blocked_reasons) and (not r.auto_eligible)),
        "stale_total": sum(1 for r in rows if r.stale),
        "issues": {
            "error": sum(1 for i in issues if i.severity == "error"),
            "warn": sum(1 for i in issues if i.severity == "warn"),
            "info": sum(1 for i in issues if i.severity == "info"),
        },
        "agent_ready_total": sum(1 for r in rows if r.agent_ready),
        "agent_not_ready_total": sum(1 for r in rows if not r.agent_ready),
    }

    return rows, issues, summary


def filter_issues(issues: list[QueueIssue], min_severity: Severity) -> list[QueueIssue]:
    floor = SEVERITY_RANK[min_severity]
    return [i for i in issues if SEVERITY_RANK[i.severity] >= floor]


def render_markdown(rows: list[QueueRow], issues: list[QueueIssue], summary: dict, *, generated_at: str) -> str:
    out: list[str] = []
    out.append("# TODO Ready Queue Report")
    out.append("")
    out.append(f"- generated_at: `{generated_at}`")
    out.append("")
    out.append("## Summary")
    out.append("")
    out.append(f"- open_total: **{summary['open_total']}**")
    out.append(f"- ready_auto: **{summary['ready_auto']}**")
    out.append(f"- ready_human: **{summary['ready_human']}**")
    out.append(f"- blocked_total: **{summary['blocked_total']}**")
    out.append(f"- stale_total: **{summary['stale_total']}**")
    out.append(f"- agent_ready_total: **{summary['agent_ready_total']}**")
    out.append(f"- agent_not_ready_total: **{summary['agent_not_ready_total']}**")
    out.append(f"- issues: **error={summary['issues']['error']} warn={summary['issues']['warn']} info={summary['issues']['info']}**")
    out.append("")

    out.append("## Issues")
    out.append("")
    if not issues:
        out.append("_(none)_")
        out.append("")
    else:
        out.append("| Severity | Code | Item | Message |")
        out.append("| --- | --- | --- | --- |")
        for it in issues:
            ref = ""
            if it.file and it.line:
                ref = f"`{it.file}:{it.line}`"
            elif it.todo_id:
                ref = f"`{it.todo_id}`"
            out.append(f"| {it.severity.upper()} | `{it.code}` | {ref} | {it.message} |")
        out.append("")

    def emit_section(title: str, rows_subset: list[QueueRow]) -> None:
        out.append(f"## {title}")
        out.append("")
        if not rows_subset:
            out.append("_(none)_")
            out.append("")
            return
        out.append("| Priority | Phase | ID | File:Line | Owner | TODO | Notes |")
        out.append("| --- | ---: | --- | --- | --- | --- | --- |")
        for r in rows_subset:
            notes: list[str] = []
            if r.stale:
                notes.append(f"stale({r.age_days}d>{r.stale_days}d)")
            if r.validation_profile and r.validation_profile != "(unset)":
                notes.append(f"profile:{r.validation_profile}")
            if r.target_repo and r.target_repo != "(unset)":
                notes.append(f"target:{r.target_repo}")
            if r.blocked_reasons:
                notes.append("blocked:" + ",".join(r.blocked_reasons))
            if r.agent_ready_missing:
                notes.append("agent-missing:" + ",".join(r.agent_ready_missing))
            todo = (r.text or "").replace("|", "\\|")
            out.append(
                "| {pri} | {phase} | `{tid}` | `{file}:{line}` | {owner} | {todo} | {notes} |".format(
                    pri=r.priority,
                    phase=r.phase if r.phase != 9 else "-",
                    tid=r.todo_id,
                    file=r.file,
                    line=r.line,
                    owner=(r.owner or "(unset)").replace("|", "\\|"),
                    todo=todo,
                    notes=("; ".join(notes) if notes else "").replace("|", "\\|"),
                )
            )
        out.append("")

    emit_section("Ready Queue (Auto-Eligible)", [r for r in rows if (not r.blocked_reasons) and r.auto_eligible])
    emit_section("Ready Queue (Human-Required)", [r for r in rows if (not r.blocked_reasons) and (not r.auto_eligible)])
    emit_section("Blocked", [r for r in rows if r.blocked_reasons])

    return "\n".join(out).rstrip() + "\n"


def render_json(rows: list[QueueRow], issues: list[QueueIssue], summary: dict, *, generated_at: str) -> str:
    payload = {
        "schema_version": AGENT_QUEUE_SCHEMA_VERSION,
        "schema_id": AGENT_QUEUE_SCHEMA_ID,
        "schema_path": AGENT_QUEUE_SCHEMA_PATH,
        "generated_at": generated_at,
        "summary": summary,
        "issues": [
            {
                "severity": i.severity,
                "code": i.code,
                "message": i.message,
                "todo_id": i.todo_id,
                "file": i.file,
                "line": i.line,
            }
            for i in issues
        ],
        "items": [
            {
                "todo_id": r.todo_id,
                "text": r.text,
                "file": r.file,
                "line": r.line,
                "phase": r.phase,
                "priority": r.priority,
                "priority_rank": r.priority_rank,
                "owner": r.owner,
                "target_repo": r.target_repo,
                "validation_profile": r.validation_profile,
                "automation_level": r.automation_level,
                "safe_autofix": r.safe_autofix,
                "human_checkpoint": r.human_checkpoint,
                "depends_on": r.depends_on,
                "blocked_by": r.blocked_by,
                "blocked_reasons": r.blocked_reasons,
                "stale_days": r.stale_days,
                "age_days": r.age_days,
                "stale": r.stale,
                "auto_eligible": r.auto_eligible,
                "agent_ready": r.agent_ready,
                "agent_ready_missing": r.agent_ready_missing,
                "agent": {
                    "task_id": r.todo_id,
                    "phase": r.phase,
                    "priority": r.priority,
                    "files": r.files,
                    "files_raw": r.files_raw,
                    "file_refs": r.file_refs,
                    "verification": r.verification,
                    "qa_live_automation": r.qa_live_automation,
                    "acceptance": r.acceptance,
                    "drift_guard": r.drift_guard,
                    "downstream_rollout": r.downstream_rollout,
                    "dependencies": r.depends_on,
                    "blocked_by": r.blocked_by,
                    "stale_threshold_days": r.stale_days,
                    "validation_profile": r.validation_profile,
                    "deliverables": r.deliverables,
                },
            }
            for r in rows
        ],
    }
    return json.dumps(payload, indent=2, sort_keys=True) + "\n"


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def compute_exit(issues: list[QueueIssue], *, fail_on: Literal["none", "warn", "error"]) -> int:
    if fail_on == "none":
        return 0
    if fail_on == "error":
        return 1 if any(i.severity == "error" for i in issues) else 0
    return 1 if any(i.severity in {"warn", "error"} for i in issues) else 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo-root", default=".")
    ap.add_argument("--todo-root", default="docs/todo")
    ap.add_argument("--report", default="-")
    ap.add_argument("--json-report", default="")
    ap.add_argument("--agent-json", default="", help="Write schema-backed TODO agent queue JSON.")
    ap.add_argument("--min-severity", choices=["info", "warn", "error"], default="info")
    ap.add_argument("--fail-on", choices=["none", "warn", "error"], default="error")
    args = ap.parse_args()

    repo_root = Path(args.repo_root).resolve()
    todo_root = Path(args.todo_root)
    if not todo_root.is_absolute():
        todo_root = (repo_root / todo_root).resolve()

    if not todo_root.exists() or not todo_root.is_dir():
        print(f"ERROR: todo root not found: {todo_root}")
        return 2

    rows, issues_all, summary = build_queue(repo_root, todo_root)
    issues = filter_issues(issues_all, args.min_severity)

    generated_at = _iso_utc_now()
    md = render_markdown(rows, issues, summary, generated_at=generated_at)
    js = render_json(rows, issues, summary, generated_at=generated_at)

    if args.report == "-":
        print(md, end="")
    else:
        out_md = Path(args.report)
        if not out_md.is_absolute():
            out_md = (repo_root / out_md).resolve()
        write_text(out_md, md)
        print(f"Wrote ready-queue report: {out_md}")

    json_targets = [x for x in [args.json_report, args.agent_json] if str(x or "").strip()]
    for target in json_targets:
        out_js = Path(target)
        if not out_js.is_absolute():
            out_js = (repo_root / out_js).resolve()
        write_text(out_js, js)
        print(f"Wrote ready-queue JSON: {out_js}")

    print(
        "TODO ready-queue summary: "
        f"open={summary['open_total']} "
        f"ready_auto={summary['ready_auto']} "
        f"ready_human={summary['ready_human']} "
        f"blocked={summary['blocked_total']} "
        f"agent_ready={summary['agent_ready_total']} "
        f"issues_error={summary['issues']['error']} "
        f"issues_warn={summary['issues']['warn']} "
        f"issues_info={summary['issues']['info']}"
    )

    return compute_exit(issues, fail_on=args.fail_on)


if __name__ == "__main__":
    raise SystemExit(main())

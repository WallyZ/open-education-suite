"""Markdown report rendering for the TODO audit tool."""

from __future__ import annotations

from scripts.todo_audit.todo_parse import TodoItem
from scripts.todo_audit.util import _truncate


def render_report_markdown(
    *,
    todo_path,
    repo_root,
    report_data: dict,
) -> str:
    include_unknown = report_data["include_unknown"]
    min_confidence = report_data["min_confidence"]
    generated_at = report_data["generated_at"]
    assessed: list[dict] = report_data["assessed"]

    # Report-only status counts (keeps legacy assessment status for plan/apply semantics).
    report_counts = {"done_likely": 0, "not_done_likely": 0, "partial": 0, "unclear": 0}
    for row in assessed:
        a = row.get("assessment") or {}
        rs = a.get("report_status") or a.get("status")
        if rs == "partial_likely":
            rs = "partial"
        if rs == "unknown":
            rs = "unclear"
        if rs not in report_counts:
            rs = "unclear"
        report_counts[rs] += 1

    out: list[str] = []
    out.append("# TODO Audit Report")
    out.append("")
    out.append(f"- generated_at: `{generated_at}`")
    out.append(f"- todo_path: `{todo_path.as_posix()}`")
    out.append(f"- repo_root: `{repo_root.as_posix()}`")
    out.append(f"- min_confidence_for_mark_complete: `{min_confidence}`")
    out.append("")

    out.append("## Summary")
    out.append("")
    out.append(f"- done_likely: **{report_counts.get('done_likely', 0)}**")
    out.append(f"- not_done_likely: **{report_counts.get('not_done_likely', 0)}**")
    out.append(f"- partial: **{report_counts.get('partial', 0)}**")
    out.append(f"- unclear: **{report_counts.get('unclear', 0)}**")
    out.append(
        f"- recommend_adds_suppressed: **{int(report_data.get('recommend_adds_suppressed') or 0)}**"
    )
    out.append(
        f"- recommend_adds_emitted: **{int(report_data.get('recommend_adds_emitted') or 0)}**"
    )
    out.append("")

    # Group by section in order of appearance.
    section_order: list[str] = []
    grouped: dict[str, list[dict]] = {}
    for row in assessed:
        section = row["item"].section_display
        if section not in grouped:
            grouped[section] = []
            section_order.append(section)
        grouped[section].append(row)

    for section in section_order:
        rows = grouped[section]

        # Filter unclear items unless requested; always include rows with recommendations.
        filtered: list[dict] = []
        for r in rows:
            a0 = r.get("assessment") or {}
            status = a0.get("report_status") or a0.get("status")
            if status == "partial_likely":
                status = "partial"
            if status == "unknown":
                status = "unclear"
            if include_unknown:
                filtered.append(r)
                continue
            if r["recs"]:
                filtered.append(r)
                continue
            if status != "unclear":
                filtered.append(r)

        if not filtered:
            continue

        out.append(f"## {section}")
        out.append("")
        out.append(
            "| Line | Box | TODO | Status | Conf | Evidence | Recommended | Hint |\n"
            "|---:|:--:|---|---|---:|---|---|---|"
        )

        for r in filtered:
            item: TodoItem = r["item"]
            a = r["assessment"]

            # "checkbox drift":
            # - checked items are never auto-downgraded; instead we emit drift tags in evidence.
            # - unchecked-but-done is still a drift indicator.
            drift_tags = [e for e in (a.get("evidence") or []) if (e or "").startswith("drift:")]
            drift = bool(drift_tags) or ((not item.checked) and a["status"] == "done_likely")
            status_display_raw = a.get("report_status") or a.get("status")
            if status_display_raw == "partial_likely":
                status_display_raw = "partial"
            if status_display_raw == "unknown":
                status_display_raw = "unclear"
            status_display = status_display_raw + (" (drift)" if drift else "")

            # Evidence clarity: show at most one "hit" and one "miss".
            # This keeps the table compact while still showing why an item is partial/not_done.
            hits = []
            misses = []
            for e in a.get("evidence") or []:
                e_l = (e or "").lower()
                if e_l.startswith(
                    (
                        "missing:",
                        "missing_glob:",
                        "missing_symbol:",
                        "missing_field:",
                        "missing_key:",
                    )
                ) or (" not found" in e_l):
                    misses.append(e)
                else:
                    hits.append(e)
            ev_parts = []
            if hits:
                ev_parts.append("hit:" + hits[0])
            if misses:
                ev_parts.append("miss:" + misses[0])
            ev_s = _truncate(", ".join(ev_parts), 80) if ev_parts else ""

            recs = r["recs"]
            if recs:
                rec_s = ", ".join(
                    [
                        rr["action"] + (f"->{rr['to_section']}" if rr.get("to_section") else "")
                        for rr in recs
                    ]
                )
            else:
                rec_s = ""

            hints = r.get("hints") or []
            hint_s = _truncate(", ".join([h for h in hints if (h or "").strip()]), 60) if hints else ""

            out.append(
                "| {line} | {box} | {todo} | {status} | {conf} | {ev} | {rec} | {hint} |".format(
                    line=item.line_no,
                    box="x" if item.checked else " ",
                    todo=_truncate(item.text.replace("|", "\\|"), 80),
                    status=status_display,
                    conf=a["confidence"],
                    ev=ev_s.replace("|", "\\|"),
                    rec=rec_s.replace("|", "\\|"),
                    hint=hint_s.replace("|", "\\|"),
                )
            )

        out.append("")

    add_suggestions = report_data.get("add_suggestions") or []
    if report_data.get("suggest_additions") and add_suggestions:
        out.append("## Suggested additions (explicit opt-in)")
        out.append("")
        out.append(
            "Generated only when `--suggest-additions` is set. These are *not* applied unless you opt into `add` actions."
        )
        out.append("")
        for s in add_suggestions:
            rel = (s.get("path") or "").replace("\\", "/")
            kw = s.get("to_section") or ""
            if rel:
                out.append(f"- `{rel}` -> {kw}")
        out.append("")

    return "\n".join(out) + "\n"


def render_how_to_tag_section() -> str:
    return (
        "\n".join(
            [
                "## How to tag TODO items for deterministic audits",
                "",
                "Add one (or both) of these HTML comments on the same line as the checkbox (use either `ms:*` or `yta:*` consistently):",
                "",
                "- Stable ID:",
                "  - `<!-- ms:id <stable_id> -->` or `<!-- yta:id <stable_id> -->`",
                "",
                "- Evidence (preferred; can also carry id=):",
                "  - `<!-- ms:evidence id=<stable_id> path=... symbols=... strings=... fields=... keys=... -->` or `<!-- yta:evidence ... -->`",
                "",
                "Notes:",
                "- `path=` / `symbols=` / `strings=` / `fields=` / `keys=` accept comma/semicolon-separated lists.",
                "- If `*:evidence` exists, the auditor will prefer it over heuristic parsing.",
                "- When applying a plan, this tool will preserve existing IDs and insert one if missing.",
                "",
            ]
        )
        + "\n"
    )

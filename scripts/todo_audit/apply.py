"""Apply-mode edits for the TODO audit tool.

This contains the code that mutates a TODO markdown file when `--apply` is used.
"""

from __future__ import annotations

import json
from pathlib import Path

from scripts.todo_audit.evidence import CHECKBOX_RE, _ensure_line_has_yta_id, _todo_id_from_checkbox_line
from scripts.todo_audit.todo_parse import HEADING_RE
from scripts.todo_audit.util import _iso_utc_now


def _find_item_line_index(lines: list[str], target: dict) -> int | None:
    """Find a line index (0-based) for an item target.

    Strategy:
      1) Prefer stable id match if present.
      2) Use line number if it matches expected item text.
      3) Fallback to first checkbox line with matching text.
    """

    if not target:
        return None

    target_id = (target.get("id") or "").strip()
    if target_id:
        for i, line in enumerate(lines):
            if not CHECKBOX_RE.match(line):
                continue
            line_id = _todo_id_from_checkbox_line(line)
            if line_id and line_id == target_id:
                return i

    target_line = int(target.get("line", 0) or 0)
    target_text = (target.get("text") or "").strip()

    if 1 <= target_line <= len(lines):
        i = target_line - 1
        m = CHECKBOX_RE.match(lines[i])
        if m and m.group("text").rstrip() == target_text:
            return i

    if not target_text:
        return None

    for i, line in enumerate(lines):
        m = CHECKBOX_RE.match(line)
        if not m:
            continue
        if m.group("text").rstrip() == target_text:
            return i

    return None


def _locate_section_insertion_index(lines: list[str], section_keyword: str) -> int:
    """Find an insertion index (0-based) for a given section keyword.

    Looks for the first heading containing the keyword (case-insensitive). Inserts near the
    end of that section (before the next heading of same/higher level). If not found,
    returns EOF.
    """

    kw = section_keyword.lower().strip()
    if not kw:
        return len(lines)

    for i, line in enumerate(lines):
        m = HEADING_RE.match(line)
        if not m:
            continue
        title = m.group("title").strip()
        if kw not in title.lower():
            continue

        level = len(m.group("hashes"))
        j = i + 1
        while j < len(lines):
            hm = HEADING_RE.match(lines[j])
            if hm and len(hm.group("hashes")) <= level:
                break
            j += 1
        return j

    return len(lines)


def _set_checkbox_state(line: str, checked: bool) -> str:
    m = CHECKBOX_RE.match(line)
    if not m:
        return line
    indent = m.group("indent")
    text = m.group("text")
    mark = "x" if checked else " "
    return f"{indent}- [{mark}] {text}"


def _unique_backup_path(todo_path: Path) -> Path:
    base = Path(str(todo_path) + ".bak")
    if not base.exists():
        return base
    for i in range(2, 100):
        candidate = Path(str(todo_path) + f".bak{i}")
        if not candidate.exists():
            return candidate
    ts = _iso_utc_now().replace(":", "").replace("-", "")
    return Path(str(todo_path) + f".bak_{ts}")


def apply_plan_to_todo(
    *,
    todo_path: Path,
    plan: dict,
    interactive: bool,
    yes: bool,
    dry_run: bool,
) -> int:
    orig = todo_path.read_text(encoding="utf-8", errors="replace")
    newline = "\r\n" if "\r\n" in orig else "\n"
    lines = orig.splitlines()

    plan_items = plan.get("items") or []
    changes_applied = 0
    skipped = 0

    def confirm(action: dict) -> bool:
        if yes:
            return True
        if not interactive:
            return False

        print("\n---")
        print(f"Action: {action.get('action')}")
        tgt = action.get("target")
        if tgt:
            print(f"Target line: {tgt.get('line')}  id: {tgt.get('id')}")
            print(f"Text: {tgt.get('text')}")
        if action.get("to_section"):
            print(f"To section: {action.get('to_section')}")
        if action.get("proposed_text"):
            print("Proposed text:")
            print(action.get("proposed_text"))
        if action.get("reason"):
            print(f"Reason: {action.get('reason')}")
        ev = action.get("evidence") or []
        if ev:
            print("Evidence:")
            for e in ev[:8]:
                print(f"  - {e}")
        ans = input("Apply this change? [y/N]: ").strip().lower()
        return ans in {"y", "yes"}

    for action in plan_items:
        a = action.get("action")
        if a not in {"check", "uncheck", "add", "move", "note", "annotate"}:
            continue
        if a in {"note", "annotate"}:
            continue

        if not confirm(action):
            skipped += 1
            continue

        if a in {"check", "uncheck"}:
            idx = _find_item_line_index(lines, action.get("target") or {})
            if idx is None:
                skipped += 1
                continue
            new_line = _set_checkbox_state(lines[idx], checked=(a == "check"))
            tid = (
                ((action.get("target") or {}).get("id") or "").strip()
                or _todo_id_from_checkbox_line(lines[idx])
            )
            if tid:
                new_line = _ensure_line_has_yta_id(new_line, tid)
            if new_line != lines[idx]:
                lines[idx] = new_line
                changes_applied += 1
            continue

        if a == "move":
            idx = _find_item_line_index(lines, action.get("target") or {})
            to_kw = action.get("to_section") or ""
            if idx is None or not to_kw:
                skipped += 1
                continue
            line_to_move = lines[idx]
            tid = (
                ((action.get("target") or {}).get("id") or "").strip()
                or _todo_id_from_checkbox_line(line_to_move)
            )
            if tid:
                line_to_move = _ensure_line_has_yta_id(line_to_move, tid)
            del lines[idx]
            insert_at = _locate_section_insertion_index(lines, to_kw)
            lines.insert(insert_at, line_to_move)
            changes_applied += 1
            continue

        if a == "add":
            to_kw = action.get("to_section") or ""
            proposed = (action.get("proposed_text") or "").rstrip("\r\n")
            if not proposed:
                skipped += 1
                continue
            tid = (
                ((action.get("target") or {}).get("id") or "").strip()
                or _todo_id_from_checkbox_line(proposed)
            )
            if tid:
                proposed = _ensure_line_has_yta_id(proposed, tid)
            insert_at = _locate_section_insertion_index(lines, to_kw) if to_kw else len(lines)
            if insert_at == len(lines) and (lines and lines[-1].strip() != ""):
                lines.append("")
                insert_at = len(lines)
            lines.insert(insert_at, proposed)
            changes_applied += 1
            continue

    if dry_run:
        print("\n[dry-run] No changes written.")
        print(f"Would apply: {changes_applied} changes; skipped: {skipped}.")
        return changes_applied

    if changes_applied == 0:
        print(f"No changes applied. Skipped: {skipped}.")
        return 0

    backup_path = _unique_backup_path(todo_path)
    backup_path.write_text(orig, encoding="utf-8")
    todo_path.write_text(newline.join(lines) + newline, encoding="utf-8")

    print(f"Wrote updated TODO: {todo_path}")
    print(f"Backup saved: {backup_path}")
    print(f"Changes applied: {changes_applied}; skipped: {skipped}.")
    return changes_applied


def write_plan_json(plan: dict, plan_path: Path) -> None:
    plan_path.parent.mkdir(parents=True, exist_ok=True)
    plan_path.write_text(json.dumps(plan, indent=2, sort_keys=True) + "\n", encoding="utf-8")

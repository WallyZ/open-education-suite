#!/usr/bin/env python3
"""unreal_log_ingest_adapter.py

Normalize Unreal Editor/UAT/UBT logs into the unified repo-kit schema.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import json
import re
import sys
from pathlib import Path
from typing import Any

DEFAULT_CONTRACT = {
    "schema_version": 1,
    "sources": ["ue_editor", "uat", "ubt"],
    "required_output_fields": [
        "ts",
        "level",
        "component",
        "event",
        "msg",
        "run_id",
        "trace_id",
        "source",
        "tool",
    ],
    "severity_map": {
        "VeryVerbose": "TRACE",
        "Verbose": "DEBUG",
        "Display": "INFO",
        "Log": "INFO",
        "Warning": "WARN",
        "Error": "ERROR",
        "Fatal": "FATAL",
        "INFO": "INFO",
        "WARN": "WARN",
        "ERROR": "ERROR",
        "FATAL": "FATAL",
    },
    "source_defaults": {
        "ue_editor": {"event_prefix": "ue.editor", "component": "ue_editor"},
        "uat": {"event_prefix": "ue.uat", "component": "uat"},
        "ubt": {"event_prefix": "ue.ubt", "component": "ubt"},
    },
}

UE_PATTERN = re.compile(
    r"(?P<category>Log[\w]+):\s*(?P<severity>VeryVerbose|Verbose|Display|Log|Warning|Error|Fatal)\s*:\s*(?P<message>.*)"
)
GENERIC_PATTERN = re.compile(
    r"(?P<severity>VeryVerbose|Verbose|Display|Log|Warning|Error|Fatal|INFO|WARN|ERROR|FATAL)\s*[:\-]\s*(?P<message>.*)",
    re.IGNORECASE,
)


def _utc_now() -> str:
    return _dt.datetime.now(tz=_dt.timezone.utc).isoformat()


def _load_contract(path: Path | None) -> dict[str, Any]:
    if path is None:
        return dict(DEFAULT_CONTRACT)
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("contract payload must be an object")
    return payload


def _to_unified_level(raw_level: str, contract: dict[str, Any]) -> str:
    mapping = contract.get("severity_map")
    if not isinstance(mapping, dict):
        mapping = DEFAULT_CONTRACT["severity_map"]
    resolved = mapping.get(raw_level) or mapping.get(raw_level.upper()) or mapping.get(raw_level.title())
    if not isinstance(resolved, str):
        return "INFO"
    return resolved.upper()


def normalize_unreal_line(
    *,
    line: str,
    source: str,
    run_id: str,
    trace_id: str,
    contract: dict[str, Any],
) -> dict[str, Any]:
    source_defaults = contract.get("source_defaults")
    if not isinstance(source_defaults, dict):
        source_defaults = DEFAULT_CONTRACT["source_defaults"]
    source_cfg = source_defaults.get(source, {})
    if not isinstance(source_cfg, dict):
        source_cfg = {}

    event_prefix = str(source_cfg.get("event_prefix", source))
    default_component = str(source_cfg.get("component", source))

    category = default_component
    severity = "INFO"
    message = line.rstrip("\n")
    match = UE_PATTERN.search(message)
    if match:
        category = match.group("category")
        severity = match.group("severity")
        message = match.group("message").strip()
    else:
        generic = GENERIC_PATTERN.search(message)
        if generic:
            severity = generic.group("severity")
            message = generic.group("message").strip()

    level = _to_unified_level(severity, contract)
    event_suffix = "line"
    if level in {"WARN", "ERROR", "FATAL"}:
        event_suffix = "issue"

    return {
        "ts": _utc_now(),
        "level": level,
        "component": category,
        "event": f"{event_prefix}.{event_suffix}",
        "msg": message,
        "run_id": run_id,
        "trace_id": trace_id,
        "source": source,
        "tool": "unreal",
    }


def _iter_lines(path: str) -> list[str]:
    if path == "-":
        return [ln.rstrip("\n") for ln in sys.stdin]
    p = Path(path)
    return p.read_text(encoding="utf-8", errors="replace").splitlines()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, choices=["ue_editor", "uat", "ubt"])
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--trace-id", required=True)
    parser.add_argument("--input", default="-")
    parser.add_argument("--output", default="-")
    parser.add_argument("--contract", default="")
    args = parser.parse_args()

    contract_path = Path(args.contract) if args.contract else None
    contract = _load_contract(contract_path)
    lines = _iter_lines(args.input)

    out_stream = sys.stdout
    out_file = None
    if args.output != "-":
        out_file = Path(args.output)
        out_file.parent.mkdir(parents=True, exist_ok=True)
        out_stream = out_file.open("w", encoding="utf-8")

    try:
        for line in lines:
            if not line.strip():
                continue
            payload = normalize_unreal_line(
                line=line,
                source=args.source,
                run_id=args.run_id,
                trace_id=args.trace_id,
                contract=contract,
            )
            out_stream.write(json.dumps(payload, ensure_ascii=True) + "\n")
    finally:
        if out_file is not None:
            out_stream.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

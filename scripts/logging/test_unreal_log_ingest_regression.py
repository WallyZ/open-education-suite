#!/usr/bin/env python3
"""Fixture-driven regression tests for unreal_log_ingest_adapter.py."""

from __future__ import annotations

import json
import sys
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[1]
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from unreal_log_ingest_adapter import normalize_unreal_line  # noqa: E402


def _read_json(path: Path) -> dict:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise RuntimeError(f"JSON payload must be an object: {path}")
    return payload


def run_regression() -> None:
    fixtures_path = SCRIPT_DIR / "fixtures" / "unreal_ingest_cases.json"
    contract_path = REPO_ROOT / "docs" / "logging" / "unreal_ingestion_contract.json"

    fixtures = _read_json(fixtures_path)
    contract = _read_json(contract_path)

    cases = fixtures.get("cases")
    if not isinstance(cases, list) or not cases:
        raise RuntimeError("Fixture file must contain non-empty 'cases' list")

    required_fields = contract.get("required_output_fields")
    if not isinstance(required_fields, list) or not required_fields:
        raise RuntimeError("Contract must contain required_output_fields list")

    run_id = "run-regression-fixture"
    trace_id = "trace-regression-fixture"

    for case in cases:
        if not isinstance(case, dict):
            raise RuntimeError("Each fixture case must be an object")

        case_id = str(case.get("id", "unknown"))
        source = str(case.get("source", ""))
        line = str(case.get("line", ""))

        payload = normalize_unreal_line(
            line=line,
            source=source,
            run_id=run_id,
            trace_id=trace_id,
            contract=contract,
        )

        if not isinstance(payload, dict):
            raise RuntimeError(f"[{case_id}] normalized payload must be an object")

        for field in required_fields:
            if field not in payload:
                raise RuntimeError(f"[{case_id}] missing required output field: {field}")

        for key in ("expected_level", "expected_component", "expected_event", "expected_message"):
            if key not in case:
                raise RuntimeError(f"[{case_id}] fixture missing required expectation key: {key}")

        if payload["level"] != case["expected_level"]:
            raise RuntimeError(
                f"[{case_id}] level mismatch: expected {case['expected_level']!r} got {payload['level']!r}"
            )
        if payload["component"] != case["expected_component"]:
            raise RuntimeError(
                f"[{case_id}] component mismatch: expected {case['expected_component']!r} got {payload['component']!r}"
            )
        if payload["event"] != case["expected_event"]:
            raise RuntimeError(
                f"[{case_id}] event mismatch: expected {case['expected_event']!r} got {payload['event']!r}"
            )
        if payload["msg"] != case["expected_message"]:
            raise RuntimeError(
                f"[{case_id}] message mismatch: expected {case['expected_message']!r} got {payload['msg']!r}"
            )
        if payload["run_id"] != run_id:
            raise RuntimeError(f"[{case_id}] run_id propagation mismatch")
        if payload["trace_id"] != trace_id:
            raise RuntimeError(f"[{case_id}] trace_id propagation mismatch")
        if payload["source"] != source:
            raise RuntimeError(f"[{case_id}] source propagation mismatch")

    print(f"Unreal ingestion regression passed ({len(cases)} fixture cases).")


if __name__ == "__main__":
    run_regression()

#!/usr/bin/env python3
"""Smoke checks for repokit_logging_adapter.py."""

from __future__ import annotations

import io
import json
import sys
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from repokit_logging_adapter import build_logger  # noqa: E402


def _load_lines(buf: io.StringIO) -> list[dict[str, object]]:
    out: list[dict[str, object]] = []
    for line in buf.getvalue().splitlines():
        text = line.strip()
        if not text:
            continue
        out.append(json.loads(text))
    return out


def run_smoke() -> None:
    stream = io.StringIO()
    seeded_secret = "SEED_SECRET_PY_123"
    env = {
        "LOG_LEVEL": "INFO",
        "LOG_LEVEL_ASSET_PIPELINE": "DEBUG",
        "APIKEY": seeded_secret,
    }

    asset_logger = build_logger(
        "repokit.logging.smoke.python.asset",
        "asset_pipeline",
        run_id="run-smoke-python",
        trace_id="trace-smoke-python",
        stream=stream,
        env=env,
        secret_values=[seeded_secret],
    )
    asset_logger.debug("asset import token=%s", seeded_secret, extra={"event": "asset.import.debug"})

    gameplay_logger = build_logger(
        "repokit.logging.smoke.python.gameplay",
        "gameplay",
        run_id="run-smoke-python",
        trace_id="trace-smoke-python",
        stream=stream,
        env=env,
        secret_values=[seeded_secret],
    )
    gameplay_logger.debug("this debug line should be suppressed", extra={"event": "gameplay.debug"})
    gameplay_logger.info("gameplay info", extra={"event": "gameplay.info"})

    rows = _load_lines(stream)
    if len(rows) != 2:
        raise RuntimeError(f"Expected exactly 2 emitted rows, got {len(rows)}")

    debug_row = next((row for row in rows if row.get("event") == "asset.import.debug"), None)
    if debug_row is None:
        raise RuntimeError("Missing asset_import DEBUG line with component override")
    if debug_row.get("level") != "DEBUG":
        raise RuntimeError(f"Expected DEBUG level for component override, got {debug_row.get('level')}")

    msg = str(debug_row.get("msg", ""))
    if seeded_secret in msg:
        raise RuntimeError("Seeded secret leaked in python log output")
    if "[REDACTED]" not in msg:
        raise RuntimeError("Expected redacted marker in python log output")
    if debug_row.get("run_id") != "run-smoke-python":
        raise RuntimeError("run_id was not auto-propagated")
    if debug_row.get("trace_id") != "trace-smoke-python":
        raise RuntimeError("trace_id was not auto-propagated")

    print("Python logging adapter smoke passed.")


if __name__ == "__main__":
    run_smoke()

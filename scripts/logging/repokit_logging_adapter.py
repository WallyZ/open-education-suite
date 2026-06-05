#!/usr/bin/env python3
"""repokit_logging_adapter.py

Shared Python logging adapter for repo-kit/downstream usage.
Provides:
- unified level handling (`TRACE`..`FATAL`)
- component-aware level overrides (`LOG_LEVEL_<COMPONENT>`)
- automatic `run_id`/`trace_id` injection
- secret redaction in message payloads
"""

from __future__ import annotations

import datetime as _dt
import json
import logging
import os
import re
import sys
import uuid
from typing import Iterable, Mapping

TRACE_LEVEL_NUM = 5
logging.addLevelName(TRACE_LEVEL_NUM, "TRACE")

UNIFIED_TO_PYTHON = {
    "TRACE": TRACE_LEVEL_NUM,
    "DEBUG": logging.DEBUG,
    "INFO": logging.INFO,
    "WARN": logging.WARNING,
    "ERROR": logging.ERROR,
    "FATAL": logging.CRITICAL,
}

SECRET_KEYS_DEFAULT = (
    "token",
    "secret",
    "password",
    "apikey",
    "cookie",
    "session",
    "credential",
)

_REDACTED = "[REDACTED]"
_KEY_PATTERN = re.compile(
    r"(?P<key>token|secret|password|apikey|cookie|session|credential)\s*[:=]\s*(?P<value>[^\s,;]+)",
    re.IGNORECASE,
)


def _normalized_component_key(component: str) -> str:
    normalized = re.sub(r"[^A-Za-z0-9]+", "_", component.strip()).strip("_")
    if not normalized:
        return "DEFAULT"
    return normalized.upper()


def _sanitize_level_name(level_name: str | None) -> str:
    if not level_name:
        return "INFO"
    normalized = level_name.strip().upper()
    if normalized not in UNIFIED_TO_PYTHON:
        return "INFO"
    return normalized


def resolve_effective_level(component: str, env: Mapping[str, str] | None = None) -> str:
    source = env if env is not None else os.environ
    component_key = _normalized_component_key(component)
    component_level = source.get(f"LOG_LEVEL_{component_key}")
    if component_level:
        return _sanitize_level_name(component_level)
    return _sanitize_level_name(source.get("LOG_LEVEL"))


def _redact_text(
    value: str,
    *,
    secret_values: Iterable[str],
    secret_keys: Iterable[str],
) -> str:
    out = value

    for secret in secret_values:
        if secret:
            out = out.replace(secret, _REDACTED)

    key_set = {k.strip().lower() for k in secret_keys if k and k.strip()}
    if key_set:
        pattern = re.compile(
            r"(?P<key>" + "|".join(sorted(re.escape(k) for k in key_set)) + r")\s*[:=]\s*(?P<value>[^\s,;]+)",
            re.IGNORECASE,
        )
        out = pattern.sub(lambda m: f"{m.group('key')}={_REDACTED}", out)
    else:
        out = _KEY_PATTERN.sub(lambda m: f"{m.group('key')}={_REDACTED}", out)

    return out


def _redact_obj(value: object, *, secret_values: Iterable[str], secret_keys: Iterable[str]) -> object:
    if isinstance(value, str):
        return _redact_text(value, secret_values=secret_values, secret_keys=secret_keys)
    if isinstance(value, dict):
        redacted: dict[object, object] = {}
        lowered = {k.lower() for k in secret_keys}
        for key, item in value.items():
            key_text = str(key).lower()
            if key_text in lowered:
                redacted[key] = _REDACTED
            else:
                redacted[key] = _redact_obj(item, secret_values=secret_values, secret_keys=secret_keys)
        return redacted
    if isinstance(value, (list, tuple)):
        redacted_items = [_redact_obj(x, secret_values=secret_values, secret_keys=secret_keys) for x in value]
        return type(value)(redacted_items)
    return value


class RedactingFilter(logging.Filter):
    def __init__(
        self,
        *,
        secret_values: Iterable[str] | None = None,
        secret_keys: Iterable[str] | None = None,
    ) -> None:
        super().__init__()
        self.secret_values = tuple(secret_values or ())
        self.secret_keys = tuple(secret_keys or SECRET_KEYS_DEFAULT)

    def filter(self, record: logging.LogRecord) -> bool:
        rendered = record.getMessage()
        record.msg = _redact_text(
            rendered,
            secret_values=self.secret_values,
            secret_keys=self.secret_keys,
        )
        # Message has already been rendered; avoid second formatting pass mismatch.
        record.args = ()
        return True


class StructuredFormatter(logging.Formatter):
    _RESERVED_KEYS = {
        "name",
        "msg",
        "args",
        "levelname",
        "levelno",
        "pathname",
        "filename",
        "module",
        "exc_info",
        "exc_text",
        "stack_info",
        "lineno",
        "funcName",
        "created",
        "msecs",
        "relativeCreated",
        "thread",
        "threadName",
        "processName",
        "process",
        "message",
    }

    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, object] = {
            "ts": _dt.datetime.now(tz=_dt.timezone.utc).isoformat(),
            "level": _sanitize_level_name(record.levelname),
            "component": getattr(record, "component", "app"),
            "event": getattr(record, "event", "app.log"),
            "msg": record.getMessage(),
            "run_id": getattr(record, "run_id", ""),
            "trace_id": getattr(record, "trace_id", ""),
            "source": getattr(record, "source", "app"),
            "tool": getattr(record, "tool", "python"),
            "logger": record.name,
        }

        for key, value in record.__dict__.items():
            if key in self._RESERVED_KEYS or key in payload:
                continue
            if isinstance(value, (str, int, float, bool)) or value is None:
                payload[key] = value

        return json.dumps(payload, ensure_ascii=True)


class RepoKitLoggerAdapter(logging.LoggerAdapter):
    def process(self, msg: object, kwargs: dict[str, object]) -> tuple[object, dict[str, object]]:
        extra = dict(self.extra)
        incoming_extra = kwargs.pop("extra", None)
        if isinstance(incoming_extra, dict):
            extra.update(incoming_extra)
        kwargs["extra"] = extra
        return msg, kwargs


def _ensure_logger_handler(
    *,
    logger: logging.Logger,
    stream: object,
    level_name: str,
    secret_values: Iterable[str],
    secret_keys: Iterable[str],
) -> None:
    # Rebuild only repo-kit-managed handlers to keep idempotent setup.
    logger.handlers = [h for h in logger.handlers if not getattr(h, "_repokit_handler", False)]

    handler = logging.StreamHandler(stream)
    handler.setLevel(UNIFIED_TO_PYTHON[level_name])
    handler.setFormatter(StructuredFormatter())
    handler.addFilter(
        RedactingFilter(secret_values=secret_values, secret_keys=secret_keys)
    )
    setattr(handler, "_repokit_handler", True)
    logger.addHandler(handler)


def build_logger(
    name: str,
    component: str,
    *,
    run_id: str | None = None,
    trace_id: str | None = None,
    source: str = "app",
    tool: str = "python",
    env: Mapping[str, str] | None = None,
    stream: object | None = None,
    secret_values: Iterable[str] | None = None,
    secret_keys: Iterable[str] | None = None,
    level: str | None = None,
) -> RepoKitLoggerAdapter:
    runtime_env = env if env is not None else os.environ
    chosen_level = _sanitize_level_name(level or resolve_effective_level(component, runtime_env))
    chosen_run_id = run_id or runtime_env.get("RUN_ID") or f"run-{uuid.uuid4().hex[:12]}"
    chosen_trace_id = trace_id or runtime_env.get("TRACE_ID") or f"trace-{uuid.uuid4().hex[:16]}"

    logger = logging.getLogger(name)
    logger.setLevel(UNIFIED_TO_PYTHON[chosen_level])
    logger.propagate = False

    configured_secret_values = list(secret_values or ())
    configured_secret_keys = list(secret_keys or SECRET_KEYS_DEFAULT)

    # Add known env secret values for automatic redaction if present.
    for key in runtime_env:
        if key.lower() in {k.lower() for k in configured_secret_keys}:
            maybe = runtime_env.get(key)
            if maybe:
                configured_secret_values.append(maybe)

    _ensure_logger_handler(
        logger=logger,
        stream=(stream if stream is not None else sys.stdout),
        level_name=chosen_level,
        secret_values=configured_secret_values,
        secret_keys=configured_secret_keys,
    )

    adapter_extra = {
        "run_id": chosen_run_id,
        "trace_id": chosen_trace_id,
        "component": component,
        "source": source,
        "tool": tool,
    }
    return RepoKitLoggerAdapter(logger, adapter_extra)


def log_trace(adapter: RepoKitLoggerAdapter, message: str, *args: object, **kwargs: object) -> None:
    adapter.log(TRACE_LEVEL_NUM, message, *args, **kwargs)

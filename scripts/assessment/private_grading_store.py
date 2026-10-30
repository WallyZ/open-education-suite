"""Transactional grading authority, encrypted for the current Windows account."""

from __future__ import annotations

import ctypes
import json
import os
import secrets
import sqlite3
import uuid
from contextlib import contextmanager
from ctypes import wintypes
from pathlib import Path


class _Blob(ctypes.Structure):
    _fields_ = [("size", wintypes.DWORD), ("data", ctypes.POINTER(ctypes.c_ubyte))]


def _crypt(payload: bytes, decrypt: bool = False) -> bytes:
    if os.name != "nt":
        raise ValueError("Private grading authority requires Windows user-scoped DPAPI")
    crypt = ctypes.WinDLL("crypt32", use_last_error=True)
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    source_buffer = ctypes.create_string_buffer(payload)
    entropy_bytes = b"OpenEducationSuite.PrivateGrading.v1"
    entropy_buffer = ctypes.create_string_buffer(entropy_bytes)
    source = _Blob(len(payload), ctypes.cast(source_buffer, ctypes.POINTER(ctypes.c_ubyte)))
    entropy = _Blob(len(entropy_bytes), ctypes.cast(entropy_buffer, ctypes.POINTER(ctypes.c_ubyte)))
    target = _Blob()
    function = crypt.CryptUnprotectData if decrypt else crypt.CryptProtectData
    function.argtypes = [ctypes.POINTER(_Blob), ctypes.c_void_p if decrypt else wintypes.LPCWSTR,
                         ctypes.POINTER(_Blob), ctypes.c_void_p, ctypes.c_void_p,
                         wintypes.DWORD, ctypes.POINTER(_Blob)]
    function.restype = wintypes.BOOL
    kernel.LocalFree.argtypes = [ctypes.c_void_p]
    kernel.LocalFree.restype = ctypes.c_void_p
    if not function(ctypes.byref(source), None if decrypt else "Open Education grading authority",
                    ctypes.byref(entropy), None, None, 1, ctypes.byref(target)):
        raise ValueError("Private grading protection failed for this Windows account")
    try:
        return ctypes.string_at(target.data, target.size)
    finally:
        kernel.LocalFree(target.data)


class PrivateGradingStore:
    """One encrypted snapshot committed atomically with its signing key and replay cache."""

    def __init__(self, suite: Path, path: Path, revision: str, rehearsal: bool):
        self.path = path.resolve()
        suite = suite.resolve()
        approved = (suite / ".repo-kit-local/grading", suite / ".codex-cache/tmp")
        if not any(self.path.is_relative_to(root) for root in approved):
            raise ValueError("Grading authority must use an approved ignored private root")
        self.revision = revision
        self.mode = "rehearsal" if rehearsal else "ordinary"
        self.path.parent.mkdir(parents=True, exist_ok=True)
        new = not self.path.exists()
        with self._connection() as connection:
            connection.execute("BEGIN IMMEDIATE")
            try:
                if new:
                    connection.execute("CREATE TABLE IF NOT EXISTS authority (id INTEGER PRIMARY KEY CHECK(id=1), payload BLOB NOT NULL)")
                row = connection.execute("SELECT payload FROM authority WHERE id=1").fetchone()
                if row is None:
                    if not new:
                        raise ValueError("Private authority is incomplete; refusing to replace it")
                    self._write(connection, {"format": 1, "mode": self.mode, "revision": revision,
                                             "authorityId": uuid.uuid4().hex, "secret": secrets.token_hex(32),
                                             "sessions": {}, "challenges": {}})
                else:
                    self._decode(row[0])
                connection.commit()
            except Exception:
                connection.rollback()
                raise

    @contextmanager
    def _connection(self):
        connection = sqlite3.connect(self.path, timeout=30, isolation_level=None)
        try:
            connection.execute("PRAGMA synchronous=FULL")
            connection.execute("PRAGMA temp_store=MEMORY")
            yield connection
        finally:
            connection.close()

    def _decode(self, payload: bytes) -> dict:
        value = json.loads(_crypt(payload, decrypt=True))
        if (not isinstance(value, dict) or value.get("format") != 1
                or value.get("mode") != self.mode or value.get("revision") != self.revision
                or not isinstance(value.get("sessions"), dict) or not isinstance(value.get("challenges"), dict)
                or not isinstance(value.get("secret"), str) or len(value["secret"]) != 64
                or not isinstance(value.get("authorityId"), str)):
            raise ValueError("Private authority mode, source revision or format requires review")
        bytes.fromhex(value["secret"])
        return value

    def _write(self, connection, value: dict) -> None:
        sealed = _crypt(json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False).encode())
        connection.execute("INSERT OR REPLACE INTO authority(id,payload) VALUES(1,?)", (sealed,))

    @contextmanager
    def transaction(self):
        with self._connection() as connection:
            connection.execute("BEGIN IMMEDIATE")
            try:
                row = connection.execute("SELECT payload FROM authority WHERE id=1").fetchone()
                if row is None:
                    raise ValueError("Private grading authority is missing")
                value = self._decode(row[0])
                yield value
                self._write(connection, value)
                connection.commit()
            except Exception:
                connection.rollback()
                raise

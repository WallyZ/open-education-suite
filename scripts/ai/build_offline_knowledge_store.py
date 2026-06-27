"""Build an offline AI knowledge-store package from registered content repos."""

from __future__ import annotations

import argparse
import json
import sqlite3
from pathlib import Path
from typing import Any

SCHEMA_VERSION = "open-education/offline-ai-knowledge-store/v1"
DEFAULT_MANIFEST_PATH = "ai-knowledge/manifest.json"
DEFAULT_PROVIDER = "ollama"
PROVIDER_IDS = {
    "ollama": "ollama-local",
    "lm-studio": "lm-studio-local",
}


def _load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict):
        raise ValueError(f"Expected JSON object: {path}")
    return data


def _load_jsonl(path: Path) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, 1):
            raw = line.strip()
            if not raw:
                continue
            data = json.loads(raw)
            if not isinstance(data, dict):
                raise ValueError(f"Expected JSON object at {path}:{line_number}")
            records.append(data)
    return records


def _write_json(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _write_jsonl(path: Path, records: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        for record in records:
            handle.write(json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n")


def _require(condition: bool, message: str, errors: list[str]) -> None:
    if not condition:
        errors.append(message)


def _is_relative_public_path(value: str) -> bool:
    return bool(value) and ":" not in value and not value.startswith(("/", "\\"))


def _validate_manifest(path: Path, manifest: dict[str, Any], errors: list[str]) -> None:
    label = str(path)
    _require(manifest.get("schemaVersion") == SCHEMA_VERSION, f"{label}: invalid schemaVersion", errors)
    _require(bool(manifest.get("storeId")), f"{label}: missing storeId", errors)
    _require(bool(manifest.get("ownerRepoId")), f"{label}: missing ownerRepoId", errors)
    _require(manifest.get("role") == "content-knowledge-seed", f"{label}: role must be content-knowledge-seed", errors)
    records_path = str(manifest.get("sourceRecordsPath") or "")
    _require(_is_relative_public_path(records_path), f"{label}: sourceRecordsPath must be relative", errors)

    profiles = manifest.get("runtimeProfiles") or []
    profile_ids = {str(profile.get("id")) for profile in profiles if isinstance(profile, dict)}
    for required in ("ollama-local", "lm-studio-local"):
        _require(required in profile_ids, f"{label}: missing runtime profile {required}", errors)
    for profile in profiles:
        if not isinstance(profile, dict):
            errors.append(f"{label}: runtimeProfiles entries must be objects")
            continue
        _require(profile.get("networkScope") == "localhost-only", f"{label}: runtime profile must be localhost-only", errors)
        _require(str(profile.get("apiBase") or "").startswith("http://127.0.0.1:"), f"{label}: runtime apiBase must be localhost", errors)

    privacy = manifest.get("privacyBoundary") or {}
    for key in (
        "containsLearnerPrivateData",
        "containsCredentials",
        "containsPrivateNotes",
        "containsEmbeddings",
        "containsCopiedSourceText",
    ):
        _require(privacy.get(key) is False, f"{label}: privacyBoundary.{key} must be false", errors)
    _require(privacy.get("allowsLocalPrivateOverlays") is True, f"{label}: local private overlays must be allowed", errors)

    writeback = manifest.get("writebackPolicy") or {}
    for key in (
        "seedRecordsAreReadOnly",
        "privateOverlaysStayLocal",
        "publicPromotionRequiresReview",
        "durableLearnerStateRequiresCheckedCode",
    ):
        _require(writeback.get(key) is True, f"{label}: writebackPolicy.{key} must be true", errors)


def _validate_record(path: Path, record: dict[str, Any], errors: list[str]) -> None:
    label = f"{path}:{record.get('recordId', '<missing>')}"
    for key in ("recordId", "kind", "title", "sourceRepo", "sourcePath", "summary"):
        _require(bool(record.get(key)), f"{label}: missing {key}", errors)
    _require(_is_relative_public_path(str(record.get("sourcePath") or "")), f"{label}: sourcePath must be relative", errors)
    _require(record.get("privacyClass") == "public-course-seed", f"{label}: privacyClass must be public-course-seed", errors)
    _require(record.get("writePolicy") == "read-only-seed", f"{label}: writePolicy must be read-only-seed", errors)
    _require(record.get("citationRequired") is True, f"{label}: citationRequired must be true", errors)
    _require(len(record.get("retrievalTerms") or []) >= 3, f"{label}: needs at least 3 retrievalTerms", errors)
    serialized = json.dumps(record, sort_keys=True)
    for token in ("api_key", "bearer ", "secret", "token=", "F:\\", "learnerId", "privateNote"):
        _require(token.lower() not in serialized.lower(), f"{label}: forbidden private token {token}", errors)


def _discover_content_stores(repo_root: Path) -> tuple[list[dict[str, Any]], list[str]]:
    errors: list[str] = []
    registry_path = repo_root / "content-sources.json"
    registry = _load_json(registry_path)
    stores: list[dict[str, Any]] = []

    for source in registry.get("contentSources") or []:
        source_id = str(source.get("id") or "")
        local_path = str(source.get("localPath") or "")
        manifest_name = str(source.get("contentManifest") or "content-repo.json")
        if not source_id or not local_path:
            continue
        source_root = (repo_root / local_path).resolve()
        content_manifest_path = source_root / manifest_name
        if not content_manifest_path.is_file():
            continue
        content_manifest = _load_json(content_manifest_path)
        ai_config = content_manifest.get("aiKnowledgeStore") or {}
        ai_manifest_rel = str(ai_config.get("manifestPath") or "")
        if not ai_manifest_rel and (source_root / DEFAULT_MANIFEST_PATH).is_file():
            ai_manifest_rel = DEFAULT_MANIFEST_PATH
        if not ai_manifest_rel:
            continue
        if not _is_relative_public_path(ai_manifest_rel):
            errors.append(f"{source_id}: AI manifest path must be relative")
            continue

        ai_manifest_path = source_root / ai_manifest_rel
        if not ai_manifest_path.is_file():
            errors.append(f"{source_id}: missing AI knowledge manifest {ai_manifest_rel}")
            continue
        ai_manifest = _load_json(ai_manifest_path)
        _validate_manifest(ai_manifest_path, ai_manifest, errors)

        records_rel = str(ai_manifest.get("sourceRecordsPath") or ai_config.get("recordsPath") or "")
        records_path = source_root / records_rel
        if not records_path.is_file():
            errors.append(f"{source_id}: missing AI knowledge records {records_rel}")
            continue
        records = _load_jsonl(records_path)
        if not records:
            errors.append(f"{source_id}: AI knowledge records are empty")
        for record in records:
            if not record.get("sourceRepo"):
                record["sourceRepo"] = source_id
            _validate_record(records_path, record, errors)

        stores.append(
            {
                "sourceId": source_id,
                "sourceTitle": source.get("title") or source_id,
                "manifestPath": ai_manifest_rel,
                "recordsPath": records_rel,
                "manifest": ai_manifest,
                "records": records,
            }
        )

    return stores, errors


def _select_runtime_profile(stores: list[dict[str, Any]], provider: str) -> dict[str, Any]:
    provider_id = PROVIDER_IDS[provider]
    for store in stores:
        for profile in store["manifest"].get("runtimeProfiles") or []:
            if profile.get("id") == provider_id:
                return dict(profile)
    return {
        "id": provider_id,
        "provider": provider,
        "apiBase": "http://127.0.0.1:11434" if provider == "ollama" else "http://127.0.0.1:1234/v1",
        "chatEndpoint": "/api/chat" if provider == "ollama" else "/chat/completions",
        "embeddingsEndpoint": "/api/embeddings" if provider == "ollama" else "/embeddings",
        "networkScope": "localhost-only",
        "defaultModelPolicy": "owner-selected",
    }


def _aggregate_records(stores: list[dict[str, Any]]) -> list[dict[str, Any]]:
    combined: list[dict[str, Any]] = []
    for store in stores:
        for record in store["records"]:
            enriched = dict(record)
            enriched["contentSourceId"] = store["sourceId"]
            enriched["contentSourceTitle"] = store["sourceTitle"]
            combined.append(enriched)
    combined.sort(key=lambda item: (str(item.get("contentSourceId")), str(item.get("recordId"))))
    return combined


def _build_manifest(stores: list[dict[str, Any]], provider: str) -> dict[str, Any]:
    records = _aggregate_records(stores)
    return {
        "schemaVersion": "open-education/offline-ai-knowledge-package/v1",
        "packageId": "open-education-offline-ai-knowledge",
        "provider": provider,
        "selectedRuntimeProfile": _select_runtime_profile(stores, provider),
        "privacyBoundary": {
            "containsLearnerPrivateData": False,
            "containsCredentials": False,
            "containsPrivateNotes": False,
            "containsEmbeddings": False,
            "privateOverlaysStayLocal": True,
        },
        "sourceStores": [
            {
                "sourceId": store["sourceId"],
                "sourceTitle": store["sourceTitle"],
                "manifestPath": store["manifestPath"],
                "recordsPath": store["recordsPath"],
                "storeId": store["manifest"].get("storeId"),
                "recordCount": len(store["records"]),
            }
            for store in stores
        ],
        "artifacts": {
            "recordsJsonl": "records.jsonl",
            "sqlite": "offline-knowledge-store.sqlite",
        },
        "summary": {
            "storeCount": len(stores),
            "recordCount": len(records),
        },
    }


def _build_sqlite(path: Path, manifest: dict[str, Any], records: list[dict[str, Any]]) -> None:
    if path.exists():
        path.unlink()
    with sqlite3.connect(path) as conn:
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute(
            """
            CREATE TABLE package_manifest (
                key TEXT PRIMARY KEY,
                value_json TEXT NOT NULL
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE runtime_profiles (
                id TEXT PRIMARY KEY,
                provider TEXT NOT NULL,
                api_base TEXT NOT NULL,
                chat_endpoint TEXT NOT NULL,
                embeddings_endpoint TEXT NOT NULL,
                network_scope TEXT NOT NULL,
                profile_json TEXT NOT NULL
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE records (
                content_source_id TEXT NOT NULL,
                record_id TEXT NOT NULL,
                kind TEXT NOT NULL,
                title TEXT NOT NULL,
                source_repo TEXT NOT NULL,
                source_path TEXT NOT NULL,
                summary TEXT NOT NULL,
                retrieval_terms_json TEXT NOT NULL,
                record_json TEXT NOT NULL,
                PRIMARY KEY (content_source_id, record_id)
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE local_notes (
                note_id TEXT PRIMARY KEY,
                content_source_id TEXT NOT NULL,
                record_id TEXT NOT NULL,
                note_kind TEXT NOT NULL,
                body TEXT NOT NULL,
                created_at_utc TEXT NOT NULL,
                private_overlay INTEGER NOT NULL DEFAULT 1
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE sync_log (
                event_id TEXT PRIMARY KEY,
                event_kind TEXT NOT NULL,
                event_json TEXT NOT NULL,
                created_at_utc TEXT NOT NULL
            )
            """
        )
        conn.execute(
            "INSERT INTO package_manifest(key, value_json) VALUES (?, ?)",
            ("manifest", json.dumps(manifest, sort_keys=True)),
        )
        profile = manifest["selectedRuntimeProfile"]
        conn.execute(
            """
            INSERT INTO runtime_profiles(
                id, provider, api_base, chat_endpoint, embeddings_endpoint, network_scope, profile_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                profile["id"],
                profile["provider"],
                profile["apiBase"],
                profile["chatEndpoint"],
                profile["embeddingsEndpoint"],
                profile["networkScope"],
                json.dumps(profile, sort_keys=True),
            ),
        )
        for record in records:
            conn.execute(
                """
                INSERT INTO records(
                    content_source_id, record_id, kind, title, source_repo, source_path, summary,
                    retrieval_terms_json, record_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    record.get("contentSourceId"),
                    record.get("recordId"),
                    record.get("kind"),
                    record.get("title"),
                    record.get("sourceRepo"),
                    record.get("sourcePath"),
                    record.get("summary"),
                    json.dumps(record.get("retrievalTerms") or [], sort_keys=True),
                    json.dumps(record, sort_keys=True),
                ),
            )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--output-root", default=".codex-cache/tmp/offline-ai-knowledge-store")
    parser.add_argument("--provider", choices=("ollama", "lm-studio"), default=DEFAULT_PROVIDER)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    output_root = (repo_root / args.output_root).resolve()
    stores, errors = _discover_content_stores(repo_root)
    if not stores:
        errors.append("No offline AI knowledge manifests found in registered content sources.")
    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        return 1

    records = _aggregate_records(stores)
    manifest = _build_manifest(stores, args.provider)
    if not args.check:
        output_root.mkdir(parents=True, exist_ok=True)
        _write_json(output_root / "manifest.json", manifest)
        _write_jsonl(output_root / "records.jsonl", records)
        _build_sqlite(output_root / "offline-knowledge-store.sqlite", manifest, records)

    print(
        json.dumps(
            {
                "schemaVersion": 1,
                "status": "ok",
                "provider": args.provider,
                "storeCount": len(stores),
                "recordCount": len(records),
                "outputRoot": str(output_root).replace("\\", "/") if not args.check else "",
            },
            indent=2,
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

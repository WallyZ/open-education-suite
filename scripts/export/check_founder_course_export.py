"""Validate the Founder-Level Civic Classical all-object export and mastery flow."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import re
import tempfile
from pathlib import Path
from typing import Any, Iterable


ABSOLUTE_PATH_PATTERN = re.compile(r"(?:^[A-Za-z]:[\\/]|^/|/Users/|/home/)", re.IGNORECASE)


def load_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(value, dict):
        raise ValueError(f"Expected JSON object: {path}")
    return value


def iter_jsonl(path: Path) -> Iterable[dict[str, Any]]:
    with path.open("r", encoding="utf-8-sig") as handle:
        for line_number, line in enumerate(handle, start=1):
            if not line.strip():
                continue
            value = json.loads(line)
            if not isinstance(value, dict):
                raise ValueError(f"Expected JSON object: {path}:{line_number}")
            yield value


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def matches_text_sha256(path: Path, expected: str) -> bool:
    if sha256_file(path) == expected:
        return True
    normalized = path.read_bytes().replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    return hashlib.sha256(normalized).hexdigest() == expected


def stable_sha256(value: Any) -> str:
    payload = json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def walk_keys(value: Any) -> Iterable[str]:
    if isinstance(value, dict):
        for key, child in value.items():
            yield str(key)
            yield from walk_keys(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk_keys(child)


def find_record(path: Path, record_id: str) -> dict[str, Any]:
    for record in iter_jsonl(path):
        if record.get("id") == record_id:
            return record
    raise ValueError(f"Record not found: {record_id} in {path}")


def assert_subset(actual: Any, expected: Any, path: str = "$") -> None:
    if isinstance(expected, dict):
        if not isinstance(actual, dict):
            raise ValueError(f"{path} must be an object")
        for key, value in expected.items():
            if key not in actual:
                raise ValueError(f"{path}.{key} is missing")
            assert_subset(actual[key], value, f"{path}.{key}")
        return
    if isinstance(expected, list):
        if actual != expected:
            raise ValueError(f"{path} list mismatch")
        return
    if actual != expected:
        raise ValueError(f"{path} expected {expected!r}; found {actual!r}")


def validate_manifest_schema(manifest: dict[str, Any], schema: dict[str, Any]) -> None:
    for key in schema.get("required", []):
        if key not in manifest:
            raise ValueError(f"Manifest missing required field: {key}")
    for key, rule in schema.get("properties", {}).items():
        if key not in manifest:
            continue
        if "const" in rule and manifest[key] != rule["const"]:
            raise ValueError(f"Manifest {key} must equal {rule['const']!r}")
        if rule.get("type") == "integer" and not isinstance(manifest[key], int):
            raise ValueError(f"Manifest {key} must be an integer")


def validate_public_record(
    record: dict[str, Any],
    object_type: str,
    forbidden_keys: set[str],
    operations: set[str],
) -> None:
    required = {
        "schemaVersion",
        "exportVersion",
        "id",
        "objectType",
        "visibility",
        "sourceLocator",
        "references",
        "audienceMetadata",
        "data",
    }
    if required - record.keys():
        raise ValueError(f"Public record {record.get('id')} misses {sorted(required - record.keys())}")
    if record["schemaVersion"] != 1 or record["exportVersion"] != "2026-07-23-v1":
        raise ValueError(f"Public record version mismatch: {record['id']}")
    if record["objectType"] != object_type or record["visibility"] != "learner-safe-public":
        raise ValueError(f"Public type/visibility mismatch: {record['id']}")
    source_path = str(record["sourceLocator"].get("path", ""))
    if not source_path or ABSOLUTE_PATH_PATTERN.search(source_path):
        raise ValueError(f"Public source locator must be relative: {record['id']}")
    audience = record["audienceMetadata"]
    if (
        audience.get("audienceClassification") != "minor-safe"
        or audience.get("minorSafe") is not True
        or audience.get("adultOnly") is not False
        or not operations.issubset(set(audience.get("allowedOperations", [])))
    ):
        raise ValueError(f"Public audience metadata mismatch: {record['id']}")
    leaked = forbidden_keys.intersection(walk_keys(record))
    if leaked:
        raise ValueError(f"Public record leaks restricted keys {sorted(leaked)}: {record['id']}")


def validate_restricted_record(record: dict[str, Any]) -> None:
    required = {
        "schemaVersion",
        "exportVersion",
        "id",
        "objectType",
        "subtype",
        "visibility",
        "learnerVisible",
        "targetId",
        "sourceLocator",
        "references",
        "data",
    }
    if required - record.keys():
        raise ValueError(f"Restricted record misses fields: {record.get('id')}")
    if (
        record["objectType"] != "restricted-answer-key"
        or record["visibility"] != "restricted-facilitator-or-authorized-grader"
        or record["learnerVisible"] is not False
        or not str(record["id"]).startswith("restricted-answer:")
    ):
        raise ValueError(f"Restricted visibility contract mismatch: {record['id']}")


def score_evidence(submitted: list[str], expected: list[str]) -> dict[str, Any]:
    expected_normalized = {item.strip().casefold() for item in expected}
    submitted_normalized = {item.strip().casefold() for item in submitted}
    matched = len(expected_normalized.intersection(submitted_normalized))
    total = len(expected_normalized)
    if matched == total:
        level = 4
    elif matched >= max(1, total - 1):
        level = 3
    elif matched >= 2:
        level = 2
    else:
        level = 1
    return {"level": level, "matched": matched, "total": total}


def run_end_to_end(
    founder_root: Path,
    manifest: dict[str, Any],
    contract: dict[str, Any],
    public_paths: dict[str, Path],
    restricted_path: Path,
    temp_root: Path,
) -> dict[str, Any]:
    flow_contract = contract["selectedFlow"]
    lesson = find_record(public_paths["lesson"], flow_contract["lessonId"])
    lesson_data = lesson["data"]
    if lesson_data["gradeCode"] != "g1" or lesson_data["calendarWeek"] != 10 or lesson_data["day"] != 1:
        raise ValueError("Selected founder lesson schedule mismatch")

    reading_id = lesson_data["readingId"]
    if not reading_id:
        raise ValueError("Selected founder lesson lacks its exact reading")
    reading = find_record(public_paths["reading"], reading_id)
    materials = find_record(public_paths["materials-safety"], lesson_data["materialsSafetyId"])
    access_routes = [
        find_record(public_paths["access-route"], access_id)
        for access_id in lesson_data["accessRouteIds"]
    ]
    source_rights_ids = [
        ref for ref in reading["references"] if str(ref).startswith("source-rights:")
    ]
    if not source_rights_ids:
        raise ValueError("Selected reading lacks source-rights links")
    for source_rights_id in source_rights_ids:
        find_record(public_paths["source-rights"], source_rights_id)

    learner_render = {
        "lessonId": lesson["id"],
        "title": lesson_data["title"],
        "objective": lesson_data["objective"],
        "reading": {
            "id": reading["id"],
            "title": reading["data"]["title"],
            "sourceRoute": reading["data"]["sourceRoute"],
            "learnerMaterial": reading["data"]["learnerMaterial"],
            "sourceRightsIds": source_rights_ids,
        },
        "materials": materials["data"]["materials"],
        "safetyAndPrivacy": materials["data"]["safetyAndPrivacy"],
        "accessRoutes": [
            {"id": route["id"], "description": route["data"]["description"]}
            for route in access_routes
        ],
    }
    forbidden_render_keys = set(contract["forbiddenPublicKeys"])
    if forbidden_render_keys.intersection(walk_keys(learner_render)):
        raise ValueError("Learner render contains restricted payload")

    initial_assessment = find_record(
        public_paths["assessment"], flow_contract["initialAssessmentId"]
    )
    retest_assessment = find_record(
        public_paths["assessment"], flow_contract["retestAssessmentId"]
    )
    delayed_assessment = find_record(
        public_paths["assessment"], flow_contract["delayedAssessmentId"]
    )
    rubric = find_record(public_paths["rubric"], flow_contract["rubricId"])
    daily_rubric = find_record(public_paths["rubric"], lesson_data["rubricId"])
    correction = find_record(
        public_paths["correction-reteach"], lesson_data["correctionReteachId"]
    )
    progress_template = find_record(
        public_paths["progress-state"], lesson_data["progressStateId"]
    )

    for assessment in (initial_assessment, retest_assessment, delayed_assessment):
        if lesson["id"] not in assessment["references"]:
            raise ValueError(f"Assessment does not link selected lesson: {assessment['id']}")
        if rubric["id"] not in assessment["references"]:
            raise ValueError(f"Assessment does not link actual family rubric: {assessment['id']}")

    restricted_initial = find_record(
        restricted_path, initial_assessment["data"]["restrictedAnswerKeyId"]
    )
    restricted_retest = find_record(
        restricted_path, retest_assessment["data"]["restrictedAnswerKeyId"]
    )
    if (
        restricted_initial["targetId"] != initial_assessment["id"]
        or restricted_retest["targetId"] != retest_assessment["id"]
    ):
        raise ValueError("Restricted assessment key target mismatch")

    initial_expected = list(restricted_initial["data"]["expectedEvidence"])
    retest_expected = list(restricted_retest["data"]["expectedEvidence"])
    initial_attempt = initial_expected[:2]
    initial_score = score_evidence(initial_attempt, initial_expected)
    if initial_score["level"] != flow_contract["initialExpectedLevel"]:
        raise ValueError("Initial rubric score mismatch")
    if int(daily_rubric["data"]["passingLevel"]) != 3:
        raise ValueError("Actual daily rubric passing level mismatch")

    remediation = {
        "correctionReteachId": correction["id"],
        "steps": correction["data"]["steps"],
        "cue": restricted_initial["data"]["correctionCue"],
        "firstAttemptPreserved": True,
    }
    if not remediation["steps"] or not remediation["cue"]:
        raise ValueError("Remediation route is incomplete")

    retest_score = score_evidence(retest_expected, retest_expected)
    if retest_score["level"] != flow_contract["retestExpectedLevel"]:
        raise ValueError("Retest rubric score mismatch")

    event_ids = {
        record_id.rsplit(":", 1)[-1]: record_id
        for record_id in progress_template["data"]["allowedMasteryEventIds"]
    }
    required_event_types = {
        "attempt-recorded",
        "rubric-scored",
        "remediation-completed",
        "retest-scored",
        "delayed-review-scheduled",
    }
    if set(event_ids) != required_event_types:
        raise ValueError("Progress template mastery-event contract mismatch")
    for event_id in event_ids.values():
        event = find_record(public_paths["mastery-event"], event_id)
        if (
            progress_template["id"] not in event["references"]
            or event["data"]["evidenceImpact"] != "evidence-bearing"
            or event["data"]["proposalOnly"] is not False
        ):
            raise ValueError(f"Mastery event is not evidence-bearing: {event_id}")

    state = copy.deepcopy(progress_template["data"])
    state.update(
        {
            "status": "in-progress",
            "attemptCount": 2,
            "attemptEvents": [
                {
                    "eventContractId": event_ids["attempt-recorded"],
                    "assessmentId": initial_assessment["id"],
                    "submittedEvidenceCount": len(initial_attempt),
                },
                {
                    "eventContractId": event_ids["rubric-scored"],
                    "assessmentId": initial_assessment["id"],
                    "rubricId": rubric["id"],
                    "level": initial_score["level"],
                    "status": "needs-remediation",
                },
                {
                    "eventContractId": event_ids["remediation-completed"],
                    "correctionReteachId": correction["id"],
                    "firstAttemptPreserved": True,
                },
                {
                    "eventContractId": event_ids["retest-scored"],
                    "assessmentId": retest_assessment["id"],
                    "rubricId": rubric["id"],
                    "level": retest_score["level"],
                    "status": "passed",
                },
                {
                    "eventContractId": event_ids["delayed-review-scheduled"],
                    "assessmentId": delayed_assessment["id"],
                    "dueDate": "2026-08-06",
                },
            ],
            "masteryStatus": flow_contract["masteryStatus"],
            "delayedReview": {
                "assessmentId": delayed_assessment["id"],
                "dueDate": "2026-08-06",
                "status": "scheduled",
            },
            "version": 5,
        }
    )
    if "catalog-preview" in json.dumps(state) or "proposal-only" in json.dumps(state):
        raise ValueError("Mastery state fell back to a preview/proposal-only path")

    temp_root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="founder-e2e-", dir=temp_root) as temp_dir:
        temp_path = Path(temp_dir)
        persisted_path = temp_path / "progress-state.json"
        persisted_path.write_text(
            json.dumps(state, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )
        persisted = load_json(persisted_path)
        export_snapshot = {
            "schemaVersion": 1,
            "sourceId": manifest["sourceId"],
            "lessonId": lesson["id"],
            "stateSha256": stable_sha256(persisted),
            "state": persisted,
        }
        export_path = temp_path / "learner-progress-export.json"
        export_path.write_text(
            json.dumps(export_snapshot, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        imported = load_json(export_path)
        if (
            imported["stateSha256"] != stable_sha256(imported["state"])
            or imported["state"] != state
        ):
            raise ValueError("Persisted learner state failed export/import integrity")

    return {
        "schemaVersion": 1,
        "status": "passed",
        "sourceId": manifest["sourceId"],
        "exportVersion": manifest["exportVersion"],
        "recordCounts": {
            "public": manifest["publicRecordCount"],
            "restricted": manifest["restrictedRecordCount"],
            "total": manifest["totalRecordCount"],
            "references": load_json(
                founder_root / manifest["referentialIntegrityReportPath"]
            )["referenceCount"],
        },
        "selection": {
            "lessonId": lesson["id"],
            "gradeCode": lesson_data["gradeCode"],
            "calendarWeek": lesson_data["calendarWeek"],
            "day": lesson_data["day"],
            "initialAssessmentId": initial_assessment["id"],
            "retestAssessmentId": retest_assessment["id"],
            "delayedAssessmentId": delayed_assessment["id"],
            "rubricId": rubric["id"],
        },
        "flow": {
            "steps": [
                "render-source-and-accessible-materials",
                "record-initial-attempt",
                "apply-exported-rubric",
                "apply-correction-and-reteach",
                "record-changed-retest",
                "schedule-delayed-review",
                "persist-export-import-state",
            ],
            "initialScoreLevel": initial_score["level"],
            "initialStatus": "needs-remediation",
            "retestScoreLevel": retest_score["level"],
            "masteryStatus": state["masteryStatus"],
            "delayedReviewDate": state["delayedReview"]["dueDate"],
            "masteryImpact": "evidence-bearing",
            "catalogPreviewUsed": False,
            "proposalOnlyUsed": False,
            "restrictedPayloadInLearnerRender": False,
            "statePersisted": True,
            "stateExportImported": True,
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate founder all-object exports and the real mastery flow"
    )
    parser.add_argument("--suite-root", default=".")
    parser.add_argument("--founder-root", required=True)
    parser.add_argument("--temp-root", default="")
    parser.add_argument("--evidence-output", default="")
    args = parser.parse_args()

    suite_root = Path(args.suite_root).resolve()
    founder_root = Path(args.founder_root).resolve()
    export_root = founder_root / "exports" / "suite-v1"
    manifest = load_json(export_root / "suite-export-manifest.json")
    schema = load_json(suite_root / "schemas" / "founder-course-export.schema.json")
    contract = schema["x-exportContract"]
    validate_manifest_schema(manifest, schema)

    expected_types = set(contract["requiredPublicObjectTypes"])
    forbidden_keys = set(contract["forbiddenPublicKeys"])
    operations = set(contract["requiredAudienceOperations"])
    file_entries = manifest["files"]
    if len(file_entries) != len(expected_types) + 1:
        raise ValueError("Export manifest shard count mismatch")
    public_entries = {
        entry["objectType"]: entry
        for entry in file_entries
        if entry["visibility"] == "learner-safe-public"
    }
    if set(public_entries) != expected_types:
        raise ValueError("Export manifest public object-type set mismatch")
    restricted_entries = [
        entry
        for entry in file_entries
        if entry["visibility"] == "restricted-facilitator-or-authorized-grader"
    ]
    if len(restricted_entries) != 1:
        raise ValueError("Export manifest must contain one restricted shard")

    public_paths: dict[str, Path] = {}
    all_ids: set[str] = set()
    public_ids: set[str] = set()
    restricted_ids: set[str] = set()
    observed_public_count = 0
    observed_restricted_count = 0
    for object_type, entry in public_entries.items():
        path = founder_root / entry["path"]
        public_paths[object_type] = path
        if not matches_text_sha256(path, entry["sha256"]):
            raise ValueError(f"Public shard checksum mismatch: {entry['path']}")
        shard_count = 0
        for record in iter_jsonl(path):
            validate_public_record(record, object_type, forbidden_keys, operations)
            record_id = str(record["id"])
            if record_id in all_ids:
                raise ValueError(f"Duplicate export id: {record_id}")
            all_ids.add(record_id)
            public_ids.add(record_id)
            shard_count += 1
        if shard_count != entry["recordCount"]:
            raise ValueError(f"Public shard count mismatch: {entry['path']}")
        observed_public_count += shard_count

    restricted_entry = restricted_entries[0]
    restricted_path = founder_root / restricted_entry["path"]
    if not matches_text_sha256(restricted_path, restricted_entry["sha256"]):
        raise ValueError("Restricted shard checksum mismatch")
    for record in iter_jsonl(restricted_path):
        validate_restricted_record(record)
        record_id = str(record["id"])
        if record_id in all_ids:
            raise ValueError(f"Duplicate export id: {record_id}")
        all_ids.add(record_id)
        restricted_ids.add(record_id)
        observed_restricted_count += 1
    if observed_restricted_count != restricted_entry["recordCount"]:
        raise ValueError("Restricted shard count mismatch")

    reference_count = 0
    for path in public_paths.values():
        for record in iter_jsonl(path):
            for target_id in record["references"]:
                reference_count += 1
                if target_id not in all_ids:
                    raise ValueError(f"Dangling public reference: {record['id']} -> {target_id}")
    for record in iter_jsonl(restricted_path):
        if record["targetId"] not in public_ids:
            raise ValueError(f"Restricted target is not public: {record['id']}")
        for target_id in record["references"]:
            reference_count += 1
            if target_id not in all_ids:
                raise ValueError(f"Dangling restricted reference: {record['id']} -> {target_id}")

    integrity = load_json(export_root / "referential-integrity-report.json")
    if (
        integrity["status"] != "passed"
        or integrity["uniqueIdCount"] != len(all_ids)
        or integrity["referenceCount"] != reference_count
        or integrity["danglingReferenceCount"] != 0
        or integrity["publicRestrictedFieldLeakCount"] != 0
        or integrity["progressEventTargetValidation"] != "all-exact-targets-resolved"
    ):
        raise ValueError("Founder referential-integrity report mismatch")
    if (
        observed_public_count != manifest["publicRecordCount"]
        or observed_restricted_count != manifest["restrictedRecordCount"]
        or len(all_ids) != manifest["totalRecordCount"]
    ):
        raise ValueError("Founder export aggregate counts mismatch")

    temp_root = (
        Path(args.temp_root).resolve()
        if args.temp_root
        else suite_root / ".codex-cache" / "tmp"
    )
    evidence = run_end_to_end(
        founder_root,
        manifest,
        contract,
        public_paths,
        restricted_path,
        temp_root,
    )
    expected_evidence = load_json(
        suite_root / "fixtures" / "founder-course-end-to-end.expected.json"
    )
    assert_subset(evidence, expected_evidence)
    evidence_text = json.dumps(evidence, indent=2, ensure_ascii=False) + "\n"
    if args.evidence_output:
        output_path = Path(args.evidence_output).resolve()
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(evidence_text, encoding="utf-8")
    print(evidence_text, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

"""Deterministic negative-fixture and registry checks for audience policy."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

from audience_policy import OPERATIONS, filter_records, load_json, load_records, metadata_errors


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def ids(records: list[dict[str, Any]]) -> list[str]:
    return sorted(str(record["contentId"]) for record in records)


def validate_records(records: list[dict[str, Any]], label: str) -> None:
    require(records, f"{label} contains no records")
    metadata_ids: set[str] = set()
    content_ids: set[str] = set()
    for record in records:
        errors = metadata_errors(record)
        require(not errors, f"{label} invalid record {record.get('metadataId')}: {errors}")
        metadata_id = str(record["metadataId"])
        content_id = str(record["contentId"])
        require(metadata_id not in metadata_ids, f"{label} duplicate metadataId: {metadata_id}")
        require(content_id not in content_ids, f"{label} duplicate contentId: {content_id}")
        metadata_ids.add(metadata_id)
        content_ids.add(content_id)


def validate_fixture(repo_root: Path) -> None:
    fixture = load_json(repo_root / "fixtures" / "audience-policy-negative.json")
    records = fixture["records"]
    contexts = fixture["contexts"]
    expectations = fixture["expectations"]
    validate_records(records, "negative fixture")

    minor_expected = sorted(expectations["minorAllowedContentIds"])
    male_results: dict[str, list[str]] = {}
    female_results: dict[str, list[str]] = {}
    for operation in sorted(OPERATIONS):
        tutor_context = "retrieval-grounded-explanation" if operation == "tutor-context" else ""
        query = "relationship" if operation == "search" else ""
        male = filter_records(
            records,
            contexts["minorMale"],
            operation,
            query=query,
            requested_tutor_context=tutor_context,
        )
        female = filter_records(
            records,
            contexts["minorFemale"],
            operation,
            query=query,
            requested_tutor_context=tutor_context,
        )
        male_results[operation] = ids(male)
        female_results[operation] = ids(female)
        require(male_results[operation] == female_results[operation], f"gender swap changed {operation} result")
        if operation == "search":
            require(not male, "minor search leaked adult relationship content")
        else:
            require(male_results[operation] == minor_expected, f"minor {operation} result mismatch")
        serialized = json.dumps(male, ensure_ascii=False)
        require(
            expectations["blockedDependencyMustNotAppear"] not in serialized,
            f"minor {operation} leaked an adult-only dependency",
        )

    adult_no_opt_in = ids(
        filter_records(records, contexts["adultNoOptIn"], "catalog")
    )
    require(
        adult_no_opt_in == sorted(expectations["adultNoOptInAllowedContentIds"]),
        "adult content appeared without explicit opt-in",
    )
    adult_opt_in = ids(filter_records(records, contexts["adultOptIn"], "catalog"))
    for expected_id in expectations["adultOptInContainsContentIds"]:
        require(expected_id in adult_opt_in, f"adult opt-in did not expose {expected_id}")

    for record in records:
        require(
            record["masteryAndSafetyPolicyId"] == expectations["masteryAndSafetyPolicyId"],
            "fixture mastery/safety policy differs by content",
        )

    malformed = dict(records[0])
    malformed.pop("minorSafe")
    require(
        not filter_records([malformed], contexts["minorMale"], "catalog"),
        "missing metadata did not fail closed",
    )


def validate_source_registry(repo_root: Path) -> None:
    registry = load_json(repo_root / "content-sources.json")
    audience_registry = load_json(repo_root / "audience-sources.json")
    source_ids = {str(record["id"]) for record in registry["contentSources"]}
    audience_ids = {str(record["sourceId"]) for record in audience_registry["sources"]}
    require(source_ids == audience_ids, "suite source audience registry does not exactly cover content-sources.json")
    require(
        audience_registry.get("defaultRule") == "fail-closed-when-source-or-object-metadata-is-missing",
        "suite source audience registry is not fail closed",
    )
    adult_record = next(
        record for record in audience_registry["sources"]
        if record["sourceId"] == "mens-relationship-skills"
    )
    require(adult_record["adultOnly"] is True, "relationship source is not adult-only")
    require(adult_record["minorSafe"] is False, "relationship source is marked minor-safe")
    require(
        adult_record["guardianOrFacilitatorRequirement"] == "adult-confirmed-opt-in",
        "relationship source does not require confirmed adult opt-in",
    )


def validate_actual_catalog(repo_root: Path) -> int:
    teaching_root = repo_root / "scripts" / "teaching"
    if str(teaching_root) not in sys.path:
        sys.path.insert(0, str(teaching_root))
    from content_catalog_adapter import build_content_catalog

    operator_catalog = build_content_catalog(repo_root, operator_unfiltered=True)
    all_courses = [
        course
        for source in operator_catalog["sources"]
        for course in source.get("courses", [])
    ]
    require(all_courses, "operator catalog contains no courses")
    for course in all_courses:
        metadata = course.get("audienceMetadata")
        require(isinstance(metadata, dict), f"course lacks audience metadata: {course.get('id')}")
        errors = metadata_errors(metadata)
        require(not errors, f"course audience metadata is invalid: {course.get('id')} {errors}")

    general_catalog = build_content_catalog(repo_root)
    general_serialized = json.dumps(general_catalog, ensure_ascii=False)
    require(
        "mens-relationship-skills" not in general_serialized,
        "default learner catalog includes adult-only relationship content",
    )
    require(
        general_catalog["audienceEnforcement"] == "fail-closed-shared-policy",
        "default learner catalog is not audience-filtered",
    )

    adult_opt_in_context = {
        "audienceRole": "adult",
        "grade": "adult",
        "ageBand": {"label": "ages-18-adult", "minAge": 18, "maxAge": None},
        "adultConfirmed": True,
        "adultContentOptIn": True,
        "guardianConfirmed": False,
        "facilitatorPresent": False,
        "blockedSensitiveTopicCategories": [],
        "completedPrerequisiteIds": [],
    }
    adult_opt_in_catalog = build_content_catalog(repo_root, adult_opt_in_context)
    require(
        any(
            source.get("sourceId") == "mens-relationship-skills"
            for source in adult_opt_in_catalog["sources"]
        ),
        "confirmed adult opt-in does not expose the adult relationship source",
    )

    minor_context = {
        "audienceRole": "minor",
        "grade": "9",
        "ageBand": {"label": "ages-14-15", "minAge": 14, "maxAge": 15},
        "adultConfirmed": False,
        "adultContentOptIn": True,
        "guardianConfirmed": True,
        "facilitatorPresent": True,
        "blockedSensitiveTopicCategories": [],
        "completedPrerequisiteIds": [],
        "gender": "female",
    }
    minor_catalog = build_content_catalog(repo_root, minor_context)
    require(
        "mens-relationship-skills" not in json.dumps(minor_catalog, ensure_ascii=False),
        "minor catalog includes adult-only content despite a false adult opt-in",
    )
    return len(all_courses)


def validate_external_registry(path: Path, expected_counts: dict[str, int]) -> None:
    records = load_records(path)
    validate_records(records, "content audience registry")
    actual_counts: dict[str, int] = {}
    for record in records:
        kind = str(record["contentKind"])
        actual_counts[kind] = actual_counts.get(kind, 0) + 1
    require(actual_counts == expected_counts, f"content registry counts mismatch: {actual_counts}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Check audience policy and negative fixtures")
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--content-registry", default="")
    parser.add_argument("--expected-counts", default="")
    args = parser.parse_args()
    repo_root = Path(args.repo_root).resolve()

    validate_source_registry(repo_root)
    validate_fixture(repo_root)
    course_count = validate_actual_catalog(repo_root)
    if args.content_registry:
        require(bool(args.expected_counts), "--expected-counts is required with --content-registry")
        expected_counts = json.loads(args.expected_counts)
        validate_external_registry(Path(args.content_registry).resolve(), expected_counts)

    print(
        json.dumps(
            {
                "schemaVersion": 1,
                "status": "passed",
                "operationsChecked": sorted(OPERATIONS),
                "sourceAudienceRecords": len(load_json(repo_root / "audience-sources.json")["sources"]),
                "effectiveCourseMetadataRecords": course_count,
                "externalRegistryChecked": bool(args.content_registry),
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"Audience policy check failed: {exc}", file=sys.stderr)
        raise SystemExit(1)

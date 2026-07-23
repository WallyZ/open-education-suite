#!/usr/bin/env python3
"""Validate Founder all-grade learning-process and memory-mastery exports."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import re
import tempfile
from pathlib import Path
from typing import Any, Iterable


ABSOLUTE_PATH_PATTERN = re.compile(r"^(?:[A-Za-z]:[\\/]|/)")
GRADE_CODES = [
    "gk",
    "g1",
    "g2",
    "g3",
    "g4",
    "g5",
    "g6",
    "g7",
    "g8",
    "g9",
    "g10",
    "g11",
    "g12",
]
NOMINAL_WEEKS = [4, 8, 12]
SCHEDULED_WEEKS = {
    1: {4: 4, 8: 8, 12: 12},
    2: {4: 4, 8: 8, 12: 10},
    3: {4: 4, 8: 8, 12: 11},
    4: {4: 4, 8: 8, 12: 12},
}
ARTIFACT_TYPES = {
    "actor-reading",
    "spaced-memory",
    "error-log",
    "teach-back",
    "transfer",
    "method-reflection",
}
REQUESTED_ARTIFACT_TYPES = ARTIFACT_TYPES - {"method-reflection"}
RETENTION_INTERVALS = {
    "one-day": 1,
    "seven-day": 7,
    "thirty-day": 30,
    "ninety-day": 90,
}
RUBRIC_LEVELS = {
    1: "not-yet",
    2: "emerging",
    3: "independent",
    4: "transfer",
}


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
                raise ValueError(f"Expected object at {path}:{line_number}")
            yield value


def compact_sha256(value: Any) -> str:
    payload = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def load_id_set(path: Path) -> set[str]:
    result: set[str] = set()
    for record in iter_jsonl(path):
        record_id = str(record.get("id", ""))
        if not record_id or record_id in result:
            raise ValueError(f"Missing or duplicate suite record ID in {path}: {record_id}")
        result.add(record_id)
    return result


def assert_subset(actual: Any, expected: Any, path: str = "$") -> None:
    if isinstance(expected, dict):
        if not isinstance(actual, dict):
            raise ValueError(f"{path} must be an object")
        for key, value in expected.items():
            if key not in actual:
                raise ValueError(f"Missing expected key {path}.{key}")
            assert_subset(actual[key], value, f"{path}.{key}")
        return
    if isinstance(expected, list):
        if actual != expected:
            raise ValueError(f"Expected exact list at {path}")
        return
    if actual != expected:
        raise ValueError(f"Expected {expected!r} at {path}; found {actual!r}")


def validate_relative_file(founder_root: Path, relative_path: str, context: str) -> None:
    if not relative_path or ABSOLUTE_PATH_PATTERN.search(relative_path):
        raise ValueError(f"Path must be relative for {context}: {relative_path}")
    resolved = (founder_root / relative_path).resolve()
    try:
        resolved.relative_to(founder_root)
    except ValueError as exc:
        raise ValueError(f"Path escapes Founder root for {context}: {relative_path}") from exc
    if not resolved.is_file():
        raise ValueError(f"Referenced file is missing for {context}: {relative_path}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate Founder learning-process and memory-mastery exports"
    )
    parser.add_argument("--suite-root", default=".")
    parser.add_argument("--founder-root", required=True)
    parser.add_argument("--temp-root")
    parser.add_argument("--evidence-output")
    args = parser.parse_args()

    suite_root = Path(args.suite_root).resolve()
    founder_root = Path(args.founder_root).resolve()
    export_root = founder_root / "exports" / "learning-process-v1"
    schema = load_json(
        suite_root / "schemas" / "founder-learning-process-export.schema.json"
    )
    contract = schema["x-learningProcessContract"]
    summary = load_json(export_root / "learning-process-export-summary.json")
    bootcamps = list(iter_jsonl(export_root / "annual-learning-bootcamps.jsonl"))
    checkpoints = list(
        iter_jsonl(export_root / "term-learning-process-checkpoints.jsonl")
    )
    founder_schema = load_json(
        export_root / "learning-process-checkpoint.schema.json"
    )
    if founder_schema["x-learningProcessContract"]["termCheckpoints"] != 156:
        raise ValueError("Founder learning-process schema contract mismatch")
    if (
        summary.get("status")
        != "all-grade-learning-process-and-memory-mastery-export-passed-real-learner-evidence-unearned"
    ):
        raise ValueError("Learning-process summary status mismatch")

    public_root = founder_root / "exports" / "suite-v1" / "public"
    route_sets = {
        "lesson": load_id_set(public_root / "lesson.jsonl"),
        "reading": load_id_set(public_root / "reading.jsonl"),
        "assessment": load_id_set(public_root / "assessment.jsonl"),
        "rubric": load_id_set(public_root / "rubric.jsonl"),
        "portfolio": load_id_set(public_root / "portfolio-artifact.jsonl"),
        "correction": load_id_set(public_root / "correction-reteach.jsonl"),
        "progress": load_id_set(public_root / "progress-state.jsonl"),
        "mastery": load_id_set(public_root / "mastery-event.jsonl"),
    }

    bootcamp_ids: set[str] = set()
    bootcamp_hash_passes = 0
    bootcamp_day_routes = 0
    bootcamp_by_grade: dict[str, dict[str, Any]] = {}
    for record in bootcamps:
        bootcamp_id = str(record.get("bootcampId", ""))
        grade_code = str(record.get("gradeCode", ""))
        if (
            bootcamp_id != f"learning-bootcamp:{grade_code}"
            or grade_code not in GRADE_CODES
            or bootcamp_id in bootcamp_ids
        ):
            raise ValueError(f"Invalid or duplicate annual bootcamp: {bootcamp_id}")
        bootcamp_ids.add(bootcamp_id)
        bootcamp_by_grade[grade_code] = record
        supplied_hash = str(record.get("recordSha256", ""))
        unhashed = copy.deepcopy(record)
        unhashed.pop("recordSha256")
        if compact_sha256(unhashed) != supplied_hash:
            raise ValueError(f"Annual bootcamp checksum mismatch: {bootcamp_id}")
        bootcamp_hash_passes += 1
        day_routes = record.get("dayRoutes")
        if not isinstance(day_routes, list) or len(day_routes) != 6:
            raise ValueError(f"Annual bootcamp must contain six days: {bootcamp_id}")
        if [item["day"] for item in day_routes] != [1, 2, 3, 4, 5, 6]:
            raise ValueError(f"Annual bootcamp day order mismatch: {bootcamp_id}")
        for day_route in day_routes:
            bootcamp_day_routes += 1
            if (
                day_route["suiteLessonId"] not in route_sets["lesson"]
                or day_route["portfolioId"] not in route_sets["portfolio"]
                or day_route["evidenceStatus"] != "awaiting-real-learner-work"
            ):
                raise ValueError(f"Annual bootcamp route mismatch: {bootcamp_id}")
        boundary = record["evidenceBoundary"]
        if (
            boundary["syntheticTemplateOnly"] is not True
            or boundary["completedDayCount"] != 0
            or boundary["realLearnerArtifactCount"] != 0
            or boundary["masteryEarned"] is not False
        ):
            raise ValueError(f"Annual bootcamp evidence boundary mismatch: {bootcamp_id}")
        formation = record["accessPrivacyAndFormation"]
        if (
            formation["christianRoute"] != "encouraged-optional"
            or formation["nonDevotionalAcademicRoute"] != "available-equivalent"
            or formation["familyCommunityPractice"] != "available-optional"
            or formation["compelledProfessionOfFaith"] is not False
            or formation["compelledPoliticalConfession"] is not False
        ):
            raise ValueError(f"Annual bootcamp formation boundary mismatch: {bootcamp_id}")

    required_fields = set(schema["required"])
    checkpoint_ids: set[str] = set()
    artifact_slot_ids: set[str] = set()
    requested_artifact_slot_ids: set[str] = set()
    retention_ids: set[str] = set()
    calibration_ids: set[str] = set()
    checkpoint_hash_passes = 0
    compressed_fallbacks = 0
    artifact_routes = 0
    requested_artifact_routes = 0
    retention_checks = 0
    rubric_count = 0
    calibration_scores = 0
    actual_artifacts = 0
    actual_scores = 0
    completed_retention = 0
    mastery_earned = 0
    catalog_preview_used = 0
    proposal_only_used = 0
    checkpoint_by_key: dict[tuple[str, int, int], dict[str, Any]] = {}

    for record in checkpoints:
        missing = required_fields - record.keys()
        if missing:
            raise ValueError(f"Checkpoint missing fields {sorted(missing)}")
        grade_code = str(record["gradeCode"])
        term = int(record["term"])
        nominal_week = int(record["nominalTermWeek"])
        checkpoint_id = str(record["checkpointId"])
        expected_id = f"learning-checkpoint:{grade_code}:t{term}:w{nominal_week:02d}"
        if (
            grade_code not in GRADE_CODES
            or term not in (1, 2, 3, 4)
            or nominal_week not in NOMINAL_WEEKS
            or checkpoint_id != expected_id
            or checkpoint_id in checkpoint_ids
        ):
            raise ValueError(f"Invalid or duplicate checkpoint: {checkpoint_id}")
        checkpoint_ids.add(checkpoint_id)
        checkpoint_by_key[(grade_code, term, nominal_week)] = record
        supplied_hash = str(record["recordSha256"])
        unhashed = copy.deepcopy(record)
        unhashed.pop("recordSha256")
        if compact_sha256(unhashed) != supplied_hash:
            raise ValueError(f"Checkpoint checksum mismatch: {checkpoint_id}")
        checkpoint_hash_passes += 1

        scheduled_week = SCHEDULED_WEEKS[term][nominal_week]
        expected_compressed = scheduled_week != nominal_week
        if (
            record["scheduledTermWeek"] != scheduled_week
            or record["compressedTermFallback"] is not expected_compressed
        ):
            raise ValueError(f"Checkpoint schedule mismatch: {checkpoint_id}")
        if expected_compressed:
            compressed_fallbacks += 1
            if "fewer than 12 scheduled instructional weeks" not in record[
                "scheduleExplanation"
            ]:
                raise ValueError(f"Compressed checkpoint is not explained: {checkpoint_id}")

        actor_route = record["actorSourceRoute"]
        validate_relative_file(
            founder_root, actor_route["sourcePath"], f"{checkpoint_id} ACTOR source"
        )
        if (
            f"lesson:{actor_route['lessonId']}" not in route_sets["lesson"]
            or actor_route["readingId"] not in route_sets["reading"]
            or actor_route["processSteps"]
            != ["Aim", "Comprehend and compress", "Test", "Own", "Run"]
        ):
            raise ValueError(f"ACTOR source route mismatch: {checkpoint_id}")

        routing = record["canonicalRouting"]
        route_checks = [
            ("lesson", routing["lessonId"]),
            ("assessment", routing["assessmentId"]),
            ("rubric", routing["rubricId"]),
            ("portfolio", routing["portfolioId"]),
            ("correction", routing["correctionReteachId"]),
            ("progress", routing["progressStateId"]),
        ]
        for route_type, route_id in route_checks:
            if route_id not in route_sets[route_type]:
                raise ValueError(
                    f"Missing canonical {route_type} route {route_id}: {checkpoint_id}"
                )
        mastery_event_ids = routing["masteryEventIds"]
        if (
            not isinstance(mastery_event_ids, list)
            or len(mastery_event_ids) != 5
            or any(item not in route_sets["mastery"] for item in mastery_event_ids)
        ):
            raise ValueError(f"Mastery-event routing mismatch: {checkpoint_id}")

        artifacts = record["portfolioArtifactSlots"]
        if (
            not isinstance(artifacts, list)
            or len(artifacts) != 6
            or {item["artifactType"] for item in artifacts} != ARTIFACT_TYPES
        ):
            raise ValueError(f"Portfolio artifact family mismatch: {checkpoint_id}")
        for artifact in artifacts:
            artifact_routes += 1
            artifact_slot_ids.add(artifact["artifactSlotId"])
            if artifact["artifactType"] in REQUESTED_ARTIFACT_TYPES:
                requested_artifact_routes += 1
                requested_artifact_slot_ids.add(artifact["artifactSlotId"])
            if (
                artifact["canonicalPortfolioId"] != routing["portfolioId"]
                or artifact["evidenceStatus"] != "awaiting-real-learner-work"
                or artifact["containsRealLearnerWork"] is not False
                or not artifact["requiredParts"]
            ):
                raise ValueError(f"Portfolio artifact state mismatch: {checkpoint_id}")

        retention = record["delayedRetentionChecks"]
        if (
            not isinstance(retention, list)
            or len(retention) != 4
            or {item["interval"]: item["delayDays"] for item in retention}
            != RETENTION_INTERVALS
        ):
            raise ValueError(f"Delayed retention schedule mismatch: {checkpoint_id}")
        for check in retention:
            retention_checks += 1
            retention_id = check["retentionCheckId"]
            if retention_id in retention_ids:
                raise ValueError(f"Duplicate delayed retention ID: {retention_id}")
            retention_ids.add(retention_id)
            if (
                check["status"] != "scheduled-not-yet-attempted"
                or check["actualScore"] is not None
                or check["passed"] is not None
                or check["evidenceEarned"] is not False
            ):
                raise ValueError(f"Unearned retention state mismatch: {retention_id}")

        rubric = record["methodChoiceRubric"]
        rubric_count += 1
        if (
            rubric["passingLevel"] != "independent"
            or rubric["advancedLevel"] != "transfer"
            or rubric["actualLearnerScore"] is not None
            or rubric["actualLearnerLevel"] is not None
            or rubric["scoreStatus"] != "unearned-awaiting-real-evidence"
        ):
            raise ValueError(f"Method-choice rubric state mismatch: {checkpoint_id}")
        if {item["score"]: item["level"] for item in rubric["levels"]} != RUBRIC_LEVELS:
            raise ValueError(f"Method-choice rubric level mismatch: {checkpoint_id}")
        calibration = rubric["calibrationSamples"]
        if (
            len(calibration) != 4
            or {item["score"]: item["level"] for item in calibration}
            != RUBRIC_LEVELS
        ):
            raise ValueError(f"Rubric calibration mismatch: {checkpoint_id}")
        for sample in calibration:
            calibration_scores += 1
            calibration_id = sample["calibrationId"]
            if calibration_id in calibration_ids:
                raise ValueError(f"Duplicate calibration ID: {calibration_id}")
            calibration_ids.add(calibration_id)
            if sample["synthetic"] is not True or sample["learnerResult"] is not False:
                raise ValueError(f"Calibration boundary mismatch: {calibration_id}")

        state = record["initialEvidenceState"]
        actual_artifacts += state["actualLearnerArtifactCount"]
        actual_scores += state["actualLearnerScoreCount"]
        completed_retention += state["completedRetentionCheckCount"]
        mastery_earned += int(state["masteryStatus"] != "unearned")
        catalog_preview_used += int(state["catalogPreviewUsed"])
        proposal_only_used += int(state["proposalOnlyUsed"])
        if (
            state["syntheticTemplate"] is not True
            or state["containsRealLearnerData"] is not False
            or state["checkpointStatus"] != "not-started"
        ):
            raise ValueError(f"Initial checkpoint evidence state mismatch: {checkpoint_id}")
        formation = record["accessPrivacyAndFormation"]
        if (
            formation["sameMasteryTargetAcrossAccommodations"] is not True
            or formation["firstAttemptBeforeAiHelp"] is not True
            or formation["christianRoute"] != "encouraged-optional"
            or formation["nonDevotionalAcademicRoute"] != "available-equivalent"
            or formation["familyCommunityPractice"] != "available-optional"
            or formation["compelledProfessionOfFaith"] is not False
            or formation["compelledPoliticalConfession"] is not False
            or formation["compelledFamilyDisclosure"] is not False
        ):
            raise ValueError(f"Access/privacy/formation mismatch: {checkpoint_id}")

    for grade_code in GRADE_CODES:
        if grade_code not in bootcamp_by_grade:
            raise ValueError(f"Missing annual bootcamp: {grade_code}")
        for term in (1, 2, 3, 4):
            for nominal_week in NOMINAL_WEEKS:
                if (grade_code, term, nominal_week) not in checkpoint_by_key:
                    raise ValueError(
                        f"Missing checkpoint: {grade_code} term {term} week {nominal_week}"
                    )

    actual_counts = {
        "gradeCount": len(bootcamp_by_grade),
        "annualBootcampCount": len(bootcamp_ids),
        "annualBootcampDayRouteCount": bootcamp_day_routes,
        "termCheckpointCount": len(checkpoint_ids),
        "compressedTermCheckpointFallbackCount": compressed_fallbacks,
        "uniquePortfolioArtifactSlotCount": len(artifact_slot_ids),
        "checkpointToArtifactRouteCount": artifact_routes,
        "requestedArtifactFamilySlotCount": len(requested_artifact_slot_ids),
        "requestedArtifactFamilyRouteCount": requested_artifact_routes,
        "delayedRetentionCheckCount": retention_checks,
        "methodChoiceRubricCount": rubric_count,
        "scoredSyntheticCalibrationSampleCount": calibration_scores,
        "actualLearnerArtifactCount": actual_artifacts,
        "actualLearnerScoreCount": actual_scores,
        "completedRetentionCheckCount": completed_retention,
        "masteryEarnedCount": mastery_earned,
        "catalogPreviewUsedCount": catalog_preview_used,
        "proposalOnlyUsedCount": proposal_only_used,
    }
    if actual_counts != contract:
        raise ValueError(
            f"Learning-process aggregate contract mismatch: {actual_counts!r}"
        )
    summary_checks = {
        "gradeCount": actual_counts["gradeCount"],
        "annualBootcampCount": actual_counts["annualBootcampCount"],
        "annualBootcampDayRouteCount": actual_counts["annualBootcampDayRouteCount"],
        "termCheckpointCount": actual_counts["termCheckpointCount"],
        "compressedTermCheckpointFallbackCount": actual_counts[
            "compressedTermCheckpointFallbackCount"
        ],
        "totalPortfolioArtifactSlotCount": actual_counts[
            "uniquePortfolioArtifactSlotCount"
        ],
        "checkpointToArtifactRouteCount": actual_counts[
            "checkpointToArtifactRouteCount"
        ],
        "requestedArtifactFamilySlotCount": actual_counts[
            "requestedArtifactFamilySlotCount"
        ],
        "requestedArtifactFamilyRouteCount": actual_counts[
            "requestedArtifactFamilyRouteCount"
        ],
        "delayedRetentionCheckCount": actual_counts["delayedRetentionCheckCount"],
        "methodChoiceRubricCount": actual_counts["methodChoiceRubricCount"],
        "scoredSyntheticCalibrationSampleCount": actual_counts[
            "scoredSyntheticCalibrationSampleCount"
        ],
        "actualLearnerArtifactCount": actual_artifacts,
        "actualLearnerScoreCount": actual_scores,
        "completedRetentionCheckCount": completed_retention,
        "masteryEarnedCount": mastery_earned,
    }
    for key, value in summary_checks.items():
        if summary.get(key) != value:
            raise ValueError(f"Learning-process summary mismatch for {key}")

    temp_root = (
        Path(args.temp_root).resolve()
        if args.temp_root
        else suite_root / ".codex-cache" / "tmp"
    )
    temp_root.mkdir(parents=True, exist_ok=True)
    grade_samples: list[dict[str, Any]] = []
    rendered_count = 0
    with tempfile.TemporaryDirectory(
        prefix="founder-learning-process-", dir=temp_root
    ) as temp_dir:
        sample_root = Path(temp_dir)
        for grade_code in GRADE_CODES:
            bootcamp = bootcamp_by_grade[grade_code]
            checkpoint = checkpoint_by_key[(grade_code, 1, 4)]
            rendered = {
                "schemaVersion": 1,
                "gradeCode": grade_code,
                "annualBootcamp": {
                    "bootcampId": bootcamp["bootcampId"],
                    "dayRoutes": bootcamp["dayRoutes"],
                },
                "checkpoint": {
                    "checkpointId": checkpoint["checkpointId"],
                    "anchorLessonId": checkpoint["anchorLessonId"],
                    "actorSourceRoute": checkpoint["actorSourceRoute"],
                    "portfolioArtifactSlots": checkpoint["portfolioArtifactSlots"],
                    "delayedRetentionChecks": checkpoint["delayedRetentionChecks"],
                    "methodChoiceRubric": checkpoint["methodChoiceRubric"],
                    "initialEvidenceState": checkpoint["initialEvidenceState"],
                },
            }
            sample_path = sample_root / f"{grade_code}-learning-process.json"
            sample_path.write_text(
                json.dumps(rendered, indent=2, ensure_ascii=False) + "\n",
                encoding="utf-8",
            )
            imported = load_json(sample_path)
            if imported != rendered:
                raise ValueError(f"Learning-process sample round trip failed: {grade_code}")
            rendered_count += 1
            grade_samples.append(
                {
                    "gradeCode": grade_code,
                    "bootcampId": bootcamp["bootcampId"],
                    "checkpointId": checkpoint["checkpointId"],
                    "anchorLessonId": checkpoint["anchorLessonId"],
                }
            )

    evidence = {
        "schemaVersion": 1,
        "status": "passed",
        "sourceId": "founder-level-civic-classical",
        "exportVersion": "2026-07-23-v1",
        "counts": {
            "grades": len(bootcamp_by_grade),
            "annualBootcamps": len(bootcamp_ids),
            "annualBootcampDayRoutes": bootcamp_day_routes,
            "termCheckpoints": len(checkpoint_ids),
            "compressedTermCheckpointFallbacks": compressed_fallbacks,
            "uniquePortfolioArtifactSlots": len(artifact_slot_ids),
            "checkpointToArtifactRoutes": artifact_routes,
            "requestedArtifactFamilySlots": len(requested_artifact_slot_ids),
            "requestedArtifactFamilyRoutes": requested_artifact_routes,
            "delayedRetentionChecks": retention_checks,
            "methodChoiceRubrics": rubric_count,
            "scoredSyntheticCalibrationSamples": calibration_scores,
        },
        "validation": {
            "canonicalRoutesResolved": True,
            "checkpointHashPassCount": checkpoint_hash_passes,
            "bootcampHashPassCount": bootcamp_hash_passes,
            "renderedGradeSampleCount": rendered_count,
            "fileRoundTripSampleCount": rendered_count,
            "actualLearnerArtifactCount": actual_artifacts,
            "actualLearnerScoreCount": actual_scores,
            "completedRetentionCheckCount": completed_retention,
            "masteryEarnedCount": mastery_earned,
            "catalogPreviewUsedCount": catalog_preview_used,
            "proposalOnlyUsedCount": proposal_only_used,
        },
        "gradeSamples": grade_samples,
    }
    expected = load_json(
        suite_root / "fixtures" / "founder-learning-process-export.expected.json"
    )
    assert_subset(evidence, expected)
    evidence_text = json.dumps(evidence, indent=2, ensure_ascii=False) + "\n"
    if args.evidence_output:
        output_path = Path(args.evidence_output).resolve()
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(evidence_text, encoding="utf-8")
    print(evidence_text, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

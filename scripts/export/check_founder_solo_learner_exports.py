"""Validate Founder all-grade solo learner UI and portable state exports."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import re
import tempfile
from collections import defaultdict
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


def compact_sha256(value: Any) -> str:
    payload = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def walk_keys(value: Any) -> Iterable[str]:
    if isinstance(value, dict):
        for key, child in value.items():
            yield str(key)
            yield from walk_keys(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk_keys(child)


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


def load_record_map(path: Path) -> dict[str, dict[str, Any]]:
    records: dict[str, dict[str, Any]] = {}
    for record in iter_jsonl(path):
        record_id = str(record.get("id", ""))
        if not record_id or record_id in records:
            raise ValueError(f"Missing or duplicate object ID in {path}: {record_id}")
        records[record_id] = record
    return records


def validate_relative_file(founder_root: Path, relative_path: str, context: str) -> None:
    if not relative_path or ABSOLUTE_PATH_PATTERN.search(relative_path):
        raise ValueError(f"Path must be relative for {context}: {relative_path}")
    resolved = (founder_root / relative_path).resolve()
    try:
        resolved.relative_to(founder_root)
    except ValueError as exc:
        raise ValueError(f"Path escapes founder root for {context}: {relative_path}") from exc
    if not resolved.is_file():
        raise ValueError(f"Referenced file does not exist for {context}: {relative_path}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate all Founder solo learner UI and portable state exports"
    )
    parser.add_argument("--suite-root", default=".")
    parser.add_argument("--founder-root", required=True)
    parser.add_argument("--temp-root", default="")
    parser.add_argument("--evidence-output", default="")
    args = parser.parse_args()

    suite_root = Path(args.suite_root).resolve()
    founder_root = Path(args.founder_root).resolve()
    solo_root = founder_root / "exports" / "solo-learner-v1"
    schema = load_json(suite_root / "schemas" / "founder-solo-learner-export.schema.json")
    contract = schema["x-soloLearnerContract"]
    expected_counts = contract["expectedCounts"]
    summary = load_json(solo_root / "solo-learner-export-summary.json")
    expected_summary = {
        "sessionCount": expected_counts["sessions"],
        "gradeCount": expected_counts["grades"],
        "sessionsPerGrade": expected_counts["sessionsPerGrade"],
        "checklistEntryCount": expected_counts["checklistEntries"],
        "previousNavigationEdgeCount": expected_counts["previousEdges"],
        "nextNavigationEdgeCount": expected_counts["nextEdges"],
        "readingAndSourceRightsRouteCount": expected_counts["readingRoutes"],
        "packetEmbeddedOrSynthesisSourceRouteCount": expected_counts[
            "packetFallbackRoutes"
        ],
        "facilitatorRequiredCount": expected_counts["facilitatorRequired"],
        "facilitatorRecommendedCount": expected_counts["facilitatorRecommended"],
        "facilitatorAvailableIfNeededCount": expected_counts[
            "facilitatorAvailableIfNeeded"
        ],
        "originalActivityFacilitatorRequiredCount": expected_counts[
            "originalActivityFacilitatorRequired"
        ],
        "autonomousSafeEquivalentCount": expected_counts[
            "autonomousSafeEquivalents"
        ],
        "cannotCompleteWithoutFacilitatorCount": expected_counts[
            "cannotCompleteWithoutFacilitator"
        ],
        "learnerSelfCheckRouteCount": expected_counts["learnerSelfCheckRoutes"],
        "externalGraderRequiredForOrdinaryMasteryCount": expected_counts[
            "externalGraderRequiredForOrdinaryMastery"
        ],
        "unresolvedLearningCaptureCount": expected_counts[
            "unresolvedLearningRoutes"
        ],
        "studyLeadRequiredForOrdinaryUse": False,
        "authorizedResearchSiteRequiredForOrdinaryUse": False,
        "particularExternalSiteRequired": False,
        "conditionalEscalationFlagCount": expected_counts[
            "conditionalEscalationFlags"
        ],
        "restrictedAnswerPayloadIncludedCount": 0,
        "realLearnerStateCount": 0,
        "catalogPreviewUsedCount": 0,
        "proposalOnlyUsedCount": 0,
    }
    for key, value in expected_summary.items():
        if summary.get(key) != value:
            raise ValueError(f"Solo learner summary mismatch for {key}")
    if (
        summary.get("status")
        != "all-grade-all-lesson-autonomous-solo-learning-and-portable-state-export-passed"
    ):
        raise ValueError("Solo learner summary status mismatch")

    public_root = founder_root / "exports" / "suite-v1" / "public"
    object_types = (
        "lesson",
        "reading",
        "source-rights",
        "delivery-package",
        "assessment",
        "rubric",
        "correction-reteach",
        "portfolio-artifact",
        "progress-state",
        "mastery-event",
    )
    objects = {
        object_type: load_record_map(public_root / f"{object_type}.jsonl")
        for object_type in object_types
    }
    restricted_ids = {
        str(record["id"])
        for record in iter_jsonl(
            founder_root
            / "exports"
            / "suite-v1"
            / "restricted"
            / "restricted-answer-keys.jsonl"
        )
    }

    required_record_fields = set(schema["required"])
    required_sections = contract["requiredUiSections"]
    required_checklist_steps = contract["requiredChecklistSteps"]
    grade_codes = contract["gradeCodes"]
    forbidden_keys = set(contract["forbiddenLearnerKeys"])
    records_by_grade: dict[str, list[dict[str, Any]]] = defaultdict(list)
    session_ids: set[str] = set()
    lesson_ids: set[str] = set()
    source_rights_resolved = True
    reading_routes = 0
    packet_fallback_routes = 0
    previous_edges = 0
    next_edges = 0
    restricted_payload_leaks = 0
    progress_hash_passes = 0
    session_hash_passes = 0
    in_memory_round_trips = 0
    facilitator_counts = {
        "required": 0,
        "recommended": 0,
        "available-if-needed": 0,
    }
    conditional_escalation_flags = 0
    autonomous_safe_equivalents = 0
    cannot_complete_without_facilitator = 0
    learner_self_check_routes = 0
    external_grader_required = 0
    unresolved_learning_routes = 0
    catalog_preview_used = 0
    proposal_only_used = 0
    real_learner_states = 0

    records_path = solo_root / "solo-learner-sessions.jsonl"
    for record in iter_jsonl(records_path):
        missing = required_record_fields - record.keys()
        if missing:
            raise ValueError(f"Solo session misses fields {sorted(missing)}")
        if (
            record["schemaVersion"] != 1
            or record["exportVersion"] != "2026-07-24-v2"
            or record["sourceId"] != "founder-level-civic-classical"
            or record["status"]
            != "synthetic-autonomous-solo-route-and-initial-state-export-passed"
        ):
            raise ValueError(f"Solo session identity mismatch: {record['sessionId']}")
        session_id = str(record["sessionId"])
        lesson_id = str(record["lessonId"])
        if session_id in session_ids or lesson_id in lesson_ids:
            raise ValueError(f"Duplicate solo session or lesson: {session_id}")
        session_ids.add(session_id)
        lesson_ids.add(lesson_id)
        grade_code = str(record["gradeCode"])
        if grade_code not in grade_codes:
            raise ValueError(f"Unknown grade code: {grade_code}")
        records_by_grade[grade_code].append(record)

        supplied_session_sha = str(record["sessionSha256"])
        unhashed_record = copy.deepcopy(record)
        unhashed_record.pop("sessionSha256")
        if compact_sha256(unhashed_record) != supplied_session_sha:
            raise ValueError(f"Solo session checksum mismatch: {session_id}")
        session_hash_passes += 1

        leaked_keys = forbidden_keys.intersection(walk_keys(record))
        if leaked_keys:
            restricted_payload_leaks += 1
            raise ValueError(
                f"Solo learner record leaks restricted keys {sorted(leaked_keys)}: {session_id}"
            )

        lesson_object_id = f"lesson:{lesson_id}"
        lesson = objects["lesson"].get(lesson_object_id)
        if not lesson:
            raise ValueError(f"Solo session lesson does not resolve: {session_id}")
        lesson_data = lesson["data"]
        for field in ("gradeCode", "courseId", "moduleId", "calendarWeek", "term", "day"):
            if record[field] != lesson_data[field]:
                raise ValueError(f"Solo session lesson field mismatch {field}: {session_id}")
        if record["objective"] != lesson_data["objective"]:
            raise ValueError(f"Solo objective mismatch: {session_id}")

        navigation = record["navigation"]
        if (
            navigation["uiSectionOrder"] != required_sections
            or navigation["totalLessonsInGrade"] != expected_counts["sessionsPerGrade"]
            or navigation["keyboardPreviousNextAvailable"] is not True
            or navigation["backToGradeAvailable"] is not True
        ):
            raise ValueError(f"Solo UI navigation contract mismatch: {session_id}")
        if navigation["previousLessonId"]:
            previous_edges += 1
        if navigation["nextLessonId"]:
            next_edges += 1

        learner_view = record["learnerView"]
        delivery = objects["delivery-package"].get(learner_view["deliveryPackageId"])
        if (
            not delivery
            or learner_view["deliveryPackageId"] != lesson_data["deliveryPackageId"]
            or delivery["data"]["lessonId"] != lesson_id
        ):
            raise ValueError(f"Solo delivery route mismatch: {session_id}")
        validate_relative_file(
            founder_root, learner_view["deliverySourcePath"], f"{session_id} delivery"
        )
        if set(learner_view["accessRoutes"]) != {
            "oral",
            "visual",
            "movement",
            "writingSupport",
            "multilingual",
            "overload",
            "acceleration",
        }:
            raise ValueError(f"Solo access-route set mismatch: {session_id}")

        source_links = record["sourceLinks"]
        validate_relative_file(
            founder_root, source_links["learnerMaterialPath"], f"{session_id} source"
        )
        if lesson_data.get("readingId"):
            reading_routes += 1
            reading = objects["reading"].get(source_links["readingId"])
            if (
                not reading
                or source_links["readingId"] != lesson_data["readingId"]
                or source_links["sourceStatus"]
                != "exact-reading-and-source-rights-routed"
                or source_links["learnerMaterialPath"]
                != reading["data"]["learnerMaterial"]["path"]
                or source_links["learnerMaterialAnchor"]
                != reading["data"]["learnerMaterial"]["anchor"]
                or source_links["sourceRightsIds"]
                != reading["data"]["sourceRightsIds"]
            ):
                raise ValueError(f"Solo reading route mismatch: {session_id}")
            for source_rights_id in source_links["sourceRightsIds"]:
                if source_rights_id not in objects["source-rights"]:
                    source_rights_resolved = False
                    raise ValueError(
                        f"Solo source-rights route does not resolve: {session_id}"
                    )
        else:
            packet_fallback_routes += 1
            if (
                source_links["readingId"] is not None
                or source_links["sourceStatus"]
                != "packet-embedded-or-synthesis-no-separate-reading"
                or source_links["sourceRightsIds"] != []
            ):
                raise ValueError(f"Solo packet-fallback route mismatch: {session_id}")
        if source_links["externalCopyPermissionInferred"] is not False:
            raise ValueError(f"Solo source route infers copying permission: {session_id}")

        routing = record["routing"]
        assessment = objects["assessment"].get(
            routing["assessment"]["publicAssessmentId"]
        )
        rubric = objects["rubric"].get(routing["rubric"]["publicRubricId"])
        correction = objects["correction-reteach"].get(
            routing["correctionLog"]["correctionReteachId"]
        )
        portfolio = objects["portfolio-artifact"].get(
            routing["portfolio"]["portfolioArtifactId"]
        )
        progress = objects["progress-state"].get(
            routing["progress"]["progressStateId"]
        )
        if (
            not assessment
            or not rubric
            or not correction
            or not portfolio
            or not progress
            or routing["assessment"]["publicAssessmentId"]
            != lesson_data["assessmentId"]
            or routing["rubric"]["publicRubricId"] != lesson_data["rubricId"]
            or routing["correctionLog"]["correctionReteachId"]
            != lesson_data["correctionReteachId"]
            or routing["portfolio"]["portfolioArtifactId"]
            != lesson_data["portfolioArtifactId"]
            or routing["progress"]["progressStateId"]
            != lesson_data["progressStateId"]
        ):
            raise ValueError(f"Solo assessment/evidence route mismatch: {session_id}")

        restricted_route = routing["restrictedAnswerRoute"]
        if (
            restricted_route["restrictedAnswerKeyId"]
            != assessment["data"]["restrictedAnswerKeyId"]
            or restricted_route["restrictedAnswerKeyId"] not in restricted_ids
            or restricted_route["visibility"]
            != contract["requiredRestrictedVisibility"]
            or restricted_route["learnerPayloadIncluded"] is not False
            or restricted_route["authorizedRoutingAvailable"] is not True
            or restricted_route["learnerMayRevealAfterAttempt"] is not True
            or restricted_route["revealRequiresPreservedAttempt"] is not True
            or restricted_route["localRestrictedSidecarRequired"] is not True
            or restricted_route["externalGraderRequiredForOrdinaryMastery"]
            is not False
            or restricted_route[
                "independentScorerRequiredForFormalStudyOrCredentialClaim"
            ]
            is not True
        ):
            raise ValueError(f"Solo restricted-answer route mismatch: {session_id}")
        learner_self_check_routes += 1
        if restricted_route["externalGraderRequiredForOrdinaryMastery"]:
            external_grader_required += 1
        if (
            routing["rubric"]["learnerCriteriaVisible"] is not True
            or routing["rubric"]["learnerSelfScoringAvailable"] is not True
            or routing["rubric"]["authorizedScoringStillRequired"] is not False
            or routing["correctionLog"]["initialEntries"] != []
            or routing["correctionLog"]["firstAttemptMustBePreserved"] is not True
            or routing["portfolio"]["visibility"]
            != "private-by-default-until-reviewed"
            or routing["portfolio"]["exportRequiresLearnerOrGuardianReview"]
            is not True
        ):
            raise ValueError(f"Solo evidence/privacy route mismatch: {session_id}")
        unresolved = routing["unresolvedLearning"]
        if (
            unresolved["schemaPath"]
            != "resources/unresolved-learning-record.schema.json"
            or unresolved["initialEntries"] != []
            or unresolved["localOnlyByDefault"] is not True
            or unresolved["learnerApprovedMinimizedAiReviewAvailable"] is not True
            or unresolved["aiMayChangeMastery"] is not False
            or unresolved["aiMayPublishPrivateWork"] is not False
            or unresolved["aiProposalRequiresReview"] is not True
        ):
            raise ValueError(f"Solo unresolved-learning route mismatch: {session_id}")
        unresolved_learning_routes += 1
        if (
            routing["progress"]["masteryEventIds"]
            != lesson_data["masteryEventIds"]
            or routing["progress"]["initialMasteryStatus"]
            != contract["requiredInitialMasteryStatus"]
        ):
            raise ValueError(f"Solo progress-event route mismatch: {session_id}")
        for mastery_event_id in routing["progress"]["masteryEventIds"]:
            event = objects["mastery-event"].get(mastery_event_id)
            if (
                not event
                or event["data"]["evidenceImpact"] != "evidence-bearing"
                or event["data"]["proposalOnly"] is not False
            ):
                raise ValueError(f"Solo mastery event mismatch: {session_id}")
        if routing["progress"]["catalogPreviewUsed"]:
            catalog_preview_used += 1
        if routing["progress"]["proposalOnlyUsed"]:
            proposal_only_used += 1

        export = record["progressChecklistExport"]
        state = export["state"]
        if (
            export["format"] != "founder-solo-progress-checklist-v1"
            or export["persistenceStatus"] != "synthetic-initial-state-serialized"
            or export["exportStatus"] != "portable-json-ready"
            or state["sessionId"] != session_id
            or state["lessonId"] != lesson_id
            or state["containsRealLearnerData"] is not False
            or state["localOnly"] is not True
            or state["exportImportReady"] is not True
            or state["checklistStatus"]
            != {"completedCount": 0, "totalCount": 10, "status": "not-started"}
            or [step["stepId"] for step in state["checklist"]]
            != required_checklist_steps
            or any(step["status"] != "pending" for step in state["checklist"])
            or state["progressState"]["masteryStatus"]
            != contract["requiredInitialMasteryStatus"]
            or state["progressState"]["attemptEvents"] != []
            or state["correctionLog"] != []
        ):
            raise ValueError(f"Solo progress/checklist state mismatch: {session_id}")
        if compact_sha256(state) != export["sha256"]:
            raise ValueError(f"Solo progress-state checksum mismatch: {session_id}")
        progress_hash_passes += 1
        if json.loads(json.dumps(state, ensure_ascii=False)) != state:
            raise ValueError(f"Solo in-memory export/import mismatch: {session_id}")
        in_memory_round_trips += 1
        if state["containsRealLearnerData"]:
            real_learner_states += 1

        handoff = record["soloHandoff"]
        facilitator_status = handoff["guardianOrFacilitatorForOriginalActivity"]
        if facilitator_status not in facilitator_counts:
            raise ValueError(f"Unknown solo facilitator status: {session_id}")
        facilitator_counts[facilitator_status] += 1
        if (
            handoff["status"] != "complete"
            or len(handoff["escalationTriggers"]) != 5
            or handoff["conditionalStopAndEscalate"] is not True
            or handoff["noForcedReligiousOrPoliticalAgreement"] is not True
        ):
            raise ValueError(f"Solo handoff/escalation mismatch: {session_id}")
        conditional_escalation_flags += len(handoff["escalationTriggers"])
        expected_required = facilitator_status == "required"
        expected_recommended = facilitator_status == "recommended"
        expected_available = facilitator_status == "available-if-needed"
        if (
            handoff["canCompleteWithoutFacilitator"] is not True
            or handoff["requiresFacilitatorBeforeStart"] is not False
            or handoff["requiresFacilitatorForOriginalActivity"] is not expected_required
            or handoff["facilitatorRecommended"] is not expected_recommended
            or handoff["facilitatorAvailableIfNeeded"] is not expected_available
            or handoff["cannotCompleteAloneReason"] is not None
            or (expected_required and not handoff["originalActivityGateReason"])
            or (
                not expected_required
                and handoff["originalActivityGateReason"] is not None
            )
            or handoff["autonomousSafeEquivalentRequired"] is not True
            or not handoff["safeEquivalentRoute"]
            or handoff["studyLeadRequiredForOrdinaryUse"] is not False
            or handoff["authorizedResearchSiteRequiredForOrdinaryUse"] is not False
            or handoff["particularExternalSiteRequired"] is not False
        ):
            raise ValueError(f"Solo facilitator flag mismatch: {session_id}")
        autonomous_safe_equivalents += 1
        if not handoff["canCompleteWithoutFacilitator"]:
            cannot_complete_without_facilitator += 1

        boundary = record["privacyAndFormationBoundary"]
        if (
            boundary["syntheticLearnerIdOnly"] is not True
            or boundary["containsRealLearnerData"] is not False
            or boundary["localOnlyByDefault"] is not True
            or boundary["privatePortfolioDefault"] is not True
            or boundary["christianRoute"] != "encouraged-optional"
            or boundary["nonDevotionalAcademicRoute"] != "available-equivalent"
            or boundary["familyCommunityPractice"] != "available-optional"
            or boundary["compelledProfessionOfFaith"] is not False
            or boundary["compelledPoliticalConfession"] is not False
            or boundary["identicalSafetyAndMasteryRules"] is not True
        ):
            raise ValueError(f"Solo privacy/formation boundary mismatch: {session_id}")

    if len(session_ids) != expected_counts["sessions"]:
        raise ValueError("Solo session aggregate count mismatch")
    if set(records_by_grade) != set(grade_codes):
        raise ValueError("Solo grade set mismatch")

    for grade_code in grade_codes:
        grade_records = sorted(
            records_by_grade[grade_code],
            key=lambda record: record["navigation"]["positionInGrade"],
        )
        if len(grade_records) != expected_counts["sessionsPerGrade"]:
            raise ValueError(f"Solo grade session count mismatch: {grade_code}")
        for index, record in enumerate(grade_records):
            navigation = record["navigation"]
            expected_previous = (
                grade_records[index - 1]["lessonId"] if index > 0 else None
            )
            expected_next = (
                grade_records[index + 1]["lessonId"]
                if index < len(grade_records) - 1
                else None
            )
            if (
                navigation["positionInGrade"] != index + 1
                or navigation["previousLessonId"] != expected_previous
                or navigation["nextLessonId"] != expected_next
            ):
                raise ValueError(
                    f"Solo previous/next graph mismatch: {record['sessionId']}"
                )

    if (
        previous_edges != expected_counts["previousEdges"]
        or next_edges != expected_counts["nextEdges"]
        or reading_routes != expected_counts["readingRoutes"]
        or packet_fallback_routes != expected_counts["packetFallbackRoutes"]
        or facilitator_counts["required"] != expected_counts["facilitatorRequired"]
        or facilitator_counts["recommended"]
        != expected_counts["facilitatorRecommended"]
        or facilitator_counts["available-if-needed"]
        != expected_counts["facilitatorAvailableIfNeeded"]
        or facilitator_counts["required"]
        != expected_counts["originalActivityFacilitatorRequired"]
        or autonomous_safe_equivalents
        != expected_counts["autonomousSafeEquivalents"]
        or cannot_complete_without_facilitator
        != expected_counts["cannotCompleteWithoutFacilitator"]
        or learner_self_check_routes != expected_counts["learnerSelfCheckRoutes"]
        or external_grader_required
        != expected_counts["externalGraderRequiredForOrdinaryMastery"]
        or unresolved_learning_routes != expected_counts["unresolvedLearningRoutes"]
        or conditional_escalation_flags
        != expected_counts["conditionalEscalationFlags"]
    ):
        raise ValueError("Solo aggregate navigation/source/escalation mismatch")

    grade_samples: list[dict[str, Any]] = []
    rendered_samples: list[dict[str, Any]] = []
    temp_root = (
        Path(args.temp_root).resolve()
        if args.temp_root
        else suite_root / ".codex-cache" / "tmp"
    )
    temp_root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="founder-solo-ui-", dir=temp_root) as temp_dir:
        sample_root = Path(temp_dir)
        for grade_code in grade_codes:
            record = min(
                records_by_grade[grade_code],
                key=lambda item: item["navigation"]["positionInGrade"],
            )
            rendered = {
                "schemaVersion": 1,
                "sessionId": record["sessionId"],
                "lessonId": record["lessonId"],
                "gradeCode": record["gradeCode"],
                "title": record["title"],
                "objective": record["objective"],
                "navigation": record["navigation"],
                "sourceLinks": record["sourceLinks"],
                "assessmentId": record["routing"]["assessment"]["publicAssessmentId"],
                "restrictedAnswerRoute": record["routing"]["restrictedAnswerRoute"],
                "rubricId": record["routing"]["rubric"]["publicRubricId"],
                "correctionLog": record["routing"]["correctionLog"],
                "portfolio": record["routing"]["portfolio"],
                "progress": record["progressChecklistExport"],
                "soloHandoff": record["soloHandoff"],
            }
            leaked = forbidden_keys.intersection(walk_keys(rendered))
            if leaked:
                raise ValueError(
                    f"Rendered solo sample leaks restricted fields: {sorted(leaked)}"
                )
            sample_path = sample_root / f"{grade_code}-session.json"
            sample_path.write_text(
                json.dumps(rendered, indent=2, ensure_ascii=False) + "\n",
                encoding="utf-8",
            )
            imported = load_json(sample_path)
            if imported != rendered:
                raise ValueError(f"Solo file round trip failed: {grade_code}")
            rendered_samples.append(rendered)
            grade_samples.append(
                {
                    "gradeCode": grade_code,
                    "lessonId": record["lessonId"],
                    "positionInGrade": record["navigation"]["positionInGrade"],
                    "guardianOrFacilitatorForOriginalActivity": record["soloHandoff"][
                        "guardianOrFacilitatorForOriginalActivity"
                    ],
                    "canCompleteWithoutFacilitator": record["soloHandoff"][
                        "canCompleteWithoutFacilitator"
                    ],
                }
            )

    evidence = {
        "schemaVersion": 1,
        "status": "passed",
        "sourceId": "founder-level-civic-classical",
        "exportVersion": "2026-07-24-v2",
        "counts": {
            "sessions": len(session_ids),
            "grades": len(records_by_grade),
            "sessionsPerGrade": expected_counts["sessionsPerGrade"],
            "uiSectionsPerSession": len(required_sections),
            "checklistStepsPerSession": len(required_checklist_steps),
            "checklistEntries": len(session_ids) * len(required_checklist_steps),
            "previousEdges": previous_edges,
            "nextEdges": next_edges,
            "readingRoutes": reading_routes,
            "packetFallbackRoutes": packet_fallback_routes,
            "publicAssessmentRoutes": len(session_ids),
            "restrictedAnswerRoutes": len(session_ids),
            "publicRubricRoutes": len(session_ids),
            "correctionLogRoutes": len(session_ids),
            "portfolioRoutes": len(session_ids),
            "progressRoutes": len(session_ids),
            "portableStateExports": len(session_ids),
            "facilitatorRequired": facilitator_counts["required"],
            "facilitatorRecommended": facilitator_counts["recommended"],
            "facilitatorAvailableIfNeeded": facilitator_counts[
                "available-if-needed"
            ],
            "originalActivityFacilitatorRequired": facilitator_counts["required"],
            "autonomousSafeEquivalents": autonomous_safe_equivalents,
            "cannotCompleteWithoutFacilitator": cannot_complete_without_facilitator,
            "learnerSelfCheckRoutes": learner_self_check_routes,
            "externalGraderRequiredForOrdinaryMastery": external_grader_required,
            "unresolvedLearningRoutes": unresolved_learning_routes,
            "conditionalEscalationFlags": conditional_escalation_flags,
        },
        "validation": {
            "navigationGraphComplete": True,
            "sourceAndRightsRoutesResolved": source_rights_resolved,
            "restrictedPayloadLeakCount": restricted_payload_leaks,
            "progressStateHashPassCount": progress_hash_passes,
            "sessionHashPassCount": session_hash_passes,
            "inMemoryRoundTripPassCount": in_memory_round_trips,
            "renderedGradeSampleCount": len(rendered_samples),
            "fileRoundTripSampleCount": len(rendered_samples),
            "catalogPreviewUsedCount": catalog_preview_used,
            "proposalOnlyUsedCount": proposal_only_used,
            "realLearnerStateCount": real_learner_states,
            "ordinaryUseRequiresStudyLead": False,
            "ordinaryUseRequiresAuthorizedResearchSite": False,
            "particularExternalSiteRequired": False,
        },
        "gradeSamples": grade_samples,
    }
    expected = load_json(
        suite_root / "fixtures" / "founder-solo-learner-export.expected.json"
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

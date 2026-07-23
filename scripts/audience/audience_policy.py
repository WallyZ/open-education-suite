"""Fail-closed audience and sensitivity policy for learner-facing content.

The same evaluator is used by catalog, search, recommendation, export, import,
and tutor-context operations. It uses age/grade bands rather than dates of
birth, never treats guardian approval as permission for adult-only content,
and deliberately ignores learner gender when applying safety or mastery rules.
"""

from __future__ import annotations

import argparse
import json
from copy import deepcopy
from pathlib import Path
from typing import Any, Iterable


OPERATIONS = {
    "catalog",
    "search",
    "recommendation",
    "export",
    "import",
    "tutor-context",
}
REQUIRED_FIELDS = {
    "schemaVersion",
    "policyVersion",
    "metadataId",
    "contentKind",
    "contentId",
    "sourcePath",
    "gradeBand",
    "ageBand",
    "audienceClassification",
    "minorSafe",
    "adultOnly",
    "guardianOrFacilitatorRequirement",
    "sensitiveTopicCategories",
    "prerequisiteIds",
    "permittedTutorContexts",
    "allowedOperations",
    "masteryAndSafetyPolicyId",
    "status",
}
CONTENT_KINDS = {"course", "lesson", "source", "tutor-seed", "assessment", "handoff"}
REQUIREMENTS = {
    "none",
    "guardian-or-facilitator-recommended",
    "guardian-required",
    "facilitator-required",
    "guardian-or-facilitator-required",
    "adult-confirmed-opt-in",
}


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def load_records(path: Path) -> list[dict[str, Any]]:
    if path.suffix.lower() == ".jsonl":
        records: list[dict[str, Any]] = []
        with path.open("r", encoding="utf-8-sig") as stream:
            for line in stream:
                if line.strip():
                    value = json.loads(line)
                    if isinstance(value, dict):
                        records.append(value)
        return records
    value = load_json(path)
    if isinstance(value, list):
        return [record for record in value if isinstance(record, dict)]
    if isinstance(value, dict):
        for key in ("records", "sources", "items"):
            if isinstance(value.get(key), list):
                return [record for record in value[key] if isinstance(record, dict)]
    return []


def metadata_errors(record: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    missing = sorted(REQUIRED_FIELDS - record.keys())
    if missing:
        errors.append("missing-fields:" + ",".join(missing))
    if record.get("schemaVersion") != 1:
        errors.append("invalid-schema-version")
    if record.get("contentKind") not in CONTENT_KINDS:
        errors.append("invalid-content-kind")
    classification = record.get("audienceClassification")
    if classification not in {"minor-safe", "adult-only"}:
        errors.append("invalid-audience-classification")
    if classification == "minor-safe" and (
        record.get("minorSafe") is not True or record.get("adultOnly") is not False
    ):
        errors.append("inconsistent-minor-safe-flags")
    if classification == "adult-only" and (
        record.get("minorSafe") is not False or record.get("adultOnly") is not True
    ):
        errors.append("inconsistent-adult-only-flags")
    if record.get("guardianOrFacilitatorRequirement") not in REQUIREMENTS:
        errors.append("invalid-guardian-facilitator-requirement")
    if classification == "adult-only" and (
        record.get("guardianOrFacilitatorRequirement") != "adult-confirmed-opt-in"
    ):
        errors.append("adult-only-must-require-confirmed-opt-in")
    grade_band = record.get("gradeBand")
    if not isinstance(grade_band, dict) or not {
        "label",
        "minGrade",
        "maxGrade",
    }.issubset(grade_band):
        errors.append("invalid-grade-band")
    age_band = record.get("ageBand")
    if not isinstance(age_band, dict) or not {
        "label",
        "minAge",
        "maxAge",
    }.issubset(age_band):
        errors.append("invalid-age-band")
    else:
        minimum = age_band.get("minAge")
        maximum = age_band.get("maxAge")
        if minimum is not None and (not isinstance(minimum, int) or minimum < 0):
            errors.append("invalid-minimum-age")
        if maximum is not None and (not isinstance(maximum, int) or maximum < 0):
            errors.append("invalid-maximum-age")
        if isinstance(minimum, int) and isinstance(maximum, int) and minimum > maximum:
            errors.append("reversed-age-band")
    for field in (
        "sensitiveTopicCategories",
        "prerequisiteIds",
        "permittedTutorContexts",
        "allowedOperations",
    ):
        value = record.get(field)
        if not isinstance(value, list):
            errors.append(f"invalid-list:{field}")
        elif field != "prerequisiteIds" and not value:
            errors.append(f"empty-list:{field}")
        elif len(value) != len(set(str(item) for item in value)):
            errors.append(f"duplicate-list-values:{field}")
    operations = set(record.get("allowedOperations", []))
    if operations - OPERATIONS:
        errors.append("invalid-allowed-operation")
    if record.get("masteryAndSafetyPolicyId") != "suite-equivalent-safety-and-mastery-v1":
        errors.append("invalid-mastery-safety-policy")
    for field in ("metadataId", "contentId", "sourcePath", "policyVersion", "status"):
        if not str(record.get(field, "")).strip():
            errors.append(f"empty-field:{field}")
    return errors


def _age_band_allows(record: dict[str, Any], context: dict[str, Any]) -> bool:
    if context.get("audienceRole") == "adult":
        return True
    learner_band = context.get("ageBand")
    content_band = record.get("ageBand")
    if not isinstance(learner_band, dict) or not isinstance(content_band, dict):
        return False
    learner_min = learner_band.get("minAge")
    learner_max = learner_band.get("maxAge")
    content_min = content_band.get("minAge")
    content_max = content_band.get("maxAge")
    if not isinstance(learner_min, int) or not isinstance(learner_max, int):
        return False
    if isinstance(content_min, int) and learner_min < content_min:
        return False
    if isinstance(content_max, int) and learner_max > content_max:
        return False
    return True


def _grade_rank(value: Any) -> int | None:
    normalized = str(value).strip().lower()
    if normalized in {"k", "kindergarten"}:
        return 0
    if normalized == "adult":
        return 13
    if normalized.isdigit() and 1 <= int(normalized) <= 12:
        return int(normalized)
    return None


def _grade_band_allows(record: dict[str, Any], context: dict[str, Any]) -> bool:
    if context.get("audienceRole") == "adult":
        return True
    learner_grade = _grade_rank(context.get("grade"))
    band = record.get("gradeBand")
    if learner_grade is None or not isinstance(band, dict):
        return False
    minimum = _grade_rank(band.get("minGrade"))
    maximum = _grade_rank(band.get("maxGrade"))
    if minimum is not None and learner_grade < minimum:
        return False
    if maximum is not None and learner_grade > maximum:
        return False
    return True


def evaluate_access(
    record: dict[str, Any],
    context: dict[str, Any],
    operation: str,
    record_lookup: dict[str, dict[str, Any]] | None = None,
    requested_tutor_context: str = "",
    _seen: set[str] | None = None,
) -> tuple[bool, str]:
    """Return an allow/deny decision without disclosing blocked dependency IDs."""
    if operation not in OPERATIONS:
        return False, "unsupported-operation"
    if metadata_errors(record):
        return False, "missing-or-invalid-metadata"
    if operation not in record.get("allowedOperations", []):
        return False, "operation-not-permitted"

    classification = record["audienceClassification"]
    role = str(context.get("audienceRole", "")).lower()
    if classification == "adult-only":
        if role != "adult":
            return False, "adult-content-not-available"
        if context.get("adultConfirmed") is not True:
            return False, "adult-confirmation-required"
        if context.get("adultContentOptIn") is not True:
            return False, "adult-content-opt-in-required"
    elif role == "minor":
        if record.get("minorSafe") is not True or record.get("adultOnly") is not False:
            return False, "content-not-minor-safe"
        if not _age_band_allows(record, context):
            return False, "age-band-not-eligible"
        if not _grade_band_allows(record, context):
            return False, "grade-band-not-eligible"
    elif role != "adult":
        return False, "audience-role-not-confirmed"

    requirement = record["guardianOrFacilitatorRequirement"]
    guardian = context.get("guardianConfirmed") is True
    facilitator = context.get("facilitatorPresent") is True
    if requirement == "guardian-required" and not guardian:
        return False, "guardian-required"
    if requirement == "facilitator-required" and not facilitator:
        return False, "facilitator-required"
    if requirement == "guardian-or-facilitator-required" and not (guardian or facilitator):
        return False, "guardian-or-facilitator-required"

    blocked_categories = set(context.get("blockedSensitiveTopicCategories", []))
    if blocked_categories.intersection(record.get("sensitiveTopicCategories", [])):
        return False, "sensitive-topic-blocked"

    if operation == "tutor-context":
        if not requested_tutor_context:
            return False, "tutor-context-required"
        if requested_tutor_context not in record.get("permittedTutorContexts", []):
            return False, "tutor-context-not-permitted"

    prerequisites = record.get("prerequisiteIds", [])
    if prerequisites:
        lookup = record_lookup or {}
        completed = set(context.get("completedPrerequisiteIds", []))
        seen = set(_seen or set())
        content_id = str(record["contentId"])
        if content_id in seen:
            return False, "prerequisite-cycle"
        seen.add(content_id)
        for prerequisite_id in prerequisites:
            prerequisite = lookup.get(str(prerequisite_id))
            if prerequisite is None:
                return False, "ineligible-prerequisite"
            allowed, _ = evaluate_access(
                prerequisite,
                context,
                operation,
                lookup,
                requested_tutor_context,
                seen,
            )
            if not allowed:
                return False, "ineligible-prerequisite"
            if str(prerequisite_id) not in completed:
                return False, "prerequisite-not-complete"

    return True, "allowed"


def filter_records(
    records: Iterable[dict[str, Any]],
    context: dict[str, Any],
    operation: str,
    *,
    query: str = "",
    requested_tutor_context: str = "",
) -> list[dict[str, Any]]:
    records_list = [record for record in records if isinstance(record, dict)]
    lookup = {
        str(record.get("contentId")): record
        for record in records_list
        if str(record.get("contentId", "")).strip()
    }
    allowed: list[dict[str, Any]] = []
    query_normalized = query.casefold().strip()
    for record in records_list:
        permitted, _ = evaluate_access(
            record,
            context,
            operation,
            lookup,
            requested_tutor_context,
        )
        if not permitted:
            continue
        if operation == "search" and query_normalized:
            searchable = " ".join(
                str(record.get(field, ""))
                for field in ("contentId", "title", "summary", "sourcePath")
            ).casefold()
            if query_normalized not in searchable:
                continue
        allowed.append(deepcopy(record))
    return allowed


def _default_context() -> dict[str, Any]:
    return {
        "audienceRole": "minor",
        "grade": "unknown",
        "ageBand": {"label": "unknown", "minAge": None, "maxAge": None},
        "adultConfirmed": False,
        "adultContentOptIn": False,
        "guardianConfirmed": False,
        "facilitatorPresent": False,
        "blockedSensitiveTopicCategories": [],
        "completedPrerequisiteIds": [],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Apply fail-closed audience filtering")
    parser.add_argument("--records", required=True, help="JSON or JSONL metadata records")
    parser.add_argument("--context", required=True, help="JSON learner audience context")
    parser.add_argument("--operation", required=True, choices=sorted(OPERATIONS))
    parser.add_argument("--query", default="")
    parser.add_argument("--tutor-context", default="")
    args = parser.parse_args()

    context_value = load_json(Path(args.context))
    context = context_value if isinstance(context_value, dict) else _default_context()
    records = load_records(Path(args.records))
    allowed = filter_records(
        records,
        context,
        args.operation,
        query=args.query,
        requested_tutor_context=args.tutor_context,
    )
    print(
        json.dumps(
            {
                "schemaVersion": 1,
                "operation": args.operation,
                "allowedCount": len(allowed),
                "records": allowed,
            },
            indent=2,
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

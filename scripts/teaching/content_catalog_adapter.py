"""Build the public-safe learner catalog shared by static and live delivery.

The adapter intentionally exposes only learner-facing semantic fields. Source
answer keys, calibration samples, private learner data, and absolute content
repository paths never enter the catalog payload.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from copy import deepcopy
from pathlib import Path
from typing import Any, Iterator

AUDIENCE_SCRIPT_ROOT = Path(__file__).resolve().parents[1] / "audience"
if str(AUDIENCE_SCRIPT_ROOT) not in sys.path:
    sys.path.insert(0, str(AUDIENCE_SCRIPT_ROOT))

from audience_policy import filter_records


def objective_label(objective_id: str) -> str:
    slug = str(objective_id).split("/")[-1]
    return " ".join(part.capitalize() for part in slug.replace("-", " ").split())


def catalog_objective(objective_id: str) -> dict[str, str]:
    return {"objectiveId": objective_id, "label": objective_label(objective_id)}


def content_path(source_root: Path, relative_path: str) -> Path:
    parts = str(relative_path).replace("\\", "/").split("/")
    return source_root.joinpath(*(part for part in parts if part))


def public_source_path(source_root: Path, value: Any) -> str:
    """Return a source-relative path or reject a path outside the content repo."""
    raw_value = str(value).strip()
    if not raw_value:
        return ""
    resolved_root = source_root.resolve()
    candidate = Path(raw_value)
    if not candidate.is_absolute():
        candidate = content_path(resolved_root, raw_value)
    try:
        relative = candidate.resolve(strict=False).relative_to(resolved_root)
    except ValueError as exc:
        raise ValueError("Public catalog path escapes its content repository") from exc
    return relative.as_posix()


def load_json(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8-sig"))
    return payload if isinstance(payload, dict) else {}


def load_source_audience_defaults(repo_root: Path) -> dict[str, dict[str, Any]]:
    registry = load_json(repo_root / "audience-sources.json")
    defaults: dict[str, dict[str, Any]] = {}
    for record in registry.get("sources", []):
        if isinstance(record, dict) and str(record.get("sourceId", "")).strip():
            defaults[str(record["sourceId"])] = record
    return defaults


def materialize_course_audience_metadata(
    source_id: str,
    course_id: str,
    title: str,
    source_path: str,
    source_default: dict[str, Any] | None,
) -> dict[str, Any] | None:
    if not source_default:
        return None
    return {
        "schemaVersion": 1,
        "policyVersion": str(source_default.get("policyVersion", "2026-07-23-v1")),
        "metadataId": f"suite:course:{course_id}",
        "contentKind": "course",
        "contentId": course_id,
        "sourcePath": source_path,
        "title": title,
        "gradeBand": deepcopy(source_default.get("gradeBand")),
        "ageBand": deepcopy(source_default.get("ageBand")),
        "audienceClassification": source_default.get("audienceClassification"),
        "minorSafe": source_default.get("minorSafe"),
        "adultOnly": source_default.get("adultOnly"),
        "guardianOrFacilitatorRequirement": source_default.get(
            "guardianOrFacilitatorRequirement"
        ),
        "sensitiveTopicCategories": list(
            source_default.get("sensitiveTopicCategories", [])
        ),
        "prerequisiteIds": list(source_default.get("prerequisiteIds", [])),
        "permittedTutorContexts": list(
            source_default.get("permittedTutorContexts", [])
        ),
        "allowedOperations": list(source_default.get("allowedOperations", [])),
        "masteryAndSafetyPolicyId": source_default.get("masteryAndSafetyPolicyId"),
        "inheritedFrom": f"audience-sources.json#{source_id}",
        "status": str(source_default.get("status", "source-default-unreviewed")),
    }


def iter_jsonl(path: Path) -> Iterator[dict[str, Any]]:
    with path.open("r", encoding="utf-8-sig") as stream:
        for line in stream:
            if not line.strip():
                continue
            payload = json.loads(line)
            if isinstance(payload, dict):
                yield payload


def find_jsonl_record(path: Path, key: str, value: str) -> dict[str, Any] | None:
    for record in iter_jsonl(path):
        if record.get(key) == value:
            return record
    return None


def extract_objectives(path: Path) -> list[str]:
    if not path.is_file():
        return []
    content = path.read_text(encoding="utf-8-sig")
    objective_ids = re.findall(r"`([^`]+:objectives/[^`]+)`", content)
    return list(dict.fromkeys(objective_ids))


def first_public_ai_record(path: Path) -> dict[str, Any] | None:
    for record in iter_jsonl(path):
        privacy_class = str(record.get("privacyClass", ""))
        if privacy_class.startswith("public-") and record.get("writePolicy") == "read-only-seed":
            return record
    return None


def first_learner_prompt(item: dict[str, Any]) -> str:
    forms = item.get("forms", [])
    if not isinstance(forms, list):
        return ""
    for form in forms:
        if isinstance(form, dict) and form.get("stage") == "independent":
            return str(form.get("prompt", ""))
    for form in forms:
        if isinstance(form, dict) and form.get("prompt"):
            return str(form["prompt"])
    return ""


def assessment_bank_sort_key(path: Path) -> tuple[int, int, str]:
    match = re.match(r"g(k|\d+)-t(\d+)-", path.name.lower())
    if not match:
        return (10_000, 10_000, path.name.lower())
    grade = 0 if match.group(1) == "k" else int(match.group(1))
    return (grade, int(match.group(2)), path.name.lower())


def build_semantic_preview(source_root: Path, manifest: dict[str, Any]) -> dict[str, Any] | None:
    lesson_config = manifest.get("dailyLessonPackets", {})
    reading_config = manifest.get("dailyReadingAssignments", {})
    coverage_config = manifest.get("deliveryCoverage", {})
    assessment_config = manifest.get("assessmentItems", {})
    ai_config = manifest.get("aiKnowledgeStore", {})
    required_paths = (
        lesson_config.get("recordsPath"),
        reading_config.get("recordsPath"),
        coverage_config.get("recordsPath"),
        assessment_config.get("recordDirectory"),
        assessment_config.get("recordPattern"),
        ai_config.get("recordsPath"),
    )
    if not all(required_paths):
        return None

    lesson_path = content_path(source_root, str(lesson_config["recordsPath"]))
    reading_path = content_path(source_root, str(reading_config["recordsPath"]))
    coverage_path = content_path(source_root, str(coverage_config["recordsPath"]))
    assessment_root = content_path(source_root, str(assessment_config["recordDirectory"]))
    ai_path = content_path(source_root, str(ai_config["recordsPath"]))
    if not all(path.is_file() for path in (lesson_path, reading_path, coverage_path, ai_path)):
        return None
    if not assessment_root.is_dir():
        return None

    ai_record = first_public_ai_record(ai_path)
    if not ai_record:
        return None

    selected: tuple[dict[str, Any], dict[str, Any], dict[str, Any], dict[str, Any], dict[str, Any], Path] | None = None
    bank_paths = sorted(
        assessment_root.glob(str(assessment_config["recordPattern"])),
        key=assessment_bank_sort_key,
    )
    for bank_path in bank_paths:
        bank = load_json(bank_path)
        for item in bank.get("items", []):
            if not isinstance(item, dict):
                continue
            lesson_links = item.get("lessonLinks", [])
            if not isinstance(lesson_links, list):
                continue
            for lesson_id in lesson_links:
                if not isinstance(lesson_id, str) or not lesson_id.startswith("lesson-"):
                    continue
                lesson = find_jsonl_record(lesson_path, "lessonId", lesson_id)
                reading = find_jsonl_record(reading_path, "lessonId", lesson_id)
                coverage = find_jsonl_record(coverage_path, "recordId", lesson_id)
                if lesson and reading and coverage:
                    selected = (lesson, reading, coverage, bank, item, bank_path)
                    break
            if selected:
                break
        if selected:
            break

    if not selected:
        return None

    lesson, reading, coverage, bank, item, bank_path = selected
    lesson_status = str(lesson.get("status", "draft"))
    reading_primary = reading.get("primarySource", {})
    if not isinstance(reading_primary, dict):
        reading_primary = {}
    learner_material = reading.get("learnerMaterial", {})
    if not isinstance(learner_material, dict):
        learner_material = {}
    missing_artifacts = coverage.get("missingArtifactKinds", [])
    if not isinstance(missing_artifacts, list):
        missing_artifacts = []
    retrieval_prompts = lesson.get("prerequisiteRetrieval", [])
    if not isinstance(retrieval_prompts, list):
        retrieval_prompts = []

    lesson_source_path = public_source_path(source_root, lesson_config["recordsPath"])
    reading_source_path = public_source_path(
        source_root,
        learner_material.get("path", reading_config["recordsPath"]),
    )
    coverage_source_path = public_source_path(source_root, coverage_config["recordsPath"])
    assessment_source_path = public_source_path(source_root, bank_path)
    ai_source_path = public_source_path(source_root, ai_record.get("sourcePath", ""))

    return {
        "schemaVersion": 1,
        "previewKind": "public-safe-structured-draft",
        "courseId": str(lesson.get("courseId", "")),
        "readinessStatus": lesson_status,
        "lesson": {
            "lessonId": str(lesson.get("lessonId", "")),
            "title": str(lesson.get("title", "")),
            "dailyObjective": str(lesson.get("dailyObjective", "")),
            "status": lesson_status,
            "retrievalPrompts": [str(value) for value in retrieval_prompts[:2]],
            "safetyAndPrivacy": str(lesson.get("safetyAndPrivacy", "")),
            "sourcePath": lesson_source_path,
        },
        "reading": {
            "assignmentId": str(reading.get("assignmentId", "")),
            "title": str(reading.get("title", "")),
            "status": str(reading.get("status", "")),
            "learnerAction": str(reading.get("learnerAction", "")),
            "sourceTitle": str(reading_primary.get("sourceTitle", "")),
            "sourceLocator": str(reading_primary.get("locator", "")),
            "rightsBasis": str(reading_primary.get("rightsBasis", "")),
            "sourcePath": reading_source_path,
        },
        "coverage": {
            "recordId": str(coverage.get("recordId", "")),
            "required": bool(coverage.get("required", False)),
            "coverageStatus": str(coverage.get("coverageStatus", "")),
            "missingArtifactKinds": [str(value) for value in missing_artifacts],
            "sourcePath": coverage_source_path,
        },
        "assessmentItem": {
            "bankId": str(bank.get("bankId", "")),
            "itemId": str(item.get("itemId", "")),
            "title": str(item.get("title", "")),
            "objective": str(item.get("objective", "")),
            "learnerPrompt": first_learner_prompt(item),
            "status": str(bank.get("status", "")),
            "sourcePath": assessment_source_path,
        },
        "aiKnowledge": {
            "recordId": str(ai_record.get("recordId", "")),
            "title": str(ai_record.get("title", "")),
            "kind": str(ai_record.get("kind", "")),
            "summary": str(ai_record.get("summary", "")),
            "tutorUse": str(ai_record.get("tutorUse", "")),
            "privacyClass": str(ai_record.get("privacyClass", "")),
            "sourcePath": ai_source_path,
        },
    }


def build_source_catalog(
    source: dict[str, Any],
    audience_defaults: dict[str, dict[str, Any]] | None = None,
) -> dict[str, Any]:
    objects = source.get("objects", [])
    if not isinstance(objects, list):
        objects = []
    source_id = str(source.get("id", ""))
    source_audience_default = (audience_defaults or {}).get(source_id)
    source_root = Path(str(source.get("resolvedPath", "")))
    manifest_path = Path(str(source.get("manifestPath", "")))
    source_objectives: dict[str, dict[str, str]] = {}
    courses: list[dict[str, Any]] = []

    preview = None
    if source_root.is_dir() and manifest_path.is_file():
        try:
            preview = build_semantic_preview(source_root, load_json(manifest_path))
        except (OSError, UnicodeError, json.JSONDecodeError, TypeError, ValueError):
            preview = None

    preview_attached = False
    for item in objects:
        if not isinstance(item, dict):
            continue
        source_path = str(item.get("sourcePath", ""))
        normalized_path = source_path.replace("\\", "/").lower()
        if item.get("type") != "study-plan" or not normalized_path.startswith("study-plans/courses/"):
            continue
        try:
            safe_source_path = public_source_path(source_root, source_path)
        except ValueError:
            continue
        course_path = content_path(source_root, safe_source_path)
        objective_ids = extract_objectives(course_path)
        for objective_id in objective_ids:
            source_objectives[objective_id] = catalog_objective(objective_id)
        course = {
            "id": item.get("id"),
            "title": item.get("title"),
            "sourceRepo": item.get("sourceRepo"),
            "sourcePath": safe_source_path,
            "objectives": [catalog_objective(objective_id) for objective_id in objective_ids],
        }
        course_audience = materialize_course_audience_metadata(
            source_id,
            str(course["id"]),
            str(course["title"]),
            safe_source_path,
            source_audience_default,
        )
        if course_audience:
            course["audienceMetadata"] = course_audience
        if preview and not preview_attached and preview.get("courseId"):
            try:
                course_content = course_path.read_text(encoding="utf-8-sig")
            except (OSError, UnicodeError):
                course_content = ""
            preview_course_slug = str(preview["courseId"]).lower()
            preview_objective_id = next(
                (
                    objective_id
                    for objective_id in objective_ids
                    if objective_id.rsplit("/", 1)[-1].lower() == preview_course_slug
                ),
                "",
            )
            if str(preview["courseId"]) in course_content and preview_objective_id:
                course["structuredPreview"] = {**preview, "objectiveId": preview_objective_id}
                preview_attached = True
        courses.append(course)

    for item in objects:
        if not isinstance(item, dict) or item.get("type") != "objective":
            continue
        try:
            objective_source_path = public_source_path(source_root, item.get("sourcePath", ""))
        except ValueError:
            continue
        objective_path = content_path(source_root, objective_source_path)
        for objective_id in extract_objectives(objective_path):
            source_objectives[objective_id] = catalog_objective(objective_id)

    source_repo = objects[0].get("sourceRepo") if objects and isinstance(objects[0], dict) else source.get("id")
    return {
        "sourceId": source_id,
        "title": source.get("title"),
        "sourceRepo": source_repo,
        "objectCount": source.get("objectCount", 0),
        "courses": courses,
        "objectives": [source_objectives[key] for key in sorted(source_objectives)],
        "structuredPreviewCount": 1 if preview_attached else 0,
        "audienceDefaultStatus": (
            str(source_audience_default.get("status"))
            if source_audience_default
            else "missing-deny"
        ),
    }


def scan_content_sources(repo_root: Path) -> dict[str, Any]:
    powershell = shutil.which("powershell") or shutil.which("pwsh")
    if not powershell:
        raise RuntimeError("PowerShell is required to scan content sources.")
    scan_script = repo_root / "scripts" / "ingestion" / "scan-content-sources.ps1"
    quoted_scan_script = str(scan_script).replace("'", "''")
    scan_command = (
        "[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false); "
        f"& '{quoted_scan_script}'"
    )
    completed = subprocess.run(
        [
            powershell,
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            scan_command,
        ],
        cwd=repo_root,
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8-sig",
    )
    payload = json.loads(completed.stdout)
    return payload if isinstance(payload, dict) else {}


def default_general_audience_context() -> dict[str, Any]:
    return {
        "audienceRole": "adult",
        "grade": "adult",
        "ageBand": {"label": "ages-18-adult", "minAge": 18, "maxAge": None},
        "adultConfirmed": True,
        "adultContentOptIn": False,
        "guardianConfirmed": False,
        "facilitatorPresent": False,
        "blockedSensitiveTopicCategories": [],
        "completedPrerequisiteIds": [],
    }


def filter_catalog_sources(
    sources: list[dict[str, Any]],
    context: dict[str, Any],
    operation: str,
    *,
    query: str = "",
    requested_tutor_context: str = "",
) -> list[dict[str, Any]]:
    all_courses = [
        course
        for source in sources
        for course in source.get("courses", [])
        if isinstance(course, dict)
    ]
    metadata_records = [
        course["audienceMetadata"]
        for course in all_courses
        if isinstance(course.get("audienceMetadata"), dict)
    ]
    allowed_metadata = filter_records(
        metadata_records,
        context,
        operation,
        query=query,
        requested_tutor_context=requested_tutor_context,
    )
    allowed_ids = {str(record["contentId"]) for record in allowed_metadata}

    filtered_sources: list[dict[str, Any]] = []
    for source in sources:
        visible_courses = [
            course
            for course in source.get("courses", [])
            if str(course.get("id", "")) in allowed_ids
        ]
        if not visible_courses:
            continue
        visible_objectives: dict[str, dict[str, str]] = {}
        for course in visible_courses:
            for objective in course.get("objectives", []):
                if isinstance(objective, dict) and objective.get("objectiveId"):
                    visible_objectives[str(objective["objectiveId"])] = objective
        filtered_source = dict(source)
        filtered_source["courses"] = visible_courses
        filtered_source["objectives"] = [
            visible_objectives[key] for key in sorted(visible_objectives)
        ]
        filtered_source["structuredPreviewCount"] = sum(
            1 for course in visible_courses if course.get("structuredPreview")
        )
        filtered_sources.append(filtered_source)
    return filtered_sources


def build_content_catalog(
    repo_root: Path,
    audience_context: dict[str, Any] | None = None,
    operation: str = "catalog",
    *,
    query: str = "",
    requested_tutor_context: str = "",
    operator_unfiltered: bool = False,
) -> dict[str, Any]:
    scan_report = scan_content_sources(repo_root)
    audience_defaults = load_source_audience_defaults(repo_root)
    sources = [
        build_source_catalog(source, audience_defaults)
        for source in scan_report.get("sources", [])
        if isinstance(source, dict)
    ]
    context = audience_context or default_general_audience_context()
    if not operator_unfiltered:
        sources = filter_catalog_sources(
            sources,
            context,
            operation,
            query=query,
            requested_tutor_context=requested_tutor_context,
        )
    return {
        "schemaVersion": 1,
        "generatedFrom": "scripts/teaching/content_catalog_adapter.py",
        "sourceCount": len(sources),
        "courseCount": sum(len(source.get("courses", [])) for source in sources),
        "audienceEnforcement": (
            "operator-unfiltered-explicit"
            if operator_unfiltered
            else "fail-closed-shared-policy"
        ),
        "audienceOperation": operation,
        "adultContentOptIn": bool(context.get("adultContentOptIn", False)),
        "storesBirthDate": False,
        "sources": sources,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Build the audience-filtered learner content catalog")
    parser.add_argument("--repo-root", default=".", help="Open Education Suite repository root")
    parser.add_argument("--audience-context-path", default="")
    parser.add_argument(
        "--operation",
        default="catalog",
        choices=("catalog", "search", "recommendation", "export", "import", "tutor-context"),
    )
    parser.add_argument("--query", default="")
    parser.add_argument("--tutor-context", default="")
    parser.add_argument("--operator-unfiltered", action="store_true")
    args = parser.parse_args()
    repo_root = Path(args.repo_root).resolve()
    context = (
        load_json(Path(args.audience_context_path).resolve())
        if args.audience_context_path
        else default_general_audience_context()
    )
    payload = build_content_catalog(
        repo_root,
        context,
        args.operation,
        query=args.query,
        requested_tutor_context=args.tutor_context,
        operator_unfiltered=args.operator_unfiltered,
    )
    print(json.dumps(payload, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

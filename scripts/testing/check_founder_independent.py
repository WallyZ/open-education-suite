"""Exercise the public grading operations and privately materialize QA answers."""

from __future__ import annotations

import argparse
import copy
import json
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "assessment"))
from founder_independent import FounderAssessment, canonical


def rejected(action) -> None:
    try:
        action()
    except ValueError:
        return
    raise AssertionError("Rejected operation unexpectedly succeeded")


def exercise(service: FounderAssessment) -> dict:
    learner = "qa-server-scored"
    initial = service.begin({"learnerId": learner, "now": "2026-08-01"})
    wrong = dict(service.expected["initial"], budget=999)
    request = {"learnerId": learner, "token": initial["token"], "answers": wrong, "support": "unassisted"}
    first = service.grade(request)
    assert first["body"]["results"][-1]["status"] == "partial"
    assert first["body"]["state"]["mastery"][0]["confidence"] == 0
    assert canonical(service.grade(request)) == canonical(first)
    assert len(first["body"]["state"]["auditLog"]) == 1
    rejected(lambda: service.grade({**request, "score": 1}))
    rejected(lambda: service.grade({**request, "learnerId": "another-profile"}))
    changed = dict(request, answers=service.expected["initial"])
    rejected(lambda: service.grade(changed))
    tampered = copy.deepcopy(first)
    tampered["body"]["state"]["mastery"][0]["confidence"] = 1
    rejected(lambda: service.verify(tampered, learner))
    rejected(lambda: service.verify(first, "another-profile"))
    retry = service.begin({"learnerId": learner, "receipt": first, "now": "2026-08-01", "correctionReviewed": True})
    assisted = service.grade({"learnerId": learner, "token": retry["token"], "answers": service.expected["retry"], "support": "assisted"})
    assert assisted["body"]["state"]["mastery"][0]["confidence"] == 0
    next_retry = service.begin({"learnerId": learner, "receipt": assisted, "now": "2026-08-01", "correctionReviewed": True})
    assert next_retry["stage"] == "retry"
    passed = service.grade({"learnerId": learner, "token": next_retry["token"], "answers": service.expected["retry"], "support": "unassisted"})
    assert passed["body"]["state"]["mastery"][0]["confidence"] == 0.1
    rejected(lambda: service.verify(first, learner))
    rejected(lambda: service.grade(request))
    rejected(lambda: service.begin({"learnerId": learner, "receipt": passed, "now": "2026-08-02"}))
    delayed = service.begin({"learnerId": learner, "receipt": passed, "now": "2026-08-08"})
    bad = dict(service.expected["delayed"], personalClaim="false")
    rejected(lambda: service.grade({"learnerId": learner, "token": delayed["token"], "answers": bad, "support": "unassisted"}))
    final = service.grade({"learnerId": learner, "token": delayed["token"], "answers": service.expected["delayed"], "support": "unassisted"})
    state = final["body"]["state"]
    assert state["mastery"][0]["confidence"] == 0.2
    assert state["mastery"][0]["objectiveId"].endswith(":objective/lesson-g1-cw10-d01")
    assert len(state["auditLog"]) == len(state["learningEvents"]) == 4
    assert len({event["eventId"] for event in state["learningEvents"]}) == 4
    withdrawn = service.withdraw(final, learner)
    rejected(lambda: service.begin({"learnerId": learner, "receipt": withdrawn, "now": "2026-08-09"}))
    assert service.verify(withdrawn, learner)["body"]["withdrawn"] is True
    forbidden = ("expectedEvidence", "workedSteps", "scoringNotes", "correctionCue")
    assert not any(marker in json.dumps(final) for marker in forbidden)
    return withdrawn


def prepare(suite: Path, temp: Path, service: FounderAssessment) -> None:
    template = json.loads((suite / "qa-live/feature_spec.founder_assessment.json").read_text())

    def substitute(value):
        if isinstance(value, dict):
            return {key: substitute(child) for key, child in value.items()}
        if isinstance(value, list):
            return [substitute(child) for child in value]
        if isinstance(value, str) and value.startswith("__") and value.endswith("__"):
            stage, field = value[2:-2].split(".")
            answer = service.expected[stage][field]
            return str(answer).lower() if isinstance(answer, bool) else str(answer)
        return value
    private_spec = temp / "private-assessment-spec.json"
    private_spec.write_text(json.dumps(substitute(template)), encoding="utf-8")
    workflow = json.loads((suite / "qa-live/workflow.founder_ui.json").read_text())
    workflow["workflow_id"] = "founder-independent-assessment"
    workflow["base_url"] = "http://127.0.0.1:8788"
    workflow["startup_command"][-1] = "8788"
    workflow["startup_command"].append("--assessment-rehearsal")
    workflow["browser_specs"] = [str(private_spec)]
    (temp / "assessment-workflow.json").write_text(json.dumps(workflow), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--suite-root", required=True)
    parser.add_argument("--temp-root", required=True)
    args = parser.parse_args()
    suite, temp = Path(args.suite_root).resolve(), Path(args.temp_root).resolve()
    temp.relative_to(suite / ".codex-cache/tmp")
    with tempfile.TemporaryDirectory(prefix="scoring-tests-", dir=temp) as work:
        service = FounderAssessment(suite, Path(work), rehearsal=True)
        saved = exercise(service)
        prepare(suite, temp, service)
        ordinary = FounderAssessment(suite, Path(work) / "ordinary")
        rejected(lambda: ordinary.begin({"learnerId": "ordinary", "now": "2026-08-01"}))
        rejected(lambda: ordinary.verify(saved, saved["body"]["learnerId"]))
    print("Founder independent scoring, canonical mastery, replay, receipt, support, timing and withdrawal checks passed. Private QA inputs prepared under the run temp directory.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

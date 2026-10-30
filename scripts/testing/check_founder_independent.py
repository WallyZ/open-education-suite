"""Exercise the public grading operations and privately materialize QA answers."""

from __future__ import annotations

import argparse
import copy
import json
import sqlite3
import sys
import tempfile
from contextlib import closing
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "assessment"))
from founder_independent import FounderAssessment, canonical
from private_grading_store import PrivateGradingStore


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


def persistence_checks(suite: Path, work: Path, service: FounderAssessment, saved: dict) -> None:
    store = service.store.path
    reopened = FounderAssessment(suite, work / "reopened", rehearsal=True, store_path=store)
    assert canonical(reopened.verify(saved, saved["body"]["learnerId"])) == canonical(saved)
    learner = "qa-restart-pending"
    pending = service.begin({"learnerId": learner, "now": "2026-08-01"})
    request = {"learnerId": learner, "token": pending["token"], "answers": service.expected["initial"], "support": "unassisted"}
    # A challenge issued by one instance is scored by the reopened instance.
    scored = reopened.grade(request)
    again = FounderAssessment(suite, work / "again", rehearsal=True, store_path=store)
    assert canonical(again.grade(request)) == canonical(scored)
    assert len(again.verify(scored, learner)["body"]["state"]["auditLog"]) == 1
    withdrawn = again.withdraw(scored, learner)
    after_withdrawal = FounderAssessment(suite, work / "after-withdrawal", rehearsal=True, store_path=store)
    assert after_withdrawal.verify(withdrawn, learner)["body"]["withdrawn"] is True
    rejected(lambda: after_withdrawal.verify(scored, learner))
    rejected(lambda: FounderAssessment(suite, work / "wrong-mode", store_path=store))
    rejected(lambda: PrivateGradingStore(suite, store, "different-source-revision", True))
    # Normal transaction rollback must leave the durable authority unchanged.
    try:
        with service.store.transaction() as vault:
            vault["sessions"].clear()
            raise ValueError("fixture rollback")
    except ValueError:
        pass
    assert after_withdrawal.verify(withdrawn, learner)["body"]["withdrawn"] is True
    with service.store.transaction() as vault:
        signing_key = vault["secret"].encode()
    on_disk = store.read_bytes()
    assert learner.encode() not in on_disk and signing_key not in on_disk
    corrupt = FounderAssessment(suite, work / "corrupt", rehearsal=True)
    with closing(sqlite3.connect(corrupt.store.path)) as connection:
        with connection:
            payload = bytearray(connection.execute("SELECT payload FROM authority WHERE id=1").fetchone()[0])
            payload[len(payload) // 2] ^= 1
            connection.execute("UPDATE authority SET payload=? WHERE id=1", (bytes(payload),))
    rejected(lambda: FounderAssessment(suite, work / "corrupt-reopen", rehearsal=True, store_path=corrupt.store.path))
    print("Private authority reopen, pending challenge, committed replay, withdrawal, rollback, encryption and corruption checks passed.")


def prepare_restart(suite: Path, temp: Path, phase: int) -> None:
    workflow_path = temp / "assessment-workflow.json"
    workflow = json.loads(workflow_path.read_text())
    store = temp / "restart-authority.sqlite"
    if phase == 1:
        spec = json.loads((temp / "private-assessment-spec.json").read_text())
        spec["scenarios"][0]["actions"] = spec["scenarios"][0]["actions"][:-3]
        workflow["startup_command"] += ["--assessment-store", str(store)]
    else:
        service = FounderAssessment(suite, temp / f"recovery-{phase}", rehearsal=True, store_path=store)
        receipts = service.local_receipts("gdev-101-live-smoke-learner")
        if len(receipts) != 1:
            raise ValueError("Expected one isolated QA grading session")
        receipt = receipts[0]
        snapshot = copy.deepcopy(receipt["body"]["state"])
        snapshot["founderAssessment"] = receipt
        old_path = temp / "pre-withdrawal-export.json"
        if phase == 2:
            old_path.write_text(json.dumps(snapshot), encoding="utf-8")
        with service.store.transaction() as vault:
            tokens = [token for token, value in vault["challenges"].items()
                      if value["session"] == receipt["body"]["sessionId"] and value["stage"] == "delayed" and value["result"]]
        if len(tokens) != 1:
            raise ValueError("Expected the committed delayed nonce")
        replay = {"learnerId": receipt["body"]["learnerId"], "token": tokens[0], "answers": service.expected["delayed"], "support": "unassisted"}
        value_map = {
            "__export__": json.dumps(snapshot), "__oldExport__": old_path.read_text(),
            "__storeHttpPath__": "/" + store.relative_to(suite).as_posix(),
            "__replayOptions__": json.dumps({"body": replay, "expect_status": 200,
                "expect_json": {"body": {"version": 4}}, "reject_text": ["expectedEvidence", "workedSteps", "scoringNotes"]}),
        }
        template = json.loads((suite / "qa-live/feature_spec.founder_restart.json").read_text())
        def substitute(value):
            if isinstance(value, dict):
                return {key: substitute(child) for key, child in value.items()}
            if isinstance(value, list):
                return [substitute(child) for child in value]
            return value_map.get(value, value) if isinstance(value, str) else value
        spec = substitute(template)
        spec["scenarios"] = [spec["scenarios"][phase - 2]]
    path = temp / f"private-restart-phase-{phase}.json"
    path.write_text(json.dumps(spec), encoding="utf-8")
    workflow["workflow_id"] = f"founder-restart-phase-{phase}"
    workflow["browser_specs"] = [str(path)]
    workflow_path.write_text(json.dumps(workflow), encoding="utf-8")
    print(f"Prepared private restart phase {phase}; responses and receipts remain in the ignored run directory.")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--suite-root", required=True)
    parser.add_argument("--temp-root", required=True)
    parser.add_argument("--persistence", action="store_true")
    parser.add_argument("--restart-phase", type=int, choices=(1, 2, 3))
    args = parser.parse_args()
    suite, temp = Path(args.suite_root).resolve(), Path(args.temp_root).resolve()
    temp.relative_to(suite / ".codex-cache/tmp")
    if args.restart_phase:
        prepare_restart(suite, temp, args.restart_phase)
        return 0
    with tempfile.TemporaryDirectory(prefix="scoring-tests-", dir=temp) as work:
        service = FounderAssessment(suite, Path(work), rehearsal=True)
        saved = exercise(service)
        if args.persistence:
            persistence_checks(suite, Path(work), service, saved)
        prepare(suite, temp, service)
        ordinary = FounderAssessment(suite, Path(work) / "ordinary")
        rejected(lambda: ordinary.begin({"learnerId": "ordinary", "now": "2026-08-01"}))
        rejected(lambda: ordinary.verify(saved, saved["body"]["learnerId"]))
    print("Founder independent scoring, canonical mastery, replay, receipt, support, timing and withdrawal checks passed. Private QA inputs prepared under the run temp directory.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

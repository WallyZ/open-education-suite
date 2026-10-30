"""Bounded, server-side structured assessment; never a tutor-context provider."""

from __future__ import annotations

import copy
import hashlib
import hmac
import json
import re
import secrets
import shutil
import subprocess
import threading
import time
import uuid
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

from private_grading_store import PrivateGradingStore


def canonical(value: object) -> bytes:
    # Browser JSON round-trips do not retain the distinction between 1 and 1.0.
    def normalize(item: object) -> object:
        if isinstance(item, float) and item.is_integer():
            return int(item)
        if isinstance(item, dict):
            return {key: normalize(child) for key, child in item.items()}
        if isinstance(item, list):
            return [normalize(child) for child in item]
        return item
    return json.dumps(normalize(value), sort_keys=True, separators=(",", ":"), allow_nan=False).encode()


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def record(path: Path, record_id: str) -> dict:
    with path.open(encoding="utf-8-sig") as handle:
        for line in handle:
            value = json.loads(line)
            if value.get("id") == record_id:
                return value
    raise ValueError("Required assessment record is unavailable")


def normalized(value: object) -> str:
    return re.sub(r"[^a-z0-9]+", "", str(value).casefold())


class FounderAssessment:
    """Local, restart-safe authority for one selected objective and Windows account."""

    def __init__(self, suite: Path, runtime: Path, rehearsal: bool = False, store_path: Path | None = None):
        self.suite = suite.resolve()
        self.root = self.suite.parent / "open-education-founder-level-civic-classical"
        self.runtime = runtime
        self.runtime.mkdir(parents=True, exist_ok=True)
        self.rehearsal = rehearsal
        self.lock = threading.Lock()
        schema = read_json(suite / "schemas/founder-course-export.schema.json")
        self.flow = schema["x-exportContract"]["selectedFlow"]
        manifest_path = self.root / "exports/suite-v1/suite-export-manifest.json"
        manifest = read_json(manifest_path)
        entry = next(item for item in manifest["files"] if item["visibility"] == "restricted-facilitator-or-authorized-grader")
        bank = (self.root / entry["path"]).resolve()
        bank.relative_to(self.root.resolve())
        bank_bytes = bank.read_bytes()
        if entry["sha256"] not in {hashlib.sha256(bank_bytes).hexdigest(), hashlib.sha256(bank_bytes.replace(b"\r\n", b"\n")).hexdigest()}:
            raise ValueError("Assessment bank checksum mismatch")
        self.bindings = {path: hashlib.sha256(path.read_bytes()).hexdigest()
                         for path in (manifest_path, bank, suite / "schemas/founder-course-export.schema.json", Path(__file__))}
        self.revision = hashlib.sha256(canonical(list(self.bindings.values()))).hexdigest()
        self.forms = {}
        for stage, key in (("initial", "initialAssessmentId"), ("retry", "retestAssessmentId"), ("delayed", "delayedAssessmentId")):
            form = record(self.root / "exports/suite-v1/public/assessment.jsonl", self.flow[key])
            private = record(bank, form["data"]["restrictedAnswerKeyId"])
            if (self.flow["lessonId"] not in form["references"]
                    or self.flow["rubricId"] not in form["references"]
                    or private["targetId"] != form["id"]
                    or private["visibility"] != "restricted-facilitator-or-authorized-grader"):
                raise ValueError("Assessment/rubric/key binding mismatch")
            self.forms[stage] = {"id": form["id"], "evidence": private["data"]["expectedEvidence"]}
        native = self.flow["lessonId"].removeprefix("lesson:")
        crosswalk = self.root / "docs/graduate-standard/generated/founder-graduate-standard-crosswalk.jsonl"
        with crosswalk.open(encoding="utf-8-sig") as handle:
            refs = [json.loads(line).get("objectiveRef", {}) for line in handle]
        self.objective = next(ref["objectiveId"] for ref in refs if ref.get("objectiveId", "").endswith(f":objective/{native}"))
        reading_path = self.root / "exports/suite-v1/public/reading.jsonl"
        rights_path = self.root / "exports/suite-v1/public/source-rights.jsonl"
        lesson = record(self.root / "exports/suite-v1/public/lesson.jsonl", self.flow["lessonId"])
        reading = record(reading_path, lesson["data"]["readingId"])
        primary = record(rights_path, reading["data"]["sourceRightsIds"][0])["data"]
        source_path = (self.root / primary["localPath"]).resolve()
        source_path.relative_to(self.root.resolve())
        source_bytes = source_path.read_bytes()
        if primary["sha256"] not in {hashlib.sha256(source_bytes).hexdigest(), hashlib.sha256(source_bytes.replace(b"\r\n", b"\n")).hexdigest()}:
            raise ValueError("Assessment source checksum mismatch")
        self.source_text = source_bytes.decode("utf-8-sig")
        for path in (crosswalk, source_path, reading_path, rights_path, self.root / "exports/suite-v1/public/assessment.jsonl", Path(__file__).with_name("private_grading_store.py"), self.suite / "scripts/state/update-learner-state.ps1"):
            self.bindings[path] = hashlib.sha256(path.read_bytes()).hexdigest()
        self.revision = hashlib.sha256(canonical(list(self.bindings.values()))).hexdigest()
        self.fields, self.expected, self.groups = self._structured_contract()
        self.store = PrivateGradingStore(self.suite, store_path or runtime / "authority.sqlite", self.revision, rehearsal)

    def _adopt(self, vault: dict) -> None:
        self.secret = bytes.fromhex(vault["secret"])
        self.authority_id = vault["authorityId"]
        self.sessions = vault["sessions"]
        self.challenges = vault["challenges"]

    def local_receipts(self, learner: str) -> list[dict]:
        """Offline recovery for the OS account with store access; never an HTTP lookup."""
        with self.lock, self.store.transaction() as vault:
            self._adopt(vault)
            self._fresh()
            return [self._receipt(key) for key, value in self.sessions.items() if value["state"]["learnerId"] == learner]

    def _structured_contract(self) -> tuple[dict, dict, dict]:
        """Interpret only the current authored rubric; fail closed on unsupported drift."""
        initial = self.forms["initial"]["evidence"]
        retry = self.forms["retry"]["evidence"]
        delayed = self.forms["delayed"]["evidence"]
        fingerprints = ("912a9f5530080929268a0aae346e19330dcbcad554e685fcb6f2ca5ce81598f1",
                        "e5de7b878d21dd12e4e8d4cc7486822637215d628de41aa1c6fa613a2711623c",
                        "3284868ce55203225758b294c49d74f3a2729f5bf24def2c55db717c17efb74f")
        if any(hashlib.sha256(canonical(evidence)).hexdigest() != fingerprint
               for evidence, fingerprint in zip((initial, retry, delayed), fingerprints)):
            raise ValueError("Structured rubric requires review")
        arithmetic = re.fullmatch(r"(\d+)\+(\d+)=(\d+) does not fit(\d+)", initial[1])
        remaining = re.fullmatch(r"(\d+) remain", initial[3])
        roles = [re.fullmatch(pattern, retry[index]) for index, pattern in enumerate(
            (r"(.+) checks labels", r"(.+) shelves picture books", r"(.+) moves cart/handles torn page"))]
        if not arithmetic or not remaining or not all(roles):
            raise ValueError("Structured rubric requires review")
        lunch, kite, total, budget = map(int, arithmetic.groups())
        word_numbers = {word: index for index, word in enumerate(("zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"))}
        cloudy = re.search(r"counted (\w+) cloudy days", self.source_text)
        forward = re.search(r"The path moved (\w+) squares forward", self.source_text)
        if not cloudy or not forward or cloudy[1] not in word_numbers or forward[1] not in word_numbers:
            raise ValueError("Transfer facts require source review")
        fields = {
            "initial": [("budget", "Starting budget (tokens)", "number"), ("lunch", "Lunch price", "number"),
                        ("kite", "Kite price", "number"), ("total", "Cost of both", "number"),
                        ("buyBoth", "Can both fit the budget?", "boolean"), ("choice", "Which purchase did the fictional rule require first?", "text"),
                        ("remaining", "Tokens remaining after that purchase", "number"),
                        ("universalAdvice", "Does this establish advice for every real family?", "boolean"),
                        ("familyInference", "Can we infer a real family's income or food choices?", "boolean")],
            "retry": [("labels", "Who checks the labels?", "text"), ("shelves", "Who shelves the picture books?", "text"),
                      ("cart", "Who handles the heavy cart and torn page?", "text"),
                      ("purpose", "Shared purpose", ["order-search", "become-famous", "not-stated"]),
                      ("everyProblem", "Must the learner handle every problem alone?", "boolean"),
                      ("rankClaim", "Do these actions prove personality or rank?", "boolean")],
            "delayed": [("weatherCloudy", "Cloudy days in Seven Weather Notes", "number"),
                        ("weather", "Weather source scope", ["one-week", "all-weather-everywhere", "unlimited"]),
                        ("mapForward", "First forward move in Map to the Garden Box (squares)", "number"),
                        ("map", "Map source scope", ["fictional-space", "all-real-places", "unlimited"]),
                        ("marketRemaining", "Tokens left after the required purchase in Lunch Before the Kite", "number"),
                        ("market", "Market source scope", ["fictional-prices-rule", "universal-advice", "unlimited"]),
                        ("personalClaim", "Is a universal or personal claim supported by those sources alone?", "boolean")],
        }
        expected = {
            "initial": {"budget": budget, "lunch": lunch, "kite": kite, "total": total, "buyBoth": False,
                        "choice": initial[2].split()[0], "remaining": int(remaining[1]),
                        "universalAdvice": "no" not in initial[4].split(), "familyInference": "no" not in initial[4].split()},
            "retry": {"labels": roles[0][1], "shelves": roles[1][1], "cart": roles[2][1],
                      "purpose": retry[3].removeprefix("shared ").removesuffix(" purpose").replace("/", "-"),
                      "everyProblem": "not" not in retry[4].split(), "rankClaim": "rejected" not in retry[5]},
            "delayed": {"weatherCloudy": word_numbers[cloudy[1]], "weather": delayed[0].split("limited to ")[1].replace(" ", "-"),
                        "mapForward": word_numbers[forward[1]], "map": delayed[1].split("limited to ")[1].replace(" ", "-"),
                        "marketRemaining": int(remaining[1]), "market": re.sub(r"[ /]+", "-", delayed[2].split("limited to ")[1]),
                        "personalClaim": "unsupported" not in delayed[3]},
        }
        groups = {"initial": [("budget", "lunch", "kite", "choice"), ("total", "buyBoth"), ("choice",), ("remaining",), ("universalAdvice", "familyInference")],
                  "retry": [(key,) for key in expected["retry"]],
                  "delayed": [("weatherCloudy", "weather"), ("mapForward", "map"), ("marketRemaining", "market"), ("personalClaim",)]}
        return fields, expected, groups

    def _fresh(self) -> None:
        if any(hashlib.sha256(path.read_bytes()).hexdigest() != digest for path, digest in self.bindings.items()):
            raise ValueError("Assessment source changed; restart after review")

    def _receipt(self, session_id: str) -> dict:
        item = self.sessions[session_id]
        body = {"schemaVersion": 1, "sessionId": session_id, "learnerId": item["state"]["learnerId"],
                "authorityId": self.authority_id,
                "lessonId": self.flow["lessonId"], "objectiveId": self.objective, "revision": self.revision,
                "synthetic": self.rehearsal, "version": len(item["history"]), "state": item["state"],
                "results": item["history"], "withdrawn": item["withdrawn"]}
        return {"body": copy.deepcopy(body), "signature": hmac.new(self.secret, canonical(body), "sha256").hexdigest()}

    def verify(self, receipt: dict, learner: str) -> dict:
        with self.lock, self.store.transaction() as vault:
            self._adopt(vault)
            return self._verify(receipt, learner)

    def _verify(self, receipt: dict, learner: str) -> dict:
        self._fresh()
        body = receipt.get("body", {})
        signature = receipt.get("signature", "")
        if (not isinstance(signature, str) or not hmac.compare_digest(signature, hmac.new(self.secret, canonical(body), "sha256").hexdigest())
                or body.get("learnerId") != learner or body.get("revision") != self.revision
                or body.get("sessionId") not in self.sessions):
            raise ValueError("Unverified assessment receipt")
        current = self._receipt(body["sessionId"])
        if canonical(current) != canonical(receipt):
            raise ValueError("Stale assessment receipt")
        return current

    def begin(self, request: dict) -> dict:
        with self.lock, self.store.transaction() as vault:
            self._adopt(vault)
            self._fresh()
            if set(request) - {"learnerId", "receipt", "now", "correctionReviewed"}:
                raise ValueError("Unexpected assessment field")
            learner = request.get("learnerId", "")
            if not isinstance(learner, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,80}", learner):
                raise ValueError("Invalid learner reference")
            now = date.today().isoformat()
            if "now" in request:
                if not self.rehearsal:
                    raise ValueError("Rehearsal clock is disabled")
                now = date.fromisoformat(request["now"]).isoformat()
            if request.get("receipt"):
                prior = self._verify(request["receipt"], learner)
                session_id = prior["body"]["sessionId"]
            else:
                session_id = uuid.uuid4().hex
                state = {"schemaVersion": 1, "learnerId": learner,
                         "profile": {"learnerId": learner, "goals": [self.objective], "constraints": [], "preferences": {}, "accommodations": [], "priorExperience": []},
                         "mastery": [], "misconceptions": [], "reviewQueue": [], "learningEvents": [], "auditLog": [],
                         "privacy": {"piiPolicy": "pseudonymous-local-only", "redactionFields": [], "localOnly": True},
                         "sync": {"mode": "local", "lastSyncedAt": None, "conflictPolicy": "append-events-and-recompute-mastery"}}
                self.sessions[session_id] = {"state": state, "history": [], "withdrawn": False}
            item = self.sessions[session_id]
            if item["withdrawn"]:
                raise ValueError("Assessment participation withdrawn")
            last = item["history"][-1] if item["history"] else None
            stage = "initial" if not last else "retry"
            if last:
                if last["stage"] == "delayed":
                    raise ValueError("Assessment loop already finished; review required")
                if last["stage"] == "retry" and last["status"] == "correct" and last["support"] == "unassisted":
                    stage = "delayed"
                    if date.fromisoformat(now) < date.fromisoformat(last["date"]) + timedelta(days=7):
                        raise ValueError("Delayed assessment is not due")
                if stage == "retry" and request.get("correctionReviewed") is not True:
                    raise ValueError("Review correction before changed retry")
                if now < last["date"]:
                    raise ValueError("Assessment dates must remain ordered")
            token = secrets.token_urlsafe(32)
            self.challenges[token] = {"session": session_id, "version": len(item["history"]), "stage": stage,
                                      "date": now, "expires": time.time() + 600, "result": None, "requestHash": None}
            prompts = {"initial": "Recall the fictional market case. Supply the quantities, decision and scope without the source or hints.",
                       "retry": "Reread The Book Return Team, then close it. Identify roles, purpose and limits without hints.",
                       "delayed": "Without passages or hints, distinguish the scope of the weather, map and fictional market sources."}
            return {"token": token, "stage": stage, "assessmentId": self.forms[stage]["id"], "prompt": prompts[stage],
                    "fields": [{"id": field, "label": label, "kind": kind} for field, label, kind in self.fields[stage]],
                    "synthetic": self.rehearsal}

    def grade(self, request: dict) -> dict:
        with self.lock, self.store.transaction() as vault:
            self._adopt(vault)
            self._fresh()
            if set(request) != {"token", "learnerId", "answers", "support"} or request["support"] not in ("unassisted", "assisted"):
                raise ValueError("Invalid assessment submission")
            challenge = self.challenges.get(request["token"])
            if not challenge or challenge["expires"] < time.time():
                raise ValueError("Unknown or expired assessment challenge")
            item = self.sessions[challenge["session"]]
            if request["learnerId"] != item["state"]["learnerId"] or item["withdrawn"]:
                raise ValueError("Assessment learner binding rejected")
            request_hash = hashlib.sha256(canonical(request)).hexdigest()
            if challenge["result"]:
                if request_hash != challenge["requestHash"]:
                    raise ValueError("Changed replay rejected")
                if challenge["result"]["body"]["version"] != len(item["history"]):
                    raise ValueError("Stale assessment replay")
                return copy.deepcopy(challenge["result"])
            if challenge["version"] != len(item["history"]):
                raise ValueError("Stale assessment challenge")
            stage = challenge["stage"]
            answers = request["answers"]
            if not isinstance(answers, dict) or set(answers) != set(self.expected[stage]):
                raise ValueError("Missing or unexpected response fields")
            for field, _, kind in self.fields[stage]:
                value = answers[field]
                if (kind == "number" and (type(value) is not int or not 0 <= value <= 10000)
                        or kind == "boolean" and type(value) is not bool
                        or kind == "text" and (not isinstance(value, str) or not value.strip() or len(value) > 100)
                        or isinstance(kind, list) and value not in kind):
                    raise ValueError("Invalid response type")
            matches = {field: normalized(value) == normalized(self.expected[stage][field]) for field, value in answers.items()}
            passed = sum(all(matches[field] for field in group) for group in self.groups[stage])
            score = passed / len(self.groups[stage])
            status = "correct" if score == 1 else "partial" if score else "incorrect"
            eligible = status == "correct" and request["support"] == "unassisted"
            delta = 0.1 if eligible else 0.0
            result = {"schemaVersion": 1, "itemId": self.forms[stage]["id"], "status": status, "score": score,
                      "hintUsage": 0 if request["support"] == "unassisted" else 1,
                      "masteryEvidence": {"objectiveId": self.objective, "evidenceType": "server-structured-unassisted" if eligible else "server-structured-practice", "confidenceDelta": delta}}
            work = self.runtime / uuid.uuid4().hex
            work.mkdir()
            try:
                (work / "state.json").write_bytes(canonical(item["state"]))
                (work / "result.json").write_bytes(canonical(result))
                shell = shutil.which("pwsh") or shutil.which("powershell")
                if not shell:
                    raise ValueError("Canonical mastery updater is unavailable")
                completed = subprocess.run([shell, "-NoProfile", "-NonInteractive", "-File", "scripts/state/update-learner-state.ps1",
                                            "-StatePath", str(work / "state.json"), "-AssessmentResultPath", str(work / "result.json"),
                                            "-OutputPath", str(work / "updated.json"), "-Now", challenge["date"] + "T12:00:00Z" if self.rehearsal else datetime.now(timezone.utc).isoformat()],
                                           cwd=self.suite, capture_output=True, text=True, timeout=30, check=False)
                if completed.returncode:
                    raise ValueError("Canonical mastery updater failed")
                state = read_json(work / "updated.json")
                state["learningEvents"][-1]["eventId"] += "-" + uuid.uuid4().hex
                item["state"] = state
            finally:
                shutil.rmtree(work)
            item["history"].append({"stage": stage, "date": challenge["date"] if self.rehearsal else date.today().isoformat(), "status": status, "score": score,
                                    "support": request["support"], "assessmentId": self.forms[stage]["id"],
                                    "submissionSha256": request_hash, "rubricId": self.flow["rubricId"]})
            receipt = self._receipt(challenge["session"])
            challenge["requestHash"] = request_hash
            challenge["result"] = receipt
            return copy.deepcopy(receipt)

    def withdraw(self, receipt: dict, learner: str) -> dict:
        with self.lock, self.store.transaction() as vault:
            self._adopt(vault)
            current = self._verify(receipt, learner)
            session_id = current["body"]["sessionId"]
            self.sessions[session_id]["withdrawn"] = True
            return self._receipt(session_id)

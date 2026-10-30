import argparse
import hashlib
import json
import mimetypes
import os
import re
import shutil
import subprocess
import sys
import threading
import uuid
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse

from content_catalog_adapter import build_content_catalog

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "assessment"))
from founder_independent import FounderAssessment


FIXED_NOW = "2026-05-25T12:00:00Z"
OBJECTIVE_ID = "game-development:objectives/course/gdev-101/design-vocabulary"
GAME_DEVELOPMENT_LECTURE_PATH = (
    "open-education-game-development",
    "generated-lectures",
    "gdev-101-design-vocabulary",
    "publish",
    "lecture-video.publish-ready.json",
)
GAME_DEVELOPMENT_CONTENT_ROUTE = "/content-repos/open-education-game-development/"
FOUNDER_CIVIC_CLASSICAL_CONTENT_ROUTE = (
    "/content-repos/open-education-founder-level-civic-classical/"
)


def new_run_root(repo_root: Path, prefix: str) -> Path:
    temp_base = os.environ.get("TMP") or os.environ.get("TEMP")
    if temp_base:
        base_path = Path(temp_base)
        if not base_path.is_absolute():
            base_path = repo_root / base_path
        try:
            base_path.resolve().relative_to((repo_root / ".codex-cache/tmp").resolve())
        except ValueError:
            base_path = repo_root / ".codex-cache/tmp"
    else:
        base_path = repo_root / ".codex-cache" / "tmp"
    return base_path / f"{prefix}_{uuid.uuid4().hex}"


def build_default_state(path: Path) -> None:
    payload = {
        "schemaVersion": 1,
        "learnerId": "gdev-101-live-smoke-learner",
        "profile": {
            "learnerId": "gdev-101-live-smoke-learner",
            "goals": [OBJECTIVE_ID],
            "constraints": ["short-evening-sessions"],
            "preferences": {
                "explanationStyle": "worked-example",
                "practiceMode": "scaffolded",
            },
            "accommodations": ["low-distraction-output"],
            "priorExperience": ["played-games-but-new-to-design"],
        },
        "mastery": [
            {
                "objectiveId": OBJECTIVE_ID,
                "confidence": 0.0,
                "lastEvidenceAt": None,
                "evidenceCount": 0,
                "evidenceSources": [],
            }
        ],
        "misconceptions": [],
        "reviewQueue": [],
        "learningEvents": [],
        "auditLog": [],
        "privacy": {
            "piiPolicy": "fixtures-use-non-identifying-ids",
            "redactionFields": ["profile.accommodations", "profile.constraints"],
            "localOnly": True,
        },
        "sync": {
            "mode": "local",
            "lastSyncedAt": None,
            "conflictPolicy": "append-events-and-recompute-mastery",
        },
    }
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def load_default_lecture_package(repo_root: Path) -> dict:
    content_repo_root = repo_root.parent / GAME_DEVELOPMENT_LECTURE_PATH[0]
    lecture_path = content_repo_root.joinpath(*GAME_DEVELOPMENT_LECTURE_PATH[1:])
    lecture_package = json.loads(lecture_path.read_text(encoding="utf-8"))
    lecture_package["contentRepoRoot"] = str(content_repo_root)
    lecture_package["contentRepoWebRoot"] = content_repo_root.resolve().as_uri() + "/"
    lecture_package["contentRepoHttpRoot"] = GAME_DEVELOPMENT_CONTENT_ROUTE
    lecture_package["sourcePackagePath"] = str(lecture_path.relative_to(content_repo_root)).replace("/", "\\")
    return lecture_package


def run_session_turn(repo_root: Path) -> dict:
    run_root = new_run_root(repo_root, "learner_ui_bridge")
    run_root.mkdir(parents=True, exist_ok=True)
    state_path = run_root / "gdev-101-learner-state.json"
    try:
        build_default_state(state_path)
        completed = subprocess.run(
            [
                "powershell",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(repo_root / "scripts" / "teaching" / "start-session.ps1"),
                "-StatePath",
                str(state_path),
                "-NonInteractive",
                "-Now",
                FIXED_NOW,
            ],
            cwd=repo_root,
            check=True,
            capture_output=True,
            text=True,
            encoding="utf-8",
        )
        return {
            "schemaVersion": 1,
            "source": "scripts/teaching/start-session.ps1",
            "session": json.loads(completed.stdout),
            "lecturePackage": load_default_lecture_package(repo_root),
            "contentCatalog": build_content_catalog(repo_root),
        }
    finally:
        shutil.rmtree(run_root, ignore_errors=True)


def run_live_teacher(repo_root: Path) -> dict:
    run_root = new_run_root(repo_root, "learner_ui_live_teacher")
    run_root.mkdir(parents=True, exist_ok=True)
    state_path = run_root / "gdev-101-learner-state.json"
    prompt_path = run_root / "live-ai-teacher-prompt.json"
    output_path = run_root / "live-ai-teacher-output.json"
    try:
        build_default_state(state_path)
        completed = subprocess.run(
            [
                "powershell",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(repo_root / "scripts" / "ai" / "invoke-openai-teacher.ps1"),
                "-StatePath",
                str(state_path),
                "-Mode",
                "socratic",
                "-OutputPath",
                str(output_path),
                "-PromptPath",
                str(prompt_path),
                "-Now",
                FIXED_NOW,
            ],
            cwd=repo_root,
            check=True,
            capture_output=True,
            text=True,
            encoding="utf-8",
        )
        return {
            "schemaVersion": 1,
            "source": "scripts/ai/invoke-openai-teacher.ps1",
            "summary": json.loads(completed.stdout),
            "output": json.loads(output_path.read_text(encoding="utf-8")),
        }
    finally:
        shutil.rmtree(run_root, ignore_errors=True)


def founder_lesson_payload(repo_root: Path) -> dict:
    """Project only public records for the already selected integration sequence."""
    root = repo_root.parent / "open-education-founder-level-civic-classical"
    contract = json.loads((repo_root / "schemas/founder-course-export.schema.json").read_text(
        encoding="utf-8-sig"))["x-exportContract"]["selectedFlow"]

    def public(kind: str, record_id: str) -> dict:
        with (root / f"exports/suite-v1/public/{kind}.jsonl").open(encoding="utf-8-sig") as handle:
            for line in handle:
                record = json.loads(line)
                if record["id"] == record_id:
                    if record["visibility"] != "learner-safe-public":
                        raise ValueError("Founder record is not public")
                    return record
        raise ValueError("Selected Founder record is missing")

    lesson = public("lesson", contract["lessonId"])
    reading = public("reading", lesson["data"]["readingId"])
    primary_id = reading["data"]["sourceRightsIds"][0]
    primary = public("source-rights", primary_id)["data"]
    source_path = (root / primary["localPath"]).resolve()
    source_path.relative_to(root.resolve())
    source_bytes = source_path.read_bytes()
    normalized_bytes = source_bytes.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    if primary["sha256"] not in {hashlib.sha256(source_bytes).hexdigest(), hashlib.sha256(normalized_bytes).hexdigest()}:
        raise ValueError("Assigned passage checksum mismatch")
    passage_id = reading["data"]["sourceRoute"].split()[0]
    passage = re.search(rf"^### {re.escape(passage_id)}:.*?\n(.*?)(?=^#{{1,3}} |\Z)",
                        normalized_bytes.decode("utf-8-sig"), re.MULTILINE | re.DOTALL)
    if not passage or not passage.group(1).strip():
        raise ValueError("Assigned passage is unavailable")
    rubric = public("rubric", contract["rubricId"])
    correction = public("correction-reteach", lesson["data"]["correctionReteachId"])
    forms = []
    for stage, key in (("initial", "initialAssessmentId"), ("retry", "retestAssessmentId"),
                       ("delayed", "delayedAssessmentId")):
        form = public("assessment", contract[key])
        if lesson["id"] not in form["references"]:
            raise ValueError("Founder form is bound to a different lesson")
        forms.append({"stage": stage, "id": form["id"], "prompt": form["data"]["prompt"]})
    payload = {
        "schemaVersion": 1, "sourceId": "founder-level-civic-classical",
        "lessonId": lesson["id"], "title": lesson["data"]["title"],
        "objective": lesson["data"]["objective"],
        "reading": {"title": reading["data"]["title"], "sourceRoute": reading["data"]["sourceRoute"],
                    "text": passage.group(1).strip(), "license": primary["rightsBasis"]},
        "sourceRights": [ref for ref in reading["references"] if ref.startswith("source-rights:")],
        "forms": forms, "rubric": rubric["data"]["masteryRule"],
        "feedback": rubric["data"]["revisionRule"], "correction": correction["data"]["steps"],
    }
    payload["contentRevision"] = hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest()
    retry_passage = re.search(r"^### G1-T1-R08:.*?\n(.*?)(?=^#{1,3} |\Z)",
                              normalized_bytes.decode("utf-8-sig"), re.MULTILINE | re.DOTALL)
    if not retry_passage:
        raise ValueError("Changed-task source is unavailable")
    payload["retryReading"] = retry_passage.group(1).strip()
    return payload


class LearnerBridgeHandler(BaseHTTPRequestHandler):
    server_version = "OpenEducationLearnerBridge/1.0"

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/api/founder/lesson":
            try:
                self.write_json(founder_lesson_payload(self.server.repo_root))
            except (ValueError, KeyError, OSError):
                self.write_json({"error": "founder-content-unavailable"}, HTTPStatus.SERVICE_UNAVAILABLE)
            return
        if parsed.path == "/api/teacher/live/status":
            self.write_json(
                {
                    "schemaVersion": 1,
                    "enabled": self.server.live_ai_enabled,
                    "setting": "--enable-live-ai",
                    "source": "scripts/ai/invoke-openai-teacher.ps1",
                }
            )
            return
        if parsed.path == "/api/session/start":
            if parsed.query == "refresh=1":
                self.server.session_payload = run_session_turn(self.server.repo_root)
            self.write_json(self.server.session_payload)
            return
        if parsed.path == "/api/content/catalog":
            self.write_json(self.server.session_payload["contentCatalog"])
            return
        if parsed.path == "/":
            self.send_response(HTTPStatus.FOUND)
            self.send_header("Location", "/ui/learner/index.html")
            self.end_headers()
            return
        if parsed.path.startswith(GAME_DEVELOPMENT_CONTENT_ROUTE):
            self.serve_game_development_content(parsed.path)
            return
        if parsed.path.startswith(FOUNDER_CIVIC_CLASSICAL_CONTENT_ROUTE):
            self.serve_founder_civic_classical_content(parsed.path)
            return
        self.serve_static(parsed.path)

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path.startswith("/api/founder/assessment/"):
            origin = self.headers.get("Origin")
            if (self.server.server_address[0] not in ("127.0.0.1", "::1")
                    or origin and urlparse(origin).netloc != self.headers.get("Host")
                    or self.headers.get("Content-Type", "").split(";")[0] != "application/json"):
                self.write_json({"error": "assessment-request-rejected"}, HTTPStatus.FORBIDDEN)
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if not 0 < length <= 20000:
                    raise ValueError("Invalid request length")
                request = json.loads(self.rfile.read(length))
                if not isinstance(request, dict):
                    raise ValueError("Invalid request")
                with self.server.assessment_lock:
                    if self.server.assessment_provider is None:
                        self.server.assessment_provider = FounderAssessment(
                            self.server.repo_root, self.server.assessment_runtime,
                            rehearsal=self.server.assessment_rehearsal)
                provider = self.server.assessment_provider
                operation = parsed.path.rsplit("/", 1)[-1]
                if operation == "begin":
                    # Source projection is public only; restricted records never enter it.
                    public = founder_lesson_payload(self.server.repo_root)
                    result = provider.begin(request)
                    result["studyText"] = public["reading"]["text"] if result["stage"] == "initial" else "The Book Return Team\n" + public["retryReading"] if result["stage"] == "retry" else "Delayed assessment: do not reopen sources."
                elif operation == "grade":
                    result = provider.grade(request)
                elif operation == "verify" and set(request) == {"receipt", "learnerId"}:
                    with provider.lock:
                        result = provider.verify(request["receipt"], request["learnerId"])
                elif operation == "withdraw" and set(request) == {"receipt", "learnerId"}:
                    result = provider.withdraw(request["receipt"], request["learnerId"])
                else:
                    raise ValueError("Unsupported assessment operation")
                self.write_json(result)
            except (ValueError, KeyError, TypeError):
                # A denied RPC is an application result, never a successful grade.
                self.write_json({"accepted": False, "error": "assessment-request-rejected"})
            except Exception:
                self.write_json({"error": "assessment-unavailable"}, HTTPStatus.SERVICE_UNAVAILABLE)
            return
        if parsed.path == "/api/teacher/live":
            if not self.server.live_ai_enabled:
                self.write_json(
                    {
                        "schemaVersion": 1,
                        "error": "live-ai-disabled",
                        "message": "Live AI teacher invocation is disabled by operator setting.",
                        "requiredSetting": "--enable-live-ai",
                    },
                    HTTPStatus.FORBIDDEN,
                )
                return
            try:
                self.write_json(run_live_teacher(self.server.repo_root))
            except Exception as exc:
                self.write_json(
                    {
                        "schemaVersion": 1,
                        "error": "live-ai-invocation-failed",
                        "message": str(exc),
                    },
                    HTTPStatus.INTERNAL_SERVER_ERROR,
                )
            return
        if parsed.path == "/api/session/start":
            self.write_json(self.server.session_payload)
            return
        self.send_error(HTTPStatus.NOT_FOUND)

    def serve_static(self, request_path: str) -> None:
        relative = unquote(request_path).lstrip("/")
        target = (self.server.repo_root / relative).resolve()
        repo_root = self.server.repo_root.resolve()
        try:
            safe_relative = target.relative_to(repo_root)
        except ValueError:
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        if not safe_relative.parts or safe_relative.parts[0] != "ui" or not target.is_file():
            self.send_error(HTTPStatus.NOT_FOUND)
            return

        content_type = mimetypes.guess_type(target.name)[0] or "application/octet-stream"
        data = target.read_bytes()
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def serve_game_development_content(self, request_path: str) -> None:
        relative = unquote(request_path[len(GAME_DEVELOPMENT_CONTENT_ROUTE):]).lstrip("/")
        content_root = (self.server.repo_root.parent / "open-education-game-development").resolve()
        target = (content_root / relative).resolve()
        try:
            target.relative_to(content_root)
        except ValueError:
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        if not target.is_file():
            self.send_error(HTTPStatus.NOT_FOUND)
            return

        content_type = mimetypes.guess_type(target.name)[0] or "application/octet-stream"
        data = target.read_bytes()
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def serve_founder_civic_classical_content(self, request_path: str) -> None:
        relative = unquote(
            request_path[len(FOUNDER_CIVIC_CLASSICAL_CONTENT_ROUTE):]
        ).lstrip("/")
        content_root = (
            self.server.repo_root.parent
            / "open-education-founder-level-civic-classical"
        ).resolve()
        target = (content_root / relative).resolve()
        try:
            safe_relative = target.relative_to(content_root)
        except ValueError:
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        folded_parts = tuple(part.casefold() for part in safe_relative.parts)
        if (any(part.startswith(".") for part in folded_parts)
                or "restricted" in folded_parts
                or (folded_parts and folded_parts[0] == "assessments")):
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        if not target.is_file():
            self.send_error(HTTPStatus.NOT_FOUND)
            return

        content_type = (
            mimetypes.guess_type(target.name)[0] or "application/octet-stream"
        )
        data = target.read_bytes()
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header(
            "Content-Security-Policy",
            "default-src 'none'; style-src 'unsafe-inline'; "
            "img-src 'self' data:; font-src 'self'; base-uri 'none'; "
            "form-action 'none'; frame-ancestors 'self'",
        )
        self.end_headers()
        self.wfile.write(data)

    def write_json(self, payload: dict, status: HTTPStatus = HTTPStatus.OK) -> None:
        data = json.dumps(payload, indent=2).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, format: str, *args: object) -> None:
        sys.stderr.write("%s - - [%s] %s\n" % (self.address_string(), self.log_date_time_string(), format % args))


def main() -> int:
    parser = argparse.ArgumentParser(description="Open Education learner UI local bridge")
    parser.add_argument("--repo-root", default=".", help="Repository root to serve")
    parser.add_argument("--host", default="127.0.0.1", help="Host to bind")
    parser.add_argument("--port", type=int, default=8786, help="Port to bind")
    parser.add_argument("--enable-live-ai", action="store_true", help="Allow /api/teacher/live to call the live AI teacher script")
    parser.add_argument("--assessment-rehearsal", action="store_true", help="Allow simulated assessment dates; receipts are marked synthetic")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    server = ThreadingHTTPServer((args.host, args.port), LearnerBridgeHandler)
    server.repo_root = repo_root
    server.live_ai_enabled = bool(args.enable_live_ai)
    server.assessment_rehearsal = bool(args.assessment_rehearsal)
    server.assessment_provider = None
    server.assessment_lock = threading.Lock()
    server.assessment_runtime = new_run_root(repo_root, "founder-assessment")
    server.session_payload = run_session_turn(repo_root)
    live_status = "enabled" if server.live_ai_enabled else "disabled"
    print(f"learner-ui-bridge listening http://{args.host}:{args.port} repo={repo_root} live-ai={live_status}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        return 0
    finally:
        shutil.rmtree(server.assessment_runtime, ignore_errors=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

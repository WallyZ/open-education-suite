import argparse
import json
import mimetypes
import os
import shutil
import subprocess
import sys
import uuid
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse

from content_catalog_adapter import build_content_catalog


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


def new_run_root(repo_root: Path, prefix: str) -> Path:
    temp_base = os.environ.get("TMP") or os.environ.get("TEMP")
    if temp_base:
        base_path = Path(temp_base)
        if not base_path.is_absolute():
            base_path = repo_root / base_path
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


class LearnerBridgeHandler(BaseHTTPRequestHandler):
    server_version = "OpenEducationLearnerBridge/1.0"

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
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
            self.write_json(build_content_catalog(self.server.repo_root))
            return
        if parsed.path == "/":
            self.send_response(HTTPStatus.FOUND)
            self.send_header("Location", "/ui/learner/index.html")
            self.end_headers()
            return
        if parsed.path.startswith(GAME_DEVELOPMENT_CONTENT_ROUTE):
            self.serve_game_development_content(parsed.path)
            return
        self.serve_static(parsed.path)

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
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
        if not str(target).startswith(str(repo_root)) or not target.is_file():
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
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    server = ThreadingHTTPServer((args.host, args.port), LearnerBridgeHandler)
    server.repo_root = repo_root
    server.live_ai_enabled = bool(args.enable_live_ai)
    server.session_payload = run_session_turn(repo_root)
    live_status = "enabled" if server.live_ai_enabled else "disabled"
    print(f"learner-ui-bridge listening http://{args.host}:{args.port} repo={repo_root} live-ai={live_status}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

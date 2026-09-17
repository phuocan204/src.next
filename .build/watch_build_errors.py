#!/usr/bin/env python3
"""Watch the Kiwi release log and publish each new build failure once."""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path


INTERVAL_SECONDS = 600
ERROR_MARKERS = (
    "FAILED:",
    "ninja: build stopped:",
    "Release build failed",
    "Traceback (most recent call last):",
)


def ask_codex_to_fix(project_root: Path, error_path: Path) -> int:
    codex = shutil.which("codex")
    project_argument = str(project_root)
    error_argument = str(error_path)
    if not codex and os.name != "nt":
        candidates = sorted(
            Path("/mnt/c/Users").glob(
                "*/AppData/Local/OpenAI/Codex/bin/*/codex.exe"
            ),
            key=lambda path: path.stat().st_mtime,
            reverse=True,
        )
        if candidates:
            codex = str(candidates[0])
            project_argument = subprocess.check_output(
                ["wslpath", "-w", str(project_root)], text=True
            ).strip()
            error_argument = subprocess.check_output(
                ["wslpath", "-w", str(error_path)], text=True
            ).strip()
    if not codex:
        print("Watcher warning: codex.exe was not found in PATH.", file=sys.stderr)
        return 127

    fixer_log = project_root / "release-apk" / "codex-fixer.log"
    prompt = f"""
Kiwi Browser ARM64 release build failed. Read the latest error from:
{error_argument}

Work inside {project_argument}. Diagnose the newest failure, apply the smallest safe
source or build-script fix, and verify it. Preserve all existing changes and
/root/chromium/src/out/KiwiRelease. Do not clean or rebuild from scratch. Restart
the release pipeline from cache, confirm Ninja is running, then finish without
waiting for the whole APK build. Do not re-fix older errors already resolved.
""".strip()
    command = [
        codex,
        "exec",
        "--approve-for-me",
        "--sandbox",
        "workspace-write",
        "--skip-git-repo-check",
        "--color",
        "never",
        "-C",
        project_argument,
        prompt,
    ]
    timestamp = datetime.now().astimezone().isoformat(timespec="seconds")
    with fixer_log.open("a", encoding="utf-8") as output:
        output.write(f"\n===== Codex fixer started {timestamp} =====\n")
        output.flush()
        result = subprocess.run(
            command,
            cwd=project_root,
            stdout=output,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )
        output.write(f"===== Codex fixer exited {result.returncode} =====\n")
    return result.returncode


def extract_latest_failure(log_text: str) -> str | None:
    lines = log_text.splitlines()
    failure_indexes = [
        index
        for index, line in enumerate(lines)
        if "FAILED:" in line or "Release build failed" in line
    ]
    if not failure_indexes:
        return None

    start = failure_indexes[-1]
    # Include the command and compiler diagnostics following the latest failure.
    block = lines[start : start + 220]
    return "\n".join(block).strip()


def build_is_running() -> bool:
    if os.name == "nt":
        return False
    for cmdline_path in Path("/proc").glob("[0-9]*/cmdline"):
        try:
            command = cmdline_path.read_bytes().replace(b"\0", b" ")
        except OSError:
            continue
        if b"ninja" in command and b"/root/chromium/src/out/KiwiRelease" in command:
            return True
    return False


def scan(project_root: Path) -> bool:
    output_dir = project_root / "release-apk"
    log_path = output_dir / "build.log"
    error_path = output_dir / "latest-error.txt"
    state_path = output_dir / ".error-watcher-state.json"
    output_dir.mkdir(parents=True, exist_ok=True)

    if (output_dir / "KiwiBrowser-arm64-release.apk").exists() or build_is_running():
        return False
    if not log_path.exists():
        return False

    text = log_path.read_text(encoding="utf-8", errors="replace")
    if not any(marker in text for marker in ERROR_MARKERS):
        return False

    failure = extract_latest_failure(text)
    if not failure:
        return False

    digest = hashlib.sha256(failure.encode("utf-8")).hexdigest()
    previous_digest = ""
    if state_path.exists():
        try:
            previous_digest = json.loads(
                state_path.read_text(encoding="utf-8")
            ).get("last_error_sha256", "")
        except (OSError, ValueError):
            pass

    if digest == previous_digest:
        return False

    timestamp = datetime.now().astimezone().isoformat(timespec="seconds")
    error_path.write_text(
        f"Detected: {timestamp}\nLog: {log_path}\n\n{failure}\n",
        encoding="utf-8",
    )
    state_path.write_text(
        json.dumps(
            {"last_error_sha256": digest, "detected_at": timestamp}, indent=2
        ),
        encoding="utf-8",
    )
    print(f"[{timestamp}] New build error: {error_path}", flush=True)
    return_code = ask_codex_to_fix(project_root, error_path)
    print(f"[{timestamp}] Codex fixer exit code: {return_code}", flush=True)
    return True


def main() -> int:
    project_root = (
        Path(sys.argv[1]).resolve()
        if len(sys.argv) > 1
        else Path(__file__).resolve().parents[1]
    )
    once = "--once" in sys.argv[2:] or "--once" in sys.argv[1:]

    while True:
        try:
            scan(project_root)
        except Exception as exc:  # Keep the watcher alive after transient file locks.
            print(f"Watcher warning: {exc}", file=sys.stderr, flush=True)
        if once:
            return 0
        time.sleep(INTERVAL_SECONDS)


if __name__ == "__main__":
    raise SystemExit(main())

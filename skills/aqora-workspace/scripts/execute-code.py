#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "httpx>=0.27",
#   "websockets>=12",
# ]
# ///
"""Execute code inside a running aqora workspace's marimo kernel.

Opens a short-lived WebSocket to register a Marimo-Session-Id with the kernel,
then POSTs code to the agent-only /api/kernel/execute endpoint and streams the
result back as Server-Sent Events. Output is decoded and printed to stdout.

Usage:
  execute-code.py --workspace ID|SLUG [--session SID] -c "code"
  execute-code.py --workspace ID|SLUG [--session SID] script.py
  execute-code.py --workspace ID|SLUG [--session SID] <<'EOF'
    code
  EOF
  execute-code.py --url URL [--session SID] -c "code"

Auth resolution order:
  1. --token TOKEN flag (avoid; visible in ps)
  2. AQORA_TOKEN env var (preferred for CI)
  3. access_token from the aqora CLI credentials file
     (written by `aqora login`, located at <config_home>/credentials.json)

Running without uv:
  pip install httpx>=0.27 websockets>=12
  python execute-code.py ...

Environment:
  AQORA_API_URL       Override the default aqora API endpoint (default https://aqora.io).
  AQORA_CONFIG_HOME   Override the aqora CLI config home.
  AQORA_TOKEN         Provide an explicit access token.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import platform
import re
import subprocess
import sys
import uuid
from pathlib import Path
from typing import Optional
from urllib.parse import parse_qs, urlparse

import httpx
import websockets
from websockets.exceptions import WebSocketException

AQORA_API_DEFAULT = os.environ.get("AQORA_API_URL", "https://aqora.io").rstrip("/")
SCRIPT_DIR = Path(__file__).resolve().parent
LIST_SCRIPT = SCRIPT_DIR / "list-workspaces.sh"


def resolve_token(aqora_api: str) -> str:
    """Find a valid aqora access token. See module docstring for order."""
    if token := os.environ.get("AQORA_TOKEN"):
        return token

    if config_home := os.environ.get("AQORA_CONFIG_HOME"):
        config_home_path = Path(config_home)
    elif platform.system() == "Darwin":
        config_home_path = Path.home() / "Library" / "Application Support" / "aqora"
    else:
        data_home = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local" / "share")
        config_home_path = Path(data_home) / "aqora"

    creds_file = config_home_path / "credentials.json"
    if creds_file.is_file():
        try:
            data = json.loads(creds_file.read_text())
        except json.JSONDecodeError:
            pass
        else:
            url_key = aqora_api.rstrip("/") + "/"
            entry = data.get("credentials", {}).get(url_key)
            if entry and (access := entry.get("access_token")):
                return access

    sys.exit(
        "Error: no aqora token available.\n"
        "Fix one of:\n"
        "  1. export AQORA_TOKEN=<your personal access token>\n"
        "  2. install the aqora CLI and run `aqora login`\n"
        "\n"
        "See references/auth.md in the skill directory for details."
    )


def resolve_workspace_url(workspace_id: str) -> str:
    """Call the sibling list-workspaces.sh to map a workspace id or slug to a URL."""
    if not LIST_SCRIPT.is_file():
        sys.exit(f"Error: list-workspaces.sh not found at {LIST_SCRIPT}")
    result = subprocess.run(
        ["bash", str(LIST_SCRIPT), "--id", workspace_id, "--url-only"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        sys.stderr.write(result.stderr)
        sys.exit(result.returncode or 1)
    url = result.stdout.strip()
    if not url:
        sys.exit(f"No live runner for workspace '{workspace_id}'.")
    return url


def parse_runner_url(runner_url: str) -> tuple[str, str, str]:
    """Return (base, access_token, file). base is scheme://host/path without trailing slash."""
    parsed = urlparse(runner_url)
    query = parse_qs(parsed.query)
    access_token = query.get("access_token", [""])[0]
    if not access_token:
        sys.exit("Runner URL is missing the access_token query parameter.")
    file_param = query.get("file", ["readme.py"])[0]
    base = f"{parsed.scheme}://{parsed.netloc}{parsed.path.rstrip('/')}"
    return base, access_token, file_param


def warn_non_aqora(url: str) -> None:
    """Print a warning when the target host is not aqora or loopback."""
    host = urlparse(url).hostname or ""
    trusted = {"aqora.io", "localhost", "127.0.0.1", "::1", "0.0.0.0"}
    if host in trusted:
        return
    if host.endswith(".aqora.io") or host.endswith(".aqora-internal.io"):
        return
    print(
        f"Warning: connecting to non-aqora host '{host}'. Ensure this is trusted.",
        file=sys.stderr,
    )


def log_call_if_requested() -> None:
    """Append an ISO timestamp line to EXECUTE_CODE_LOG if set."""
    if path := os.environ.get("EXECUTE_CODE_LOG"):
        from datetime import datetime, timezone
        with open(path, "a") as f:
            f.write(datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ\n"))


async def stream_execute(
    runner_url: str,
    code: str,
    session: Optional[str],
) -> int:
    """Run the full handshake and stream output. Return process exit code."""
    warn_non_aqora(runner_url)
    base, runner_access_token, file_param = parse_runner_url(runner_url)
    session_id = session or str(uuid.uuid4())

    async with httpx.AsyncClient(follow_redirects=True, timeout=30.0) as client:
        # Step 1: GET the runner page to set session cookie and fetch server token
        try:
            page = await client.get(runner_url)
            page.raise_for_status()
        except httpx.HTTPError as e:
            sys.stderr.write(f"Error fetching runner page: {e}\n")
            return 1

        match = re.search(
            r'<marimo-server-token[^>]+data-token="([^"]+)"', page.text
        )
        if not match:
            sys.stderr.write(
                "Error: could not find marimo-server-token in runner HTML.\n"
                "The runner layout may have changed or the URL is not a running workspace.\n"
            )
            return 1
        server_token = match.group(1)

        # Step 2: Open WebSocket to register the session id, keep it open during HTTP POST
        ws_scheme = "wss" if base.startswith("https") else "ws"
        ws_url = (
            f"{ws_scheme}://{urlparse(base).netloc}{urlparse(base).path.rstrip('/')}/ws"
            f"?session_id={session_id}"
            f"&file={file_param}"
            f"&access_token={runner_access_token}"
        )

        cookies_header = "; ".join(f"{n}={v}" for n, v in client.cookies.items())
        ws_headers = [("Cookie", cookies_header)] if cookies_header else []

        try:
            ws = await websockets.connect(
                ws_url,
                additional_headers=ws_headers,
            )
        except WebSocketException as e:
            sys.stderr.write(f"Error opening WebSocket to runner: {e}\n")
            return 1

        try:
            # Wait briefly for marimo to emit its initial handshake message
            try:
                await asyncio.wait_for(ws.recv(), timeout=5.0)
            except asyncio.TimeoutError:
                pass

            # Step 3: POST code to the agent-only execute endpoint, stream SSE
            cookies_dict = {n: v for n, v in client.cookies.items()}
            try:
                async with client.stream(
                    "POST",
                    f"{base}/api/kernel/execute",
                    headers={
                        "Content-Type": "application/json",
                        "Marimo-Server-Token": server_token,
                        "Marimo-Session-Id": session_id,
                    },
                    json={"code": code},
                    cookies=cookies_dict,
                    timeout=None,
                ) as response:
                    if response.status_code >= 400:
                        body = await response.aread()
                        sys.stderr.write(
                            f"HTTP {response.status_code} from aqora runner: "
                            f"{body.decode('utf-8', 'replace')}\n"
                        )
                        if response.status_code in (401, 403):
                            sys.stderr.write(
                                "Hint: if your aqora session is stale, run "
                                "`aqora login` and retry.\n"
                            )
                        return 1

                    last_event = ""
                    async for raw_line in response.aiter_lines():
                        line = raw_line.rstrip("\r")
                        if line.startswith("event:"):
                            last_event = line.split(":", 1)[1].strip()
                        elif line.startswith("data:"):
                            payload = line.split(":", 1)[1].strip()
                            if not payload:
                                continue
                            handle_sse(last_event, payload)
                        elif line == "":
                            last_event = ""
            except httpx.HTTPError as e:
                sys.stderr.write(f"Error streaming execute response: {e}\n")
                return 1
        finally:
            await ws.close()

    return 0


def handle_sse(event: str, data: str) -> None:
    """Translate a single marimo SSE event into human-friendly output."""
    try:
        payload = json.loads(data)
    except json.JSONDecodeError:
        sys.stdout.write(data + "\n")
        return

    if event == "stdout":
        sys.stdout.write(payload.get("data", ""))
    elif event == "stderr":
        sys.stderr.write(payload.get("data", ""))
    elif event == "done":
        output = payload.get("output") or {}
        mimetype = output.get("mimetype", "")
        value = output.get("data", "")
        if mimetype.startswith("text/") and value:
            sys.stdout.write(value)
            if not value.endswith("\n"):
                sys.stdout.write("\n")
        elif value:
            sys.stdout.write(json.dumps(output) + "\n")
    elif event == "error":
        sys.stderr.write(f"marimo error: {json.dumps(payload)}\n")
    else:
        sys.stderr.write(f"[{event}] {data}\n")


def read_code_from_args(args: argparse.Namespace, positional: list[str]) -> str:
    if args.code is not None:
        return args.code
    if positional:
        return Path(positional[0]).read_text()
    if not sys.stdin.isatty():
        return sys.stdin.read()
    sys.exit(
        "Usage:\n"
        "  execute-code.py --workspace ID -c \"code\"\n"
        "  execute-code.py --workspace ID script.py\n"
        "  execute-code.py --url URL -c \"code\"\n"
        "\n"
        "Auth: set AQORA_TOKEN or run `aqora login` first."
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Execute code inside a running aqora workspace's marimo kernel."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--workspace",
        help="Workspace id or slug. Resolves to an editor URL via list-workspaces.sh.",
    )
    parser.add_argument(
        "--url",
        help="Runner editor URL (skips workspace lookup). Must contain access_token query param.",
    )
    parser.add_argument(
        "--session",
        help="Override the generated Marimo-Session-Id. Rarely needed.",
    )
    parser.add_argument(
        "--token",
        help="Aqora access token. Avoid; visible in ps. Prefer AQORA_TOKEN env var.",
    )
    parser.add_argument(
        "-c",
        dest="code",
        help="Code to execute. Alternatively pass a file as a positional argument or pipe on stdin.",
    )
    parser.add_argument(
        "file",
        nargs="?",
        help="Path to a Python file to execute (alternative to -c or stdin).",
    )
    return parser


def main() -> int:
    log_call_if_requested()
    parser = build_parser()
    args = parser.parse_args()

    if args.token:
        os.environ["AQORA_TOKEN"] = args.token

    resolve_token(AQORA_API_DEFAULT)

    if args.url:
        runner_url = args.url
    elif args.workspace:
        runner_url = resolve_workspace_url(args.workspace)
    else:
        sys.exit("Error: provide --workspace ID or --url URL.")

    code = read_code_from_args(args, [args.file] if args.file else [])
    try:
        return asyncio.run(stream_execute(runner_url, code, args.session))
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    sys.exit(main())

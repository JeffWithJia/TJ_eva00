#!/usr/bin/env python3
"""Restricted host-side systemd/journal proxy for the Apex backend container."""

from __future__ import annotations

import json
import os
import signal
import socket
import socketserver
import struct
import subprocess
import sys
import threading
from pathlib import Path
from typing import Any


SOCKET_PATH = os.environ.get(
    "APEX_HOST_CONTROL_SOCKET", "/run/apex-host-control/backend.sock"
)
ALLOWED_UID = int(os.environ.get("APEX_HOST_CONTROL_UID", "1000"))
ALLOWED_SERVICES = {
    "apex-camera.service",
    "apex-dnsmasq.service",
    "apex-robot.service",
    "apex-teleop.service",
    "apex-tool.service",
}
ALLOWED_PROPERTIES = {
    "Id",
    "LoadState",
    "ActiveState",
    "SubState",
    "UnitFileState",
    "Result",
    "ExecMainPID",
    "ExecMainStatus",
    "FragmentPath",
    "ActiveEnterTimestamp",
    "InactiveEnterTimestamp",
    "StateChangeTimestamp",
}


def send_message(stream: Any, payload: dict[str, Any]) -> None:
    stream.write((json.dumps(payload, separators=(",", ":")) + "\n").encode())
    stream.flush()


def run_command(command: list[str], timeout: int) -> dict[str, Any]:
    result = subprocess.run(
        command,
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
    )
    return {
        "ok": result.returncode == 0,
        "returncode": result.returncode,
        "stdout": result.stdout,
        "stderr": result.stderr,
        "error": (result.stderr or result.stdout).strip() if result.returncode else "",
    }


def validate_service(value: Any) -> str:
    service = str(value or "")
    if service not in ALLOWED_SERVICES:
        raise ValueError(f"Service is not allowlisted: {service}")
    return service


class HostControlHandler(socketserver.StreamRequestHandler):
    def handle(self) -> None:
        try:
            peer = self.request.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12)
            _, uid, _ = struct.unpack("3i", peer)
            if uid not in {0, ALLOWED_UID}:
                raise PermissionError(f"UID {uid} is not authorized")

            encoded = self.rfile.readline(1024 * 1024)
            if not encoded:
                return
            request = json.loads(encoded)
            operation = request.get("op")
            if operation == "systemctl":
                self.handle_systemctl(request)
            elif operation == "journal":
                self.handle_journal(request)
            elif operation == "permissions":
                send_message(
                    self.wfile,
                    {
                        "ok": True,
                        "ready": True,
                        "mode": "host-control-socket",
                        "socket": SOCKET_PATH,
                    },
                )
            else:
                raise ValueError(f"Unsupported operation: {operation}")
        except (BrokenPipeError, ConnectionResetError):
            return
        except Exception as exc:
            try:
                send_message(self.wfile, {"ok": False, "error": str(exc)})
            except (BrokenPipeError, ConnectionResetError):
                return

    def handle_systemctl(self, request: dict[str, Any]) -> None:
        action = str(request.get("action", ""))
        service = validate_service(request.get("service"))
        if action in {"start", "stop", "restart"}:
            send_message(
                self.wfile,
                run_command(["/usr/bin/systemctl", action, service], timeout=60),
            )
            return
        if action != "show":
            raise ValueError(f"Unsupported systemctl action: {action}")

        properties = request.get("properties") or []
        if not isinstance(properties, list) or any(
            str(prop) not in ALLOWED_PROPERTIES for prop in properties
        ):
            raise ValueError("One or more systemctl properties are not allowlisted")
        command = ["/usr/bin/systemctl", "show", service]
        for prop in properties:
            command.extend(["--property", str(prop)])
        send_message(self.wfile, run_command(command, timeout=15))

    def handle_journal(self, request: dict[str, Any]) -> None:
        service_value = request.get("service")
        service = validate_service(service_value) if service_value else None
        lines = max(1, min(int(request.get("lines", 100)), 2000))
        follow = bool(request.get("follow", False))
        priority = request.get("priority")
        if priority not in {None, "err..alert"}:
            raise ValueError("Journal priority is not allowlisted")
        if follow and service is None:
            raise ValueError("Following the system journal is not allowed")

        command = ["/usr/bin/journalctl"]
        if service:
            command.extend(["-u", service])
        if priority:
            command.extend(["-p", priority])
        if follow:
            command.append("-f")
        command.extend(["-n", str(lines), "--no-pager", "-o", "short-iso"])

        if not follow:
            send_message(self.wfile, run_command(command, timeout=20))
            return

        process = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        try:
            assert process.stdout is not None
            for line in process.stdout:
                send_message(
                    self.wfile,
                    {"ok": True, "type": "line", "line": line.rstrip("\n")},
                )
            send_message(self.wfile, {"ok": True, "type": "eof"})
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    process.kill()


class ThreadedUnixServer(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True
    allow_reuse_address = True


def main() -> int:
    if os.geteuid() != 0:
        print("apex_backend_host_control.py must run as root", file=sys.stderr)
        return 1

    path = Path(SOCKET_PATH)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.parent.chmod(0o755)
    if path.exists() or path.is_socket():
        path.unlink()

    server = ThreadedUnixServer(SOCKET_PATH, HostControlHandler)
    os.chmod(SOCKET_PATH, 0o660)
    try:
        os.chown(SOCKET_PATH, 0, int(os.environ.get("APEX_HOST_CONTROL_GID", "1000")))
    except OSError as exc:
        print(f"Unable to set socket group: {exc}", file=sys.stderr)
        server.server_close()
        path.unlink(missing_ok=True)
        return 1

    def stop_server(_signum: int, _frame: Any) -> None:
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, stop_server)
    signal.signal(signal.SIGINT, stop_server)
    try:
        server.serve_forever(poll_interval=0.25)
    finally:
        server.server_close()
        path.unlink(missing_ok=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

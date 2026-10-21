"""Fail-closed cleanup of ONLY Godot processes owned by a net_smooth1 run.

Windows console wrappers may exit while their separate Godot MAIN exe remains
alive. Popen.wait() is not sufficient proof of isolation of the NEXT GUI arm.

Never search-and-kill all Godot.exe processes: other tests and editor sessions
may share the host. Match exact --instance-id and --node-id role/run pairs,
the supplied engine bin directory and Godot process name. Unknown/ambiguous
process identity fails closed, not guessed or killed.

No dependency beyond Python stdlib, pwsh Get-CimInstance and taskkill on Win10.
"""
from __future__ import annotations

import json
import ntpath
import os
from pathlib import Path
import re
import shutil
import subprocess
import time
from typing import Callable


ROLES = ("a", "b", "server")
RUN_ID = re.compile(r"^[0-9a-f]{16}$")
MAX_SCAN_ROWS = 96
_WAIT_GRACE_S = 60.0
_WAIT_TERM_S = 10.0


def _exact_marker(command: str, value: str) -> bool:
    return re.search(r'(^|[\s"])' + re.escape(value) + r'(?=$|[\s"])',
                     command) is not None


def select_windows_owned_godot(rows: list[dict], run_id: str,
                               godot_binary: Path) -> tuple[list[int], list[int]]:
    """(verified own PIDs, ambiguous run-matching Godot PIDs).

    Preserve the signed 64-bit process instance ID untouched in the cache.
    This cleanup uses OS PIDs, *not* Godot Object.get_instance_id().
    """
    if RUN_ID.fullmatch(run_id) is None:
        raise ValueError("NET_SMOOTH_INVALID_RUN_ID")
    if len(rows) > MAX_SCAN_ROWS:
        raise ValueError("NET_SMOOTH_TOO_MANY_PROCESS_ROWS")
    root = ntpath.normcase(ntpath.normpath(ntpath.dirname(str(godot_binary))))
    verified: list[int] = []
    ambiguous: list[int] = []
    for row in rows:
        if not isinstance(row, dict):
            raise ValueError("NET_SMOOTH_BAD_PROCESS_ROW")
        pid = row.get("pid")
        command = row.get("command_line", "")
        name = row.get("name", "")
        exe = row.get("executable", "")
        if type(pid) is not int or pid <= 0 or not isinstance(command, str):
            raise ValueError("NET_SMOOTH_INVALID_PID_OR_COMMAND")
        if not isinstance(name, str) or not isinstance(exe, str):
            raise ValueError("NET_SMOOTH_INVALID_PROCESS_IDENTITY")
        marker = "--instance-id=" + run_id
        if not _exact_marker(command, marker):
            continue
        if not re.fullmatch(r"(?i)godot.*\.exe", name):
            continue
        if not any(_exact_marker(command, "--node-id=smooth-" + role + "-" + run_id)
                   for role in ROLES):
            ambiguous.append(pid)
            continue
        folder = ntpath.normcase(ntpath.normpath(ntpath.dirname(exe))) if exe else ""
        if not folder or folder != root:
            ambiguous.append(pid)
            continue
        verified.append(pid)
    if len(verified) != len(set(verified)) or len(ambiguous) != len(set(ambiguous)):
        raise ValueError("NET_SMOOTH_DUPLICATE_PROCESS_PID")
    return verified, ambiguous


def windows_process_rows(run_id: str) -> list[dict]:
    if RUN_ID.fullmatch(run_id) is None:
        raise ValueError("NET_SMOOTH_INVALID_RUN_ID")
    return _query_windows_godot_rows("--instance-id=" + run_id)


def windows_smooth_process_rows() -> list[dict]:
    # Read-only preflight: refuse to start performance tests while another
    # smooth-run Godot instance is already alive. NEVER kill unrelated runs.
    return _query_windows_godot_rows("--node-id=smooth-")


def preflight_no_smooth_godot(godot_binary: Path,
                             scanner: Callable[[], list[dict]] | None = None) -> list[int]:
    rows = scanner() if scanner is not None else windows_smooth_process_rows()
    engine_dir = ntpath.normcase(ntpath.normpath(ntpath.dirname(str(godot_binary))))
    found: list[int] = []
    for row in rows:
        if not isinstance(row, dict) or type(row.get("pid")) is not int:
            raise RuntimeError("NET_SMOOTH_PREFLIGHT_BAD_PROCESS_ROW")
        name = str(row.get("name", ""))
        command = str(row.get("command_line", ""))
        executable = str(row.get("executable", ""))
        if not re.fullmatch(r"(?i)godot.*\.exe", name):
            continue
        if "--node-id=smooth-" not in command:
            continue
        folder = ntpath.normcase(ntpath.normpath(ntpath.dirname(executable))) if executable else ""
        if folder == engine_dir:
            found.append(row["pid"])
    if found:
        raise RuntimeError("NET_SMOOTH_OTHER_GODOT_RUN_ALREADY_ACTIVE:" +
                           ",".join(str(x) for x in sorted(found)))
    return found


def _query_windows_godot_rows(needle: str) -> list[dict]:
    shell = shutil.which("pwsh") or shutil.which("powershell")
    if not shell:
        raise RuntimeError("NET_SMOOTH_WINDOWS_PROCESS_QUERY_UNAVAILABLE")
    # Match exact run marker / read-only preflight marker via env, NEVER
    # interpolate input into PowerShell source. A pwsh process is excluded by
    # the executable-name gate.
    script = r"""
$ErrorActionPreference='Stop'
$needle = $env:DWS_NET_SMOOTH_PROCESS_NEEDLE
$rows = @(
  Get-CimInstance -ClassName Win32_Process -ErrorAction Stop |
  Where-Object { $_.Name -match '(?i)^godot.*\.exe$' -and
                  $_.CommandLine -and $_.CommandLine.Contains($needle) } |
  ForEach-Object {
    [pscustomobject]@{
      pid=[int]$_.ProcessId
      name=[string]$_.Name
      executable=[string]$_.ExecutablePath
      command_line=[string]$_.CommandLine
    }
  }
)
ConvertTo-Json -InputObject $rows -Compress -Depth 5
"""
    env = dict(os.environ)
    env["DWS_NET_SMOOTH_PROCESS_NEEDLE"] = needle
    p = subprocess.run([shell, "-NoProfile", "-NonInteractive", "-Command", script],
                       capture_output=True, text=True, encoding="utf-8", errors="replace",
                       env=env, timeout=35, check=False)
    if p.returncode != 0:
        raise RuntimeError("NET_SMOOTH_WINDOWS_CIM_FAILED_EXIT_" + str(p.returncode))
    rows = json.loads(p.stdout.strip())
    if not isinstance(rows, list):
        raise RuntimeError("NET_SMOOTH_WINDOWS_CIM_BAD_JSON")
    return rows


def terminate_windows_tree(pid: int) -> None:
    if type(pid) is not int or pid <= 0:
        raise ValueError("NET_SMOOTH_INVALID_KILL_PID")
    # Only called for verified exact run-owned Godot processes; no /IM wildcards.
    subprocess.run(["taskkill", "/PID", str(pid), "/T", "/F"], timeout=25,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                   check=False)


def finalize_owned_processes(
    processes: dict,
    root: Path,
    run_id: str,
    godot_binary: Path,
    *,
    windows: bool | None = None,
    scanner: Callable[[str], list[dict]] | None = None,
    tree_killer: Callable[[int], None] | None = None,
    wait_grace_s: float = _WAIT_GRACE_S,
    wait_terminate_s: float = _WAIT_TERM_S,
) -> dict:
    """Best effort teardown, fail-closed isolation evidence even if run FAILed."""
    if RUN_ID.fullmatch(run_id) is None:
        raise ValueError("NET_SMOOTH_INVALID_RUN_ID")
    win = os.name == "nt" if windows is None else windows
    scan = scanner or windows_process_rows
    kill_tree = tree_killer or terminate_windows_tree
    result = {
        "run_id": run_id, "role_exit_codes": {}, "errors": [],
        "forced_roles": [], "orphan_pids": [], "orphan_killed": [],
        "ambiguous_pids": [], "remaining_owned_pids": [],
        "platform": "WINDOWS_PROCESS_TREE" if win else "PARENT_HANDLES_ONLY",
        "verified": False,
    }
    # Signal clients first, then the authoritative server, exactly as before.
    for roles in (("a", "b"), ("server",)):
        for role in roles:
            if role not in processes:
                continue
            try:
                (root / role / "stop.signal").touch()
            except OSError:
                result["errors"].append(f"{role}: STOP_SIGNAL_FAILED")
        for role in roles:
            proc = processes.get(role)
            if proc is None:
                continue
            try:
                proc.wait(timeout=wait_grace_s)
            except subprocess.TimeoutExpired:
                result["forced_roles"].append(role)
                result["errors"].append(f"{role}: GRACEFUL_SHUTDOWN_TIMEOUT")
                try:
                    proc.terminate()
                except OSError:
                    result["errors"].append(f"{role}: TERMINATE_FAILED")
                try:
                    proc.wait(timeout=wait_terminate_s)
                except subprocess.TimeoutExpired:
                    try:
                        proc.kill()
                        proc.wait(timeout=wait_terminate_s)
                    except (OSError, subprocess.TimeoutExpired):
                        result["errors"].append(f"{role}: KILL_FAILED")
            except OSError:
                result["errors"].append(f"{role}: WAIT_FAILED")
            if proc.poll() is None:
                result["errors"].append(f"{role}: LIVE_PARENT_AFTER_SHUTDOWN")
                try:
                    proc.kill()
                    proc.wait(timeout=wait_terminate_s)
                except (OSError, subprocess.TimeoutExpired):
                    result["errors"].append(f"{role}: FINAL_PARENT_KILL_FAILED")
            result["role_exit_codes"][role] = proc.poll()

    if win:
        try:
            rows = scan(run_id)
            own, ambiguous = select_windows_owned_godot(rows, run_id, godot_binary)
            result["orphan_pids"] = own
            result["ambiguous_pids"] = ambiguous
            if ambiguous:
                result["errors"].append("AMBIGUOUS_GODOT_PROCESS_NOT_KILLED")
            for pid in own:
                try:
                    kill_tree(pid)
                    result["orphan_killed"].append(pid)
                except (OSError, subprocess.TimeoutExpired, RuntimeError):
                    result["errors"].append(f"OWNED_GODOT_TREE_KILL_FAILED:{pid}")
            if own:
                # Query a second time to certify next GUI arm is not polluted.
                # Child main exe may take a moment to exit after taskkill.
                time.sleep(.3)
            survivors, unverified = select_windows_owned_godot(
                scan(run_id), run_id, godot_binary)
            result["remaining_owned_pids"] = survivors
            result["ambiguous_pids"] = sorted(set(ambiguous + unverified))
            if survivors:
                result["errors"].append("OWNED_GODOT_PROCESSES_REMAIN")
            if unverified:
                result["errors"].append("UNVERIFIED_GODOT_PROCESS_REMAINS")
            if own:
                # Even if cleanup succeeded, the current run is not accepted
                # as a clean isolation proof; the NEXT run can start safely.
                result["errors"].append("OWNED_GODOT_ORPHAN_RECOVERED")
            result["verified"] = not survivors and not result["ambiguous_pids"]
        except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired,
                json.JSONDecodeError) as exc:
            result["errors"].append("WINDOWS_PROCESS_CLEANUP_UNVERIFIED:" +
                                    type(exc).__name__)
    else:
        # Explicitly do not claim a process-tree check on unsupported OS.
        result["verified"] = all(p.poll() is not None for p in processes.values())
    return result

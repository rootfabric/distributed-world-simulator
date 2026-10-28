#!/usr/bin/env python3
"""Read-only Windows PID/creation-time inventory. NEVER terminate any process.

Collect three independent snapshots AFTER an existing harness returns. Compare
actual main-engine PIDs from trace headers with wrapper PIDs in manifests.
A PID alone cannot prove ownership: Windows may reuse it. Record creation time,
parent PID, executable and command-line markers; do not assert cleanup fixed.
Secrets in automation-control-token arguments are redacted before any disk write.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024*1024), b""):
            h.update(chunk)
    return h.hexdigest()


def sanitize_command(value: str) -> str:
    if not isinstance(value, str):
        raise ValueError("COMMAND_LINE_NOT_STRING")
    # Covers --automation-control-token=value, quoted value, and split option.
    return re.sub(r'(?i)(--automation-control-token(?:=|\s+))(?:"[^"\r\n]*"|[^\s"\r\n]+)',
                  r'\1<redacted>', value)


def evidence_identity(root: Path) -> dict:
    path = root/"manifest.json"
    before = sha(path)
    m = json.loads(path.read_text(encoding="utf-8-sig"))
    run_id = m.get("run_id")
    if not isinstance(run_id, str) or not re.fullmatch(r"[0-9a-f]{16}", run_id):
        raise ValueError("INVALID_RUN_ID:"+str(root))
    role_pids = {}
    for role in ("server", "a", "b"):
        trace = root/role/"trace.jsonl"
        with trace.open(encoding="utf-8") as f:
            header = json.loads(f.readline(1024*1024))
        data = header.get("data", {})
        if (header.get("kind") != "header" or data.get("role") != role
                or data.get("run_id") != run_id
                or type(data.get("pid")) is not int or data["pid"] <= 0):
            raise ValueError("INVALID_TRACE_PID_HEADER:"+role)
        role_pids[role] = data["pid"]
    wrappers = m.get("pids", {})
    if not isinstance(wrappers, dict) or any(type(v) is not int or v <= 0 for v in wrappers.values()):
        raise ValueError("INVALID_WRAPPER_PID_MAP")
    if before != sha(path):
        raise ValueError("MANIFEST_CHANGED_DURING_READ")
    return {"root": str(root.resolve()), "manifest_sha256": before,
            "run_id": run_id, "product_identity": m.get("identity", {}),
            "wrapper_pids": wrappers, "trace_header_main_pids": role_pids,
            "original_cleanup_report": m.get("cleanup", {}),
            "original_errors": m.get("errors", [])}


def query_rows(expected_pids: list[int]) -> list[dict]:
    if os.name != "nt":
        raise RuntimeError("WINDOWS_REQUIRED_FOR_CIM_INVENTORY")
    shell = shutil.which("pwsh") or shutil.which("powershell")
    if not shell:
        raise RuntimeError("POWERSHELL_NOT_FOUND")
    env = dict(os.environ)
    env["DWS_READONLY_EXPECTED_PIDS"] = json.dumps(expected_pids)
    script = r'''
$ErrorActionPreference = 'Stop'
$ids = @($env:DWS_READONLY_EXPECTED_PIDS | ConvertFrom-Json)
$rows = @(Get-CimInstance Win32_Process -ErrorAction Stop |
  Where-Object { $_.Name -match '(?i)^godot.*\.exe$' -or $ids -contains [int]$_.ProcessId } |
  ForEach-Object {
    [pscustomobject]@{
      pid = [int]$_.ProcessId
      parent_pid = [int]$_.ParentProcessId
      creation_utc = $(if ($_.CreationDate) { $_.CreationDate.ToUniversalTime().ToString('o') } else { $null })
      session_id = [int]$_.SessionId
      executable = [string]$_.ExecutablePath
      name = [string]$_.Name
      command_line = [string]$_.CommandLine
    }
  })
ConvertTo-Json -InputObject $rows -Compress -Depth 5
'''
    p = subprocess.run([shell, "-NoProfile", "-NonInteractive", "-Command", script],
                       env=env, capture_output=True, text=True, encoding="utf-8",
                       errors="replace", timeout=35, check=False)
    if p.returncode != 0:
        raise RuntimeError("CIM_INVENTORY_FAILED_EXIT_"+str(p.returncode))
    rows = json.loads(p.stdout.lstrip("\ufeff").strip())
    if not isinstance(rows, list) or len(rows) > 512:
        raise ValueError("INVALID_CIM_LIST")
    return rows


def classify_rows(rows: list[dict], evidence: list[dict]) -> list[dict]:
    output = []
    expected = {p for e in evidence for p in
                list(e["wrapper_pids"].values())+list(e["trace_header_main_pids"].values())}
    for row in rows:
        if not isinstance(row, dict) or type(row.get("pid")) is not int or row["pid"] <= 0:
            raise ValueError("INVALID_INVENTORY_PID")
        command = row.get("command_line")
        if not isinstance(command, str):
            raise ValueError("INVALID_INVENTORY_COMMAND")
        match = []
        for e in evidence:
            rid = re.escape(e["run_id"])
            if re.search(r'--instance-id(?:=|\s+)"?'+rid+r'(?=$|[\s"])', command):
                match.append(e["run_id"])
        safe = {k: row.get(k) for k in
                ("pid", "parent_pid", "creation_utc", "session_id", "executable", "name")}
        safe.update(command_line_redacted=sanitize_command(command),
                    matching_instance_markers=match,
                    pid_seen_in_old_evidence=row["pid"] in expected,
                    ownership_verdict="UNPROVEN_READ_ONLY_NO_KILL")
        output.append(safe)
    return output


def collect(roots: list[Path], console: Path, main_exe: Path, output: Path) -> dict:
    dest = output.resolve()
    if dest.exists() or any(dest.is_relative_to(r.resolve()) for r in roots):
        raise ValueError("OUTPUT_MUST_BE_NEW_AND_OUTSIDE_OLD_EVIDENCE")
    evidence = [evidence_identity(r.resolve()) for r in roots]
    pids = sorted({pid for e in evidence for pid in
                   list(e["wrapper_pids"].values())+list(e["trace_header_main_pids"].values())})
    binaries = {"console": {"path": str(console.resolve()), "sha256": sha(console)},
                "main": {"path": str(main_exe.resolve()), "sha256": sha(main_exe)}}
    snapshots = []
    for i in range(3):
        if i:
            time.sleep(1.0)
        snapshots.append({"at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
                          "processes": classify_rows(query_rows(pids), evidence)})
    # Historical PID/headers are not enough to identify a live process safely.
    result = {"schema": "dws.r31bp21.readonly_process_inventory.v1",
              "verdict": "INVENTORY_ONLY_B3_NOT_CLOSED", "analyzer_sha256": sha(Path(__file__)),
              "evidence": evidence, "binary_files": binaries, "snapshots": snapshots,
              "warnings": ["This tool never calls taskkill or terminates anything.",
                           "PIDs can be reused; match creation time, executable, command and original spawn ledger before deciding ownership.",
                           "Already manually killed processes cannot be reconstructed from a later empty inventory.",
                           "A current empty snapshot alone is not proof the harness cleaned an earlier run."]}
    dest.parent.mkdir(parents=True, exist_ok=True)
    with dest.open("x", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2, allow_nan=False)
    return result


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--run-root", type=Path, action="append", required=True)
    p.add_argument("--godot-console", type=Path, required=True)
    p.add_argument("--godot-main", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    a = p.parse_args()
    try:
        collect(a.run_root, a.godot_console, a.godot_main, a.output)
        print("INVENTORY_ONLY_B3_NOT_CLOSED: "+str(a.output))
        return 0
    except (OSError, ValueError, TypeError, RuntimeError, subprocess.TimeoutExpired) as exc:
        print("PROCESS_INVENTORY_INCONCLUSIVE: "+str(exc), file=__import__("sys").stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

"""Run-owned Windows 10+ Job Object. Opt-in tool, NOT a product change.

Uses PROC_THREAD_ATTRIBUTE_JOB_LIST at CreateProcessW (not the racy
CreateProcess -> AssignProcess sequence). CREATE_SUSPENDED permits an identity
receipt before the first user instruction. No breakaway flags, no inherited
job handle, no CIM substring/PID-only ownership, no global kill, no CPU limits.
Native tests MUST run on Windows; portable tests cannot prove Win32 behavior.
"""
from __future__ import annotations

import ctypes as C
import math
import os
from pathlib import Path
import subprocess
import time
from typing import Callable

DWORD = C.c_uint32
WORD = C.c_uint16
HANDLE = C.c_void_p
SIZE = C.c_size_t
BOOL = C.c_int
LPWSTR = C.c_wchar_p
PTR = C.c_void_p
KILL_ON_CLOSE = 0x2000
JOB_LIST = 0x2000D
HANDLE_LIST = 0x20002
CREATE_FLAGS = 0x00080000 | 0x00000400 | 0x00000004  # EX, Unicode, suspended
WAIT_TIMEOUT = 258
ERROR_MORE_DATA = 234


class BasicLimit(C.Structure):
    _fields_ = [("process_time", C.c_int64), ("job_time", C.c_int64),
                ("flags", DWORD), ("min_ws", SIZE), ("max_ws", SIZE),
                ("active_limit", DWORD), ("affinity", SIZE),
                ("priority", DWORD), ("scheduling", DWORD)]


class IOCounts(C.Structure):
    _fields_ = [(key, C.c_uint64) for key in
                ("read_ops", "write_ops", "other_ops", "read_bytes", "write_bytes", "other_bytes")]


class ExtendedLimit(C.Structure):
    _fields_ = [("basic", BasicLimit), ("io", IOCounts),
                ("process_memory", SIZE), ("job_memory", SIZE),
                ("peak_process", SIZE), ("peak_job", SIZE)]


class Accounting(C.Structure):
    _fields_ = [(key, C.c_int64) for key in ("user", "kernel", "period_user", "period_kernel")] + [
        (key, DWORD) for key in ("page_faults", "total", "active", "terminated")]


class Startup(C.Structure):
    _fields_ = [("cb", DWORD), ("reserved", LPWSTR), ("desktop", LPWSTR), ("title", LPWSTR)] + [
        (key, DWORD) for key in ("x", "y", "x_size", "y_size", "x_chars", "y_chars", "fill", "flags")] + [
        ("show", WORD), ("reserved_size", WORD), ("reserved_ptr", PTR),
        ("stdin", HANDLE), ("stdout", HANDLE), ("stderr", HANDLE)]


class StartupEx(C.Structure):
    _fields_ = [("basic", Startup), ("attributes", PTR)]


class ProcessInfo(C.Structure):
    _fields_ = [("process", HANDLE), ("thread", HANDLE), ("pid", DWORD), ("tid", DWORD)]


class FileTime(C.Structure):
    _fields_ = [("lo", DWORD), ("hi", DWORD)]


def redact_argv(argv: list[str]) -> list[str]:
    """Do not leak automation credentials into the independent receipt."""
    output, redact_next = [], False
    for arg in argv:
        if redact_next:
            output.append("<redacted>")
            redact_next = False
            continue
        key = arg.split("=", 1)[0].lower()
        secret = any(token in key for token in ("token", "password", "secret", "authorization"))
        if secret and key.startswith(("--", "/")):
            if "=" in arg:
                output.append(arg.split("=", 1)[0] + "=<redacted>")
            else:
                output.append(arg)
                redact_next = True
        else:
            output.append(arg)
    return output


def environment_block(env: dict[str, str]) -> str:
    rows = []
    for key, value in sorted(env.items(), key=lambda kv: kv[0].upper()):
        if not key or "\0" in key or "=" in key or "\0" in value:
            raise ValueError("JOB_INVALID_ENVIRONMENT")
        rows.append(key + "=" + value)
    return "\0".join(rows) + "\0\0"


def wait_empty(snapshot: Callable[[], dict], timeout: float,
               *, clock=time.monotonic, sleep=time.sleep) -> dict:
    if not math.isfinite(timeout) or timeout < 0:
        raise ValueError("JOB_INVALID_TIMEOUT")
    end = clock() + timeout
    while True:
        state = snapshot()  # query failure is never rewritten into an empty job
        if state["active"] == 0 and not state["pids"]:
            return state
        remaining = end - clock()
        if remaining <= 0:
            return state
        sleep(min(.05, remaining))


class Kernel:
    def __init__(self):
        if os.name != "nt":
            raise OSError("WINDOWS_NATIVE_JOB_REQUIRED")
        self.k = C.WinDLL("kernel32", use_last_error=True)
        signatures = {
            "CreateJobObjectW": (HANDLE, [PTR, LPWSTR]),
            "CloseHandle": (BOOL, [HANDLE]),
            "SetInformationJobObject": (BOOL, [HANDLE, C.c_int, PTR, DWORD]),
            "QueryInformationJobObject": (BOOL, [HANDLE, C.c_int, PTR, DWORD, PTR]),
            "TerminateJobObject": (BOOL, [HANDLE, DWORD]),
            "InitializeProcThreadAttributeList": (BOOL, [PTR, DWORD, DWORD, C.POINTER(SIZE)]),
            "UpdateProcThreadAttribute": (BOOL, [PTR, DWORD, SIZE, PTR, SIZE, PTR, PTR]),
            "DeleteProcThreadAttributeList": (None, [PTR]),
            "CreateProcessW": (BOOL, [LPWSTR, LPWSTR, PTR, PTR, BOOL, DWORD, PTR, LPWSTR, PTR, PTR]),
            "ResumeThread": (DWORD, [HANDLE]),
            "WaitForSingleObject": (DWORD, [HANDLE, DWORD]),
            "GetExitCodeProcess": (BOOL, [HANDLE, C.POINTER(DWORD)]),
            "IsProcessInJob": (BOOL, [HANDLE, HANDLE, C.POINTER(BOOL)]),
            "GetProcessTimes": (BOOL, [HANDLE, PTR, PTR, PTR, PTR]),
            "QueryFullProcessImageNameW": (BOOL, [HANDLE, DWORD, LPWSTR, C.POINTER(DWORD)]),
            "OpenProcess": (HANDLE, [DWORD, BOOL, DWORD]),
            "GetCurrentProcess": (HANDLE, []),
            "DuplicateHandle": (BOOL, [HANDLE, HANDLE, HANDLE, C.POINTER(HANDLE), DWORD, BOOL, DWORD]),
        }
        for name, (restype, argtypes) in signatures.items():
            fn = getattr(self.k, name)
            fn.restype, fn.argtypes = restype, argtypes

    @staticmethod
    def check(value, label):
        if not value:
            raise OSError(C.get_last_error(), label)
        return value

    def close(self, handle):
        if handle:
            self.check(self.k.CloseHandle(handle), "CloseHandle")

    def identity(self, process, job=None) -> dict:
        born, exited, kernel, user = FileTime(), FileTime(), FileTime(), FileTime()
        self.check(self.k.GetProcessTimes(process, C.byref(born), C.byref(exited),
                                         C.byref(kernel), C.byref(user)), "GetProcessTimes")
        size = DWORD(32768)
        image = C.create_unicode_buffer(size.value)
        self.check(self.k.QueryFullProcessImageNameW(process, 0, image, C.byref(size)),
                   "QueryFullProcessImageNameW")
        result = {"creation_filetime_100ns": str((born.hi << 32) | born.lo),
                  "executable": image.value}
        if job is not None:
            member = BOOL()
            self.check(self.k.IsProcessInJob(process, job, C.byref(member)), "IsProcessInJob")
            result["member_of_this_job"] = bool(member.value)
        return result


class NativeProcess:
    def __init__(self, api: Kernel, info: ProcessInfo):
        self.api, self.handle, self.thread = api, info.process, info.thread
        self.pid, self.returncode = int(info.pid), None

    def resume(self):
        if not self.thread:
            raise RuntimeError("PROCESS_ALREADY_RESUMED")
        count = self.api.k.ResumeThread(self.thread)
        if count == 0xFFFFFFFF:
            raise OSError(C.get_last_error(), "ResumeThread")
        self.api.close(self.thread)
        self.thread = None
        if count != 1:
            raise RuntimeError("UNEXPECTED_SUSPEND_COUNT")

    def wait(self, timeout: float | None = None) -> int:
        if not self.handle:
            raise RuntimeError("PROCESS_HANDLE_CLOSED")
        if timeout is not None and (not math.isfinite(timeout) or timeout < 0):
            raise ValueError("PROCESS_INVALID_TIMEOUT")
        ms = 0xFFFFFFFF if timeout is None else min(0xFFFFFFFE, math.ceil(timeout * 1000))
        result = self.api.k.WaitForSingleObject(self.handle, ms)
        if result == WAIT_TIMEOUT:
            raise subprocess.TimeoutExpired("job-owned process", timeout)
        if result != 0:
            raise OSError(C.get_last_error(), "WaitForSingleObject")
        code = DWORD()
        self.api.check(self.api.k.GetExitCodeProcess(self.handle, C.byref(code)), "GetExitCodeProcess")
        self.returncode = int(code.value)
        return self.returncode

    def poll(self):
        try:
            return self.wait(0)
        except subprocess.TimeoutExpired:
            return None

    def close(self):
        self.api.close(self.thread)
        self.thread = None
        self.api.close(self.handle)
        self.handle = None


class OwnedJob:
    """One unnamed, non-inheritable Job; never adopt an arbitrary existing PID."""
    def __init__(self):
        self.api = Kernel()
        self.handle = self.api.check(self.api.k.CreateJobObjectW(None, None), "CreateJobObjectW")
        self.processes: list[NativeProcess] = []
        try:
            limits = ExtendedLimit()
            limits.basic.flags = KILL_ON_CLOSE  # no CPU, priority, memory or breakaway changes
            self.api.check(self.api.k.SetInformationJobObject(
                self.handle, 9, C.byref(limits), C.sizeof(limits)), "SetInformationJobObject")
        except BaseException:
            self.close()
            raise

    def create_suspended(self, argv: list[str], *, cwd: Path, log: Path,
                         env: dict[str, str] | None = None) -> tuple[NativeProcess, dict]:
        import msvcrt  # Windows-only, keep module import portable
        if not self.handle or not argv or any(not isinstance(x, str) or "\0" in x for x in argv):
            raise ValueError("JOB_INVALID_CREATE_REQUEST")
        exe = Path(argv[0]).resolve(strict=True)
        cwd = cwd.resolve(strict=True)
        log.parent.mkdir(parents=True, exist_ok=True)
        environment = C.create_unicode_buffer(environment_block(dict(os.environ) if env is None else env))
        command = C.create_unicode_buffer(subprocess.list2cmdline([str(exe)] + argv[1:]))
        api = self.api
        duplicates = []
        attributes = None
        initialized = False
        proc = None
        # Only stdin/out handles can be inherited. The private job handle is NOT
        # in this list, so controller death closes the LAST job handle.
        with open(os.devnull, "rb") as stdin, log.open("xb") as output:
            try:
                current = api.k.GetCurrentProcess()
                for stream in (stdin, output):
                    duplicate = HANDLE()
                    api.check(api.k.DuplicateHandle(current, msvcrt.get_osfhandle(stream.fileno()),
                        current, C.byref(duplicate), 0, True, 2), "DuplicateHandle")
                    duplicates.append(duplicate.value)
                size = SIZE()
                api.k.InitializeProcThreadAttributeList(None, 2, 0, C.byref(size))
                if not size.value:
                    raise OSError(C.get_last_error(), "AttributeListSize")
                attributes = C.create_string_buffer(size.value)
                api.check(api.k.InitializeProcThreadAttributeList(attributes, 2, 0, C.byref(size)),
                          "InitializeProcThreadAttributeList")
                initialized = True
                jobs = (HANDLE * 1)(self.handle)
                handles = (HANDLE * 2)(*duplicates)
                api.check(api.k.UpdateProcThreadAttribute(attributes, 0, JOB_LIST,
                    jobs, C.sizeof(jobs), None, None), "UpdateProcThreadAttribute(JOB_LIST)")
                api.check(api.k.UpdateProcThreadAttribute(attributes, 0, HANDLE_LIST,
                    handles, C.sizeof(handles), None, None), "UpdateProcThreadAttribute(HANDLE_LIST)")
                si = StartupEx()
                si.basic.cb, si.basic.flags = C.sizeof(si), 0x100  # STARTF_USESTDHANDLES
                si.basic.stdin, si.basic.stdout, si.basic.stderr = duplicates[0], duplicates[1], duplicates[1]
                si.attributes = C.cast(attributes, PTR)
                info = ProcessInfo()
                api.check(api.k.CreateProcessW(str(exe), command, None, None, True, CREATE_FLAGS,
                    environment, str(cwd), C.byref(si), C.byref(info)), "CreateProcessW(job-list)")
                proc = NativeProcess(api, info)
                self.processes.append(proc)
                identity = api.identity(proc.handle, self.handle)
                if not identity["member_of_this_job"]:
                    raise RuntimeError("CREATED_PROCESS_NOT_IN_OWN_JOB")
                identity.update(pid=proc.pid, command_requested=redact_argv([str(exe)] + argv[1:]),
                                cwd=str(cwd), state="SUSPENDED_BEFORE_USER_CODE")
                return proc, identity
            except BaseException:
                # Every successful create was assigned atomically by the OS;
                # terminating this private job can never target another run.
                if proc is not None:
                    self.terminate()
                raise
            finally:
                if initialized:
                    api.k.DeleteProcThreadAttributeList(attributes)
                for handle in duplicates:
                    api.close(handle)

    def snapshot(self) -> dict:
        if not self.handle:
            raise RuntimeError("JOB_CLOSED")
        capacity = 16
        while capacity <= 4096:
            class ProcessList(C.Structure):
                _fields_ = [("assigned", DWORD), ("listed", DWORD), ("pids", SIZE * capacity)]
            values = ProcessList()
            ok = self.api.k.QueryInformationJobObject(self.handle, 3, C.byref(values), C.sizeof(values), None)
            if not ok and C.get_last_error() != ERROR_MORE_DATA:
                raise OSError(C.get_last_error(), "QueryInformationJobObject(process-list)")
            if ok and values.assigned <= values.listed <= capacity:
                pids = [int(x) for x in values.pids[:values.listed]]
                break
            capacity = max(capacity * 2, int(values.assigned))
        else:
            raise RuntimeError("JOB_PROCESS_LIST_BUDGET_EXCEEDED")
        accounting = Accounting()
        self.api.check(self.api.k.QueryInformationJobObject(self.handle, 1,
            C.byref(accounting), C.sizeof(accounting), None), "QueryInformationJobObject(accounting)")
        return {"pids": pids, "active": int(accounting.active),
                "total": int(accounting.total), "terminated": int(accounting.terminated)}

    def identities(self, pids: list[int]) -> list[dict]:
        rows = []
        for pid in pids:
            handle = self.api.k.OpenProcess(0x1000 | 0x100000, False, pid)
            if not handle:
                rows.append({"pid": pid, "identity": "UNRESOLVED_OR_EXITED",
                             "winerror": C.get_last_error()})
                continue
            try:
                identity = self.api.identity(handle, self.handle)
                identity["pid"] = pid
                rows.append(identity)
            finally:
                self.api.close(handle)
        return rows

    def terminate(self):
        if self.handle:
            self.api.check(self.api.k.TerminateJobObject(self.handle, 0xE31B), "TerminateJobObject")

    def finish(self, grace: float = 3.0, timeout: float = 10.0) -> dict:
        state = wait_empty(self.snapshot, grace)
        forced = state["active"] != 0 or bool(state["pids"])
        rows = self.identities(state["pids"]) if forced else []
        if forced:
            self.terminate()
        final = wait_empty(self.snapshot, timeout)
        verified = final["active"] == 0 and not final["pids"]
        return {"isolation_verified": verified, "natural_exit": not forced,
                "forced_job_termination": forced, "before": state, "remaining_identity": rows,
                "after": final,
                "acceptance": "CLEAN_JOB_EMPTY" if verified and not forced else
                              "FORCED_CLEANUP_NOT_ACCEPTED" if verified else "JOB_NOT_EMPTY"}

    def close(self):
        # This is the crash/exception safety net, not evidence of observed empty
        # process membership; only finish() can provide that separate receipt.
        if self.handle:
            self.api.close(self.handle)
            self.handle = None
        for proc in self.processes:
            proc.close()
        self.processes.clear()

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()

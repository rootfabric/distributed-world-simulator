"""Static guard for optional test evidence sinks.

A test's product/diagnostic verdict must not depend on an optional evidence
output path being configured. If a path is configured, failure to write the
requested evidence remains fail-closed.
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

EVIDENCE_ENV_SUFFIXES = ("_RESULT", "_REPORT", "_EVIDENCE", "_OUTPUT", "_MANIFEST")
FAILURE_CODE = "OPTIONAL_EVIDENCE_SINK_CONTROLS_VERDICT"

_GD_ENV = re.compile(
    r'\bvar\s+(?P<name>[A-Za-z_]\w*)\s*(?::[^=]+)?\s*(?::=|=)\s*'
    r'OS\.get_environment\("(?P<env>[A-Z0-9_]+)"\)'
)
_PY_ENV = re.compile(
    r'\b(?P<name>[A-Za-z_]\w*)\s*=\s*os\.(?:environ\.get|getenv)\('
    r'["\'](?P<env>[A-Z0-9_]+)["\']'
)


@dataclass(frozen=True)
class EvidenceSinkViolation:
    path: str
    line: int
    env: str
    flag: str
    code: str = FAILURE_CODE

    def render(self) -> str:
        return f"{self.code}:{self.path}:{self.line}:{self.env}:{self.flag}"


def _is_evidence_env(name: str) -> bool:
    return name.endswith(EVIDENCE_ENV_SUFFIXES)


def _indent(line: str) -> int:
    expanded = line.expandtabs(4)
    return len(expanded) - len(expanded.lstrip(" "))


def _guard_body(lines: list[str], index: int) -> str:
    line = lines[index]
    _, _, tail = line.partition(":")
    chunks = [tail] if tail.strip() else []
    base_indent = _indent(line)
    for following in lines[index + 1 :]:
        if not following.strip():
            continue
        if _indent(following) <= base_indent:
            break
        chunks.append(following)
    return "\n".join(chunks)


def _termination_mentions(lines: list[str], start: int, flag: str, language: str) -> bool:
    tokens = ("quit(", "get_tree().quit(") if language == "gd" else ("SystemExit(", "sys.exit(")
    for i in range(start, len(lines)):
        if not any(token in lines[i] for token in tokens):
            continue
        snippet = "\n".join(lines[i : min(len(lines), i + 12)])
        if re.search(rf"\b{re.escape(flag)}\b", snippet):
            return True
    return False


def _false_declared_before(lines: list[str], end: int, flag: str, language: str) -> bool:
    if language == "gd":
        pattern = re.compile(rf"\bvar\s+{re.escape(flag)}\s*(?::[^=]+)?\s*(?::=|=)\s*false\b")
    else:
        pattern = re.compile(rf"\b{re.escape(flag)}\s*=\s*False\b")
    return any(pattern.search(line) for line in lines[:end])


def _assigned_flags(body: str) -> set[str]:
    return set(re.findall(r"\b([A-Za-z_]\w*)\s*=\s*(?!=)", body))


def _scan_gdscript(path: str, source: str) -> list[EvidenceSinkViolation]:
    lines = source.splitlines()
    violations: list[EvidenceSinkViolation] = []
    env_vars: dict[str, tuple[str, int]] = {}
    for i, line in enumerate(lines):
        match = _GD_ENV.search(line)
        if match and _is_evidence_env(match.group("env")):
            env_vars[match.group("name")] = (match.group("env"), i)

    for output, (env, _) in env_vars.items():
        guard = re.compile(rf"\bif\s+not\s+{re.escape(output)}\.is_empty\(\)\s*:")
        for i, line in enumerate(lines):
            if not guard.search(line):
                continue
            for flag in _assigned_flags(_guard_body(lines, i)):
                if (
                    _false_declared_before(lines, i, flag, "gd")
                    and _termination_mentions(lines, i, flag, "gd")
                ):
                    violations.append(EvidenceSinkViolation(path, i + 1, env, flag))
    return violations


def _scan_python(path: str, source: str) -> list[EvidenceSinkViolation]:
    lines = source.splitlines()
    violations: list[EvidenceSinkViolation] = []
    env_vars: dict[str, tuple[str, int]] = {}
    for i, line in enumerate(lines):
        match = _PY_ENV.search(line)
        if match and _is_evidence_env(match.group("env")):
            env_vars[match.group("name")] = (match.group("env"), i)

    for output, (env, _) in env_vars.items():
        guard = re.compile(
            rf"\bif\s+(?:{re.escape(output)}|bool\({re.escape(output)}\)|"
            rf"{re.escape(output)}\s*!=\s*['\"][\"'])\s*:"
        )
        for i, line in enumerate(lines):
            if not guard.search(line):
                continue
            for flag in _assigned_flags(_guard_body(lines, i)):
                if (
                    _false_declared_before(lines, i, flag, "py")
                    and _termination_mentions(lines, i, flag, "py")
                ):
                    violations.append(EvidenceSinkViolation(path, i + 1, env, flag))
    return violations


def find_optional_evidence_sink_violations(path: str, source: str) -> list[EvidenceSinkViolation]:
    suffix = Path(path).suffix.lower()
    if suffix == ".gd":
        return _scan_gdscript(path, source)
    if suffix == ".py":
        return _scan_python(path, source)
    return []


def guarded_test_path(path: str) -> bool:
    normalized = path.replace("\\", "/")
    if not normalized.startswith("tests/"):
        return False
    if normalized.startswith("tests/harness/"):
        return False
    return Path(normalized).suffix.lower() in {".gd", ".py"}


def validate_optional_evidence_sinks(root: Path, paths: Iterable[str]) -> list[str]:
    checked: list[str] = []
    violations: list[EvidenceSinkViolation] = []
    for path in sorted(set(paths)):
        if not guarded_test_path(path):
            continue
        file_path = root / path
        if not file_path.exists():
            continue
        checked.append(path)
        violations.extend(
            find_optional_evidence_sink_violations(path, file_path.read_text(encoding="utf-8"))
        )
    if violations:
        rendered = "|".join(item.render() for item in violations)
        raise RuntimeError(f"{FAILURE_CODE}:{rendered}")
    return checked

from __future__ import annotations

import hashlib
import json
import os
import random
import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence


REQUIRED_EVIDENCE_FIELDS = (
    "schema",
    "scenario_id",
    "seed",
    "sequence",
    "kind",
    "process_role",
    "process_id",
    "process_incarnation",
)


class HarnessContractError(ValueError):
    """Raised when research-harness evidence/config violates the I1 contract."""


@dataclass(frozen=True)
class LinkProfile:
    latency_ms: int = 0
    jitter_ms: int = 0
    loss_rate: float = 0.0
    duplicate_rate: float = 0.0
    reorder_rate: float = 0.0
    bandwidth_kbps: int = 0
    queue_limit_packets: int = 0

    def __post_init__(self) -> None:
        if self.latency_ms < 0 or self.jitter_ms < 0:
            raise HarnessContractError("latency/jitter must be non-negative")
        for name, value in (
            ("loss_rate", self.loss_rate),
            ("duplicate_rate", self.duplicate_rate),
            ("reorder_rate", self.reorder_rate),
        ):
            if value < 0.0 or value > 1.0:
                raise HarnessContractError(f"{name} must be in [0, 1]")
        if self.bandwidth_kbps < 0 or self.queue_limit_packets < 0:
            raise HarnessContractError("bandwidth/queue limit must be non-negative")

    @classmethod
    def from_mapping(cls, raw: Mapping[str, Any]) -> "LinkProfile":
        return cls(
            latency_ms=int(raw.get("latency_ms", 0)),
            jitter_ms=int(raw.get("jitter_ms", 0)),
            loss_rate=float(raw.get("loss_rate", 0.0)),
            duplicate_rate=float(raw.get("duplicate_rate", 0.0)),
            reorder_rate=float(raw.get("reorder_rate", 0.0)),
            bandwidth_kbps=int(raw.get("bandwidth_kbps", 0)),
            queue_limit_packets=int(raw.get("queue_limit_packets", 0)),
        )


@dataclass(frozen=True)
class DeliveryDecision:
    duplicate_ordinal: int
    delay_ms: int
    reordered: bool


class DeterministicLinkPlanner:
    """Order-independent deterministic packet fault decisions for a directed logical link."""

    def __init__(self, scenario_seed: int) -> None:
        self.scenario_seed = int(scenario_seed)

    def _rng(self, link_id: str, packet_index: int) -> random.Random:
        material = f"{self.scenario_seed}:{link_id}:{int(packet_index)}".encode("utf-8")
        digest = hashlib.sha256(material).digest()
        return random.Random(int.from_bytes(digest[:8], "big"))

    def plan_packet(
        self,
        link_id: str,
        packet_index: int,
        profile: LinkProfile,
    ) -> list[DeliveryDecision]:
        rng = self._rng(link_id, packet_index)
        if rng.random() < profile.loss_rate:
            return []

        jitter = 0
        if profile.jitter_ms:
            jitter = rng.randint(-profile.jitter_ms, profile.jitter_ms)
        delay = max(0, profile.latency_ms + jitter)

        reordered = rng.random() < profile.reorder_rate
        if reordered:
            # I1-A models reorder as deterministic extra hold-back. It does not
            # yet claim wire-level transport emulation.
            delay += max(1, profile.jitter_ms or 1)

        deliveries = [DeliveryDecision(0, delay, reordered)]
        if rng.random() < profile.duplicate_rate:
            duplicate_delay = delay + rng.randint(0, max(1, profile.jitter_ms + 1))
            deliveries.append(DeliveryDecision(1, duplicate_delay, reordered))
        return deliveries


@dataclass
class EvidenceRecorder:
    scenario_id: str
    seed: int
    events: list[dict[str, Any]] = field(default_factory=list)
    _sequence: int = 0

    def record(
        self,
        kind: str,
        *,
        process_role: str,
        process_id: str,
        process_incarnation: int,
        **fields: Any,
    ) -> dict[str, Any]:
        self._sequence += 1
        event: dict[str, Any] = {
            "schema": "distributed_world_simulator.sm1_i1_evidence.v1",
            "scenario_id": self.scenario_id,
            "seed": int(self.seed),
            "sequence": self._sequence,
            "kind": str(kind),
            "process_role": str(process_role),
            "process_id": str(process_id),
            "process_incarnation": int(process_incarnation),
        }
        event.update(fields)
        validate_evidence_event(event)
        self.events.append(event)
        return event

    def to_json_lines(self) -> str:
        return "".join(json.dumps(event, sort_keys=True) + "\n" for event in self.events)


def validate_evidence_event(event: Mapping[str, Any]) -> None:
    missing = [field for field in REQUIRED_EVIDENCE_FIELDS if field not in event]
    if missing:
        raise HarnessContractError(f"evidence missing required fields: {missing}")
    if event["schema"] != "distributed_world_simulator.sm1_i1_evidence.v1":
        raise HarnessContractError("unexpected evidence schema")
    if not str(event["scenario_id"]).strip():
        raise HarnessContractError("scenario_id must be non-empty")
    if int(event["sequence"]) < 1:
        raise HarnessContractError("sequence must be >= 1")
    if int(event["process_incarnation"]) < 1:
        raise HarnessContractError("process_incarnation must be >= 1")


class GlobalEvidenceAnalyzer:
    """Global, cross-process oracle analyzer. It never decides canonical ownership."""

    ORACLE_KEYS = (
        "writer_violations",
        "identity_changes_due_to_topology",
        "stale_owner_mutations_accepted",
        "duplicate_canonical_commits",
        "projection_canonical_writes",
        "unexpected_revision_rollback",
    )

    def analyze(self, events: Iterable[Mapping[str, Any]]) -> dict[str, Any]:
        ordered = sorted(
            (dict(event) for event in events),
            key=lambda item: (str(item.get("scenario_id", "")), int(item.get("sequence", 0))),
        )
        for event in ordered:
            validate_evidence_event(event)

        counters = {key: 0 for key in self.ORACLE_KEYS}
        active_writers: dict[tuple[str, str], set[str]] = {}
        identities: dict[str, str] = {}
        accepted_commits: dict[str, set[str]] = {}
        max_revision: dict[str, int] = {}

        for event in ordered:
            kind = str(event["kind"])
            if kind == "WRITER_STATE":
                observation_id = str(event.get("observation_id", event["sequence"]))
                subject_id = _required_text(event, "subject_id")
                authority_id = _required_text(event, "authority_id")
                key = (observation_id, subject_id)
                writers = active_writers.setdefault(key, set())
                if bool(event.get("active_writer", False)):
                    writers.add(authority_id)
            elif kind == "IDENTITY_STATE":
                subject_id = _required_text(event, "subject_id")
                identity_id = _required_text(event, "identity_id")
                previous = identities.setdefault(subject_id, identity_id)
                if previous != identity_id:
                    counters["identity_changes_due_to_topology"] += 1
            elif kind == "MUTATION_RESULT":
                if bool(event.get("stale_owner", False)) and bool(event.get("accepted", False)):
                    counters["stale_owner_mutations_accepted"] += 1
            elif kind == "CANONICAL_COMMIT":
                if bool(event.get("accepted", True)):
                    operation_id = _required_text(event, "operation_id")
                    commit_id = _required_text(event, "commit_id")
                    commits = accepted_commits.setdefault(operation_id, set())
                    if commit_id not in commits and commits:
                        counters["duplicate_canonical_commits"] += 1
                    commits.add(commit_id)
            elif kind == "PROJECTION_WRITE_RESULT":
                if bool(event.get("canonical_write_accepted", False)):
                    counters["projection_canonical_writes"] += 1
            elif kind == "REVISION_STATE":
                subject_id = _required_text(event, "subject_id")
                revision = int(event.get("state_revision", -1))
                if revision < 0:
                    raise HarnessContractError("state_revision must be >= 0")
                previous = max_revision.get(subject_id)
                if previous is not None and revision < previous:
                    counters["unexpected_revision_rollback"] += 1
                max_revision[subject_id] = max(
                    revision, previous if previous is not None else revision
                )

        counters["writer_violations"] = sum(
            max(0, len(writers) - 1) for writers in active_writers.values()
        )
        passed = all(counters[key] == 0 for key in self.ORACLE_KEYS)
        return {
            "schema": "distributed_world_simulator.sm1_i1_report.v1",
            "events_analyzed": len(ordered),
            "oracles": counters,
            "result": "PASS" if passed else "FAIL",
        }


def _required_text(event: Mapping[str, Any], field: str) -> str:
    value = str(event.get(field, "")).strip()
    if not value:
        raise HarnessContractError(f"{field} must be non-empty for {event.get('kind')}")
    return value


@dataclass
class ProcessSpec:
    role: str
    process_id: str
    command: Sequence[str]
    cwd: str | None = None
    env: Mapping[str, str] | None = None


@dataclass
class ManagedProcess:
    spec: ProcessSpec
    incarnation: int = 0
    process: subprocess.Popen[str] | None = None

    def start(self) -> int:
        if self.process is not None and self.process.poll() is None:
            raise HarnessContractError(f"process already running: {self.spec.process_id}")
        self.incarnation += 1
        env = os.environ.copy()
        if self.spec.env:
            env.update({str(key): str(value) for key, value in self.spec.env.items()})
        env.update(
            {
                "DWS_I1_RESEARCH_ONLY": "1",
                "DWS_I1_PROCESS_ROLE": self.spec.role,
                "DWS_I1_PROCESS_ID": self.spec.process_id,
                "DWS_I1_PROCESS_INCARNATION": str(self.incarnation),
            }
        )
        self.process = subprocess.Popen(
            list(self.spec.command),
            cwd=self.spec.cwd,
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            text=True,
        )
        return self.incarnation

    def is_alive(self) -> bool:
        return self.process is not None and self.process.poll() is None

    def terminate(self, timeout_s: float = 2.0) -> None:
        if self.process is None:
            return
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=timeout_s)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=timeout_s)

    def restart(self) -> int:
        self.terminate()
        return self.start()


class ProcessSupervisor:
    """Research-only process lifecycle scaffold; no simulation ownership semantics."""

    def __init__(self) -> None:
        self._processes: dict[str, ManagedProcess] = {}

    def register(self, spec: ProcessSpec) -> ManagedProcess:
        if spec.process_id in self._processes:
            raise HarnessContractError(f"duplicate process_id: {spec.process_id}")
        managed = ManagedProcess(spec)
        self._processes[spec.process_id] = managed
        return managed

    def start(self, process_id: str) -> int:
        return self._processes[process_id].start()

    def restart(self, process_id: str) -> int:
        return self._processes[process_id].restart()

    def terminate(self, process_id: str) -> None:
        self._processes[process_id].terminate()

    def terminate_all(self) -> None:
        for managed in self._processes.values():
            managed.terminate()

    def status(self) -> dict[str, dict[str, Any]]:
        return {
            process_id: {
                "role": managed.spec.role,
                "incarnation": managed.incarnation,
                "alive": managed.is_alive(),
            }
            for process_id, managed in sorted(self._processes.items())
        }


def load_network_profiles(path: str | Path) -> dict[str, LinkProfile]:
    raw = json.loads(Path(path).read_text(encoding="utf-8"))
    if raw.get("schema") != "distributed_world_simulator.sm1_i1_network_profiles.v1":
        raise HarnessContractError("unexpected network profile schema")
    profiles = raw.get("profiles")
    if not isinstance(profiles, dict) or not profiles:
        raise HarnessContractError("profiles must be a non-empty object")
    return {name: LinkProfile.from_mapping(value) for name, value in profiles.items()}


def write_report(path: str | Path, report: Mapping[str, Any]) -> None:
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(
        json.dumps(dict(report), indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

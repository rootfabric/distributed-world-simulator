"""Native A8-backed entry point for A9; no alternate biological/authority writer."""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from .ecological_fidelity_v1 import FidelityRecord, FidelityError, binding, canonical, digest, require, MAX_RAW

GODOT_SHA256 = 'bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7'
GODOT_VERSION = '4.7.1.stable.double.custom_build.a13da4feb'
ERRORS = re.compile(r'SCRIPT ERROR|Parse Error|ERROR:|FAIL:|A9_NATIVE_FAIL')


class NativeA8:
    """Trusted local research coordinator, not a network/authentication service.

    The caller owns current durable A8/A9 acknowledgement anchors. Passing a
    formerly valid packet is not permission to publish over a newer durable tip.
    All native processes and inputs/outputs are retained under evidence_dir.
    """
    def __init__(self, root: Path, godot: Path, evidence_dir: Path):
        self.root = root.resolve(strict=True)
        self.godot = godot.resolve(strict=True)
        require((self.root / 'project.godot').is_file(), 'PROJECT_ROOT')
        require(digest(self.godot.read_bytes()) == GODOT_SHA256, 'GODOT_BINARY_SHA256')
        version = subprocess.check_output([str(self.godot), '--version'], text=True, timeout=30).strip()
        require(version == GODOT_VERSION, 'GODOT_BINARY_VERSION')
        self.evidence_dir = evidence_dir.resolve()
        require(self.evidence_dir.is_relative_to(self.root / 'artifacts'), 'EVIDENCE_MUST_BE_IN_ARTIFACTS')
        self.evidence_dir.mkdir(parents=True, exist_ok=True)
        self.runs: list[dict] = []

    def _invoke(self, operation: str, raw: bytes = b'', expected_sha: str = '', origin: str = '',
                entity_id: str = '', command: dict | None = None, received: bytes = b'', steps: int = 0) -> tuple[bytes, dict]:
        require(len(self.runs) < 2048, 'NATIVE_PROCESS_BUDGET')
        require(type(raw) is bytes and len(raw) <= MAX_RAW and type(received) is bytes and len(received) <= MAX_RAW, 'NATIVE_INPUT_BUDGET')
        directory = Path(tempfile.mkdtemp(prefix='native-', dir=self.evidence_dir))
        source_path = directory / 'source.json'
        if raw: source_path.write_bytes(raw)
        received_path = directory / 'received.json'
        if received: received_path.write_bytes(received)
        request = {'operation': operation, 'input': str(source_path) if raw else '',
                   'snapshot_hash': expected_sha, 'origin_hash': origin, 'entity_id': entity_id,
                   'command': {} if command is None else command, 'received': str(received_path) if received else '', 'steps': steps}
        request_path = directory / 'request.json'; response_path = directory / 'admission.json'
        encoded = canonical(request)
        require(len(encoded) <= 65536, 'NATIVE_REQUEST_BUDGET')
        request_path.write_bytes(encoded)
        cmd = [str(self.godot), '--headless', '--audio-driver', 'Dummy', '--path', str(self.root), '--script',
               'res://scripts/research/ecology/v2/fidelity_admission_v1.gd', '--', str(request_path), str(response_path)]
        log = directory / 'native.log'
        with log.open('wb') as f:
            result = subprocess.run(cmd, cwd=self.root, env=dict(os.environ, GODOT_SILENCE_ROOT_WARNING='1'),
                                    stdout=f, stderr=subprocess.STDOUT, timeout=600, check=False)
        text = log.read_text(encoding='utf-8-sig', errors='replace')
        entry = {'operation': operation, 'command': cmd, 'exit_code': result.returncode,
                 'log': log.relative_to(self.root).as_posix(), 'log_sha256': digest(log.read_bytes())}
        self.runs.append(entry)
        require(result.returncode == 0 and not ERRORS.search(text), 'NATIVE_EXECUTION_FAILED:' + text[-3000:])
        require(response_path.is_file() and response_path.stat().st_size <= 131072, 'NATIVE_RESPONSE_BUDGET')
        payload = Path(str(response_path) + '.snapshot')
        require(payload.is_file() and payload.stat().st_size <= MAX_RAW, 'NATIVE_SNAPSHOT_BUDGET')
        data = payload.read_bytes(); admission = json.loads(response_path.read_bytes())
        require('A9_NATIVE_PASS snapshot=' + digest(data) in text, 'NATIVE_SUCCESS_MARKER')
        require(admission.get('success') is True and admission.get('source', {}).get('snapshot_sha256') == digest(data), 'NATIVE_RESPONSE_BINDING')
        if operation != 'GENESIS':
            require(admission['source']['origin_sha256'] == origin, 'NATIVE_ORIGIN_CHANGED')
        if operation == 'ADMIT':
            require(data == raw and digest(data) == expected_sha, 'ADMISSION_MUTATED_INPUT')
        entry.update(snapshot_sha256=digest(data), admission_sha256=digest(response_path.read_bytes()))
        return data, admission

    def admit(self, raw: bytes, expected_sha: str, origin: str) -> dict:
        binding(raw, expected_sha, origin)
        return self._invoke('ADMIT', raw, expected_sha, origin)[1]

    def genesis(self, entity_id: str, steps: int = 0) -> FidelityRecord:
        require(type(steps) is int and 0 <= steps <= 16, 'GENESIS_STEP_BUDGET')
        data, result = self._invoke('GENESIS', entity_id=entity_id, steps=steps)
        return FidelityRecord.from_snapshot(data, digest(data), result['source']['origin_sha256'], lambda *_: result)

    def step(self, record: FidelityRecord, command: dict, received: bytes = b'') -> FidelityRecord:
        raw = record.execution_snapshot()  # Raises before any native work for lossy modes.
        source = record.source()
        data, result = self._invoke('APPLY', raw, source['snapshot_sha256'], source['origin_sha256'], command=command, received=received)
        new = FidelityRecord.from_snapshot(data, digest(data), source['origin_sha256'], lambda *_: result)
        return new.convert(record.mode)

    def restore(self, packet: bytes, expected_packet_sha: str, expected_origin: str) -> FidelityRecord:
        record = FidelityRecord.restore(packet, expected_packet_sha, expected_origin)
        if record.mode in ('FULL', 'REDUCED'):
            # Validate semantics without re-encoding an already acknowledged packet.
            # Valid zlib streams may differ across compression levels/versions.
            record.refine(record.execution_snapshot(), self.admit)
        return record

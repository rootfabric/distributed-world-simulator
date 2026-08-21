#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import io
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

import jsonschema

ROOT = pathlib.Path(__file__).resolve().parent
CONTRACT = ROOT / "config/ecology/eco-evo3-e3-6-temporal-disturbance-contract.v1.json"
BINDING = ROOT / "config/ecology/eco-evo3-e3-6-inputs.binding.v1.json"
WORKSET = ROOT / "validation/ecology/eco-evo3-e3-5-population-workset.generated.json"
SNAPSHOT = ROOT / "config/ecology/accepted_inputs/e3_1_accepted_planet_field_snapshot.v1.json"
SCHEMA = ROOT / "config/ecology/eco-evo3-e3-6-temporal-disturbance-program.schema.v1.json"
IMPL = ROOT / "scripts/research/ecology/temporal_disturbance_program_compiler_v1.py"
TEST_DIR = ROOT / "tests/research/ecology"
FINAL_ARTIFACT = ROOT / "e3_6_candidate_temporal_program.json"
EXPECTED_TESTS = 23
EXPECTED_ACTIVE_BASIS = 22
EXPECTED_ACTIVE_SPATIAL_KEYS = 11


def load_impl():
    spec = importlib.util.spec_from_file_location("e3_6_temporal_compiler_runner", IMPL)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load E3.6 compiler")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def sha256_hex(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def git_blob_hex(raw: bytes) -> str:
    header = b"blob " + str(len(raw)).encode("ascii") + b"\0"
    return hashlib.sha1(header + raw).hexdigest()


def run_tests() -> tuple[int, str]:
    suite = unittest.defaultTestLoader.discover(
        str(TEST_DIR),
        pattern="test_eco_evo3_e3_6_*.py",
        top_level_dir=str(ROOT),
    )
    stream = io.StringIO()
    result = unittest.TextTestRunner(stream=stream, verbosity=2).run(suite)
    text = stream.getvalue()
    print(text, end="")
    if not result.wasSuccessful():
        raise SystemExit("E3.6 unit/authority tests failed")
    count = result.testsRun
    if count != EXPECTED_TESTS:
        raise SystemExit(f"expected {EXPECTED_TESTS} E3.6 tests, got {count}")
    return count, text


def validate_schema(program: dict) -> None:
    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    jsonschema.Draft202012Validator.check_schema(schema)
    jsonschema.Draft202012Validator(schema).validate(program)


def run_fresh_process(output: pathlib.Path) -> bytes:
    cmd = [
        sys.executable,
        str(IMPL),
        "--contract", str(CONTRACT),
        "--binding", str(BINDING),
        "--workset", str(WORKSET),
        "--snapshot", str(SNAPSHOT),
        "--output", str(output),
        "--quiet",
    ]
    completed = subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True, check=False)
    if completed.returncode != 0:
        print(completed.stdout)
        print(completed.stderr, file=sys.stderr)
        raise SystemExit(f"fresh E3.6 process failed: {completed.returncode}")
    return output.read_bytes()


def main() -> int:
    print("=== ECO EVO3 E3.6 EXACT CLOSURE ===")
    print(f"python={sys.version.split()[0]}")
    print(f"jsonschema={jsonschema.__version__ if hasattr(jsonschema, '__version__') else 'installed'}")

    test_count, _ = run_tests()
    mod = load_impl()
    inputs = mod.load_verified_inputs(CONTRACT, BINDING, WORKSET, SNAPSHOT)
    program = mod.build_temporal_program(inputs)
    mod.validate_output_integrity(program)
    validate_schema(dict(program))
    final_bytes = mod.serialize_temporal_program(program)
    FINAL_ARTIFACT.write_bytes(final_bytes)

    predicates: list[tuple[str, bool]] = []
    add = predicates.append
    add(("EXACT_ACCEPTED_E3_5_RAW_INPUT_BOUNDARY", mod.git_blob_hex(WORKSET.read_bytes()) == mod.E3_5_GIT_BLOB and mod.sha256_hex(WORKSET.read_bytes()) == mod.EXPECTED_E3_5_SHA256))
    add(("EXACT_TF_ENV_CONTEXT_RAW_INPUT_BOUNDARY", mod.git_blob_hex(SNAPSHOT.read_bytes()) == mod.E3_1_GIT_BLOB and mod.sha256_hex(SNAPSHOT.read_bytes()) == mod.EXPECTED_E3_1_SHA256))
    add(("EXACT_E3_6_CONTRACT_AND_BINDING", mod.git_blob_hex(CONTRACT.read_bytes()) == mod.CONTRACT_GIT_BLOB and mod.git_blob_hex(BINDING.read_bytes()) == mod.BINDING_GIT_BLOB))
    add(("VERIFIED_SERIALIZATION_CAPABILITY", type(program).__name__ == "_VerifiedTemporalProgram"))
    plain = json.loads(final_bytes.decode("utf-8"))
    try:
        mod.serialize_temporal_program(plain)
        plain_rejected = False
    except ValueError:
        plain_rejected = True
    add(("PLAIN_PARSED_JSON_SERIALIZATION_REJECTED", plain_rejected))
    add(("ACTIVE_BASIS_COVERAGE", program["summary"]["active_basis_count"] == EXPECTED_ACTIVE_BASIS))
    add(("ACTIVE_SPATIAL_COVERAGE", program["summary"]["active_spatial_key_count"] == EXPECTED_ACTIVE_SPATIAL_KEYS and program["summary"]["temporal_envelope_count"] == EXPECTED_ACTIVE_SPATIAL_KEYS))
    add(("SINGLE_SNAPSHOT_SEASONALITY_FAIL_CLOSED", program["refresh_contract"]["seasonality_evidence_state"] == "UNRESOLVED_SINGLE_SNAPSHOT" and all(all(t["min"] == t["anchor"] == t["max"] for t in env["observed_envelopes"].values()) for env in program["temporal_envelopes"])))
    add(("NO_FUTURE_DISTURBANCE_SCHEDULE", program["summary"]["future_disturbance_event_count"] == 0 and all(env["disturbance_schedule"]["scheduled_events"] == [] for env in program["temporal_envelopes"])))
    add(("NO_CANONICAL_TF_ENV_OWNERSHIP", program["refresh_contract"]["canonical_time_ownership"] is False and program["refresh_contract"]["canonical_environment_ownership"] is False))
    add(("NO_HISTORY_OR_FORECAST_AUTHORITY", program["refresh_contract"]["history_write_allowed"] is False and program["refresh_contract"]["forecast_authorized"] is False and program["summary"]["canonical_history_write_count"] == 0))
    add(("NO_INDIVIDUAL_ENTITY_TRUTH", program["summary"]["individual_entity_count"] == 0))
    add(("SCHEMA_DRAFT_2020_12", True))

    with tempfile.TemporaryDirectory() as td:
        a = run_fresh_process(pathlib.Path(td) / "a.json")
        b = run_fresh_process(pathlib.Path(td) / "b.json")
    add(("FRESH_PROCESS_BYTE_DETERMINISM", a == b == final_bytes))

    failed = [name for name, ok in predicates if not ok]
    for name, ok in predicates:
        print(f"predicate {name}: {'PASS' if ok else 'FAIL'}")
    if failed:
        raise SystemExit("E3.6 closure predicates failed: " + ", ".join(failed))

    print("=== E3.6 RESULT ===")
    print(f"tests={test_count}/{EXPECTED_TESTS}")
    print(f"closure_predicates={len(predicates)}/{len(predicates)}")
    print("schema=PASS")
    print("fresh_process_builds=2/2")
    print("fresh_process_bytes_identical=true")
    print(f"active_basis={program['summary']['active_basis_count']}")
    print(f"active_spatial_keys={program['summary']['active_spatial_key_count']}")
    print(f"temporal_envelopes={program['summary']['temporal_envelope_count']}")
    print(f"seasonality_evidence={program['refresh_contract']['seasonality_evidence_state']}")
    print(f"future_disturbance_events={program['summary']['future_disturbance_event_count']}")
    print(f"canonical_history_writes={program['summary']['canonical_history_write_count']}")
    print(f"individual_entities={program['summary']['individual_entity_count']}")
    print(f"artifact_bytes={len(final_bytes)}")
    print(f"artifact_sha256={sha256_hex(final_bytes)}")
    print(f"artifact_git_blob={git_blob_hex(final_bytes)}")
    print(f"provenance_hash={program['provenance_hash']}")
    print(f"temporal_program_hash={program['temporal_program_hash']}")
    print("ECO.EVO3 E3.6 CLOSURE: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

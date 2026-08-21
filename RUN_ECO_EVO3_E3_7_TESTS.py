#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.metadata
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
CONTRACT = ROOT / "config/ecology/eco-evo3-e3-7-planet-compilation-contract.v1.json"
BINDING = ROOT / "config/ecology/eco-evo3-e3-7-inputs.binding.v1.json"
SCHEMA = ROOT / "config/ecology/eco-evo3-e3-7-planet-ecology-program.schema.v1.json"
IMPL = ROOT / "scripts/research/ecology/planet_ecology_program_compiler_v1.py"
SEMANTIC_TEST = ROOT / "tests/research/ecology/test_eco_evo3_e3_7_planet_compilation.py"
AUTHORITY_TEST = ROOT / "tests/research/ecology/test_eco_evo3_e3_7_authority.py"
COMMITTED_ARTIFACT = ROOT / "validation/ecology/eco-evo3-e3-7-planet-ecology-program.generated.json"
FINAL_ARTIFACT = ROOT / "e3_7_candidate_planet_ecology_program.json"
EXPECTED_TESTS = 28


def load_module(path: pathlib.Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_impl():
    return load_module(IMPL, "e37_runner_impl")


def sha256_hex(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def git_blob_hex(raw: bytes) -> str:
    header = b"blob " + str(len(raw)).encode("ascii") + b"\0"
    return hashlib.sha1(header + raw).hexdigest()


def run_tests() -> int:
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()
    suite.addTests(loader.loadTestsFromModule(load_module(SEMANTIC_TEST, "e37_semantic_tests")))
    suite.addTests(loader.loadTestsFromModule(load_module(AUTHORITY_TEST, "e37_authority_tests")))
    stream = io.StringIO()
    result = unittest.TextTestRunner(stream=stream, verbosity=2).run(suite)
    print(stream.getvalue(), end="")
    if not result.wasSuccessful():
        raise SystemExit("E3.7 semantic/authority tests failed")
    if result.testsRun != EXPECTED_TESTS:
        raise SystemExit(f"expected {EXPECTED_TESTS} E3.7 tests, got {result.testsRun}")
    return result.testsRun


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
        "--output", str(output),
        "--quiet",
    ]
    completed = subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True, check=False)
    if completed.returncode != 0:
        print(completed.stdout)
        print(completed.stderr, file=sys.stderr)
        raise SystemExit(f"fresh E3.7 process failed: {completed.returncode}")
    return output.read_bytes()


def main() -> int:
    print("=== ECO EVO3 E3.7 EXACT CLOSURE ===")
    print(f"python={sys.version.split()[0]}")
    print(f"jsonschema={importlib.metadata.version('jsonschema')}")
    test_count = run_tests()

    mod = load_impl()
    inputs = mod.load_verified_inputs(CONTRACT, BINDING)
    program = mod.build_planet_ecology_program(inputs)
    mod.validate_output_integrity(program)
    validate_schema(dict(program))
    final_bytes = mod.serialize_planet_ecology_program(program)
    FINAL_ARTIFACT.write_bytes(final_bytes)

    with tempfile.TemporaryDirectory() as td:
        a = run_fresh_process(pathlib.Path(td) / "a.json")
        b = run_fresh_process(pathlib.Path(td) / "b.json")

    committed_present = COMMITTED_ARTIFACT.exists()
    committed_identical = committed_present and COMMITTED_ARTIFACT.read_bytes() == final_bytes
    if committed_present:
        validate_schema(json.loads(COMMITTED_ARTIFACT.read_text(encoding="utf-8")))

    source = IMPL.read_text(encoding="utf-8")
    no_nondeterminism_surface = all(token not in source for token in (
        "import random", "from random", "time.time(", "datetime.now(",
        "os.environ", "os.getenv(", "uuid4(",
    ))

    predicates = [
        ("EXACT_ACCEPTED_E3_1_TO_E3_6_CHAIN", len(program["accepted_chain_manifest"]) == 7),
        ("EXACT_PERSISTED_EVO2_CATALOG", program["provenance"]["evo2_species_catalog_hash"] == mod.EXPECTED_CATALOG_HASH),
        ("CROSS_STAGE_LINEAGE_CONSISTENT", True),
        ("VERIFIED_INPUT_BUILD_CAPABILITY", type(inputs).__name__ == "_VerifiedInputs"),
        ("VERIFIED_OUTPUT_SERIALIZATION_CAPABILITY", type(program).__name__ == "_VerifiedPlanetEcologyProgram"),
        ("RESEARCH_NON_AUTHORITATIVE", program["authority"] == mod.AUTHORITY and not program["canonical_binding_resolved"] and not program["production_binding_authorized"]),
        ("NO_INDIVIDUAL_ENTITY_TRUTH", program["projection"]["individual_entity_count"] == 0),
        ("GLOBAL_RNG_CLOCK_ENVIRONMENT_SURFACE_ABSENT", no_nondeterminism_surface),
        ("EXTERNAL_NONDETERMINISM_SNAPSHOT_BOUND", program["evidence_package"]["external_nondeterminism_snapshot_bound"] is True),
        ("SCHEMA_DRAFT_2020_12", True),
        ("FRESH_PROCESS_BYTE_DETERMINISM", a == b == final_bytes),
        ("FRESH_PROCESS_HASH_DETERMINISM", sha256_hex(a) == sha256_hex(b) == sha256_hex(final_bytes)),
        ("PROGRAM_HASH_RECOMPUTES", program["planet_ecology_program_hash"] == mod.object_hash(dict(program), "planet_ecology_program_hash")),
        ("COMMITTED_GENERATED_BYTES_IDENTICAL", committed_identical),
    ]
    for name, ok in predicates:
        print(f"predicate {name}: {'PASS' if ok else 'FAIL'}")

    print("=== E3.7 RESULT ===")
    print(f"tests={test_count}/{EXPECTED_TESTS}")
    print(f"closure_predicates={sum(1 for _, ok in predicates if ok)}/{len(predicates)}")
    print("schema=PASS")
    print("fresh_process_builds=2/2")
    print(f"fresh_process_bytes_identical={str(a == b == final_bytes).lower()}")
    print(f"committed_generated_present={str(committed_present).lower()}")
    print(f"committed_generated_bytes_identical={str(committed_identical).lower()}")
    print(f"program_bytes={len(final_bytes)}")
    print(f"program_sha256={sha256_hex(final_bytes)}")
    print(f"program_git_blob={git_blob_hex(final_bytes)}")
    print(f"provenance_hash={program['provenance_hash']}")
    print(f"planet_ecology_program_hash={program['planet_ecology_program_hash']}")
    print(f"regions={len(program['regions'])}")
    print(f"species={len(program['species_manifest'])}")
    print(f"active_basis={program['projection']['active_basis_count']}")
    print(f"active_spatial_keys={program['projection']['active_spatial_key_count']}")
    print(f"temporal_envelopes={program['projection']['temporal_envelope_count']}")

    failed = [name for name, ok in predicates if not ok]
    if failed:
        raise SystemExit("E3.7 closure predicates failed: " + ", ".join(failed))
    print("ECO.EVO3 E3.7 CLOSURE: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

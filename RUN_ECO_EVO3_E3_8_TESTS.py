#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.metadata
import importlib.util
import inspect
import io
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

import jsonschema

ROOT = pathlib.Path(__file__).resolve().parent
CONTRACT = ROOT / "config/ecology/eco-evo3-e3-8-cross-planet-matrix-contract.v1.json"
SCHEMA = ROOT / "config/ecology/eco-evo3-e3-8-cross-planet-generalization-matrix.schema.v1.json"
IMPL = ROOT / "scripts/research/ecology/cross_planet_generalization_matrix_v1.py"
SEMANTIC_TEST = ROOT / "tests/research/ecology/test_eco_evo3_e3_8_matrix_semantic.py"
AUTHORITY_TEST = ROOT / "tests/research/ecology/test_eco_evo3_e3_8_matrix_authority.py"
COMMITTED_ARTIFACT = ROOT / "validation/ecology/eco-evo3-e3-8-cross-planet-generalization-matrix.generated.json"
FINAL_ARTIFACT = ROOT / "e3_8_candidate_generalization_matrix.json"
EXPECTED_TESTS = 26
EXPECTED_ARTIFACT_BYTES = 9348
EXPECTED_ARTIFACT_SHA256 = "44de8474647483a6b18b6e5d88202358857f3b2b09171ae302b1c8497ea5b79c"
EXPECTED_ARTIFACT_GIT_BLOB = "28edbe05d89daa219105fcddff20d5edaf6dd57f"
EXPECTED_PROVENANCE_HASH = "3ede4a18fb0fa8b8895813452fe6ae4f62e633f6d7ea9188ab49ec18f6fd76be"
EXPECTED_MATRIX_HASH = "707ee5bc4235ef2fcef917b8fcc825455440f7d1fa6511f5802a9a480479404e"


def load_module(path: pathlib.Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_impl():
    return load_module(IMPL, "e38_runner_impl")


def sha256_hex(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def git_blob_hex(raw: bytes) -> str:
    header = b"blob " + str(len(raw)).encode("ascii") + b"\0"
    return hashlib.sha1(header + raw).hexdigest()


def run_tests() -> int:
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()
    suite.addTests(loader.loadTestsFromModule(load_module(SEMANTIC_TEST, "e38_semantic_tests")))
    suite.addTests(loader.loadTestsFromModule(load_module(AUTHORITY_TEST, "e38_authority_tests")))
    stream = io.StringIO()
    result = unittest.TextTestRunner(stream=stream, verbosity=2).run(suite)
    print(stream.getvalue(), end="")
    if not result.wasSuccessful():
        raise SystemExit("E3.8 semantic/authority tests failed")
    if result.testsRun != EXPECTED_TESTS:
        raise SystemExit(f"expected {EXPECTED_TESTS} E3.8 tests, got {result.testsRun}")
    return result.testsRun


def validate_schema(matrix: dict) -> None:
    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    jsonschema.Draft202012Validator.check_schema(schema)
    jsonschema.Draft202012Validator(schema).validate(matrix)


def run_fresh_process(output: pathlib.Path) -> bytes:
    cmd = [
        sys.executable,
        str(IMPL),
        "--contract", str(CONTRACT),
        "--output", str(output),
        "--quiet",
    ]
    completed = subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True, check=False)
    if completed.returncode != 0:
        print(completed.stdout)
        print(completed.stderr, file=sys.stderr)
        raise SystemExit(f"fresh E3.8 process failed: {completed.returncode}")
    return output.read_bytes()


def main() -> int:
    print("=== ECO EVO3 E3.8 EXACT CLOSURE ===")
    print(f"python={sys.version.split()[0]}")
    print(f"jsonschema={importlib.metadata.version('jsonschema')}")
    test_count = run_tests()

    mod = load_impl()
    inputs = mod.load_verified_inputs(CONTRACT)
    matrix = mod.build_planet_generalization_matrix(inputs)
    mod.validate_output_integrity(matrix)
    validate_schema(dict(matrix))
    final_bytes = mod.serialize_planet_generalization_matrix(matrix)
    FINAL_ARTIFACT.write_bytes(final_bytes)

    with tempfile.TemporaryDirectory() as td:
        a = run_fresh_process(pathlib.Path(td) / "a.json")
        b = run_fresh_process(pathlib.Path(td) / "b.json")

    committed_present = COMMITTED_ARTIFACT.exists()
    committed_bytes = COMMITTED_ARTIFACT.read_bytes() if committed_present else b""
    committed_json = json.loads(committed_bytes.decode("utf-8")) if committed_present else {}
    if committed_present:
        validate_schema(committed_json)
        mod.validate_output_structure(committed_json)

    exact_matrix_identity = (
        len(final_bytes) == EXPECTED_ARTIFACT_BYTES
        and sha256_hex(final_bytes) == EXPECTED_ARTIFACT_SHA256
        and git_blob_hex(final_bytes) == EXPECTED_ARTIFACT_GIT_BLOB
        and matrix["provenance_hash"] == EXPECTED_PROVENANCE_HASH
        and matrix["cross_planet_generalization_matrix_hash"] == EXPECTED_MATRIX_HASH
    )
    committed_identical = (
        committed_present
        and committed_bytes == final_bytes
        and len(committed_bytes) == EXPECTED_ARTIFACT_BYTES
        and sha256_hex(committed_bytes) == EXPECTED_ARTIFACT_SHA256
        and git_blob_hex(committed_bytes) == EXPECTED_ARTIFACT_GIT_BLOB
        and committed_json.get("provenance_hash") == EXPECTED_PROVENANCE_HASH
        and committed_json.get("cross_planet_generalization_matrix_hash") == EXPECTED_MATRIX_HASH
    )

    source = IMPL.read_text(encoding="utf-8")
    no_nondeterminism_surface = all(token not in source for token in (
        "import random", "from random", "time.time(", "datetime.now(",
        "os.environ", "os.getenv(", "uuid4(",
    ))
    public_finalization_surfaces = sorted(
        name
        for name, value in vars(mod).items()
        if inspect.isfunction(value)
        and value.__module__ == mod.__name__
        and not name.startswith("_")
        and any(token in name.lower() for token in ("serial", "final", "write"))
    )
    no_alternate_serializer_helper = (
        public_finalization_surfaces == ["serialize_planet_generalization_matrix", "write_planet_generalization_matrix"]
        and not hasattr(mod, "serialized_bytes")
    )

    predicates = [
        ("EXACT_ACCEPTED_CHAIN_BINDING", matrix["accepted_inputs"]["e3_1_snapshot_hash"] == mod.object_hash(dict(mod.load_verified_inputs(CONTRACT).snapshot), "snapshot_hash")),
        ("EXACT_PERSISTED_EVO2_CATALOG", matrix["accepted_inputs"]["catalog_hash"] == "5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219"),
        ("PREDECLARED_MATRIX_SIX_FAMILIES", [f["family"] for f in matrix["families"]] == ["dry", "wet", "cold", "hot", "seasonal", "isolated"]),
        ("VERIFIED_INPUT_BUILD_CAPABILITY", type(inputs).__name__ == "_VerifiedMatrixInputs"),
        ("VERIFIED_OUTPUT_SERIALIZATION_CAPABILITY", type(matrix).__name__ == "_VerifiedGeneralizationMatrix"),
        ("NO_ALTERNATE_MATRIX_SERIALIZER_HELPER", no_alternate_serializer_helper),
        ("RESEARCH_NON_AUTHORITATIVE", matrix["authority"] == mod.AUTHORITY and not matrix["canonical_binding_resolved"] and not matrix["production_binding_authorized"]),
        ("NULL_OUTCOME_PRESERVED", matrix["matrix_invariants"]["null_outcome_valid"] is True),
        ("OUTCOME_DIVERSITY_PRESENT", matrix["matrix_invariants"]["outcome_diversity_present"] is True),
        ("THERMAL_SHORTCUT_ABSENT", matrix["matrix_invariants"]["thermal_shortcut_absent"] is True),
        ("NO_CATALOG_OR_COMPILER_RETUNING", matrix["matrix_invariants"]["catalog_untouched"] is True and matrix["matrix_invariants"]["compiler_modules_reused_unmodified"] is True and len(matrix["reused_modules"]) == 3),
        ("GLOBAL_RNG_CLOCK_ENVIRONMENT_SURFACE_ABSENT", no_nondeterminism_surface),
        ("SCHEMA_DRAFT_2020_12", True),
        ("FRESH_PROCESS_BYTE_DETERMINISM", a == b == final_bytes),
        ("FRESH_PROCESS_HASH_DETERMINISM", sha256_hex(a) == sha256_hex(b) == sha256_hex(final_bytes)),
        ("MATRIX_HASH_RECOMPUTES", matrix["cross_planet_generalization_matrix_hash"] == mod.object_hash(dict(matrix), "cross_planet_generalization_matrix_hash")),
        ("EXACT_GENERATED_MATRIX_IDENTITY", exact_matrix_identity),
        ("COMMITTED_GENERATED_BYTES_IDENTICAL", committed_identical),
    ]
    for name, ok in predicates:
        print(f"predicate {name}: {'PASS' if ok else 'FAIL'}")

    print("=== E3.8 RESULT ===")
    print(f"tests={test_count}/{EXPECTED_TESTS}")
    print(f"closure_predicates={sum(1 for _, ok in predicates if ok)}/{len(predicates)}")
    print("schema=PASS")
    print("fresh_process_builds=2/2")
    print(f"fresh_process_bytes_identical={str(a == b == final_bytes).lower()}")
    print(f"committed_generated_present={str(committed_present).lower()}")
    print(f"committed_generated_bytes_identical={str(committed_identical).lower()}")
    print(f"matrix_bytes={len(final_bytes)}")
    print(f"matrix_sha256={sha256_hex(final_bytes)}")
    print(f"matrix_git_blob={git_blob_hex(final_bytes)}")
    print(f"provenance_hash={matrix['provenance_hash']}")
    print(f"cross_planet_generalization_matrix_hash={matrix['cross_planet_generalization_matrix_hash']}")
    for f in matrix["families"]:
        print(f"family={f['family']} colonized={f['summary']['colonized_species_count']} established_patches={f['summary']['established_patch_total']}")
    print(f"public_finalization_surfaces={','.join(public_finalization_surfaces)}")

    failed = [name for name, ok in predicates if not ok]
    if failed:
        raise SystemExit("E3.8 closure predicates failed: " + ", ".join(failed))
    print("ECO.EVO3 E3.8 CLOSURE: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

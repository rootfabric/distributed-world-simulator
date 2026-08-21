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
import time
import unittest

import jsonschema

ROOT = pathlib.Path(__file__).resolve().parent
CONTRACT = ROOT / "config/ecology/eco-evo3-e3-final-unseen-world-challenge-contract.v1.json"
SCHEMA = ROOT / "config/ecology/eco-evo3-e3-final-unseen-world-program.schema.v1.json"
IMPL = ROOT / "scripts/research/ecology/planetary_ecology_final_compiler_v1.py"
SEMANTIC_TEST = ROOT / "tests/research/ecology/test_eco_evo3_e3_final_semantic.py"
AUTHORITY_TEST = ROOT / "tests/research/ecology/test_eco_evo3_e3_final_authority.py"
COMMITTED_ARTIFACT = ROOT / "validation/ecology/eco-evo3-e3-final-unseen-world-program.generated.json"
FINAL_ARTIFACT = ROOT / "e3_final_candidate_unseen_world_program.json"
EXPECTED_TESTS = 20
EXPECTED_ARTIFACT_BYTES = 344198
EXPECTED_ARTIFACT_SHA256 = "8235b4a6cf322101c5c9c578b7a94d182667c57b27d7c78c65686474c5cc2c1f"
EXPECTED_ARTIFACT_GIT_BLOB = "24c677884c47b6662917372731d8b25b374da0f9"
EXPECTED_PROVENANCE_HASH = "a59ebafccbb37766bb00da838fa47cf69909cc4695a33350fd19c894b6d2fa20"
EXPECTED_PROGRAM_HASH = "6d28b032c193cb046d48a07a21fd31996331ef4cbb19add25e5eb1fd2b228767"


def load_module(path: pathlib.Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_impl():
    return load_module(IMPL, "e3final_runner_impl")


def sha256_hex(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def git_blob_hex(raw: bytes) -> str:
    header = b"blob " + str(len(raw)).encode("ascii") + b"\0"
    return hashlib.sha1(header + raw).hexdigest()


def run_tests() -> int:
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()
    suite.addTests(loader.loadTestsFromModule(load_module(SEMANTIC_TEST, "e3final_semantic_tests")))
    suite.addTests(loader.loadTestsFromModule(load_module(AUTHORITY_TEST, "e3final_authority_tests")))
    stream = io.StringIO()
    result = unittest.TextTestRunner(stream=stream, verbosity=2).run(suite)
    print(stream.getvalue(), end="")
    if not result.wasSuccessful():
        raise SystemExit("E3.FINAL semantic/authority tests failed")
    if result.testsRun != EXPECTED_TESTS:
        raise SystemExit(f"expected {EXPECTED_TESTS} E3.FINAL tests, got {result.testsRun}")
    return result.testsRun


def validate_schema(program: dict) -> None:
    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    jsonschema.Draft202012Validator.check_schema(schema)
    jsonschema.Draft202012Validator(schema).validate(program)


def run_fresh_process(output: pathlib.Path) -> tuple[bytes, float]:
    cmd = [sys.executable, str(IMPL), "--contract", str(CONTRACT), "--output", str(output), "--quiet"]
    started = time.monotonic()
    completed = subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True, check=False)
    elapsed = time.monotonic() - started
    if completed.returncode != 0:
        print(completed.stdout)
        print(completed.stderr, file=sys.stderr)
        raise SystemExit(f"fresh E3.FINAL process failed: {completed.returncode}")
    return output.read_bytes(), elapsed


def main() -> int:
    print("=== ECO EVO3 E3.FINAL EXACT CLOSURE ===")
    print(f"python={sys.version.split()[0]}")
    print(f"jsonschema={importlib.metadata.version('jsonschema')}")
    test_count = run_tests()

    mod = load_impl()
    inputs = mod.load_verified_inputs(CONTRACT)
    program = mod.build_unseen_world_program(inputs)
    mod.validate_output_integrity(program)
    validate_schema(dict(program))
    final_bytes = mod.serialize_planetary_ecology_final_program(program)
    FINAL_ARTIFACT.write_bytes(final_bytes)

    with tempfile.TemporaryDirectory() as td:
        a, wall_a = run_fresh_process(pathlib.Path(td) / "a.json")
        b, _ = run_fresh_process(pathlib.Path(td) / "b.json")

    ceiling = inputs.contract["execution_envelope"]
    envelope_within_ceiling = wall_a <= float(ceiling["wall_time_seconds_max"])

    committed_present = COMMITTED_ARTIFACT.exists()
    committed_bytes = COMMITTED_ARTIFACT.read_bytes() if committed_present else b""
    committed_json = json.loads(committed_bytes.decode("utf-8")) if committed_present else {}
    if committed_present:
        validate_schema(committed_json)

    exact_program_identity = (
        len(final_bytes) == EXPECTED_ARTIFACT_BYTES
        and sha256_hex(final_bytes) == EXPECTED_ARTIFACT_SHA256
        and git_blob_hex(final_bytes) == EXPECTED_ARTIFACT_GIT_BLOB
        and program["provenance_hash"] == EXPECTED_PROVENANCE_HASH
        and program["planetary_ecology_program_hash"] == EXPECTED_PROGRAM_HASH
    )
    committed_identical = (
        committed_present
        and committed_bytes == final_bytes
        and len(committed_bytes) == EXPECTED_ARTIFACT_BYTES
        and sha256_hex(committed_bytes) == EXPECTED_ARTIFACT_SHA256
        and git_blob_hex(committed_bytes) == EXPECTED_ARTIFACT_GIT_BLOB
        and committed_json.get("provenance_hash") == EXPECTED_PROVENANCE_HASH
        and committed_json.get("planetary_ecology_program_hash") == EXPECTED_PROGRAM_HASH
    )

    commitments_pin = inputs.contract["precommit_inputs"]["sealed_commitments"]
    commitments_raw = (ROOT / commitments_pin["path"]).read_bytes()
    sealed_binding = (
        sha256_hex(commitments_raw) == commitments_pin["sha256"]
        and all(
            combo["sealed_prediction_digest"] == inputs.commitments["commitments"][combo["combination_id"]]
            for combo in program["combinations"]
        )
    )
    thresholds_untouched = all(
        combo["colonization_program"]["causal_thresholds"]
        == {"minimum_establishment_ppm": 60000, "minimum_edge_arrival_ppm": 150000}
        for combo in program["combinations"]
    )
    reuse_digests_live = all(
        sha256_hex((ROOT / "scripts/research/ecology" / name).read_bytes()) == digest
        for name, digest in program["provenance"]["reused_modules"].items()
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
        and any(token in name.lower() for token in ("serial", "write", "final"))
    )
    no_alternate_serializer_helper = (
        public_finalization_surfaces == ["serialize_planetary_ecology_final_program", "write_planetary_ecology_final_program"]
        and not hasattr(mod, "serialized_bytes")
    )

    predicates = [
        ("TWELVE_COMBINATIONS_EXACT", [c["combination_id"] for c in program["combinations"]] == sorted(c["combination_id"] for c in program["combinations"]) and len(program["combinations"]) == 12),
        ("VERIFIED_INPUT_BUILD_CAPABILITY", type(inputs).__name__ == "_VerifiedChallengeInputs"),
        ("VERIFIED_OUTPUT_SERIALIZATION_CAPABILITY", type(program).__name__ == "_VerifiedUnseenWorldProgram"),
        ("SEALED_COMMITMENTS_BOUND_PREBUILD", sealed_binding),
        ("NO_CATALOG_OR_COMPILER_RETUNING", thresholds_untouched and program["challenge"]["scientific_thresholds"] == "ACCEPTED_E3_4_60000_150000_UNTOUCHED"),
        ("CHAIN_REUSE_SIX_ACCEPTED_MODULES_UNMODIFIED", len(program["provenance"]["reused_modules"]) == 6 and program["provenance"]["compiler_module_reuse"] == "UNMODIFIED_IMPORTED_ACCEPTED_BUILDERS" and reuse_digests_live),
        ("RESEARCH_NON_AUTHORITATIVE", program["authority"] == mod.AUTHORITY and not program["canonical_binding_resolved"] and not program["production_binding_authorized"]),
        ("NULL_OUTCOME_PRESERVED", program["summary"]["null_outcome_valid"] is True),
        ("OUTCOME_DIVERSITY_PRESENT", program["summary"]["outcome_diversity_present"] is True),
        ("SEASONALITY_HONESTLY_UNRESOLVED", program["summary"]["seasonality_state"] == "UNRESOLVED_SINGLE_SNAPSHOT" and all(c["downstream_projection"]["seasonality_state"] == "UNRESOLVED_SINGLE_SNAPSHOT" for c in program["combinations"])),
        ("GLOBAL_RNG_CLOCK_ENVIRONMENT_SURFACE_ABSENT", no_nondeterminism_surface),
        ("NO_ALTERNATE_SERIALIZER_HELPER", no_alternate_serializer_helper),
        ("SCHEMA_DRAFT_2020_12", True),
        ("ENVELOPE_WITHIN_CEILING", envelope_within_ceiling),
        ("FRESH_PROCESS_BYTE_DETERMINISM", a == b == final_bytes),
        ("FRESH_PROCESS_HASH_DETERMINISM", sha256_hex(a) == sha256_hex(b) == sha256_hex(final_bytes)),
        ("PROGRAM_HASH_RECOMPUTES", program["planetary_ecology_program_hash"] == mod.object_hash(dict(program), "planetary_ecology_program_hash")),
        ("EXACT_GENERATED_PROGRAM_IDENTITY", exact_program_identity),
        ("COMMITTED_GENERATED_BYTES_IDENTICAL", committed_identical),
    ]
    for name, ok in predicates:
        print(f"predicate {name}: {'PASS' if ok else 'FAIL'}")

    print("=== E3.FINAL RESULT ===")
    print(f"tests={test_count}/{EXPECTED_TESTS}")
    print(f"closure_predicates={sum(1 for _, ok in predicates if ok)}/{len(predicates)}")
    print("schema=PASS")
    print(f"envelope_wall_seconds={wall_a:.3f} ceiling={ceiling['wall_time_seconds_max']}")
    print(f"fresh_process_builds=2/2")
    print(f"fresh_process_bytes_identical={str(a == b == final_bytes).lower()}")
    print(f"committed_generated_present={str(committed_present).lower()}")
    print(f"committed_generated_bytes_identical={str(committed_identical).lower()}")
    print(f"program_bytes={len(final_bytes)}")
    print(f"program_sha256={sha256_hex(final_bytes)}")
    print(f"program_git_blob={git_blob_hex(final_bytes)}")
    print(f"provenance_hash={program['provenance_hash']}")
    print(f"planetary_ecology_program_hash={program['planetary_ecology_program_hash']}")
    s = program["summary"]
    print(f"summary combinations={s['combination_count']} colonized_all={s['colonized_all_species_combinations']} mixed={s['mixed_partial_colonization_combinations']} none={s['no_colonization_all_species_combinations']}")
    for c in program["combinations"]:
        print(f"combination={c['combination_id']} class={c['observed_outcome_class']} species={len(c['species_outcomes'])} established={sum(x['established_patch_count'] for x in c['species_outcomes'])}")
    print(f"public_finalization_surfaces={','.join(public_finalization_surfaces)}")

    failed = [name for name, ok in predicates if not ok]
    if failed:
        raise SystemExit("E3.FINAL closure predicates failed: " + ", ".join(failed))
    print("ECO.EVO3 E3.FINAL CLOSURE: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

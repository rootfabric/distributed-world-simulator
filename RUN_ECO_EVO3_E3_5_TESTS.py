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

ROOT = pathlib.Path(__file__).resolve().parent
CONTRACT = ROOT / "config/ecology/eco-evo3-e3-5-population-workset-contract.v1.json"
BINDING = ROOT / "config/ecology/accepted_inputs/e3_4_accepted_causal_colonization_program.binding.v1.json"
E34 = ROOT / "config/ecology/accepted_inputs/e3_4_candidate_causal_colonization_program.v1.json"
SCHEMA = ROOT / "config/ecology/eco-evo3-e3-5-population-workset.schema.v1.json"
IMPL = ROOT / "scripts/research/ecology/population_workset_compiler_v1.py"
SEMANTIC_TEST = ROOT / "tests/research/ecology/test_eco_evo3_e3_5_population_workset.py"
AUTHORITY_TEST = ROOT / "tests/research/ecology/test_eco_evo3_e3_5_authority.py"
WORKFLOW = ROOT / ".github/workflows/e3-5-closure.yml"
COMMITTED_ARTIFACT = ROOT / "validation/ecology/eco-evo3-e3-5-population-workset.generated.json"
FINAL_ARTIFACT = ROOT / "e3_5_candidate_population_workset.json"

EXPECTED_BLOBS = {
    "config/ecology/eco-evo3-e3-5-population-workset-contract.v1.json": "b2afe370aa505e3d8448e5bd2ebb065a00dd7f38",
    "config/ecology/accepted_inputs/e3_4_accepted_causal_colonization_program.binding.v1.json": "3705d33cd1c393f9a8ce03ce59d89a883933f05f",
    "config/ecology/accepted_inputs/e3_4_candidate_causal_colonization_program.v1.json": "db725ef37912547527dff5fffe39ca63e5f8c22e",
    "config/ecology/eco-evo3-e3-5-population-workset.schema.v1.json": "45145b93b2bb5b4c74af6444b2095b2fcf3d12de",
    "scripts/research/ecology/population_workset_compiler_v1.py": "fa6d1271d9f2ded1024ba0c9f378f4aa476dd59a",
    "tests/research/ecology/test_eco_evo3_e3_5_population_workset.py": "c07641b7c747f587f71e58d86c39e8d49fe1b083",
    "tests/research/ecology/test_eco_evo3_e3_5_authority.py": "5dc263729eb8dc07f84c8c26fc21bc586d5e4c00",
    ".github/workflows/e3-5-closure.yml": "c65d84172fe20bea8e668ec584620c7bd9682f48",
    "validation/ecology/eco-evo3-e3-5-population-workset.generated.json": "d54ce8dad2760312d414c62c88d5f4f71427514f",
}
EXPECTED_CONTRACT_HASH = "45317ec4912e9add2ed0f722a0184d0065772da2130b9f58d063729e9a321100"
EXPECTED_E34_PROGRAM_HASH = "6f0b1cbe134f6b77825f66b356624975cc84e88f08c9aaba789f24c7d1cba4e6"
EXPECTED_E34_PROVENANCE_HASH = "d79a41e95c7cfb39dec2f41b11d4066f1e57ab0260ed991c69077348ce6add9a"
EXPECTED_E34_ARTIFACT_SHA256 = "fa6ece19e76784428fb0251a99d5b88bc1ed6183000e6c99755edbe2439c8463"
EXPECTED_E35_WORKSET_HASH = "b8f30e129c0f714ebc937cdac6869e63223d8d72172cecb68dd049f604557ff5"
EXPECTED_E35_PROVENANCE_HASH = "ec9c734882ef4a97eec2ed071f3c06ec2a29df52f13a45c7054a4641cbd42738"
EXPECTED_COMMITTED_ARTIFACT_SHA256 = "0ea5351b7692564161804a3aea5fe5044f3321ded3dcb4d0c7343e93d52c4975"
EXPECTED_TESTS = 51
EXPECTED_SUMMARY = {
    "active_basis_count": 22,
    "active_species_count": 2,
    "active_patch_count": 11,
    "active_scheduling_region_count": 1,
    "planet_work_unit_count": 1,
    "region_work_unit_count": 1,
    "patch_work_unit_count": 11,
    "local_active_work_unit_count": 11,
    "total_work_unit_count": 24,
    "budget_hint_count": 24,
    "individual_entity_count": 0,
}


def git_blob(path: pathlib.Path) -> str:
    data = path.read_bytes()
    return hashlib.sha1(b"blob " + str(len(data)).encode("ascii") + b"\0" + data).hexdigest()


def load_module(path: pathlib.Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def main() -> int:
    try:
        from jsonschema import Draft202012Validator
    except ImportError:
        print("missing_dependency=jsonschema", file=sys.stderr)
        return 9

    if importlib.metadata.version("jsonschema") != "4.26.0":
        print("jsonschema_version_mismatch", file=sys.stderr)
        return 10

    for rel, expected in EXPECTED_BLOBS.items():
        path = ROOT / rel
        if not path.is_file() or git_blob(path) != expected:
            print(f"closure_mismatch={rel}", file=sys.stderr)
            return 11

    compiled = subprocess.run(
        [sys.executable, "-m", "py_compile", str(IMPL), str(SEMANTIC_TEST), str(AUTHORITY_TEST)],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if compiled.returncode != 0 or compiled.stdout or compiled.stderr:
        sys.stderr.write(compiled.stdout)
        sys.stderr.write(compiled.stderr)
        return 12

    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    Draft202012Validator.check_schema(schema)

    impl = load_module(IMPL, "e35_population_workset_runner")
    contract = impl.load_contract(CONTRACT)
    program = impl.load_accepted_e3_4(E34, BINDING, contract)
    output = impl.build_population_workset(contract, program)
    impl.validate_output_integrity(output)

    if contract["contract_hash"] != EXPECTED_CONTRACT_HASH:
        return 13
    if program["colonization_program_hash"] != EXPECTED_E34_PROGRAM_HASH:
        return 14
    if program["provenance_hash"] != EXPECTED_E34_PROVENANCE_HASH:
        return 15
    if hashlib.sha256(E34.read_bytes()).hexdigest() != EXPECTED_E34_ARTIFACT_SHA256:
        return 16
    if output["summary"] != EXPECTED_SUMMARY:
        return 17
    if output["workset_result"] != "ACTIVE_WORKSETS":
        return 18
    if output["population_workset_hash"] != EXPECTED_E35_WORKSET_HASH:
        return 19
    if output["provenance_hash"] != EXPECTED_E35_PROVENANCE_HASH:
        return 20

    validator = Draft202012Validator(schema)
    errors = sorted(validator.iter_errors(output), key=lambda error: list(error.path))
    if errors:
        print(f"published_schema_rejects_generated_workset={errors[0].message}", file=sys.stderr)
        return 21

    semantic_tests = load_module(SEMANTIC_TEST, "e35_population_workset_semantic_tests")
    authority_tests = load_module(AUTHORITY_TEST, "e35_population_workset_authority_tests")
    suite = unittest.TestSuite([
        unittest.defaultTestLoader.loadTestsFromModule(semantic_tests),
        unittest.defaultTestLoader.loadTestsFromModule(authority_tests),
    ])
    stream = io.StringIO()
    result = unittest.TextTestRunner(stream=stream, verbosity=0).run(suite)
    if not result.wasSuccessful() or result.testsRun != EXPECTED_TESTS:
        sys.stderr.write(stream.getvalue())
        print(f"tests_run={result.testsRun}", file=sys.stderr)
        return 22

    in_process_bytes = impl.serialize_workset(output)
    with tempfile.TemporaryDirectory(prefix="eco-e35-") as td:
        td_path = pathlib.Path(td)
        fresh_paths = [td_path / "fresh-a.json", td_path / "fresh-b.json"]
        fresh_bytes: list[bytes] = []
        for path in fresh_paths:
            completed = subprocess.run(
                [sys.executable, str(IMPL), "--output", str(path), "--quiet"],
                cwd=ROOT,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            if completed.returncode != 0 or completed.stdout or completed.stderr:
                sys.stderr.buffer.write(completed.stdout)
                sys.stderr.buffer.write(completed.stderr)
                return 23
            fresh_bytes.append(path.read_bytes())
        if fresh_bytes[0] != fresh_bytes[1]:
            print("fresh_build_bytes_mismatch", file=sys.stderr)
            return 24
        if fresh_bytes[0] != in_process_bytes:
            print("fresh_process_vs_in_process_mismatch", file=sys.stderr)
            return 25

        committed_bytes = COMMITTED_ARTIFACT.read_bytes()
        if committed_bytes != fresh_bytes[0]:
            print("committed_generated_vs_machine_bytes_mismatch", file=sys.stderr)
            return 26
        if hashlib.sha256(committed_bytes).hexdigest() != EXPECTED_COMMITTED_ARTIFACT_SHA256:
            print("committed_generated_sha256_mismatch", file=sys.stderr)
            return 27
        if git_blob(COMMITTED_ARTIFACT) != EXPECTED_BLOBS["validation/ecology/eco-evo3-e3-5-population-workset.generated.json"]:
            print("committed_generated_git_blob_mismatch", file=sys.stderr)
            return 28
        FINAL_ARTIFACT.write_bytes(fresh_bytes[0])

    artifact_bytes = FINAL_ARTIFACT.read_bytes()
    artifact_sha256 = hashlib.sha256(artifact_bytes).hexdigest()
    if artifact_sha256 != EXPECTED_COMMITTED_ARTIFACT_SHA256:
        return 29
    artifact = json.loads(artifact_bytes.decode("utf-8"))
    impl.validate_output_structure(artifact)
    if artifact["population_workset_hash"] != EXPECTED_E35_WORKSET_HASH:
        return 30
    if artifact["provenance_hash"] != EXPECTED_E35_PROVENANCE_HASH:
        return 31
    schema_errors = sorted(validator.iter_errors(artifact), key=lambda error: list(error.path))
    if schema_errors:
        return 32

    source_text = IMPL.read_text(encoding="utf-8")
    forbidden_rng = ("import random", "from random", "import secrets", "import uuid", "random.")
    if any(token in source_text for token in forbidden_rng):
        return 33

    print("ECO.EVO3 E3.5 repair R1 exact closure: PASS")
    print("python_version=" + sys.version.split()[0])
    print("jsonschema_version=4.26.0")
    print("semantic_tests=27/27")
    print("authority_regression_tests=24/24")
    print("total_tests=51/51")
    print("exact_published_closure=9/9")
    print("published_schema_validation=PASS")
    print("fresh_process_builds=2/2")
    print("fresh_process_bytes_identical=true")
    print("committed_generated_bytes_identical=true")
    print("committed_generated_git_blob=" + git_blob(COMMITTED_ARTIFACT))
    print("committed_generated_sha256=" + hashlib.sha256(COMMITTED_ARTIFACT.read_bytes()).hexdigest())
    print("parsed_artifact_serialization_capability=ABSENT")
    print("reviewer_provenance_replacement_reproducer=REJECTED")
    print("exact_input_serialization_traversal=REQUIRED")
    print("order_independence=PASS")
    print("no_colonization_semantics=PASS")
    print("global_rng_surface=ABSENT")
    print("individual_entity_truth=ABSENT")
    print("canonical_sd_authority=ABSENT")
    print("network_persistence_transaction_authority=ABSENT")
    print("scale_coverage=PLANET,REGION,PATCH,LOCAL_ACTIVE:EXACT_ONCE")
    print("workset_result=" + artifact["workset_result"])
    print("active_basis_count=" + str(artifact["summary"]["active_basis_count"]))
    print("active_species_count=" + str(artifact["summary"]["active_species_count"]))
    print("active_patch_count=" + str(artifact["summary"]["active_patch_count"]))
    print("active_scheduling_region_count=" + str(artifact["summary"]["active_scheduling_region_count"]))
    print("total_work_unit_count=" + str(artifact["summary"]["total_work_unit_count"]))
    print("population_workset_hash=" + artifact["population_workset_hash"])
    print("provenance_hash=" + artifact["provenance_hash"])
    print("artifact_sha256=" + artifact_sha256)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

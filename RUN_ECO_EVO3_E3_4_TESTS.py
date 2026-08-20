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
CONTRACT = ROOT / "config/ecology/eco-evo3-e3-4-causal-colonization-contract.v1.json"
BINDING = ROOT / "config/ecology/accepted_inputs/e3_3_accepted_research_ecology_decomposition.binding.v1.json"
DECOMPOSITION = ROOT / "config/ecology/accepted_inputs/e3_3_candidate_research_ecology_decomposition.v1.json"
CATALOG = ROOT / "config/ecology/accepted_inputs/evo2_full_persisted_species_catalog.e3_4.v1.json"
SCHEMA = ROOT / "config/ecology/eco-evo3-e3-4-causal-colonization-program.schema.v1.json"
IMPL = ROOT / "scripts/research/ecology/causal_colonization_program_compiler_v1.py"
TEST = ROOT / "tests/research/ecology/test_eco_evo3_e3_4_causal_colonization.py"

EXPECTED_BLOBS = {
    "config/ecology/eco-evo3-e3-4-causal-colonization-contract.v1.json": "de38fbc06a2a733cfac52df5b0345f900f42f117",
    "config/ecology/accepted_inputs/e3_3_accepted_research_ecology_decomposition.binding.v1.json": "84660f5c60da2e7b9dcb9ace0d287321f303a94e",
    "config/ecology/accepted_inputs/e3_3_candidate_research_ecology_decomposition.v1.json": "9915bc13b0e81533fdc99ffe5707d0d60ba58eda",
    "config/ecology/accepted_inputs/evo2_full_persisted_species_catalog.e3_4.v1.json": "397ace0c6c7b204793b7663e7a89417d44ba3484",
    "config/ecology/eco-evo3-e3-4-causal-colonization-program.schema.v1.json": "95991eb62d90690b351d7522805ada2695d82898",
    "scripts/research/ecology/causal_colonization_program_compiler_v1.py": "46f424608a9d4e9bf9119b3700c3ba75b24197bd",
    "tests/research/ecology/test_eco_evo3_e3_4_causal_colonization.py": "91499b788c4d8908fdad272c4cc69289e905d71d",
}
EXPECTED_CONTRACT_HASH = "531172bc2ebdd4d13977d50afe25616a34bb0879fb8efa34d745ea3048b9d3d3"
EXPECTED_DECOMPOSITION_SHA256 = "cab0ec65d66f68f097c07b686e5e87ba998dfe39a9b587a3f945b10d0ac2029a"
EXPECTED_CATALOG_HASH = "5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219"
EXPECTED_CATALOG_ARTIFACT_SHA256 = "99d6dbf87d1a459e2f73f13959dcb53d9b0b8be1519bb5352622202954cf7d1e"
EXPECTED_E2_FINAL = "6daab256af3d1e7693c66a8afaad4d04fd1564c4376b9f3cd747a268a10c2250"
EXPECTED_HISTORICAL_ANCHOR = "f0e16195f1331f238bbacab2768e5d72ec01d1a3"
EXPECTED_PROGRAM_HASH = "6f0b1cbe134f6b77825f66b356624975cc84e88f08c9aaba789f24c7d1cba4e6"
EXPECTED_PROVENANCE_HASH = "d79a41e95c7cfb39dec2f41b11d4066f1e57ab0260ed991c69077348ce6add9a"
EXPECTED_ARTIFACT_SHA256 = "fa6ece19e76784428fb0251a99d5b88bc1ed6183000e6c99755edbe2439c8463"
EXPECTED_SUMMARY = {
    "input_species_count": 2,
    "colonized_species_count": 2,
    "filtered_species_count": 0,
    "colonized_patch_count": 11,
    "total_species_patch_establishments": 22,
    "no_colonization": False,
}
EXPECTED_TESTS = 48


def git_blob(path: pathlib.Path) -> str:
    data = path.read_bytes()
    return hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()


def load_module(path: pathlib.Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def main() -> int:
    try:
        from jsonschema import Draft202012Validator
    except ImportError:
        print("missing_dependency=jsonschema", file=sys.stderr)
        return 9

    for rel, expected in EXPECTED_BLOBS.items():
        path = ROOT / rel
        if not path.is_file() or git_blob(path) != expected:
            print(f"closure_mismatch={rel}", file=sys.stderr)
            return 10

    if hashlib.sha256(DECOMPOSITION.read_bytes()).hexdigest() != EXPECTED_DECOMPOSITION_SHA256:
        return 11
    if hashlib.sha256(CATALOG.read_bytes()).hexdigest() != EXPECTED_CATALOG_ARTIFACT_SHA256:
        return 12

    compiled = subprocess.run(
        [sys.executable, "-m", "py_compile", str(IMPL), str(TEST)],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if compiled.returncode or compiled.stdout or compiled.stderr:
        return 13

    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    try:
        Draft202012Validator.check_schema(schema)
    except Exception as exc:
        print(f"schema_invalid={type(exc).__name__}", file=sys.stderr)
        return 14

    impl = load_module(IMPL, "e34_colonization_runner")
    contract = impl.load_contract(CONTRACT)
    decomposition = impl.load_accepted_decomposition(DECOMPOSITION, BINDING, contract)
    catalog = impl.load_full_persisted_catalog(CATALOG, contract)
    output = impl.build_colonization_program(contract, decomposition, catalog)
    impl.validate_program_integrity(output)

    if contract["contract_hash"] != EXPECTED_CONTRACT_HASH:
        return 15
    if catalog["catalog_hash"] != EXPECTED_CATALOG_HASH:
        return 16
    if contract["persisted_evo2_catalog"]["e2_final_aggregate_hash"] != EXPECTED_E2_FINAL:
        return 17
    if contract["persisted_evo2_catalog"]["historical_eco_anchor"] != EXPECTED_HISTORICAL_ANCHOR:
        return 18
    if output["colonization_program_hash"] != EXPECTED_PROGRAM_HASH:
        return 19
    if output["provenance_hash"] != EXPECTED_PROVENANCE_HASH:
        return 20
    if output["summary"] != EXPECTED_SUMMARY:
        return 21
    if output["colonization_result"] != "COLONIZATION_PRESENT":
        return 22
    if len(output["input_species_manifest"]) != 2 or len(output["species_programs"]) != 2:
        return 23
    if any(item["status"] != "COLONIZED" for item in output["species_programs"]):
        return 24
    if any(len(item["established_patch_ids"]) != 11 for item in output["species_programs"]):
        return 25

    validator = Draft202012Validator(schema)
    errors = sorted(validator.iter_errors(output), key=lambda error: list(error.path))
    if errors:
        print(f"published_schema_rejects_generated_program={errors[0].message}", file=sys.stderr)
        return 26

    tests = load_module(TEST, "e34_acceptance_tests")
    suite = unittest.defaultTestLoader.loadTestsFromModule(tests)
    stream = io.StringIO()
    result = unittest.TextTestRunner(stream=stream, verbosity=0).run(suite)
    if not result.wasSuccessful() or result.testsRun != EXPECTED_TESTS:
        sys.stderr.write(stream.getvalue())
        return 27

    with tempfile.TemporaryDirectory(prefix="eco-e34-") as td:
        first = pathlib.Path(td) / "a.json"
        second = pathlib.Path(td) / "b.json"
        base = [
            sys.executable,
            str(IMPL),
            "--contract", str(CONTRACT),
            "--accepted-decomposition", str(DECOMPOSITION),
            "--accepted-decomposition-binding", str(BINDING),
            "--persisted-catalog", str(CATALOG),
            "--quiet",
            "--output",
        ]
        pa = subprocess.run(base + [str(first)], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        pb = subprocess.run(base + [str(second)], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if pa.returncode or pb.returncode or pa.stdout or pb.stdout or pa.stderr or pb.stderr:
            return 28
        a = first.read_bytes()
        b = second.read_bytes()
        if a != b:
            return 29
        if hashlib.sha256(a).hexdigest() != EXPECTED_ARTIFACT_SHA256:
            return 30
        fresh = json.loads(a.decode("utf-8"))
        if fresh["colonization_program_hash"] != EXPECTED_PROGRAM_HASH:
            return 31
        errors = sorted(validator.iter_errors(fresh), key=lambda error: list(error.path))
        if errors:
            print(f"fresh_artifact_schema_rejected={errors[0].message}", file=sys.stderr)
            return 32

    print("ECO.EVO3 E3.4 Causal Colonization Program Compiler: PASS")
    print("semantic_tests=48/48")
    print("negative_matrix=PASS")
    print("published_schema_validation=PASS")
    print("closure_blobs=7/7")
    print("full_persisted_catalog_entries=2/2")
    print("fresh_colonization_builds=2/2")
    print("fresh_colonization_bytes_identical=true")
    print("colonization_result=COLONIZATION_PRESENT")
    print("colonized_species_count=2")
    print("colonized_patch_count=11")
    print("total_species_patch_establishments=22")
    print("no_colonization_negative_case=PASS")
    print(f'jsonschema_version={importlib.metadata.version("jsonschema")}')
    print(f"contract_hash={EXPECTED_CONTRACT_HASH}")
    print(f"catalog_hash={EXPECTED_CATALOG_HASH}")
    print(f"decomposition_artifact_sha256={EXPECTED_DECOMPOSITION_SHA256}")
    print(f"catalog_artifact_sha256={EXPECTED_CATALOG_ARTIFACT_SHA256}")
    print(f"program_hash={EXPECTED_PROGRAM_HASH}")
    print(f"provenance_hash={EXPECTED_PROVENANCE_HASH}")
    print(f"artifact_sha256={EXPECTED_ARTIFACT_SHA256}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

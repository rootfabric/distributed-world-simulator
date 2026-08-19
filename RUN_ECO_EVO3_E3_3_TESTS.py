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
CONTRACT = ROOT / "config/ecology/eco-evo3-e3-3-research-ecology-decomposition-contract.v1.json"
FIELD = ROOT / "config/ecology/accepted_inputs/e3_2_accepted_ecological_opportunity_field.v1.json"
SCHEMA = ROOT / "config/ecology/eco-evo3-e3-3-research-ecology-decomposition.schema.v1.json"
IMPL = ROOT / "scripts/research/ecology/research_ecology_decomposition_v1.py"
TEST = ROOT / "tests/research/ecology/test_eco_evo3_e3_3_research_ecology_decomposition.py"

EXPECTED_BLOBS = {
    "config/ecology/eco-evo3-e3-3-research-ecology-decomposition-contract.v1.json": "784cc3aef012a3647bf8010436ff2dac6f6446f4",
    "config/ecology/accepted_inputs/e3_2_accepted_ecological_opportunity_field.v1.json": "68e601958b1206235729aceb40843cd8666840aa",
    "config/ecology/eco-evo3-e3-3-research-ecology-decomposition.schema.v1.json": "80454d5ba92553b58f598a237bf3b7815773ad33",
    "scripts/research/ecology/research_ecology_decomposition_v1.py": "02fbc95fe94f51b09970b1d17c4a629c692f500d",
    "tests/research/ecology/test_eco_evo3_e3_3_research_ecology_decomposition.py": "9268abdbb96231f24bcbaab7d4692371e5e9dbe8",
}
EXPECTED_CONTRACT = "593b1889198021e2fcdae0c3746bdbe771d606427f07a7ccfc7c8a530cebec9f"
EXPECTED_SOURCE_FIELD = "acba61638f8128b667880f2bd391ab73f6175d0899656bba92657d578d48203c"
EXPECTED_SOURCE_ARTIFACT = "59a0af5e40cae5c8a91e487da158edadfd4e127a0390ebe856f78f2365a066ff"
EXPECTED_PROVENANCE = "76cf3fac25f7c7f52309d9c38befb3c50321e652eacb3a58731473646d680e02"
EXPECTED_DECOMPOSITION = "9736ec70f844c930f8e160a4f08ae8e0aae1cce6f73fbf106499bea15b15a51a"
EXPECTED_ARTIFACT = "cab0ec65d66f68f097c07b686e5e87ba998dfe39a9b587a3f945b10d0ac2029a"
EXPECTED_SUMMARY = {
    "patch_count": 12,
    "edge_count": 10,
    "region_count": 2,
    "singleton_region_count": 1,
    "largest_region_patch_count": 11,
}
EXPECTED_TESTS = 60


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

    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    try:
        Draft202012Validator.check_schema(schema)
    except Exception as exc:
        print(f"schema_invalid={type(exc).__name__}", file=sys.stderr)
        return 20

    compiled = subprocess.run(
        [sys.executable, "-m", "py_compile", str(IMPL), str(TEST)],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if compiled.returncode or compiled.stdout or compiled.stderr:
        return 11

    impl = load_module(IMPL, "e33_decomposition_runner")
    contract = impl.load_json(CONTRACT)
    field = impl.load_accepted_opportunity_field(FIELD, contract)
    output = impl.build_decomposition(contract, field)

    if contract["contract_hash"] != EXPECTED_CONTRACT:
        return 12
    if field["opportunity_field_hash"] != EXPECTED_SOURCE_FIELD:
        return 13
    if hashlib.sha256(FIELD.read_bytes()).hexdigest() != EXPECTED_SOURCE_ARTIFACT:
        return 14
    if output["decomposition_provenance_hash"] != EXPECTED_PROVENANCE:
        return 15
    if output["decomposition_hash"] != EXPECTED_DECOMPOSITION:
        return 16
    if output["summary"] != EXPECTED_SUMMARY:
        return 17

    validator = Draft202012Validator(schema)
    errors = sorted(validator.iter_errors(output), key=lambda error: list(error.path))
    if errors:
        print(f"published_schema_rejects_generated_decomposition={errors[0].message}", file=sys.stderr)
        return 21

    tests = load_module(TEST, "e33_acceptance_tests")
    suite = unittest.defaultTestLoader.loadTestsFromModule(tests)
    stream = io.StringIO()
    result = unittest.TextTestRunner(stream=stream, verbosity=0).run(suite)
    if not result.wasSuccessful() or result.testsRun != EXPECTED_TESTS:
        sys.stderr.write(stream.getvalue())
        return 18

    with tempfile.TemporaryDirectory(prefix="eco-e33-") as td:
        first = pathlib.Path(td) / "a.json"
        second = pathlib.Path(td) / "b.json"
        base = [
            sys.executable,
            str(IMPL),
            "--contract", str(CONTRACT),
            "--accepted-field", str(FIELD),
            "--quiet",
            "--output",
        ]
        pa = subprocess.run(base + [str(first)], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        pb = subprocess.run(base + [str(second)], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if pa.returncode or pb.returncode or pa.stdout or pb.stdout or pa.stderr or pb.stderr:
            return 19
        a = first.read_bytes()
        b = second.read_bytes()
        if a != b:
            return 22
        if hashlib.sha256(a).hexdigest() != EXPECTED_ARTIFACT:
            return 23
        fresh = json.loads(a.decode("utf-8"))
        errors = sorted(validator.iter_errors(fresh), key=lambda error: list(error.path))
        if errors:
            print(f"fresh_artifact_schema_rejected={errors[0].message}", file=sys.stderr)
            return 24

    print("ECO.EVO3 E3.3 Research Ecology Decomposition: PASS")
    print("semantic_tests=60/60")
    print("published_schema_validation=PASS")
    print("closure_blobs=5/5")
    print("fresh_decomposition_builds=2/2")
    print("fresh_decomposition_bytes_identical=true")
    print("patch_count=12")
    print("edge_count=10")
    print("region_count=2")
    print("singleton_region_count=1")
    print(f'jsonschema_version={importlib.metadata.version("jsonschema")}')
    print(f"contract_hash={EXPECTED_CONTRACT}")
    print(f"source_opportunity_field_hash={EXPECTED_SOURCE_FIELD}")
    print(f"source_field_artifact_sha256={EXPECTED_SOURCE_ARTIFACT}")
    print(f"decomposition_provenance_hash={EXPECTED_PROVENANCE}")
    print(f"decomposition_hash={EXPECTED_DECOMPOSITION}")
    print(f"decomposition_artifact_sha256={EXPECTED_ARTIFACT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

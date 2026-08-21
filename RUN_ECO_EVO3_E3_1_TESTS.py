#!/usr/bin/env python3
from __future__ import annotations
import hashlib, importlib.util, io, json, pathlib, subprocess, sys, tempfile, unittest
ROOT=pathlib.Path(__file__).resolve().parent
CONTRACT=ROOT/"config/ecology/eco-evo3-e3-1-planet-field-snapshot-contract.v1.json"; SCHEMA=ROOT/"config/ecology/eco-evo3-e3-1-planet-field-snapshot.schema.v1.json"; FIXTURE=ROOT/"fixtures/research/ecology/evo3/e3_1_planet_field_semantic_fixture.v1.json"; IMPL=ROOT/"scripts/research/ecology/planet_field_snapshot_v1.py"; TEST=ROOT/"tests/research/ecology/test_eco_evo3_e3_1_planet_field_snapshot.py"
EXPECTED_CONTRACT="b3e96b432008ea93692c5cbde9cf7c74cceca4e4c4196ef261a5fbd0ff405170"; EXPECTED_FIXTURE="3e22d87666b13a4bafcdd5dd3184097b53b221103fd2f9e9f2be452c8ab79978"; EXPECTED_PROVENANCE="3827c1da7d94227fb04b5fbfbd93fd5262c826cd86503af9f540a120431a82c3"; EXPECTED_SNAPSHOT="2ceb042d905b06ae76acc699b60ed6c115d3e0ac7943ce7cbe0c94f962447b00"; EXPECTED_TESTS=32
def load_module(path,name):
    spec=importlib.util.spec_from_file_location(name,path); m=importlib.util.module_from_spec(spec); assert spec.loader; sys.modules[name]=m; spec.loader.exec_module(m); return m
def main():
    for p in (CONTRACT,SCHEMA,FIXTURE,IMPL,TEST):
        if not p.is_file(): raise SystemExit(f"missing:{p.relative_to(ROOT)}")
    json.loads(SCHEMA.read_text()); subprocess.run([sys.executable,"-m","py_compile",str(IMPL),str(TEST)],cwd=ROOT,check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    impl=load_module(IMPL,"e31_planet_field_snapshot"); contract=impl.load_json(CONTRACT); fixture=impl.load_json(FIXTURE); snapshot=impl.build_snapshot(contract,fixture)
    if contract["contract_hash"]!=EXPECTED_CONTRACT or fixture["fixture_hash"]!=EXPECTED_FIXTURE or snapshot["field_provenance_hash"]!=EXPECTED_PROVENANCE or snapshot["snapshot_hash"]!=EXPECTED_SNAPSHOT: return 4
    tm=load_module(TEST,"e31_acceptance_tests"); suite=unittest.defaultTestLoader.loadTestsFromModule(tm); stream=io.StringIO(); result=unittest.TextTestRunner(stream=stream,verbosity=0).run(suite)
    if not result.wasSuccessful() or result.testsRun!=EXPECTED_TESTS: sys.stderr.write(stream.getvalue()); return 1
    with tempfile.TemporaryDirectory(prefix="eco-e31-") as td:
        a=pathlib.Path(td)/"a.json"; b=pathlib.Path(td)/"b.json"; base=[sys.executable,str(IMPL),"--contract",str(CONTRACT),"--fixture",str(FIXTURE),"--quiet","--output"]
        pa=subprocess.run(base+[str(a)],cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE); pb=subprocess.run(base+[str(b)],cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        if pa.returncode or pb.returncode or pa.stdout or pb.stdout or pa.stderr or pb.stderr: return 2
        ab=a.read_bytes(); bb=b.read_bytes()
        if ab!=bb: return 3
        artifact_sha=hashlib.sha256(ab).hexdigest()
    print("ECO.EVO3 E3.1 Planet Field Snapshot Contract: PASS"); print("semantic_tests=32/32"); print("fresh_snapshot_builds=2/2"); print("fresh_snapshot_bytes_identical=true"); print("sample_count=12"); print(f"contract_hash={EXPECTED_CONTRACT}"); print(f"fixture_hash={EXPECTED_FIXTURE}"); print(f"field_provenance_hash={EXPECTED_PROVENANCE}"); print(f"snapshot_hash={EXPECTED_SNAPSHOT}"); print(f"snapshot_artifact_sha256={artifact_sha}"); return 0
if __name__=="__main__": raise SystemExit(main())

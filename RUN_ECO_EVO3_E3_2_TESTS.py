#!/usr/bin/env python3
from __future__ import annotations
import hashlib, importlib.util, io, json, pathlib, subprocess, sys, tempfile, unittest
ROOT=pathlib.Path(__file__).resolve().parent
CONTRACT=ROOT/'config/ecology/eco-evo3-e3-2-ecological-opportunity-field-contract.v1.json'
SCHEMA=ROOT/'config/ecology/eco-evo3-e3-2-ecological-opportunity-field.schema.v1.json'
SNAPSHOT=ROOT/'config/ecology/accepted_inputs/e3_1_accepted_planet_field_snapshot.v1.json'
IMPL=ROOT/'scripts/research/ecology/ecological_opportunity_field_v1.py'
TEST=ROOT/'tests/research/ecology/test_eco_evo3_e3_2_ecological_opportunity_field.py'
EXPECTED_BLOBS={
 'config/ecology/eco-evo3-e3-2-ecological-opportunity-field-contract.v1.json':'bb1f09c7b2c10887749c1b89693a503318368335',
 'config/ecology/accepted_inputs/e3_1_accepted_planet_field_snapshot.v1.json':'0d5f8b6b66b56195770af94ed2d847b5c84751c5',
 'config/ecology/eco-evo3-e3-2-ecological-opportunity-field.schema.v1.json':'46134f36d18a13f3811a0836b2773a66d5c6bb33',
 'scripts/research/ecology/ecological_opportunity_field_v1.py':'a38ef6122426fa2e551b213c8d0ad2bc39799ec0',
 'tests/research/ecology/test_eco_evo3_e3_2_ecological_opportunity_field.py':'8ad2ba1e15eadf24a74555c41de938a9cb7dedc6',
}
EXPECTED_CONTRACT='bbb2e4f29ac88da42102ee6c08d239f8e0a72760ab8d1371fdea2cda258ed47d'
EXPECTED_SNAPSHOT='2ceb042d905b06ae76acc699b60ed6c115d3e0ac7943ce7cbe0c94f962447b00'
EXPECTED_SNAPSHOT_ARTIFACT='5123ebd58e6eade5d3dab2325af49a43234bc8834182ddd7db7d6c463896b790'
EXPECTED_FIELD_PROVENANCE='9be81517eaf0c28503291c5595c0790232b8f88c7ffa9ced2e886ec1f8597aa4'
EXPECTED_FIELD='acba61638f8128b667880f2bd391ab73f6175d0899656bba92657d578d48203c'
EXPECTED_FIELD_ARTIFACT='59a0af5e40cae5c8a91e487da158edadfd4e127a0390ebe856f78f2365a066ff'
EXPECTED_TESTS=42

def git_blob(path:pathlib.Path)->str:
 b=path.read_bytes(); return hashlib.sha1(b'blob '+str(len(b)).encode()+b'\0'+b).hexdigest()
def load_module(path,name):
 spec=importlib.util.spec_from_file_location(name,path); m=importlib.util.module_from_spec(spec); assert spec.loader; sys.modules[name]=m; spec.loader.exec_module(m); return m
def main()->int:
 for rel,expected in EXPECTED_BLOBS.items():
  p=ROOT/rel
  if not p.is_file() or git_blob(p)!=expected:
   print(f'closure_mismatch={rel}',file=sys.stderr); return 10
 json.loads(SCHEMA.read_text(encoding='utf-8'))
 compile_run=subprocess.run([sys.executable,'-m','py_compile',str(IMPL),str(TEST)],cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
 if compile_run.returncode or compile_run.stdout or compile_run.stderr: return 11
 impl=load_module(IMPL,'e32_opportunity_field_runner')
 contract=impl.load_json(CONTRACT); snapshot=impl.load_accepted_snapshot(SNAPSHOT,contract); field=impl.build_opportunity_field(contract,snapshot)
 if contract['contract_hash']!=EXPECTED_CONTRACT: return 12
 if snapshot['snapshot_hash']!=EXPECTED_SNAPSHOT or hashlib.sha256(SNAPSHOT.read_bytes()).hexdigest()!=EXPECTED_SNAPSHOT_ARTIFACT: return 13
 if field['field_provenance_hash']!=EXPECTED_FIELD_PROVENANCE or field['opportunity_field_hash']!=EXPECTED_FIELD: return 14
 if field['summary']!={'sample_count':12,'limiting_resource_min_ppm':120000,'limiting_resource_max_ppm':700000,'limiting_resource_mean_ppm':390833,'establishment_min_ppm':52500,'establishment_max_ppm':402600,'establishment_mean_ppm':262050}: return 15
 tm=load_module(TEST,'e32_acceptance_tests'); suite=unittest.defaultTestLoader.loadTestsFromModule(tm); stream=io.StringIO(); result=unittest.TextTestRunner(stream=stream,verbosity=0).run(suite)
 if not result.wasSuccessful() or result.testsRun!=EXPECTED_TESTS:
  sys.stderr.write(stream.getvalue()); return 16
 with tempfile.TemporaryDirectory(prefix='eco-e32-') as td:
  a=pathlib.Path(td)/'a.json'; b=pathlib.Path(td)/'b.json'; base=[sys.executable,str(IMPL),'--contract',str(CONTRACT),'--snapshot',str(SNAPSHOT),'--quiet','--output']
  pa=subprocess.run(base+[str(a)],cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE); pb=subprocess.run(base+[str(b)],cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
  if pa.returncode or pb.returncode or pa.stdout or pb.stdout or pa.stderr or pb.stderr: return 17
  ab=a.read_bytes(); bb=b.read_bytes()
  if ab!=bb: return 18
  artifact=hashlib.sha256(ab).hexdigest()
  if artifact!=EXPECTED_FIELD_ARTIFACT: return 19
 print('ECO.EVO3 E3.2 Ecological Opportunity Field: PASS')
 print('semantic_tests=42/42')
 print('closure_blobs=5/5')
 print('fresh_field_builds=2/2')
 print('fresh_field_bytes_identical=true')
 print('sample_count=12')
 print(f'contract_hash={EXPECTED_CONTRACT}')
 print(f'source_snapshot_hash={EXPECTED_SNAPSHOT}')
 print(f'snapshot_artifact_sha256={EXPECTED_SNAPSHOT_ARTIFACT}')
 print(f'field_provenance_hash={EXPECTED_FIELD_PROVENANCE}')
 print(f'opportunity_field_hash={EXPECTED_FIELD}')
 print('establishment_mean_ppm=262050')
 print(f'field_artifact_sha256={EXPECTED_FIELD_ARTIFACT}')
 return 0
if __name__=='__main__': raise SystemExit(main())

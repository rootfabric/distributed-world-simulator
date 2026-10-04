import copy, importlib.util, json, tempfile, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
spec=importlib.util.spec_from_file_location("r53",ROOT/"scripts/research/fabric_bake0/collect_r5_3_evidence.py");c=importlib.util.module_from_spec(spec);spec.loader.exec_module(c)
class T(unittest.TestCase):
 def payload(self):
  d=dict(c.EXPECTED,schema="fabric.r5_3.recursive_rom.result.v1",failures=[],max_flow_error=1e-13,max_power_error=1e-11,baseline_expanded_system_hash="a"*64,final_expanded_system_hash="b"*64,final_root_node_hash="c"*64,final_root_capsule_checksum="d"*64)
  return d
 def test_valid(self):c.validate(self.payload())
 def test_counts_fail_closed(self):
  for k in c.EXPECTED:
   d=self.payload();d[k]=d[k]+1
   with self.subTest(k=k),self.assertRaises(ValueError):c.validate(d)
 def test_bool_not_int(self):
  d=self.payload();d["checks"]=True
  with self.assertRaises(ValueError):c.validate(d)
 def test_hashes(self):
  for k in ("baseline_expanded_system_hash","final_expanded_system_hash","final_root_node_hash","final_root_capsule_checksum"):
   d=self.payload();d[k]=""
   with self.subTest(k=k),self.assertRaises(ValueError):c.validate(d)
 def test_bounds(self):
  for k,v in (("max_flow_error",1.0),("max_power_error",float("nan"))):
   d=self.payload();d[k]=v
   with self.assertRaises(ValueError):c.validate(d)
 def test_strict_json(self):
  for x in ('{"x":NaN}','{"x":1,"x":2}','[]'):
   with self.assertRaises(ValueError):c.strict(x)
 def test_sample(self):
  with tempfile.TemporaryDirectory() as td:
   p=Path(td)/"s.log";good=c.PREFIX+json.dumps(self.payload())+"\n"+c.PASS+"\n";p.write_text(good);c.sample(p)
   for bad in (good+"ERROR: x",good+good,good.replace(c.PASS,"FAIL")):
    p.write_text(bad)
    with self.assertRaises(ValueError):c.sample(p)
 def test_runtime_source_contract(self):
  runtime=(ROOT/"scripts/research/fabric_bake0/r5_3_recursive_rom_runtime_v1.gd").read_text();compiler=(ROOT/"scripts/research/fabric_bake0/r5_3_recursive_rom_compiler_v1.gd").read_text()
  self.assertNotIn("res://tests/",runtime);self.assertNotIn("res://tests/",compiler);self.assertIn("runtime_source_component_traversals\":0",runtime);self.assertIn("Reducer.reduce",compiler);self.assertNotIn("MIN_INTERNAL_VARIABLES",compiler)
if __name__=="__main__":unittest.main()

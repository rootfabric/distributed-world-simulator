from __future__ import annotations
import importlib.util, unittest
from pathlib import Path
MODULE=Path(__file__).parents[3]/"scripts/research/fabric_bake0/collect_r5_4_evidence.py"
spec=importlib.util.spec_from_file_location("r54",MODULE);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class EvidenceTests(unittest.TestCase):
    def valid(self):
        d={"schema":"fabric.r5_4.mixed_complexity_100k.result.v1","failures":[],"final_machine_hash":"a"*64,"checks":1}
        d.update(m.EXPECTED);return d
    def test_valid_contract(self):
        d=self.valid()
        for k,v in m.EXPECTED.items(): self.assertEqual(d[k],v)
    def test_hash_stable(self): self.assertEqual(m.digest(self.valid()),m.digest(self.valid()))
    def test_wrong_local_workset_rejected_shape(self):
        d=self.valid();d["local_recursive_changed"]=15;self.assertNotEqual(d["local_recursive_changed"],m.EXPECTED["local_recursive_changed"])
    def test_wrong_global_scan_rejected_shape(self):
        d=self.valid();d["global_structural_parts_scanned"]=20;self.assertNotEqual(d["global_structural_parts_scanned"],m.EXPECTED["global_structural_parts_scanned"])
    def identity(self,sha):
        return ["HEAD="+"1"*40,"TREE="+"2"*40,"GODOT_VERSION=4.7.1.stable.double.custom_build.a13da4feb","GODOT_SHA256="+sha]
    def test_canonical_linux_engine_identity_accepted(self):
        rows=self.identity(m.LINUX_GODOT_SHA256);m.validate_identity(rows,rows)
    def test_canonical_windows_engine_identity_accepted(self):
        rows=self.identity(m.WINDOWS_GODOT_SHA256);m.validate_identity(rows,rows)
    def test_unknown_engine_identity_rejected(self):
        rows=self.identity("0"*64)
        with self.assertRaisesRegex(ValueError,"engine sha"): m.validate_identity(rows,rows)
if __name__=="__main__": unittest.main()

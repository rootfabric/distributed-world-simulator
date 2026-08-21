from __future__ import annotations
import copy, importlib.util, pathlib, sys, unittest
ROOT = pathlib.Path(__file__).resolve().parents[3]
MODULE_PATH = ROOT / "scripts/research/ecology/planet_field_snapshot_v1.py"
CONTRACT_PATH = ROOT / "config/ecology/eco-evo3-e3-1-planet-field-snapshot-contract.v1.json"
FIXTURE_PATH = ROOT / "fixtures/research/ecology/evo3/e3_1_planet_field_semantic_fixture.v1.json"
spec = importlib.util.spec_from_file_location("planet_field_snapshot_v1", MODULE_PATH); mod = importlib.util.module_from_spec(spec); assert spec.loader is not None; sys.modules[spec.name]=mod; spec.loader.exec_module(mod)
def rehash(o,f): o[f]=mod.object_hash(o,f)
def rehash_fixture(f):
    for s in f["samples"]: rehash(s,"sample_hash")
    rehash(f,"fixture_hash")
def rehash_snapshot(s): rehash(s,"snapshot_hash")
class E31PlanetFieldSnapshotTests(unittest.TestCase):
    def setUp(self):
        self.contract=mod.load_json(CONTRACT_PATH); self.fixture=mod.load_json(FIXTURE_PATH); self.snapshot=mod.build_snapshot(self.contract,self.fixture)
    def rejected(self,fn):
        with self.assertRaises(ValueError): fn()
    def test_01_contract_valid(self): mod.validate_contract(self.contract)
    def test_02_fixture_valid(self): mod.validate_fixture(self.fixture,self.contract)
    def test_03_snapshot_valid(self): mod.validate_snapshot(self.snapshot,self.contract,self.fixture)
    def test_04_deterministic_same_process(self): self.assertEqual(mod.canonical_bytes(self.snapshot),mod.canonical_bytes(mod.build_snapshot(self.contract,self.fixture)))
    def test_05_foundations_exact(self): self.assertEqual(list(self.snapshot["foundation_manifest"]),["G","ENV","MAT","WQ","SD","TF"])
    def test_06_sample_count_order(self):
        keys=[x["stable_spatial_key"] for x in self.snapshot["samples"]]; self.assertEqual(len(keys),12); self.assertEqual(keys,sorted(keys))
    def test_07_parent_substitution(self):
        c=copy.deepcopy(self.contract); c["parent"]["e3_0_code_under_test_head"]="0"*40; rehash(c,"contract_hash"); self.rejected(lambda:mod.validate_contract(c))
    def test_08_xfer0_substitution(self):
        c=copy.deepcopy(self.contract); c["parent"]["xfer0_contract_hash"]="0"*64; rehash(c,"contract_hash"); self.rejected(lambda:mod.validate_contract(c))
    def test_09_missing_foundation_contract(self):
        c=copy.deepcopy(self.contract); c["binding"]["required_foundations"].remove("TF"); rehash(c,"contract_hash"); self.rejected(lambda:mod.validate_contract(c))
    def test_10_production_binding(self):
        c=copy.deepcopy(self.contract); c["binding"]["production_api_binding_authorized"]=True; rehash(c,"contract_hash"); self.rejected(lambda:mod.validate_contract(c))
    def test_11_canonical_binding_contract(self):
        c=copy.deepcopy(self.contract); c["binding"]["canonical_bindings_resolved"]=True; rehash(c,"contract_hash"); self.rejected(lambda:mod.validate_contract(c))
    def test_12_owner_write(self):
        c=copy.deepcopy(self.contract); c["binding"]["compiler_may_write_owner_state"]=True; rehash(c,"contract_hash"); self.rejected(lambda:mod.validate_contract(c))
    def test_13_float_policy(self):
        c=copy.deepcopy(self.contract); c["snapshot_semantics"]["numeric_encoding"]="JSON_FLOATS"; rehash(c,"contract_hash"); self.rejected(lambda:mod.validate_contract(c))
    def test_14_fixture_foundation_canonical(self):
        f=copy.deepcopy(self.fixture); f["foundation_references"]["ENV"]["canonical_binding_resolved"]=True; rehash_fixture(f); self.rejected(lambda:mod.validate_fixture(f,self.contract))
    def test_15_fixture_missing_foundation(self):
        f=copy.deepcopy(self.fixture); del f["foundation_references"]["WQ"]; rehash_fixture(f); self.rejected(lambda:mod.validate_fixture(f,self.contract))
    def test_16_duplicate_spatial_key(self):
        f=copy.deepcopy(self.fixture); f["samples"][1]["stable_spatial_key"]=f["samples"][0]["stable_spatial_key"]; rehash_fixture(f); self.rejected(lambda:mod.validate_fixture(f,self.contract))
    def test_17_out_of_bounds(self):
        f=copy.deepcopy(self.fixture); f["samples"][0]["soil_moisture_ppm"]=1000001; rehash_fixture(f); self.rejected(lambda:mod.validate_fixture(f,self.contract))
    def test_18_non_integer(self):
        f=copy.deepcopy(self.fixture); f["samples"][0]["temperature_milli_c"]=12.5; rehash_fixture(f); self.rejected(lambda:mod.validate_fixture(f,self.contract))
    def test_19_raw_sample_hash_tamper(self):
        f=copy.deepcopy(self.fixture); f["samples"][0]["temperature_milli_c"]+=1; rehash(f,"fixture_hash"); self.rejected(lambda:mod.validate_fixture(f,self.contract))
    def test_20_biome_injection(self):
        f=copy.deepcopy(self.fixture); f["samples"][0]["biome_label"]="dry"; rehash_fixture(f); self.rejected(lambda:mod.validate_fixture(f,self.contract))
    def test_21_species_injection(self):
        f=copy.deepcopy(self.fixture); f["samples"][0]["species_assignment"]="x"; rehash_fixture(f); self.rejected(lambda:mod.validate_fixture(f,self.contract))
    def test_22_population_injection(self):
        f=copy.deepcopy(self.fixture); f["population_truth"]={}; rehash_fixture(f); self.rejected(lambda:mod.validate_fixture(f,self.contract))
    def test_23_snapshot_authority(self):
        s=copy.deepcopy(self.snapshot); s["authority"]="CANONICAL_WORLD_STATE"; rehash_snapshot(s); self.rejected(lambda:mod.validate_snapshot(s,self.contract))
    def test_24_snapshot_canonical_binding(self):
        s=copy.deepcopy(self.snapshot); s["canonical_binding_resolved"]=True; rehash_snapshot(s); self.rejected(lambda:mod.validate_snapshot(s,self.contract))
    def test_25_snapshot_reorder(self):
        s=copy.deepcopy(self.snapshot); s["samples"][0],s["samples"][1]=s["samples"][1],s["samples"][0]; rehash_snapshot(s); self.rejected(lambda:mod.validate_snapshot(s,self.contract))
    def test_26_snapshot_species_field(self):
        s=copy.deepcopy(self.snapshot); s["species_assignment"]=[]; rehash_snapshot(s); self.rejected(lambda:mod.validate_snapshot(s,self.contract))
    def test_27_foundation_change_provenance(self):
        f=copy.deepcopy(self.fixture); f["foundation_references"]["ENV"]["semantic_reference"]+="/changed"; rehash_fixture(f); x=mod.build_snapshot(self.contract,f); self.assertNotEqual(x["field_provenance_hash"],self.snapshot["field_provenance_hash"])
    def test_28_field_change_snapshot_hash(self):
        f=copy.deepcopy(self.fixture); f["samples"][0]["temperature_milli_c"]+=1; rehash_fixture(f); x=mod.build_snapshot(self.contract,f); self.assertNotEqual(x["snapshot_hash"],self.snapshot["snapshot_hash"])
    def test_29_fixture_hash_bound(self): self.assertEqual(self.snapshot["source_fixture_hash"],self.fixture["fixture_hash"])
    def test_30_per_sample_provenance(self):
        v=[x["field_provenance_hash"] for x in self.snapshot["samples"]]; self.assertEqual(len(v),12); self.assertEqual(len(set(v)),12)
    def test_31_no_rng_import(self):
        src=MODULE_PATH.read_text(); self.assertNotIn("import random",src); self.assertNotIn("from random",src); self.assertNotIn("import secrets",src)
    def test_32_no_biome_species_population_snapshot(self):
        t=mod.canonical_bytes(self.snapshot).decode().lower(); self.assertNotIn("biome",t); self.assertNotIn("species",t); self.assertNotIn("population",t)
if __name__ == "__main__": unittest.main()

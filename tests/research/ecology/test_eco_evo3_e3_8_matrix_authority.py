from __future__ import annotations

import copy
import importlib.util
import inspect
import json
import pathlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
IMPL = ROOT / "scripts/research/ecology/cross_planet_generalization_matrix_v1.py"


def load_impl():
    spec = importlib.util.spec_from_file_location("e38_impl_authority", IMPL)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class TestE38MatrixAuthorityBoundary(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = load_impl()
        cls.inputs = cls.mod.load_verified_inputs()
        cls.matrix = cls.mod.build_planet_generalization_matrix(cls.inputs)

    def _plain_variants(self):
        exact = self.mod.serialize_planet_generalization_matrix(self.matrix)
        plain = json.loads(exact.decode("utf-8"))
        forged = copy.deepcopy(plain)
        forged["authority"] = "PRODUCTION_AUTHORITATIVE"
        forged["cross_planet_generalization_matrix_hash"] = self.mod.object_hash(forged, "cross_planet_generalization_matrix_hash")
        mutated = copy.deepcopy(plain)
        mutated["families"][0]["summary"]["established_patch_total"] += 1
        mutated["cross_planet_generalization_matrix_hash"] = self.mod.object_hash(mutated, "cross_planet_generalization_matrix_hash")
        return plain, forged, mutated

    def test_01_plain_dict_cannot_build(self):
        with self.assertRaises(ValueError):
            self.mod.build_planet_generalization_matrix({
                "contract": dict(self.inputs.contract),
                "snapshot": dict(self.inputs.snapshot),
                "catalog": dict(self.inputs.catalog),
            })

    def test_02_plain_reconstructed_json_cannot_serialize(self):
        plain = self._plain_variants()[0]
        with self.assertRaises(ValueError):
            self.mod.serialize_planet_generalization_matrix(plain)

    def test_03_generic_exact_final_byte_helper_absent(self):
        self.assertFalse(hasattr(self.mod, "serialized_bytes"))

    def test_04_all_public_matrix_finalization_surfaces_reject_plain_and_forged_dicts(self):
        surfaces = sorted(
            name
            for name, value in vars(self.mod).items()
            if inspect.isfunction(value)
            and value.__module__ == self.mod.__name__
            and not name.startswith("_")
            and any(token in name.lower() for token in ("serial", "final", "write"))
        )
        self.assertEqual(surfaces, ["serialize_planet_generalization_matrix", "write_planet_generalization_matrix"])
        for variant in self._plain_variants():
            with self.subTest(surface="serialize_planet_generalization_matrix"):
                with self.assertRaises(ValueError):
                    self.mod.serialize_planet_generalization_matrix(variant)
            with tempfile.TemporaryDirectory() as td:
                output = pathlib.Path(td) / "unauthorized.json"
                with self.subTest(surface="write_planet_generalization_matrix"):
                    with self.assertRaises(ValueError):
                        self.mod.write_planet_generalization_matrix(variant, output)
                    self.assertFalse(output.exists())

    def test_05_mutated_verified_matrix_rejected(self):
        mutated = self.mod._VerifiedGeneralizationMatrix(dict(self.matrix), self.inputs)
        mutated["families"][0]["summary"]["established_patch_total"] += 1
        mutated["cross_planet_generalization_matrix_hash"] = self.mod.object_hash(dict(mutated), "cross_planet_generalization_matrix_hash")
        with self.assertRaises(ValueError):
            self.mod.serialize_planet_generalization_matrix(mutated)

    def test_06_forged_verified_wrapper_rejected(self):
        forged = copy.deepcopy(dict(self.matrix))
        forged["authority"] = "PRODUCTION_AUTHORITATIVE"
        forged["cross_planet_generalization_matrix_hash"] = self.mod.object_hash(forged, "cross_planet_generalization_matrix_hash")
        wrapper = self.mod._VerifiedGeneralizationMatrix(forged, self.inputs)
        with self.assertRaises(ValueError):
            self.mod.serialize_planet_generalization_matrix(wrapper)

    def test_07_forged_verified_inputs_reverified_from_raw(self):
        fake_catalog = copy.deepcopy(self.inputs.catalog)
        fake_catalog["entries"][0]["genome"]["seed_count"] = 999999
        forged = self.mod._VerifiedMatrixInputs(
            contract=self.inputs.contract,
            snapshot=self.inputs.snapshot,
            catalog=fake_catalog,
            contract_e32=self.inputs.contract_e32,
            contract_e33=self.inputs.contract_e33,
            contract_e34=self.inputs.contract_e34,
            decomposition=self.inputs.decomposition,
            program_e34=self.inputs.program_e34,
            raw=self.inputs.raw,
        )
        rebuilt = self.mod.build_planet_generalization_matrix(forged)
        self.assertEqual(
            rebuilt["cross_planet_generalization_matrix_hash"],
            self.matrix["cross_planet_generalization_matrix_hash"],
        )

    def test_08_accepted_input_raw_drift_rejected(self):
        for name in ("e3_1_snapshot", "catalog", "e3_3_decomposition", "e3_4_program"):
            with self.subTest(input=name):
                raw = dict(self.inputs.raw)
                value = json.loads(raw[name].decode("utf-8"))
                value["__e38_drift__"] = True
                raw[name] = self.mod.canonical_bytes(value) + b"\n"
                with self.assertRaises(ValueError):
                    self.mod._verified_inputs_from_raw(raw)

    def test_09_contract_drift_rejected(self):
        raw = dict(self.inputs.raw)
        contract = json.loads(raw["contract"].decode("utf-8"))
        contract["predeclared_families"][0]["numerator"] = 999999
        raw["contract"] = self.mod.canonical_bytes(contract) + b"\n"
        with self.assertRaises(ValueError):
            self.mod._verified_inputs_from_raw(raw)

    def test_10_predeclaration_cannot_be_tuned_after_reveal(self):
        raw = dict(self.inputs.raw)
        contract = json.loads(raw["contract"].decode("utf-8"))
        contract["predeclared_families"] = [f for f in contract["predeclared_families"] if f["family"] != "dry"]
        raw["contract"] = self.mod.canonical_bytes(contract) + b"\n"
        with self.assertRaises(ValueError):
            self.mod._verified_inputs_from_raw(raw)


if __name__ == "__main__":
    unittest.main()

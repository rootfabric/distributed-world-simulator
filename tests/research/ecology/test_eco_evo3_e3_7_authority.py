from __future__ import annotations

import copy
import importlib.util
import inspect
import json
import pathlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
IMPL = ROOT / "scripts/research/ecology/planet_ecology_program_compiler_v1.py"


def load_impl():
    spec = importlib.util.spec_from_file_location("e37_impl_authority", IMPL)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class TestE37AuthorityBoundary(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = load_impl()
        cls.inputs = cls.mod.load_verified_inputs()
        cls.program = cls.mod.build_planet_ecology_program(cls.inputs)

    def assert_raw_drift_rejected(self, name: str):
        raw = dict(self.inputs.raw)
        value = json.loads(raw[name].decode("utf-8"))
        value["__e37_drift__"] = True
        raw[name] = self.mod.canonical_bytes(value) + b"\n"
        with self.assertRaises(ValueError):
            self.mod._verified_inputs_from_raw(raw)

    def _plain_program_variants(self):
        exact = self.mod.serialize_planet_ecology_program(self.program)
        plain = json.loads(exact.decode("utf-8"))
        forged = copy.deepcopy(plain)
        forged["authority"] = "PRODUCTION_AUTHORITATIVE"
        forged["planet_ecology_program_hash"] = self.mod.object_hash(forged, "planet_ecology_program_hash")
        mutated = copy.deepcopy(plain)
        mutated["projection"]["active_basis_count"] += 1
        mutated["planet_ecology_program_hash"] = self.mod.object_hash(mutated, "planet_ecology_program_hash")
        return plain, forged, mutated

    def test_15_plain_dict_cannot_build(self):
        with self.assertRaises(ValueError):
            self.mod.build_planet_ecology_program(dict(self.inputs.values))

    def test_16_plain_reconstructed_json_cannot_serialize(self):
        plain = self._plain_program_variants()[0]
        with self.assertRaises(ValueError):
            self.mod.serialize_planet_ecology_program(plain)

    def test_16a_generic_exact_final_byte_helper_absent(self):
        self.assertFalse(hasattr(self.mod, "serialized_bytes"))

    def test_16b_all_public_program_finalization_surfaces_reject_plain_and_forged_dicts(self):
        surfaces = sorted(
            name
            for name, value in vars(self.mod).items()
            if inspect.isfunction(value)
            and value.__module__ == self.mod.__name__
            and not name.startswith("_")
            and any(token in name.lower() for token in ("serial", "final", "write"))
        )
        self.assertEqual(surfaces, ["serialize_planet_ecology_program", "write_planet_ecology_program"])
        for variant in self._plain_program_variants():
            with self.subTest(surface="serialize_planet_ecology_program", authority=variant.get("authority")):
                with self.assertRaises(ValueError):
                    self.mod.serialize_planet_ecology_program(variant)
            with tempfile.TemporaryDirectory() as td:
                output = pathlib.Path(td) / "unauthorized.json"
                with self.subTest(surface="write_planet_ecology_program", authority=variant.get("authority")):
                    with self.assertRaises(ValueError):
                        self.mod.write_planet_ecology_program(variant, output)
                    self.assertFalse(output.exists())

    def test_17_mutated_verified_program_rejected(self):
        mutated = self.mod._VerifiedPlanetEcologyProgram(dict(self.program), self.inputs)
        mutated["projection"]["active_basis_count"] += 1
        mutated["planet_ecology_program_hash"] = self.mod.object_hash(dict(mutated), "planet_ecology_program_hash")
        with self.assertRaises(ValueError):
            self.mod.serialize_planet_ecology_program(mutated)

    def test_18_forged_verified_wrapper_rejected(self):
        forged = copy.deepcopy(dict(self.program))
        forged["authority"] = "PRODUCTION_AUTHORITATIVE"
        forged["planet_ecology_program_hash"] = self.mod.object_hash(forged, "planet_ecology_program_hash")
        wrapper = self.mod._VerifiedPlanetEcologyProgram(forged, self.inputs)
        with self.assertRaises(ValueError):
            self.mod.serialize_planet_ecology_program(wrapper)

    def test_19_forged_verified_inputs_reverified_from_raw(self):
        fake_values = copy.deepcopy(self.inputs.values)
        fake_values["catalog"]["canonical_species_declared"] = True
        forged = self.mod._VerifiedInputs(contract=self.inputs.contract, binding=self.inputs.binding, values=fake_values, raw=self.inputs.raw)
        rebuilt = self.mod.build_planet_ecology_program(forged)
        self.assertTrue(all(x["canonical_species_declared"] is False for x in rebuilt["species_manifest"]))

    def test_20_contract_raw_drift_rejected(self):
        self.assert_raw_drift_rejected("contract")

    def test_21_binding_raw_drift_rejected(self):
        self.assert_raw_drift_rejected("binding")

    def test_22_e31_raw_drift_rejected(self):
        self.assert_raw_drift_rejected("e3_1")

    def test_23_e32_raw_drift_rejected(self):
        self.assert_raw_drift_rejected("e3_2")

    def test_24_e33_raw_drift_rejected(self):
        self.assert_raw_drift_rejected("e3_3")

    def test_25_e34_raw_drift_rejected(self):
        self.assert_raw_drift_rejected("e3_4")

    def test_26_catalog_raw_drift_rejected(self):
        self.assert_raw_drift_rejected("catalog")

    def test_27_e35_raw_drift_rejected(self):
        self.assert_raw_drift_rejected("e3_5")

    def test_28_e36_raw_drift_rejected(self):
        self.assert_raw_drift_rejected("e3_6")


if __name__ == "__main__":
    unittest.main()

from __future__ import annotations

import copy
import importlib.util
import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
IMPL = ROOT / "scripts/research/ecology/planetary_ecology_final_compiler_v1.py"
CONTRACT = ROOT / "config/ecology/eco-evo3-e3-final-unseen-world-challenge-contract.v1.json"
ACCEPTED_MODULE_DIGESTS = 6


def load_module(path: pathlib.Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class AuthorityE3Final(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = load_module(IMPL, "e3final_authority_impl")
        cls.inputs = cls.mod.load_verified_inputs(CONTRACT)
        cls.program = cls.mod.build_unseen_world_program(cls.inputs)

    def test_plain_dict_rejected_by_serializer(self):
        with self.assertRaises(Exception):
            self.mod.serialize_planetary_ecology_final_program(dict(self.program))

    def test_tampered_combination_rejected_by_integrity(self):
        forged = self.mod._VerifiedUnseenWorldProgram(copy.deepcopy(dict(self.program)), self.inputs)
        forged["combinations"][0]["observed_outcome_class"] = "COLONIZED_ALL_SPECIES"
        with self.assertRaises(Exception):
            self.mod.validate_output_integrity(forged)

    def test_tampered_raw_input_rejected_at_load(self):
        raw = dict(self.inputs.raw)
        target = "config/ecology/accepted_inputs/e3_final/evo2_persisted_species_catalog.e3_final_mono_r1.v1.json"
        catalog = json.loads(raw[target].decode("utf-8"))
        catalog["entries"][0]["genome"]["seed_count"] = 999999
        raw[target] = json.dumps(catalog, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
        with self.assertRaises(Exception):
            self.mod.load_verified_inputs(CONTRACT, raw_override=raw)

    def test_no_alternate_serializer_helper_and_exact_surfaces(self):
        import inspect
        surfaces = sorted(
            name for name, value in vars(self.mod).items()
            if inspect.isfunction(value) and value.__module__ == self.mod.__name__
            and not name.startswith("_")
            and any(token in name.lower() for token in ("serial", "write", "final"))
        )
        self.assertEqual(surfaces, ["serialize_planetary_ecology_final_program", "write_planetary_ecology_final_program"])
        self.assertFalse(hasattr(self.mod, "serialized_bytes"))

    def test_accepted_modules_unmodified_in_git(self):
        import subprocess
        files = sorted(self.program["provenance"]["reused_modules"])
        out = subprocess.run(
            ["git", "status", "--porcelain", "--"] + [f"scripts/research/ecology/{f}" for f in files],
            cwd=ROOT, capture_output=True, text=True,
        ).stdout.strip()
        self.assertEqual(out, "", "accepted compiler modules must remain unmodified")

    def test_forbidden_promotions_all_false(self):
        promotions = self.program["provenance"]["forbidden_promotions"]
        self.assertTrue(promotions)
        self.assertTrue(all(v is False for v in promotions.values()))
        self.mod._reject_true_authority(dict(self.program), "AUTHORITY_TEST")
        self.assertFalse(self.program["production_binding_authorized"])

    def test_sealed_plaintext_absent_from_repo(self):
        commitments = self.inputs.commitments["commitments"]
        self.assertEqual(len(commitments), 12)
        for key, digest in commitments.items():
            self.assertIsInstance(digest, str)
            self.assertRegex(digest, r"^[0-9a-f]{64}$", key)
            self.assertNotIn("expected_outcome_class", str(digest))
        self.assertFalse((ROOT / "e3-final-sealed").exists(), "sealed plaintext must live outside the repository")


if __name__ == "__main__":
    unittest.main()

from __future__ import annotations

import hashlib
import importlib.util
import json
import pathlib
import subprocess
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
AGENT_PATH = ROOT / "scripts/research/ecology/evo4_t1_herbivore_agent_v1.py"
MANIFEST_PATH = ROOT / "validation/ecology/evo4_b6_region_manifest.v1.json"
RESULT_PATH = ROOT / "validation/ecology/evo4_t1_agent_pressure.v1.json"


def load_module(name: str, path: pathlib.Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


agent_mod = load_module("evo4_t1_herbivore_agent_v1", AGENT_PATH)
MANIFEST = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
ATTRS = agent_mod.derive_species_attributes(MANIFEST)


class Evo4T1HerbivoreAgentTests(unittest.TestCase):
    def test_01_species_attributes_deterministic_and_bounded(self):
        again = agent_mod.derive_species_attributes(json.loads(MANIFEST_PATH.read_text(encoding="utf-8")))
        self.assertEqual(ATTRS, again)
        instance_species = sorted({str(i["genome_id"]) for i in MANIFEST["instances"]})
        self.assertEqual(len(instance_species), 9)
        for gid in instance_species:
            for key, lo, hi in (
                ("defense", 0.05, 0.95),
                ("vigor", 0.3, 1.0),
                ("nutrient_value", 0.05, 0.98),
                ("toxicity", 0.02, 0.60),
            ):
                self.assertGreaterEqual(ATTRS[gid][key], lo, f"{gid}.{key}")
                self.assertLessEqual(ATTRS[gid][key], hi, f"{gid}.{key}")

    def test_02_t0_defense_formula_reproduced_on_shared_genomes(self):
        # The sealed T0 probe reported defense=0.5641 (e22-alpha-late) and
        # 0.3755 (e22-beta); the T1 derivation must match bit-for-bit.
        self.assertAlmostEqual(ATTRS["genome/e22-alpha-late"]["defense"], 0.5641, places=4)
        self.assertAlmostEqual(ATTRS["genome/e22-beta"]["defense"], 0.3755, places=4)

    def test_03_pressure_monotone_in_appetite(self):
        base_rows = agent_mod.aggregate_patch_pressure(MANIFEST, agent_mod.make_agent(), ATTRS)
        self.assertEqual(len(base_rows), 11)

        def cell_pressures(appetite: float) -> dict:
            rows = agent_mod.aggregate_patch_pressure(
                MANIFEST, agent_mod.make_agent(appetite=appetite), ATTRS)
            cells = {}
            for row in rows:
                for gid, share in row["species_pressure_share"].items():
                    cells[(row["patch_key"], gid)] = row["pressure_by_appetite"]["%.2f" % appetite] * share
            return cells

        previous_total = None
        for appetite in (0.25, 0.50, 1.00, 1.50, 2.00):
            cells = cell_pressures(appetite)
            total = sum(cells.values())
            if previous_total is not None:
                self.assertGreater(total, previous_total + 1e-9, f"appetite={appetite}")
            previous_total = total

        low_cells = cell_pressures(0.25)
        high_cells = cell_pressures(2.00)
        for key in low_cells:
            self.assertGreaterEqual(high_cells[key], low_cells[key] - 1e-12, str(key))

    def test_04_preference_alignment_and_mobility_effect(self):
        default_rows = agent_mod.aggregate_patch_pressure(MANIFEST, agent_mod.make_agent(), ATTRS)
        gates = agent_mod.evaluate_gates(default_rows, agent_mod.make_agent(), ATTRS)
        self.assertTrue(gates["g3_preference_alignment"])
        pressured, unweighted = gates["pressured_palatability_vs_uniform_mean"]
        self.assertGreater(pressured, unweighted)

        concentrated = agent_mod.aggregate_patch_pressure(
            MANIFEST, agent_mod.make_agent(mobility=0.0), ATTRS)
        roaming = agent_mod.aggregate_patch_pressure(
            MANIFEST, agent_mod.make_agent(mobility=1.0), ATTRS)
        weight_c = {r["patch_key"]: r["visitation_weight"] for r in concentrated}
        weight_r = {r["patch_key"]: r["visitation_weight"] for r in roaming}
        divergence = sum(abs(weight_c[k] - weight_r[k]) for k in weight_c)
        self.assertGreater(divergence, 0.5, "mobility must reshape patch visitation")
        for rows in (concentrated, roaming):
            total = sum(r["pressure_by_appetite"]["1.00"] for r in rows)
            self.assertAlmostEqual(total, 1.0, places=6, msg="pressure stock conserved")
            share_sum = sum(sum(r["species_pressure_share"].values()) for r in rows)
            self.assertAlmostEqual(share_sum, len(rows), places=6,
                                   msg="intra-patch species shares must each sum to 1")

    def test_05_artifact_byte_identical_across_fresh_processes(self):
        first = subprocess.run([sys.executable, str(AGENT_PATH)], capture_output=True, text=True)
        digest_a = hashlib.sha256(RESULT_PATH.read_bytes()).hexdigest()
        second = subprocess.run([sys.executable, str(AGENT_PATH)], capture_output=True, text=True)
        digest_b = hashlib.sha256(RESULT_PATH.read_bytes()).hexdigest()
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertIn("verdict=PASS", first.stdout)
        self.assertEqual(digest_a, digest_b)

    def test_06_artifact_matches_in_memory_computation(self):
        document = json.loads(RESULT_PATH.read_text(encoding="utf-8"))
        self.assertEqual(document["schema"], "distributed_world_simulator.ecology.evo4_t1_agent_pressure.v1")
        self.assertEqual(document["verdict"], "PASS")
        self.assertTrue(all(
            value for key, value in document["gates"].items() if isinstance(value, bool)))
        recomputed = agent_mod.aggregate_patch_pressure(
            MANIFEST, document["agent_contract"], ATTRS)
        by_key = {row["patch_key"]: row for row in recomputed}
        for artifact_row in document["patches"]:
            live = by_key[artifact_row["patch_key"]]
            self.assertEqual(live["visitation_weight"], artifact_row["visitation_weight"])
            self.assertEqual(
                live["pressure_by_appetite"]["1.00"], artifact_row["pressure_by_appetite"]["1.00"])
            self.assertEqual(live["species_pressure_share"], artifact_row["species_pressure_share"])


if __name__ == "__main__":
    unittest.main()

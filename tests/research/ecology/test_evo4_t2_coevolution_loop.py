from __future__ import annotations

import hashlib
import importlib.util
import json
import pathlib
import subprocess
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
LOOP_PATH = ROOT / "scripts/research/ecology/evo4_t2_coevolution_loop_v1.py"
TRAJECTORY_PATH = ROOT / "validation/ecology/evo4_t2_coevolution_trajectory.v1.json"
RESULT_PATH = ROOT / "validation/ecology/evo4_t2_coevolution_result.v1.json"


def load_module(name: str, path: pathlib.Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


loop = load_module("evo4_t2_coevolution_loop_v1", LOOP_PATH)
TRAJECTORY = json.loads(TRAJECTORY_PATH.read_text(encoding="utf-8"))
RESULT = json.loads(RESULT_PATH.read_text(encoding="utf-8"))


class Evo4T2CoevolutionLoopTests(unittest.TestCase):
    def _species_and_attrs(self):
        from evo4_t1_herbivore_agent_v1 import MANIFEST_PATH, derive_species_attributes  # noqa: PLC0415
        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        attrs_all = derive_species_attributes(manifest)
        species = sorted({str(i["genome_id"]) for i in manifest["instances"]})
        return species, {gid: attrs_all[gid] for gid in species}

    def test_01_trajectory_shape_and_coevolution_motion(self):
        self.assertEqual(TRAJECTORY["schema"], "distributed_world_simulator.ecology.evo4_t2_coevolution.v1.trajectory")
        self.assertEqual(len(TRAJECTORY["trajectory"]), 40)
        first, last = TRAJECTORY["trajectory"][0], TRAJECTORY["trajectory"][-1]
        self.assertGreater(last["mean_defense"], first["mean_defense"],
                           "defense distribution must shift under herbivory")
        self.assertLess(last["total_agent_intake"], first["total_agent_intake"],
                        "agent intake must drop as defense spreads")
        self.assertEqual(sum(last["defense_histogram"].values()), 9)
        self.assertGreater(last["mean_defense"], 0.05)
        self.assertLess(last["mean_defense"], 0.95)

    def test_02_result_verdict_and_gates(self):
        self.assertEqual(RESULT["verdict"], "PASS")
        self.assertTrue(RESULT["gates"]["g2_restart_determinism_byte_equal"])
        self.assertTrue(RESULT["gates"]["g3_robustness_three_seeds"])
        self.assertEqual(RESULT["trajectory_sha256"], RESULT["replay_sha256"])
        self.assertEqual(TRAJECTORY["trajectory_sha256"], RESULT["trajectory_sha256"])

    def test_03_no_pure_strategy_dominance_both_directions(self):
        species, attrs = self._species_and_attrs()
        checks = loop.invasion_checks(loop.MAIN_SEED, species, attrs)
        self.assertTrue(checks["no_defense_invadable"]["invadable"],
                        "all-undefended community must be invadable by defended mutants")
        self.assertTrue(checks["full_defense_invadable"]["invadable"],
                        "all-defended community must be invadable by cheaper mutants")
        for label in ("no_defense_invadable", "full_defense_invadable"):
            best = max(
                checks[label]["species"].items(),
                key=lambda kv: kv[1]["mutant_payoff"] - kv[1]["resident_payoff"])
            self.assertGreater(best[1]["mutant_payoff"] - best[1]["resident_payoff"], 1e-6, label)

    def test_04_t0_endpoint_payoff_identity_and_best_response_monotone(self):
        vigor, pressure = 0.5, 0.3
        self.assertAlmostEqual(loop.payoff(vigor, 0.0, pressure), vigor - 0.85 * pressure, places=12)
        self.assertAlmostEqual(loop.payoff(vigor, 1.0, pressure), vigor - 0.35, places=12)
        previous = None
        for pressure in (0.05, 0.2, 0.4, 0.6, 0.9):
            level = loop.best_response(vigor, pressure)
            if previous is not None:
                self.assertGreaterEqual(level, previous - 1e-12)
            previous = level
        self.assertGreater(loop.best_response(0.5, 0.9), loop.best_response(0.5, 0.05))

    def test_05_robustness_three_seeds_all_pass_invasion(self):
        species, attrs = self._species_and_attrs()
        for seed in loop.ROBUSTNESS_SEEDS:
            checks = loop.invasion_checks(seed, species, attrs)
            self.assertTrue(checks["no_defense_invadable"]["invadable"], f"seed={seed}")
            self.assertTrue(checks["full_defense_invadable"]["invadable"], f"seed={seed}")

    def test_06_restart_determinism_in_process_and_fresh_process(self):
        species, attrs = self._species_and_attrs()
        run_a = loop.simulate(loop.MAIN_SEED, species, attrs)
        run_b = loop.simulate(loop.MAIN_SEED, species, attrs)
        canonical_a = json.dumps(run_a, sort_keys=True, separators=(",", ":"))
        canonical_b = json.dumps(run_b, sort_keys=True, separators=(",", ":"))
        self.assertEqual(hashlib.sha256(canonical_a.encode()).hexdigest(),
                         hashlib.sha256(canonical_b.encode()).hexdigest())

        first = subprocess.run([sys.executable, str(LOOP_PATH)], capture_output=True, text=True)
        digests_a = [hashlib.sha256(TRAJECTORY_PATH.read_bytes()).hexdigest(),
                     hashlib.sha256(RESULT_PATH.read_bytes()).hexdigest()]
        second = subprocess.run([sys.executable, str(LOOP_PATH)], capture_output=True, text=True)
        digests_b = [hashlib.sha256(TRAJECTORY_PATH.read_bytes()).hexdigest(),
                     hashlib.sha256(RESULT_PATH.read_bytes()).hexdigest()]
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertIn("verdict=PASS", first.stdout)
        self.assertEqual(digests_a, digests_b)


if __name__ == "__main__":
    unittest.main()

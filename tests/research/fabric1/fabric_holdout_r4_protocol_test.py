"""Self-authored protocol calibration, explicitly NOT the independent holdout."""
import copy
import math
import subprocess
import tempfile
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts/research/fabric_holdout_r4"))
import holdout as h


def calibration():
    return {"id": "calibration", "family": "CALIBRATION_NOT_HOLDOUT", "expectation": "PHYSICS",
            "mechanical_nodes": [["anchor", 0.0, 1.0, True], ["slider", 2.0, 1.5, False]],
            "springs": [["support", "anchor", "slider", 12.0, 0.7, 100.0]],
            "electrical_nodes": [["p", 0.0], ["mid", 1.0], ["g", 3.0]],
            "resistors": [["source", "p", "mid", 2.0, "SOURCE_RESISTANCE"], ["load", "mid", "g", 3.0, "LOAD_RESISTANCE"]],
            "ports": {"p": 7.0, "g": 0.0}, "coupler_node": "slider", "coupling": 1.3,
            "external_force_n": 0.2, "length_unit": "m", "material_mechanical": "material/rubber",
            "material_electrical": "material/copper", "guard_fraction": 0.8, "dt_s": 0.002, "steps": 50}


class ProtocolTest(unittest.TestCase):
    def test_valid_and_strict_shapes(self):
        h.validate_case(calibration())
        for key, value in (("dt_s", float("nan")), ("steps", 0), ("steps", True), ("coupling", -1), ("length_unit", "parsec")):
            case = calibration(); case[key] = value
            with self.assertRaises(ValueError): h.validate_case(case)
        case = calibration(); case["hidden_solver"] = "no"
        with self.assertRaises(ValueError): h.validate_case(case)

    def test_duplicate_ids_rejected(self):
        case = calibration(); case["mechanical_nodes"][1][0] = "anchor"
        with self.assertRaises(ValueError): h.validate_case(case)

    def test_exact_kirchhoff_series(self):
        result = h.network(calibration())
        self.assertEqual(result["potentials_v"]["mid"], 4.2)
        self.assertEqual(result["port_currents_a"], {"p": 1.4, "g": -1.4})
        self.assertEqual(result["power_w"], 9.8)

    def test_exact_multiport(self):
        case = calibration(); case["ports"]["mid"] = 1.0
        result = h.network(case)
        self.assertEqual(result["port_currents_a"]["p"], 3)
        self.assertAlmostEqual(result["port_currents_a"]["mid"], -8/3)
        self.assertTrue(result["kcl_exact"] and result["power_exact"])

    def test_floating_component_is_invalid(self):
        case = calibration()
        case["electrical_nodes"] += [["f1", 4], ["f2", 5]]
        case["resistors"].append(["floating", "f1", "f2", 1, "WIRE"])
        with self.assertRaisesRegex(ValueError, "SINGULAR_PHYSICS"): h.network(case)

    def test_unanchored_mechanics_is_invalid(self):
        case = calibration(); case["mechanical_nodes"][0][3] = False
        with self.assertRaisesRegex(ValueError, "SINGULAR_PHYSICS"): h.mechanics(case)

    def test_stiffness_inverse(self):
        self.assertAlmostEqual(h.mechanics(calibration())["static_displacement_per_newton"]["slider"], 1/12)

    def test_undamped_reference(self):
        p = {"m": 1, "k": 4, "c": 0, "drive": 1, "g": 0, "r": 5, "u": 7}
        x, v, i = h.state(p, .5)
        self.assertAlmostEqual(x, (1-math.cos(1))/4)
        self.assertAlmostEqual(v, math.sin(1)/2)
        self.assertEqual(i, 1.4)

    def test_critical_reference(self):
        p = {"m": 1, "k": 4, "c": 4, "drive": 1, "g": 0, "r": 5, "u": 7}
        x, v, _ = h.state(p, .5)
        self.assertAlmostEqual(x, (1-2/math.e)/4)
        self.assertAlmostEqual(v, .5/math.e)

    def test_overdamped_reference(self):
        p = {"m": 1, "k": 2, "c": 3, "drive": 1, "g": 0, "r": 1, "u": 0}
        x, v, _ = h.state(p, .5)
        self.assertAlmostEqual(x, .5*(1-2*math.exp(-.5)+math.exp(-1)))
        self.assertAlmostEqual(v, math.exp(-.5)-math.exp(-1))

    def test_analytic_event_before_peak(self):
        case = calibration(); case["springs"][0][3:] = [4, 0, .1]
        p = {"m": 1, "k": 4, "c": 0, "drive": 1, "g": 0, "r": 1, "u": 0}
        event = h.first_failure(case, p, 2)
        self.assertAlmostEqual(event["time_s"], math.acos(.9)/2, places=12)
        self.assertEqual(event["bond_id"], "bond/support")

    def test_equivalence_operators(self):
        original = calibration()
        original["electrical_nodes"].append(["extra", 2])
        original["resistors"][1] = ["load", "mid", "extra", 1, "LOAD_RESISTANCE"]
        original["resistors"].append(["wire", "extra", "g", 2, "WIRE"])
        expected = h.oscillator(original)
        for name, case in h.variants(original):
            h.validate_case(case)
            normalized = h.normalize(case, name)
            self.assertEqual(len(normalized["electrical"]["edges"]), len(case["resistors"]))
            if name != "length_x2_fixed_area": self.assertEqual(h.oscillator(case), expected)
        scaled = dict(h.variants(original))["length_x2_fixed_area"]
        self.assertAlmostEqual(h.oscillator(scaled)["r"], expected["r"]*2)
        self.assertAlmostEqual(h.oscillator(scaled)["k"], expected["k"]/2)

    def test_no_vacuous_rejection_pass(self):
        case = calibration(); case["expectation"] = "REJECT_INVALID"
        result = h.evaluate(case, {"id": "x", "compile": {"success": False}, "source_unchanged": True}, "original")
        self.assertEqual(result["verdict"], "FAIL")

    def test_valid_unsupported_is_failure(self):
        result = h.evaluate(calibration(), {"id": "x", "compile": {"success": False, "error_code": "TEST_UNSUPPORTED"}, "r2_mechanical": {"success": True}, "r2_electrical": {"success": True}}, "original")
        self.assertEqual(result["verdict"], "FAIL")
        self.assertIn("VALID_PRIMITIVES_NOT_EXECUTABLE_IN_R3", result["issues"])

    def field_fixture(self):
        case = calibration()
        case["electrical_nodes"].append(["other", 2])
        case["resistors"] += [["branch_a", "p", "other", 4, "WIRE"],
                              ["branch_b", "other", "g", 1, "WIRE"],
                              ["cross", "mid", "other", 5, "WIRE"]]
        reference = h.network(case)
        sample = {"velocity_m_per_s": 0.0, "electrical_observables": {
            field: {prefix + key: value for key, value in reference[field].items()}
            for field, prefix in (("edge_currents_a", "bond/"), ("port_currents_a", "part/"), ("potentials_v", "part/"))}}
        return case, sample

    def test_complete_distributed_readback(self):
        case, sample = self.field_fixture()
        self.assertEqual(h.electrical_field_checks(case, sample), [])

    def test_missing_readback_cannot_pass_bridge_as_scalar(self):
        case, _ = self.field_fixture()
        self.assertIn("MISSING_DISTRIBUTED_ELECTRICAL_READBACK", h.electrical_field_checks(case, {"current_a": 1.4}))
        self.assertEqual(h.electrical_field_checks(calibration(), {"current_a": 1.4}), [])
        path = calibration(); path["ports"] = {"p": 7, "mid": 1}
        self.assertIn("MISSING_DISTRIBUTED_ELECTRICAL_READBACK", h.electrical_field_checks(path, {}))

    def test_each_distributed_field_is_checked(self):
        case, original = self.field_fixture()
        for field in ("edge_currents_a", "port_currents_a", "potentials_v"):
            with self.subTest(field=field):
                sample = copy.deepcopy(original)
                key = next(iter(sample["electrical_observables"][field]))
                sample["electrical_observables"][field][key] += 0.1
                self.assertIn("ELECTRICAL_FIELD_ORACLE_" + field, h.electrical_field_checks(case, sample))
                del sample["electrical_observables"][field][key]
                self.assertIn("ELECTRICAL_FIELD_COVERAGE_" + field, h.electrical_field_checks(case, sample))

    def test_same_total_current_wrong_bridge_flow_is_not_pass(self):
        case, sample = self.field_fixture()
        sample["electrical_observables"]["edge_currents_a"]["bond/cross"] += 0.1
        sample.update({"time_s": 0, "displacement_m": 0, "current_a": h.state(h.oscillator(case), 0)[2],
                       "pending_proposal": {}, "energy_residual_j": 0})
        run = {"samples": [sample], "final": sample, "rejection_atomic": True,
               "wrong_owner_rejected": True, "denied_rejected": True}
        observed = {"id": "calibration", "compile": {"success": True},
                    "r2_mechanical": {"success": True}, "r2_electrical": {"success": True},
                    "runs": {"FULL": run, "BAKE": copy.deepcopy(run)}}
        result = h.evaluate(case, observed, "original")
        self.assertEqual(result["verdict"], "FAIL")
        self.assertIn("FULL_ELECTRICAL_FIELD_ORACLE_edge_currents_a", result["issues"])
        self.assertIn("FULL_ELECTRICAL_KCL_RESIDUAL", result["issues"])

    def test_linked_worktree_exclude_path(self):
        # Reproduce the actual runner prefix in a linked worktree, without Godot.
        prefix = (ROOT / "RUN_FABRIC_HOLDOUT_R4_TESTS.sh").read_text().split('finish() {', 1)[0]
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory) / "repo"; work = Path(directory) / "work"
            repo.mkdir()
            def git(*args):
                subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True)
            git("init"); git("-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "--allow-empty", "-m", "test")
            git("worktree", "add", "--detach", str(work), "HEAD")
            self.assertTrue((work / ".git").is_file())
            launcher = work / "RUN_FABRIC_HOLDOUT_R4_TESTS.sh"
            launcher.write_text(prefix)
            subprocess.run(["bash", str(launcher)], cwd=work, check=True, capture_output=True)
            actual = subprocess.check_output(["git", "-C", str(work), "rev-parse", "--git-path", "info/exclude"], text=True).strip()
            target = Path(actual) if Path(actual).is_absolute() else work / actual
            self.assertIn("*.gd.uid", target.read_text())

    def test_schema_nan_cannot_serialize(self):
        with self.assertRaises(ValueError): h.dumps({"x": float("nan")})


if __name__ == "__main__":
    unittest.main(verbosity=2)

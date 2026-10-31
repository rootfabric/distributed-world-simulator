"""R3C21 diagnostics negative cases: invalid/incomplete traces never PASS."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
MODULE=ROOT/"tools/net_smooth1/analyze_r3c21_visual_frames.py"
spec=importlib.util.spec_from_file_location("r3c21_analyzer", MODULE)
an=importlib.util.module_from_spec(spec)
spec.loader.exec_module(an)


def trace(path: Path, role: str, run: str, *, with_end=True, error=False):
    rows=[
        {"n":1,"t_us":1000,"kind":"header","data":{"role":role,"run_id":run}},
        {"n":2,"t_us":2000,"kind":"r3c3r2_visual_commit","data":{"token":3,"commit_ms":.13}},
        {"n":3,"t_us":2600,"kind":"r3c21_first_visible_frame",
         "data":{"token":3,"frame_gap_ms":77}},
        {"n":4,"t_us":2900,"kind":"r3c21_preattach_slice",
         "data":{"elapsed_us":1400}},
        {"n":5,"t_us":3000,"kind":"frame","data":{"interval_ms":20}},
    ]
    if with_end:
        rows.append({"kind":"end","t_us":4000,"data":{"produced":5,"written":5,
                                                  "dropped":1 if error else 0,"io_errors":0}})
    path.write_text("\n".join(json.dumps(x) for x in rows)+"\n",encoding="utf-8")


class R3C21Analyzer(unittest.TestCase):
    def test_per_role_preattach_and_first_visible_budgets(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); run="exact-r3c21"
            for role in ("a", "b"):
                (root/role).mkdir()
                trace(root/role/"trace.jsonl",role,run)
            (root/"manifest.json").write_text(json.dumps(
                {"run_id":run,"completed":True,"r3c21_frame_paced_presentation":True}))
            result=an.analyze(root)
            self.assertEqual(result["evidence_class"],"DIAGNOSTIC_ONLY_NOT_ACCEPTANCE")
            self.assertFalse(result["acceptance_bypass"])
            self.assertEqual(result["clients"]["a"]["postcommit_frame_gap_ms"]["max"],77)
            self.assertEqual(result["clients"]["b"]["stages_ms"]["r3c21_preattach_slice"]["elapsed_us"]["max"],1.4)

    def test_missing_end_is_inconclusive(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/"trace.jsonl"
            trace(path,"b","run",with_end=False)
            with self.assertRaisesRegex(ValueError,"missing END"):
                an.inspect(path,"b","run")

    def test_dropped_trace_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/"trace.jsonl"
            trace(path,"a","run",error=True)
            with self.assertRaisesRegex(ValueError,"trace dropped/error"):
                an.inspect(path,"a","run")

    def test_ghost_visual_token_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/"trace.jsonl"
            trace(path,"a","run")
            text=path.read_text().replace('"token": 3, "frame_gap_ms"', '"token": 22, "frame_gap_ms"')
            path.write_text(text)
            with self.assertRaisesRegex(ValueError,"unbound first-visible token"):
                an.inspect(path,"a","run")

    def test_normal_acceptance_cannot_be_overridden(self):
        source=MODULE.read_text(encoding="utf-8")
        self.assertIn("DIAGNOSTIC_ONLY_NOT_ACCEPTANCE",source)
        self.assertIn('"acceptance_bypass": False',source)
        self.assertIn("tools/net_smooth1/analyze_net_smooth1.py",source)
        self.assertNotIn('"verdict": "PASS"',source)


if __name__=="__main__":
    unittest.main()

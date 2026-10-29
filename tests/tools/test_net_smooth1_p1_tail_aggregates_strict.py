"""Fail-closed raw measured trace -> true full-tail counts; no baked AGG."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/"tools/net_smooth1"))
sys.path.insert(0,str(ROOT/"tests/tools"))
from test_net_smooth1_r31p22_loop_stages import fixture, RUN_ID
from p1_tail_aggregates import summarize_run


def example(root:Path) -> Path:
    (root/"server").mkdir(parents=True)
    records=fixture()
    (root/"server"/"trace.jsonl").write_text(
        "".join(json.dumps(x)+"\n" for x in records), encoding="utf-8")
    (root/"manifest.json").write_text(json.dumps({
        "run_id":RUN_ID,
        "identity":{"head":"a"*40,"tree":"b"*40,"godot_sha256":"c"*64},
    }),encoding="utf-8")
    (root/"report.json").write_text('{"verdict":"FAIL"}',encoding="utf-8")
    return root


class StrictMeasuredTail(unittest.TestCase):
    def test_recomputed_not_copied(self):
        with tempfile.TemporaryDirectory() as d:
            root=example(Path(d))
            original=(root/"server"/"trace.jsonl").read_bytes()
            got=summarize_run(root)
            self.assertEqual(original,(root/"server"/"trace.jsonl").read_bytes())
            self.assertEqual(got["original_normative_verdict"],"FAIL")
            self.assertEqual(got["source_run_id"],RUN_ID)
            self.assertGreaterEqual(got["count_frames"],100)
            self.assertLessEqual(got["count_over25_with_snapshot"],
                                 got["count_over25"])
            self.assertGreater(got["flush_stage_ms"]["n"],0)
            self.assertEqual(got["interpretation"],
                             "SNAPSHOT_COINCIDENCE_NOT_PROOF_OF_FLUSH_CAUSALITY")

    def test_bad_footer_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root=example(Path(d))
            trace=root/"server"/"trace.jsonl"
            rows=[json.loads(x) for x in trace.read_text(encoding="utf-8").splitlines()]
            rows[-1]["data"]["written"]=0
            trace.write_text("".join(json.dumps(x)+"\n" for x in rows),encoding="utf-8")
            with self.assertRaisesRegex(ValueError,"TRACE_LOSS_OR_IO_ERROR"):
                summarize_run(root)

    def test_invalid_product_identity_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root=example(Path(d))
            manifest=root/"manifest.json"
            data=json.loads(manifest.read_text())
            data["identity"].pop("tree")
            manifest.write_text(json.dumps(data))
            with self.assertRaisesRegex(ValueError,"SOURCE_IDENTITY_MISSING"):
                summarize_run(root)


if __name__=="__main__":
    unittest.main()

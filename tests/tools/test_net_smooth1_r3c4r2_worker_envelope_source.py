"""Fail-closed R3C.4 R2 source contracts; Windows Godot remains authoritative."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
def read(p):
    return (ROOT / p).read_text(encoding="utf-8")

SERVER = read("scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd")
ADAPTER = read("scripts/runtime/networked_gameplay/m6/m6_dedicated_gameplay_authority_adapter.gd")
HARNESS = read("tools/net_smooth1/run_net_smooth1.py")
ANALYZER = read("tools/net_smooth1/analyze_net_smooth1.py")
RUNTIME_TEST = read("tests/runtime/test_net_smooth1_r3c4r2_worker_envelope.gd")
WRITER = read("scripts/persistence/async_checkpoint_writer.gd")


def func(src, name):
    found = re.search(r"^(?:static )?func " + re.escape(name) + r"\(", src, re.M)
    if found is None:
        raise ValueError("function missing: " + name)
    next_func = re.search(r"^func ", src[found.end():], re.M)
    return src[found.start(): found.end()+next_func.start() if next_func else len(src)]


class R3C4R2SourceSafety(unittest.TestCase):
    def test_r2_is_opt_in_default_off(self):
        self.assertIn("_r3c4r2_worker_envelope_enabled := false", SERVER)
        self.assertIn("DWS_NET_R3C4R2_WORKER_ENVELOPE", SERVER)
        self.assertIn("r3c4r2_worker_envelope_canary", SERVER)
        self.assertIn("R3C4R2_INVALID_WORKER_ENVELOPE_MODE", SERVER)

    def test_r2_requires_r1_fail_closed(self):
        self.assertIn("R3C4R2_REQUIRES_PERIODIC_FRAME_PACING", SERVER)
        setup = func(SERVER, "setup")
        r1 = setup.index("_r3c4_periodic_frame_pacing_enabled = (")
        r2 = setup.index("_r3c4r2_worker_envelope_enabled = (")
        gate = setup.index("R3C4R2_REQUIRES_PERIODIC_FRAME_PACING")
        self.assertLess(r1, r2)
        self.assertLess(r2, gate)
        # The gate must compare against the already-resolved R1 flag.
        self.assertIn("not _r3c4_periodic_frame_pacing_enabled", setup)

    def test_capture_is_joint_on_one_authoritative_frame(self):
        submit = func(SERVER, "_submit_async_movement_checkpoint")
        self.assertIn("if _r3c4r2_worker_envelope_enabled:", submit)
        r2 = submit.index("if _r3c4r2_worker_envelope_enabled:")
        legacy = submit.index("authority = _recovery_authority.export_recovery_state()")
        # R2 branch: ONE service durable DTO export + ONE replay projection,
        # both detached on this frame; the expensive DTO export stays on main.
        self.assertIn("_service.export_durable_state()", submit)
        self.assertIn("_replay_outbox.to_dict()", submit)
        self.assertLess(submit.index("_service.export_durable_state()"), submit.index("_replay_outbox.to_dict()"))
        # Normalization is a pure function of the detached DTO + session id.
        self.assertIn("M6AuthorityAdapter.normalize_durable_state(", submit)
        self.assertIn("R3C4R2_ENVELOPE_NORMALIZATION_FAILED", submit)
        # No multi-frame claim: capture happens before the single submit.
        self.assertLess(r2, submit.index("_movement_checkpoint_writer.submit("))

    def test_worker_pipeline_unchanged(self):
        # Deep copy BEFORE wakeup stays in the existing worker entry point.
        self.assertIn("authority_state.duplicate(true)", WRITER)
        self.assertIn("_wake.post()", WRITER)
        self.assertIn("Checkpoint.create(", WRITER)
        self.assertIn("_repository.save_atomic(checkpoint)", WRITER)
        # The M6 envelope normalization is a pure static function of the DTO.
        normalize = func(ADAPTER, "normalize_durable_state")
        self.assertIn("static func normalize_durable_state", ADAPTER)
        self.assertIn("EntitySnapshot.normalize", normalize)
        export = func(ADAPTER, "export_recovery_state")
        self.assertIn("normalize_durable_state(durable_state, _logical_session_id)", export)

    def test_harness_flag_is_server_only_and_default_off(self):
        self.assertIn("'--r3c4r2-worker-envelope'", HARNESS)
        self.assertIn("env['DWS_NET_R3C4R2_WORKER_ENVELOPE']='1'", HARNESS)
        self.assertIn("if role == 'server' and args.r3c4r2_worker_envelope:", HARNESS)
        self.assertIn("r3c4r2_worker_envelope=args.r3c4r2_worker_envelope", HARNESS)
        self.assertNotIn("--r3c4r2-worker-envelope", read("scripts/app/earth_app.gd"))
        self.assertIn("tests/runtime/test_net_smooth1_r3c4r2_worker_envelope.gd", HARNESS)

    def test_runtime_falsifier_covers_contract(self):
        for token in ("default off without flag/env", "R2 without R1 is rejected",
                      "invalid R2 mode rejected", "wrapped envelope equals legacy adapter envelope",
                      "wrapped checkpoint SHA256 equals legacy SHA256",
                      "final disk checksums are equal",
                      "disk checksum unaffected by post-submit mutation",
                      "empty DTO rejects to empty envelope",
                      "disk untouched by rejected submits",
                      "heavy snapshot frame still defers (R1 pacing exact)",
                      "only completion advances generation under R2",
                      "restored R2 checkpoint validates with unchanged validator"):
            self.assertIn(token, RUNTIME_TEST)

    def test_analyzer_and_normative_checker_untouched(self):
        self.assertIn('frame p99 >25ms', ANALYZER)
        self.assertIn('simulation <59Hz', ANALYZER)
        self.assertNotIn("r3c4r2", ANALYZER)
        self.assertNotIn("r3c4r2", read("scripts/persistence/authoritative_checkpoint.gd"))
        self.assertNotIn("r3c4r2", read("scripts/persistence/authoritative_recovery_repository.gd"))


if __name__ == "__main__":
    unittest.main()

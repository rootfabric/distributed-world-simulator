"""Source-only R3C.4 R2 worker envelope and exact M6 fences."""
from pathlib import Path
import re
import unittest
ROOT = Path(__file__).resolve().parents[2]
def read(p): return (ROOT/p).read_text(encoding="utf-8")
SERVER=read("scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd")
ADAPTER=read("scripts/runtime/networked_gameplay/m6/m6_dedicated_gameplay_authority_adapter.gd")
WRITER=read("scripts/persistence/async_checkpoint_writer.gd")
HARNESS=read("tools/net_smooth1/run_net_smooth1.py")
NATIVE=read("tests/runtime/test_net_smooth1_r3c4_r2_worker_envelope.gd")

def method(s, name, static=False):
    m=re.search(r"^"+("static " if static else "")+"func "+re.escape(name)+r"\(",s,re.M)
    if not m: raise AssertionError("missing "+name)
    nxt=re.search(r"^(?:static )?func ",s[m.end():],re.M)
    return s[m.start():m.end()+nxt.start() if nxt else len(s)]

class R3C4R2(unittest.TestCase):
    def test_worker_owns_exact_pure_envelope(self):
        src=method(ADAPTER,"capture_frozen_gameplay_source_for_worker")
        self.assertIn("_service.export_durable_state()",src)
        self.assertNotIn("EntitySnapshot.normalize",src)
        wrap=method(ADAPTER,"wrap_frozen_gameplay_source",True)
        self.assertIn("EntitySnapshot.normalize(EntitySnapshot.create(",wrap)
        self.assertIn('"networked_gameplay_state": durable',wrap)
        self.assertNotIn("_service.",wrap)
    def test_deep_alias_not_shared_and_worker_rejects_invalid(self):
        submit=method(WRITER,"submit_frozen_gameplay_source")
        for s in ("frozen_gameplay.duplicate(true)","replay_state.duplicate(true)",
                  "if _busy or _stopping:","_wake.post()"): self.assertIn(s,submit)
        self.assertIn('R3C4_R2_PERIODIC_FROZEN_GAMEPLAY',method(WRITER,"_run"))
        self.assertIn('R3C4_R2_WORKER_ENVELOPE_INVALID',method(WRITER,"_run"))
        self.assertIn('_repository.save_atomic(checkpoint)',method(WRITER,"_run"))
    def test_default_m6_command_and_gate_unchanged(self):
        for name in ("_persist_checkpoint","_persist_command_result"):
            self.assertNotIn("_r3c4r2_",method(SERVER,name))
        cmd=method(SERVER,"_persist_command_result")
        self.assertIn("_durable_ack_gate.mark_submitted(",cmd)
        self.assertIn("_durable_ack_gate.complete(",cmd)
        periodic=method(SERVER,"_maybe_persist_movement_checkpoint")
        self.assertIn("_r3c4_periodic_capture_slot_available()",periodic)
        self.assertNotIn("_r3c4r2_",periodic)
        export=method(SERVER,"_submit_async_movement_checkpoint")
        for s in ("submit_frozen_gameplay_source(", "_replay_outbox.to_dict()",
                  "_recovery_authority.export_recovery_state()"):
            self.assertIn(s,export)
    def test_opt_in_server_only(self):
        self.assertIn("R3C4_R2_REQUIRES_PERIODIC_PERSISTENT_MODE",SERVER)
        self.assertIn("R3C4_R2_INVALID_MODE",SERVER)
        self.assertIn("if role == 'server' and args.r3c4r2_worker_envelope:",HARNESS)
        self.assertIn("--r3c4r2-worker-envelope",HARNESS)
        self.assertIn("and not args.r3c4_periodic_frame_pacing:",HARNESS)
    def test_real_native_parity_falsifiers(self):
        for token in ("wrapped == legacy","disk checkpoint AND SHA",
                      "caller-mutated-after-submit",
                      "R3C4_R2_WORKER_ENVELOPE_INVALID",
                      "_durable_ack_gate",
                      "load_committed()","quit(0 if failures.is_empty() else 1)"):
            self.assertIn(token,NATIVE)
if __name__=="__main__": unittest.main()

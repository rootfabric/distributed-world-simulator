"""R31P23 R2.0 source contracts, real segment opt-in, original M6 invariant."""
from pathlib import Path
import re
import unittest

ROOT=Path(__file__).resolve().parents[2]
BOUNDARY=ROOT/"scripts/network/transports/v2/network_transport_boundary_v2.gd"
SIM=ROOT/"scripts/network/conditions/network_condition_simulator_port.gd"
ENET=ROOT/"scripts/network/transports/v2/enet_multi_peer_transport_port.gd"
SERVER=ROOT/"scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd"
HARNESS=ROOT/"tools/net_smooth1/run_net_smooth1.py"
PROTOCOL=ROOT/"scripts/network/transports/v2/protocol_frame_v2.gd"
M6=ROOT/"scripts/persistence/async_checkpoint_writer.gd"
REDUCER=ROOT/"tools/net_smooth1/analyze_r31p23r2_flush_layers.py"


def method(src:str,name:str)->str:
    result=re.search(r"(?ms)^func "+re.escape(name)+r"\(.*?(?=^func |\Z)",src)
    if not result:
        raise AssertionError("missing "+name)
    return result.group()


class Source(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.code={p:p.read_text(encoding="utf-8") for p in
                  (BOUNDARY,SIM,ENET,SERVER,HARNESS,PROTOCOL,M6,REDUCER)}

    def test_flag_is_explicit_server_only_and_default_off(self):
        svr=self.code[SERVER]
        setup=method(svr,"setup")
        self.assertIn("var _r31p23r2_flush_attribution_enabled := false",svr)
        for item in ("DWS_NET_R31P23R2_FLUSH_ATTRIBUTION","R31P23R2_INVALID_MODE",
                     "R31P23R2_REQUIRES_R31P22_LOOP_ATTRIBUTION",
                     "r31p23r2_flush_attribution_canary",
                     "_boundary.configure_r31p23r2_flush_attribution(true)"):
            self.assertIn(item,setup)
        h=self.code[HARNESS]
        self.assertIn("r31p23r2_flush_attribution=args.r31p23r2_flush_attribution",h)
        self.assertIn("if role == 'server' and args.r31p23r2_flush_attribution:",h)
        self.assertIn("env['DWS_NET_R31P23R2_FLUSH_ATTRIBUTION']='1'",h)

    def test_full_three_layer_propagation(self):
        for p in (BOUNDARY,SIM,ENET):
            code=self.code[p]
            self.assertIn("var _r31p23r2_attribution_enabled := false",code)
            self.assertIn("func configure_r31p23r2_flush_attribution(enabled: bool)",code)
        self.assertIn("_port.configure_r31p23r2_flush_attribution(enabled)",
                      method(self.code[BOUNDARY],"configure_r31p23r2_flush_attribution"))
        self.assertIn("_delegate.configure_r31p23r2_flush_attribution(enabled)",
                      method(self.code[SIM],"configure_r31p23r2_flush_attribution"))

    def test_original_send_sequence_and_packet_checksum_unchanged(self):
        svr=method(self.code[SERVER],"_send_on_channel")
        for name in ("_boundary.create_frame_for_peer(",
                     "_boundary.send_to_peer(",
                     "_boundary.flush_outbound(32, peer_id)"):
            self.assertEqual(svr.count(name),1)
        stages=method(self.code[BOUNDARY],"flush_outbound")
        self.assertEqual(stages.count("_port.send_to_peer("),1)
        self.assertIn("item.get(\"frame\", {}).duplicate(true)",stages)
        self.assertIn("session.release_queue",stages)
        self.assertIn("session.commit_outgoing_sequence",self.code[BOUNDARY])
        enet=method(self.code[ENET],"send_to_peer")
        for tok in ("FrameScript.validate(frame)",
                    "FrameScript.encode(frame, MAX_PACKET_BYTES)",
                    "_peer.put_packet("):
            self.assertEqual(enet.count(tok),1)
        protocol=self.code[PROTOCOL]
        self.assertIn('"payload_checksum": UtilsScript.payload_hash(canonical_payload)',protocol)
        self.assertIn('func validate(value: Dictionary) -> Dictionary:',protocol)
        self.assertIn('PAYLOAD_CHECKSUM_MISMATCH',protocol)

    def test_boundary_trace_timing_only_no_wire_changes(self):
        boundary=method(self.code[BOUNDARY],"flush_outbound")
        self.assertIn('String(Dictionary(p23_frame.get("payload", {})).get("type", ""))',boundary)
        self.assertIn('== "COMPACT_GAMEPLAY_SNAPSHOT"',boundary)
        for k in ("queue_stage_ms","detached_frame_copy_ms","port_call_ms",
                  "engine_frame","frame_id","session_sequence","simulator"):
            self.assertIn('"'+k+'"',boundary)
        self.assertIn('R31SmoothTrace.emit("r31p23r2_flush_packet"',boundary)
        self.assertIn("result.get(\"details\", {})",boundary)
        self.assertNotIn("await ",boundary)
        self.assertNotIn("Thread.new()",boundary)

    def test_simulator_legacy_passthrough_packet_is_unchanged(self):
        s=method(self.code[SIM],"send_to_peer")
        self.assertIn("FrameScript.validate(frame)",s)
        self.assertIn("NetworkUtilsScript.canonical_json(frame)",s)
        self.assertEqual(s.count("_delegate.send_to_peer(peer_id, frame)"),1)
        self.assertIn("_with_simulator_details(direct, packet_bytes, false, false, _now_ms())",s)
        self.assertIn('"r31p23r2_simulator_stages"',s)
        self.assertIn('"r31p23r2_enet_stages"',s)
        self.assertIn("if p23_probe and bool(result.get(\"success\", false)):",s)

    def test_enet_validate_and_encode_accounted_separately(self):
        s=method(self.code[ENET],"send_to_peer")
        for k in ("validate_ms","frame_encode_ms","channel_setup_ms",
                  "put_packet_ms","peer_stats_ms","total_ms"):
            self.assertIn('"'+k+'"',s)
        self.assertIn("_r31p23r2_attribution_enabled",s)
        self.assertIn('"r31p23r2_enet_stages"',s)

    def test_m6_durable_writer_and_errors_unaltered(self):
        c=self.code[M6]
        for text in ("submit_frozen_gameplay_source(", "frozen_gameplay.duplicate(true)",
                     "replay_state.duplicate(true)", "poll_completed()",
                     "_completion = result"):
            self.assertIn(text,c)
        for p in (M6,PROTOCOL):
            self.assertNotIn("_r31p23r2",self.code[p])
        reducer=self.code[REDUCER]
        for text in ("P23R2_INCOMPLETE_COMPACT_COVERAGE",
                     "P23R2_ENET_COMPONENTS_NOT_ADDITIVE",
                     "P23R2_LAYER_STAGES_EXCEED_ORIGINAL_FLUSH",
                     "P23R2_FAILED_COMPACT_WIRE_SEND",
                     "R31P23R2_TRANSPORT_ATTRIBUTION_VALID_ONLY_NOT_PERF_PASS"):
            self.assertIn(text,reducer)


if __name__=="__main__":
    unittest.main()

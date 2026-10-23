"""P2.3 R2.1 exact canonical current-COMPACT fast-path source fences.

The only full validation skipped is ENet's *second* validation performed by
ProtocolFrameV2.encode(frame) after the ORIGINAL ENet.validate(frame) already
succeeded. No unchecked input can enter this path, no change to wire delivery,
M6 replay or session sequencing, and LOCAL simulator check is still required.
"""
from __future__ import annotations
import re
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[2]
SERVER=ROOT/"scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd"
BOUNDARY=ROOT/"scripts/network/transports/v2/network_transport_boundary_v2.gd"
SIMULATOR=ROOT/"scripts/network/conditions/network_condition_simulator_port.gd"
ENET=ROOT/"scripts/network/transports/v2/enet_multi_peer_transport_port.gd"
FRAME=ROOT/"scripts/network/transports/v2/protocol_frame_v2.gd"
M6=ROOT/"scripts/persistence/async_checkpoint_writer.gd"
RUNNER=ROOT/"tools/net_smooth1/run_net_smooth1.py"


def function(src,name):
    m=re.search(r"(?ms)^func "+re.escape(name)+r"\(.*?(?=^func |\Z)",src)
    if m is None:
        raise AssertionError("missing "+name)
    return m.group(0)


class R21Source(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data={p:p.read_text(encoding="utf-8") for p in
                  [SERVER,BOUNDARY,SIMULATOR,ENET,FRAME,M6,RUNNER]}

    def test_disabled_by_default_explicit_off_on_and_server_only(self):
        s=self.data[SERVER]
        self.assertIn("var _r31p23r21_single_pass_compact_enabled := false",s)
        setup=function(s,"setup")
        for token in (
            'DWS_NET_R31P23R21_SINGLE_PASS_COMPACT',
            'R31P23R21_INVALID_MODE',
            'R31P23R21_REQUIRES_R2P0_FLUSH_ATTRIBUTION',
            'r31p23r21_single_pass_compact_canary',
            '_boundary.configure_r31p23r21_single_pass_compact(true)',
        ):
            self.assertIn(token,setup)
        h=self.data[RUNNER]
        self.assertIn("r31p23r21_single_pass_compact=args.r31p23r21_single_pass_compact",h)
        self.assertIn("if role == 'server' and args.r31p23r21_single_pass_compact:",h)
        self.assertIn("env['DWS_NET_R31P23R21_SINGLE_PASS_COMPACT']='1'",h)
        self.assertIn("P2.3 R2.1 single-pass COMPACT requires --r31p23r2-flush-attribution",h)

    def test_full_boundary_simulator_enet_chain_explicit_enabled(self):
        for name in [BOUNDARY,SIMULATOR,ENET]:
            src=self.data[name]
            self.assertIn("var _r31p23r21_single_pass_compact_enabled := false",src)
            self.assertIn("func configure_r31p23r21_single_pass_compact(enabled: bool)",src)
        self.assertIn("_port.configure_r31p23r21_single_pass_compact(enabled)",
                      function(self.data[BOUNDARY],"configure_r31p23r21_single_pass_compact"))
        self.assertIn("_delegate.configure_r31p23r21_single_pass_compact(enabled)",
                      function(self.data[SIMULATOR],"configure_r31p23r21_single_pass_compact"))

    def test_exact_full_native_frame_validate_is_still_mandatory(self):
        enet=function(self.data[ENET],"send_to_peer")
        self.assertEqual(enet.count("FrameScript.validate(frame)"),1)
        self.assertIn('if not bool(check.get("success", false)):',enet)
        self.assertLess(enet.index("FrameScript.validate(frame)"),
                        enet.index("_r31p23r21_encode_after_frame_validate("))
        self.assertLess(enet.index("_logical_to_numeric.has(peer_id)"),
                        enet.index("_r31p23r21_encode_after_frame_validate("))
        self.assertLess(enet.index('"SESSION_MISMATCH"'),
                        enet.index("_r31p23r21_encode_after_frame_validate("))
        self.assertIn('and _mode == "SERVER"',enet)
        self.assertIn('== "COMPACT_GAMEPLAY_SNAPSHOT"',enet)
        self.assertIn('ChannelPolicyScript.SNAPSHOT',enet)
        self.assertIn('"UNRELIABLE_SEQUENCED"',enet)
        self.assertIn("encoded = FrameScript.encode(frame, MAX_PACKET_BYTES)",enet)
        self.assertIn("_peer.put_packet(",enet)
        self.assertNotIn("await",enet)
        self.assertNotIn("Thread.new",enet)

    def test_byte_canonical_function_mirrors_original_packet_size_errors(self):
        f=function(self.data[FRAME],"encode")
        fast=function(self.data[ENET],"_r31p23r21_encode_after_frame_validate")
        for token in (
            "NetworkUtilsScript.canonical_json(frame)",
            '"SERIALIZATION_FAILED"',
            'canonical_text.to_utf8_buffer()',
            'packet.size() > max_packet_bytes',
            '"PACKET_TOO_LARGE"',
            '"packet": packet',
            '"packet_bytes": packet.size()',
        ):
            self.assertIn(token,fast)
        for token in (
            "UtilsScript.canonical_json(value)",
            '"SERIALIZATION_FAILED"',
            'encoded.to_utf8_buffer()',
            "packet.size() > max_packet_bytes",
            '"PACKET_TOO_LARGE"',
            '"packet": packet',
            '"packet_bytes": packet.size()',
        ):
            self.assertIn(token,f)
        # A malformed frame must hit EXACT same original payload checksum
        # guard, which is NOT removed from FrameScript.validate.
        validate=function(self.data[FRAME],"validate")
        self.assertIn('UtilsScript.payload_hash(value["payload"])',validate)
        self.assertIn('"PAYLOAD_CHECKSUM_MISMATCH"',validate)
        self.assertIn("UtilsScript.canonicalize(value",validate)
        self.assertIn("TransportUtilsScript.is_canonical_transport_id(",validate)

    def test_simulator_reuses_exact_enet_encoded_bytes_only_on_local_path(self):
        sim=function(self.data[SIMULATOR],"send_to_peer")
        self.assertEqual(sim.count("FrameScript.validate(frame)"),1)
        self.assertIn("NetworkUtilsScript.canonical_json(frame).to_utf8_buffer().size()",sim)
        self.assertIn("if real_passthrough:",sim)
        self.assertIn("_has_active_manual_condition(OUTGOING)",sim)
        self.assertIn('"transport_kind", "")) == "ENET_MULTI_PEER"',sim)
        self.assertIn('== "COMPACT_GAMEPLAY_SNAPSHOT"',sim)
        self.assertIn('typeof(exact_bytes) != TYPE_INT',sim)
        self.assertIn('"R31P23R21_DELEGATE_PACKET_SIZE_MISSING"',sim)
        self.assertIn('packet_bytes = int(exact_bytes)',sim)
        self.assertIn("_with_simulator_details(direct, packet_bytes, false, false, _now_ms())",sim)
        self.assertIn('r21_reuse_encoded_size',sim)
        self.assertIn("if not bool(frame_check.get(\"success\", false)):",sim)
        self.assertNotIn("await",sim)

    def test_other_transport_messages_and_m6_are_untouched(self):
        enet=self.data[ENET]
        for field in ["_peer.transfer_channel = channel", "_peer.set_target_peer(",
                      "_peer.transfer_mode = transfer_mode", "_peer.put_packet("]:
            self.assertIn(field,enet)
        boundary=self.data[BOUNDARY]
        for token in ["commit_outgoing_sequence", "reserve_queue(", "release_queue(",
                      "_port.send_to_peer(", "flush_outbound("]:
            self.assertIn(token,boundary)
        self.assertIn("frozen_gameplay.duplicate(true)",self.data[M6])
        self.assertIn("replay_state.duplicate(true)",self.data[M6])
        self.assertNotIn("r31p23r21",self.data[M6])
        self.assertNotIn("r31p23r21",self.data[FRAME])
        self.assertIn("NX3_FIXED_TICK_RATE_HZ := 60",self.data[SERVER])
        self.assertIn("NX3_MOVEMENT_SNAPSHOT_INTERVAL_TICKS := 3",self.data[SERVER])


if __name__=="__main__":
    unittest.main()

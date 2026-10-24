"""NET-SMOOTH1 P2.3 R2.2 — fail-closed attestation source contracts.

Proof is private to native server ENet; it may never be supplied by client,
queue, disk, M6 replay, or remote caller. Original simulator frame validation
is mandatory and must precede the synchronous packet freeze. Never refactor
to asynchronous or defer the short validation-to-freeze interval.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
SERVER = ROOT / "scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd"
BOUNDARY = ROOT / "scripts/network/transports/v2/network_transport_boundary_v2.gd"
SIM = ROOT / "scripts/network/conditions/network_condition_simulator_port.gd"
ENET = ROOT / "scripts/network/transports/v2/enet_multi_peer_transport_port.gd"
FRAME = ROOT / "scripts/network/transports/v2/protocol_frame_v2.gd"
M6 = ROOT / "scripts/persistence/async_checkpoint_writer.gd"
RUNNER = ROOT / "tools/net_smooth1/run_net_smooth1.py"


def function(source, name):
    found = re.search(r"(?ms)^func " + re.escape(name) +
                      r"\(.*?(?=^func |\Z)", source)
    assert found is not None, name
    return found.group(0)


class R22Source(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = {path: path.read_text(encoding="utf-8") for path in (
            SERVER, BOUNDARY, SIM, ENET, FRAME, M6, RUNNER)}

    def test_server_only_opt_in_requires_r21(self):
        setup = function(self.data[SERVER], "setup")
        for token in (
            "DWS_NET_R31P23R22_ATTESTED_COMPACT",
            "R31P23R22_INVALID_MODE",
            "R31P23R22_REQUIRES_R21",
            "r31p23r22_attested_compact_canary",
            "_boundary.configure_r31p23r22_attested_compact(",
            "true, _authority_owner_id, _authority_epoch",
        ):
            self.assertIn(token, setup)
        self.assertIn("var _r31p23r22_attested_compact_enabled := false",
                      self.data[SERVER])
        runner = self.data[RUNNER]
        for token in ("--r31p23r22-attested-compact",
                      "if role == 'server' and args.r31p23r22_attested_compact:",
                      "DWS_NET_R31P23R22_ATTESTED_COMPACT",
                      "requires --r31p23r21-single-pass-compact"):
            self.assertIn(token, runner)

    def test_explicit_server_boundary_sim_enet_chain(self):
        for f in (BOUNDARY, SIM, ENET):
            self.assertIn("var _r31p23r22_attested_compact_enabled := false",
                          self.data[f])
            self.assertIn("func configure_r31p23r22_attested_compact(", self.data[f])
            self.assertIn("R31P23R22_REQUIRES_R21", self.data[f])
        self.assertIn("_port.configure_r31p23r22_attested_compact(",
                      function(self.data[BOUNDARY], "configure_r31p23r22_attested_compact"))
        self.assertIn("_delegate.configure_r31p23r22_attested_compact(",
                      function(self.data[SIM], "configure_r31p23r22_attested_compact"))

    def test_first_full_validator_remains_and_freeze_is_synchronous(self):
        sim = function(self.data[SIM], "send_to_peer")
        self.assertEqual(sim.count("FrameScript.validate(frame)"), 1)
        # Count only the original full simulator validator, never comments.
        check = sim.index("var frame_check: Dictionary = FrameScript.validate(frame)")
        frozen = sim.index("_delegate.r22_prepare_validated_compact(")
        self.assertLess(check, frozen)
        self.assertIn("if not bool(frame_check.get(\"success\", false)):", sim)
        between = sim[check:frozen]
        for forbidden in ("await ", "call_deferred(", "Thread.new(",
                          "frame[\"payload\"] =", "frame.duplicate("):
            self.assertNotIn(forbidden, between)
        self.assertIn("_delegate.r22_send_prepared(", sim)
        self.assertIn("and real_passthrough", sim)
        self.assertIn("_mode == \"SERVER\"", sim)
        self.assertIn('String(frame.get("channel", "")) == ChannelPolicyScript.SNAPSHOT', sim)
        self.assertIn('String(frame.get("delivery_mode", "")) == "UNRELIABLE_SEQUENCED"', sim)
        self.assertIn("_delegate.send_to_peer(peer_id, frame)", sim)  # original fallback

    def test_internal_one_use_live_identity_and_checksum_fences(self):
        prepare = function(self.data[ENET], "r22_prepare_validated_compact")
        consume = function(self.data[ENET], "_r22_take_attestation")
        send = function(self.data[ENET], "r22_send_prepared")
        for token in ("_r22_source_ref.get_ref()", "_logical_to_numeric.has(peer_id)",
                      "_session_by_peer.get(peer_id,", "_route_generation_by_peer.get(peer_id,",
                      "NetworkUtilsScript.canonical_json(frame)", "canonical_text.to_utf8_buffer()",
                      "canonical_text.sha256_text()", "source.get_instance_id()",
                      "get_instance_id()", '"payload_checksum": String(frame["payload_checksum"])',
                      '"authority_epoch": _r22_authority_epoch', '"sequence": int(frame["sequence"])'):
            self.assertIn(token, prepare)
        for token in ("_r22_pending = {}", "R31P23R22_PROOF_MISSING_OR_REPLAYED",
                      "R31P23R22_AUTHORITY_CHANGED", "R31P23R22_ROUTE_CHANGED",
                      '"SESSION_MISMATCH"', "PAYLOAD_CHECKSUM_MISMATCH",
                      'packet.get_string_from_utf8().sha256_text()', "TransportUtilsScript.success"):
            self.assertIn(token, consume)
        self.assertIn("_r22_take_attestation(source, peer_id, ticket)", send)
        self.assertIn("_peer.put_packet(packet)", send)
        self.assertNotIn("FrameScript.validate(frame)", send)
        for content in (prepare, consume, send):
            self.assertNotIn("await ", content)
            self.assertNotIn("Thread.new(", content)

    def test_r21_legacy_validator_and_m6_untouched(self):
        legacy = function(self.data[ENET], "send_to_peer")
        self.assertEqual(legacy.count("FrameScript.validate(frame)"), 1)
        self.assertIn("encoded = FrameScript.encode(frame, MAX_PACKET_BYTES)", legacy)
        self.assertIn("_peer.put_packet(", legacy)
        self.assertIn("PAYLOAD_CHECKSUM_MISMATCH", function(self.data[FRAME], "validate"))
        self.assertNotIn("r31p23r22", self.data[FRAME])
        self.assertNotIn("r31p23r22", self.data[M6])
        self.assertIn("commit_outgoing_sequence", self.data[BOUNDARY])
        self.assertIn("_port.send_to_peer(queued_peer_id, dispatch_frame)", self.data[BOUNDARY])


if __name__ == "__main__":
    unittest.main()

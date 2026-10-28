"""#815: ensure session-bound negotiation changes ONLY opt-in COMPACT.

No false performance, handshake, safety or historic-incident acceptance.
"""
from pathlib import Path
import ast
import sys
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/"tools/net_smooth1"))
import verify_815_real_chain_report as source_fingerprint

POLICY=(ROOT/"scripts/network/contracts/r31_815_compact_codec_negotiation.gd").read_text()
SERVER=(ROOT/"scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd").read_text()
CLIENT=(ROOT/"scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_p2.gd").read_text()
BASE=(ROOT/"scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_nx6.gd").read_text()
RUNNER=(ROOT/"tools/net_smooth1/run_net_smooth1.py").read_text()
CODEC=(ROOT/"scripts/runtime/networked_gameplay/contracts/compact_gameplay_snapshot_v2.gd").read_text()


class LiveF64Source(unittest.TestCase):
    def test_original_full_v1_frame_and_checksum_files_identical_to_verified_red(self):
        source_fingerprint.check_source(ROOT)

    def test_original_compatibility_handshake_not_weakened(self):
        hs=(ROOT/"scripts/network/observability/network_compatibility_handshake.gd").read_text()
        self.assertIn("FingerprintScript.compare(",hs)
        self.assertIn("validate_client_ack(",hs)
        self.assertIn('"HELLO_CHECKSUM_MISMATCH"',hs)
        self.assertIn('"ACK_CHECKSUM_MISMATCH"',hs)
        self.assertIn('CompatibilityHandshake.evaluate_server(',SERVER)
        self.assertIn('CompatibilityHandshake.validate_client_ack(',CLIENT)

    def test_server_choice_is_authenticated_before_ack_and_bound_to_transport_session(self):
        method=SERVER[SERVER.index("func _handle_compatibility_hello("):
                      SERVER.index("func _r31_815_peer_codec(")]
        for needed in ("R31CodecPolicy.choose(", "R31CodecPolicy.create_choice(",
                       "COMPACT_CODEC_RENEGOTIATION_FORBIDDEN",
                       '"compact_codec_format": selected_format'):
            self.assertIn(needed,method)
        self.assertLess(method.index("R31CodecPolicy.choose("),
                        method.index('"COMPATIBILITY_ACK", ack_payload'))
        self.assertLess(method.index('"COMPATIBILITY_ACK", ack_payload'),
                        method.index('"compact_codec_format": selected_format'))
        peer=SERVER[SERVER.index("func _r31_815_peer_codec("):
                    SERVER.index("func _reject_handshake(")]
        self.assertIn('row.get("session_id", "")',peer)
        self.assertIn('_peer_to_session.get(peer_id',peer)
        self.assertIn('return ""',peer)
        self.assertIn('_peer_compatibility.erase(peer_id)',SERVER)

    def test_real_server_both_codecs_are_selected_per_peer_without_downgrade(self):
        self.assertIn('CompactV2.encode(authoritative_snapshot)',SERVER)
        self.assertIn('selected_codec: String = _r31_815_peer_codec(peer_id)',SERVER)
        self.assertIn('selected_codec == R31CodecPolicy.F64',SERVER)
        self.assertIn('compact_snapshot_v2 if selected_codec == R31CodecPolicy.F64',SERVER)
        self.assertIn('continue  # stale session, never an unnegotiated format fallback',SERVER)
        self.assertIn('return  # NO implicit v1 downgrade',SERVER)
        self.assertIn('R31_815_CODEC_REQUIRES_PLAYABLE_PRODUCT_SEAM',SERVER)
        self.assertIn('_r31_815_v2_sent += 1',SERVER)
        self.assertIn('var need_v1: bool = _r31_815_compact_mode == "off"',SERVER)
        self.assertIn('var need_v2: bool = false',SERVER)
        self.assertIn('if need_v1:',SERVER)
        self.assertIn('if need_v2:',SERVER)
        self.assertIn('CompactGameplaySnapshot.encode(authoritative_snapshot)',SERVER)
        self.assertIn('CompactV2.encode(authoritative_snapshot)',SERVER)
        self.assertIn('_r31_815_v1_encodes += 1',SERVER)
        self.assertIn('_r31_815_v2_encodes += 1',SERVER)
        self.assertIn('compact_snapshot_v2 if selected_codec == R31CodecPolicy.F64',SERVER)
        self.assertIn('"compact_codec_offer_checksum": String(offer.get("checksum", ""))',SERVER)
        self.assertIn('existing.get("compact_codec_offer_checksum", "")',SERVER)
        self.assertIn('r31_815_compact_v2_sent',SERVER)
        self.assertIn('DWS_NET_815_COMPACT_SERVER_MODE',SERVER)

    def test_client_uses_one_virtual_decoder_for_normal_and_committed_view(self):
        self.assertIn('return CompactGameplaySnapshot.decode(snapshot)',BASE)
        self.assertEqual(BASE.count('_decode_compact_snapshot(snapshot)'),1)
        self.assertEqual(BASE.count('_decode_compact_snapshot(wire)'),1)
        self.assertIn('COMPACT_CODEC_VERSION_MISMATCH',CLIENT)
        self.assertIn('COMPACT_CODEC_SESSION_NOT_NEGOTIATED',CLIENT)
        self.assertIn('return super._decode_compact_snapshot(wire)',CLIENT)
        self.assertIn('CompactCodecV2.decode(wire)',CLIENT)
        self.assertIn('r31_815_compact_v2_received',CLIENT)
        self.assertIn('R31CodecPolicy.client_accept(',CLIENT)
        self.assertIn('COMPACT_CODEC_RENEGOTIATION_FORBIDDEN',CLIENT)
        self.assertIn('if _handshake_verified:',CLIENT)
        self.assertIn('_r31_815_bound_session != _transport_session_id',CLIENT)
        self.assertIn('_r31_815_bound_handshake != _handshake_id',CLIENT)
        self.assertIn('_r31_815_selected != selected',CLIENT)

    def test_default_off_exact_and_full_join_m6_unmodified(self):
        self.assertIn('var _r31_815_compact_mode: String = "off"',SERVER)
        self.assertIn('var _r31_815_client_mode: String = "off"',CLIENT)
        self.assertIn('return super._send_control(message_type, data)',CLIENT)
        self.assertIn('return super._decode_compact_snapshot(wire)',CLIENT)
        self.assertIn('_broadcast_snapshot(',SERVER)
        self.assertIn('"GAMEPLAY_SNAPSHOT"',SERVER)
        self.assertIn('M6PendingDurableAckGate',SERVER)
        self.assertIn('M6ReplayOutbox',SERVER)
        self.assertIn('"server_tick": _server_tick',SERVER)
        self.assertNotIn('Engine.max_fps',CLIENT)

    def test_runner_modes_are_explicit_roles_not_inherited_from_shell(self):
        for phrase in (
            "r31_815_compact_server_mode=args.r31_815_compact_server_mode",
            "r31_815_compact_client_a_mode=args.r31_815_compact_client_a_mode",
            "r31_815_compact_client_b_mode=args.r31_815_compact_client_b_mode",
            "env.pop('DWS_NET_815_COMPACT_SERVER_MODE', None)",
            "env.pop('DWS_NET_815_COMPACT_CLIENT_MODE', None)",
            "role == 'server' and args.r31_815_compact_server_mode != 'off'",
            "role == 'a' and args.r31_815_compact_client_a_mode != 'off'",
            "role == 'b' and args.r31_815_compact_client_b_mode != 'off'",
            "F64-v2 test deployment requires real LOCAL two-client reconnect scenario",
        ):
            self.assertIn(phrase,RUNNER)
        ast.parse(RUNNER)

    def test_binary64_is_lossless_and_no_checksum_waiver(self):
        for phrase in ('IEEE754_BINARY64_LE_HEX_V1','FullSnapshot.validate(snapshot)',
                       '"c": source["checksum"]','_pack64(number) != text'):
            self.assertIn(phrase,CODEC)
        self.assertNotIn("F64_PROTOCOL_CHECKSUM_WAIVER",CODEC)
        self.assertNotIn("ROUND_FLOAT_FOR_CHECKSUM",CODEC)
        self.assertIn("COMPACT_CODEC_DOWNGRADE_FORBIDDEN",POLICY)
        self.assertIn("COMPACT_CODEC_RENEGOTIATION_FORBIDDEN",SERVER)

if __name__=="__main__":
    unittest.main()

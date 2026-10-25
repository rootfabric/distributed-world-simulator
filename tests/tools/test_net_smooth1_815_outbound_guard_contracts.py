"""Fail-closed R31 #815 outbound guard source/API invariants.

R1 guard must never bypass the original receiver's strict checksum/canonical
validator; only a server-only explicit opt-in can prevent an invalid packet
from reaching the real ENet put_packet. No tolerance, rounding, or wire edits.
"""
from pathlib import Path
import ast
import unittest

ROOT=Path(__file__).resolve().parents[2]
ENET=(ROOT/"scripts/network/transports/v2/enet_multi_peer_transport_port.gd").read_text(encoding="utf-8")
PROTO=(ROOT/"scripts/network/transports/v2/protocol_frame_v2.gd").read_text(encoding="utf-8")
RUN=(ROOT/"tools/net_smooth1/run_net_smooth1.py").read_text(encoding="utf-8")
NATIVE=(ROOT/"tests/runtime/test_net_smooth1_r31_815_outbound_decode_guard.gd").read_text(encoding="utf-8")
SIM=(ROOT/"scripts/network/conditions/network_condition_simulator_port.gd").read_text(encoding="utf-8")
BOUND=(ROOT/"scripts/network/transports/v2/network_transport_boundary_v2.gd").read_text(encoding="utf-8")


def body(source,name):
    idx=source.index(f"func {name}(")
    stop=source.find("\nfunc ",idx+1)
    return source[idx:stop if stop!=-1 else None]


class OutboundGuardContracts(unittest.TestCase):
    def test_exact_original_decoder_decides_no_weaker_validation(self):
        guard=body(ENET,"_r31_815_preflight")
        self.assertIn("FrameScript.decode(packet, MAX_PACKET_BYTES)",guard)
        self.assertIn('OS.get_environment(R31_815_OUTBOUND_GUARD_ENV) != "1"',guard)
        self.assertIn('_mode != "SERVER"',guard)
        self.assertIn('R31_815_OUTBOUND_RECEIVER_REJECTED',guard)
        self.assertIn('"decoder_error_code": decoder_code',guard)
        self.assertNotIn('put_packet(',guard)
        self.assertNotIn('packet[',guard)
        self.assertNotIn("FrameScript.validate(",guard)
        self.assertNotIn("decoded[\"details\"]",guard)

    def test_exact_preflight_is_before_both_native_packet_sends(self):
        r22=body(ENET,"r22_prepare_validated_compact")
        self.assertLess(r22.index("_r31_815_preflight(packet, frame)"),
                        r22.index("_r22_ticket_counter += 1"))
        regular=body(ENET,"send_to_peer")
        self.assertLess(regular.index("_r31_815_preflight("),
                        regular.index("_peer.put_packet("))
        self.assertIn("FrameScript.validate(frame)",regular)
        self.assertIn("FrameScript.encode(frame",regular)
        r22send=body(ENET,"r22_send_prepared")
        self.assertIn("proof_result: Dictionary = _r22_take_attestation(",r22send)
        self.assertIn("_peer.put_packet(packet)",r22send)
        self.assertIn("_r31_815_original_payload_sha256",ENET)

    def test_guard_only_server_environment_and_non_normative(self):
        self.assertIn("env.pop('DWS_NET_R31_815_OUTBOUND_DECODE_GUARD', None)",RUN)
        self.assertIn("if role == 'server' and args.r31_815_outbound_guard:",RUN)
        self.assertIn("env['DWS_NET_R31_815_OUTBOUND_DECODE_GUARD']='1'",RUN)
        self.assertIn("--r31-815-outbound-guard",RUN)
        self.assertIn("args.r31_815_outbound_guard and not args.r31_815_wire_forensics",RUN)
        self.assertIn("r31_815_outbound_guard=args.r31_815_outbound_guard",RUN)
        self.assertIn("CHECKSUM_FINGERPRINT_DIAGNOSTIC_ONLY",RUN)
        ast.parse(RUN)

    def test_original_verification_and_retry_semantics_unmodified(self):
        self.assertIn('UtilsScript.validation_failure("PAYLOAD_CHECKSUM_MISMATCH"',PROTO)
        self.assertIn("if UtilsScript.canonical_json(parsed) != text:",PROTO)
        self.assertIn("FrameScript.decode(packet, MAX_PACKET_BYTES)",ENET)
        self.assertIn("if not bool(result.get(\"success\", false)) and bool(item.get(\"reliable\", false)):",SIM)
        self.assertIn("network_simulator_unreliable_delegate_send_drops",SIM)
        self.assertIn("blocked_streams[blocked_key] = true",BOUND)
        self.assertIn("pending_messages",BOUND)

    def test_real_red_green_native_falsifier_checks(self):
        for code in (
            "R31_815_OUTBOUND_RECEIVER_REJECTED",
            "Frame.validate(known_unstable)",
            "Frame.decode(packet)",
            "default OFF does not change original",
            "R2.2 frozen one-use proof DENIED",
            "legacy send path refuses",
            "receiver unmodified strict checksum",
            "one-byte corruption",
        ):
            self.assertIn(code,NATIVE)

    def test_no_false_perf_or_historical_issue_closure(self):
        self.assertNotIn("PAYLOAD_CHECKSUM_MISMATCH_IGNORED",ENET)
        self.assertNotIn("set_profile('OFF')",ENET)
        self.assertNotIn("R31_815_OUTBOUND_FIXED",ENET)
        self.assertNotIn("READY_FOR_MERGE=true",RUN)


if __name__=="__main__":
    unittest.main()

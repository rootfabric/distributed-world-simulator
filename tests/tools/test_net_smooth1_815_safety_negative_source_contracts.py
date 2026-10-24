"""SAFETY-815 — deterministic negative safety source contracts (issues #809/#823/#815).

The Godot runtime run is DEFERRED (host contended by a performance campaign),
so these tests statically pin the new negative falsifier
``tests/runtime/test_net_smooth1_815_safety_negative.gd``:

1. every one of the six report-specified negative tests exists and asserts the
   EXACT fail-closed error code (PAYLOAD_CHECKSUM_MISMATCH,
   COMPACT_GAMEPLAY_SNAPSHOT_CHECKSUM_MISMATCH, SESSION_MISMATCH,
   STALE_TRANSPORT_SESSION, R31P23R22_AUTHORITY_CHANGED /
   R31P23R22_ROUTE_CHANGED) using the project check()/result-JSON pattern;
2. a Python reference of the canonicalization contract
   (``network_contract_utils.gd`` canonicalize + ``JSON.stringify(..., "",
   true, true)``: integral floats collapse to integers, keys sorted, compact
   separators, shortest round-trip float text) proves byte-identity of a
   fixed vector of JOIN/snapshot frames across two INDEPENDENT Python
   encoders and across an encode->parse->encode roundtrip. The GDScript
   encoder side of the same vector runs inside the deferred Godot test.
"""
from hashlib import sha256
from json import dumps
from math import isfinite
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
GD = ROOT / "tests/runtime/test_net_smooth1_815_safety_negative.gd"

TESTS = {
    "_join_bit_corruption": [
        "PAYLOAD_CHECKSUM_MISMATCH",
        "Frame.decode(",
        "^ 0x01",
        "send_to_peer(",
    ],
    "_permutation_unharmed": [
        '"reorder_percent": 100.0',
        '"duplicate_percent": 100.0',
        '"jitter_ms": 4',
        "advance_time_ms(",
        "PAYLOAD_CHECKSUM_MISMATCH",
    ],
    "_session_cross_delivery": [
        '== "SESSION_MISMATCH"',
        '== "STALE_TRANSPORT_SESSION"',
        "disconnect_peer(",
        "_register_peer",
    ],
    "_authority_epoch_fences": [
        '== "R31P23R22_AUTHORITY_CHANGED"',
        '== "R31P23R22_ROUTE_CHANGED"',
        '== "SESSION_MISMATCH"',
        '== "R31P23R22_PROOF_MISSING_OR_REPLAYED"',
        "== \"PAYLOAD_CHECKSUM_MISMATCH\"",
    ],
    "_compact_nested_checksum": [
        '==\n\t\t\t"COMPACT_GAMEPLAY_SNAPSHOT_CHECKSUM_MISMATCH"',
        "Compact.validate(",
        "Compact.decode(",
        "payload_hash(",
    ],
    "_canonical_roundtrip_identity": [
        "Wire.canonical_json(frame.duplicate(true))",
        "JSON.parse_string(",
        "byte identity",
        "payload_hash(",
    ],
}


def function(source, name):
    found = re.search(r"(?ms)^func " + re.escape(name) +
                      r"\(.*?(?=^func |\Z)", source)
    assert found is not None, name
    return found.group(0)


def canonicalize(value):
    """Mirror of network_contract_utils.gd canonicalize()."""
    if value is None or isinstance(value, bool) or isinstance(value, str):
        return value
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        if not isfinite(value):
            raise ValueError("non-finite")
        return int(value) if value == int(value) else value
    if isinstance(value, list):
        return [canonicalize(item) for item in value]
    if isinstance(value, dict):
        if not all(isinstance(key, str) for key in value):
            raise ValueError("non-string key")
        return {key: canonicalize(value[key]) for key in value}
    raise ValueError("forbidden value")


def canonical_json_a(value):
    """Encoder A: stdlib json, sorted keys, compact separators."""
    return dumps(canonicalize(value), sort_keys=True,
                 separators=(",", ":"), ensure_ascii=False,
                 allow_nan=False)


def canonical_json_b(value):
    """Encoder B: independent hand-written serializer, same contract."""
    normalized = canonicalize(value)

    def encode(node):
        if node is None:
            return "null"
        if node is True:
            return "true"
        if node is False:
            return "false"
        if isinstance(node, int):
            return str(node)
        if isinstance(node, float):
            return repr(node)
        if isinstance(node, str):
            return dumps(node, ensure_ascii=False)
        if isinstance(node, list):
            return "[" + ",".join(encode(item) for item in node) + "]"
        if isinstance(node, dict):
            return "{" + ",".join(
                dumps(key, ensure_ascii=False) + ":" + encode(node[key])
                for key in sorted(node)) + "}"
        raise ValueError("forbidden value")

    return encode(normalized)


def payload_hash(value):
    return sha256(canonical_json_a(value).encode("utf-8")).hexdigest()


def player(player_id, x, z, velocity, yaw, epoch):
    return {
        "logical_player_id": player_id,
        "player_entity_id": "player/" + player_id,
        "transport_session_id": "transport-session/%s/%d" % (player_id, epoch),
        "ownership_epoch": epoch, "connected": True,
        "position": {"x": x, "y": 0.0, "z": z},
        "velocity": {"x": velocity, "y": 0.0, "z": -velocity / 11.0},
        "inventory": [], "last_input_sequence": 12, "state_revision": 22,
        "orientation_yaw": yaw, "flashlight_enabled": False,
    }


def sample(revision, server_tick):
    return {
        "schema": "planet_simulator.player_state_snapshot.v1",
        "authority_owner_id": "simulation/m3/dedicated",
        "authority_epoch": 1, "revision": revision,
        "server_tick": server_tick, "region_id": "region/user1/a",
        "players": [player("a", 5.5, 2.5, 0.25, 1.5, 1)],
        "shared_item": {"item_id": "item/shared/beacon/1",
                        "available": True,
                        "owner_player_entity_id": "", "revision": revision},
        "checksum": payload_hash({"kept": "full-checksum-placeholder"}),
    }


def frame(frame_id, session, sequence, channel, delivery, payload):
    return {
        "schema": "planet_simulator.protocol_frame.v2",
        "protocol_version": 2, "frame_id": frame_id,
        "session_id": session, "sequence": sequence,
        "channel": channel, "delivery_mode": delivery,
        "payload_schema":
            "planet_simulator.m3.graphical_multiplayer_message.v1",
        "payload": payload,
        "payload_checksum": payload_hash(payload),
    }


def fixed_vector():
    join_payload = {
        "type": "JOIN_ACK", "reason": "JOIN_COMPLETE_815_SENTINEL",
        "player": player("a", 1.5, 2.5, 0.25, 1.5, 1),
        "snapshot": sample(4, 3),
        "item_graph_snapshot": {"revision": 1, "entries": []},
        "server_sent_at_ms": 1234,
    }
    compact_payload = {
        "type": "COMPACT_GAMEPLAY_SNAPSHOT",
        "reason": "MOVEMENT_NETWORK_TICK", "server_sent_at_ms": 1003.0,
        "snapshot": sample(6, 3),
    }
    return [
        frame("frame/815/join/1", "transport-session/815/a/1", 1,
              "RESYNC", "RELIABLE_ORDERED", join_payload),
        frame("frame/815/snap/3", "transport-session/815/a/1", 3,
              "SNAPSHOT", "UNRELIABLE_SEQUENCED", compact_payload),
    ]


class Safety815Source(unittest.TestCase):
    def setUp(self):
        self.source = GD.read_text(encoding="utf-8")

    def test_file_exists_and_follows_check_pattern(self):
        self.assertIn("extends SceneTree", self.source)
        self.assertIn("var checks := 0", self.source)
        self.assertIn("var failures: Array[String] = []", self.source)
        self.assertIn("func check(ok: bool, label: String) -> void:",
                      self.source)
        self.assertIn('push_error("NET_SMOOTH_815_SAFETY_NEGATIVE_FAIL:"',
                      self.source)
        self.assertIn('"PASS" if failures.is_empty() else "FAIL"',
                      self.source)
        self.assertIn("quit(0 if failures.is_empty() else 1)", self.source)
        for name in TESTS:
            self.assertIn("func %s() -> void:" % name, self.source)
            self.assertIn("\t%s()" % name, self.source)

    def test_no_real_enet_sockets_or_gui_required(self):
        for forbidden in ("ENetMultiplayerPeer.create_client",
                          "ENetMultiplayerPeer.create_server",
                          "DisplayServer", "accept_quit"):
            self.assertNotIn(forbidden, self.source)
        # Only a detached placeholder peer is installed, mirroring the
        # attested-compact test's private-field stub pattern.
        self.assertIn('enet.set("_peer", ENetMultiplayerPeer.new())',
                      self.source)

    def test_each_negative_test_pins_its_exact_error_code(self):
        for name, tokens in TESTS.items():
            body = function(self.source, name)
            for token in tokens:
                self.assertIn(token, body, "%s: %s" % (name, token))

    def test_deferred_godot_run_is_documented_in_header(self):
        self.assertIn("DEFERRED", self.source)
        self.assertIn("tests/tools/"
                      "test_net_smooth1_815_safety_negative_source_contracts.py",
                      self.source)

    def test_canonical_vector_is_byte_identical_across_two_encoders(self):
        for index, value in enumerate(fixed_vector()):
            text_a = canonical_json_a(value)
            text_b = canonical_json_b(value)
            self.assertEqual(text_a, text_b,
                             "encoder divergence on vector %d" % index)
            reparsed = loads_json(text_a)
            self.assertEqual(canonical_json_a(reparsed), text_a,
                             "roundtrip divergence on vector %d" % index)
            self.assertEqual(
                payload_hash(reparsed["payload"]),
                value["payload_checksum"],
                "payload hash not stable across roundtrip on vector %d" % index)

    def test_key_order_and_scalar_typing_cannot_change_canonical_bytes(self):
        value = fixed_vector()[0]
        reordered = dict(reversed(list(value.items())))
        self.assertEqual(canonical_json_a(value), canonical_json_a(reordered))
        float_typed = {key: (float(item) if key == "sequence" else item)
                       for key, item in value.items()}
        self.assertEqual(canonical_json_a(value), canonical_json_a(float_typed))


def loads_json(text):
    from json import loads
    return loads(text)


if __name__ == "__main__":
    unittest.main()

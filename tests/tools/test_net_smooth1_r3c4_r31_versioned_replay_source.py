"""R3.1a fail-closed source contracts: every replay ledger writer bumps fence."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
M4 = ROOT / "scripts/runtime/networked_gameplay/m4"
SERVICE = ROOT / "scripts/runtime/networked_gameplay"
P2 = SERVICE / "networked_gameplay_service_p2.gd"
SHELL = SERVICE / "networked_gameplay_service.gd"
USER1 = SERVICE / "user1/user1_product_seam_gameplay_service.gd"
OWN = SERVICE / "services/player_ownership_service.gd"
MINING = SERVICE / "p3/resource_mining_service.gd"
M4_BASE = M4 / "canonical_multiplayer_item_graph_service_base.gd"
M4_ROOT = M4 / "canonical_multiplayer_item_graph_service.gd"
OUTBOX = SERVICE / "m6/m6_durable_replay_outbox_p2.gd"
SERVER = SERVICE / "m3/m3_dedicated_server_runtime_p2.gd"
RUN = ROOT / "tools/net_smooth1/run_net_smooth1.py"


def func(src: str, name: str) -> str:
    match = re.search(r"(?m)^func " + re.escape(name) + r"\(.*?(?=^func |\Z)", src, re.S)
    if match is None:
        raise AssertionError("missing function " + name)
    return match.group()


class R31ImmutableReplayContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sources = {p: p.read_text(encoding="utf-8") for p in (
            P2, SHELL, USER1, OWN, MINING, M4_BASE, M4_ROOT, OUTBOX, SERVER, RUN,
            M4 / "canonical_multiplayer_item_graph_service_p3.gd",
            M4 / "canonical_multiplayer_item_graph_service_p4.gd")}

    def get(self, path):
        return self.sources[path]

    def test_owner_source_fence_all_domains_including_seam(self):
        root = func(self.get(SHELL), "get_r31_replay_source_fence")
        for term in ("get_service_replay_projection_generation()",
                     "_ownership.get_replay_projection_generation()",
                     "_canonical_multiplayer_items.get_replay_projection_generation()",
                     "_resource_mining.get_replay_projection_generation()",
                     "_authority_owner_id", "_authority_epoch"):
            self.assertIn(term, root)
        seam = func(self.get(USER1), "get_r31_replay_source_fence")
        self.assertIn("super.get_r31_replay_source_fence()", seam)
        self.assertIn("_seam_transfers_quiescent()", seam)
        self.assertIn("_transfer_serial", seam)

    def test_ledger_writer_mutations_versioned(self):
        pairs = [
            (OWN, "_record", "_replay_projection_generation += 1"),
            (MINING, "_record_result", "_replay_projection_generation += 1"),
            (P2, "_record", "_replay_projection_generation += 1"),
            (P2, "handle_live_player_input", "_replay_projection_generation += 1"),
            (P2, "install_live_player_replay", "_replay_projection_generation += 1"),
            (M4_BASE, "execute", "_replay_projection_generation += 1"),
            (M4_ROOT, "_tag_live_replay6", "_note_replay_projection_mutation()"),
            (M4_ROOT, "retire_live_item_carry", "_note_replay_projection_mutation()"),
            (M4_ROOT, "install_live_item_carry", "_note_replay_projection_mutation()"),
            (M4 / "canonical_multiplayer_item_graph_service_p3.gd",
             "apply_server_output", "_note_replay_projection_mutation()"),
            (M4 / "canonical_multiplayer_item_graph_service_p4.gd",
             "apply_server_construction_consume", "_note_replay_projection_mutation()"),
        ]
        for path, method, mark in pairs:
            with self.subTest(path=path.name, method=method):
                self.assertIn(mark, func(self.get(path), method))
        for path in (OWN, MINING, P2, M4_BASE):
            body = self.get(path)
            self.assertIn("get_replay_projection_generation", body)
            if path is not P2:
                self.assertIn("_replay_projection_generation", body)

    def test_replay_load_restore_bumps_generation(self):
        for path in (OWN, MINING, P2, M4_BASE):
            self.assertIn("_replay_projection_generation += 1", func(self.get(path),
                "restore_replay_state") if path != M4_BASE else
                func(self.get(path), "restore_replay_state").replace(
                    "_note_replay_projection_mutation()", "_replay_projection_generation += 1"))
        self.assertIn("_r31_invalidate_projection()", func(self.get(OUTBOX), "load_dict"))

    def test_cache_bounded_and_immutable(self):
        cache = func(self.get(OUTBOX), "to_dict_r31_versioned")
        for token in ("get_r31_replay_source_fence()", "_r31_cache_fence == source_fence",
                      "_r31_cache_outbox_version == _r31_outbox_version",
                      "_r31_cache_value.duplicate(true)",
                      "R31_CACHE_MAX_OUTBOX_RECORDS", "R31_CACHE_MAX_BYTES",
                      "source_fence.duplicate(true)", "to_dict()",
                      "SOURCE_FENCE_CHANGED"):
            self.assertIn(token, cache)
        canonical = func(self.get(OUTBOX), "to_dict")
        self.assertIn('Utils.finalize_json_checksum(value)', canonical)
        self.assertIn('"_records"', canonical.replace("committed_outbox", "_records"))
        for method in ("setup", "stage_committed", "mark_delivered", "mark_delivery_attempt", "load_dict"):
            self.assertIn("_r31_invalidate_projection()", func(self.get(OUTBOX), method))

    def test_only_periodic_uses_cache(self):
        server = self.get(SERVER)
        capture = func(server, "_submit_async_movement_checkpoint")
        self.assertIn("_replay_outbox.to_dict_r31_versioned()", capture)
        self.assertIn("_replay_outbox.to_dict()", capture)
        self.assertEqual(server.count("to_dict_r31_versioned()"), 1)
        self.assertIn("R3C4_R31_REQUIRES_R2_WORKER_ENVELOPE", func(server, "setup"))
        self.assertIn("R3C4_R31_R30_ATTRIBUTION_MODE_CONFLICT", func(server, "setup"))
        self.assertIn("DWS_NET_R3C4_R31_REPLAY_PROJECTION", func(server, "setup"))
        self.assertIn("r31_cache_hit", capture)
        self.assertIn("r31_cache_bypassed", capture)

    def test_gui_switch_server_only(self):
        h = self.get(RUN)
        self.assertIn("r3c4r31_replay_projection=args.r3c4r31_replay_projection", h)
        self.assertIn("if role == 'server' and args.r3c4r31_replay_projection:", h)
        self.assertIn("R3C4 R3.1 replay projection requires --r3c4r2-worker-envelope", h)


if __name__ == "__main__":
    unittest.main()
